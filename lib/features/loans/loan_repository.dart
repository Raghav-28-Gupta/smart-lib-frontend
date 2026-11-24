// lib/features/loans/loan_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../models/loan.dart';
import '../../models/return_report.dart';

abstract class LoanRepository {
  Future<List<Loan>> activeLoans();
  Future<Loan> renew(String loanId);
  Future<void> returnLoan(String loanId, {ReturnReport? report});
}

class HttpLoanRepository implements LoanRepository {
  HttpLoanRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<Loan>> activeLoans() async {
    final res = await guardApi(() => _dio.get<List<dynamic>>('/loans/me'));
    return res.data!.map((j) => Loan.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<Loan> renew(String loanId) async {
    final res = await guardApi(() => _dio.post<Map<String, dynamic>>('/loans/${Uri.encodeComponent(loanId)}/renew'));
    return Loan.fromJson(res.data!);
  }

  @override
  Future<void> returnLoan(String loanId, {ReturnReport? report}) async {
    // The response is the returned loan; the list just drops it. A report rides
    // in the same request, so the server saves it together with the return or
    // not at all; without one the request has no body, as it always had.
    await guardApi(() => _dio.post<Object?>(
          '/loans/${Uri.encodeComponent(loanId)}/return',
          data: report == null ? null : {'report': report.toJson()},
        ));
  }
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

  /// The problem reports that came with a return, in order (a return without
  /// one adds nothing).
  final reports = <({String loanId, ReturnReport report})>[];

  @override
  Future<List<Loan>> activeLoans() async => List.of(_loans);

  @override
  Future<Loan> renew(String loanId) async {
    final index = _loans.indexWhere((l) => l.id == loanId);
    final renewed = _loans[index].copyWith(
      dueDate: DateTime.now().add(const Duration(days: 14)),
      status: LoanStatus.normal, fineAmount: 0,
    );
    _loans[index] = renewed;
    return renewed;
  }

  @override
  Future<void> returnLoan(String loanId, {ReturnReport? report}) async {
    _loans.removeWhere((l) => l.id == loanId);
    if (report != null) reports.add((loanId: loanId, report: report));
  }
}

final loanRepositoryProvider = Provider<LoanRepository>((ref) => HttpLoanRepository(ref.watch(apiClientProvider)));
