// test/features/loans/loans_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/ui/confirm_dialog.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/features/borrow_requests/borrow_request_repository.dart';
import 'package:smartlib_frontend/features/borrow_requests/borrow_requests_controller.dart';
import 'package:smartlib_frontend/features/fines/fine_repository.dart';
import 'package:smartlib_frontend/features/fines/fines_controller.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/loans/loans_controller.dart';
import 'package:smartlib_frontend/features/loans/loans_screen.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/waitlist/waitlist_repository.dart';
import 'package:smartlib_frontend/models/borrow_request.dart';
import 'package:smartlib_frontend/models/fine.dart';
import 'package:smartlib_frontend/models/loan.dart';
import 'package:smartlib_frontend/models/reservation.dart';
import '../../support/fixtures.dart';
import '../../support/mock_overrides.dart';

class _RefusingLoanRepository extends MockLoanRepository {
  @override
  Future<void> returnLoan(String loanId) async => throw const ConflictException('This loan has already been returned.');
  @override
  Future<Loan> renew(String loanId) async => throw const ConflictException('1 student is waiting for this title.');
}

BorrowRequest _request(String id, String bookId, String title, BorrowRequestStatus status, {Duration age = Duration.zero, String? reason}) {
  final requestedAt = DateTime.now().subtract(age);
  return BorrowRequest(
    id: id, bookId: bookId, bookTitle: title, status: status, requestedAt: requestedAt,
    expiresAt: requestedAt.add(const Duration(hours: 24)),
    decidedAt: status == BorrowRequestStatus.pending ? null : requestedAt.add(const Duration(hours: 1)),
    declineReason: reason,
  );
}

/// The mock, with the network failing on demand.
class _FlakyRequests extends MockBorrowRequestRepository {
  _FlakyRequests({super.requests}) : super(MockBookRepository());
  bool offline = false;
  @override
  Future<List<BorrowRequest>> mine() =>
      offline ? Future.error(const ApiException(0, ApiException.networkMessage)) : super.mine();
}

/// The mock, with the server's answer to a cancel held back until [release].
class _SlowCancel extends MockBorrowRequestRepository {
  _SlowCancel({super.requests}) : super(MockBookRepository());

  final release = Completer<void>();
  int cancels = 0;

  @override
  Future<void> cancel(String requestId) async {
    cancels++;
    await release.future;
    return super.cancel(requestId);
  }
}

class _NoLoans extends MockLoanRepository {
  @override
  Future<List<Loan>> activeLoans() async => [];
}

class _UnknownLoan extends MockLoanRepository {
  @override
  Future<List<Loan>> activeLoans() async => [
        Loan(id: 'loan9', bookId: 'b1', dueDate: DateTime.now(), status: LoanStatus.unknown, fineAmount: 0, canRenew: false),
      ];
}

/// The mock loans, counting fetches, with the network failing on demand.
class _CountingLoans extends MockLoanRepository {
  int fetches = 0;
  bool offline = false;
  @override
  Future<List<Loan>> activeLoans() {
    fetches++;
    return offline ? Future.error(const ApiException(0, ApiException.networkMessage)) : super.activeLoans();
  }
}

/// The mock fines, counting fetches, with the network failing on demand.
class _CountingFines extends MockFineRepository {
  _CountingFines({super.fines});
  int fetches = 0;
  bool offline = false;
  @override
  Future<FinesSummary> myFines() {
    fetches++;
    return offline ? Future.error(const ApiException(0, ApiException.networkMessage)) : super.myFines();
  }
}

class _FailingFines extends MockFineRepository {
  @override
  Future<FinesSummary> myFines() async => throw const ApiException(500, 'The library server had a problem.');
}

/// The mock loans, where returning or renewing the overdue loan3 makes the
/// "server" write a ₹30 fine into [fines], as the real one does for a late loan.
class _LateLoans extends MockLoanRepository {
  _LateLoans(this.fines);
  final MockFineRepository fines;

  void _writeFine() => fines.fines = [_fine('late-fine'), ...fines.fines];

  @override
  Future<void> returnLoan(String loanId) async {
    await super.returnLoan(loanId);
    if (loanId == 'loan3') _writeFine();
  }

  @override
  Future<Loan> renew(String loanId) async {
    final renewed = await super.renew(loanId);
    if (loanId == 'loan3') _writeFine();
    return renewed;
  }
}

