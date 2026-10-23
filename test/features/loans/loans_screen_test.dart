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
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/loans/loans_screen.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/waitlist/waitlist_repository.dart';
import 'package:smartlib_frontend/models/borrow_request.dart';
import 'package:smartlib_frontend/models/loan.dart';
import 'package:smartlib_frontend/models/reservation.dart';
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
}
