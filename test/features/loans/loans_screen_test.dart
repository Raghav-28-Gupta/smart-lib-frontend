// test/features/loans/loans_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/ui/confirm_dialog.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/loans/loans_screen.dart';
import 'package:smartlib_frontend/models/loan.dart';
import '../../support/mock_overrides.dart';

class _RefusingLoanRepository extends MockLoanRepository {
  @override
  Future<void> returnLoan(String loanId) async => throw const ConflictException('This loan has already been returned.');
  @override
  Future<Loan> renew(String loanId) async => throw const ConflictException('1 student is waiting for this title.');
}

void main() {
  testWidgets('shows the overdue fine and the renewal-blocked reason', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(), child: MaterialApp(
      theme: buildSmartLibTheme(), home: const LoansScreen(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Fine: ₹30.0 and counting'), findsOneWidget);
    expect(find.text('Renewal unavailable — 1 student is waiting for this title.'), findsOneWidget);
  });

  testWidgets("tapping Return opens the confirm dialog with the design's exact copy", (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(), child: MaterialApp(
      theme: buildSmartLibTheme(),
      home: const Scaffold(body: Stack(children: [LoansScreen(), ConfirmDialogHost()])),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return').first);
    await tester.pumpAndSettle();
    expect(find.text('Return this book?'), findsOneWidget);
  });

  testWidgets('a refused return says why, and the loan stays on the list', (tester) async {
    // It used to toast "Returned." before the server had even answered.
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: _RefusingLoanRepository()),
      child: MaterialApp(
        theme: buildSmartLibTheme(),
        builder: withToasts,
        home: const Scaffold(body: Stack(children: [LoansScreen(), ConfirmDialogHost()])),
      ),
    ));
    await tester.pumpAndSettle();
    final before = find.text('Return').evaluate().length;
    await tester.tap(find.text('Return').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Return'));
    await tester.pump();
    await tester.pump();

    expect(find.text('This loan has already been returned.'), findsOneWidget);
    expect(find.text('Returned.'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Return').evaluate().length, before);
  });

  testWidgets('a refused renewal says why', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: _RefusingLoanRepository()),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const LoansScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Renew').first);
    await tester.pump();
    await tester.pump();
    expect(find.text('1 student is waiting for this title.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
