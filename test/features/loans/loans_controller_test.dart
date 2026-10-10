// test/features/loans/loans_controller_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/loans/loans_controller.dart';
import 'package:smartlib_frontend/models/loan.dart';
import '../../support/mock_overrides.dart';

/// Returns one loan named after the fetch number, so a test can tell a fresh
/// fetch from a cached list.
class _CountingLoanRepository extends MockLoanRepository {
  int fetches = 0;
  @override
  Future<List<Loan>> activeLoans() async {
    fetches++;
    return [
      Loan(id: 'fetch-$fetches', bookId: 'b1', dueDate: DateTime(2026, 10, 1), status: LoanStatus.normal, fineAmount: 0, canRenew: true),
    ];
  }
}

void main() {
  test('build() loads the 4 seeded loans, one of which is overdue', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    final loans = await container.read(loansControllerProvider.future);
    expect(loans.length, 4);
    expect(loans.firstWhere((l) => l.id == 'loan3').status, LoanStatus.overdue);
    expect(loans.firstWhere((l) => l.id == 'loan3').fineAmount, 30.0);
    expect(loans.firstWhere((l) => l.id == 'loan4').canRenew, false);
  });

  test('renew marks the loan justRenewed and clears overdue status', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container.read(loansControllerProvider.future);
    await container.read(loansControllerProvider.notifier).renew('loan3');
    final loans = container.read(loansControllerProvider).value!;
    final renewed = loans.firstWhere((l) => l.id == 'loan3');
    expect(renewed.justRenewed, true);
    expect(renewed.status, LoanStatus.normal);
  });

  test('returnLoan removes the loan from the list', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container.read(loansControllerProvider.future);
    await container.read(loansControllerProvider.notifier).returnLoan('loan1');
    final loans = container.read(loansControllerProvider).value!;
    expect(loans.any((l) => l.id == 'loan1'), false);
  });

  test("a different user logging in gets their own loans, not the last user's", () async {
    // The loans list outlives a logout, so without this the next person to
    // log in on the same device would see someone else's borrowing history.
    final repo = _CountingLoanRepository();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(loans: repo));
    addTearDown(container.dispose);
    final auth = container.read(authControllerProvider.notifier);

    await auth.login('aditi.sharma@thapar.edu', 'anything');
    expect((await container.read(loansControllerProvider.future)).single.id, 'fetch-1');

    await auth.logOut();
    await auth.register('Second Student', 'second@thapar.edu', 'password123');
    expect((await container.read(loansControllerProvider.future)).single.id, 'fetch-2');
  });

  test('unrelated auth changes do not refetch the loans', () async {
    // Only who is logged in matters -- a validation message clearing, say,
    // must not trigger a network round trip.
    final repo = _CountingLoanRepository();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(loans: repo));
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).login('aditi.sharma@thapar.edu', 'anything');
    await container.read(loansControllerProvider.future);

    container.read(authControllerProvider.notifier).clearValidation();
    await container.read(loansControllerProvider.future);
    expect(repo.fetches, 1);
  });
}
