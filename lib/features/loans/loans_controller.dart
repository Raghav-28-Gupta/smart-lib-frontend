// lib/features/loans/loans_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/loan.dart';
import 'loan_repository.dart';

class LoansController extends AsyncNotifier<List<Loan>> {
  @override
  Future<List<Loan>> build() => ref.read(loanRepositoryProvider).activeLoans();

  void prependLoan(Loan loan) => state = AsyncValue.data([loan, ...(state.value ?? [])]);

  Future<void> renew(String loanId) async {
    final renewed = await ref.read(loanRepositoryProvider).renew(loanId);
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
