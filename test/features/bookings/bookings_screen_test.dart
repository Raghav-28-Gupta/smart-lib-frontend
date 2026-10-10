// test/features/bookings/bookings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/bookings/bookings_screen.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import '../../support/mock_overrides.dart';

class _RefusingCheckIn extends MockBookingRepository {
  @override
  Future<ResourceBooking> checkIn(String bookingId) async =>
      throw const ConflictException('The grace period for this booking has passed.');
}

void main() {
  testWidgets('shows the far-booking and in-window copy for the seeded bookings', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(), child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookingsScreen(),
    )));
    await tester.pumpAndSettle();
    // Check-in opens AT the start time, for 15 minutes (bookingService.ts
    // computeWindow) -- not before it.
    expect(find.textContaining('check-in opens at the start time'), findsOneWidget);
    expect(find.textContaining('Check in within'), findsOneWidget);
  });

  testWidgets('a refused check-in says why', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(bookings: _RefusingCheckIn()),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookingsScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Check In'));
    await tester.pump();
    await tester.pump();
    expect(find.text('The grace period for this booking has passed.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
