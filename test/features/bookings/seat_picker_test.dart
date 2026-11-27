// test/features/bookings/seat_picker_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/bookings/seat_picker.dart';
import 'package:smartlib_frontend/models/resource.dart';

void main() {
  // 2:20 PM: 9 AM to 2 PM are over (2 PM closed at 2:15), 3 PM is next.
  final afternoon = DateTime(2026, 11, 27, 14, 20);
  const seats = [Resource(id: 'a', name: 'Desk 1', type: ResourceType.seat, takenSlotsToday: [])];

  group('shownSlot', () {
    test('a chosen slot that is still open is the one shown', () {
      expect(shownSlot(seats, 0, '5:00 PM', now: afternoon), '5:00 PM');
    });

    test('a chosen slot that has passed falls back to the default', () {
      expect(shownSlot(seats, 0, '2:00 PM', now: afternoon), '3:00 PM');
      expect(shownSlot(seats, 0, '9:00 AM', now: afternoon), '3:00 PM');
    });

    test('the same slot on a later day has not passed', () {
      expect(shownSlot(seats, 1, '2:00 PM', now: afternoon), '2:00 PM');
    });

    test('no choice, or a time that is not a slot, falls back to the default', () {
      expect(shownSlot(seats, 0, null, now: afternoon), '3:00 PM');
      expect(shownSlot(seats, 0, '6:30 PM', now: afternoon), '3:00 PM');
    });
  });
}
