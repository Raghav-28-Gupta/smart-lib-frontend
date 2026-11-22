// lib/features/fines/fines_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_exception.dart';
import '../../models/fine.dart';
import '../auth/auth_controller.dart';
import 'fine_repository.dart';

/// The logged-in student's fines, for the Fines section under My Loans. The
/// student only reads them: a librarian records payments, waives and lowers.
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
