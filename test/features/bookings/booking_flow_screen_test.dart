// test/features/bookings/booking_flow_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/clock.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/bookings/booking_flow_screen.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/bookings/demo_seat_layout.dart';
import 'package:smartlib_frontend/features/bookings/seat_map_view.dart';
import 'package:smartlib_frontend/features/bookings/time_slots.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import '../../support/mock_overrides.dart';

/// Every booking is refused, with nothing else free to suggest.
class _NoAlternativesRepository extends MockBookingRepository {
  @override
  Future<ResourceBooking> createBooking({required Resource resource, required DateTime start, required DateTime end}) async =>
      throw BookingConflictException(const []);
}

/// The slot passed while the user sat on the confirm screen.
class _SlotPassedRepository extends MockBookingRepository {
  @override
  Future<ResourceBooking> createBooking({required Resource resource, required DateTime start, required DateTime end}) async =>
      throw const ApiException(400, 'That time slot has already passed. Pick a later one.');
}

/// The demo layout with Reading Room A's Desk 1 taken out of service.
class _OfflineDeskRepository extends MockBookingRepository {
  @override
  Future<List<Resource>> resources(ResourceType type, int dateIndex) async {
    if (type != ResourceType.seat) return super.resources(type, dateIndex);
    return [
      for (final s in demoSeats())
        if (s.id == 's-rra-1')
          Resource(
            id: s.id,
            name: s.name,
            type: s.type,
            takenSlotsToday: const [],
            location: s.location,
            row: s.row,
            column: s.column,
            zoneFront: s.zoneFront,
            status: ResourceStatus.offline,
          )
        else
          s,
    ];
  }
}

/// The demo layout plus one seat a librarian has not placed yet.
class _UnplacedSeatRepository extends MockBookingRepository {
  @override
  Future<List<Resource>> resources(ResourceType type, int dateIndex) async {
    final resources = await super.resources(type, dateIndex);
    if (type != ResourceType.seat) return resources;
    return [...resources, const Resource(id: 'x1', name: 'Annex · Desk 1', type: ResourceType.seat, takenSlotsToday: [])];
  }
}

/// The demo layout, where a test can take a seat at every time between loads
/// (someone else booked it, as far as the map can tell).
class _TakenLaterRepository extends MockBookingRepository {
  final takenEverywhere = <String>{};

  @override
  Future<List<Resource>> resources(ResourceType type, int dateIndex) async {
    final resources = await super.resources(type, dateIndex);
    return [
      for (final r in resources)
        if (takenEverywhere.contains(r.id))
          Resource(
            id: r.id,
            name: r.name,
            type: r.type,
            takenSlotsToday: kTimeSlots,
            location: r.location,
            row: r.row,
            column: r.column,
            zoneFront: r.zoneFront,
            status: r.status,
          )
        else
          r,
    ];
  }
}

/// The demo layout plus a placed desk whose name has no digits, in Reading Room
/// A's first aisle cell.
class _NamedDeskRepository extends MockBookingRepository {
  @override
  Future<List<Resource>> resources(ResourceType type, int dateIndex) async {
    final resources = await super.resources(type, dateIndex);
    if (type != ResourceType.seat) return resources;
    return [
      ...resources,
      const Resource(
        id: 'nook',
        name: 'Window Nook',
        type: ResourceType.seat,
        takenSlotsToday: [],
        location: 'Reading Room A',
        row: 1,
        column: 4,
        zoneFront: 'Windows',
      ),
    ];
  }
}

/// Counts how often the seats are loaded.
class _CountingRepository extends MockBookingRepository {
  int seatLoads = 0;

  @override
  Future<List<Resource>> resources(ResourceType type, int dateIndex) {
    if (type == ResourceType.seat) seatLoads++;
    return super.resources(type, dateIndex);
  }
}

Future<void> _pumpSeats(WidgetTester tester, {BookingRepository? repo, DateTime? now}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...mockRepositoryOverrides(bookings: repo),
      if (now != null) clockProvider.overrideWithValue(() => now),
    ],
    child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookingFlowScreen()),
  ));
  await tester.pumpAndSettle();
}

/// Scrolls the keyed widget into view (the page and the time strip both
/// scroll), then taps it.
Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

ChoiceChip _chip(WidgetTester tester, String key) => tester.widget<ChoiceChip>(find.byKey(Key(key)));

