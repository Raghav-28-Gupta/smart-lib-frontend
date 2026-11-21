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
  @override
  Future<FinesSummary> build() {
    // Outlives a logout, so keyed on who is logged in -- a different user
    // means a fresh fetch, never the previous user's fines.
    ref.watch(authControllerProvider.select((s) => s.user?.id));
    return ref.read(fineRepositoryProvider).myFines();
  }

  Future<void>? _refreshing;

  /// The re-check when My Loans opens: shows what the server says now (a payment,
  /// a waive, an adjustment), and keeps what is shown if the request fails. A
  /// call made while another is in flight joins it.
  Future<void> refreshQuietly() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    try {
      final fresh = await ref.read(fineRepositoryProvider).myFines();
      state = AsyncValue.data(fresh);
    } on ApiException {
      // Keep what's shown; the next time My Loans opens tries again.
    }
  }
}

final finesControllerProvider = AsyncNotifierProvider<FinesController, FinesSummary>(FinesController.new);
