// test/models/resource_booking_status_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';

void main() {
  final start = DateTime(2026, 10, 10, 17);

  ResourceBooking booking(BookingStatus status, {int grace = 0}) => ResourceBooking(
        id: 'bk',
        resourceName: 'Silent Zone · Desk 3',
        type: ResourceType.seat,
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
        status: status,
        graceRemainingSeconds: grace,
      );

  test('stays upcoming until the start time', () {
    final b = booking(BookingStatus.upcomingFar).advancedTo(start.subtract(const Duration(seconds: 1)));
    expect(b.status, BookingStatus.upcomingFar);
  });

  test('opens the check-in window at the start time, with the full grace period', () {
    // Without this a booking made in advance never becomes checkable --
    // the list isn't refetched while the app stays open.
    final b = booking(BookingStatus.upcomingFar).advancedTo(start);
    expect(b.status, BookingStatus.inWindow);
    expect(b.graceRemainingSeconds, kCheckInGracePeriod.inSeconds);
  });

  test('counts grace down from the start time rather than per tick', () {
    // Recomputed, not decremented: a timer that stalls while the app is in
    // the background must not leave extra time on the clock.
    final b = booking(BookingStatus.inWindow, grace: 900).advancedTo(start.add(const Duration(minutes: 10)));
    expect(b.status, BookingStatus.inWindow);
    expect(b.graceRemainingSeconds, 300);
  });

  test('is released once the grace period has passed without a check-in', () {
    final b = booking(BookingStatus.inWindow, grace: 1).advancedTo(start.add(kCheckInGracePeriod + const Duration(seconds: 1)));
    expect(b.status, BookingStatus.released);
    expect(b.graceRemainingSeconds, 0);
  });

  test('an upcoming booking whose window passed entirely goes straight to released', () {
    final b = booking(BookingStatus.upcomingFar).advancedTo(start.add(const Duration(hours: 2)));
    expect(b.status, BookingStatus.released);
  });

  test('never moves backwards, if the device clock is behind the server\'s', () {
    // The server already said inWindow; a slow local clock mustn't hide the
    // Check In button again.
    final b = booking(BookingStatus.inWindow, grace: 600).advancedTo(start.subtract(const Duration(minutes: 1)));
    expect(b.status, BookingStatus.inWindow);
  });

  test('leaves checked-in and released bookings alone', () {
    final later = start.add(const Duration(hours: 3));
    expect(booking(BookingStatus.checkedIn).advancedTo(later).status, BookingStatus.checkedIn);
    expect(booking(BookingStatus.released).advancedTo(start).status, BookingStatus.released);
  });
}
