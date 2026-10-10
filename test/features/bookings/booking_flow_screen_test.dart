// test/features/bookings/booking_flow_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/clock.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/bookings/booking_flow_screen.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import '../../support/mock_overrides.dart';

/// Every booking is refused, with nothing else free to suggest.
class _NoAlternativesRepository extends MockBookingRepository {
  @override
  Future<ResourceBooking> createBooking({required Resource resource, required DateTime start, required DateTime end}) async =>
      throw BookingConflictException(const []);
}

/// The slot passed while the user sat on the confirm screen.
class _SlotPassedRepository extends MockBookingRepository {
  @override
  Future<ResourceBooking> createBooking({required Resource resource, required DateTime start, required DateTime end}) async =>
      throw const ApiException(400, 'That time slot has already passed. Pick a later one.');
}

void main() {
  testWidgets('picking a free slot and confirming shows the Booked success screen', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(), child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookingFlowScreen(),
    )));
    await tester.pumpAndSettle();
    // Tomorrow, so the test doesn't depend on the time of day: today's
    // morning slots grey out once they've passed.
    await tester.tap(find.byKey(const Key('dateChip-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9:00 AM').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();
    expect(find.text('Booked'), findsOneWidget);
  });

  testWidgets('room type 2+ days out shows the no-rooms-free empty state', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(), child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookingFlowScreen(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rooms'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dateChip-2')));
    await tester.pumpAndSettle();
    expect(find.text('No rooms free on this date'), findsOneWidget);
  });

  testWidgets('a conflict with nothing else free says so, instead of an empty list', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(bookings: _NoAlternativesRepository()), child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookingFlowScreen(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dateChip-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9:00 AM').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();

    expect(find.text('That slot was just taken'), findsOneWidget);
    expect(find.text("Nothing similar is free right now. Try another time or day."), findsOneWidget);
    expect(find.textContaining("Here's what's still open"), findsNothing);
  });

  testWidgets("today's slots grey out once their check-in window has closed", (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...mockRepositoryOverrides(),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 10, 12, 10)),
      ],
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookingFlowScreen()),
    ));
    await tester.pumpAndSettle();

    // 9-11 AM are over; the 12 PM window is open until 12:15.
    expect(find.widgetWithText(ChoiceChip, '9:00 AM'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '11:00 AM'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '12:00 PM'), findsWidgets);

    await tester.tap(find.byKey(const Key('dateChip-1')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '9:00 AM'), findsWidgets);
  });

  testWidgets('a refusal on confirm says why and stays on the confirm screen', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(bookings: _SlotPassedRepository()),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookingFlowScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dateChip-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9:00 AM').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pump();
    await tester.pump();

    expect(find.text('That time slot has already passed. Pick a later one.'), findsOneWidget);
    expect(find.text('Confirm your booking'), findsOneWidget);
    expect(find.text('Booked'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });
}
