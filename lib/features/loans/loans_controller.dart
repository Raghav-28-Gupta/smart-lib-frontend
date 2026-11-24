// lib/features/loans/loans_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_exception.dart';
import '../../models/loan.dart';
import '../../models/return_report.dart';
import '../auth/auth_controller.dart';
import '../fines/fines_controller.dart';
import 'loan_repository.dart';

class LoansController extends AsyncNotifier<List<Loan>> {
  // Loans with a renewal in flight. A second tap would renew twice and use up
  // the renewal limit for nothing.
  final _renewing = <String>{};

  // Loans with a return in flight. A second return would be refused ("already
  // returned"), and that refusal's toast would replace the first one's "Returned." or
  // "Returned. Thanks for the report." The card's Return is off meanwhile
  // ([isReturning]), so this is the guard behind it.
  final _returning = <String>{};

  // Bumped by every build(). This notifier outlives a rebuild (a different student
  // logging in), so a quiet refresh begun for the last student must neither land in
  // the next student's state nor be joined by their `refreshQuietly`.
  int _generation = 0;

  @override
  Future<List<Loan>> build() {
    _generation++;
    _refreshing = null;
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

  /// Whether a return of [loanId] is on the wire: the loan card's Return is off then.
  /// Listeners are told when it starts and when it ends (`ref.notifyListeners`), as
  /// this is state beside the list that the card has to redraw for.
  bool isReturning(String loanId) => _returning.contains(loanId);

  /// Returns the loan, with the student's [report] of a problem with the copy when
  /// they made one. The report is part of the same request, so a refusal (the loan
  /// was closed elsewhere) means neither the return nor the report was saved. A return
  /// of a loan whose return is already on the wire sends nothing.
  Future<void> returnLoan(String loanId, {ReturnReport? report}) async {
    if (!_returning.add(loanId)) return;
    _returningChanged();
    try {
      await ref.read(loanRepositoryProvider).returnLoan(loanId, report: report);
      final current = state.value ?? [];
      state = AsyncValue.data(current.where((l) => l.id != loanId).toList());
      _refreshFines();
    } on ApiException catch (e) {
      _refetchIfStale(e);
      rethrow;
    } finally {
      _returning.remove(loanId);
      _returningChanged();
    }
  }

  void _returningChanged() {
    if (ref.mounted) ref.notifyListeners();
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
  /// open and once for the request) fetches once -- unless that one was begun for
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
      final fresh = await ref.read(loanRepositoryProvider).activeLoans();
      // The answer to the previous student's request, arriving after the next one
      // logged in: theirs, so it is dropped.
      if (generation == _generation) state = AsyncValue.data(fresh);
    } on ApiException {
      // Keep what's shown; the next re-check tries again.
    }
  }

  // The caller reports the failure; this keeps the list true to the server. A
  // 409/404 means the loan was closed elsewhere (a librarian marked the copy lost,
  // or it was returned on another device), and closing one that was late writes its
  // fines, so the fines are asked again too.
  void _refetchIfStale(ApiException e) {
    if (!e.meansStaleState) return;
    ref.invalidateSelf();
    _refreshFines();
  }
}

final loansControllerProvider = AsyncNotifierProvider<LoansController, List<Loan>>(LoansController.new);
