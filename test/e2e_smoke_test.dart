// test/e2e_smoke_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/router/app_router.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';

void main() {
  testWidgets('login, borrow a book, recover from a booking conflict, see the booking land', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildSmartLibTheme(),
        routerConfig: container.read(routerProvider),
      ),
    ));
    await tester.pumpAndSettle();

    // Log in as the seeded demo account.
    await tester.enterText(find.byType(TextField).first, 'aditi.sharma@thapar.edu');
    await tester.enterText(find.byType(TextField).at(1), 'anything');
    await tester.tap(find.text('Log in').last);
    await tester.pumpAndSettle();

    // Home -> Search -> open a book that's currently available -> borrow it.
    await tester.tap(find.text('Search').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Atomic Habits');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Atomic Habits'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrow this copy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Borrowed'), findsOneWidget);

    // Loans now shows it.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Loans').first);
    await tester.pumpAndSettle();
    expect(find.text('Atomic Habits'), findsOneWidget);

    // Start a new booking, pick the scripted conflict slot, confirm.
    await tester.tap(find.text('Bookings').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5:00 PM').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();

    // The conflict-recovery screen appears — pick the first alternative and confirm again.
    expect(find.text('That slot was just taken'), findsOneWidget);
    await tester.tap(find.text('Reading Room A · Desk 12').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();
    expect(find.text('Booked'), findsOneWidget);

    // Back in My Bookings, the new booking is there.
    await tester.tap(find.text('View My Bookings'));
    await tester.pumpAndSettle();
    expect(find.text('Reading Room A · Desk 12'), findsOneWidget);

    container.dispose();
  });
}
