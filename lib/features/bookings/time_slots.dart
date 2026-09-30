// lib/features/bookings/time_slots.dart
//
// The booking slot vocabulary, and conversion between how the UI thinks
// about a slot -- (dateIndex, '5:00 PM') -- and how the API does: a
// `YYYY-MM-DD` date for availability, and UTC ISO timestamps for bookings.

/// One-hour slots offered by the booking flow. Mirrors TIME_SLOTS in
/// backend/src/config/constants.ts -- the availability endpoint reports taken
/// slots using exactly these labels, so the two lists must not drift.
const kTimeSlots = [
  '9:00 AM', '10:00 AM', '11:00 AM', '12:00 PM', '1:00 PM', '2:00 PM',
  '3:00 PM', '4:00 PM', '5:00 PM', '6:00 PM', '7:00 PM',
];

/// Start hour (24h, local time) of each slot in [kTimeSlots].
const kSlotHours = <String, int>{
  '9:00 AM': 9, '10:00 AM': 10, '11:00 AM': 11, '12:00 PM': 12,
  '1:00 PM': 13, '2:00 PM': 14, '3:00 PM': 15, '4:00 PM': 16,
  '5:00 PM': 17, '6:00 PM': 18, '7:00 PM': 19,
};

/// `YYYY-MM-DD` for the day [dateIndex] days after today -- the `date`
/// param GET /resources/availability expects.
String apiDate(int dateIndex, {DateTime? now}) {
  final day = _day(dateIndex, now);
  return '${day.year}-${_twoDigits(day.month)}-${_twoDigits(day.day)}';
}

/// Local start and end of the one-hour slot [label] on day [dateIndex].
({DateTime start, DateTime end}) slotWindow(int dateIndex, String label, {DateTime? now}) {
  final hour = kSlotHours[label];
  if (hour == null) throw ArgumentError.value(label, 'label', 'not a booking slot');
  final day = _day(dateIndex, now);
  return (
    start: DateTime(day.year, day.month, day.day, hour),
    end: DateTime(day.year, day.month, day.day, hour + 1),
  );
}

/// [slotWindow] as the UTC ISO strings POST /bookings requires. Its zod
/// schema rejects a timestamp with no offset, which is what
/// `toIso8601String()` produces for a local DateTime.
({String start, String end}) slotWindowIso(int dateIndex, String label, {DateTime? now}) {
  final window = slotWindow(dateIndex, label, now: now);
  return (start: window.start.toUtc().toIso8601String(), end: window.end.toUtc().toIso8601String());
}

// The DateTime constructor normalizes day/month overflow, so this avoids
// Duration arithmetic, which would drift by an hour across a DST change.
DateTime _day(int dateIndex, DateTime? now) {
  final today = now ?? DateTime.now();
  return DateTime(today.year, today.month, today.day + dateIndex);
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');
