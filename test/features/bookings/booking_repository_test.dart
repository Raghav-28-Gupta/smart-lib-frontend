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

  group('disputeNoShow', () {
    // A booking the library recorded as a no-show, as the server lists it two days later.
    ResourceBooking missed(String id, {bool canDispute = true, NoShowDisputeInfo? dispute, bool recorded = true}) {
      final start = DateTime.now().subtract(const Duration(days: 2));
      return ResourceBooking(
        id: id, resourceId: 's3', resourceName: 'Silent Zone · Desk 3', type: ResourceType.seat, startTime: start,
        endTime: start.add(const Duration(hours: 1)), status: BookingStatus.released,
        noShow: recorded ? NoShowInfo(canDispute: canDispute, dispute: dispute) : null,
      );
    }

    test('records each accepted dispute, in order', () async {
      final repo = MockBookingRepository(bookings: [missed('bk-a'), missed('bk-b')]);
      await repo.disputeNoShow('bk-a', 'The scanner was down.');
      await repo.disputeNoShow('bk-b', 'I was there.');
      expect(repo.noShowDisputes, [
        (bookingId: 'bk-a', reason: 'The scanner was down.'),
        (bookingId: 'bk-b', reason: 'I was there.'),
      ]);
    });

    test('turns the listed booking into an open dispute that cannot be disputed again, and touches no other', () async {
      final repo = MockBookingRepository(bookings: [missed('bk-a'), missed('bk-b')]);

      await repo.disputeNoShow('bk-a', 'The scanner was down.');

      final after = await repo.myBookings();
      final a = after.singleWhere((b) => b.id == 'bk-a');
      expect(a.noShow!.dispute!.status, NoShowDisputeStatus.open);
      expect(a.noShow!.dispute!.note, isNull);
      expect(a.noShow!.canDispute, false);
      expect(a.status, BookingStatus.released); // a dispute does not change the booking's own status
      final b = after.singleWhere((b) => b.id == 'bk-b');
      expect(b.noShow!.dispute, isNull);
      expect(b.noShow!.canDispute, true);
    });

    test('a mock built without bookings still lists the two seeded ones', () async {
      expect(await MockBookingRepository().myBookings(), hasLength(2));
      expect(await MockBookingRepository(bookings: const []).myBookings(), isEmpty);
    });

    group('refuses where the server does, and records nothing', () {
      Future<void> expectRefused(MockBookingRepository repo, String id, int status, String message) async {
        await expectLater(
          repo.disputeNoShow(id, 'I was there.'),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', status)
              .having((e) => e.message, 'message', message)),
        );
        expect(repo.noShowDisputes, isEmpty);
      }

      test('a booking that is not in the list is 404', () async {
        await expectRefused(MockBookingRepository(bookings: [missed('bk-a')]), 'nope', 404, 'Booking not found');
      });

      test('a booking that was only released, or any seeded one, is not a recorded no-show', () async {
        await expectRefused(
            MockBookingRepository(bookings: [missed('bk-a', recorded: false)]), 'bk-a', 409, 'This booking is not a recorded no-show.');
        await expectRefused(MockBookingRepository(), 'bk1', 409, 'This booking is not a recorded no-show.');
      });

      test('a no-show past its 7 days is refused', () async {
        await expectRefused(MockBookingRepository(bookings: [missed('bk-a', canDispute: false)]), 'bk-a', 409,
            'The 7 days to dispute this no-show have passed.');
      });

      test('a no-show that was disputed before is refused, whatever became of the dispute', () async {
        for (final status in [NoShowDisputeStatus.open, NoShowDisputeStatus.overturned, NoShowDisputeStatus.upheld]) {
          await expectRefused(MockBookingRepository(bookings: [missed('bk-a', canDispute: false, dispute: NoShowDisputeInfo(status: status))]),
              'bk-a', 409, "You've already disputed this no-show.");
        }
      });

      test('the second dispute of one booking is refused', () async {
        final repo = MockBookingRepository(bookings: [missed('bk-a')]);
        await repo.disputeNoShow('bk-a', 'I was there.');
        await expectLater(
          repo.disputeNoShow('bk-a', 'I was really there.'),
          throwsA(isA<ConflictException>().having((e) => e.message, 'message', "You've already disputed this no-show.")),
        );
        expect(repo.noShowDisputes, hasLength(1));
      });
    });

    test('throws what a test sets, records nothing, and goes through again once cleared', () async {
      final repo = MockBookingRepository(bookings: [missed('bk-a')])
        ..disputeError = const ConflictException("You've already disputed this no-show.");
      await expectLater(
        repo.disputeNoShow('bk-a', 'I was there.'),
        throwsA(isA<ConflictException>().having((e) => e.message, 'message', "You've already disputed this no-show.")),
      );
      expect(repo.noShowDisputes, isEmpty);
      expect((await repo.myBookings()).single.noShow!.dispute, isNull);

      repo.disputeError = null;
      await repo.disputeNoShow('bk-a', 'I was there.');
      expect(repo.noShowDisputes, [(bookingId: 'bk-a', reason: 'I was there.')]);
    });
  });
}
