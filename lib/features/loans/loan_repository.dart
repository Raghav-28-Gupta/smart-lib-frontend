// lib/features/loans/loan_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/loan.dart';

abstract class LoanRepository {
  Future<List<Loan>> activeLoans();
  Future<Loan> renew(String loanId);
  Future<void> returnLoan(String loanId);
  Future<Loan> createLoan(String bookId);
}

class MockLoanRepository implements LoanRepository {
  MockLoanRepository() {
    final now = DateTime.now();
    _loans = [
      Loan(id: 'loan1', bookId: 'b1', dueDate: now.add(const Duration(days: 8)), status: LoanStatus.normal, fineAmount: 0, canRenew: true),
      Loan(id: 'loan2', bookId: 'b3', dueDate: now.add(const Duration(days: 2)), status: LoanStatus.normal, fineAmount: 0, canRenew: true),
      Loan(id: 'loan3', bookId: 'b4', dueDate: now.subtract(const Duration(days: 3)), status: LoanStatus.overdue, fineAmount: 30, canRenew: true),
      Loan(id: 'loan4', bookId: 'b8', dueDate: now.add(const Duration(days: 5)), status: LoanStatus.normal, fineAmount: 0, canRenew: false, blockedReason: '1 student is waiting for this title.'),
    ];
  }

  late List<Loan> _loans;

  @override
  Future<List<Loan>> activeLoans() async => List.of(_loans);

  @override
  Future<Loan> renew(String loanId) async {
    final index = _loans.indexWhere((l) => l.id == loanId);
    final renewed = _loans[index].copyWith(
      dueDate: DateTime.now().add(const Duration(days: 14)),
      status: LoanStatus.normal, fineAmount: 0, justRenewed: true,
    );
    _loans[index] = renewed;
    return renewed;
  }

  @override
  Future<void> returnLoan(String loanId) async {
    _loans.removeWhere((l) => l.id == loanId);
  }

  @override
  Future<Loan> createLoan(String bookId) async {
    final loan = Loan(
      id: 'loan-$bookId-${DateTime.now().microsecondsSinceEpoch}', bookId: bookId,
      dueDate: DateTime.now().add(const Duration(days: 14)), status: LoanStatus.normal,
      fineAmount: 0, canRenew: true,
    );
    _loans.removeWhere((l) => l.bookId == bookId);
    _loans.insert(0, loan);
    return loan;
  }
}

final loanRepositoryProvider = Provider<LoanRepository>((ref) => MockLoanRepository());
