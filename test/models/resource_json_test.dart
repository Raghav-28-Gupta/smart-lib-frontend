// test/models/resource_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/bookings/time_slots.dart';
import 'package:smartlib_frontend/models/resource.dart';
import '../support/fixtures.dart';

void main() {
  List<Resource> parse(String name) => (fixture(name) as List)
      .map((j) => Resource.fromJson(j as Map<String, dynamic>))
      .toList();

  test('parses GET /resources/availability for seats', () {
    final seats = parse('resources_availability_seats');
    expect(seats, hasLength(4));
    final s1 = seats.singleWhere((r) => r.id == 's1');
    expect(s1.name, 'Reading Room A · Desk 12');
    expect(s1.type, ResourceType.seat);
    expect(s1.takenSlotsToday, ['11:00 AM', '12:00 PM']);
  });

  test('parses rooms, and a fully booked room lists the whole slot vocabulary', () {
    // The server builds these labels itself; r2 is seeded with every slot
    // taken, so this proves the two vocabularies agree over the wire, not
    // just in source.
    final r2 = parse('resources_availability_rooms').singleWhere((r) => r.id == 'r2');
    expect(r2.type, ResourceType.room);
    expect(r2.takenSlotsToday, kTimeSlots);
  });
}
