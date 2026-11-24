// test/features/bookings/bookings_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/core/router/app_router.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/auth/auth_repository.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/bookings/bookings_screen.dart';
import 'package:smartlib_frontend/models/app_user.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import 'package:smartlib_frontend/widgets/loading_skeleton.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/mock_overrides.dart';
import '../../support/note_field_expect.dart';

class _RefusingCheckIn extends MockBookingRepository {
  @override
  Future<ResourceBooking> checkIn(String bookingId) async =>
      throw const ConflictException('The grace period for this booking has passed.');
}

/// Serves exactly these bookings, with the network failing on demand.
class _ListedBookings extends MockBookingRepository {
  _ListedBookings(this.bookings);
  List<ResourceBooking> bookings;
  bool offline = false;

  @override
  Future<List<ResourceBooking>> myBookings() async {
    if (offline) throw const ApiException(0, ApiException.networkMessage);
    return List.of(bookings);
  }
}

/// [_ListedBookings] that counts how many times the list was fetched.
class _CountingBookings extends _ListedBookings {
  _CountingBookings(super.bookings);
  int fetches = 0;

  @override
  Future<List<ResourceBooking>> myBookings() {
    fetches++;
    return super.myBookings();
  }
}

ResourceBooking _room(String id, BookingStatus status, {String? reason}) {
  final start = DateTime.now().add(const Duration(hours: 20));
  return ResourceBooking(
    id: id, resourceName: 'Group Room 201', type: ResourceType.room, startTime: start,
    endTime: start.add(const Duration(hours: 1)), status: status,
    expiresAt: status == BookingStatus.requested ? start.add(kCheckInGracePeriod) : null,
    declineReason: reason,
  );
}

/// A seat booking the library cancelled, or moved from [movedFrom].
ResourceBooking _library(String id, BookingStatus status, {String? cancelReason, String? movedFrom}) {
  final start = DateTime.now().add(const Duration(hours: 20));
  return ResourceBooking(
    id: id, resourceName: 'Silent Zone · Desk 3', type: ResourceType.seat, startTime: start,
    endTime: start.add(const Duration(hours: 1)), status: status,
    cancelReason: cancelReason, movedFrom: movedFrom,
  );
}

/// The bookings a real backend returned for a library cancel and a library move.
List<ResourceBooking> _capturedLibraryBookings() => (fixture('bookings_me_library') as List)
    .map((j) => ResourceBooking.fromJson(j as Map<String, dynamic>))
    .where((b) => b.status == BookingStatus.cancelledByLibrary || b.movedFrom != null)
    .toList();

Future<void> _pumpBookings(WidgetTester tester, List<ResourceBooking> bookings) async {
  await tester.pumpWidget(ProviderScope(
    overrides: mockRepositoryOverrides(bookings: _ListedBookings(bookings)),
    child: MaterialApp(theme: buildSmartLibTheme(), home: const BookingsScreen()),
  ));
  await tester.pumpAndSettle();
}

/// The real app shell with a saved session. It lands on Home, which loads the
/// bookings list before My Bookings is ever opened -- the situation a student
/// is in when a librarian cancels or moves one of their bookings.
Future<ProviderContainer> _pumpApp(WidgetTester tester, _CountingBookings repo) async {
  final tokens = TokenStore(InMemoryTokenPersistence('saved-jwt'));
  final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: repo, tokens: tokens));
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: buildSmartLibTheme(), routerConfig: container.read(routerProvider)),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// Taps a bottom-nav tab, as the student does.
Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

/// A checked-in seat booking, which the student may report, has reported, or may not.
ResourceBooking _desk(String id, String name, {String? resourceId, bool canReport = false, bool reportOpen = false}) {
  final start = DateTime.now().subtract(const Duration(minutes: 10));
  return ResourceBooking(
    id: id, resourceId: resourceId ?? 'res-$id', resourceName: name, type: ResourceType.seat, startTime: start,
    endTime: start.add(const Duration(hours: 1)), status: BookingStatus.checkedIn,
    canReport: canReport, reportOpen: reportOpen,
  );
}

