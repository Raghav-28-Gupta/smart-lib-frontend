// lib/features/loans/loans_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/loan.dart';
import '../auth/auth_controller.dart';
import 'loan_repository.dart';

class LoansController extends AsyncNotifier<List<Loan>> {
  @override
  Future<List<Loan>> build() {
    // This list outlives a logout, so it's keyed on who is logged in: a
    // different user means a fresh fetch, never the previous user's loans.
    // Selecting just the id keeps unrelated auth changes from refetching.
    ref.watch(authControllerProvider.select((s) => s.user?.id));
    return ref.read(loanRepositoryProvider).activeLoans();
  }

  void prependLoan(Loan loan) => state = AsyncValue.data([loan, ...(state.value ?? [])]);

  Future<void> renew(String loanId) async {
    // justRenewed is screen state -- it drives the "Renewed" flash -- so it's
    // set here rather than by the repository, and holds for any data source.
    final renewed = (await ref.read(loanRepositoryProvider).renew(loanId)).copyWith(justRenewed: true);
    final current = state.value ?? [];
    state = AsyncValue.data([for (final l in current) if (l.id == loanId) renewed else l]);
  }

  Future<void> returnLoan(String loanId) async {
    await ref.read(loanRepositoryProvider).returnLoan(loanId);
    final current = state.value ?? [];
    state = AsyncValue.data(current.where((l) => l.id != loanId).toList());
  }
}

final loansControllerProvider = AsyncNotifierProvider<LoansController, List<Loan>>(LoansController.new);
