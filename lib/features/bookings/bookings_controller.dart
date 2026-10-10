// lib/features/bookings/bookings_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_exception.dart';
import '../../models/resource_booking.dart';
import '../auth/auth_controller.dart';
import 'booking_repository.dart';

class BookingsController extends AsyncNotifier<List<ResourceBooking>> {
  @override
  Future<List<ResourceBooking>> build() {
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
    // previous list.
    if (state.isLoading || !state.hasValue) return;
    final current = state.requireValue;
    final now = DateTime.now();
    state = AsyncValue.data([for (final b in current) b.advancedTo(now)]);
  }

  Future<void> checkIn(String id) async {
    final ResourceBooking updated;
    try {
      updated = await ref.read(bookingRepositoryProvider).checkIn(id);
    } on ApiException catch (e) {
      _refetchIfStale(e);
      rethrow;
    }
    final current = state.value ?? [];
    state = AsyncValue.data([for (final b in current) if (b.id == id) updated else b]);
  }

  Future<void> cancel(String id) async {
    try {
      await ref.read(bookingRepositoryProvider).cancelBooking(id);
    } on ApiException catch (e) {
      _refetchIfStale(e);
      rethrow;
    }
    final current = state.value ?? [];
    state = AsyncValue.data(current.where((b) => b.id != id).toList());
  }

  // The caller reports the failure; this keeps the list true to the server.
  void _refetchIfStale(ApiException e) {
    if (e.meansStaleState) ref.invalidateSelf();
  }

  void prependBooking(ResourceBooking booking) => state = AsyncValue.data([booking, ...(state.value ?? [])]);
}

final bookingsControllerProvider = AsyncNotifierProvider<BookingsController, List<ResourceBooking>>(BookingsController.new);
