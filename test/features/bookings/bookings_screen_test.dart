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
import 'package:smartlib_frontend/features/bookings/bookings_controller.dart';
import 'package:smartlib_frontend/features/bookings/bookings_screen.dart';
import 'package:smartlib_frontend/features/notices/notice_repository.dart';
import 'package:smartlib_frontend/features/notices/notices_controller.dart';
import 'package:smartlib_frontend/models/app_user.dart';
import 'package:smartlib_frontend/models/notice.dart';
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

/// A seat booking the library recorded as a no-show two days ago, as the server lists it:
/// its status stays released, and [noShow] says whether it may still be disputed and what
/// became of a dispute. [canReport] is the server's separate say on reporting the seat.
ResourceBooking _missed(String id, String name, {NoShowInfo noShow = const NoShowInfo(canDispute: true), bool canReport = false}) {
  final start = DateTime.now().subtract(const Duration(days: 2));
  return ResourceBooking(
    id: id, resourceId: 'res-$id', resourceName: name, type: ResourceType.seat, startTime: start,
    endTime: start.add(const Duration(hours: 1)), status: BookingStatus.released, canReport: canReport, noShow: noShow,
  );
}

/// A no-show that was disputed and answered (or not yet) as [status], with the library's [note].
NoShowInfo _disputed(NoShowDisputeStatus status, {String? note}) =>
    NoShowInfo(canDispute: false, dispute: NoShowDisputeInfo(status: status, note: note));

typedef _SentDispute = ({String bookingId, String reason});

/// The gated bookings where the server records a no-show dispute (the booking then reads
/// as an open dispute) or refuses it with [refusal] until a test clears it, and where the
/// answer can be held back until [release]. [served] is what the server holds.
class _DisputeScript extends _GatedBookings {
  _DisputeScript(List<ResourceBooking> bookings) {
    served = bookings;
  }

  ApiException? refusal;
  Completer<void>? release;

  /// Whether an accepted dispute changes [served]; a test about another student turns it off.
  bool records = true;

  /// Every dispute that reached the server, refused or not.
  final sent = <_SentDispute>[];

  @override
  Future<void> disputeNoShow(String bookingId, String reason) async {
    await release?.future;
    sent.add((bookingId: bookingId, reason: reason));
    final refused = refusal;
    if (refused != null) throw refused;
    if (records) {
      served = [
        for (final b in served) b.id == bookingId ? b.copyWith(noShow: _disputed(NoShowDisputeStatus.open)) : b,
      ];
    }
  }
}

/// The mock notices, counting fetches, with the network failing on demand.
class _CountingNotices extends MockNoticeRepository {
  _CountingNotices({super.notices});
  int fetches = 0;
  bool offline = false;

  @override
  Future<List<Notice>> myNotices() {
    fetches++;
    return offline ? Future.error(const ApiException(0, ApiException.networkMessage)) : super.myNotices();
  }
}

/// Serves [served] as it was when the request was made, with the answer held back
/// while [gate] is set: a student's notices that are still on their way.
class _GatedNotices extends MockNoticeRepository {
  List<Notice> served = [];
  bool failing = false;
  Completer<void>? gate;
  int fetches = 0;

  @override
  Future<List<Notice>> myNotices() async {
    fetches++;
    final gate = this.gate;
    final answer = List.of(served);
    final fail = failing;
    await gate?.future;
    if (fail) throw const ApiException(500, 'The library server had a problem.');
    return answer;
  }
}

Notice _notice(String id, NoticeKind kind, String title, String body, {DateTime? createdAt}) =>
    Notice(id: id, kind: kind, title: title, body: body, createdAt: createdAt ?? DateTime.now().subtract(const Duration(hours: 5)));

// The three kinds about a booking, as the server words them.
Notice _reminder() => _notice('r1', NoticeKind.bookingReminder, 'Your booking starts soon',
    'Group Room 201, 2–3 PM. Check in within 15 minutes of the start or the slot is released.');
Notice _missedNotice() => _notice('m1', NoticeKind.noShow, 'Missed booking',
    "You didn't check in to Seat A1 (Thu, Oct 22, 2–3 PM), so the slot was released and a no-show was recorded. "
        'Your reliability score went from 100 to 95. If this is wrong, you can dispute it from My Bookings within 7 days.');
Notice _outcomeNotice() => _notice('o1', NoticeKind.noShowOutcome, 'No-show removed',
    'The library removed the no-show for Seat A1 (Thu, Oct 22) and restored your reliability score to 100.');

// Kinds My Loans shows: a fine's outcome, an overdue notice, a report's outcome, and one this version does not know.
Notice _fineOutcomeNotice() => _notice('f1', NoticeKind.disputeOutcome, 'Your fine stands', 'The library kept your ₹30 fine for Sapiens.');
Notice _overdueNotice() => _notice('v1', NoticeKind.overdueReminder, 'Overdue book reminder', 'Your copy of Operating System Concepts is 3 days overdue.');
Notice _reportOutcomeNotice() => _notice('p1', NoticeKind.reportOutcome, 'Thanks for the report', 'Thanks for reporting a problem with Sapiens.');
Notice _unknownNotice() => _notice('u1', NoticeKind.unknown, 'A new sort of notice', 'Something the library wants you to read.');

