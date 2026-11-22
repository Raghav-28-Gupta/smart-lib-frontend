// test/features/loans/loans_controller_test.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/fines/fine_repository.dart';
import 'package:smartlib_frontend/features/fines/fines_controller.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/loans/loans_controller.dart';
import 'package:smartlib_frontend/models/fine.dart';
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

/// The mock, with renew/return made to fail or stall on demand.
class _ScriptedLoanRepository extends MockLoanRepository {
  Object? renewError;
  Object? returnError;
  Completer<void>? renewGate;
  int fetches = 0;
  int renewCalls = 0;

  @override
  Future<List<Loan>> activeLoans() {
    fetches++;
    return super.activeLoans();
  }

  @override
  Future<Loan> renew(String loanId) async {
    renewCalls++;
    await renewGate?.future;
    if (renewError != null) throw renewError!;
    return super.renew(loanId);
  }

  @override
  Future<void> returnLoan(String loanId) async {
    if (returnError != null) throw returnError!;
    return super.returnLoan(loanId);
  }
}

/// The mock, counting fetches, with the answer held back until [gate] completes.
class _GatedLoanRepository extends MockLoanRepository {
  int fetches = 0;
  Completer<void>? gate;

  @override
  Future<List<Loan>> activeLoans() async {
    fetches++;
    await gate?.future;
    return super.activeLoans();
  }
}

/// Answers each fetch with one loan named by [answer] as it was when the request
/// was made (what the server knew then), counting fetches, with the answer held
/// back while [gate] is set.
class _ScriptedLoans extends MockLoanRepository {
  String answer = 'A-loan';
  int fetches = 0;
  Completer<void>? gate;

  @override
  Future<List<Loan>> activeLoans() async {
    fetches++;
    final id = answer;
    await gate?.future;
    return [Loan(id: id, bookId: 'b1', dueDate: DateTime(2026, 10, 1), status: LoanStatus.normal, fineAmount: 0, canRenew: true)];
  }
}

/// The mock fines, counting fetches.
class _CountingFines extends MockFineRepository {
  int fetches = 0;
  @override
  Future<FinesSummary> myFines() {
    fetches++;
    return super.myFines();
  }
}

