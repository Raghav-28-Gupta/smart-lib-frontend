// test/features/bookings/booking_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/models/resource.dart';

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
}
