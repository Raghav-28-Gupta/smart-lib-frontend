// test/features/bookings/seat_map_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/bookings/demo_seat_layout.dart';
import 'package:smartlib_frontend/features/bookings/seat_map.dart';
import 'package:smartlib_frontend/features/bookings/time_slots.dart';
import 'package:smartlib_frontend/models/resource.dart';

Resource seat(
  String id, {
  String? name,
  List<String> taken = const [],
  String? location,
  int? row,
  int? column,
  String? front,
  ResourceStatus status = ResourceStatus.available,
}) =>
    Resource(
      id: id,
      name: name ?? 'Desk $id',
      type: ResourceType.seat,
      takenSlotsToday: taken,
      location: location,
      row: row,
      column: column,
      zoneFront: front,
      status: status,
    );

void main() {
  // A day with room to spare: every slot today is still ahead of 8 AM.
  final earlyToday = DateTime(2026, 11, 27, 8);
  // 2:20 PM: 9 AM to 2 PM are over (2 PM closed at 2:15), 3 PM is next.
  final afternoon = DateTime(2026, 11, 27, 14, 20);

  group('deskLabel', () {
    test('deskLabel takes the last digits: "Reading Room A · Desk 14" is "14", "Room 2 Desk 101" is "101"', () {
      expect(deskLabel('Reading Room A · Desk 14'), '14');
      expect(deskLabel('Room 2 Desk 101'), '101');
    });

    test('deskLabel without digits takes the first 3 characters: "Window Nook" is "Win"', () {
      expect(deskLabel('Window Nook'), 'Win');
    });

    test('deskLabel never comes back empty for a short name', () {
      expect(deskLabel('A'), 'A');
      expect(deskLabel('Ab'), 'Ab');
    });
  });

  group('free counts', () {
    test('an offline seat is never free and never counted', () {
      final open = seat('a');
      final offline = seat('b', status: ResourceStatus.offline);
      expect(isFreeAt(open, '3:00 PM'), true);
      expect(isFreeAt(offline, '3:00 PM'), false);
      expect(freeCount([open, offline], '3:00 PM'), 1);
      expect(freeCount([offline], '3:00 PM'), 0);
    });

    test('a seat taken at a slot is not free then, and still free at another', () {
      final s = seat('a', taken: ['3:00 PM']);
      expect(isFreeAt(s, '3:00 PM'), false);
      expect(isFreeAt(s, '4:00 PM'), true);
    });

    test('a slot where every seat is taken is full, and a zone with nothing free counts 0', () {
      final seats = [
        seat('a', taken: ['3:00 PM'], location: 'Reading Room A', row: 1, column: 1),
        seat('b', taken: ['3:00 PM'], location: 'Reading Room A', row: 1, column: 2),
        seat('c', location: 'Silent Zone', row: 1, column: 1),
      ];
      // Everyone is taken in Reading Room A, but Silent Zone's desk keeps the slot open.
      expect(slotState(seats, 1, '3:00 PM', now: earlyToday), SlotState.open);
      final reading = zonesOf(seats).firstWhere((z) => z.name == 'Reading Room A');
      expect(freeCount(reading.desks.values, '3:00 PM'), 0);

      final everyone = seats.take(2).toList();
      expect(slotState(everyone, 1, '3:00 PM', now: earlyToday), SlotState.full);
      expect(slotState(everyone, 1, '4:00 PM', now: earlyToday), SlotState.open);
    });

    test('a slot with only offline seats left is full', () {
      final seats = [
        seat('a', taken: ['3:00 PM']),
        seat('b', status: ResourceStatus.offline),
      ];
      expect(slotState(seats, 1, '3:00 PM', now: earlyToday), SlotState.full);
    });
  });

  group('slotState', () {
    test('a passed slot is passed even when it is also full', () {
      final seats = [seat('a', taken: ['9:00 AM', '3:00 PM'])];
      expect(slotState(seats, 0, '9:00 AM', now: afternoon), SlotState.passed);
      expect(slotState(seats, 0, '3:00 PM', now: afternoon), SlotState.full);
      expect(slotState(seats, 0, '4:00 PM', now: afternoon), SlotState.open);
    });

    test('the same hour is not passed tomorrow', () {
      final seats = [seat('a')];
      expect(slotState(seats, 0, '9:00 AM', now: afternoon), SlotState.passed);
      expect(slotState(seats, 1, '9:00 AM', now: afternoon), SlotState.open);
    });

    test('the current slot stays open until its check-in window closes', () {
      final seats = [seat('a')];
      expect(slotState(seats, 0, '2:00 PM', now: DateTime(2026, 11, 27, 14, 10)), SlotState.open);
      expect(slotState(seats, 0, '2:00 PM', now: DateTime(2026, 11, 27, 14, 20)), SlotState.passed);
    });
  });

  group('defaultSlot', () {
    test(
        'defaultSlot today is the first slot neither passed nor full; on a later day the first that is not full; null when nothing is left today',
        () {
      final free = [seat('a'), seat('b')];
      // Today at 2:20 PM: 9 AM to 2 PM are passed, so 3 PM is the first.
      expect(defaultSlot(free, 0, now: afternoon), '3:00 PM');

      // 3 PM is full for every seat, so today moves on to 4 PM.
      final threeTaken = [seat('a', taken: ['3:00 PM']), seat('b', taken: ['3:00 PM'])];
      expect(defaultSlot(threeTaken, 0, now: afternoon), '4:00 PM');

      // A later day skips only what is full: 9 AM is not passed there.
      expect(defaultSlot(free, 1, now: afternoon), '9:00 AM');
      final nineTaken = [seat('a', taken: ['9:00 AM']), seat('b', taken: ['9:00 AM'])];
      expect(defaultSlot(nineTaken, 1, now: afternoon), '10:00 AM');

      // Nothing left today: every slot is passed, or every remaining one is full.
      expect(defaultSlot(free, 0, now: DateTime(2026, 11, 27, 19, 30)), isNull);
      final restTaken = [
        seat('a', taken: ['3:00 PM', '4:00 PM', '5:00 PM', '6:00 PM', '7:00 PM']),
      ];
      expect(defaultSlot(restTaken, 0, now: afternoon), isNull);
    });

    test('defaultSlot is null for a day with no seats to book', () {
      expect(defaultSlot(const [], 1, now: afternoon), isNull);
    });
  });

  group('slotEndLabel', () {
    test('slotEndLabel: 9:00 AM to 10:00 AM, 11:00 AM to 12:00 PM, 7:00 PM to 8:00 PM', () {
      expect(slotEndLabel('9:00 AM'), '10:00 AM');
      expect(slotEndLabel('11:00 AM'), '12:00 PM');
      expect(slotEndLabel('7:00 PM'), '8:00 PM');
    });

    test('slotEndLabel crosses noon and every slot ends one hour on', () {
      expect(slotEndLabel('12:00 PM'), '1:00 PM');
      for (final slot in kTimeSlots) {
        expect(slotEndLabel(slot), isNot(slot));
      }
    });
  });

  group('zonesOf', () {
    test('zonesOf sizes each zone by its max row and column, keys desks by (row, column) and sorts zones by name', () {
      final silent3 = seat('s3', name: 'Silent Zone · Desk 3', location: 'Silent Zone', row: 1, column: 3, front: 'Entrance');
      final silent9 = seat('s9', name: 'Silent Zone · Desk 9', location: 'Silent Zone', row: 6, column: 9, front: 'Entrance');
      final reading1 = seat('r1', name: 'Reading Room A · Desk 1', location: 'Reading Room A', row: 1, column: 1, front: 'Windows');
      final reading2 = seat('r2', name: 'Reading Room A · Desk 2', location: 'Reading Room A', row: 2, column: 12, front: 'Windows');
      final zones = zonesOf([silent3, reading2, silent9, reading1]);

      expect(zones.map((z) => z.name), ['Reading Room A', 'Silent Zone']);

      final reading = zones[0];
      expect(reading.front, 'Windows');
      expect(reading.rows, 2);
      expect(reading.columns, 12);
      expect(reading.desks.length, 2);
      expect(reading.desks[(1, 1)], same(reading1));
      expect(reading.desks[(2, 12)], same(reading2));
      expect(reading.desks[(1, 2)], isNull); // a gap

      final silent = zones[1];
      expect(silent.front, 'Entrance');
      expect(silent.rows, 6);
      expect(silent.columns, 9);
      expect(silent.desks[(1, 3)], same(silent3));
      expect(silent.desks[(6, 9)], same(silent9));
    });

    test('a zone with no front keeps it null, and a seat that names one gives it', () {
      final zones = zonesOf([
        seat('a', location: 'Annex', row: 1, column: 1),
        seat('b', location: 'Annex', row: 1, column: 2, front: 'Door'),
        seat('c', location: 'Loft', row: 1, column: 1),
        seat('d', location: 'Loft', row: 1, column: 2, front: '  '),
      ]);
      expect(zones.firstWhere((z) => z.name == 'Annex').front, 'Door');
      expect(zones.firstWhere((z) => z.name == 'Loft').front, isNull);
    });

    test('zonesOf leaves out seats that are not placed, keeps offline ones on the map, and keeps zones that differ by case apart', () {
      final zones = zonesOf([
        seat('placed', location: 'Reading Room A', row: 1, column: 1),
        seat('offline', location: 'Reading Room A', row: 1, column: 2, status: ResourceStatus.offline),
        seat('noRow', location: 'Reading Room A'),
        seat('noLocation', row: 3, column: 3),
        seat('blankLocation', location: '  ', row: 4, column: 4),
        seat('typo', location: 'Reading room A', row: 1, column: 1),
      ]);
      expect(zones.map((z) => z.name), ['Reading Room A', 'Reading room A']);
      expect(zones[0].desks.keys.toSet(), {(1, 1), (1, 2)});
      expect(zones[0].desks[(1, 2)]!.status, ResourceStatus.offline);
      expect(zones[0].rows, 1);
      expect(zones[0].columns, 2);
      expect(zones[1].desks.keys.toSet(), {(1, 1)});
    });

    test('zonesOf is empty when no seat is placed', () {
      expect(zonesOf([seat('a'), seat('b', location: 'Annex')]), isEmpty);
      expect(zonesOf(const []), isEmpty);
    });

    test('the demo layout reads as two zones of 80 and 48 desks', () {
      final zones = zonesOf(demoSeats());
      expect(zones.map((z) => z.name), ['Reading Room A', 'Silent Zone']);
      expect((zones[0].rows, zones[0].columns, zones[0].desks.length, zones[0].front), (8, 12, 80, 'Windows'));
      expect((zones[1].rows, zones[1].columns, zones[1].desks.length, zones[1].front), (6, 9, 48, 'Entrance'));
      expect(unplacedSeats(demoSeats()), isEmpty);
    });
  });

  group('unplacedSeats', () {
    test('unplacedSeats lists seats without a position or location and leaves out offline ones', () {
      final placed = seat('placed', location: 'Annex', row: 1, column: 1);
      final noPosition = seat('noPosition', location: 'Annex');
      final noColumn = seat('noColumn', location: 'Annex', row: 2);
      final noLocation = seat('noLocation', row: 1, column: 2);
      final blankLocation = seat('blankLocation', location: ' ', row: 1, column: 3);
      final offlineUnplaced = seat('offlineUnplaced', status: ResourceStatus.offline);
      final offlinePlaced = seat('offlinePlaced', location: 'Annex', row: 5, column: 5, status: ResourceStatus.offline);

      final result = unplacedSeats([placed, noPosition, noColumn, noLocation, blankLocation, offlineUnplaced, offlinePlaced]);
      expect(result.map((s) => s.id), ['noPosition', 'noColumn', 'noLocation', 'blankLocation']);
    });
  });
}