typedef _Sent = ({String resourceId, ResourceReportCategory category, String? note});

/// The listed bookings, where the server records a report (every booking of that
/// resource then reads reported) or refuses it with [refusal] until a test clears
/// it, and where its answer can be held back until [release].
class _ReportScript extends _ListedBookings {
  _ReportScript(super.bookings);

  ApiException? refusal;
  Completer<void>? release;

  /// Every report that reached the server, refused or not.
  final sent = <_Sent>[];

  @override
  Future<void> reportResource(String resourceId, ResourceReportCategory category, String? note) async {
    await release?.future;
    sent.add((resourceId: resourceId, category: category, note: note));
    final refused = refusal;
    if (refused != null) throw refused;
    bookings = [
      for (final b in bookings) b.resourceId == resourceId ? b.copyWith(reportOpen: true, canReport: false) : b,
    ];
  }
}

/// Logs in whoever asks, at once (the mock's 300 ms delay would need pumping).
class _InstantAuth extends MockAuthRepository {
  @override
  Future<AppUser> login(String email, String password) async =>
      AppUser(id: 'u-$email', name: email, email: email, roll: '1');
}

/// Serves [served] as it was when the request was made, with the answer held back
/// while [gate] is set: a student's list that is still on its way.
class _GatedBookings extends MockBookingRepository {
  List<ResourceBooking> served = [];
  bool failing = false;
  Completer<void>? gate;

  @override
  Future<List<ResourceBooking>> myBookings() async {
    final gate = this.gate;
    final answer = List.of(served);
    final fail = failing;
    await gate?.future;
    if (fail) throw const ApiException(500, 'The library server had a problem.');
    return answer;
  }
}

