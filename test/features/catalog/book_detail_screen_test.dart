// test/features/catalog/book_detail_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/features/borrow_requests/borrow_request_repository.dart';
import 'package:smartlib_frontend/features/catalog/book_detail_screen.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/waitlist/waitlist_repository.dart';
import 'package:smartlib_frontend/models/book.dart';
import 'package:smartlib_frontend/models/borrow_request.dart';
import 'package:smartlib_frontend/models/loan.dart';
import 'package:smartlib_frontend/models/reservation.dart';
import '../../support/mock_overrides.dart';

/// The demo student's loans without b1, so b1 can be requested.
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
  Future<Loan> renew(String loanId) async => _loans.firstWhere((l) => l.id == loanId);

  @override
  Future<void> returnLoan(String loanId) async => _loans.removeWhere((l) => l.id == loanId);

  /// Stands in for a librarian approving: the request becomes this loan.
  void approve(String bookId) => _loans.insert(
        0,
        Loan(id: 'loan-$bookId', bookId: bookId, dueDate: DateTime.now().add(const Duration(days: 14)), status: LoanStatus.normal, fineAmount: 0, canRenew: true),
      );
}

/// The mock, recording what was requested and refusing on demand.
class _Requests extends MockBorrowRequestRepository {
  _Requests({super.requests}) : super(MockBookRepository());

  final createdFor = <String>[];
  Object? refuseWith;

  @override
  Future<BorrowRequest> create(String bookId) async {
    createdFor.add(bookId);
    if (refuseWith != null) throw refuseWith!;
    return super.create(bookId);
  }
}

BorrowRequest _answered(BorrowRequestStatus status, {String? reason}) {
  final requestedAt = DateTime.now().subtract(const Duration(hours: 3));
  return BorrowRequest(
    id: 'br-old', bookId: 'b1', bookTitle: 'Introduction to Algorithms', status: status,
    requestedAt: requestedAt, expiresAt: requestedAt.add(const Duration(hours: 24)),
    decidedAt: requestedAt.add(const Duration(hours: 1)), declineReason: reason,
  );
}

/// b1 with one free copy: a request takes it off the shelf, an answer puts it back.
class _LastCopyShelf extends MockBookRepository {
  int available = 1;

  @override
  Future<Book?> getById(String id) async => Book(
      id: 'b1', title: 'Atomic Habits', author: 'James Clear', genre: 'Self-help', description: 'd',
      totalCopies: 4, availableCopies: available, heldCopies: 0, waitlistCount: 0);
}

class _LastCopyRequests extends MockBorrowRequestRepository {
  _LastCopyRequests(this._shelf) : super(_shelf);

  final _LastCopyShelf _shelf;

  @override
  Future<BorrowRequest> create(String bookId) async {
    _shelf.available = 0;
    return super.create(bookId);
  }

  @override
  void decide(String bookId, BorrowRequestStatus status, {String? reason}) {
    _shelf.available = 1;
    super.decide(bookId, status, reason: reason);
  }
}

/// The mock, with the server's answer to a cancel held back until [release].
class _SlowCancel extends MockBorrowRequestRepository {
  _SlowCancel() : super(MockBookRepository());

  final release = Completer<void>();
  int cancels = 0;

  @override
  Future<void> cancel(String requestId) async {
    cancels++;
    await release.future;
    return super.cancel(requestId);
  }
}

/// b9 with its one shelf copy held for a student on the waitlist.
class _HeldCopyBookRepository extends MockBookRepository {
  @override
  Future<Book?> getById(String id) async => const Book(
      id: 'b9', title: 'The Midnight Library', author: 'Matt Haig', genre: 'Fiction', description: 'd',
      totalCopies: 2, availableCopies: 1, heldCopies: 1, waitlistCount: 0);
}

