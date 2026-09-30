// lib/models/json_converters.dart
//
// Field converters shared by the generated fromJson code.

/// The backend serializes every timestamp as UTC (`...Z`), and
/// `DateTime.parse` keeps it UTC. Everything the UI renders -- due dates,
/// time-slot labels -- has to be in the device's local time, or a 5:00 PM
/// booking in India displays as 11:30 AM. Converting once, at the parse
/// boundary, means no screen has to remember to.
DateTime localDateTime(String value) => DateTime.parse(value).toLocal();
