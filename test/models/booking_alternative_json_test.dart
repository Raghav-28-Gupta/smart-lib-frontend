// test/models/booking_alternative_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/time_format.dart';
import 'package:smartlib_frontend/models/booking_alternative.dart';
import 'package:smartlib_frontend/models/resource.dart';
import '../support/fixtures.dart';

void main() {
  List<BookingAlternative> fromConflict() {
    final body = fixture('booking_conflict_409') as Map<String, dynamic>;
    final details = body['details'] as Map<String, dynamic>;
    return (details['alternatives'] as List)
        .map((j) => BookingAlternative.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  test('parses both alternative kinds from a real 409', () {
    final alts = fromConflict();
    expect(alts, hasLength(2));
    // Same room, another hour...
    expect(alts[0].resourceId, 'r1');
    expect(alts[0].resourceName, 'Group Room 201 · 4 seats');
    expect(alts[0].resourceType, ResourceType.room);
    // ...and another room at the same hour.
    expect(alts[1].resourceId, 'r3');
    expect(alts[1].resourceType, ResourceType.room);
  });

  test('keeps the server\'s exact window, in local time', () {
    final raw = ((fixture('booking_conflict_409') as Map<String, dynamic>)['details']
        as Map<String, dynamic>)['alternatives'] as List;
    final alt = BookingAlternative.fromJson(raw.first as Map<String, dynamic>);
    expect(alt.startTime.isUtc, false);
    expect(alt.startTime.isAtSameMomentAs(DateTime.parse((raw.first as Map)['startTime'] as String)), true);
    // Derived from the start time rather than taken from the server's own
    // `timeSlot`, which the server formats in *its* timezone.
    expect(alt.timeSlot, clockLabel(alt.startTime));
  });

  test('timeSlot is the slot-chip label for its start time', () {
    final alt = BookingAlternative(
      resourceId: 's1',
      resourceName: 'Reading Room A · Desk 12',
      resourceType: ResourceType.seat,
      startTime: DateTime(2026, 9, 30, 17),
      endTime: DateTime(2026, 9, 30, 18),
    );
    expect(alt.timeSlot, '5:00 PM');
  });

  test('toResource builds the Resource the booking flow selects', () {
    final r = fromConflict().first.toResource();
    expect(r.id, 'r1');
    expect(r.name, 'Group Room 201 · 4 seats');
    expect(r.type, ResourceType.room);
    // The 409 carries no availability grid, and the confirm screen shows
    // none -- an empty list is honest, not a placeholder.
    expect(r.takenSlotsToday, isEmpty);
  });
}