void main() {
  test('refreshQuietly joins a fetch in flight', () async {
    // My Loans asks once for the open and once for a pending request; the
    // server should be asked once.
    final repo = _GatedLoanRepository();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(loans: repo));
    addTearDown(container.dispose);
    await container.read(loansControllerProvider.future);
    repo.gate = Completer<void>();
    final notifier = container.read(loansControllerProvider.notifier);

    final first = notifier.refreshQuietly();
    final second = notifier.refreshQuietly();
    repo.gate!.complete();
    await Future.wait([first, second]);
    expect(repo.fetches, 2); // the load, and one refresh for both callers

    // The join ends with the fetch: a later call asks again.
    await notifier.refreshQuietly();
    expect(repo.fetches, 3);
  });

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

  group('when a different student logs in', () {
    Future<(ProviderContainer, _ScriptedLoans, AuthController)> asStudentA() async {
      final repo = _ScriptedLoans();
      final container = ProviderContainer(overrides: mockRepositoryOverrides(loans: repo));
      addTearDown(container.dispose);
      final auth = container.read(authControllerProvider.notifier);
      await auth.login('aditi.sharma@thapar.edu', 'anything');
      expect((await container.read(loansControllerProvider.future)).single.id, 'A-loan');
      container.listen(loansControllerProvider, (_, __) {}); // a screen is watching
      return (container, repo, auth);
    }

    Future<void> switchToB(AuthController auth) async {
      await auth.logOut();
      await auth.register('Second Student', 'second@thapar.edu', 'password123');
    }

    test("A's refresh still in flight when B logs in lands without changing B's loans", () async {
      final (container, repo, auth) = await asStudentA();
      final notifier = container.read(loansControllerProvider.notifier);

      // A's quiet refresh is on the wire (it will answer with A's loans)...
      repo.gate = Completer<void>();
      final staleGate = repo.gate!;
      final stale = notifier.refreshQuietly();
      // ...when A logs out and B logs in, whose own fetch answers at once.
      repo.gate = null;
      repo.answer = 'B-loan';
      await switchToB(auth);
      expect((await container.read(loansControllerProvider.future)).single.id, 'B-loan');

      staleGate.complete();
      await stale;

      expect(container.read(loansControllerProvider).value!.single.id, 'B-loan');
    });

    test("B's refreshQuietly does its own fetch instead of joining A's in flight", () async {
      final (container, repo, auth) = await asStudentA();
      final notifier = container.read(loansControllerProvider.notifier);

      repo.gate = Completer<void>();
      final staleGate = repo.gate!;
      final stale = notifier.refreshQuietly();
      repo.gate = null;
      repo.answer = 'B-loan';
      await switchToB(auth);
      await container.read(loansControllerProvider.future);
      final fetchesBefore = repo.fetches;

      // B has borrowed something since: B's refresh must see it, not wait for A's.
      repo.answer = 'B-loan-2';
      await notifier.refreshQuietly().timeout(const Duration(seconds: 1));

      expect(repo.fetches, fetchesBefore + 1);
      expect(container.read(loansControllerProvider).value!.single.id, 'B-loan-2');

      staleGate.complete();
      await stale;
      expect(container.read(loansControllerProvider).value!.single.id, 'B-loan-2');
    });

    test("B's own refreshes still join each other", () async {
      final (container, repo, auth) = await asStudentA();
      await switchToB(auth);
      await container.read(loansControllerProvider.future);
      final notifier = container.read(loansControllerProvider.notifier);
      repo.gate = Completer<void>();
      final fetchesBefore = repo.fetches;

      final first = notifier.refreshQuietly();
      final second = notifier.refreshQuietly();
      repo.gate!.complete();
      await Future.wait([first, second]);

      expect(repo.fetches, fetchesBefore + 1);
    });
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

  group('when the server refuses', () {
    Future<(ProviderContainer, _ScriptedLoanRepository)> loaded() async {
      final repo = _ScriptedLoanRepository();
      final container = ProviderContainer(overrides: mockRepositoryOverrides(loans: repo));
      addTearDown(container.dispose);
      await container.read(loansControllerProvider.future);
      return (container, repo);
    }

    test('a refused renewal is reported, and the list is refetched -- it was stale', () async {
      // e.g. someone joined the waitlist since the list loaded, so canRenew
      // is out of date.
      final (container, repo) = await loaded();
      repo.renewError = const ConflictException('1 student is waiting for this title.');
      await expectLater(container.read(loansControllerProvider.notifier).renew('loan1'), throwsA(isA<ConflictException>()));
      await container.read(loansControllerProvider.future);
      expect(repo.fetches, 2);
    });

    test('a refused return is reported, and the list is refetched', () async {
      final (container, repo) = await loaded();
      repo.returnError = const ConflictException('This loan has already been returned.');
      await expectLater(container.read(loansControllerProvider.notifier).returnLoan('loan1'), throwsA(isA<ConflictException>()));
      await container.read(loansControllerProvider.future);
      expect(repo.fetches, 2);
    });

    test('a refusal does not read fines the student never opened', () async {
      // The fines refresh follows the loans', but only for a student who has them.
      final fines = _CountingFines();
      final repo = _ScriptedLoanRepository()..returnError = const ConflictException('This loan has already been returned.');
      final container = ProviderContainer(overrides: mockRepositoryOverrides(loans: repo, fines: fines));
      addTearDown(container.dispose);
      await container.read(loansControllerProvider.future);

      await expectLater(container.read(loansControllerProvider.notifier).returnLoan('loan1'), throwsA(isA<ConflictException>()));
      await container.read(loansControllerProvider.future);

      expect(fines.fetches, 0);
      expect(container.exists(finesControllerProvider), false);
    });

    test('an unreachable server keeps the list as it is', () async {
      // Refetching would fail too, and turn the whole screen into an error.
      final (container, repo) = await loaded();
      repo.renewError = const ApiException(0, ApiException.networkMessage);
      await expectLater(container.read(loansControllerProvider.notifier).renew('loan1'), throwsA(isA<ApiException>()));
      expect(repo.fetches, 1);
      expect(container.read(loansControllerProvider).value, hasLength(4));
    });
  });

  test('a double tap on Renew renews once', () async {
    // Renewing twice would use up the renewal limit for nothing.
    final repo = _ScriptedLoanRepository()..renewGate = Completer<void>();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(loans: repo));
    addTearDown(container.dispose);
    await container.read(loansControllerProvider.future);
    final notifier = container.read(loansControllerProvider.notifier);

    final first = notifier.renew('loan1');
    final second = notifier.renew('loan1');
    repo.renewGate!.complete();
    await Future.wait([first, second]);
    expect(repo.renewCalls, 1);
  });
}
