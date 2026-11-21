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

  test('parses room requests: requested with its hold deadline, declined, and expired', () {
    final bookings = (fixture('bookings_me_requests') as List)
        .map((j) => ResourceBooking.fromJson(j as Map<String, dynamic>))
        .toList();
    final requested = bookings.singleWhere((b) => b.status == BookingStatus.requested);
    expect(requested.expiresAt, requested.startTime.add(kCheckInGracePeriod));
    final declined = bookings.singleWhere((b) => b.status == BookingStatus.declined);
    expect(declined.declineReason, isNull); // declined without a reason
    expect(bookings.where((b) => b.status == BookingStatus.expired), hasLength(1));
  });

  test('a new room booking comes back as a request, held until the grace period ends', () {
    final b = ResourceBooking.fromJson(fixture('booking_room_requested') as Map<String, dynamic>);
    expect(b.type, ResourceType.room);
    expect(b.status, BookingStatus.requested);
    expect(b.expiresAt!.isUtc, false);
    expect(b.expiresAt, b.startTime.add(kCheckInGracePeriod));
  });

  test("a status this version doesn't know falls back to unknown", () {
    final raw = {...(fixture('bookings_me') as List).first as Map<String, dynamic>, 'frontendStatus': 'paused'};
    expect(ResourceBooking.fromJson(raw).status, BookingStatus.unknown);
  });

  group('library cancel and move', () {
    List<Map<String, dynamic>> libraryRaw() => (fixture('bookings_me_library') as List).cast<Map<String, dynamic>>();
    List<ResourceBooking> library() => libraryRaw().map(ResourceBooking.fromJson).toList();

    test('parses cancelledByLibrary with its reason', () {
      final cancelled = library().singleWhere((b) => b.status == BookingStatus.cancelledByLibrary);
      expect(cancelled.cancelReason, 'Room closed for maintenance');
      expect(cancelled.movedFrom, isNull);
    });

    test('parses movedFrom', () {
      final moved = library().singleWhere((b) => b.movedFrom != null);
      expect(moved.status, BookingStatus.upcomingFar); // still bookable after the move
      expect(moved.cancelReason, isNull);
      // movedFrom is the name of the resource it left, not the one it is on now.
      expect(moved.movedFrom, isNot(moved.resourceName));
      expect(moved.movedFrom, isNotEmpty);
    });

    test('existing fixtures still parse with null cancelReason and movedFrom', () {
      for (final name in ['bookings_me', 'bookings_me_requests']) {
        for (final raw in (fixture(name) as List).cast<Map<String, dynamic>>()) {
          // As captured, and as an older backend sent it, without either key.
          final older = {...raw}..remove('cancelReason')..remove('movedFrom');
          for (final json in [raw, older]) {
            final b = ResourceBooking.fromJson(json);
            expect(b.cancelReason, isNull, reason: name);
            expect(b.movedFrom, isNull, reason: name);
          }
        }
      }
      for (final name in ['booking_created', 'booking_checked_in', 'booking_room_requested']) {
        final b = ResourceBooking.fromJson(fixture(name) as Map<String, dynamic>);
        expect(b.cancelReason, isNull, reason: name);
        expect(b.movedFrom, isNull, reason: name);
      }
    });

    test('an unknown frontendStatus still maps to unknown', () {
      final raw = {...libraryRaw().first, 'frontendStatus': 'cancelledByRobots'};
      final b = ResourceBooking.fromJson(raw);
      expect(b.status, BookingStatus.unknown);
    });

    ResourceBooking booking(BookingStatus status, {String? cancelReason, String? movedFrom, required DateTime start}) => ResourceBooking(
          id: 'bk', resourceName: 'Silent Zone · Desk 3', type: ResourceType.seat, startTime: start,
          endTime: start.add(const Duration(hours: 1)), status: status, cancelReason: cancelReason, movedFrom: movedFrom,
        );

    test('advancedTo leaves cancelledByLibrary unchanged', () {
      // Started five minutes ago, so a live booking would be inWindow; three
      // hours on it would be released. A cancelled booking is neither.
      final start = DateTime.now().subtract(const Duration(minutes: 5));
      final cancelled = booking(BookingStatus.cancelledByLibrary, cancelReason: 'Room closed for maintenance', start: start);
      for (final now in [start.subtract(const Duration(hours: 2)), start.add(const Duration(minutes: 5)), start.add(const Duration(hours: 3))]) {
        final advanced = cancelled.advancedTo(now);
        expect(advanced.status, BookingStatus.cancelledByLibrary);
        expect(advanced.graceRemainingSeconds, 0);
        expect(advanced.cancelReason, 'Room closed for maintenance');
      }
    });

    test('advancedTo and copyWith keep movedFrom', () {
      final start = DateTime.now().add(const Duration(hours: 1));
      final moved = booking(BookingStatus.upcomingFar, movedFrom: 'Reading Room A · Desk 12', start: start);
      final open = moved.advancedTo(start.add(const Duration(minutes: 1)));
      expect(open.status, BookingStatus.inWindow);
      expect(open.movedFrom, 'Reading Room A · Desk 12');
      expect(moved.copyWith(status: BookingStatus.checkedIn).movedFrom, 'Reading Room A · Desk 12');
    });
  });
}
