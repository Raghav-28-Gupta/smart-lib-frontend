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
    // The two the capture made, and the demo student's seeded no-show (a released booking).
    expect(bookings, hasLength(3));
    expect(bookings.where((b) => b.status == BookingStatus.released), hasLength(1));

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

  group('problem reports', () {
    List<Map<String, dynamic>> raw(String name) => (fixture(name) as List).cast<Map<String, dynamic>>();
    List<ResourceBooking> parsed(String name) => raw(name).map(ResourceBooking.fromJson).toList();

    ResourceBooking booking({String resourceId = 's3', bool canReport = false, bool reportOpen = false}) {
      final start = DateTime.now().subtract(const Duration(minutes: 5));
      return ResourceBooking(
        id: 'bk', resourceId: resourceId, resourceName: 'Silent Zone · Desk 3', type: ResourceType.seat, startTime: start,
        endTime: start.add(const Duration(hours: 1)), status: BookingStatus.inWindow, graceRemainingSeconds: 600,
        canReport: canReport, reportOpen: reportOpen,
      );
    }

    test('parses canReport, reportOpen and resourceId', () {
      // The seat Aditi checked into: she may report it, and has not.
      final inWindow = parsed('bookings_me').singleWhere((b) => b.status == BookingStatus.inWindow);
      expect(inWindow.resourceId, 's3');
      expect(inWindow.canReport, true);
      expect(inWindow.reportOpen, false);

      // After she reported that desk, every booking of hers on it says so, and none offers the button.
      final reported = parsed('bookings_me_reported');
      final onDesk3 = reported.where((b) => b.resourceId == 's3').toList();
      expect(onDesk3, isNotEmpty);
      for (final b in onDesk3) {
        expect(b.reportOpen, true);
        expect(b.canReport, false);
      }
      // A booking on any other resource reads nothing of it.
      expect(reported.where((b) => b.resourceId != 's3'), isNotEmpty);
      for (final b in reported.where((b) => b.resourceId != 's3')) {
        expect(b.reportOpen, false);
      }
    });

    test('older payloads without them parse as false', () {
      for (final name in ['bookings_me', 'bookings_me_requests', 'bookings_me_library']) {
        for (final json in raw(name)) {
          // As an older backend sent it, without any of the three keys.
          final older = {...json}..remove('canReport')..remove('reportOpen')..remove('resourceId');
          final b = ResourceBooking.fromJson(older);
          expect(b.resourceId, '', reason: name);
          expect(b.canReport, false, reason: name);
          expect(b.reportOpen, false, reason: name);
          // Everything else still reads as before.
          expect(b.id, json['id'], reason: name);
          expect(b.resourceName, json['resourceName'], reason: name);
        }
      }
      for (final name in ['booking_created', 'booking_checked_in', 'booking_room_requested']) {
        final older = {...fixture(name) as Map<String, dynamic>}..remove('canReport')..remove('reportOpen')..remove('resourceId');
        final b = ResourceBooking.fromJson(older);
        expect(b.canReport, false, reason: name);
        expect(b.reportOpen, false, reason: name);
      }
    });

    test('copyWith keeps them, and sets them when asked', () {
      final reportable = booking(canReport: true);
      expect(reportable.copyWith(status: BookingStatus.checkedIn).resourceId, 's3');
      expect(reportable.copyWith(status: BookingStatus.checkedIn).canReport, true);
      expect(reportable.copyWith(graceRemainingSeconds: 5).canReport, true);
      final reported = booking(reportOpen: true);
      expect(reported.copyWith(status: BookingStatus.checkedIn).reportOpen, true);
      expect(reported.copyWith(status: BookingStatus.checkedIn).canReport, false);

      final marked = reportable.copyWith(reportOpen: true, canReport: false);
      expect(marked.reportOpen, true);
      expect(marked.canReport, false);
      expect(marked.resourceId, 's3');
      expect(marked.id, 'bk');
    });

    test('advancedTo keeps them as the booking moves through its states', () {
      final start = DateTime.now().add(const Duration(hours: 1));
      final b = ResourceBooking(
        id: 'bk', resourceId: 's3', resourceName: 'Silent Zone · Desk 3', type: ResourceType.seat, startTime: start,
        endTime: start.add(const Duration(hours: 1)), status: BookingStatus.upcomingFar, canReport: true,
      );
      final open = b.advancedTo(start.add(const Duration(minutes: 1)));
      expect(open.status, BookingStatus.inWindow);
      expect(open.resourceId, 's3');
      expect(open.canReport, true);
    });

    test('the categories are spelled as the server spells them', () {
      expect(ResourceReportCategory.values, [ResourceReportCategory.notWorking, ResourceReportCategory.dirty, ResourceReportCategory.other]);
      expect(ResourceReportCategory.notWorking.wireName, 'not_working');
      expect(ResourceReportCategory.dirty.wireName, 'dirty');
      expect(ResourceReportCategory.other.wireName, 'other');
    });
  });

  // `bookings_me_no_show` and `bookings_me_no_show_disputed` are captured (tool/capture_fixtures.dart):
  // the demo student's seeded no-show before and after she disputes it.
  group('no-shows', () {
    List<Map<String, dynamic>> raw(String name) => (fixture(name) as List).cast<Map<String, dynamic>>();
    List<ResourceBooking> parsed(String name) => raw(name).map(ResourceBooking.fromJson).toList();

    ResourceBooking recorded({NoShowInfo? noShow}) {
      final start = DateTime.now().subtract(const Duration(days: 1));
      return ResourceBooking(
        id: 'bk', resourceId: 's2', resourceName: 'Reading Room A · Desk 14', type: ResourceType.seat, startTime: start,
        endTime: start.add(const Duration(hours: 1)), status: BookingStatus.released, noShow: noShow,
      );
    }

    test('a booking payload without noShow parses to null', () {
      // As an older server sent it (no key at all), and as a newer one sends an ordinary booking (null).
      for (final name in ['bookings_me', 'bookings_me_requests', 'bookings_me_library', 'bookings_me_reported']) {
        for (final json in raw(name)) {
          final older = {...json}..remove('noShow');
          expect(older.containsKey('noShow'), false, reason: name);
          expect(ResourceBooking.fromJson(older).noShow, isNull, reason: name);
          expect(ResourceBooking.fromJson({...json, 'noShow': null}).noShow, isNull, reason: name);
        }
      }
      for (final name in ['booking_created', 'booking_checked_in', 'booking_room_requested']) {
        final older = {...fixture(name) as Map<String, dynamic>}..remove('noShow');
        expect(ResourceBooking.fromJson(older).noShow, isNull, reason: name);
      }
    });

    test('a captured no-show booking parses with canDispute true', () {
      final listed = parsed('bookings_me_no_show');
      final missed = listed.singleWhere((b) => b.noShow?.canDispute == true);
      // The server keeps frontendStatus 'released' for a no-show, so an older app shows its
      // released text; the new app tells the two apart by noShow.
      expect(missed.status, BookingStatus.released);
      expect(missed.noShow!.dispute, isNull);
      // No other booking is disputable, and the ordinary ones carry noShow null.
      final others = listed.where((b) => b.id != missed.id);
      expect(others, isNotEmpty);
      for (final b in others) {
        expect(b.noShow?.canDispute, isNot(true));
      }
      expect(others.where((b) => b.noShow == null), isNotEmpty);
    });

    test('a captured dispute reads open, with no note while it waits', () {
      final missedId = parsed('bookings_me_no_show').singleWhere((b) => b.noShow?.canDispute == true).id;
      final disputed = parsed('bookings_me_no_show_disputed').singleWhere((b) => b.id == missedId);
      expect(disputed.status, BookingStatus.released);
      expect(disputed.noShow!.canDispute, false);
      expect(disputed.noShow!.dispute!.status, NoShowDisputeStatus.open);
      expect(disputed.noShow!.dispute!.note, isNull);
    });

    test('an answered dispute carries its status and the library note', () {
      ResourceBooking withDispute(Object? dispute) => ResourceBooking.fromJson({
            ...raw('bookings_me_no_show').first,
            'noShow': {'canDispute': false, 'dispute': dispute},
          });
      final overturned = withDispute({'status': 'overturned', 'note': 'The desk scanner was down.'});
      expect(overturned.noShow!.dispute!.status, NoShowDisputeStatus.overturned);
      expect(overturned.noShow!.dispute!.note, 'The desk scanner was down.');
      final upheld = withDispute({'status': 'upheld', 'note': null});
      expect(upheld.noShow!.dispute!.status, NoShowDisputeStatus.upheld);
      expect(upheld.noShow!.dispute!.note, isNull);
      // A dispute with no note key at all reads as no note.
      expect(withDispute({'status': 'upheld'}).noShow!.dispute!.note, isNull);
    });

    test('an unknown dispute status maps to unknown', () {
      final b = ResourceBooking.fromJson({
        ...raw('bookings_me_no_show').first,
        'noShow': {
          'canDispute': false,
          'dispute': {'status': 'escalated_to_the_moon', 'note': 'Something a later server says.'},
        },
      });
      expect(b.noShow!.dispute!.status, NoShowDisputeStatus.unknown);
      expect(b.noShow!.dispute!.note, 'Something a later server says.');
      expect(NoShowDisputeStatus.values, [
        NoShowDisputeStatus.open,
        NoShowDisputeStatus.overturned,
        NoShowDisputeStatus.upheld,
        NoShowDisputeStatus.unknown,
      ]);
    });

    test('copyWith and advancedTo keep noShow, and copyWith sets it when asked', () {
      const info = NoShowInfo(canDispute: true);
      final missed = recorded(noShow: info);
      expect(missed.copyWith(graceRemainingSeconds: 0).noShow, same(info));
      expect(missed.advancedTo(DateTime.now()).noShow, same(info));
      expect(recorded().copyWith(canReport: true).noShow, isNull);

      const open = NoShowInfo(canDispute: false, dispute: NoShowDisputeInfo(status: NoShowDisputeStatus.open));
      final marked = missed.copyWith(noShow: open);
      expect(marked.noShow, same(open));
      expect(marked.id, 'bk');
      expect(marked.status, BookingStatus.released);
    });
  });
}
