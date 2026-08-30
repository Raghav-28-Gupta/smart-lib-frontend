// test/features/catalog/book_detail_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/catalog/book_detail_screen.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/models/loan.dart';
import '../../support/mock_overrides.dart';

class _CleanLoanRepository implements LoanRepository {
  _CleanLoanRepository() {
    final now = DateTime.now();
    _loans = [
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

void main() {
  testWidgets('an available book shows the Borrow button and copy count', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: _CleanLoanRepository()),
      child: MaterialApp(
        theme: buildSmartLibTheme(),
        home: const BookDetailScreen(bookId: 'b1'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 copies available'), findsOneWidget);
    expect(find.text('Borrow this copy'), findsOneWidget);
  });

  testWidgets('borrowing flips the button to the Borrowed state', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: _CleanLoanRepository()),
      child: MaterialApp(
        theme: buildSmartLibTheme(),
        home: const BookDetailScreen(bookId: 'b1'),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrow this copy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Borrowed'), findsOneWidget);
  });

  testWidgets('an unavailable book shows the waitlist copy and Join Waitlist button', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(), child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b2'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('2 people ahead of you on the waitlist.'), findsOneWidget);
    expect(find.text('Join Waitlist'), findsOneWidget);
  });
}
