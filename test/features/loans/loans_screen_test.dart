// test/features/loans/loans_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/ui/confirm_dialog.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/auth/auth_repository.dart';
import 'package:smartlib_frontend/features/borrow_requests/borrow_request_repository.dart';
import 'package:smartlib_frontend/features/borrow_requests/borrow_requests_controller.dart';
import 'package:smartlib_frontend/features/fines/fine_repository.dart';
import 'package:smartlib_frontend/features/fines/fines_controller.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/loans/loans_controller.dart';
import 'package:smartlib_frontend/features/loans/loans_screen.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/notices/notice_repository.dart';
import 'package:smartlib_frontend/features/notices/notices_controller.dart';
import 'package:smartlib_frontend/features/waitlist/waitlist_repository.dart';
import 'package:smartlib_frontend/models/app_user.dart';
import 'package:smartlib_frontend/models/borrow_request.dart';
import 'package:smartlib_frontend/models/fine.dart';
import 'package:smartlib_frontend/models/loan.dart';
import 'package:smartlib_frontend/models/notice.dart';
import 'package:smartlib_frontend/models/reservation.dart';
import 'package:smartlib_frontend/models/return_report.dart';
import 'package:smartlib_frontend/widgets/loading_skeleton.dart';
import '../../support/fixtures.dart';
import '../../support/mock_overrides.dart';

class _RefusingLoanRepository extends MockLoanRepository {
  @override
  Future<void> returnLoan(String loanId, {ReturnReport? report}) async => throw const ConflictException('This loan has already been returned.');
  @override
  Future<Loan> renew(String loanId) async => throw const ConflictException('1 student is waiting for this title.');
}

/// The mock loans, with the server's answer to a return held back until [release], and
/// then refused with [refusal] when that is set.
class _SlowReturn extends MockLoanRepository {
  final release = Completer<void>();
  ApiException? refusal;
  int returns = 0;

  @override
  Future<void> returnLoan(String loanId, {ReturnReport? report}) async {
    returns++;
    await release.future;
    final refused = refusal;
    if (refused != null) throw refused;
    return super.returnLoan(loanId, report: report);
  }
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

/// The mock fines where the server refuses a dispute with [refusal] until a test
/// clears it, and where the answer to a dispute can be held back until [release].
class _DisputeScript extends MockFineRepository {
  _DisputeScript({super.fines});

  ApiException? refusal;
  Completer<void>? release;

  @override
  Future<void> dispute(String fineId, String reason) async {
    await release?.future;
    final refused = refusal;
    if (refused != null) {
      disputes.add((fineId: fineId, reason: reason)); // it reached the server, which said no
      throw refused;
    }
    return super.dispute(fineId, reason);
  }
}

/// The mock loans, where returning or renewing the overdue loan3 makes the
/// "server" write a ₹30 fine into [fines], as the real one does for a late loan.
class _LateLoans extends MockLoanRepository {
  _LateLoans(this.fines);
  final MockFineRepository fines;

  void _writeFine() => fines.fines = [_fine('late-fine'), ...fines.fines];

  @override
  Future<void> returnLoan(String loanId, {ReturnReport? report}) async {
    await super.returnLoan(loanId, report: report);
    if (loanId == 'loan3') _writeFine();
  }

  @override
  Future<Loan> renew(String loanId) async {
    final renewed = await super.renew(loanId);
    if (loanId == 'loan3') _writeFine();
    return renewed;
  }
}

/// The mock loans where the loan was closed somewhere else (a librarian marked the
/// copy lost, or it was returned on another device), which charged a ₹300 fine into
/// [fines] the student hasn't seen. Returning or renewing here is refused with [error].
class _ClosedElsewhere extends MockLoanRepository {
  _ClosedElsewhere(this.fines, this.error);
  final MockFineRepository fines;
  final ApiException error;

  Never _refuse() {
    fines.fines = [_fine('lost-fine', item: 'Operating System Concepts', reason: FineReason.lost, amount: 300), ...fines.fines];
    throw error;
  }

