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
}
