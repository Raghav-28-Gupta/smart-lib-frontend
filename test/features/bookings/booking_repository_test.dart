// test/features/bookings/booking_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';

void main() {
  test('myBookings returns the 2 seeded bookings', () async {
    final repo = MockBookingRepository();
    final bookings = await repo.myBookings();
    expect(bookings.length, 2);
  });

  test('resources(room, dateIndex >= 2) is empty — scripted no-rooms-free date', () async {
    final repo = MockBookingRepository();
    final rooms = await repo.resources(ResourceType.room, 2);
    expect(rooms, isEmpty);
  });

  test('resources(seat, 0) includes today\'s taken slots', () async {
    final repo = MockBookingRepository();
    final seats = await repo.resources(ResourceType.seat, 0);
    final s1 = seats.firstWhere((r) => r.id == 's1');
    expect(s1.takenSlotsToday, contains('11:00 AM'));
  });

  test('checkIn flips a booking to checkedIn', () async {
    final repo = MockBookingRepository();
    final updated = await repo.checkIn('bk2');
    expect(updated.status.toString(), contains('checkedIn'));
  });

  test('cancelBooking removes the booking', () async {
    final repo = MockBookingRepository();
    await repo.cancelBooking('bk1');
    final bookings = await repo.myBookings();
    expect(bookings.any((b) => b.id == 'bk1'), false);
  });

  group('reportResource', () {
    test('the seeded bookings can be reported, each on its own resource', () async {
      final bookings = await MockBookingRepository().myBookings();
      expect(bookings.every((b) => b.canReport && !b.reportOpen), true);
      expect(bookings.map((b) => b.resourceId).toSet(), hasLength(2));
      expect(bookings.every((b) => b.resourceId.isNotEmpty), true);
    });

    test('records the report and turns the resource\'s bookings into reported ones', () async {
      final repo = MockBookingRepository();
      final target = (await repo.myBookings()).first;

      await repo.reportResource(target.resourceId, ResourceReportCategory.notWorking, 'The lamp is dead.');

      expect(repo.reports, [(resourceId: target.resourceId, category: ResourceReportCategory.notWorking, note: 'The lamp is dead.')]);
      final after = await repo.myBookings();
      final reported = after.singleWhere((b) => b.id == target.id);
      expect(reported.reportOpen, true);
      expect(reported.canReport, false);
      final other = after.singleWhere((b) => b.id != target.id);
      expect(other.reportOpen, false);
      expect(other.canReport, true);
    });

    test('refuses a second report on the same resource, as the server does', () async {
      final repo = MockBookingRepository();
      final target = (await repo.myBookings()).first;
      await repo.reportResource(target.resourceId, ResourceReportCategory.dirty, null);

      await expectLater(
        repo.reportResource(target.resourceId, ResourceReportCategory.dirty, null),
        throwsA(isA<ConflictException>().having((e) => e.message, 'message', 'You already reported this. The library is looking into it.')),
      );
      expect(repo.reports, hasLength(1));
    });

    test('refuses a resource the student has no reportable booking on', () async {
      final repo = MockBookingRepository();
      await expectLater(
        repo.reportResource('never-booked', ResourceReportCategory.dirty, null),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', 'You can only report a seat or room you have booked.')),
      );
      expect(repo.reports, isEmpty);
    });
  });
}
