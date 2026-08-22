// test/features/loans/loans_controller_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/loans/loans_controller.dart';
import 'package:smartlib_frontend/models/loan.dart';

void main() {
  test('build() loads the 4 seeded loans, one of which is overdue', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final loans = await container.read(loansControllerProvider.future);
    expect(loans.length, 4);
    expect(loans.firstWhere((l) => l.id == 'loan3').status, LoanStatus.overdue);
    expect(loans.firstWhere((l) => l.id == 'loan3').fineAmount, 30.0);
    expect(loans.firstWhere((l) => l.id == 'loan4').canRenew, false);
  });

  test('renew marks the loan justRenewed and clears overdue status', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(loansControllerProvider.future);
    await container.read(loansControllerProvider.notifier).renew('loan3');
    final loans = container.read(loansControllerProvider).value!;
    final renewed = loans.firstWhere((l) => l.id == 'loan3');
    expect(renewed.justRenewed, true);
    expect(renewed.status, LoanStatus.normal);
  });

  test('returnLoan removes the loan from the list', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(loansControllerProvider.future);
    await container.read(loansControllerProvider.notifier).returnLoan('loan1');
    final loans = container.read(loansControllerProvider).value!;
    expect(loans.any((l) => l.id == 'loan1'), false);
  });
}
