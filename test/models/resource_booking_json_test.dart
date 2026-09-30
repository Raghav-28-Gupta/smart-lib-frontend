// test/models/resource_booking_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/time_format.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import '../support/fixtures.dart';

void main() {
  test('parses GET /bookings/me, mapping resourceType and frontendStatus', () {
    final bookings = (fixture('bookings_me') as List)
        .map((j) => ResourceBooking.fromJson(j as Map<String, dynamic>))
        .toList();
    expect(bookings, hasLength(2));

    final inWindow = bookings.singleWhere((b) => b.status == BookingStatus.inWindow);
    expect(inWindow.resourceName, 'Silent Zone · Desk 3');
    expect(inWindow.type, ResourceType.seat);
    expect(inWindow.graceRemainingSeconds, greaterThan(0));

    final upcoming = bookings.singleWhere((b) => b.status == BookingStatus.upcomingFar);
    expect(upcoming.graceRemainingSeconds, 0);
  });

  test('converts start and end to local time, and derives the label from them', () {
    final raw = (fixture('bookings_me') as List).first as Map<String, dynamic>;
    final b = ResourceBooking.fromJson(raw);
    expect(b.startTime.isUtc, false);
    expect(b.endTime.isUtc, false);
    expect(b.startTime.isAtSameMomentAs(DateTime.parse(raw['startTime'] as String)), true);
    // The label's text depends on the machine's timezone (the fixture is UTC),
    // so from a fixture only its consistency is asserted -- the literal
    // format is pinned below with local times.
    expect(b.timeSlot, timeRangeLabel(b.startTime, b.endTime));
  });

  test('parses the check-in and create responses', () {
    final checkedIn = ResourceBooking.fromJson(fixture('booking_checked_in') as Map<String, dynamic>);
    expect(checkedIn.status, BookingStatus.checkedIn);
    final created = ResourceBooking.fromJson(fixture('booking_created') as Map<String, dynamic>);
    expect(created.status, BookingStatus.upcomingFar);
  });

  test('timeSlot renders the booking copy format from real times', () {
    final b = ResourceBooking(
      id: 'bk',
      resourceName: 'Reading Room A · Desk 12',
      type: ResourceType.seat,
      startTime: DateTime(2026, 9, 30, 15),
      endTime: DateTime(2026, 9, 30, 17),
      status: BookingStatus.upcomingFar,
    );
    expect(b.timeSlot, '3:00 – 5:00 PM');
  });
}