Fine _fine(
  String id, {
  String item = 'Operating System Concepts',
  FineReason reason = FineReason.overdue,
  double amount = 30,
  double? was,
  FineStatus status = FineStatus.outstanding,
  String? note,
  DateTime? date,
}) =>
    Fine(
      id: id, reason: reason, item: item, amount: amount, originalAmount: was ?? amount,
      status: status, date: date ?? DateTime.now().subtract(const Duration(days: 2)), note: note,
    );

/// The fines a real backend returned for the demo student's returned overdue loan.
List<Fine> _captured(String name) => FinesSummary.fromJson(fixture(name) as Map<String, dynamic>).fines;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

Future<void> _pumpLoans(
  WidgetTester tester, {
  MockFineRepository? fines,
  LoanRepository? loans,
  bool confirmDialogs = false,
}) async {
  // Tall, so the Fines section below the four seeded loans is built.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 3000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: mockRepositoryOverrides(fines: fines, loans: loans),
    child: MaterialApp(
      theme: buildSmartLibTheme(),
      builder: withToasts,
      home: confirmDialogs
          ? const Scaffold(body: Stack(children: [LoansScreen(), ConfirmDialogHost()]))
          : const LoansScreen(),
    ),
  ));
  await tester.pumpAndSettle();
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

  testWidgets('My Loans lists your waitlist: a held copy with its deadline, and your place in line', (tester) async {
    // A held copy is released to the next student after 48 hours, so it has
    // to be somewhere the student will see it.
    final waitlist = MockWaitlistRepository(MockBookRepository(), reservations: [
      Reservation(id: 'res-b9', bookId: 'b9', status: ReservationStatus.held, claimExpiresAt: DateTime.now().add(const Duration(hours: 30))),
      const Reservation(id: 'res-b2', bookId: 'b2', status: ReservationStatus.waiting, queuePosition: 3),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(waitlist: waitlist),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const LoansScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Waitlist'), findsOneWidget);
    expect(find.text('The Midnight Library'), findsOneWidget);
    expect(find.textContaining('Held for you until'), findsOneWidget);
    expect(find.text('Operating System Concepts'), findsOneWidget);
    expect(find.text('#3 in line'), findsOneWidget);
  });

  testWidgets('shows requests above the waitlist and loans, the newest per title', (tester) async {
    final requests = _FlakyRequests(requests: [
      _request('br-3', 'b12', 'Atomic Habits', BorrowRequestStatus.pending),
      _request('br-2', 'b12', 'Atomic Habits', BorrowRequestStatus.declined, age: const Duration(hours: 5)),
      _request('br-1', 'b5', 'Data Structures and Algorithms in Java', BorrowRequestStatus.declined, reason: 'Reserved for a course'),
      _request('br-0', 'b11', 'Sapiens', BorrowRequestStatus.expired),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(borrowRequests: requests),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const LoansScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Requests'), findsOneWidget);
    expect(find.textContaining('Waiting for a librarian · expires '), findsOneWidget);
    expect(find.text('Cancel request'), findsOneWidget);
    expect(find.text('Declined — Reserved for a course'), findsOneWidget);
    expect(find.text('Expired — no librarian approved it in time'), findsOneWidget);
    // The older answer for b12 is hidden by the newer request.
    expect(find.text('Declined by the library'), findsNothing);
  });

  testWidgets('Cancel request withdraws it', (tester) async {
    final requests = _FlakyRequests(requests: [_request('br-3', 'b12', 'Atomic Habits', BorrowRequestStatus.pending)]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(borrowRequests: requests),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const LoansScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();

    expect(find.text('Request cancelled.'), findsOneWidget);
    expect(find.text('Requests'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Cancel request is off while the cancel is in flight, so a second tap cannot send a second one', (tester) async {
    final requests = _SlowCancel(requests: [_request('br-3', 'b12', 'Atomic Habits', BorrowRequestStatus.pending)]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(borrowRequests: requests),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const LoansScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel request'));
    await tester.pump();

    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancel request')).onPressed, isNull);
    expect(requests.cancels, 1);

    requests.release.complete();
    await tester.pumpAndSettle();
    expect(find.text('Request cancelled.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a network blip during the re-check keeps the list on screen', (tester) async {
    final requests = _FlakyRequests(requests: [_request('br-3', 'b12', 'Atomic Habits', BorrowRequestStatus.pending)]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(borrowRequests: requests),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const LoansScreen()),
    ));
    await tester.pumpAndSettle();

    requests.offline = true;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(find.textContaining('Waiting for a librarian'), findsOneWidget);
    expect(find.text("Couldn't load your loans"), findsNothing);
    expect(find.text(ApiException.networkMessage), findsNothing);
  });

  testWidgets('opening My Loans re-checks a request the server answered while it was closed, without waiting 30 seconds', (tester) async {
    final requests = _FlakyRequests(requests: [_request('br-3', 'b12', 'Atomic Habits', BorrowRequestStatus.pending)]);
    final container = ProviderContainer(overrides: mockRepositoryOverrides(borrowRequests: requests));
    addTearDown(container.dispose);
    // The student requested earlier, so the controller still holds it as pending...
    await container.read(borrowRequestsControllerProvider.future);
    // ...and a librarian approved it since: the server no longer lists it.
    requests.decide('b12', BorrowRequestStatus.approved);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildSmartLibTheme(), home: const LoansScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Waiting for a librarian'), findsNothing);
    expect(find.text('Cancel request'), findsNothing);
    expect(find.text('Requests'), findsNothing);
  });

  testWidgets('the empty state waits until there are no loans, waitlist or requests', (tester) async {
    final requests = _FlakyRequests(requests: [_request('br-3', 'b12', 'Atomic Habits', BorrowRequestStatus.pending)]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: _NoLoans(), borrowRequests: requests),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const LoansScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('No active loans.'), findsOneWidget);
    expect(find.text('Browse the catalog'), findsNothing);
  });

  testWidgets("a loan with a status this version doesn't know says to update the app", (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: _UnknownLoan()),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const LoansScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Update the app to see this item's status."), findsOneWidget);
    expect(find.text('Renew'), findsNothing);
  });

  group('the Fines section', () {
    testWidgets('shows the Fines section with the outstanding total', (tester) async {
      final date = DateTime.now().subtract(const Duration(days: 2));
      await _pumpLoans(tester, fines: MockFineRepository(fines: [
        _fine('f1', date: date),
        _fine('f2', item: 'Group Room 201', reason: FineReason.noShow, amount: 50, status: FineStatus.outstanding),
        _fine('f3', item: 'The Midnight Library', reason: FineReason.lost, amount: 300, status: FineStatus.paid),
        _fine('f4', item: 'Sapiens', amount: 0, was: 40, status: FineStatus.waived, note: 'Medical leave', date: date.subtract(const Duration(days: 40))),
      ]));

      expect(find.text('Fines'), findsOneWidget);
      // Only what is still owed: 30 + 50. The paid and waived fines don't count.
      expect(find.text('Outstanding: ₹80'), findsOneWidget);

      expect(find.text('Operating System Concepts'), findsOneWidget);
      expect(find.text('₹30'), findsOneWidget);
      expect(find.text('Overdue · ${date.day} ${_months[date.month - 1]} ${date.year}'), findsOneWidget);
      expect(find.text('Outstanding'), findsNWidgets(2));
      expect(find.textContaining('No-show'), findsOneWidget);
      expect(find.textContaining('Lost book'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Waived'), findsOneWidget);
      expect(find.text('₹0, was ₹40'), findsOneWidget);
      // Whole rupees: the amounts arrive as numbers, but never show a decimal.
      expect(find.text('₹30.0'), findsNothing);
      expect(find.text('₹300'), findsOneWidget);
    });

    testWidgets('shows "₹20, was ₹30" and the library note', (tester) async {
      await _pumpLoans(tester, fines: MockFineRepository(fines: _captured('fines_me_adjusted')));

      expect(find.text('₹20, was ₹30'), findsOneWidget);
      expect(find.text('Library note: Returned during exam week'), findsOneWidget);
      expect(find.text('Adjusted'), findsOneWidget);
      expect(find.text('Outstanding: ₹20'), findsOneWidget);
    });

    testWidgets('keeps the library note after the fine is paid, and owes nothing', (tester) async {
      await _pumpLoans(tester, fines: MockFineRepository(fines: _captured('fines_me_paid')));

      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('₹20, was ₹30'), findsOneWidget);
      expect(find.text('Library note: Returned during exam week'), findsOneWidget);
      expect(find.textContaining('Outstanding:'), findsNothing);
    });

    testWidgets('shows the fine the backend captured for an unadjusted overdue loan', (tester) async {
      await _pumpLoans(tester, fines: MockFineRepository(fines: _captured('fines_me')));

      expect(find.text('Outstanding: ₹30'), findsOneWidget);
      expect(find.text('₹30'), findsOneWidget);
      expect(find.textContaining('Library note'), findsNothing);
    });

    testWidgets('shows "No fines." when there are none', (tester) async {
      await _pumpLoans(tester);

      expect(find.text('Fines'), findsOneWidget);
      expect(find.text('No fines.'), findsOneWidget);
      expect(find.textContaining('Outstanding:'), findsNothing);
    });

    testWidgets('a student with only fines sees the section, not the empty state', (tester) async {
      await _pumpLoans(tester, loans: _NoLoans(), fines: MockFineRepository(fines: [_fine('f1')]));

      expect(find.text('No active loans'), findsNothing);
      expect(find.text('Browse the catalog'), findsNothing);
      expect(find.text('Fines'), findsOneWidget);
      expect(find.text('Operating System Concepts'), findsOneWidget);
      expect(find.text('Outstanding: ₹30'), findsOneWidget);
    });

    testWidgets('a student with no loans and no fines still sees the empty state', (tester) async {
      await _pumpLoans(tester, loans: _NoLoans());

      expect(find.text('No active loans'), findsOneWidget);
      expect(find.text('Browse the catalog'), findsOneWidget);
      expect(find.text('Fines'), findsNothing);
    });

    testWidgets('an unknown status shows the update notice', (tester) async {
      await _pumpLoans(tester, fines: MockFineRepository(fines: [_fine('f1', status: FineStatus.unknown)]));

      expect(find.text("Update the app to see this item's status."), findsOneWidget);
      expect(find.text('Operating System Concepts'), findsOneWidget);
      // Nothing the app doesn't understand is claimed about it.
      expect(find.text('Outstanding'), findsNothing);
      expect(find.text('₹30'), findsNothing);
    });

    testWidgets('a fine that cannot be loaded says so, offers Retry, and leaves the loans alone', (tester) async {
      await _pumpLoans(tester, fines: _FailingFines());

      expect(find.text("Couldn't load your fines."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Fine: ₹30.0 and counting'), findsOneWidget);
      expect(find.text("Couldn't load your loans"), findsNothing);
    });
  });

  group('a late loan returned or renewed from My Loans', () {
    // The loan3 row is the overdue one, third in the list.
    Finder overdueLoan(Type button, String label) => find.widgetWithText(button, label).at(2);

    testWidgets('returning a loan refreshes the Fines section', (tester) async {
      final fines = _CountingFines();
      await _pumpLoans(tester, loans: _LateLoans(fines), fines: fines, confirmDialogs: true);
      expect(find.text('No fines.'), findsOneWidget);
      expect(fines.fetches, 1);

      await tester.tap(overdueLoan(TextButton, 'Return'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Return'));
      await tester.pumpAndSettle();

      // The fine the server wrote for the late return is on this screen now.
      expect(fines.fetches, 2);
      expect(find.text('Outstanding: ₹30'), findsOneWidget);
      expect(find.text('No fines.'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('renewing a loan refreshes the Fines section', (tester) async {
      final fines = _CountingFines();
      await _pumpLoans(tester, loans: _LateLoans(fines), fines: fines);
      expect(find.text('No fines.'), findsOneWidget);

      await tester.tap(overdueLoan(OutlinedButton, 'Renew'));
      await tester.pumpAndSettle();

      expect(fines.fetches, 2);
      expect(find.text('Outstanding: ₹30'), findsOneWidget);
      expect(find.text('No fines.'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a failed fines refresh after a return keeps the Fines section as it was', (tester) async {
      final fines = _CountingFines(fines: [_fine('f1', status: FineStatus.paid)]);
      await _pumpLoans(tester, loans: _LateLoans(fines), fines: fines, confirmDialogs: true);

      fines.offline = true;
      await tester.tap(overdueLoan(TextButton, 'Return'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Return'));
      await tester.pumpAndSettle();

      expect(fines.fetches, 2); // it did ask, and the ask failed
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text("Couldn't load your fines."), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a refused return does not refresh the fines', (tester) async {
      final fines = _CountingFines();
      await _pumpLoans(tester, loans: _RefusingLoanRepository(), fines: fines, confirmDialogs: true);

      await tester.tap(overdueLoan(TextButton, 'Return'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Return'));
      await tester.pumpAndSettle();

      expect(find.text('This loan has already been returned.'), findsOneWidget);
      expect(fines.fetches, 1);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('opening My Loans refreshes the loans and the fines', () {
    Future<(ProviderContainer, _CountingLoans, _CountingFines)> loaded({List<Fine> fines = const [], bool preloadFines = true}) async {
      final loans = _CountingLoans();
      final repo = _CountingFines(fines: fines);
      final container = ProviderContainer(overrides: mockRepositoryOverrides(loans: loans, fines: repo));
      addTearDown(container.dispose);
      await container.read(loansControllerProvider.future);
      if (preloadFines) await container.read(finesControllerProvider.future);
      return (container, loans, repo);
    }

    Future<void> open(WidgetTester tester, ProviderContainer container) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 3000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildSmartLibTheme(), home: const LoansScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('opening My Loans refetches loans and fines once', (tester) async {
      // Both were loaded earlier (Home reads the loans), so each can predate a
      // payment, a waive or a lost loan.
      final (container, loans, fines) = await loaded(fines: [_fine('f1')]);
      expect((loans.fetches, fines.fetches), (1, 1));

      // A librarian records the payment while the student is elsewhere.
      fines.fines = [_fine('f1', status: FineStatus.paid)];
      await open(tester, container);

      expect((loans.fetches, fines.fetches), (2, 2));
      expect(find.text('Paid'), findsOneWidget);
      expect(find.textContaining('Outstanding:'), findsNothing);

      // Each visit builds a new screen, so the next one asks again.
      fines.fines = [_fine('f1', status: FineStatus.paid), _fine('f2', item: 'Sapiens')];
      await tester.pumpWidget(const SizedBox());
      await open(tester, container);
      expect((loans.fetches, fines.fetches), (3, 3));
      expect(find.text('Sapiens'), findsOneWidget);
    });

    testWidgets('a failed quiet refresh on open keeps the loans and fines on screen', (tester) async {
      final (container, loans, fines) = await loaded(fines: [_fine('f1')]);

      loans.offline = true;
      fines.offline = true;
      await open(tester, container);

      expect((loans.fetches, fines.fetches), (2, 2)); // it did ask, and the asks failed
      expect(find.text('Operating System Concepts'), findsOneWidget);
      expect(find.text('Outstanding: ₹30'), findsOneWidget);
      expect(find.text('Fine: ₹30.0 and counting'), findsOneWidget);
      expect(find.text("Couldn't load your loans"), findsNothing);
      expect(find.text("Couldn't load your fines."), findsNothing);
    });

    testWidgets('opening it before the lists have loaded does not fetch a second time', (tester) async {
      final loans = _CountingLoans();
      final fines = _CountingFines(fines: [_fine('f1')]);
      await _pumpLoans(tester, loans: loans, fines: fines);

      expect(find.text('Operating System Concepts'), findsOneWidget);
      expect((loans.fetches, fines.fetches), (1, 1)); // the loads are the fresh fetches
    });

    testWidgets('the loans are refreshed on open even when the fines are loading for the first time', (tester) async {
      // Home loads the loans, but nothing loads the fines until My Loans opens.
      final (container, loans, fines) = await loaded(fines: [_fine('f1')], preloadFines: false);

      await open(tester, container);

      expect(loans.fetches, 2);
      expect(fines.fetches, 1);
      expect(find.text('Operating System Concepts'), findsOneWidget);
    });

    testWidgets('opening it while a request is pending still fetches the loans only once', (tester) async {
      // PendingRefresh also re-checks right after the first frame when it opens
      // active; the two share one fetch of the loans.
      final loans = _CountingLoans();
      final container = ProviderContainer(overrides: mockRepositoryOverrides(
        loans: loans,
        fines: _CountingFines(),
        borrowRequests: _FlakyRequests(requests: [_request('br-3', 'b12', 'Atomic Habits', BorrowRequestStatus.pending)]),
      ));
      addTearDown(container.dispose);
      await container.read(loansControllerProvider.future);
      await container.read(finesControllerProvider.future);
      await container.read(borrowRequestsControllerProvider.future);
      expect(loans.fetches, 1);

      await open(tester, container);

      expect(find.textContaining('Waiting for a librarian'), findsOneWidget);
      expect(loans.fetches, 2);
    });
  });
}
