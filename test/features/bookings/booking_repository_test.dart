// test/features/bookings/booking_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/bookings/time_slots.dart';
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

  group('the demo seat layout', () {
    test('serves the 128-desk demo layout: s2 is Reading Room A · Desk 14 at row 2, column 5, with front Windows', () async {
      final seats = await MockBookingRepository().resources(ResourceType.seat, 0);
      expect(seats, hasLength(128));
      expect(seats.every((s) => s.type == ResourceType.seat && s.status == ResourceStatus.available && s.isPlaced), true);

      final s2 = seats.singleWhere((s) => s.id == 's2');
      expect(s2.name, 'Reading Room A · Desk 14');
      expect(s2.location, 'Reading Room A');
      expect(s2.row, 2);
      expect(s2.column, 5);
      expect(s2.zoneFront, 'Windows');

      // The other kept desks, as the seed places them.
      Resource seat(String id) => seats.singleWhere((s) => s.id == id);
      expect((seat('s1').name, seat('s1').row, seat('s1').column), ('Reading Room A · Desk 12', 2, 2));
      expect((seat('s3').name, seat('s3').row, seat('s3').column, seat('s3').zoneFront), ('Silent Zone · Desk 3', 1, 3, 'Entrance'));
      expect((seat('s4').name, seat('s4').row, seat('s4').column), ('Silent Zone · Desk 7', 1, 8));

      final reading = seats.where((s) => s.location == 'Reading Room A').toList();
      final silent = seats.where((s) => s.location == 'Silent Zone').toList();
      expect(reading, hasLength(80));
      expect(silent, hasLength(48));
      expect(reading.every((s) => s.zoneFront == 'Windows'), true);
      expect(silent.every((s) => s.zoneFront == 'Entrance'), true);

      // The aisles: columns 4 and 9 in Reading Room A, column 5 in Silent Zone, hold no desk.
      expect(reading.map((s) => s.column).toSet(), {1, 2, 3, 5, 6, 7, 8, 10, 11, 12});
      expect(reading.map((s) => s.row).toSet(), {1, 2, 3, 4, 5, 6, 7, 8});
      expect(silent.map((s) => s.column).toSet(), {1, 2, 3, 4, 6, 7, 8, 9});
      expect(silent.map((s) => s.row).toSet(), {1, 2, 3, 4, 5, 6});

      // Desk N runs row by row over the desk columns; a generated desk's id carries N, and
      // the kept ones (Desk 12 and 14, Silent Zone Desk 3 and 7) keep theirs.
      Resource named(String name) => seats.singleWhere((s) => s.name == name);
      expect((named('Reading Room A · Desk 1').id, named('Reading Room A · Desk 1').row, named('Reading Room A · Desk 1').column), ('s-rra-1', 1, 1));
      expect((named('Reading Room A · Desk 80').id, named('Reading Room A · Desk 80').row, named('Reading Room A · Desk 80').column), ('s-rra-80', 8, 12));
      expect((named('Silent Zone · Desk 1').id, named('Silent Zone · Desk 1').row, named('Silent Zone · Desk 1').column), ('s-sz-1', 1, 1));
      expect((named('Silent Zone · Desk 48').id, named('Silent Zone · Desk 48').row, named('Silent Zone · Desk 48').column), ('s-sz-48', 6, 9));
      expect(seats.map((s) => s.id).toSet().intersection({'s-rra-12', 's-rra-14', 's-sz-3', 's-sz-7'}), isEmpty);
    });

    test('today s1 to s4 keep their taken slots, and tomorrow nothing is taken', () async {
      final repo = MockBookingRepository();
      final today = await repo.resources(ResourceType.seat, 0);
      Map<String, List<String>> takenById(List<Resource> seats) => {for (final s in seats) s.id: s.takenSlotsToday};

      expect(takenById(today)['s1'], ['11:00 AM', '12:00 PM']);
      expect(takenById(today)['s2'], ['9:00 AM', '10:00 AM', '3:00 PM', '4:00 PM']);
      expect(takenById(today)['s3'], isEmpty);
      expect(takenById(today)['s4'], ['1:00 PM', '2:00 PM', '6:00 PM']);
      final others = today.where((s) => !const {'s1', 's2', 's3', 's4'}.contains(s.id));
      expect(others, hasLength(124));
      expect(others.every((s) => s.takenSlotsToday.isEmpty), true);

      for (final dateIndex in [1, 2]) {
        final later = await repo.resources(ResourceType.seat, dateIndex);
        expect(later, hasLength(128));
        expect(later.every((s) => s.takenSlotsToday.isEmpty), true, reason: 'day $dateIndex');
      }
    });

    test('ids and positions are unique', () async {
      final seats = await MockBookingRepository().resources(ResourceType.seat, 0);
      expect(seats.map((s) => s.id).toSet(), hasLength(seats.length));
      expect(seats.map((s) => s.name).toSet(), hasLength(seats.length));
      expect(seats.map((s) => (s.location, s.row, s.column)).toSet(), hasLength(seats.length));
    });

    test('the rooms are unchanged, and are not on any map', () async {
      final rooms = await MockBookingRepository().resources(ResourceType.room, 0);
      expect(rooms.map((r) => r.id), ['r1', 'r2', 'r3']);
      expect(rooms.every((r) => !r.isPlaced && r.status == ResourceStatus.available), true);
      expect(rooms.singleWhere((r) => r.id == 'r2').takenSlotsToday, kTimeSlots);
    });

    test('the scripted s1 conflict tomorrow at 5:00 PM still offers s1 at 6:00 PM and s3 at 5:00 PM', () async {
      final repo = MockBookingRepository();
      final s1 = (await repo.resources(ResourceType.seat, 1)).singleWhere((s) => s.id == 's1');
      final start = slotWindow(1, '5:00 PM');
      try {
        await repo.createBooking(resource: s1, start: start.start, end: start.end);
        fail('expected a BookingConflictException');
      } on BookingConflictException catch (e) {
        expect(e.alternatives.map((a) => (a.resourceId, a.resourceName)), [
          ('s1', 'Reading Room A · Desk 12'),
          ('s3', 'Silent Zone · Desk 3'),
        ]);
      }
      // The conflicting slot now reads taken.
      expect((await repo.resources(ResourceType.seat, 1)).singleWhere((s) => s.id == 's1').takenSlotsToday, ['5:00 PM']);
    });
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
