// test/features/home/home_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/home/home_screen.dart';
import 'package:smartlib_frontend/models/app_user.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import '../../support/mock_overrides.dart';

/// The mock, with exactly these bookings.
class _Bookings extends MockBookingRepository {
  _Bookings(this._list);
  final List<ResourceBooking> _list;

  @override
  Future<List<ResourceBooking>> myBookings() async => List.of(_list);
}

ResourceBooking _room(String id, String name, BookingStatus status) {
  final start = DateTime.now().add(const Duration(hours: 20));
  return ResourceBooking(
      id: id, resourceName: name, type: ResourceType.room, startTime: start,
      endTime: start.add(const Duration(hours: 1)), status: status);
}

class _LoggedInAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(
          id: 'u1',
          name: 'Aditi Sharma',
          email: 'aditi.sharma@thapar.edu',
          roll: '1024160143',
        ),
      );
}

void main() {
  testWidgets('shows the returning-user greeting and both quick-glance sections', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_LoggedInAuthController.new),
        ...mockRepositoryOverrides(),
      ],
      child: MaterialApp(theme: buildSmartLibTheme(), home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back, Aditi'), findsOneWidget);
    expect(find.text('Active loans'), findsOneWidget);
    expect(find.text('Upcoming bookings'), findsOneWidget);
  });

  testWidgets('Upcoming bookings skips a declined room request and shows the confirmed booking', (tester) async {
    final seatStart = DateTime.now().add(const Duration(hours: 22));
    final bookings = _Bookings([
      _room('bk-d', 'Group Room 201', BookingStatus.declined),
      ResourceBooking(
          id: 'bk-s', resourceName: 'Reading Room A · Desk 4', type: ResourceType.seat, startTime: seatStart,
          endTime: seatStart.add(const Duration(hours: 2)), status: BookingStatus.upcomingFar),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(bookings: bookings),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Reading Room A · Desk 4'), findsOneWidget);
    expect(find.text('Group Room 201'), findsNothing);
  });

  testWidgets('with only room requests that are not confirmed, Upcoming bookings says there are none yet', (tester) async {
    final bookings = _Bookings([
      _room('bk-r', 'Group Room 201', BookingStatus.requested),
      _room('bk-d', 'Group Room 202', BookingStatus.declined),
      _room('bk-e', 'Group Room 203', BookingStatus.expired),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(bookings: bookings),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No bookings yet — reserve a seat or room to get started.'), findsOneWidget);
    expect(find.textContaining('Group Room'), findsNothing);
  });
}