/// The time chip's first line, the slot itself.
Text _slotText(WidgetTester tester, String slot) =>
    tester.widget<Text>(find.descendant(of: find.byKey(Key('timeChip-$slot')), matching: find.text(slot)));

Finder _inTimeChip(String slot, String text) => find.descendant(of: find.byKey(Key('timeChip-$slot')), matching: find.text(text));

Finder _inBar(String text) => find.descendant(of: find.byKey(const Key('seatBar')), matching: find.text(text));

void main() {
  // ---- Seats: day, then time, then a desk on the map ----

  testWidgets('today at 2:20 PM, passed times are disabled and 3:00 PM shows "127 free"', (tester) async {
    await _pumpSeats(tester, now: DateTime(2026, 11, 27, 14, 20));

    // 2:00 PM's check-in window closed at 2:15.
    for (final slot in ['9:00 AM', '10:00 AM', '11:00 AM', '12:00 PM', '1:00 PM', '2:00 PM']) {
      expect(_chip(tester, 'timeChip-$slot').onSelected, isNull, reason: '$slot has passed');
      expect(_slotText(tester, slot).style?.decoration, TextDecoration.lineThrough, reason: '$slot is struck through');
    }
    // Desk 14 (s2) is taken at 3 PM today, so 127 of the 128 desks are free.
    expect(_chip(tester, 'timeChip-3:00 PM').onSelected, isNotNull);
    expect(_slotText(tester, '3:00 PM').style?.decoration, isNot(TextDecoration.lineThrough));
    expect(_inTimeChip('3:00 PM', '127 free'), findsOneWidget);
    // The first open time is the one picked.
    expect(_chip(tester, 'timeChip-3:00 PM').selected, isTrue);
    expect(_chip(tester, 'timeChip-2:00 PM').selected, isFalse);
  });

  testWidgets('tomorrow the first time is picked and Desk 14 sits in row 2 three columns right of Desk 12, past the aisle', (tester) async {
    await _pumpSeats(tester);
    await _tapKey(tester, 'dateChip-1');

    expect(_chip(tester, 'timeChip-9:00 AM').selected, isTrue);
    expect(_inTimeChip('9:00 AM', '128 free'), findsOneWidget);

    final desk12 = tester.getCenter(find.byKey(const Key('desk-s1'))); // row 2, column 2
    final desk13 = tester.getCenter(find.byKey(const Key('desk-s-rra-13'))); // row 2, column 3
    final desk14 = tester.getCenter(find.byKey(const Key('desk-s2'))); // row 2, column 5: column 4 is the aisle
    expect(desk14.dy, desk12.dy);
    expect(desk13.dx, greaterThan(desk12.dx));
    expect(desk14.dx - desk12.dx, closeTo(3 * (desk13.dx - desk12.dx), 0.01));
    // Desk 2 stands right in front of Desk 12, in row 1.
    final desk2 = tester.getCenter(find.byKey(const Key('desk-s-rra-2')));
    expect(desk2.dx, closeTo(desk12.dx, 0.01));
    expect(desk2.dy, lessThan(desk12.dy));
    // On the 800-wide test screen the map stops at 600 and is centred.
    expect(tester.getSize(find.byType(SeatMapView)).width, lessThanOrEqualTo(600));
    expect(tester.getCenter(find.byType(SeatMapView)).dx, closeTo(400, 0.01));

    expect(tester.getSemantics(find.byKey(const Key('desk-s1'))), isSemantics(label: 'Desk 12, free', isButton: true, isEnabled: true));
    expect(find.text('Pick a time'), findsOneWidget);
    expect(find.text('Pick a desk'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Taken'), findsOneWidget);
    expect(find.text('Your pick'), findsOneWidget);
    expect(find.text('Out of service'), findsNothing);
    expect(find.text('Not on the map yet'), findsNothing);
    expect(find.byKey(const Key('seatBar')), findsNothing);
  });

  testWidgets('a taken desk cannot be picked', (tester) async {
    await _pumpSeats(tester, now: DateTime(2026, 11, 27, 8));
    await _tapKey(tester, 'timeChip-3:00 PM');

    final desk14 = find.byKey(const Key('desk-s2'));
    expect(tester.getSemantics(desk14), isSemantics(label: 'Desk 14, taken', isButton: true, isEnabled: false));
    expect(tester.getSemantics(find.byKey(const Key('desk-s1'))), isSemantics(label: 'Desk 12, free', isButton: true));

    await tester.ensureVisible(desk14);
    await tester.pumpAndSettle();
    await tester.tap(desk14, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('seatBar')), findsNothing);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('picking a desk shows the bottom bar and Continue reaches Confirm booking, then Booked', (tester) async {
    await _pumpSeats(tester);
    await _tapKey(tester, 'dateChip-1');
    await _tapKey(tester, 'timeChip-9:00 AM');
    await _tapKey(tester, 'desk-s-rra-1');

    expect(tester.getSemantics(find.byKey(const Key('desk-s-rra-1'))), isSemantics(label: 'Desk 1, selected', isButton: true, isSelected: true));
    expect(_inBar('Reading Room A · Desk 1'), findsOneWidget);
    expect(_inBar('Tomorrow · 9:00 AM to 10:00 AM'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your booking'), findsOneWidget);
    expect(find.text('Confirm booking'), findsOneWidget);

    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();
    expect(find.text('Booked'), findsOneWidget);
  });

  testWidgets('Silent Zone shows its ENTRANCE front, and the zone stays selected when the time changes', (tester) async {
    await _pumpSeats(tester);
    await _tapKey(tester, 'dateChip-1');

    // Zones are alphabetical, and the first one opens.
    expect(find.text('Reading Room A · 80 free'), findsOneWidget);
    expect(find.text('Silent Zone · 48 free'), findsOneWidget);
    expect(_chip(tester, 'zoneChip-Reading Room A').selected, isTrue);
    expect(find.text('WINDOWS'), findsOneWidget);

    await _tapKey(tester, 'zoneChip-Silent Zone');
    expect(find.text('ENTRANCE'), findsOneWidget);
    expect(find.text('WINDOWS'), findsNothing);
    expect(find.byKey(const Key('desk-s3')), findsOneWidget);
    expect(find.byKey(const Key('desk-s1')), findsNothing);

    await _tapKey(tester, 'timeChip-5:00 PM');
    expect(_chip(tester, 'timeChip-5:00 PM').selected, isTrue);
    expect(_chip(tester, 'zoneChip-Silent Zone').selected, isTrue);
    expect(find.text('ENTRANCE'), findsOneWidget);
    expect(find.byKey(const Key('desk-s3')), findsOneWidget);
  });

  testWidgets('an offline desk shows out of service in its place, cannot be picked and is not counted', (tester) async {
    await _pumpSeats(tester, repo: _OfflineDeskRepository());
    await _tapKey(tester, 'dateChip-1');
    // At 5 PM none of the four kept desks is taken in the demo layout.
    await _tapKey(tester, 'timeChip-5:00 PM');

    final desk1 = find.byKey(const Key('desk-s-rra-1'));
    expect(tester.getSemantics(desk1), isSemantics(label: 'Desk 1, out of service', isButton: true, isEnabled: false));
    // In its place: row 1, column 1, left of Desk 2.
    final desk2 = tester.getCenter(find.byKey(const Key('desk-s-rra-2')));
    expect(tester.getCenter(desk1).dy, desk2.dy);
    expect(tester.getCenter(desk1).dx, lessThan(desk2.dx));
    // Not counted: 127 of 128 at this time, 79 of Reading Room A's 80.
    expect(_inTimeChip('5:00 PM', '127 free'), findsOneWidget);
    expect(find.text('Reading Room A · 79 free'), findsOneWidget);
    expect(find.text('Out of service'), findsOneWidget);

    await tester.ensureVisible(desk1);
    await tester.pumpAndSettle();
    await tester.tap(desk1, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('seatBar')), findsNothing);

    // The legend names it only for a zone that has one.
    await _tapKey(tester, 'zoneChip-Silent Zone');
    expect(find.text('Out of service'), findsNothing);
  });

  testWidgets('an unplaced seat is listed under Not on the map yet and can be booked', (tester) async {
    await _pumpSeats(tester, repo: _UnplacedSeatRepository());
    await _tapKey(tester, 'dateChip-1');

    expect(find.text('Not on the map yet'), findsOneWidget);
    expect(find.byKey(const Key('unplaced-x1')), findsOneWidget);
    // It counts towards the time, not towards a zone.
    expect(_inTimeChip('9:00 AM', '129 free'), findsOneWidget);
    expect(find.text('Reading Room A · 80 free'), findsOneWidget);

    await _tapKey(tester, 'unplaced-x1');
    expect(_chip(tester, 'unplaced-x1').selected, isTrue);
    expect(_inBar('Annex · Desk 1'), findsOneWidget);
    expect(_inBar('Tomorrow · 9:00 AM to 10:00 AM'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();
    expect(find.text('Booked'), findsOneWidget);
  });

  testWidgets('after the last slot today, No times left today offers See tomorrow, which moves to tomorrow', (tester) async {
    await _pumpSeats(tester, now: DateTime(2026, 11, 27, 19, 30));

    expect(find.text('No times left today'), findsOneWidget);
    for (final slot in kTimeSlots) {
      expect(_chip(tester, 'timeChip-$slot').onSelected, isNull, reason: '$slot has passed');
    }
    expect(find.byKey(const Key('desk-s1')), findsNothing);

    await _tapText(tester, 'See tomorrow');
    expect(_chip(tester, 'dateChip-1').selected, isTrue);
    expect(find.text('No times left today'), findsNothing);
    expect(_chip(tester, 'timeChip-9:00 AM').selected, isTrue);
    expect(find.byKey(const Key('desk-s1')), findsOneWidget);
  });

  testWidgets('the scripted conflict on Desk 12 tomorrow at 5:00 PM shows the alternatives, and back on the map 5:00 PM is still picked', (tester) async {
    await _pumpSeats(tester);
    await _tapKey(tester, 'dateChip-1');
    await _tapKey(tester, 'timeChip-5:00 PM');
    await _tapKey(tester, 'desk-s1');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();

    expect(find.text('That slot was just taken'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Reading Room A · Desk 12'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Silent Zone · Desk 3'), findsOneWidget);

    await tester.tap(find.text('Choose a different slot myself'));
    await tester.pumpAndSettle();
    expect(_chip(tester, 'timeChip-5:00 PM').selected, isTrue);
    // The refused desk is no longer the pick, and the reloaded map shows it taken.
    expect(find.byKey(const Key('seatBar')), findsNothing);
    expect(tester.getSemantics(find.byKey(const Key('desk-s1'))), isSemantics(label: 'Desk 12, taken'));
  });

  testWidgets("on a 320-wide screen Reading Room A's desks are at least 28 wide and the map scrolls sideways", (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    await _pumpSeats(tester);
    await _tapKey(tester, 'dateChip-1');

    final desk1 = find.byKey(const Key('desk-s-rra-1')); // row 1, column 1
    final desk10 = find.byKey(const Key('desk-s-rra-10')); // row 1, column 12: the far right
    expect(tester.getSize(desk1).width, greaterThanOrEqualTo(28));
    expect(tester.getSize(desk10).width, greaterThanOrEqualTo(28));
    expect(tester.getRect(desk10).right, greaterThan(320), reason: 'the zone is wider than the screen');

    await tester.ensureVisible(desk1);
    await tester.pumpAndSettle();
    final before = tester.getCenter(desk1).dx;
    await tester.drag(desk1, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tester.getCenter(desk1).dx, lessThan(before));
    expect(tester.getRect(desk10).right, lessThanOrEqualTo(320));
  });

  testWidgets('picking a time, a zone or a desk does not reload the seats; a new day does', (tester) async {
    final repo = _CountingRepository();
    await _pumpSeats(tester, repo: repo);
    await _tapKey(tester, 'dateChip-1');
    expect(repo.seatLoads, 2);

    await _tapKey(tester, 'timeChip-5:00 PM');
    await _tapKey(tester, 'zoneChip-Silent Zone');
    await _tapKey(tester, 'desk-s3');
    expect(find.byKey(const Key('seatBar')), findsOneWidget);
    expect(repo.seatLoads, 2);
  });

  testWidgets('a chosen time that has passed is let go: its chip is not selected and there is no bar', (tester) async {
    // 2:12 PM: 2:00 PM is open until 2:15, so it is the time shown.
    var now = DateTime(2026, 11, 27, 14, 12);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...mockRepositoryOverrides(),
        clockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookingFlowScreen()),
    ));
    await tester.pumpAndSettle();
    expect(_chip(tester, 'timeChip-2:00 PM').selected, isTrue);
    await _tapKey(tester, 'desk-s1');
    expect(find.byKey(const Key('seatBar')), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // The student lingers on the confirm step past 2:15, then goes back.
    now = DateTime(2026, 11, 27, 14, 16);
    await tester.tap(find.text('Change slot'));
    await tester.pumpAndSettle();

    expect(_chip(tester, 'timeChip-2:00 PM').selected, isFalse);
    expect(_chip(tester, 'timeChip-2:00 PM').onSelected, isNull);
    expect(_chip(tester, 'timeChip-3:00 PM').selected, isTrue);
    expect(find.byKey(const Key('seatBar')), findsNothing);
    expect(tester.getSemantics(find.byKey(const Key('desk-s1'))), isSemantics(label: 'Desk 12, free'));
  });

  testWidgets('a picked desk that becomes taken after a reload shows no bar', (tester) async {
    final repo = _TakenLaterRepository();
    await _pumpSeats(tester, repo: repo);
    await _tapKey(tester, 'dateChip-1');
    await _tapKey(tester, 'desk-s-rra-1');
    expect(find.byKey(const Key('seatBar')), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Someone else books it while the student is on the confirm step.
    repo.takenEverywhere.add('s-rra-1');
    await tester.tap(find.text('Change slot'));
    await tester.pumpAndSettle();

    expect(tester.getSemantics(find.byKey(const Key('desk-s-rra-1'))), isSemantics(label: 'Desk 1, taken'));
    expect(find.byKey(const Key('seatBar')), findsNothing);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('a picked conflict alternative reaches the confirm step, and Change slot keeps it in the bar', (tester) async {
    await _pumpSeats(tester);
    await _tapKey(tester, 'dateChip-1');
    await _tapKey(tester, 'timeChip-5:00 PM');
    await _tapKey(tester, 'desk-s1');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();

    // The first alternative is Desk 12 an hour later, at the server's own window.
    await tester.tap(find.widgetWithText(ListTile, 'Reading Room A · Desk 12'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your booking'), findsOneWidget);

    await tester.tap(find.text('Change slot'));
    await tester.pumpAndSettle();
    expect(_inBar('Reading Room A · Desk 12'), findsOneWidget);
    expect(_inBar('Tomorrow · 6:00 PM to 7:00 PM'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();
    expect(find.text('Booked'), findsOneWidget);
  });

  testWidgets("the bar names a desk without digits by its own name, not 'Desk Win'", (tester) async {
    await _pumpSeats(tester, repo: _NamedDeskRepository());
    await _tapKey(tester, 'dateChip-1');
    await _tapKey(tester, 'desk-nook');

    expect(tester.getSemantics(find.byKey(const Key('desk-nook'))), isSemantics(label: 'Desk Win, selected'));
    expect(_inBar('Window Nook'), findsOneWidget);
    expect(find.textContaining('Desk Win'), findsNothing);
  });

  testWidgets('a conflict with nothing else free says so, instead of an empty list', (tester) async {
    await _pumpSeats(tester, repo: _NoAlternativesRepository());
    await _tapKey(tester, 'dateChip-1');
    await _tapKey(tester, 'desk-s-rra-1');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();

    expect(find.text('That slot was just taken'), findsOneWidget);
    expect(find.text("Nothing similar is free right now. Try another time or day."), findsOneWidget);
    expect(find.textContaining("Here's what's still open"), findsNothing);
  });

  testWidgets('a refusal on confirm says why and stays on the confirm screen', (tester) async {
    await _pumpSeats(tester, repo: _SlotPassedRepository());
    await _tapKey(tester, 'dateChip-1');
    await _tapKey(tester, 'desk-s-rra-1');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pump();
    await tester.pump();

    expect(find.text('That time slot has already passed. Pick a later one.'), findsOneWidget);
    expect(find.text('Confirm your booking'), findsOneWidget);
    expect(find.text('Booked'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  // ---- Rooms: unchanged ----

  testWidgets('room type 2+ days out shows the no-rooms-free empty state', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(), child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookingFlowScreen(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rooms'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dateChip-2')));
    await tester.pumpAndSettle();
    expect(find.text('No rooms free on this date'), findsOneWidget);
  });

  testWidgets('booking a room sends a request, and says how long the slot is held', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(), child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookingFlowScreen(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rooms'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dateChip-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9:00 AM').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm your request'), findsOneWidget);
    expect(
      find.text('A librarian approves room bookings. If none does before your 15-minute grace period ends, the request expires.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();

    expect(find.text('Request sent'), findsOneWidget);
    expect(find.text("We'll hold the slot until tomorrow, 9:15 AM. Check My Bookings for the librarian's answer."), findsOneWidget);
    expect(find.text('View My Bookings'), findsOneWidget);
  });
}
