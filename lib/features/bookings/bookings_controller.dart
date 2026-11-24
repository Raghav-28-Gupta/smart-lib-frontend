// lib/features/bookings/bookings_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_exception.dart';
import '../../models/resource_booking.dart';
import '../auth/auth_controller.dart';
import 'booking_repository.dart';

class BookingsController extends AsyncNotifier<List<ResourceBooking>> {
  // Bumped by every build(). This notifier outlives a rebuild (a different student
  // logging in), so a quiet refresh begun for the last student must neither land in
  // the next student's state nor be joined by their `refreshQuietly`: the list now
  // carries each student's own report state (`canReport`, `reportOpen`).
  int _generation = 0;

  @override
  Future<List<ResourceBooking>> build() {
    _generation++;
    _refreshing = null;
    // Outlives a logout, so keyed on who is logged in -- a different user
    // means a fresh fetch, never the previous user's bookings.
    ref.watch(authControllerProvider.select((s) => s.user?.id));
    // Started and cancel-registered before any await, so each build owns
    // exactly one timer -- a build superseded mid-fetch can't leak one.
    final timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    ref.onDispose(timer.cancel);
    return ref.read(bookingRepositoryProvider).myBookings();
  }

  // Recomputes every booking's status from its start time each second, so an
  // upcoming booking opens for check-in on time and an unclaimed one releases
  // -- without refetching.
  void _tick() {
    // Not while (re)loading: that would replace the pending fetch with the
    // previous list. Nor on an error, which Riverpod shows beside the last
    // student's list: it must stay an error, not turn back into that list.
    if (state.isLoading || state.hasError || !state.hasValue) return;
    final current = state.requireValue;
    final now = DateTime.now();
    state = AsyncValue.data([for (final b in current) b.advancedTo(now)]);
  }

  // A check-in or a cancel is a write the student waits for. If a different student has
  // logged in by the time it answers ([generation] was taken before the request), its
  // answer is the last student's: Riverpod still holds their list on the next student's
  // loading state, so writing it back would show their bookings, with their report
  // buttons (`canReport`, `reportOpen`), until the next student's own fetch lands. The
  // caller still hears of a refusal, but it no longer reloads a list that is not theirs.

  Future<void> checkIn(String id) async {
    final generation = _generation;
    final ResourceBooking updated;
    try {
      updated = await ref.read(bookingRepositoryProvider).checkIn(id);
    } on ApiException catch (e) {
      if (generation == _generation) _refetchIfStale(e);
      rethrow;
    }
    if (generation != _generation) return;
    final current = state.value ?? [];
    state = AsyncValue.data([for (final b in current) if (b.id == id) updated else b]);
  }

  Future<void> cancel(String id) async {
    final generation = _generation;
    try {
      await ref.read(bookingRepositoryProvider).cancelBooking(id);
    } on ApiException catch (e) {
      if (generation == _generation) _refetchIfStale(e);
      rethrow;
    }
    if (generation != _generation) return;
    final current = state.value ?? [];
    state = AsyncValue.data(current.where((b) => b.id != id).toList());
  }

  /// Reports a problem with the seat or room of [b] (`POST /reports`), then reads the
  /// bookings again so the card says "Reported" from the server's own answer. A refusal
  /// is rethrown for the caller to show. A 409 (already reported, perhaps from another
  /// device), 404 or 403 (the booking no longer entitles the student to report it) means
  /// the picture was out of date, so the list is re-read then too; a network error
  /// leaves it as it is.
  Future<void> reportProblem(ResourceBooking b, ResourceReportCategory category, String? note) async {
    final generation = _generation;
    try {
      await ref.read(bookingRepositoryProvider).reportResource(b.resourceId, category, note);
    } on ApiException catch (e) {
      if (e.meansStaleState || e.statusCode == 403) await _readAfterWrite(generation);
      rethrow;
    }
    await _readAfterWrite(generation, reportedResourceId: b.resourceId);
  }

  /// Brings the list up to date after a write. A fetch already in flight was begun
  /// before the write, so it may answer without it: it is waited for first, so that its
  /// answer cannot land after, and the list is read again. When the write was a report
  /// that went through, every booking on that resource is marked reported at once, as
  /// the server answers for it, so the card says so even if the re-read fails. Nothing
  /// is done once a different student has logged in since the write began ([generation]):
  /// the list is theirs by then.
  Future<void> _readAfterWrite(int generation, {String? reportedResourceId}) async {
    final inFlight = _refreshing;
    if (inFlight != null) await inFlight;
    if (generation != _generation) return;
    if (reportedResourceId != null) {
      final current = state.value;
      if (current != null && !state.hasError && !state.isLoading) {
        state = AsyncValue.data([
          for (final b in current)
            b.resourceId == reportedResourceId ? b.copyWith(reportOpen: true, canReport: false) : b,
        ]);
      }
    }
    await refreshQuietly();
  }

  Future<void>? _refreshing;

  /// The re-check when My Bookings opens and every 30 seconds while a room
  /// request waits: shows what the server says now, and keeps the list if the
  /// request fails. A call made while another is in flight joins it, so a screen
  /// that opens with a request pending (which asks twice, once for the open and
  /// once for the request) fetches once -- unless that one was begun for a
  /// student who has since logged out.
  Future<void> refreshQuietly() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final generation = _generation;
    return _refreshing = _refresh(generation).whenComplete(() {
      // After a rebuild `_refreshing` is the next student's (or null): not ours to clear.
      if (generation == _generation) _refreshing = null;
    });
  }

  Future<void> _refresh(int generation) async {
    try {
      final fresh = await ref.read(bookingRepositoryProvider).myBookings();
      // The answer to the previous student's request, arriving after the next one
      // logged in: theirs, so it is dropped.
      if (generation == _generation) state = AsyncValue.data(fresh);
    } on ApiException {
      // Keep what's shown; the next re-check tries again.
    }
  }

  // The caller reports the failure; this keeps the list true to the server.
  void _refetchIfStale(ApiException e) {
    if (e.meansStaleState) ref.invalidateSelf();
  }

  void prependBooking(ResourceBooking booking) => state = AsyncValue.data([booking, ...(state.value ?? [])]);
}

final bookingsControllerProvider = AsyncNotifierProvider<BookingsController, List<ResourceBooking>>(BookingsController.new);
