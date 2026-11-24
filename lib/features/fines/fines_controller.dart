// lib/features/fines/fines_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_exception.dart';
import '../../models/fine.dart';
import '../auth/auth_controller.dart';
import 'fine_repository.dart';

/// The logged-in student's fines, for the Fines section under My Loans. The
/// student reads them and may dispute one: a librarian records payments, waives and
/// lowers, and answers a dispute.
class FinesController extends AsyncNotifier<FinesSummary> {
  // Bumped by every build(). This notifier outlives a rebuild (a different student
  // logging in), so a quiet refresh begun for the last student must neither land in
  // the next student's state nor be joined by their `refreshQuietly`.
  int _generation = 0;

  @override
  Future<FinesSummary> build() {
    _generation++;
    _refreshing = null;
    // Outlives a logout, so keyed on who is logged in -- a different user
    // means a fresh fetch, never the previous user's fines. (Riverpod keeps the
    // previous user's value on the loading state; a screen must not draw it, see
    // `isReloading` in `FinesSection`.)
    ref.watch(authControllerProvider.select((s) => s.user?.id));
    return ref.read(fineRepositoryProvider).myFines();
  }

  /// Sends the student's dispute of [fineId], marks that fine disputed at once ("Under
  /// review"), then re-reads the fines, so the card ends up showing the server's own
  /// answer. A refusal is rethrown for the caller to show. A 409 or 404 means the
  /// picture was out of date (the fine was paid or waived, or disputed from another
  /// device), so the fines are re-read then too; a network error leaves them as they are.
  Future<void> dispute(String fineId, String reason) async {
    final generation = _generation;
    try {
      await ref.read(fineRepositoryProvider).dispute(fineId, reason);
    } on ApiException catch (e) {
      if (e.meansStaleState) await _readAfterWrite(generation);
      rethrow;
    }
    await _readAfterWrite(generation, disputedFineId: fineId);
  }

  /// Brings the fines up to date after a write. A fetch already in flight was begun
  /// before the write, so it may answer without it: it is waited for first, so that its
  /// answer cannot land after, and the fines are read again. When the write was a dispute
  /// that went through, that fine is marked disputed at once, as the server answers for
  /// it, so the card says "Under review" even if the re-read fails. Nothing is done once
  /// a different student has logged in since the write began ([generation]): the fines
  /// are theirs by then.
  Future<void> _readAfterWrite(int generation, {String? disputedFineId}) async {
    final inFlight = _refreshing;
    if (inFlight != null) await inFlight;
    if (generation != _generation) return;
    if (disputedFineId != null) {
      final current = state.value;
      if (current != null && !state.hasError && !state.isLoading) {
        state = AsyncValue.data(FinesSummary(
          fines: [
            for (final f in current.fines)
              f.id == disputedFineId ? f.withDispute(const FineDispute(status: DisputeStatus.open)) : f,
          ],
          outstandingTotal: current.outstandingTotal,
        ));
      }
    }
    await refreshQuietly();
  }

  Future<void>? _refreshing;

  /// The re-check when My Loans opens: shows what the server says now (a payment,
  /// a waive, an adjustment), and keeps what is shown if the request fails. A
  /// call made while another is in flight joins it, unless that one was begun for
  /// a student who has since logged out.
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
      final fresh = await ref.read(fineRepositoryProvider).myFines();
      // The answer to the previous student's request, arriving after the next one
      // logged in: theirs, so it is dropped.
      if (generation == _generation) state = AsyncValue.data(fresh);
    } on ApiException {
      // Keep what's shown; the next time My Loans opens tries again.
    }
  }
}

final finesControllerProvider = AsyncNotifierProvider<FinesController, FinesSummary>(FinesController.new);
