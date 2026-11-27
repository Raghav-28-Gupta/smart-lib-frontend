// lib/features/bookings/seat_map.dart
//
// The rules behind the Seats tab, as plain functions with no widgets: what a
// desk is called, which seats are free at a time, which times are open, what the
// tab opens on, and how the seats group into zone grids. The screen reads these;
// the server stays the judge of a booking.

import '../../core/time_format.dart';
import '../../models/resource.dart';
import 'time_slots.dart';

/// What a desk shows on the map: the last run of digits in its name ("Reading
/// Room A · Desk 14" is "14"), or its first 3 characters when it has none
/// ("Window Nook" is "Win"), so a desk is never an empty box.
String deskLabel(String name) {
  final digits = RegExp(r'\d+').allMatches(name);
  if (digits.isNotEmpty) return digits.last.group(0)!;
  return String.fromCharCodes(name.trim().runes.take(3));
}

/// Whether [seat] can be booked at [slot]: in service and not taken then. An
/// offline seat is never free, whatever its taken list says.
bool isFreeAt(Resource seat, String slot) =>
    seat.status == ResourceStatus.available && !seat.takenSlotsToday.contains(slot);

/// How many of [seats] are free at [slot]; an offline seat is never counted.
int freeCount(Iterable<Resource> seats, String slot) => seats.where((s) => isFreeAt(s, slot)).length;

/// How a time chip reads: bookable, over, or with no seat left.
enum SlotState { open, passed, full }

/// [SlotState] of [slot] on day [dateIndex]. `passed` wins over `full`, so a
/// slot that is over reads as over however many seats were taken in it.
SlotState slotState(List<Resource> seats, int dateIndex, String slot, {required DateTime now}) {
  if (slotHasPassed(dateIndex, slot, now: now)) return SlotState.passed;
  return freeCount(seats, slot) == 0 ? SlotState.full : SlotState.open;
}

/// The time the tab opens on: the first slot that is open, so today skips what
/// is over or full and a later day skips only what is full. Null when none is
/// left.
String? defaultSlot(List<Resource> seats, int dateIndex, {required DateTime now}) {
  for (final slot in kTimeSlots) {
    if (slotState(seats, dateIndex, slot, now: now) == SlotState.open) return slot;
  }
  return null;
}

/// When the one-hour [slot] ends: '7:00 PM' becomes '8:00 PM'.
String slotEndLabel(String slot) => clockLabel(slotWindow(0, slot).end);

/// One zone's grid: the placed seats of one location. [rows] and [columns] are
/// the largest row and column among them; a cell with no entry in [desks] is a
/// gap (an aisle or a missing desk).
class SeatZoneMap {
  SeatZoneMap({
    required this.name,
    required this.front,
    required this.rows,
    required this.columns,
    required this.desks,
  });

  final String name;

  /// What the zone's front faces ("Windows"), null when unset.
  final String? front;
  final int rows;
  final int columns;

  /// The zone's desks by `(row, column)`, 1-based. Offline desks are here too:
  /// they hold their place on the map.
  final Map<(int, int), Resource> desks;
}

/// The zones of [seats], one per location that has a placed seat, by name. A
/// location typed with another case is another zone, as the server keeps it.
/// Seats that are not placed are left to [unplacedSeats].
List<SeatZoneMap> zonesOf(List<Resource> seats) {
  final byName = <String, List<Resource>>{};
  for (final seat in seats.where((s) => s.isPlaced)) {
    byName.putIfAbsent(seat.location!, () => []).add(seat);
  }
  final zones = [
    for (final MapEntry(key: name, value: members) in byName.entries)
      SeatZoneMap(
        name: name,
        front: members.map((s) => s.zoneFront).firstWhere((f) => f != null && f.trim().isNotEmpty, orElse: () => null),
        rows: members.map((s) => s.row!).reduce((a, b) => a > b ? a : b),
        columns: members.map((s) => s.column!).reduce((a, b) => a > b ? a : b),
        desks: {for (final s in members) (s.row!, s.column!): s},
      ),
  ];
  zones.sort((a, b) {
    final byLetters = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byLetters != 0 ? byLetters : a.name.compareTo(b.name);
  });
  return zones;
}

/// The seats with no place on a map (no row, column or location), in the order
/// given. An offline one is left out: nobody can pick it, so it is not offered.
List<Resource> unplacedSeats(List<Resource> seats) =>
    seats.where((s) => !s.isPlaced && s.status != ResourceStatus.offline).toList();
