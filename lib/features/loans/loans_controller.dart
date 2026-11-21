// lib/features/loans/loans_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_exception.dart';
import '../../models/loan.dart';
import '../auth/auth_controller.dart';
import '../fines/fines_controller.dart';
import 'loan_repository.dart';

class LoansController extends AsyncNotifier<List<Loan>> {
  // Loans with a renewal in flight. A second tap would renew twice and use up
  // the renewal limit for nothing.
  final _renewing = <String>{};

  @override
  Future<List<Loan>> build() {
    // This list outlives a logout, so it's keyed on who is logged in: a
    // different user means a fresh fetch, never the previous user's loans.
    // Selecting just the id keeps unrelated auth changes from refetching.
    ref.watch(authControllerProvider.select((s) => s.user?.id));
    return ref.read(loanRepositoryProvider).activeLoans();
  }

  Future<void> renew(String loanId) async {
    if (!_renewing.add(loanId)) return;
    try {
      // justRenewed is screen state -- it drives the "Renewed" flash -- so
      // it's set here rather than by the repository, for any data source.
      final renewed = (await ref.read(loanRepositoryProvider).renew(loanId)).copyWith(justRenewed: true);
      final current = state.value ?? [];
      state = AsyncValue.data([for (final l in current) if (l.id == loanId) renewed else l]);
      _refreshFines();
    } on ApiException catch (e) {
      _refetchIfStale(e);
      rethrow;
    } finally {
      _renewing.remove(loanId);
    }
  }

  Future<void> returnLoan(String loanId) async {
    try {
      await ref.read(loanRepositoryProvider).returnLoan(loanId);
    } on ApiException catch (e) {
      _refetchIfStale(e);
      rethrow;
    }
    final current = state.value ?? [];
    state = AsyncValue.data(current.where((l) => l.id != loanId).toList());
    _refreshFines();
  }

  /// Returning or renewing a late loan makes the server write the overdue fine,
  /// so the Fines section asks again at once instead of waiting for My Loans to
  /// be opened again. Not awaited, so the loan's own result doesn't wait on it
  /// (`refreshQuietly` never throws, and keeps the fines on a network error).
  /// Skipped when the fines were never read: My Loans loads them when it opens.
  void _refreshFines() {
    if (ref.exists(finesControllerProvider)) {
      unawaited(ref.read(finesControllerProvider.notifier).refreshQuietly());
    }
  }

  Future<void>? _refreshing;

  /// The re-check when My Loans opens (a librarian may have marked a copy lost,
  /// which drops the loan) and every 30 seconds while a request waits (an
  /// approval adds a loan): shows what the server says now, and keeps the list if
  /// the request fails. A call made while another is in flight joins it, so a
  /// screen that opens with a request pending (which asks twice, once for the
  /// open and once for the request) fetches once.
  Future<void> refreshQuietly() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    try {
      final fresh = await ref.read(loanRepositoryProvider).activeLoans();
      state = AsyncValue.data(fresh);
    } on ApiException {
      // Keep what's shown; the next re-check tries again.
    }
  }

  // The caller reports the failure; this keeps the list true to the server.
  void _refetchIfStale(ApiException e) {
    if (e.meansStaleState) ref.invalidateSelf();
  }
}

final loansControllerProvider = AsyncNotifierProvider<LoansController, List<Loan>>(LoansController.new);
