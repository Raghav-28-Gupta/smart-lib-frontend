// lib/features/bookings/demo_seat_layout.dart
//
// The demo seat map the mock repository serves: the same 128 desks, in the same
// two zones, as the backend seed (backend/prisma/seatLayout.ts). Keep the zone
// values below and that file's SEAT_ZONES in step.
//
// A zone is a grid of rows by columns. Desks stand only in `deskColumns`; the
// columns left out are aisles, so the map shows a gap there. Desk N is numbered
// row by row, left to right, over the desks only, from 1 in each zone.

import '../../models/resource.dart';

class _Zone {
  const _Zone(this.name, this.front, this.rows, this.deskColumns, this.idPrefix);
  final String name;
  final String front;
  final int rows;
  final List<int> deskColumns;

  /// A generated desk's id is `<idPrefix>-<N>`.
  final String idPrefix;
}

const _zones = [
  // 8 rows of 10, aisles after the 3rd and 7th desk, facing the windows.
  _Zone('Reading Room A', 'Windows', 8, [1, 2, 3, 5, 6, 7, 8, 10, 11, 12], 's-rra'),
  // 6 rows of 8, an aisle after the 4th, by the entrance.
  _Zone('Silent Zone', 'Entrance', 6, [1, 2, 3, 4, 6, 7, 8, 9], 's-sz'),
];

/// The four desks the mock always had, keyed by name: they keep their ids and
/// the slots taken today (served on day 0 only, as the mock always has). Every
/// other desk gets a generated id and nothing taken.
const _kept = <String, ({String id, List<String> taken})>{
  'Reading Room A · Desk 12': (id: 's1', taken: ['11:00 AM', '12:00 PM']),
  'Reading Room A · Desk 14': (id: 's2', taken: ['9:00 AM', '10:00 AM', '3:00 PM', '4:00 PM']),
  'Silent Zone · Desk 3': (id: 's3', taken: []),
  'Silent Zone · Desk 7': (id: 's4', taken: ['1:00 PM', '2:00 PM', '6:00 PM']),
};

/// Every desk of the demo layout, in zone order and then desk order. All are
/// placed and available.
List<Resource> demoSeats() {
  final seats = <Resource>[];
  for (final zone in _zones) {
    final perRow = zone.deskColumns.length;
    for (var n = 1; n <= zone.rows * perRow; n++) {
      final name = '${zone.name} · Desk $n';
      final kept = _kept[name];
      seats.add(Resource(
        id: kept?.id ?? '${zone.idPrefix}-$n',
        name: name,
        type: ResourceType.seat,
        takenSlotsToday: kept?.taken ?? const [],
        location: zone.name,
        row: (n - 1) ~/ perRow + 1,
        column: zone.deskColumns[(n - 1) % perRow],
        zoneFront: zone.front,
      ));
    }
  }
  return seats;
}
