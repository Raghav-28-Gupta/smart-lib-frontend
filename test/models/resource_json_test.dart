// test/models/resource_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/bookings/time_slots.dart';
import 'package:smartlib_frontend/models/resource.dart';
import '../support/fixtures.dart';

void main() {
  List<Resource> parse(String name) => (fixture(name) as List)
      .map((j) => Resource.fromJson(j as Map<String, dynamic>))
      .toList();

  // Which of today's slots are taken depends on the time of day the capture ran: a
  // seeded booking that has passed (and a no-show the sweep recorded on it) no longer
  // holds its slot. So these assert what was captured, not a fixed set of hours.
  List<String> rawTaken(String name, String id) => ((fixture(name) as List).cast<Map<String, dynamic>>()
          .singleWhere((j) => j['id'] == id)['takenSlotsToday'] as List)
      .cast<String>();

  test('parses GET /resources/availability for seats', () {
    final seats = parse('resources_availability_seats');
    expect(seats, hasLength(4));
    final s1 = seats.singleWhere((r) => r.id == 's1');
    expect(s1.name, 'Reading Room A · Desk 12');
    expect(s1.type, ResourceType.seat);
    for (final seat in seats) {
      expect(seat.takenSlotsToday, rawTaken('resources_availability_seats', seat.id), reason: seat.id);
    }
  });

  test('parses rooms, and the server labels the taken slots in the app\'s own slot vocabulary', () {
    // The server builds these labels itself, so this proves the two vocabularies
    // agree over the wire, not just in source. r2 is seeded with every slot taken
    // (from 9 AM), so what the capture caught of it is the slots still ahead.
    final rooms = parse('resources_availability_rooms');
    final r2 = rooms.singleWhere((r) => r.id == 'r2');
    expect(r2.type, ResourceType.room);
    expect(r2.takenSlotsToday, isNotEmpty, reason: 'captured too late in the day: re-capture earlier');
    for (final room in rooms) {
      expect(room.takenSlotsToday, rawTaken('resources_availability_rooms', room.id), reason: room.id);
      expect(kTimeSlots, containsAll(room.takenSlotsToday), reason: room.id);
    }
    // In slot order, ending at the last slot of the day.
    expect(r2.takenSlotsToday, kTimeSlots.sublist(kTimeSlots.length - r2.takenSlotsToday.length));
  });

  Map<String, dynamic> placed({Object? status = 'available'}) => {
        'id': 's-rra-21',
        'type': 'seat',
        'name': 'Reading Room A · Desk 21',
        'location': 'Reading Room A',
        'capacity': 1,
        'takenSlotsToday': <String>[],
        'row': 3,
        'column': 5,
        'zoneFront': 'Windows',
        'status': status,
      };

  test('reads location, row, column, zoneFront and status', () {
    final seat = Resource.fromJson(placed());
    expect(seat.location, 'Reading Room A');
    expect(seat.row, 3);
    expect(seat.column, 5);
    expect(seat.zoneFront, 'Windows');
    expect(seat.status, ResourceStatus.available);
    expect(seat.isPlaced, true);

    final out = Resource.fromJson(placed(status: 'offline'));
    expect(out.status, ResourceStatus.offline);
    expect(out.isPlaced, true);

    // Nulls are what the server sends for a seat with no position or front.
    final unplaced = Resource.fromJson({...placed(), 'row': null, 'column': null, 'zoneFront': null});
    expect(unplaced.row, isNull);
    expect(unplaced.column, isNull);
    expect(unplaced.zoneFront, isNull);
    expect(unplaced.isPlaced, false);
  });

  test('an answer without the new fields reads as available and not placed', () {
    // The captured payload is an older server's: it has no row, column, zoneFront or
    // status. Every item must still parse.
    final seats = parse('resources_availability_seats');
    expect(seats, isNotEmpty);
    for (final seat in seats) {
      expect(seat.row, isNull, reason: seat.id);
      expect(seat.column, isNull, reason: seat.id);
      expect(seat.zoneFront, isNull, reason: seat.id);
      expect(seat.status, ResourceStatus.available, reason: seat.id);
      expect(seat.isPlaced, false, reason: seat.id);
    }
    expect(seats.singleWhere((r) => r.id == 's1').location, 'Reading Room A');

    // A key sent as null reads as available too.
    expect(Resource.fromJson(placed(status: null)).status, ResourceStatus.available);
  });

  test('an unknown status reads as available', () {
    expect(Resource.fromJson(placed(status: 'retired')).status, ResourceStatus.available);
  });

  test('a seat is placed only with a row, a column and a non-blank location', () {
    const base = Resource(id: 'x', name: 'Desk 1', type: ResourceType.seat, takenSlotsToday: [], location: 'Silent Zone', row: 1, column: 1);
    expect(base.isPlaced, true);
    expect(Resource.fromJson({...placed(), 'row': null}).isPlaced, false);
    expect(Resource.fromJson({...placed(), 'column': null}).isPlaced, false);
    expect(Resource.fromJson({...placed(), 'location': null}).isPlaced, false);
    expect(Resource.fromJson({...placed(), 'location': '   '}).isPlaced, false);
  });
}