/// My Bookings with the toast layer, as the app mounts it.
Future<void> _pumpReporting(WidgetTester tester, MockBookingRepository repo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: mockRepositoryOverrides(bookings: repo),
    child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookingsScreen()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _showMyBookings(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookingsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the far-booking and in-window copy for the seeded bookings', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: mockRepositoryOverrides(), child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookingsScreen(),
    )));
    await tester.pumpAndSettle();
    // Check-in opens AT the start time, for 15 minutes (bookingService.ts
    // computeWindow) -- not before it.
    expect(find.textContaining('check-in opens at the start time'), findsOneWidget);
    expect(find.textContaining('Check in within'), findsOneWidget);
  });

  testWidgets('a refused check-in says why', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(bookings: _RefusingCheckIn()),
      child: MaterialApp(theme: buildSmartLibTheme(), builder: withToasts, home: const BookingsScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Check In'));
    await tester.pump();
    await tester.pump();
    expect(find.text('The grace period for this booking has passed.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('shows room requests: waiting with its deadline and Cancel, declined, expired and unknown', (tester) async {
    final repo = _ListedBookings([
      _room('bk-1', BookingStatus.requested),
      _room('bk-2', BookingStatus.declined, reason: 'Reserved for an event'),
      _room('bk-3', BookingStatus.declined),
      _room('bk-4', BookingStatus.expired),
      _room('bk-5', BookingStatus.unknown),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(bookings: repo),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookingsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Waiting for a librarian · held until '), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.text('Declined — Reserved for an event'), findsOneWidget);
    expect(find.text('Declined by the library'), findsOneWidget);
    expect(find.text('Expired — no librarian approved it in time'), findsOneWidget);
    expect(find.text("Update the app to see this item's status."), findsOneWidget);
  });

  testWidgets('while a room request waits, the list re-checks every 30 seconds and shows the answer', (tester) async {
    final repo = _ListedBookings([_room('bk-1', BookingStatus.requested)]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(bookings: repo),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookingsScreen()),
    ));
    await tester.pumpAndSettle();

    repo.bookings = [_room('bk-1', BookingStatus.upcomingFar)];
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(find.textContaining('check-in opens at the start time'), findsOneWidget);
  });

  testWidgets('a network blip during the re-check keeps the list on screen', (tester) async {
    final repo = _ListedBookings([_room('bk-1', BookingStatus.requested)]);
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(bookings: repo),
      child: MaterialApp(theme: buildSmartLibTheme(), home: const BookingsScreen()),
    ));
    await tester.pumpAndSettle();

    repo.offline = true;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(find.textContaining('Waiting for a librarian'), findsOneWidget);
    expect(find.text("Couldn't load your bookings"), findsNothing);
  });

  group('library cancel and move', () {
    testWidgets('shows "Cancelled by the library — <reason>" without buttons', (tester) async {
      // The captured payload carries the reason the librarian typed.
      final captured = _capturedLibraryBookings().where((b) => b.status == BookingStatus.cancelledByLibrary).toList();
      expect(captured, hasLength(1));
      await _pumpBookings(tester, captured);

      expect(find.text('Cancelled by the library — Room closed for maintenance'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
      expect(find.text('Check In'), findsNothing);
    });

    testWidgets('shows "Cancelled by the library" when there is no reason', (tester) async {
      await _pumpBookings(tester, [_library('bk-1', BookingStatus.cancelledByLibrary)]);

      expect(find.text('Cancelled by the library'), findsOneWidget);
      expect(find.textContaining('—'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
      expect(find.text('Check In'), findsNothing);
    });

    testWidgets('a moved booking shows the move line', (tester) async {
      final moved = _capturedLibraryBookings().singleWhere((b) => b.movedFrom != null);
      await _pumpBookings(tester, [moved]);

      expect(find.text('Moved from ${moved.movedFrom} by the library'), findsOneWidget);
      // Still a live booking on its new resource: its own status and buttons stay.
      expect(find.textContaining('check-in opens at the start time'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('a booking that was not moved shows no move line', (tester) async {
      await _pumpBookings(tester, [_library('bk-1', BookingStatus.upcomingFar)]);

      expect(find.textContaining('Moved from'), findsNothing);
    });

    testWidgets('an unknown status still shows the update notice', (tester) async {
      await _pumpBookings(tester, [_library('bk-1', BookingStatus.unknown)]);

      expect(find.text("Update the app to see this item's status."), findsOneWidget);
      expect(find.textContaining('Cancelled by the library'), findsNothing);
    });
  });

  group('opening My Bookings refreshes the list', () {
    testWidgets('a library cancel or move made after the list loaded shows each time the student opens My Bookings', (tester) async {
      final repo = _CountingBookings([_library('bk-1', BookingStatus.upcomingFar)]);
      final container = await _pumpApp(tester, repo);
      expect(repo.fetches, 1); // Home loaded the list

      // A librarian cancels one booking while the student is on Home.
      repo.bookings = [
        ...repo.bookings,
        _library('bk-2', BookingStatus.cancelledByLibrary, cancelReason: 'Room closed for maintenance'),
      ];
      await _openTab(tester, 'Bookings');
      expect(find.text('Cancelled by the library — Room closed for maintenance'), findsOneWidget);
      expect(repo.fetches, 2);

      // The student leaves and the librarian moves another booking; coming
      // back to the tab shows it too.
      await _openTab(tester, 'Home');
      repo.bookings = [
        ...repo.bookings,
        _library('bk-3', BookingStatus.upcomingFar, movedFrom: 'Reading Room A · Desk 12'),
      ];
      await _openTab(tester, 'Bookings');
      expect(find.text('Moved from Reading Room A · Desk 12 by the library'), findsOneWidget);
      expect(repo.fetches, 3);

      // Home starts the bookings timer; dispose inside the test body so it is
      // cancelled before the binding checks for pending timers.
      container.dispose();
    });

    testWidgets('a failed quiet refresh on open keeps the loaded list on screen', (tester) async {
      final repo = _CountingBookings([
        _library('bk-1', BookingStatus.upcomingFar),
        _library('bk-2', BookingStatus.cancelledByLibrary, cancelReason: 'Room closed for maintenance'),
      ]);
      final container = await _pumpApp(tester, repo);

      repo.offline = true;
      await _openTab(tester, 'Bookings');

      expect(repo.fetches, 2); // it did ask the server, and the ask failed
      expect(find.text('Cancelled by the library — Room closed for maintenance'), findsOneWidget);
      expect(find.textContaining('check-in opens at the start time'), findsOneWidget);
      expect(find.text("Couldn't load your bookings"), findsNothing);
      container.dispose();
    });

    testWidgets('opening it while a room request is pending still fetches only once', (tester) async {
      // PendingRefresh also re-checks right after the first frame when it opens
      // active; the two share one fetch rather than asking the server twice.
      final repo = _CountingBookings([_room('bk-1', BookingStatus.requested)]);
      final container = await _pumpApp(tester, repo);
      expect(repo.fetches, 1);

      await _openTab(tester, 'Bookings');

      expect(find.textContaining('Waiting for a librarian'), findsOneWidget);
      expect(repo.fetches, 2);
      container.dispose();
    });

    testWidgets('opening it before the list has loaded does not fetch a second time', (tester) async {
      final repo = _CountingBookings([_library('bk-1', BookingStatus.upcomingFar)]);
      await tester.pumpWidget(ProviderScope(
        overrides: mockRepositoryOverrides(bookings: repo),
        child: MaterialApp(theme: buildSmartLibTheme(), home: const BookingsScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('check-in opens at the start time'), findsOneWidget);
      expect(repo.fetches, 1); // the load itself is the fresh fetch
    });
  });

  group('reporting a seat or room', () {
    Finder reportButtons() => find.widgetWithText(TextButton, 'Report a problem');
    Finder noteField() => find.byType(TextField);
    Finder sendButton() => find.widgetWithText(FilledButton, 'Send');
    Finder dialog() => find.byType(AlertDialog);
    bool sendEnabled(WidgetTester tester) => tester.widget<FilledButton>(sendButton()).onPressed != null;

    // Opens the dialog on the first Report a problem button.
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(reportButtons().first);
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, String label) async {
      await tester.tap(find.descendant(of: dialog(), matching: find.text(label)));
      await tester.pumpAndSettle();
    }

    Future<void> typeNote(WidgetTester tester, String text) async {
      await tester.enterText(noteField(), text);
      await tester.pumpAndSettle();
    }

    // The toast stays up for 2.4 s; let it go so no timer outlives the test.
    Future<void> letToastGo(WidgetTester tester) => tester.pump(const Duration(seconds: 3));

    testWidgets('the button shows only when canReport', (tester) async {
      await _pumpReporting(tester, _ListedBookings([
        _desk('b1', 'Seat A1', canReport: true),
        _desk('b2', 'Seat A2'),
        _desk('b3', 'Seat A3', reportOpen: true),
      ]));

      expect(reportButtons(), findsOneWidget);
      Finder onCard(String name, Finder what) => find.descendant(of: find.widgetWithText(Card, name), matching: what);
      expect(onCard('Seat A1', reportButtons()), findsOneWidget);
      expect(onCard('Seat A1', find.text('Reported')), findsNothing);
      // A booking the server did not mark has neither the button nor a status.
      expect(onCard('Seat A2', reportButtons()), findsNothing);
      expect(onCard('Seat A2', find.text('Reported')), findsNothing);
      // A reported one reads Reported, in place of the button.
      expect(onCard('Seat A3', find.text('Reported')), findsOneWidget);
      expect(onCard('Seat A3', reportButtons()), findsNothing);
    });

    testWidgets('shows the button, then Reported, on the bookings the backend captured', (tester) async {
      List<ResourceBooking> captured(String name) =>
          (fixture(name) as List).map((j) => ResourceBooking.fromJson(j as Map<String, dynamic>)).toList();

      // Tall enough for every card: the list builds only the cards on screen, and the
      // captured list after the report has seven.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 3000);
      addTearDown(tester.view.reset);

      // Before the report: the checked-in desk offers it, and nothing reads Reported.
      final before = captured('bookings_me');
      final offered = before.where((b) => b.canReport).length;
      expect(offered, greaterThan(0));
      await _pumpReporting(tester, _ListedBookings(before));
      expect(reportButtons(), findsNWidgets(offered));
      expect(find.text('Reported'), findsNothing);

      // After it: every booking on that desk reads Reported, and none still offers the button.
      await tester.pumpWidget(const SizedBox());
      final after = captured('bookings_me_reported');
      final reported = after.where((b) => b.reportOpen).length;
      final stillOffered = after.where((b) => b.canReport).length;
      expect(reported, greaterThan(0));
      await _pumpReporting(tester, _ListedBookings(after));
      expect(find.text('Reported'), findsNWidgets(reported));
      expect(reportButtons(), findsNWidgets(stillOffered));
    });

    testWidgets("the button's label names the seat or room, as the cards' visible text is the same", (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpReporting(tester, _ListedBookings([
        _desk('b1', 'Seat A1', canReport: true),
        _desk('b2', 'Seat A2'),
        _desk('b3', 'Group Room 201', canReport: true),
      ]));

      expect(reportButtons(), findsNWidgets(2));
      expect(find.bySemanticsLabel('Report a problem with Seat A1'), findsOneWidget);
      expect(find.bySemanticsLabel('Report a problem with Group Room 201'), findsOneWidget);
      expect(find.bySemanticsLabel('Report a problem with Seat A2'), findsNothing);
      handle.dispose();
    });

    testWidgets('the dialog offers Not working, Dirty and Other with an optional note, and Send waits for a choice', (tester) async {
      await _pumpReporting(tester, _ListedBookings([_desk('b1', 'Seat A1', canReport: true)]));
      await openDialog(tester);

      expect(find.descendant(of: dialog(), matching: find.text('Report a problem')), findsOneWidget);
      expect(find.descendant(of: dialog(), matching: find.text('Seat A1')), findsOneWidget);
      expect(find.text('Not working'), findsOneWidget);
      expect(find.text('Dirty'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Note (optional)'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      // None is chosen for the student, so there is nothing to send yet.
      expect(tester.widget<RadioGroup<ResourceReportCategory>>(find.byType(RadioGroup<ResourceReportCategory>)).groupValue, isNull);
      expect(sendEnabled(tester), false);

      await choose(tester, 'Dirty');
      expect(sendEnabled(tester), true);
    });

    testWidgets('Other needs a note', (tester) async {
      final repo = _ReportScript([_desk('b1', 'Seat A1', canReport: true)]);
      await _pumpReporting(tester, repo);
      await openDialog(tester);

      await choose(tester, 'Other');
      expect(find.text('Note (required)'), findsOneWidget);
      expect(sendEnabled(tester), false);
      await tester.tap(sendButton());
      await tester.pump();
      expect(repo.sent, isEmpty);

      // Spaces are no note.
      await typeNote(tester, '    ');
      expect(sendEnabled(tester), false);

      await typeNote(tester, '  The chair has a broken leg.  ');
      expect(sendEnabled(tester), true);
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(repo.sent, [(resourceId: 'res-b1', category: ResourceReportCategory.other, note: 'The chair has a broken leg.')]);
      await letToastGo(tester);
    });

    testWidgets('the other categories send with no note, and with a trimmed one', (tester) async {
      final repo = _ReportScript([
        _desk('b1', 'Seat A1', canReport: true),
        _desk('b2', 'Seat A2', canReport: true),
      ]);
      await _pumpReporting(tester, repo);

      // A blank note is no note: the key is left out, never sent as an empty string.
      await openDialog(tester);
      await choose(tester, 'Not working');
      expect(find.text('Note (optional)'), findsOneWidget);
      await typeNote(tester, '   ');
      expect(sendEnabled(tester), true);
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(repo.sent.single, (resourceId: 'res-b1', category: ResourceReportCategory.notWorking, note: null));
      await letToastGo(tester);

      await openDialog(tester); // the first card now reads Reported, so this is Seat A2's button
      await choose(tester, 'Dirty');
      await typeNote(tester, '  Crumbs everywhere.  ');
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(repo.sent.last, (resourceId: 'res-b2', category: ResourceReportCategory.dirty, note: 'Crumbs everywhere.'));
      await letToastGo(tester);
    });

    group('the 300 limit, counted as the server counts it', () {
      // One emoji outside the BMP is a single character to the eye but two UTF-16 code units.
      const emoji = '\u{1F4A5}';

      Future<void> openWithDirty(WidgetTester tester) async {
        await _pumpReporting(tester, _ReportScript([_desk('b1', 'Seat A1', canReport: true)]));
        await openDialog(tester);
        await choose(tester, 'Dirty');
      }

      testWidgets('300 code units are accepted, 301 are not, and the counter says so', (tester) async {
        await openWithDirty(tester);

        await typeNote(tester, 'a' * 300);
        expect(find.text('300/300'), findsOneWidget);
        expect(sendEnabled(tester), true);

        await typeNote(tester, 'a' * 301);
        expect(find.text('301/300'), findsOneWidget);
        expect(sendEnabled(tester), false);

        // Spaces around the text are not counted: the server trims first.
        await typeNote(tester, '  ${'a' * 300}  ');
        expect(find.text('300/300'), findsOneWidget);
        expect(sendEnabled(tester), true);
      });

      testWidgets('a note of 301 code units that is only 151 characters to the eye keeps Send disabled', (tester) async {
        await openWithDirty(tester);

        final note = '${emoji * 150}a'; // 150 two-unit emoji and one letter
        expect(note.length, 301);
        expect(note.runes.length, 151);
        await typeNote(tester, note);
        expect(find.text('301/300'), findsOneWidget);
        expect(sendEnabled(tester), false);

        // Exactly 300 units (150 emoji) is fine.
        await typeNote(tester, emoji * 150);
        expect(find.text('300/300'), findsOneWidget);
        expect(sendEnabled(tester), true);
      });

      testWidgets('a note over the limit keeps Send disabled for Other too', (tester) async {
        await _pumpReporting(tester, _ReportScript([_desk('b1', 'Seat A1', canReport: true)]));
        await openDialog(tester);
        await choose(tester, 'Other');

        await typeNote(tester, 'b' * 301);
        expect(sendEnabled(tester), false);
        await typeNote(tester, 'b' * 300);
        expect(sendEnabled(tester), true);
      });

      testWidgets('over the limit the field says why in words, not only in colour, and the words go at 300', (tester) async {
        await openWithDirty(tester);

        await typeNote(tester, 'a' * 301);
        expect(find.text(noteTooLongMessage), findsOneWidget);
        expect(tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration.errorText, noteTooLongMessage);
        expect(tester.widget<Text>(find.text('301/300')).style?.color, Theme.of(tester.element(noteField())).colorScheme.error);
        expect(sendEnabled(tester), false);

        await typeNote(tester, emoji * 151);
        expect(find.text(noteTooLongMessage), findsOneWidget);
        expect(sendEnabled(tester), false);

        await typeNote(tester, emoji * 150);
        expect(find.text(noteTooLongMessage), findsNothing);
        expect(sendEnabled(tester), true);
      });
    });

    testWidgets('sending reports once, thanks the student, and every card of that seat reads Reported', (tester) async {
      final repo = _ReportScript([
        _desk('b1', 'Seat A1', resourceId: 's3', canReport: true),
        _desk('b2', 'Seat A1', resourceId: 's3', canReport: true),
        _desk('b3', 'Seat B2', resourceId: 's4', canReport: true),
      ]);
      await _pumpReporting(tester, repo);
      expect(reportButtons(), findsNWidgets(3));

      await openDialog(tester);
      await choose(tester, 'Not working');
      await typeNote(tester, 'The lamp is dead.');
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(repo.sent, [(resourceId: 's3', category: ResourceReportCategory.notWorking, note: 'The lamp is dead.')]);
      expect(dialog(), findsNothing);
      expect(find.text('Thanks, the library has your report.'), findsOneWidget);
      // Both bookings of that seat read Reported in place of the button; the other seat still offers it.
      expect(find.text('Reported'), findsNWidgets(2));
      expect(reportButtons(), findsOneWidget);
      expect(find.descendant(of: find.widgetWithText(Card, 'Seat B2'), matching: reportButtons()), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('Cancel closes the dialog and sends nothing', (tester) async {
      final repo = _ReportScript([_desk('b1', 'Seat A1', canReport: true)]);
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      await choose(tester, 'Dirty');
      await typeNote(tester, 'Crumbs everywhere.');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(dialog(), findsNothing);
      expect(repo.sent, isEmpty);
      expect(reportButtons(), findsOneWidget);
      expect(find.text('Reported'), findsNothing);

      // Reopened, it starts blank.
      await openDialog(tester);
      expect(tester.widget<RadioGroup<ResourceReportCategory>>(find.byType(RadioGroup<ResourceReportCategory>)).groupValue, isNull);
      expect(tester.widget<TextField>(noteField()).controller!.text, '');
    });

    for (final refusal in [
      const ConflictException('You already reported this. The library is looking into it.'),
      const ApiException(403, 'You can only report a seat or room you have booked.'),
    ]) {
      testWidgets('a ${refusal.statusCode} refusal keeps the dialog with its text and choices, and shows the server\'s message', (tester) async {
        final repo = _ReportScript([_desk('b1', 'Seat A1', canReport: true)])..refusal = refusal;
        await _pumpReporting(tester, repo);
        await openDialog(tester);
        await choose(tester, 'Other');
        await typeNote(tester, 'The chair has a broken leg.');
        await tester.tap(sendButton());
        await tester.pumpAndSettle();

        // The server's own words, the dialog still open, and the student's own choices still in it.
        expect(find.text(refusal.message), findsOneWidget);
        expect(dialog(), findsOneWidget);
        expect(tester.widget<TextField>(noteField()).controller!.text, 'The chair has a broken leg.');
        expect(tester.widget<RadioGroup<ResourceReportCategory>>(find.byType(RadioGroup<ResourceReportCategory>)).groupValue,
            ResourceReportCategory.other);
        expect(find.text('Thanks, the library has your report.'), findsNothing);
        expect(repo.sent, hasLength(1));
        // Send is usable again, and the same words go out on a second try.
        expect(sendEnabled(tester), true);
        await letToastGo(tester);

        repo.refusal = null;
        await tester.tap(sendButton());
        await tester.pumpAndSettle();
        expect(repo.sent, hasLength(2));
        expect(repo.sent.last, (resourceId: 'res-b1', category: ResourceReportCategory.other, note: 'The chair has a broken leg.'));
        expect(dialog(), findsNothing);
        expect(find.text('Reported'), findsOneWidget);
        await letToastGo(tester);
      });
    }

    testWidgets('a network failure keeps the dialog and says the library cannot be reached', (tester) async {
      final repo = _ReportScript([_desk('b1', 'Seat A1', canReport: true)])..refusal = const ApiException(0, ApiException.networkMessage);
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      await choose(tester, 'Dirty');
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.text(ApiException.networkMessage), findsOneWidget);
      expect(dialog(), findsOneWidget);
      expect(find.text('Reported'), findsNothing);
      await letToastGo(tester);
    });

    testWidgets('an expired session closes the dialog without a toast', (tester) async {
      final repo = _ReportScript([_desk('b1', 'Seat A1', canReport: true)])..refusal = const UnauthorizedException('Your session has expired.');
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      await choose(tester, 'Dirty');
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(dialog(), findsNothing);
      expect(find.text('Your session has expired.'), findsNothing);
    });

    testWidgets('a second tap on Send while the first is in flight sends nothing', (tester) async {
      final repo = _ReportScript([_desk('b1', 'Seat A1', canReport: true)])..release = Completer<void>();
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      await choose(tester, 'Dirty');

      await tester.tap(sendButton());
      await tester.pump();
      expect(sendEnabled(tester), false);
      await tester.tap(sendButton(), warnIfMissed: false);
      await tester.pump();

      repo.release!.complete();
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(1));
      expect(dialog(), findsNothing);
      await letToastGo(tester);
    });

    testWidgets('at phone width the dialog fits and Send can be reached', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 480);
      addTearDown(tester.view.reset);
      final repo = _ReportScript([_desk('b1', 'Reading Room A · Desk 12', canReport: true)]);
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      await choose(tester, 'Other');
      await typeNote(tester, 'The chair has a broken leg.');

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(sendButton());
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(1));
      await letToastGo(tester);
    });

    testWidgets('the note field draws a rounded rectangle under the app theme, and a long note fits a 360 x 740 phone', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 740);
      addTearDown(tester.view.reset);
      final repo = _ReportScript([_desk('b1', 'Reading Room A · Desk 12', canReport: true)]);
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      await choose(tester, 'Other');
      expectNoteFieldIsNotAPill(tester, noteField());

      await typeNote(tester, 'The chair has a broken leg. '.padRight(300, 'x'));
      expect(tester.takeException(), isNull);
      expectNoteFieldIsNotAPill(tester, noteField());

      await tester.ensureVisible(sendButton());
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(1));
      await letToastGo(tester);
    });
  });

  group('after one student logs out and another logs in', () {
    // The providers outlive the screen, which closes at logout and opens again for the
    // next student. Their bookings are fetched again, but Riverpod keeps the last
    // student's list on the loading state (and beside the error of a failed fetch).
    Future<ProviderContainer> openAsFirstStudent(WidgetTester tester, _GatedBookings repo, {bool retries = true}) async {
      final container = ProviderContainer(
        // Riverpod retries a failed fetch for about 40 seconds, showing it as a loading
        // state; a test about a fetch that has finally failed turns that off.
        retry: retries ? null : (_, __) => null,
        overrides: mockRepositoryOverrides(auth: _InstantAuth(), bookings: repo),
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).login('aditi.sharma@thapar.edu', 'anything');
      await _showMyBookings(tester, container);
      return container;
    }

    Future<void> openAsNextStudent(WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(const SizedBox());
      final auth = container.read(authControllerProvider.notifier);
      await auth.logOut();
      await auth.login('second@thapar.edu', 'anything');
      await _showMyBookings(tester, container);
    }

    final reportButton = find.widgetWithText(TextButton, 'Report a problem');

    testWidgets("a different student never sees the previous student's report state", (tester) async {
      final repo = _GatedBookings()
        ..served = [
          _desk('a1', 'Seat A1', canReport: true),
          _desk('a2', 'Seat A2', reportOpen: true),
        ];
      final container = await openAsFirstStudent(tester, repo);
      expect(reportButton, findsOneWidget);
      expect(find.text('Reported'), findsOneWidget);

      repo.served = [_desk('b1', 'Seat B1')];
      repo.gate = Completer<void>();
      await openAsNextStudent(tester, container);

      // Their bookings are on the way: nothing of the last student's shows, and neither
      // does a button that would report a seat on the last student's booking.
      expect(find.text('Seat A1'), findsNothing);
      expect(find.text('Seat A2'), findsNothing);
      expect(find.text('Reported'), findsNothing);
      expect(reportButton, findsNothing);
      expect(find.byType(LoadingSkeleton), findsWidgets);

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Seat B1'), findsOneWidget);
      // Their own booking is not one the server marked, so it has neither.
      expect(find.text('Reported'), findsNothing);
      expect(reportButton, findsNothing);
      container.dispose();
    });

    testWidgets("shows no report state, not the last student's, when the next student's fetch fails", (tester) async {
      final repo = _GatedBookings()
        ..served = [
          _desk('a1', 'Seat A1', canReport: true),
          _desk('a2', 'Seat A2', reportOpen: true),
        ];
      final container = await openAsFirstStudent(tester, repo, retries: false);
      expect(reportButton, findsOneWidget);

      repo.failing = true;
      await openAsNextStudent(tester, container);
      // The list's own one-second tick has run too: it must not turn the error back
      // into the last student's bookings.
      await tester.pump(const Duration(seconds: 2));

      expect(find.text("Couldn't load your bookings"), findsOneWidget);
      expect(find.text('Seat A1'), findsNothing);
      expect(find.text('Reported'), findsNothing);
      expect(reportButton, findsNothing);
      container.dispose();
    });
  });
}
