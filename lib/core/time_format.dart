// lib/core/time_format.dart
//
// Clock-time labels in the app's one format -- '5:00 PM' -- shared by the
// booking slot vocabulary and the models' display getters, so a label built
// from a real timestamp always matches the slot chip it came from.

/// '9:00 AM', '12:00 PM', '5:30 PM'. Expects a local DateTime.
String clockLabel(DateTime t) {
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minutes = t.minute.toString().padLeft(2, '0');
  return '$hour12:$minutes ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// '3:00 – 5:00 PM' when both ends share a meridiem, otherwise
/// '11:00 AM – 1:00 PM'. The en dash matches the existing booking copy.
String timeRangeLabel(DateTime start, DateTime end) {
  final from = clockLabel(start);
  final to = clockLabel(end);
  final sameMeridiem = (start.hour < 12) == (end.hour < 12);
  return sameMeridiem ? '${from.substring(0, from.length - 3)} – $to' : '$from – $to';
}