  @override
  Future<void> returnLoan(String loanId, {ReturnReport? report}) async => _refuse();
  @override
  Future<Loan> renew(String loanId) async => _refuse();
}

const _closedBecauseLost = ConflictException('This loan was closed because the copy was marked lost.');
const _offline = ApiException(0, ApiException.networkMessage);

/// Logs in whoever asks, at once (the mock's 300 ms delay would need pumping).
class _InstantAuth extends MockAuthRepository {
  @override
  Future<AppUser> login(String email, String password) async =>
      AppUser(id: 'u-$email', name: email, email: email, roll: '1');
}

/// Serves [served] as it was when the request was made, with the answer held back
/// while [gate] is set: a student's list that is still on its way.
class _GatedFines extends MockFineRepository {
  List<Fine> served = [];
  bool failing = false;
  Completer<void>? gate;
  @override
  Future<FinesSummary> myFines() async {
    final gate = this.gate;
    final answer = List.of(served);
    final fail = failing;
    await gate?.future;
    if (fail) throw const ApiException(500, 'The library server had a problem.');
    return FinesSummary(fines: answer, outstandingTotal: answer.fold(0.0, (t, f) => t + f.amount));
  }
}

/// The mock notices, counting fetches, with the network failing on demand.
class _CountingNotices extends MockNoticeRepository {
  _CountingNotices({super.notices});
  int fetches = 0;
  bool offline = false;
  @override
  Future<List<Notice>> myNotices() {
    fetches++;
    return offline ? Future.error(const ApiException(0, ApiException.networkMessage)) : super.myNotices();
  }
}

/// Serves [served] as it was when the request was made, with the answer held back
/// while [gate] is set: a student's notices that are still on their way.
class _GatedNotices extends MockNoticeRepository {
  List<Notice> served = [];
  bool failing = false;
  Completer<void>? gate;
  @override
  Future<List<Notice>> myNotices() async {
    final gate = this.gate;
    final answer = List.of(served);
    final fail = failing;
    await gate?.future;
    if (fail) throw const ApiException(500, 'The library server had a problem.');
    return answer;
  }
}

class _GatedWaitlist extends MockWaitlistRepository {
  _GatedWaitlist() : super(MockBookRepository());
  List<Reservation> served = [];
  bool failing = false;
  Completer<void>? gate;
  @override
  Future<List<Reservation>> mine() async {
    final gate = this.gate;
    final answer = List.of(served);
    final fail = failing;
    await gate?.future;
    if (fail) throw const ApiException(500, 'The library server had a problem.');
    return answer;
  }
}

class _GatedRequests extends MockBorrowRequestRepository {
  _GatedRequests() : super(MockBookRepository());
  List<BorrowRequest> served = [];
  bool failing = false;
  Completer<void>? gate;
  @override
  Future<List<BorrowRequest>> mine() async {
    final gate = this.gate;
    final answer = List.of(served);
    final fail = failing;
    await gate?.future;
    if (fail) throw const ApiException(500, 'The library server had a problem.');
    return answer;
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
  FineDispute? dispute,
}) =>
    Fine(
      id: id, reason: reason, item: item, amount: amount, originalAmount: was ?? amount,
      status: status, date: date ?? DateTime.now().subtract(const Duration(days: 2)), note: note,
      dispute: dispute,
    );

/// The fines a real backend returned for the demo student's returned overdue loan.
List<Fine> _captured(String name) => FinesSummary.fromJson(fixture(name) as Map<String, dynamic>).fines;

Notice _notice(
  String id, {
  NoticeKind kind = NoticeKind.overdueReminder,
  String title = 'Overdue book reminder',
  String body = 'Your copy of Operating System Concepts is 3 days overdue.',
  DateTime? createdAt,
}) =>
    Notice(id: id, kind: kind, title: title, body: body, createdAt: createdAt ?? DateTime.now().subtract(const Duration(hours: 5)));

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

Future<void> _pumpLoans(
  WidgetTester tester, {
  MockFineRepository? fines,
  LoanRepository? loans,
  MockNoticeRepository? notices,
  MockBorrowRequestRepository? borrowRequests,
  bool confirmDialogs = false,
}) async {
  // Tall, so the Fines section below the four seeded loans is built.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 3000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: mockRepositoryOverrides(fines: fines, loans: loans, notices: notices, borrowRequests: borrowRequests),
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

/// Shows My Loans on an existing container, as a tab visit builds it afresh.
Future<void> _showMyLoans(WidgetTester tester, ProviderContainer container) => tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const LoansScreen()),
    ));

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

  group('returning a book from My Loans with a report', () {
    Future<void> reportAndReturn(WidgetTester tester, String choice, {String? note}) async {
      await tester.tap(find.widgetWithText(TextButton, 'Return').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report a problem with this copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      if (note != null) {
        await tester.enterText(find.byType(TextField), note);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Return'));
      await tester.pumpAndSettle();
    }

    testWidgets('the report goes with the return, the loan leaves the list and the toast thanks for it', (tester) async {
      final loans = MockLoanRepository();
      await _pumpLoans(tester, loans: loans, confirmDialogs: true);
      expect(find.widgetWithText(TextButton, 'Return'), findsNWidgets(4));

      await reportAndReturn(tester, 'Missing pages', note: 'Pages 40-52 are gone');

      expect(loans.reports, hasLength(1));
      expect(loans.reports.single.loanId, 'loan1');
      expect(loans.reports.single.report.toJson(), {'category': 'missing_pages', 'note': 'Pages 40-52 are gone'});
      expect(find.widgetWithText(TextButton, 'Return'), findsNWidgets(3));
      expect(find.text('Returned. Thanks for the report.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a refused return with a report shows the server\'s message and no thanks, and the loan stays', (tester) async {
      await _pumpLoans(tester, loans: _RefusingLoanRepository(), confirmDialogs: true);

      await reportAndReturn(tester, 'Damaged');

      expect(find.text('This loan has already been returned.'), findsOneWidget);
      expect(find.text('Returned. Thanks for the report.'), findsNothing);
      expect(find.text('Returned.'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Return'), findsNWidgets(4));
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('a return still on the wire', () {
    // The card's Return, by position: loan1 is the first card.
    Finder cardReturn(int index) => find.widgetWithText(TextButton, 'Return').at(index);
    bool cardReturnEnabled(WidgetTester tester, int index) => tester.widget<TextButton>(cardReturn(index)).onPressed != null;

    // Returns the first loan with a damage report, and leaves the server's answer pending.
    Future<void> returnFirstWithReport(WidgetTester tester) async {
      await tester.tap(cardReturn(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report a problem with this copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Damaged'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Return'));
      await tester.pumpAndSettle();
    }

    testWidgets("the card's Return is off for that loan until the answer comes, so a second return cannot replace the thanks with a refusal", (tester) async {
      final loans = _SlowReturn();
      await _pumpLoans(tester, loans: loans, confirmDialogs: true);
      expect(cardReturnEnabled(tester, 0), true);

      await returnFirstWithReport(tester);

      expect(loans.returns, 1);
      expect(find.text('Return this book?'), findsNothing); // the dialog closed at once
      expect(cardReturnEnabled(tester, 0), false);
      expect(cardReturnEnabled(tester, 1), true); // another loan is not held up

      // A tap on the disabled button asks nothing: no dialog, no second request.
      await tester.tap(cardReturn(0), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Return this book?'), findsNothing);
      expect(loans.returns, 1);

      loans.release.complete();
      await tester.pumpAndSettle();

      expect(loans.returns, 1);
      expect(find.text('Returned. Thanks for the report.'), findsOneWidget);
      expect(find.text('This loan has already been returned.'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Return'), findsNWidgets(3)); // loan1 has left the list
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('another loan can be returned while the first is on the wire', (tester) async {
      final loans = _SlowReturn();
      await _pumpLoans(tester, loans: loans, confirmDialogs: true);
      await returnFirstWithReport(tester);

      await tester.tap(cardReturn(1));
      await tester.pumpAndSettle();
      expect(find.text('Return this book?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Return'));
      await tester.pumpAndSettle();
      expect(loans.returns, 2);

      loans.release.complete();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Return'), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a refused return gives the card its Return back, and says why', (tester) async {
      final loans = _SlowReturn()..refusal = const ConflictException('This loan was closed because the copy was marked lost.');
      await _pumpLoans(tester, loans: loans, confirmDialogs: true);

      await returnFirstWithReport(tester);
      expect(cardReturnEnabled(tester, 0), false);

      loans.release.complete();
      await tester.pumpAndSettle();

      expect(find.text('This loan was closed because the copy was marked lost.'), findsOneWidget);
      expect(find.text('Returned. Thanks for the report.'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Return'), findsNWidgets(4));
      expect(cardReturnEnabled(tester, 0), true);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a network failure gives the card its Return back', (tester) async {
      final loans = _SlowReturn()..refusal = const ApiException(0, ApiException.networkMessage);
      await _pumpLoans(tester, loans: loans, confirmDialogs: true);

      await returnFirstWithReport(tester);
      loans.release.complete();
      await tester.pumpAndSettle();

      expect(find.text(ApiException.networkMessage), findsOneWidget);
      expect(cardReturnEnabled(tester, 0), true);
      await tester.pump(const Duration(seconds: 3));
    });
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

  group('disputing a fine', () {
    Finder disputeButtons() => find.widgetWithText(TextButton, 'Dispute');
    Finder reasonField() => find.byType(TextField);
    Finder sendButton() => find.widgetWithText(FilledButton, 'Send');

    // Opens the dialog on the first Dispute button.
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(disputeButtons().first);
      await tester.pumpAndSettle();
    }

    // The toast stays up for 2.4 s; let it go so no timer outlives the test.
    Future<void> letToastGo(WidgetTester tester) => tester.pump(const Duration(seconds: 3));

    testWidgets('an outstanding fine shows Dispute and an open one shows "Under review"', (tester) async {
      // The fine the backend wrote for the overdue return, and an adjusted one: both still owed.
      await _pumpLoans(tester, fines: MockFineRepository(fines: [
        ..._captured('fines_me'),
        _fine('f2', item: 'Sapiens', amount: 20, was: 30, status: FineStatus.adjusted, note: 'Returned during exam week'),
      ]));
      expect(disputeButtons(), findsNWidgets(2));
      expect(find.text('Under review'), findsNothing);

      // After the student disputed, the backend's own answer: the fine is still
      // outstanding, and the button has made way for the status.
      await tester.pumpWidget(const SizedBox());
      await _pumpLoans(tester, fines: MockFineRepository(fines: _captured('fines_me_disputed')));
      expect(find.text('Under review'), findsOneWidget);
      expect(disputeButtons(), findsNothing);
      expect(find.text('Outstanding'), findsOneWidget);
      expect(find.text('Outstanding: ₹30'), findsOneWidget);
    });

    testWidgets('the dialog needs a reason and sends it', (tester) async {
      final fines = MockFineRepository(fines: [_fine('f1'), _fine('f2', item: 'Sapiens')]);
      await _pumpLoans(tester, fines: fines);
      await openDialog(tester);

      expect(find.text('Dispute this fine'), findsOneWidget);
      expect(find.text('Why do you think this fine is wrong?'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

      // Nothing to send until there is something to say: not even spaces.
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);
      await tester.tap(sendButton());
      await tester.pump();
      expect(fines.disputes, isEmpty);
      await tester.enterText(reasonField(), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);

      // At most 300 characters, as the server counts them: 301 are refused (and the
      // student's text is left alone, not cut), 300 are not.
      await tester.enterText(reasonField(), 'x' * 301);
      await tester.pump();
      expect(tester.widget<TextField>(reasonField()).controller!.text.length, 301);
      expect(find.text('301/300'), findsOneWidget);
      expect(find.text('At most 300 characters'), findsOneWidget);
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);
      await tester.enterText(reasonField(), 'x' * 300);
      await tester.pump();
      expect(find.text('300/300'), findsOneWidget);
      expect(find.text('At most 300 characters'), findsNothing);
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNotNull);

      await tester.enterText(reasonField(), '  The desk scanned my return late.  ');
      await tester.pump();
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNotNull);
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Sent once, trimmed, for the fine whose button was pressed.
      expect(fines.disputes, [(fineId: 'f1', reason: 'The desk scanned my return late.')]);
      expect(find.text('Dispute this fine'), findsNothing);
      expect(find.text('Dispute sent.'), findsOneWidget);
      // The first card now reads "Under review"; the other fine still offers Dispute.
      expect(find.text('Under review'), findsOneWidget);
      expect(disputeButtons(), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('Cancel closes the dialog and sends nothing', (tester) async {
      final fines = MockFineRepository(fines: [_fine('f1')]);
      await _pumpLoans(tester, fines: fines);
      await openDialog(tester);
      await tester.enterText(reasonField(), 'It was returned on time.');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Dispute this fine'), findsNothing);
      expect(fines.disputes, isEmpty);
      expect(disputeButtons(), findsOneWidget);
      expect(find.text('Under review'), findsNothing);
    });

    testWidgets('a refusal keeps the dialog and shows the message', (tester) async {
      final fines = _DisputeScript(fines: [_fine('f1')])
        ..refusal = const ConflictException("You've already disputed this fine.");
      await _pumpLoans(tester, fines: fines);
      await openDialog(tester);
      await tester.enterText(reasonField(), 'It was returned on time.');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // The server's own words, and the student's own words still in the field.
      expect(find.text("You've already disputed this fine."), findsOneWidget);
      expect(find.text('Dispute this fine'), findsOneWidget);
      expect(tester.widget<TextField>(reasonField()).controller!.text, 'It was returned on time.');
      expect(find.text('Dispute sent.'), findsNothing);
      expect(fines.disputes.length, 1);
      // Send is usable again, and the text goes out on a second try.
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNotNull);

      fines.refusal = null;
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(fines.disputes.length, 2);
      expect(fines.disputes.last.reason, 'It was returned on time.');
      expect(find.text('Dispute this fine'), findsNothing);
      expect(find.text('Under review'), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('a network failure keeps the dialog and says the library cannot be reached', (tester) async {
      final fines = _DisputeScript(fines: [_fine('f1')])..refusal = const ApiException(0, ApiException.networkMessage);
      await _pumpLoans(tester, fines: fines);
      await openDialog(tester);
      await tester.enterText(reasonField(), 'It was returned on time.');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.text(ApiException.networkMessage), findsOneWidget);
      expect(find.text('Dispute this fine'), findsOneWidget);
      expect(tester.widget<TextField>(reasonField()).controller!.text, 'It was returned on time.');
      await letToastGo(tester);
    });

    testWidgets('a second tap on Send while the first is in flight sends nothing', (tester) async {
      final fines = _DisputeScript(fines: [_fine('f1')])..release = Completer<void>();
      await _pumpLoans(tester, fines: fines);
      await openDialog(tester);
      await tester.enterText(reasonField(), 'It was returned on time.');
      await tester.pump();

      await tester.tap(sendButton());
      await tester.pump();
      // The answer has not come: Send is off and the field cannot change under it.
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);
      await tester.tap(sendButton());
      await tester.pump();
      expect(find.text('Dispute this fine'), findsOneWidget);

      fines.release!.complete();
      await tester.pumpAndSettle();
      expect(fines.disputes.length, 1);
      expect(find.text('Dispute this fine'), findsNothing);
      expect(find.text('Under review'), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets("an upheld dispute shows the library's note", (tester) async {
      await _pumpLoans(tester, fines: MockFineRepository(fines: [
        _fine('f1', dispute: const FineDispute(status: DisputeStatus.upheld, note: 'The scan log shows it came back a day late.')),
      ]));

      expect(find.text('The library kept this fine.'), findsOneWidget);
      expect(find.text('The scan log shows it came back a day late.'), findsOneWidget);
      // It stays owed, and the one dispute is spent.
      expect(find.text('Outstanding'), findsOneWidget);
      expect(find.text('Outstanding: ₹30'), findsOneWidget);
      expect(disputeButtons(), findsNothing);
      expect(find.text('Under review'), findsNothing);
    });

    testWidgets('an upheld dispute with no note shows only that the fine was kept', (tester) async {
      await _pumpLoans(tester, fines: MockFineRepository(fines: [
        _fine('f1', dispute: const FineDispute(status: DisputeStatus.upheld)),
      ]));

      expect(find.text('The library kept this fine.'), findsOneWidget);
      expect(disputeButtons(), findsNothing);
    });

    testWidgets('a paid or waived fine has no Dispute button', (tester) async {
      await _pumpLoans(tester, fines: MockFineRepository(fines: [
        ..._captured('fines_me_paid'),
        _fine('f2', item: 'Sapiens', amount: 0, was: 40, status: FineStatus.waived, note: 'Medical leave'),
        _fine('f3', item: 'Atomic Habits', status: FineStatus.unknown),
      ]));

      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Waived'), findsOneWidget);
      expect(disputeButtons(), findsNothing);
      expect(find.text('Under review'), findsNothing);
    });

    testWidgets('a closed dispute never brings the button back, and repeats nothing the fine already says', (tester) async {
      // The adjusted fine the backend captured: its dispute closed with the adjustment.
      await _pumpLoans(tester, fines: MockFineRepository(fines: [
        ..._captured('fines_me_adjusted'),
        _fine('f2', item: 'Sapiens', amount: 0, was: 40, status: FineStatus.waived, note: 'Medical leave',
            dispute: const FineDispute(status: DisputeStatus.waived, note: 'Medical leave')),
        // A dispute status this version does not know shows nothing, and is still a dispute.
        _fine('f3', item: 'Atomic Habits', dispute: const FineDispute(status: DisputeStatus.unknown, note: 'A later reply.')),
      ]));

      expect(disputeButtons(), findsNothing);
      expect(find.text('Under review'), findsNothing);
      expect(find.text('The library kept this fine.'), findsNothing);
      expect(find.text('A later reply.'), findsNothing);
      // The outcome reads from the fine itself, once each.
      expect(find.text('Library note: Returned during exam week'), findsOneWidget);
      expect(find.text('Library note: Medical leave'), findsOneWidget);
      expect(find.text('Medical leave'), findsNothing);
      expect(find.text('Adjusted'), findsOneWidget);
      expect(find.text('Waived'), findsOneWidget);
    });
  });

  group('the Library notices section', () {
    // The accent colour the escalation is drawn in, from the theme the screen runs under.
    Color accent(WidgetTester tester) => Theme.of(tester.element(find.byType(LoansScreen))).colorScheme.primary;

    Color? titleColour(WidgetTester tester, String title) => tester.widget<Text>(find.text(title)).style?.color;

    testWidgets("shows each notice's title, body and date, above the requests", (tester) async {
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await _pumpLoans(
        tester,
        notices: MockNoticeRepository(notices: [
          _notice('n1', title: 'Your fine stands', body: 'The library kept your ₹30 fine for Sapiens.', kind: NoticeKind.disputeOutcome, createdAt: yesterday),
          _notice('n2', createdAt: threeDaysAgo),
        ]),
        borrowRequests: MockBorrowRequestRepository(MockBookRepository(), requests: [_request('br-3', 'b12', 'Atomic Habits', BorrowRequestStatus.pending)]),
      );

      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('Your fine stands'), findsOneWidget);
      expect(find.text('The library kept your ₹30 fine for Sapiens.'), findsOneWidget);
      expect(find.text('${yesterday.day} ${_months[yesterday.month - 1]} ${yesterday.year}'), findsOneWidget);
      expect(find.text('Overdue book reminder'), findsOneWidget);
      expect(find.text('Your copy of Operating System Concepts is 3 days overdue.'), findsOneWidget);
      expect(find.text('${threeDaysAgo.day} ${_months[threeDaysAgo.month - 1]} ${threeDaysAgo.year}'), findsOneWidget);
      // The title is the bold line.
      expect(tester.widget<Text>(find.text('Your fine stands')).style?.fontWeight, FontWeight.bold);

      // Above the requests, and so above everything else on the screen.
      expect(find.text('Requests'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Library notices')).dy, lessThan(tester.getTopLeft(find.text('Requests')).dy));
      expect(tester.getTopLeft(find.text('Library notices')).dy, lessThan(tester.getTopLeft(find.text('On loan')).dy));
    });

    testWidgets('an escalation uses the accent style', (tester) async {
      await _pumpLoans(tester, notices: MockNoticeRepository(notices: [
        _notice('n1', kind: NoticeKind.overdueEscalation, title: 'Formal overdue notice', body: 'Operating System Concepts is now 5 days overdue.'),
        _notice('n2'),
      ]));

      expect(titleColour(tester, 'Formal overdue notice'), accent(tester));
      // A reminder is drawn in the default colour.
      expect(titleColour(tester, 'Overdue book reminder'), isNot(accent(tester)));
    });

    testWidgets('a notice of a kind this version does not know still shows its title and body', (tester) async {
      await _pumpLoans(tester, notices: MockNoticeRepository(notices: [
        _notice('n1', kind: NoticeKind.unknown, title: 'A new sort of notice', body: 'Something the library wants you to read.'),
      ]));

      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('A new sort of notice'), findsOneWidget);
      expect(find.text('Something the library wants you to read.'), findsOneWidget);
      expect(titleColour(tester, 'A new sort of notice'), isNot(accent(tester)));
    });

    testWidgets('hidden when there are none and while loading', (tester) async {
      await _pumpLoans(tester);
      expect(find.text('Library notices'), findsNothing);
      expect(find.text('On loan'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      final notices = _GatedNotices()
        ..served = [_notice('n1')]
        ..gate = Completer<void>();
      await _pumpLoans(tester, notices: notices);
      // The loans are on screen; the notices are still on their way.
      expect(find.text('On loan'), findsOneWidget);
      expect(find.text('Library notices'), findsNothing);
      expect(find.text('Overdue book reminder'), findsNothing);

      notices.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('Overdue book reminder'), findsOneWidget);
    });

    testWidgets('a list that cannot be loaded shows nothing, not even an error, and leaves the loans alone', (tester) async {
      final notices = _GatedNotices()..failing = true;
      await _pumpLoans(tester, notices: notices);

      expect(find.text('Library notices'), findsNothing);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('The library server had a problem.'), findsNothing);
      expect(find.text('On loan'), findsOneWidget);
      expect(find.text('Renew'), findsWidgets);
      expect(find.text('Fine: ₹30.0 and counting'), findsOneWidget);
      expect(find.text("Couldn't load your loans"), findsNothing);
    });

    testWidgets('a student with only notices sees them, not the empty state', (tester) async {
      await _pumpLoans(tester, loans: _NoLoans(), notices: MockNoticeRepository(notices: [
        _notice('n1', kind: NoticeKind.reportOutcome, title: 'Thanks for the report', body: 'Thanks for reporting a problem with Sapiens.'),
      ]));

      expect(find.text('No active loans'), findsNothing);
      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('Thanks for the report'), findsOneWidget);
    });

    testWidgets('the empty state waits for the notices to arrive, and shows when they fail', (tester) async {
      final notices = _GatedNotices()
        ..served = [_notice('n1', title: 'Your fine was waived', kind: NoticeKind.disputeOutcome)]
        ..gate = Completer<void>();
      await _pumpLoans(tester, loans: _NoLoans(), notices: notices);
      expect(find.text('No active loans'), findsNothing);

      notices.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Your fine was waived'), findsOneWidget);
      expect(find.text('No active loans'), findsNothing);

      // Secondary: a list that cannot be loaded does not hide the empty state for good.
      await tester.pumpWidget(const SizedBox());
      await _pumpLoans(tester, loans: _NoLoans(), notices: _GatedNotices()..failing = true);
      expect(find.text('No active loans'), findsOneWidget);
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

    testWidgets('a return refused because the loan was closed elsewhere refreshes the fines', (tester) async {
      // A librarian marked the copy lost: the overdue fine and the replacement
      // fine were written, and the refusal is the student's first sign of it.
      final fines = _CountingFines();
      await _pumpLoans(tester, loans: _ClosedElsewhere(fines, _closedBecauseLost), fines: fines, confirmDialogs: true);
      expect(find.text('No fines.'), findsOneWidget);

      await tester.tap(overdueLoan(TextButton, 'Return'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Return'));
      await tester.pumpAndSettle();

      expect(find.text('This loan was closed because the copy was marked lost.'), findsOneWidget);
      expect(fines.fetches, 2);
      expect(find.text('Outstanding: ₹300'), findsOneWidget);
      expect(find.textContaining('Lost book'), findsOneWidget);
      expect(find.text('No fines.'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a return refused because it was already returned elsewhere refreshes the fines', (tester) async {
      // Returned late on another device, which wrote the overdue fine.
      final fines = _CountingFines();
      await _pumpLoans(
        tester,
        loans: _ClosedElsewhere(fines, const ConflictException('This loan has already been returned.')),
        fines: fines,
        confirmDialogs: true,
      );

      await tester.tap(overdueLoan(TextButton, 'Return'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Return'));
      await tester.pumpAndSettle();

      expect(find.text('This loan has already been returned.'), findsOneWidget);
      expect(fines.fetches, 2);
      expect(find.text('Outstanding: ₹300'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a return that fails on the network does not refresh the fines', (tester) async {
      final fines = _CountingFines();
      await _pumpLoans(tester, loans: _ClosedElsewhere(fines, _offline), fines: fines, confirmDialogs: true);

      await tester.tap(overdueLoan(TextButton, 'Return'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Return'));
      await tester.pumpAndSettle();

      expect(find.text(ApiException.networkMessage), findsOneWidget);
      expect(fines.fetches, 1); // nothing is known to have changed
      expect(find.text('No fines.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a renewal refused because the loan was closed elsewhere refreshes the fines', (tester) async {
      final fines = _CountingFines();
      await _pumpLoans(tester, loans: _ClosedElsewhere(fines, _closedBecauseLost), fines: fines);
      expect(find.text('No fines.'), findsOneWidget);

      await tester.tap(overdueLoan(OutlinedButton, 'Renew'));
      await tester.pumpAndSettle();

      expect(find.text('This loan was closed because the copy was marked lost.'), findsOneWidget);
      expect(fines.fetches, 2);
      expect(find.text('Outstanding: ₹300'), findsOneWidget);
      expect(find.text('No fines.'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a renewal that fails on the network does not refresh the fines', (tester) async {
      final fines = _CountingFines();
      await _pumpLoans(tester, loans: _ClosedElsewhere(fines, _offline), fines: fines);

      await tester.tap(overdueLoan(OutlinedButton, 'Renew'));
      await tester.pumpAndSettle();

      expect(find.text(ApiException.networkMessage), findsOneWidget);
      expect(fines.fetches, 1);
      expect(find.text('No fines.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('after one student logs out and another logs in', () {
    // The providers outlive the screen, which closes at logout and opens again for
    // the next student. Their lists are fetched again, but Riverpod keeps the last
    // student's list on the loading state, so a screen drawing `.value` shows it
    // until the new student's answer arrives.
    Future<ProviderContainer> openAsFirstStudent(
      WidgetTester tester, {
      LoanRepository? loans,
      MockFineRepository? fines,
      MockNoticeRepository? notices,
      MockWaitlistRepository? waitlist,
      MockBorrowRequestRepository? borrowRequests,
      // Riverpod retries a failed fetch for about 40 seconds, showing it as a
      // loading state; a test about a fetch that has finally failed turns that off.
      bool retries = true,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 3000);
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        retry: retries ? null : (_, __) => null,
        overrides: mockRepositoryOverrides(
          auth: _InstantAuth(), loans: loans, fines: fines, notices: notices, waitlist: waitlist, borrowRequests: borrowRequests,
        ),
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).login('aditi.sharma@thapar.edu', 'anything');
      await _showMyLoans(tester, container);
      await tester.pumpAndSettle();
      return container;
    }

    // The first student logs out (which closes the screen), the next logs in and
    // opens My Loans. Whatever the test gated is still on its way.
    Future<void> openAsNextStudent(WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(const SizedBox());
      final auth = container.read(authControllerProvider.notifier);
      await auth.logOut();
      await auth.login('second@thapar.edu', 'anything');
      await _showMyLoans(tester, container);
      await tester.pumpAndSettle();
    }

    testWidgets("does not show the last student's fines, amounts or library notes while the next student's load", (tester) async {
      final fines = _GatedFines()
        ..served = [_fine('a1', item: 'Algorithms Unlocked', amount: 75, note: 'Waived pending the exam board')];
      final container = await openAsFirstStudent(tester, fines: fines);
      expect(find.text('Algorithms Unlocked'), findsOneWidget);
      expect(find.text('Outstanding: ₹75'), findsOneWidget);
      expect(find.text('Library note: Waived pending the exam board'), findsOneWidget);

      fines.served = [_fine('b1', item: 'Sapiens', amount: 20)];
      fines.gate = Completer<void>();
      await openAsNextStudent(tester, container);

      // The loans have arrived, so this is the window where the fines have not.
      expect(find.text('On loan'), findsOneWidget);
      expect(find.text('Fines'), findsOneWidget);
      expect(find.text('Algorithms Unlocked'), findsNothing);
      expect(find.text('₹75'), findsNothing);
      expect(find.textContaining('Outstanding'), findsNothing);
      expect(find.textContaining('Library note'), findsNothing);
      expect(find.text('No fines.'), findsNothing);
      expect(find.byType(LoadingSkeleton), findsOneWidget);

      fines.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sapiens'), findsOneWidget);
      expect(find.text('Outstanding: ₹20'), findsOneWidget);
      expect(find.text('Algorithms Unlocked'), findsNothing);
    });

    testWidgets("does not show the last student's fines error while the next student's load", (tester) async {
      final fines = _GatedFines()..failing = true;
      final container = await openAsFirstStudent(tester, fines: fines, retries: false);
      expect(find.text("Couldn't load your fines."), findsOneWidget);

      fines.failing = false;
      fines.served = [_fine('b1', item: 'Sapiens', amount: 20)];
      fines.gate = Completer<void>();
      await openAsNextStudent(tester, container);

      expect(find.text('On loan'), findsOneWidget);
      expect(find.text("Couldn't load your fines."), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(LoadingSkeleton), findsOneWidget);

      fines.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sapiens'), findsOneWidget);
    });

    testWidgets("says the fines could not be loaded, not the last student's fines, when the next student's fetch fails", (tester) async {
      // Riverpod keeps the last student's value beside the error, too.
      final fines = _GatedFines()..served = [_fine('a1', item: 'Algorithms Unlocked', amount: 75, note: 'Waived pending the exam board')];
      final container = await openAsFirstStudent(tester, fines: fines, retries: false);
      expect(find.text('Algorithms Unlocked'), findsOneWidget);

      fines.failing = true;
      await openAsNextStudent(tester, container);

      expect(find.text('On loan'), findsOneWidget);
      expect(find.text("Couldn't load your fines."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Algorithms Unlocked'), findsNothing);
      expect(find.textContaining('Outstanding'), findsNothing);
      expect(find.textContaining('Library note'), findsNothing);

      // Retry asks again, and the next student's own fines show.
      fines.failing = false;
      fines.served = [_fine('b1', item: 'Sapiens', amount: 20)];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Sapiens'), findsOneWidget);
      expect(find.text('Algorithms Unlocked'), findsNothing);
    });

    testWidgets("does not show the last student's fines while the next student's fetch is being retried", (tester) async {
      // Riverpod retries a failed fetch, and shows the retry as a loading state
      // holding both the new error and the last student's value. The error is the
      // next student's, so it shows at once, as for any failed load.
      final fines = _GatedFines()..served = [_fine('a1', item: 'Algorithms Unlocked', amount: 75)];
      final container = await openAsFirstStudent(tester, fines: fines);
      expect(find.text('Algorithms Unlocked'), findsOneWidget);

      fines.failing = true;
      await openAsNextStudent(tester, container);

      expect(find.text('On loan'), findsOneWidget);
      expect(find.text("Couldn't load your fines."), findsOneWidget);
      expect(find.text('Algorithms Unlocked'), findsNothing);
      expect(find.textContaining('Outstanding'), findsNothing);

      // Once the retries run out the error is final, and still not their value.
      await tester.pump(const Duration(minutes: 1));
      expect(find.text("Couldn't load your fines."), findsOneWidget);
      expect(find.text('Algorithms Unlocked'), findsNothing);
      expect(find.textContaining('Outstanding'), findsNothing);
    });

    testWidgets("a different student never sees the previous student's notices while theirs load", (tester) async {
      final notices = _GatedNotices()..served = [_notice('a1', title: 'Formal overdue notice', kind: NoticeKind.overdueEscalation, body: 'Algorithms Unlocked is now 5 days overdue.')];
      final container = await openAsFirstStudent(tester, notices: notices);
      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('Formal overdue notice'), findsOneWidget);
      expect(find.text('Algorithms Unlocked is now 5 days overdue.'), findsOneWidget);

      notices.served = [_notice('b1', title: 'Your fine was waived', kind: NoticeKind.disputeOutcome, body: 'The library waived the ₹30 fine for Sapiens.')];
      notices.gate = Completer<void>();
      await openAsNextStudent(tester, container);

      // The loans have arrived, so this is the window where the notices have not.
      expect(find.text('On loan'), findsOneWidget);
      expect(find.text('Library notices'), findsNothing);
      expect(find.text('Formal overdue notice'), findsNothing);
      expect(find.text('Algorithms Unlocked is now 5 days overdue.'), findsNothing);

      notices.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('Your fine was waived'), findsOneWidget);
      expect(find.text('Formal overdue notice'), findsNothing);
    });

    testWidgets("shows no notices, not the last student's, when the next student's fetch fails", (tester) async {
      // Riverpod keeps the last student's value beside the error, too.
      final notices = _GatedNotices()..served = [_notice('a1', title: 'Formal overdue notice', kind: NoticeKind.overdueEscalation)];
      final container = await openAsFirstStudent(tester, notices: notices, retries: false);
      expect(find.text('Formal overdue notice'), findsOneWidget);

      notices.failing = true;
      await openAsNextStudent(tester, container);

      expect(find.text('On loan'), findsOneWidget);
      expect(find.text('Library notices'), findsNothing);
      expect(find.text('Formal overdue notice'), findsNothing);
      expect(find.textContaining("Couldn't load"), findsNothing);
    });

    testWidgets("does not show the last student's notices while the next student's fetch is being retried", (tester) async {
      final notices = _GatedNotices()..served = [_notice('a1', title: 'Formal overdue notice', kind: NoticeKind.overdueEscalation)];
      final container = await openAsFirstStudent(tester, notices: notices);
      expect(find.text('Formal overdue notice'), findsOneWidget);

      notices.failing = true;
      await openAsNextStudent(tester, container);

      expect(find.text('Library notices'), findsNothing);
      expect(find.text('Formal overdue notice'), findsNothing);

      // Once the retries run out the error is final, and still not their value.
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Library notices'), findsNothing);
      expect(find.text('Formal overdue notice'), findsNothing);
    });

    testWidgets("does not show the last student's waitlist or requests when the next student's fetches fail", (tester) async {
      final waitlist = _GatedWaitlist()
        ..served = [const Reservation(id: 'res-b2', bookId: 'b2', status: ReservationStatus.waiting, queuePosition: 3)];
      final requests = _GatedRequests()..served = [_request('br-3', 'b12', 'Atomic Habits', BorrowRequestStatus.pending)];
      final container = await openAsFirstStudent(tester, waitlist: waitlist, borrowRequests: requests, retries: false);
      expect(find.text('#3 in line'), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);

      waitlist.failing = true;
      requests.failing = true;
      await openAsNextStudent(tester, container);

      expect(find.text('On loan'), findsOneWidget);
      expect(find.text('Waitlist'), findsNothing);
      expect(find.text('#3 in line'), findsNothing);
      expect(find.text('Requests'), findsNothing);
      expect(find.text('Cancel request'), findsNothing);
    });

    testWidgets("does not show the empty state while the next student's fines are on their way", (tester) async {
      // The first student has nothing at all, so they see the empty state. The
      // next student owes a fine, which is still loading: "known to be empty"
      // must not be read off the first student's empty list.
      final fines = _GatedFines();
      final container = await openAsFirstStudent(tester, loans: _NoLoans(), fines: fines);
      expect(find.text('No active loans'), findsOneWidget);

      fines.served = [_fine('b1', item: 'Sapiens', amount: 20)];
      fines.gate = Completer<void>();
      await openAsNextStudent(tester, container);

      expect(find.text('No active loans'), findsNothing);
      expect(find.text('Browse the catalog'), findsNothing);
      expect(find.text('Fines'), findsOneWidget);

      fines.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sapiens'), findsOneWidget);
      expect(find.text('No active loans'), findsNothing);
    });

    testWidgets("a different student never sees the previous student's dispute state", (tester) async {
      final fines = _GatedFines()
        ..served = [
          _fine('a1', item: 'Algorithms Unlocked', dispute: const FineDispute(status: DisputeStatus.open)),
          _fine('a2', item: 'Compilers', dispute: const FineDispute(status: DisputeStatus.upheld, note: 'The scan log shows it came back late.')),
          _fine('a3', item: 'Databases'),
        ];
      final container = await openAsFirstStudent(tester, fines: fines);
      expect(find.text('Under review'), findsOneWidget);
      expect(find.text('The library kept this fine.'), findsOneWidget);
      expect(find.text('The scan log shows it came back late.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Dispute'), findsOneWidget);

      fines.served = [_fine('b1', item: 'Sapiens', amount: 20)];
      fines.gate = Completer<void>();
      await openAsNextStudent(tester, container);

      // Their fines are on the way: nothing of the last student's disputes shows, and
      // neither does a button that would act on the last student's fine.
      expect(find.text('Fines'), findsOneWidget);
      expect(find.text('Under review'), findsNothing);
      expect(find.text('The library kept this fine.'), findsNothing);
      expect(find.text('The scan log shows it came back late.'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Dispute'), findsNothing);
      expect(find.byType(LoadingSkeleton), findsOneWidget);

      fines.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sapiens'), findsOneWidget);
      expect(find.text('Under review'), findsNothing);
      expect(find.text('The library kept this fine.'), findsNothing);
      // Their own fine has no dispute, so it offers one.
      expect(find.widgetWithText(TextButton, 'Dispute'), findsOneWidget);
    });

    testWidgets("shows no dispute state, not the last student's, when the next student's fetch fails", (tester) async {
      final fines = _GatedFines()
        ..served = [_fine('a1', item: 'Algorithms Unlocked', dispute: const FineDispute(status: DisputeStatus.open))];
      final container = await openAsFirstStudent(tester, fines: fines, retries: false);
      expect(find.text('Under review'), findsOneWidget);

      fines.failing = true;
      await openAsNextStudent(tester, container);

      expect(find.text("Couldn't load your fines."), findsOneWidget);
      expect(find.text('Under review'), findsNothing);
      expect(find.text('Algorithms Unlocked'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Dispute'), findsNothing);
    });

    testWidgets("does not show the last student's waitlist while the next student's loads", (tester) async {
      final waitlist = _GatedWaitlist()
        ..served = [const Reservation(id: 'res-b2', bookId: 'b2', status: ReservationStatus.waiting, queuePosition: 3)];
      final container = await openAsFirstStudent(tester, waitlist: waitlist);
      expect(find.text('Waitlist'), findsOneWidget);
      expect(find.text('#3 in line'), findsOneWidget);

      waitlist.served = [const Reservation(id: 'res-b5', bookId: 'b5', status: ReservationStatus.waiting, queuePosition: 1)];
      waitlist.gate = Completer<void>();
      await openAsNextStudent(tester, container);

      expect(find.text('On loan'), findsOneWidget);
      expect(find.text('Waitlist'), findsNothing);
      expect(find.text('#3 in line'), findsNothing);

      waitlist.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Waitlist'), findsOneWidget);
      expect(find.text('#1 in line'), findsOneWidget);
      expect(find.text('#3 in line'), findsNothing);
    });

    testWidgets("does not show the last student's requests while the next student's load", (tester) async {
      final requests = _GatedRequests()
        ..served = [_request('br-3', 'b12', 'Atomic Habits', BorrowRequestStatus.pending)];
      final container = await openAsFirstStudent(tester, borrowRequests: requests);
      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);

      requests.served = [_request('br-9', 'b11', 'Sapiens', BorrowRequestStatus.expired)];
      requests.gate = Completer<void>();
      await openAsNextStudent(tester, container);

      expect(find.text('On loan'), findsOneWidget);
      expect(find.text('Requests'), findsNothing);
      expect(find.text('Atomic Habits'), findsNothing);
      expect(find.text('Cancel request'), findsNothing);

      requests.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Expired — no librarian approved it in time'), findsOneWidget);
      expect(find.text('Atomic Habits'), findsNothing);
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

    testWidgets('opening My Loans refetches the notices once', (tester) async {
      // Loaded earlier, so it can predate a reminder or an outcome the library wrote
      // while the student was elsewhere.
      final notices = _CountingNotices(notices: [_notice('n1')]);
      final container = ProviderContainer(overrides: mockRepositoryOverrides(notices: notices));
      addTearDown(container.dispose);
      await container.read(noticesControllerProvider.future);
      expect(notices.fetches, 1);

      notices.notices = [_notice('n2', kind: NoticeKind.overdueEscalation, title: 'Formal overdue notice'), _notice('n1')];
      await open(tester, container);

      expect(notices.fetches, 2);
      expect(find.text('Formal overdue notice'), findsOneWidget);

      // Each visit builds a new screen, so the next one asks again.
      await tester.pumpWidget(const SizedBox());
      await open(tester, container);
      expect(notices.fetches, 3);
    });

    testWidgets('a failed quiet refresh of the notices on open keeps them on screen', (tester) async {
      final notices = _CountingNotices(notices: [_notice('n1')]);
      final container = ProviderContainer(overrides: mockRepositoryOverrides(notices: notices));
      addTearDown(container.dispose);
      await container.read(noticesControllerProvider.future);

      notices.offline = true;
      await open(tester, container);

      expect(notices.fetches, 2); // it did ask, and the ask failed
      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('Overdue book reminder'), findsOneWidget);
    });

    testWidgets('opening it before the notices have loaded does not fetch a second time', (tester) async {
      final notices = _CountingNotices(notices: [_notice('n1')]);
      await _pumpLoans(tester, notices: notices);

      expect(find.text('Overdue book reminder'), findsOneWidget);
      expect(notices.fetches, 1); // the load is the fresh fetch
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
