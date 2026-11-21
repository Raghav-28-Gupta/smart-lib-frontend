// test/features/bookings/bookings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/core/router/app_router.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/bookings/bookings_screen.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/mock_overrides.dart';

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
}