/// My Bookings with these bookings and notices, in a tall window so every card is built.
Future<void> _pumpWithNotices(WidgetTester tester, MockBookingRepository bookings, MockNoticeRepository notices) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 3000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: mockRepositoryOverrides(bookings: bookings, notices: notices),
    child: MaterialApp(theme: buildSmartLibTheme(), home: const BookingsScreen()),
  ));
  await tester.pumpAndSettle();
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

  group('Library notices on My Bookings', () {
    // The three notices about a booking (a reminder, a recorded no-show, the answer to its
    // dispute) are listed here, at the top, from the same per-user controller My Loans reads.
    // The loan and fine kinds, and a kind this version does not know, stay on My Loans.
    final bookingTitles = ['Your booking starts soon', 'Missed booking', 'No-show removed'];
    final loanTitles = ['Your fine stands', 'Overdue book reminder', 'Thanks for the report', 'A new sort of notice'];

    // The lists were loaded earlier (the bookings on Home, the notices on My Loans, say), so
    // opening the screen is a refresh; [preloadBookings] false leaves the bookings unloaded.
    Future<ProviderContainer> loadedEarlier(
      WidgetTester tester,
      MockBookingRepository bookings,
      MockNoticeRepository notices, {
      bool preloadBookings = true,
      bool preloadNotices = true,
    }) async {
      // A tall window, so every card is built.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 3000);
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: bookings, notices: notices));
      addTearDown(container.dispose);
      if (preloadBookings) await container.read(bookingsControllerProvider.future);
      if (preloadNotices) await container.read(noticesControllerProvider.future);
      return container;
    }

    testWidgets('My Bookings shows only booking notices, above the bookings, and never a loan or fine notice', (tester) async {
      await _pumpWithNotices(
        tester,
        _ListedBookings([_library('bk-1', BookingStatus.upcomingFar)]),
        MockNoticeRepository(notices: [
          _reminder(),
          _fineOutcomeNotice(),
          _missedNotice(),
          _overdueNotice(),
          _outcomeNotice(),
          _reportOutcomeNotice(),
          _unknownNotice(),
        ]),
      );

      expect(find.text('Library notices'), findsOneWidget);
      for (final title in bookingTitles) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.textContaining('Group Room 201, 2–3 PM. Check in within 15 minutes'), findsOneWidget);
      expect(find.textContaining("You didn't check in to Seat A1 (Thu, Oct 22, 2–3 PM)"), findsOneWidget);
      expect(find.textContaining('The library removed the no-show for Seat A1'), findsOneWidget);
      // The loan and fine kinds, and the one this version does not know, are My Loans' (the
      // unknown one stays there: only the three booking kinds are moved).
      for (final title in loanTitles) {
        expect(find.text(title), findsNothing);
      }
      expect(find.text('Something the library wants you to read.'), findsNothing);

      // At the top: above the first booking.
      expect(find.text('Silent Zone · Desk 3'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Library notices')).dy, lessThan(tester.getTopLeft(find.text('Silent Zone · Desk 3')).dy));
      for (final title in bookingTitles) {
        expect(tester.getTopLeft(find.text(title)).dy, lessThan(tester.getTopLeft(find.text('Silent Zone · Desk 3')).dy));
      }
    });

    testWidgets('an empty list shows no section, and loan notices alone leave none', (tester) async {
      await _pumpWithNotices(tester, _ListedBookings([_library('bk-1', BookingStatus.upcomingFar)]), MockNoticeRepository());
      expect(find.text('Library notices'), findsNothing);
      expect(find.text('Silent Zone · Desk 3'), findsOneWidget);

      // Notices, but none about a booking: no heading, no cards, no empty text.
      await tester.pumpWidget(const SizedBox());
      await _pumpWithNotices(
        tester,
        _ListedBookings([_library('bk-1', BookingStatus.upcomingFar)]),
        MockNoticeRepository(notices: [_fineOutcomeNotice(), _overdueNotice(), _reportOutcomeNotice(), _unknownNotice()]),
      );
      expect(find.text('Library notices'), findsNothing);
      for (final title in loanTitles) {
        expect(find.text(title), findsNothing);
      }
      expect(find.text('Silent Zone · Desk 3'), findsOneWidget);
    });

    testWidgets('opening My Bookings refreshes the notices each visit', (tester) async {
      // Loaded earlier, so it can predate a reminder or the outcome of a dispute the library
      // wrote while the student was elsewhere.
      final bookings = _CountingBookings([_library('bk-1', BookingStatus.upcomingFar)]);
      final notices = _CountingNotices(notices: [_reminder()]);
      final container = await loadedEarlier(tester, bookings, notices);
      expect((bookings.fetches, notices.fetches), (1, 1));

      notices.notices = [_outcomeNotice(), _reminder()];
      await _showMyBookings(tester, container);

      expect((bookings.fetches, notices.fetches), (2, 2));
      expect(find.text('No-show removed'), findsOneWidget);
      expect(find.text('Your booking starts soon'), findsOneWidget);

      // Each visit builds a new screen, so the next one asks again.
      notices.notices = [_missedNotice(), _outcomeNotice(), _reminder()];
      await tester.pumpWidget(const SizedBox());
      await _showMyBookings(tester, container);
      expect((bookings.fetches, notices.fetches), (3, 3));
      expect(find.text('Missed booking'), findsOneWidget);
      container.dispose();
    });

    testWidgets('a failed quiet refresh of the notices on open keeps the last list on screen', (tester) async {
      final bookings = _CountingBookings([_library('bk-1', BookingStatus.upcomingFar)]);
      final notices = _CountingNotices(notices: [_reminder(), _missedNotice()]);
      final container = await loadedEarlier(tester, bookings, notices);

      notices.offline = true;
      await _showMyBookings(tester, container);

      expect(notices.fetches, 2); // it did ask, and the ask failed
      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('Your booking starts soon'), findsOneWidget);
      expect(find.text('Missed booking'), findsOneWidget);
      expect(find.text('Silent Zone · Desk 3'), findsOneWidget);
      expect(find.text("Couldn't load your bookings"), findsNothing);
      container.dispose();
    });

    testWidgets('opening it before the notices have loaded does not fetch a second time', (tester) async {
      final bookings = _CountingBookings([_library('bk-1', BookingStatus.upcomingFar)]);
      final notices = _CountingNotices(notices: [_reminder()]);
      await _pumpWithNotices(tester, bookings, notices);

      expect(find.text('Your booking starts soon'), findsOneWidget);
      expect((bookings.fetches, notices.fetches), (1, 1)); // the loads are the fresh fetches
    });

    testWidgets('opening it while a room request is pending still fetches the notices, and the bookings only once', (tester) async {
      // PendingRefresh also re-checks right after the first frame when it opens active; that
      // and the open share one fetch of the bookings. The notices are a list of their own.
      final bookings = _CountingBookings([_room('bk-1', BookingStatus.requested)]);
      final notices = _CountingNotices(notices: [_reminder()]);
      final container = await loadedEarlier(tester, bookings, notices);
      expect((bookings.fetches, notices.fetches), (1, 1));

      await _showMyBookings(tester, container);

      expect(find.textContaining('Waiting for a librarian'), findsOneWidget);
      expect(find.text('Your booking starts soon'), findsOneWidget);
      expect((bookings.fetches, notices.fetches), (2, 2));
      container.dispose();
    });

    testWidgets('opening it with a room request pending and the notices never loaded fetches the notices once', (tester) async {
      // The bookings were loaded on Home, so the screen opens already waiting and PendingRefresh
      // ticks right after the first frame; the notices are first loaded by this very screen, and
      // that load is the fresh fetch, so neither the open nor the tick asks a second time.
      final bookings = _CountingBookings([_room('bk-1', BookingStatus.requested)]);
      final notices = _CountingNotices(notices: [_reminder()]);
      final container = await loadedEarlier(tester, bookings, notices, preloadNotices: false);
      expect((bookings.fetches, notices.fetches), (1, 0));

      await _showMyBookings(tester, container);

      expect(find.text('Your booking starts soon'), findsOneWidget);
      expect((bookings.fetches, notices.fetches), (2, 1));
      container.dispose();
    });

    // While a room request waits, the screen re-checks every 30 seconds (PendingRefresh). That
    // re-check refreshes the notices too, through the same controller, so a reminder the library
    // wrote while the student waits here shows without reopening the screen.
    testWidgets('a booking notice written between ticks shows after the 30-second tick, without reopening', (tester) async {
      final bookings = _CountingBookings([_room('bk-1', BookingStatus.requested)]);
      final notices = _CountingNotices();
      await _pumpWithNotices(tester, bookings, notices);
      expect(find.textContaining('Waiting for a librarian'), findsOneWidget);
      expect(find.text('Library notices'), findsNothing);
      expect((bookings.fetches, notices.fetches), (1, 1));

      // The sweep writes the reminder while the student is looking at this screen.
      notices.notices = [_reminder()];
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('Your booking starts soon'), findsOneWidget);
      expect(find.textContaining('Waiting for a librarian'), findsOneWidget);
      // One request each: the tick asks the bookings and the notices once, no more.
      expect((bookings.fetches, notices.fetches), (2, 2));

      // And on every tick: the next notice shows after the next one.
      notices.notices = [_missedNotice(), _reminder()];
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Missed booking'), findsOneWidget);
      expect((bookings.fetches, notices.fetches), (3, 3));
    });

    testWidgets('a failing notices refresh on the tick leaves the notices and the bookings untouched', (tester) async {
      final bookings = _CountingBookings([_room('bk-1', BookingStatus.requested)]);
      final notices = _CountingNotices(notices: [_reminder()]);
      await _pumpWithNotices(tester, bookings, notices);
      expect(find.text('Your booking starts soon'), findsOneWidget);

      notices.offline = true;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      expect(notices.fetches, 2); // the tick did ask, and the ask failed
      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('Your booking starts soon'), findsOneWidget);
      expect(find.textContaining('Waiting for a librarian'), findsOneWidget);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets("a failing notices refresh does not stop the tick from showing the librarian's answer to the request", (tester) async {
      final bookings = _CountingBookings([_room('bk-1', BookingStatus.requested)]);
      final notices = _CountingNotices(notices: [_reminder()]);
      await _pumpWithNotices(tester, bookings, notices);

      // The librarian approves while the notices cannot be reached.
      bookings.bookings = [_room('bk-1', BookingStatus.upcomingFar)];
      notices.offline = true;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      expect(find.textContaining('check-in opens at the start time'), findsOneWidget);
      expect(find.textContaining('Waiting for a librarian'), findsNothing);
      expect(find.text('Your booking starts soon'), findsOneWidget); // the last list stays
      expect(notices.fetches, 2);
    });

    testWidgets('each list is skipped only while it is itself loading: loaded notices are refreshed when the bookings are not', (tester) async {
      // The notices were loaded earlier (on My Loans, say); nothing has loaded the bookings yet.
      final bookings = _GatedBookings()
        ..served = [_library('bk-1', BookingStatus.upcomingFar)]
        ..gate = Completer<void>();
      final notices = _CountingNotices(notices: [_reminder()]);
      final container = await loadedEarlier(tester, bookings, notices, preloadBookings: false);
      expect(notices.fetches, 1);

      await _showMyBookings(tester, container);
      expect(find.byType(LoadingSkeleton), findsWidgets); // the bookings are on their way
      expect(notices.fetches, 2); // and the notices were still asked again

      bookings.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Silent Zone · Desk 3'), findsOneWidget);
      expect(find.text('Your booking starts soon'), findsOneWidget);
      expect(notices.fetches, 2); // the section reading the list is not a fetch
      container.dispose();
    });

    testWidgets('the notices never delay the bookings: they show first, and the section joins when the notices arrive', (tester) async {
      final notices = _GatedNotices()
        ..served = [_reminder()]
        ..gate = Completer<void>();
      await _pumpWithNotices(tester, _ListedBookings([_library('bk-1', BookingStatus.upcomingFar)]), notices);

      // The bookings are on screen; the notices are still on their way.
      expect(find.text('Silent Zone · Desk 3'), findsOneWidget);
      expect(find.text('Library notices'), findsNothing);
      expect(find.text('Your booking starts soon'), findsNothing);

      notices.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('Your booking starts soon'), findsOneWidget);
      expect(find.text('Silent Zone · Desk 3'), findsOneWidget);
    });

    testWidgets('a list of notices that cannot be loaded shows nothing, not even an error, and leaves the bookings alone', (tester) async {
      final notices = _GatedNotices()..failing = true;
      await _pumpWithNotices(tester, _ListedBookings([_library('bk-1', BookingStatus.upcomingFar)]), notices);

      expect(find.text('Library notices'), findsNothing);
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('The library server had a problem.'), findsNothing);
      expect(find.text('Silent Zone · Desk 3'), findsOneWidget);
      expect(find.textContaining('check-in opens at the start time'), findsOneWidget);
    });

    testWidgets('the empty state is unchanged: the server lists the booking of every booking notice, so none stands alone', (tester) async {
      await _pumpWithNotices(tester, _ListedBookings([]), MockNoticeRepository(notices: [_reminder()]));

      expect(find.text('No upcoming bookings'), findsOneWidget);
      expect(find.text('Library notices'), findsNothing);
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

  group('a recorded no-show', () {
    const releasedText = 'This booking was released after the grace period.';
    const missedText = 'Missed. A no-show was recorded.';
    Finder disputeButtons() => find.widgetWithText(TextButton, 'Dispute');
    Finder reasonField() => find.byType(TextField);
    Finder sendButton() => find.widgetWithText(FilledButton, 'Send');
    Finder dialog() => find.byType(AlertDialog);
    bool sendEnabled(WidgetTester tester) => tester.widget<FilledButton>(sendButton()).onPressed != null;
    Finder onCard(String name, Finder what) => find.descendant(of: find.widgetWithText(Card, name), matching: what);

    // Every line of text on the card of [name], in order.
    List<String> textsOn(WidgetTester tester, String name) => [
          for (final t in tester.widgetList<Text>(onCard(name, find.byType(Text)))) t.data ?? '',
        ];

    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(disputeButtons().first);
      await tester.pumpAndSettle();
    }

    Future<void> typeReason(WidgetTester tester, String text) async {
      await tester.enterText(reasonField(), text);
      await tester.pumpAndSettle();
    }

    // The toast stays up for 2.4 s; let it go so no timer outlives the test.
    Future<void> letToastGo(WidgetTester tester) => tester.pump(const Duration(seconds: 3));

    testWidgets('a no-show booking shows the missed text and Dispute', (tester) async {
      // One booking, built once: its time slot is read from this same instance below.
      final booking = _missed('b1', 'Seat A1');
      await _pumpReporting(tester, _ListedBookings([booking]));

      expect(find.text(missedText), findsOneWidget);
      // In place of the released text, which a plain release keeps.
      expect(find.text(releasedText), findsNothing);
      expect(disputeButtons(), findsOneWidget);
      expect(find.text('Under review'), findsNothing);
      expect(textsOn(tester, 'Seat A1'), ['Seat A1', booking.timeSlot, missedText, 'Dispute']);
    });

    testWidgets('no Dispute button when canDispute is false or a dispute exists', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 3000);
      addTearDown(tester.view.reset);
      await _pumpReporting(tester, _ListedBookings([
        _missed('b1', 'Seat A1'),
        // The seven days passed: still a recorded no-show, but nothing to dispute.
        _missed('b2', 'Seat A2', noShow: const NoShowInfo(canDispute: false)),
        _missed('b3', 'Seat A3', noShow: _disputed(NoShowDisputeStatus.open)),
        _missed('b4', 'Seat A4', noShow: _disputed(NoShowDisputeStatus.overturned)),
        _missed('b5', 'Seat A5', noShow: _disputed(NoShowDisputeStatus.upheld)),
        _missed('b6', 'Seat A6', noShow: _disputed(NoShowDisputeStatus.unknown)),
        // A dispute that exists is the end of the button, whatever canDispute claims.
        _missed('b7', 'Seat A7', noShow: const NoShowInfo(canDispute: true, dispute: NoShowDisputeInfo(status: NoShowDisputeStatus.open))),
      ]));

      expect(disputeButtons(), findsOneWidget);
      expect(onCard('Seat A1', disputeButtons()), findsOneWidget);
      // The window closed: the missed text stays, and so does everything else it says.
      expect(onCard('Seat A2', find.text(missedText)), findsOneWidget);
      for (final name in ['Seat A2', 'Seat A3', 'Seat A4', 'Seat A5', 'Seat A6', 'Seat A7']) {
        expect(onCard(name, disputeButtons()), findsNothing, reason: name);
      }
    });

    testWidgets('a booking without noShow shows the released text', (tester) async {
      await _pumpReporting(tester, _ListedBookings([
        _library('b1', BookingStatus.released), // noShow null: a plain release
      ]));

      expect(find.text(releasedText), findsOneWidget);
      expect(find.text(missedText), findsNothing);
      expect(disputeButtons(), findsNothing);
      expect(find.text('Under review'), findsNothing);
    });

    testWidgets('an older server\'s released booking, with no noShow key at all, keeps the released text', (tester) async {
      // A payload as an older backend sends it (no `noShow`): a captured booking, released.
      final json = Map<String, dynamic>.from((fixture('bookings_me') as List).first as Map)
        ..['frontendStatus'] = 'released'
        ..remove('noShow');
      final booking = ResourceBooking.fromJson(json);
      expect(booking.noShow, isNull);
      await _pumpReporting(tester, _ListedBookings([booking]));

      expect(find.text(releasedText), findsOneWidget);
      expect(find.text(missedText), findsNothing);
      expect(disputeButtons(), findsNothing);
    });

    testWidgets('outcome texts', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 3000);
      addTearDown(tester.view.reset);
      const note = 'The scan log shows you checked in at 2:03.';
      // Each booking is built once: the expected time slot is read from the very instance the card draws.
      final open = _missed('b1', 'Seat A1', noShow: _disputed(NoShowDisputeStatus.open));
      final unknown = _missed('b2', 'Seat A2', noShow: _disputed(NoShowDisputeStatus.unknown, note: 'A later reply.'));
      final removed = _missed('b3', 'Seat A3', noShow: _disputed(NoShowDisputeStatus.overturned, note: note));
      final removedNoNote = _missed('b4', 'Seat A4', noShow: _disputed(NoShowDisputeStatus.overturned));
      final stands = _missed('b5', 'Seat A5', noShow: _disputed(NoShowDisputeStatus.upheld, note: 'The door log shows nobody came in.'));
      final standsEmptyNote = _missed('b6', 'Seat A6', noShow: _disputed(NoShowDisputeStatus.upheld, note: ''));
      await _pumpReporting(tester, _ListedBookings([open, unknown, removed, removedNoNote, stands, standsEmptyNote]));

      // Open: what is under review (the missed line), then "Under review", and no button.
      expect(textsOn(tester, 'Seat A1'), ['Seat A1', open.timeSlot, missedText, 'Under review']);
      // A status this version does not know reads as waiting, and says nothing of its note.
      expect(textsOn(tester, 'Seat A2'), ['Seat A2', unknown.timeSlot, missedText, 'Under review']);
      // Overturned: it is no longer a no-show, so only the answer, then the librarian's note on its own line.
      expect(textsOn(tester, 'Seat A3'), ['Seat A3', removed.timeSlot, 'No-show removed', note]);
      expect(textsOn(tester, 'Seat A4'), ['Seat A4', removedNoNote.timeSlot, 'No-show removed']);
      // Upheld: the no-show stands, so the missed line stays above the answer and the note; an empty note is no note.
      expect(textsOn(tester, 'Seat A5'),
          ['Seat A5', stands.timeSlot, missedText, 'No-show stands', 'The door log shows nobody came in.']);
      expect(textsOn(tester, 'Seat A6'), ['Seat A6', standsEmptyNote.timeSlot, missedText, 'No-show stands']);

      // Open, unknown and both upheld cards still say what was missed; the overturned ones do not.
      expect(find.text(missedText), findsNWidgets(4));
      expect(onCard('Seat A3', find.text(missedText)), findsNothing);
      expect(onCard('Seat A4', find.text(missedText)), findsNothing);
      expect(find.text(releasedText), findsNothing);
      expect(disputeButtons(), findsNothing);
    });

    testWidgets('a no-show can still be reported: Report a problem follows the missed line and the Dispute button', (tester) async {
      final booking = _missed('b1', 'Seat A1', canReport: true);
      await _pumpReporting(tester, _ListedBookings([booking]));

      expect(find.text(missedText), findsOneWidget);
      expect(disputeButtons(), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Report a problem'), findsOneWidget);
      // In this order, top to bottom.
      expect(textsOn(tester, 'Seat A1'), ['Seat A1', booking.timeSlot, missedText, 'Dispute', 'Report a problem']);
    });

    testWidgets("the Dispute button's label names the booking, as the cards' visible text is the same", (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpReporting(tester, _ListedBookings([
        _missed('b1', 'Seat A1'),
        _missed('b2', 'Group Room 201'),
        _missed('b3', 'Seat A3', noShow: const NoShowInfo(canDispute: false)),
      ]));

      expect(disputeButtons(), findsNWidgets(2)); // the visible text stays "Dispute"
      expect(find.bySemanticsLabel('Dispute the no-show for Seat A1'), findsOneWidget);
      expect(find.bySemanticsLabel('Dispute the no-show for Group Room 201'), findsOneWidget);
      expect(find.bySemanticsLabel('Dispute the no-show for Seat A3'), findsNothing);
      handle.dispose();
    });

    testWidgets('the dialog needs a reason and sends it, trimmed, for the booking whose button was pressed', (tester) async {
      // The plain mock: it records the dispute and lists the booking as an open one.
      final booking = _missed('b1', 'Seat A1'); // built once: its time slot is read from this instance below
      final repo = MockBookingRepository(bookings: [booking, _missed('b2', 'Seat A2')]);
      await _pumpReporting(tester, repo);
      await openDialog(tester);

      expect(find.text('Dispute this no-show'), findsOneWidget);
      expect(find.text('Why do you think this no-show is wrong?'), findsOneWidget);
      expect(find.text('0/300'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

      // Nothing to send until there is something to say: not even spaces.
      expect(sendEnabled(tester), false);
      await tester.tap(sendButton());
      await tester.pump();
      expect(repo.noShowDisputes, isEmpty);
      await typeReason(tester, '    ');
      expect(sendEnabled(tester), false);

      await typeReason(tester, '  The scanner was down.  ');
      expect(sendEnabled(tester), true);
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(repo.noShowDisputes, [(bookingId: 'b1', reason: 'The scanner was down.')]);
      expect(dialog(), findsNothing);
      expect(find.text('Dispute sent.'), findsOneWidget);
      // The first card now reads "Under review" under its missed line, in place of its button; the other still offers it.
      expect(onCard('Seat A1', find.text('Under review')), findsOneWidget);
      expect(textsOn(tester, 'Seat A1'), ['Seat A1', booking.timeSlot, missedText, 'Under review']);
      expect(onCard('Seat A1', disputeButtons()), findsNothing);
      expect(disputeButtons(), findsOneWidget);
      expect(onCard('Seat A2', disputeButtons()), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('sending marks Under review at once and survives an in-flight fetch finishing later', (tester) async {
      final booking = _missed('b1', 'Seat A1'); // built once: its time slot is read from this instance below
      final repo = _DisputeScript([booking]);
      final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: repo));
      addTearDown(container.dispose);
      await _showMyBookings(tester, container);

      // A quiet refresh is on the wire, and will answer with what the server knew before the dispute...
      repo.gate = Completer<void>();
      final staleGate = repo.gate!;
      final stale = container.read(bookingsControllerProvider.notifier).refreshQuietly();
      repo.gate = null;
      await openDialog(tester);
      await typeReason(tester, 'The scanner was down.');
      // ...when the dispute is sent and the server records it, and then the network drops
      // before the list is read again: only what the app marks itself can say "Under review".
      repo.failing = true;
      await tester.tap(sendButton());
      await tester.pump();
      await tester.pump();
      expect(repo.sent, [(bookingId: 'b1', reason: 'The scanner was down.')]);
      expect(dialog(), findsOneWidget); // waiting for the fetch that began before the dispute
      expect(sendEnabled(tester), false);

      staleGate.complete();
      await stale;
      await tester.pumpAndSettle();

      expect(dialog(), findsNothing);
      expect(find.text('Dispute sent.'), findsOneWidget);
      expect(textsOn(tester, 'Seat A1'), ['Seat A1', booking.timeSlot, missedText, 'Under review']);
      expect(disputeButtons(), findsNothing);
      expect(find.text("Couldn't load your bookings"), findsNothing);
      await letToastGo(tester);
      // The bookings timer is cancelled with the container; do it inside the test body,
      // before the binding checks for pending timers.
      container.dispose();
    });

    testWidgets('Cancel closes the dialog and sends nothing', (tester) async {
      final repo = _DisputeScript([_missed('b1', 'Seat A1')]);
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      await typeReason(tester, 'The scanner was down.');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(dialog(), findsNothing);
      expect(repo.sent, isEmpty);
      expect(disputeButtons(), findsOneWidget);
      expect(find.text('Under review'), findsNothing);

      // Reopened, it starts blank.
      await openDialog(tester);
      expect(tester.widget<TextField>(reasonField()).controller!.text, '');
    });

    testWidgets('a 409 keeps the dialog and the typed text', (tester) async {
      final repo = _DisputeScript([_missed('b1', 'Seat A1')])
        ..refusal = const ConflictException("You've already disputed this no-show.");
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      await typeReason(tester, 'The scanner was down.');
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // The server's own words, the dialog still open, and the student's own words still in it.
      expect(find.text("You've already disputed this no-show."), findsOneWidget);
      expect(dialog(), findsOneWidget);
      expect(find.text('Dispute this no-show'), findsOneWidget);
      expect(tester.widget<TextField>(reasonField()).controller!.text, 'The scanner was down.');
      expect(find.text('Dispute sent.'), findsNothing);
      expect(repo.sent, hasLength(1));
      // Send is usable again, and the same words go out on a second try.
      expect(sendEnabled(tester), true);
      await letToastGo(tester);

      repo.refusal = null;
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(2));
      expect(repo.sent.last, (bookingId: 'b1', reason: 'The scanner was down.'));
      expect(dialog(), findsNothing);
      expect(find.text('Under review'), findsOneWidget);
      await letToastGo(tester);
    });

    for (final refusal in [
      const ConflictException('The 7 days to dispute this no-show have passed.'),
      const ConflictException('This booking is not a recorded no-show.'),
      const ApiException(404, 'Booking not found'),
    ]) {
      testWidgets('a ${refusal.statusCode} refusal shows the server\'s message "${refusal.message}" and sends no "Under review"', (tester) async {
        final repo = _DisputeScript([_missed('b1', 'Seat A1')])..refusal = refusal;
        await _pumpReporting(tester, repo);
        await openDialog(tester);
        await typeReason(tester, 'I was there.');
        await tester.tap(sendButton());
        await tester.pumpAndSettle();

        expect(find.text(refusal.message), findsOneWidget);
        expect(dialog(), findsOneWidget);
        expect(tester.widget<TextField>(reasonField()).controller!.text, 'I was there.');
        // A refused dispute is never marked under review, here or on the card behind the dialog.
        expect(find.text('Under review'), findsNothing);
        await letToastGo(tester);
      });
    }

    testWidgets('a network failure keeps the dialog and says the library cannot be reached', (tester) async {
      final repo = _DisputeScript([_missed('b1', 'Seat A1')])..refusal = const ApiException(0, ApiException.networkMessage);
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      await typeReason(tester, 'I was there.');
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.text(ApiException.networkMessage), findsOneWidget);
      expect(dialog(), findsOneWidget);
      expect(tester.widget<TextField>(reasonField()).controller!.text, 'I was there.');
      expect(find.text('Under review'), findsNothing);
      await letToastGo(tester);
    });

    testWidgets('an expired session closes the dialog without a toast', (tester) async {
      final repo = _DisputeScript([_missed('b1', 'Seat A1')])..refusal = const UnauthorizedException('Your session has expired.');
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      await typeReason(tester, 'I was there.');
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(dialog(), findsNothing);
      expect(find.text('Your session has expired.'), findsNothing);
    });

    testWidgets('a second tap on Send while the first is in flight sends nothing', (tester) async {
      final repo = _DisputeScript([_missed('b1', 'Seat A1')])..release = Completer<void>();
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      await typeReason(tester, 'I was there.');

      await tester.tap(sendButton());
      await tester.pump();
      // The answer has not come: Send is off and the field cannot change under it.
      expect(sendEnabled(tester), false);
      expect(tester.widget<TextField>(reasonField()).enabled, false);
      await tester.tap(sendButton(), warnIfMissed: false);
      await tester.pump();
      expect(dialog(), findsOneWidget);

      repo.release!.complete();
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(1));
      expect(dialog(), findsNothing);
      expect(find.text('Under review'), findsOneWidget);
      await letToastGo(tester);
    });

    group('the 300 limit, counted as the server counts it', () {
      // One emoji outside the BMP is a single character to the eye but two UTF-16 code units.
      const emoji = '\u{1F4A5}';

      Future<_DisputeScript> openIt(WidgetTester tester) async {
        final repo = _DisputeScript([_missed('b1', 'Seat A1')]);
        await _pumpReporting(tester, repo);
        await openDialog(tester);
        return repo;
      }

      testWidgets('301 UTF-16 units disables Send, 300 do not, and the counter and the words say so', (tester) async {
        await openIt(tester);

        await typeReason(tester, 'a' * 300);
        expect(find.text('300/300'), findsOneWidget);
        expect(find.text(noteTooLongMessage), findsNothing);
        expect(sendEnabled(tester), true);

        await typeReason(tester, 'a' * 301);
        expect(find.text('301/300'), findsOneWidget);
        expect(find.text(noteTooLongMessage), findsOneWidget);
        expect(tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration.errorText, noteTooLongMessage);
        expect(tester.widget<Text>(find.text('301/300')).style?.color, Theme.of(tester.element(reasonField())).colorScheme.error);
        expect(sendEnabled(tester), false);
        // The student's own text is left alone, not cut to fit.
        expect(tester.widget<TextField>(reasonField()).controller!.text, 'a' * 301);

        // Spaces around the reason are not counted: the server trims first.
        await typeReason(tester, '  ${'a' * 300}  ');
        expect(find.text('300/300'), findsOneWidget);
        expect(sendEnabled(tester), true);
      });

      testWidgets('301 units that are only 151 characters to the eye keep Send disabled; 300 units are accepted', (tester) async {
        await openIt(tester);

        final reason = '${emoji * 150}a'; // 150 two-unit emoji and one letter
        expect(reason.length, 301);
        expect(reason.runes.length, 151); // Flutter's own maxLength would have let it through
        await typeReason(tester, reason);
        expect(find.text('301/300'), findsOneWidget);
        expect(sendEnabled(tester), false);

        await typeReason(tester, emoji * 150);
        expect(find.text('300/300'), findsOneWidget);
        expect(find.text(noteTooLongMessage), findsNothing);
        expect(sendEnabled(tester), true);
      });

      testWidgets('a reason of exactly 300 units goes out whole', (tester) async {
        final repo = await openIt(tester);

        await typeReason(tester, '   ${'a' * 300}   \n');
        await tester.tap(sendButton());
        await tester.pumpAndSettle();

        expect(repo.sent, [(bookingId: 'b1', reason: 'a' * 300)]);
        await letToastGo(tester);
      });
    });

    testWidgets('on a 360 x 740 phone the dialog fits with a long reason, its field is a rounded rectangle and Send can be reached', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 740);
      addTearDown(tester.view.reset);
      final repo = _DisputeScript([_missed('b1', 'Reading Room A · Desk 12')]);
      await _pumpReporting(tester, repo);
      await openDialog(tester);
      expectNoteFieldIsNotAPill(tester, reasonField());

      await typeReason(tester, 'The scanner was down. '.padRight(300, 'x'));
      expect(tester.takeException(), isNull);
      expectNoteFieldIsNotAPill(tester, reasonField());

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
    Future<ProviderContainer> openAsFirstStudent(
      WidgetTester tester,
      MockBookingRepository repo, {
      bool retries = true,
      MockNoticeRepository? notices,
    }) async {
      final container = ProviderContainer(
        // Riverpod retries a failed fetch for about 40 seconds, showing it as a loading
        // state; a test about a fetch that has finally failed turns that off.
        retry: retries ? null : (_, __) => null,
        overrides: mockRepositoryOverrides(auth: _InstantAuth(), bookings: repo, notices: notices),
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

    // The notices on this screen: the window where the next student's bookings have arrived and
    // their notices have not is where the last student's list could still show.
    testWidgets("an account switch never shows the previous student's notices on My Bookings, and never a loan notice", (tester) async {
      final repo = _GatedBookings()..served = [_library('a1', BookingStatus.upcomingFar)];
      final notices = _GatedNotices()..served = [_missedNotice(), _overdueNotice()];
      final container = await openAsFirstStudent(tester, repo, notices: notices);
      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('Missed booking'), findsOneWidget);
      expect(find.text('Overdue book reminder'), findsNothing); // a loan notice, for My Loans

      repo.served = [_library('b1', BookingStatus.upcomingFar)];
      notices.served = [_outcomeNotice(), _fineOutcomeNotice()];
      notices.gate = Completer<void>();
      await openAsNextStudent(tester, container);

      // Their bookings have arrived, so this is the window where their notices have not.
      expect(find.text('Silent Zone · Desk 3'), findsOneWidget);
      expect(find.text('Library notices'), findsNothing);
      expect(find.text('Missed booking'), findsNothing);
      expect(find.textContaining("You didn't check in to Seat A1"), findsNothing);

      notices.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Library notices'), findsOneWidget);
      expect(find.text('No-show removed'), findsOneWidget);
      expect(find.text('Missed booking'), findsNothing);
      expect(find.text('Your fine stands'), findsNothing);
      container.dispose();
    });

    testWidgets("shows no notices, not the last student's, when the next student's fetch fails", (tester) async {
      // Riverpod keeps the last student's value beside the error, too.
      final repo = _GatedBookings()..served = [_library('a1', BookingStatus.upcomingFar)];
      final notices = _GatedNotices()..served = [_missedNotice()];
      final container = await openAsFirstStudent(tester, repo, notices: notices, retries: false);
      expect(find.text('Missed booking'), findsOneWidget);

      notices.failing = true;
      await openAsNextStudent(tester, container);

      expect(find.text('Silent Zone · Desk 3'), findsOneWidget);
      expect(find.text('Library notices'), findsNothing);
      expect(find.text('Missed booking'), findsNothing);
      expect(find.textContaining("Couldn't load"), findsNothing);
      container.dispose();
    });

    testWidgets("does not show the last student's notices while the next student's fetch is being retried", (tester) async {
      final repo = _GatedBookings()..served = [_library('a1', BookingStatus.upcomingFar)];
      final notices = _GatedNotices()..served = [_missedNotice()];
      final container = await openAsFirstStudent(tester, repo, notices: notices);
      expect(find.text('Missed booking'), findsOneWidget);

      notices.failing = true;
      await openAsNextStudent(tester, container);

      expect(find.text('Library notices'), findsNothing);
      expect(find.text('Missed booking'), findsNothing);

      // Once the retries run out the error is final, and still not their value.
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Library notices'), findsNothing);
      expect(find.text('Missed booking'), findsNothing);
      container.dispose();
    });

    // The 30-second tick (while a room request waits) refreshes the notices too. Its answer can
    // be on the wire when the student logs out: it is the last student's, and must never show
    // for the next one, whether their own list has arrived or is still on its way.
    group("an account switch while the tick's notices refresh is in flight", () {
      // A's screen with a waiting room request and A's notice; the tick fires and the server has
      // not answered yet (it will answer with A's two notices). Returns the held answer's gate.
      Future<(ProviderContainer, _GatedBookings, _GatedNotices, Completer<void>)> aTickInFlight(WidgetTester tester) async {
        final repo = _GatedBookings()..served = [_room('a-room', BookingStatus.requested)];
        final notices = _GatedNotices()..served = [_missedNotice()];
        final container = await openAsFirstStudent(tester, repo, notices: notices);
        expect(find.text('Missed booking'), findsOneWidget);
        expect(notices.fetches, 1);

        notices.served = [_reminder(), _missedNotice()];
        notices.gate = Completer<void>();
        final stale = notices.gate!;
        await tester.pump(const Duration(seconds: 30));
        expect(notices.fetches, 2); // the tick asked the server for A's notices
        notices.gate = null;
        return (container, repo, notices, stale);
      }

      testWidgets("A's answer landing after B's notices arrived never shows A's notice", (tester) async {
        final (container, repo, notices, stale) = await aTickInFlight(tester);

        repo.served = [_library('b1', BookingStatus.upcomingFar)];
        notices.served = [_outcomeNotice()];
        await openAsNextStudent(tester, container);
        expect(find.text('No-show removed'), findsOneWidget);
        expect(find.text('Missed booking'), findsNothing);

        stale.complete();
        await tester.pumpAndSettle();

        expect(find.text('No-show removed'), findsOneWidget);
        expect(find.text('Missed booking'), findsNothing);
        expect(find.text('Your booking starts soon'), findsNothing);
        container.dispose();
      });

      testWidgets("A's answer landing while B's notices are still loading shows nothing of A's, and B's then arrive", (tester) async {
        final (container, repo, notices, stale) = await aTickInFlight(tester);

        repo.served = [_library('b1', BookingStatus.upcomingFar)];
        notices.served = [_outcomeNotice()];
        final bGate = Completer<void>();
        notices.gate = bGate;
        await openAsNextStudent(tester, container);
        expect(find.text('Silent Zone · Desk 3'), findsOneWidget);
        expect(find.text('Library notices'), findsNothing);

        stale.complete();
        await tester.pumpAndSettle();
        // A's late answer wrote nothing: B's list is still on its way, and none of A's shows.
        expect(find.text('Library notices'), findsNothing);
        expect(find.text('Missed booking'), findsNothing);
        expect(find.text('Your booking starts soon'), findsNothing);

        bGate.complete();
        await tester.pumpAndSettle();
        expect(find.text('No-show removed'), findsOneWidget);
        expect(find.text('Missed booking'), findsNothing);
        expect(find.text('Your booking starts soon'), findsNothing);
        container.dispose();
      });
    });

    final disputeButton = find.widgetWithText(TextButton, 'Dispute');
    const missedText = 'Missed. A no-show was recorded.';

    testWidgets("a different student never sees the previous student's no-show state", (tester) async {
      final repo = _GatedBookings()
        ..served = [
          _missed('a1', 'Seat A1'),
          _missed('a2', 'Seat A2', noShow: _disputed(NoShowDisputeStatus.open)),
          _missed('a3', 'Seat A3', noShow: _disputed(NoShowDisputeStatus.overturned, note: 'The scan log shows you checked in.')),
        ];
      final container = await openAsFirstStudent(tester, repo);
      expect(disputeButton, findsOneWidget);
      expect(find.text(missedText), findsNWidgets(2)); // the one to dispute, and the one under review
      expect(find.text('Under review'), findsOneWidget);
      expect(find.text('No-show removed'), findsOneWidget);
      expect(find.text('The scan log shows you checked in.'), findsOneWidget);

      repo.served = [_library('b1', BookingStatus.released)]; // B's booking was only released
      repo.gate = Completer<void>();
      await openAsNextStudent(tester, container);

      // Their bookings are on the way: nothing of the last student's no-shows shows, and
      // neither does a button that would dispute one of them.
      expect(find.text('Seat A1'), findsNothing);
      expect(find.text(missedText), findsNothing);
      expect(find.text('Under review'), findsNothing);
      expect(find.text('No-show removed'), findsNothing);
      expect(find.text('The scan log shows you checked in.'), findsNothing);
      expect(disputeButton, findsNothing);
      expect(find.byType(LoadingSkeleton), findsWidgets);

      repo.gate!.complete();
      await tester.pumpAndSettle();
      // Their own booking is a plain release: its old text, and none of the last student's.
      expect(find.text('This booking was released after the grace period.'), findsOneWidget);
      expect(find.text(missedText), findsNothing);
      expect(find.text('Under review'), findsNothing);
      expect(disputeButton, findsNothing);
      container.dispose();
    });

    testWidgets("shows no no-show state, not the last student's, when the next student's fetch fails", (tester) async {
      final repo = _GatedBookings()
        ..served = [
          _missed('a1', 'Seat A1'),
          _missed('a2', 'Seat A2', noShow: _disputed(NoShowDisputeStatus.upheld, note: 'The door log shows nobody came in.')),
        ];
      final container = await openAsFirstStudent(tester, repo, retries: false);
      expect(disputeButton, findsOneWidget);
      expect(find.text('No-show stands'), findsOneWidget);

      repo.failing = true;
      await openAsNextStudent(tester, container);
      await tester.pump(const Duration(seconds: 2)); // the list's own tick has run too

      expect(find.text("Couldn't load your bookings"), findsOneWidget);
      expect(find.text('Seat A1'), findsNothing);
      expect(find.text(missedText), findsNothing);
      expect(find.text('No-show stands'), findsNothing);
      expect(find.text('The door log shows nobody came in.'), findsNothing);
      expect(disputeButton, findsNothing);
      container.dispose();
    });

    testWidgets('an account switch while the dispute is in flight never shows it for the next student', (tester) async {
      // The same booking id on both accounts, to show A's answer is dropped, not just missed.
      final repo = _DisputeScript([_missed('shared', 'Seat A1')])..records = false;
      final container = await openAsFirstStudent(tester, repo);

      // A sends the dispute, and the server has not answered yet...
      repo.release = Completer<void>();
      final release = repo.release!;
      await tester.tap(disputeButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'The scanner was down.');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);

      // ...when A logs out and B logs in, whose own list is still on its way.
      repo.release = null;
      repo.served = [_missed('shared', 'Seat B1')];
      repo.gate = Completer<void>();
      await openAsNextStudent(tester, container);
      expect(find.byType(LoadingSkeleton), findsWidgets);

      release.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.sent, [(bookingId: 'shared', reason: 'The scanner was down.')]); // it did go out, for A

      // A's answer wrote nothing: B's list is still loading, and nothing of A's dispute shows.
      expect(find.byType(LoadingSkeleton), findsWidgets);
      expect(find.text('Under review'), findsNothing);
      expect(find.text('Seat A1'), findsNothing);
      expect(disputeButton, findsNothing);

      repo.gate!.complete();
      await tester.pumpAndSettle();
      // B's own booking has not been disputed by B: it offers the button, and says nothing of review.
      expect(find.text('Seat B1'), findsOneWidget);
      expect(find.text(missedText), findsOneWidget);
      expect(disputeButton, findsOneWidget);
      expect(find.text('Under review'), findsNothing);
      await tester.pump(const Duration(seconds: 3)); // A's toast goes
      container.dispose();
    });

    testWidgets("an account switch while the dispute is in flight: A's answer landing after B's list arrived marks nothing of B's", (tester) async {
      final repo = _DisputeScript([_missed('shared', 'Seat A1')])..records = false;
      final container = await openAsFirstStudent(tester, repo);

      repo.release = Completer<void>();
      final release = repo.release!;
      await tester.tap(disputeButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'The scanner was down.');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pump();

      // A logs out and B logs in, and B's list (a booking with the same id) arrives at once.
      repo.release = null;
      repo.served = [_missed('shared', 'Seat B1')];
      await openAsNextStudent(tester, container);
      expect(find.text('Seat B1'), findsOneWidget);
      expect(disputeButton, findsOneWidget);

      // Only now does the server answer A. B's booking must not read "Under review", and not
      // even when the network drops just then (so that no re-read of B's list could heal a mark).
      repo.failing = true;
      release.complete();
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(1));
      expect(find.text('Under review'), findsNothing);
      expect(find.text(missedText), findsOneWidget);
      expect(disputeButton, findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // A's toast goes
      container.dispose();
    });
  });
}
