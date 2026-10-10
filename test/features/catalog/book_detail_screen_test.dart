// test/features/catalog/book_detail_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/features/catalog/book_detail_screen.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/waitlist/waitlist_repository.dart';
import 'package:smartlib_frontend/models/book.dart';
import 'package:smartlib_frontend/models/loan.dart';
import 'package:smartlib_frontend/models/reservation.dart';
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

  /// Book ids passed to createLoan, in call order.
  final createdFor = <String>[];

  /// When set, createLoan fails with this instead.
  Object? refuseWith;

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
    createdFor.add(bookId);
    if (refuseWith != null) throw refuseWith!;
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

/// b9 with its one shelf copy held for a student on the waitlist.
class _HeldCopyBookRepository extends MockBookRepository {
  @override
  Future<Book?> getById(String id) async => const Book(
      id: 'b9', title: 'The Midnight Library', author: 'Matt Haig', genre: 'Fiction', description: 'd',
      totalCopies: 2, availableCopies: 1, heldCopies: 1, waitlistCount: 0);
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

  testWidgets('borrowing flips the button to the Borrowed state, creating exactly one loan', (tester) async {
    // Borrowing used to go through both the book and the loan repository,
    // which are the same POST /loans -- so the real server saw a second
    // borrow and refused it as a 409.
    final loans = _CleanLoanRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: loans),
      child: MaterialApp(
        theme: buildSmartLibTheme(),
        home: const BookDetailScreen(bookId: 'b1'),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrow this copy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Borrowed'), findsOneWidget);
    expect(loans.createdFor, ['b1']);
  });

  testWidgets('an unavailable book shows the waitlist copy and Join Waitlist button', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(), child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b2'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('2 people ahead of you on the waitlist.'), findsOneWidget);
    expect(find.text('Join Waitlist'), findsOneWidget);
  });

  testWidgets('a refused borrow says why, and the button does not claim it worked', (tester) async {
    final loans = _CleanLoanRepository()..refuseWith = const ConflictException('No available copies right now.');
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(loans: loans),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookDetailScreen(bookId: 'b1')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrow this copy'));
    await tester.pump();
    await tester.pump();

    expect(find.text('No available copies right now.'), findsOneWidget);
    expect(find.textContaining('Borrowed'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
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

    testWidgets('a copy held for you says until when, and Borrow claims it', (tester) async {
      // Nobody else can borrow it, so it's the one case where Borrow shows
      // even though the shelf copy is held.
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

      await tester.tap(find.text('Borrow this copy'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Borrowed'), findsOneWidget);
    });

    testWidgets("copies held for other students aren't offered -- it's Join Waitlist instead", (tester) async {
      // The server refuses anyone but the claimant, so a Borrow button here
      // could only ever fail.
      await tester.pumpWidget(ProviderScope(
        overrides: mockRepositoryOverrides(loans: _CleanLoanRepository(), books: _HeldCopyBookRepository()),
        child: MaterialApp(theme: buildSmartLibTheme(), home: const BookDetailScreen(bookId: 'b9')),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Borrow this copy'), findsNothing);
      expect(find.text('Every copy on the shelf is held for a student on the waitlist.'), findsOneWidget);
      expect(find.text('Join Waitlist'), findsOneWidget);
    });
  });
}
