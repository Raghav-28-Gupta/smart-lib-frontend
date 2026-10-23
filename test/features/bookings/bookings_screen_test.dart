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

/// Serves exactly these bookings, with the network failing on demand.
class _ListedBookings extends MockBookingRepository {
  _ListedBookings(this.bookings);
  List<ResourceBooking> bookings;
  bool offline = false;

  @override
  Future<List<ResourceBooking>> myBookings() async {
    if (offline) throw const ApiException(0, ApiException.networkMessage);
    return List.of(bookings);
  }
}

ResourceBooking _room(String id, BookingStatus status, {String? reason}) {
  final start = DateTime.now().add(const Duration(hours: 20));
  return ResourceBooking(
    id: id, resourceName: 'Group Room 201', type: ResourceType.room, startTime: start,
    endTime: start.add(const Duration(hours: 1)), status: status,
    expiresAt: status == BookingStatus.requested ? start.add(kCheckInGracePeriod) : null,
    declineReason: reason,
  );
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

  testWidgets('shows room requests: waiting with its deadline and Cancel, declined, expired and unknown', (tester) async {
    final repo = _ListedBookings([
      _room('bk-1', BookingStatus.requested),
      _room('bk-2', BookingStatus.declined, reason: 'Reserved for an event'),
      _room('bk-3', BookingStatus.declined),
      _room('bk-4', BookingStatus.expired),
      _room('bk-5', BookingStatus.unknown),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(bookings: repo),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookingsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Waiting for a librarian · held until '), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.text('Declined — Reserved for an event'), findsOneWidget);
    expect(find.text('Declined by the library'), findsOneWidget);
    expect(find.text('Expired — no librarian approved it in time'), findsOneWidget);
    expect(find.text("Update the app to see this item's status."), findsOneWidget);
  });

  testWidgets('while a room request waits, the list re-checks every 30 seconds and shows the answer', (tester) async {
    final repo = _ListedBookings([_room('bk-1', BookingStatus.requested)]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(bookings: repo),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookingsScreen()),
    ));
    await tester.pumpAndSettle();

    repo.bookings = [_room('bk-1', BookingStatus.upcomingFar)];
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(find.textContaining('check-in opens at the start time'), findsOneWidget);
  });

  testWidgets('a network blip during the re-check keeps the list on screen', (tester) async {
    final repo = _ListedBookings([_room('bk-1', BookingStatus.requested)]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(bookings: repo),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookingsScreen()),
    ));
    await tester.pumpAndSettle();

    repo.offline = true;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(find.textContaining('Waiting for a librarian'), findsOneWidget);
    expect(find.text("Couldn't load your bookings"), findsNothing);
  });
}