void main() {
  testWidgets('an available book offers Request to borrow and its copy count', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: _CleanLoanRepository()),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 copies available'), findsOneWidget);
    expect(find.text('Request to borrow'), findsOneWidget);
  });

  testWidgets('requesting shows the pending state with its deadline, after exactly one request', (tester) async {
    final requests = _Requests();
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: _CleanLoanRepository(), borrowRequests: requests),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookDetailScreen(bookId: 'b1')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request to borrow'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Requested — waiting for a librarian. Expires tomorrow, '), findsOneWidget);
    expect(find.text('Cancel request'), findsOneWidget);
    expect(find.text('Request sent. A librarian will review it soon.'), findsOneWidget);
    expect(requests.createdFor, ['b1']);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a refused request says why, and does not claim it was sent', (tester) async {
    final requests = _Requests()..refuseWith = const ConflictException('No available copies right now.');
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: _CleanLoanRepository(), borrowRequests: requests),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookDetailScreen(bookId: 'b1')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request to borrow'));
    await tester.pump();
    await tester.pump();

    expect(find.text('No available copies right now.'), findsOneWidget);
    expect(find.textContaining('Requested —'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Cancel request withdraws it', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: _CleanLoanRepository()),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookDetailScreen(bookId: 'b1')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request to borrow'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();

    expect(find.text('Request cancelled.'), findsOneWidget);
    expect(find.text('Request to borrow'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Cancel request is off while the cancel is in flight, so a second tap cannot send a second one', (tester) async {
    final requests = _SlowCancel();
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: _CleanLoanRepository(), borrowRequests: requests),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookDetailScreen(bookId: 'b1')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request to borrow'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Cancel request'));
    await tester.pump();

    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancel request')).onPressed, isNull);
    expect(requests.cancels, 1);

    requests.release.complete();
    await tester.pumpAndSettle();
    expect(find.text('Request cancelled.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('when the last free copy comes back after a decline, the re-check offers Request again, not the waitlist', (tester) async {
    final shelf = _LastCopyShelf();
    final requests = _LastCopyRequests(shelf);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(books: shelf, loans: _CleanLoanRepository(), borrowRequests: requests),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b1')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request to borrow'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Requested —'), findsOneWidget);

    requests.decide('b1', BorrowRequestStatus.declined);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(find.text('Request again'), findsOneWidget);
    expect(find.text('Join Waitlist'), findsNothing);
  });

  testWidgets('a declined request says why, and offers Request again', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(
        loans: _CleanLoanRepository(),
        borrowRequests: _Requests(requests: [_answered(BorrowRequestStatus.declined, reason: 'Reserved for a course')]),
      ),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Your request was declined: Reserved for a course'), findsOneWidget);
    expect(find.text('Request again'), findsOneWidget);
  });

  testWidgets('a decline without a reason says the library declined it', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(
        loans: _CleanLoanRepository(),
        borrowRequests: _Requests(requests: [_answered(BorrowRequestStatus.declined)]),
      ),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Your request was declined by the library.'), findsOneWidget);
  });

  testWidgets('an expired request says so, and offers Request again', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(
        loans: _CleanLoanRepository(),
        borrowRequests: _Requests(requests: [_answered(BorrowRequestStatus.expired)]),
      ),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Your request expired before a librarian approved it.'), findsOneWidget);
    expect(find.text('Request again'), findsOneWidget);
  });

  testWidgets('while a request waits, the page re-checks every 30 seconds and shows the loan once approved', (tester) async {
    final loans = _CleanLoanRepository();
    final requests = _Requests();
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: loans, borrowRequests: requests),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b1')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request to borrow'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Requested —'), findsOneWidget);

    loans.approve('b1');
    requests.decide('b1', BorrowRequestStatus.approved);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(find.text('Borrowed — see My Loans for the due date'), findsOneWidget);
  });

  testWidgets('an unavailable book shows the waitlist copy and Join Waitlist button', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(), child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b2'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('2 people ahead of you on the waitlist.'), findsOneWidget);
    expect(find.text('Join Waitlist'), findsOneWidget);
  });

  group('the waitlist', () {
    testWidgets('after joining, the screen shows your place in line -- and still does when you come back', (tester) async {
      // It used to forget as soon as you left the screen, and offer Join again.
      final container = ProviderContainer(overrides: mockRepositoryOverrides(loans: _CleanLoanRepository()));
      addTearDown(container.dispose);
      Widget app(Widget home) => UncontrolledProviderScope(
          container: container, child: MaterialApp(theme: buildSmartLibTheme(), home: home));

      await tester.pumpWidget(app(const BookDetailScreen(bookId: 'b2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join Waitlist'));
      await tester.pumpAndSettle();
      // b2 already has two students queued.
      expect(find.text("You're #3 in line."), findsOneWidget);

      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpWidget(app(const BookDetailScreen(bookId: 'b2')));
      await tester.pumpAndSettle();
      expect(find.text("You're #3 in line."), findsOneWidget);
      expect(find.text('Join Waitlist'), findsNothing);
    });

    testWidgets('Leave waitlist takes you out of the queue', (tester) async {
      final waitlist = MockWaitlistRepository(MockBookRepository(), reservations: const [
        Reservation(id: 'res-b2', bookId: 'b2', status: ReservationStatus.waiting, queuePosition: 3),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: mockRepositoryOverrides(loans: _CleanLoanRepository(), waitlist: waitlist),
        child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookDetailScreen(bookId: 'b2')),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave waitlist'));
      await tester.pumpAndSettle();

      expect(find.text("You've left the waitlist."), findsOneWidget);
      expect(find.text('Join Waitlist'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a copy held for you says until when, and Request to borrow asks for it', (tester) async {
      // Nobody else can take it, so it's the one case where the request button
      // shows even though the shelf copy is held.
      final waitlist = MockWaitlistRepository(MockBookRepository(), reservations: [
        Reservation(id: 'res-b9', bookId: 'b9', status: ReservationStatus.held, claimExpiresAt: DateTime.now().add(const Duration(hours: 30))),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: mockRepositoryOverrides(loans: _CleanLoanRepository(), books: _HeldCopyBookRepository(), waitlist: waitlist),
        child: MaterialApp(theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b9')),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('A copy is held for you until'), findsOneWidget);
      expect(find.text('Join Waitlist'), findsNothing);

      await tester.tap(find.text('Request to borrow'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Requested — waiting for a librarian'), findsOneWidget);
    });

    testWidgets("copies held for other students aren't offered -- it's Join Waitlist instead", (tester) async {
      // The server refuses anyone but the claimant, so a request button here
      // could only ever fail.
      await tester.pumpWidget(ProviderScope(
        overrides: mockRepositoryOverrides(loans: _CleanLoanRepository(), books: _HeldCopyBookRepository()),
        child: MaterialApp(theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b9')),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Request to borrow'), findsNothing);
      expect(find.text('Every copy on the shelf is held for a student on the waitlist.'), findsOneWidget);
      expect(find.text('Join Waitlist'), findsOneWidget);
    });
  });
}
