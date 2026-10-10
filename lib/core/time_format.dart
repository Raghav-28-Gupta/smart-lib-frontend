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

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// 'today, 3:00 PM', 'tomorrow, 9:00 AM', or 'Mon, 8:45 PM' further out --
/// for deadlines a day or two away, like a held copy's. Expects local times.
String dayTimeLabel(DateTime t, {required DateTime now}) {
  final days = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final day = switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    _ => _weekdays[t.weekday - 1],
  };
  return '$day, ${clockLabel(t)}';
}
