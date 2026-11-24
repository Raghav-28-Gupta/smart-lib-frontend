// test/features/bookings/bookings_controller_test.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/bookings/bookings_controller.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import '../../support/mock_overrides.dart';

class _CountingBookingRepository extends MockBookingRepository {
  int fetches = 0;
  @override
  Future<List<ResourceBooking>> myBookings() async {
    fetches++;
    return super.myBookings();
  }
}

class _RefusingBookingRepository extends _CountingBookingRepository {
  @override
  Future<ResourceBooking> checkIn(String bookingId) async =>
      throw const ConflictException('The grace period for this booking has passed.');
  @override
  Future<void> cancelBooking(String bookingId) async =>
      throw const ConflictException('This booking cannot be cancelled.');
}

typedef _Report = ({String resourceId, ResourceReportCategory category, String? note});

/// A seat booking that started ten minutes ago, as the server lists it.
ResourceBooking _seat(String id, {String resourceId = 's3', bool canReport = true, bool reportOpen = false}) {
  final start = DateTime.now().subtract(const Duration(minutes: 10));
  return ResourceBooking(
    id: id, resourceId: resourceId, resourceName: 'Seat $resourceId', type: ResourceType.seat, startTime: start,
    endTime: start.add(const Duration(hours: 1)), status: BookingStatus.checkedIn,
    canReport: canReport, reportOpen: reportOpen,
  );
}

/// Serves whatever [served] holds, counting fetches, with the network failing or the
/// answer held back on demand. The answer is what [served] held when the request was
/// made (what the server knew then), however long the gate holds it.
class _ScriptedBookings extends MockBookingRepository {
  _ScriptedBookings(this.served);

  List<ResourceBooking> served;
  int fetches = 0;
  bool offline = false;
  Completer<void>? gate;

  /// What the student sent, and what the "server" does with a report: [onReport] may
  /// change [served] (the server recording it) or throw (the server refusing it).
  final sent = <_Report>[];
  void Function(String resourceId)? onReport;

  /// Holds the answer to a report back until it completes.
  Completer<void>? reportGate;

  /// Holds the answer to a check-in or a cancel back until it completes, and refuses it
  /// with [writeError] instead when that is set (after the wait).
  Completer<void>? writeGate;
  Object? writeError;

  @override
  Future<ResourceBooking> checkIn(String bookingId) async {
    final booking = served.firstWhere((b) => b.id == bookingId); // as it was when the request was made
    await writeGate?.future;
    if (writeError != null) throw writeError!;
    return booking.copyWith(status: BookingStatus.checkedIn);
  }

  @override
  Future<void> cancelBooking(String bookingId) async {
    await writeGate?.future;
    if (writeError != null) throw writeError!;
  }

  @override
  Future<List<ResourceBooking>> myBookings() async {
    fetches++;
    final answer = List.of(served);
    await gate?.future;
    if (offline) throw const ApiException(0, ApiException.networkMessage);
    return answer;
  }

  @override
  Future<void> reportResource(String resourceId, ResourceReportCategory category, String? note) async {
    await reportGate?.future;
    sent.add((resourceId: resourceId, category: category, note: note));
    onReport?.call(resourceId);
  }

  /// The list as the server holds it once the student's report on [resourceId] is open.
  List<ResourceBooking> reported(String resourceId) => [
        for (final b in served) b.resourceId == resourceId ? b.copyWith(reportOpen: true, canReport: false) : b,
      ];
}

void main() {
  test('build() loads the 2 seeded bookings', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    final bookings = await container.read(bookingsControllerProvider.future);
    expect(bookings.length, 2);
  });

  test('the timer ticks down graceRemainingSeconds for the in-window booking', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container.read(bookingsControllerProvider.future);
    final before = container.read(bookingsControllerProvider).value!.firstWhere((b) => b.id == 'bk2').graceRemainingSeconds;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final after = container.read(bookingsControllerProvider).value!.firstWhere((b) => b.id == 'bk2').graceRemainingSeconds;
    expect(after, lessThan(before));
  });

  test('checkIn flips the booking to checkedIn in state', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container.read(bookingsControllerProvider.future);
    await container.read(bookingsControllerProvider.notifier).checkIn('bk2');
    final booking = container.read(bookingsControllerProvider).value!.firstWhere((b) => b.id == 'bk2');
    expect(booking.status, BookingStatus.checkedIn);
  });

  test('cancel removes the booking from state', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container.read(bookingsControllerProvider.future);
    await container.read(bookingsControllerProvider.notifier).cancel('bk1');
    final bookings = container.read(bookingsControllerProvider).value!;
    expect(bookings.any((b) => b.id == 'bk1'), false);
  });

  test("a different user logging in gets their own bookings, not the last user's", () async {
    final repo = _CountingBookingRepository();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: repo));
    addTearDown(container.dispose);
    final auth = container.read(authControllerProvider.notifier);

    await auth.login('aditi.sharma@thapar.edu', 'anything');
    await container.read(bookingsControllerProvider.future);
    await auth.logOut();
    await auth.register('Second Student', 'second@thapar.edu', 'password123');
    await container.read(bookingsControllerProvider.future);

    expect(repo.fetches, 2);
  });

  test('a refused check-in is reported, and the list is refetched -- it was stale', () async {
    final repo = _RefusingBookingRepository();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: repo));
    addTearDown(container.dispose);
    await container.read(bookingsControllerProvider.future);

    await expectLater(container.read(bookingsControllerProvider.notifier).checkIn('bk2'), throwsA(isA<ConflictException>()));
    await container.read(bookingsControllerProvider.future);
    expect(repo.fetches, 2);
  });

  test('a refused cancellation is reported, and the list is refetched', () async {
    final repo = _RefusingBookingRepository();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: repo));
    addTearDown(container.dispose);
    await container.read(bookingsControllerProvider.future);

    await expectLater(container.read(bookingsControllerProvider.notifier).cancel('bk1'), throwsA(isA<ConflictException>()));
    await container.read(bookingsControllerProvider.future);
    expect(repo.fetches, 2);
  });

  group('reportProblem', () {
    Future<(ProviderContainer, _ScriptedBookings)> loaded(List<ResourceBooking> bookings) async {
      final repo = _ScriptedBookings(bookings);
      final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: repo));
      addTearDown(container.dispose);
      await container.read(bookingsControllerProvider.future);
      return (container, repo);
    }

    test('reportProblem refreshes the bookings', () async {
      final container = ProviderContainer(overrides: mockRepositoryOverrides());
      addTearDown(container.dispose);
      final before = await container.read(bookingsControllerProvider.future);
      final target = before.firstWhere((b) => b.canReport);
      expect(target.reportOpen, false);

      await container.read(bookingsControllerProvider.notifier).reportProblem(target, ResourceReportCategory.dirty, null);

      final after = container.read(bookingsControllerProvider);
      expect(after.isLoading, false);
      expect(after.value!.firstWhere((b) => b.id == target.id).reportOpen, true);
      expect(after.value!.firstWhere((b) => b.id == target.id).canReport, false);
      // The other booking is another resource: untouched.
      final other = after.value!.firstWhere((b) => b.id != target.id);
      expect(other.reportOpen, false);
      expect(other.canReport, true);
    });

    test("sends the booking's resource, the category and the note, then reads the list again", () async {
      final (container, repo) = await loaded([_seat('b1'), _seat('b2', resourceId: 's4')]);
      repo.onReport = (id) => repo.served = repo.reported(id);
      expect(repo.fetches, 1);

      await container
          .read(bookingsControllerProvider.notifier)
          .reportProblem(repo.served.first, ResourceReportCategory.notWorking, 'The desk lamp does not switch on.');

      expect(repo.sent, [(resourceId: 's3', category: ResourceReportCategory.notWorking, note: 'The desk lamp does not switch on.')]);
      expect(repo.fetches, 2); // the load, and the read after the report
      final state = container.read(bookingsControllerProvider);
      expect(state.value!.map((b) => b.reportOpen), [true, false]);
      expect(state.value!.map((b) => b.canReport), [false, true]);
    });

    test('a blank note goes as no note', () async {
      final (container, repo) = await loaded([_seat('b1')]);
      await container.read(bookingsControllerProvider.notifier).reportProblem(repo.served.first, ResourceReportCategory.dirty, null);
      expect(repo.sent.single.note, isNull);
    });

    test('a fetch begun before the report cannot leave the button showing', () async {
      final (container, repo) = await loaded([_seat('b1')]);
      final notifier = container.read(bookingsControllerProvider.notifier);

      // A quiet refresh is on the wire, and will answer with what the server knew before the report...
      repo.gate = Completer<void>();
      final staleGate = repo.gate!;
      final stale = notifier.refreshQuietly();
      repo.gate = null;
      // ...when the report is written, and the server now has it.
      repo.onReport = (id) => repo.served = repo.reported(id);
      var done = false;
      final report = notifier.reportProblem(repo.served.first, ResourceReportCategory.dirty, null).then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, false); // waiting for the fetch that began before the write

      staleGate.complete();
      await stale;
      await report;

      final booking = container.read(bookingsControllerProvider).value!.single;
      expect(booking.reportOpen, true);
      expect(booking.canReport, false);
    });

    test('a read that fails after the report still shows it as reported', () async {
      final (container, repo) = await loaded([_seat('b1'), _seat('b2', resourceId: 's4')]);
      // The server records it, and then the network drops before the list is read again.
      repo.onReport = (id) {
        repo.served = repo.reported(id);
        repo.offline = true;
      };

      await container.read(bookingsControllerProvider.notifier).reportProblem(repo.served.first, ResourceReportCategory.dirty, null);

      final state = container.read(bookingsControllerProvider);
      expect(state.hasError, false);
      expect(state.value!.map((b) => b.reportOpen), [true, false]);
      expect(state.value!.map((b) => b.canReport), [false, true]);
    });

    for (final refusal in [
      const ConflictException('You already reported this. The library is looking into it.'),
      const ApiException(403, 'You can only report a seat or room you have booked.'),
      const ApiException(404, 'Not found.'),
    ]) {
      test('a ${refusal.statusCode} refusal reads the list again and tells the caller why', () async {
        final (container, repo) = await loaded([_seat('b1')]);
        // Another device reported it, so the list the student holds is out of date.
        repo.onReport = (id) {
          repo.served = repo.reported(id);
          throw refusal;
        };

        await expectLater(
          container.read(bookingsControllerProvider.notifier).reportProblem(repo.served.first, ResourceReportCategory.dirty, null),
          throwsA(isA<ApiException>().having((e) => e.message, 'message', refusal.message)),
        );

        expect(repo.fetches, 2);
        final state = container.read(bookingsControllerProvider);
        expect(state.hasError, false);
        expect(state.value!.single.reportOpen, true);
      });
    }

    test('a network failure tells the caller and does not read the list again', () async {
      final (container, repo) = await loaded([_seat('b1')]);
      repo.onReport = (_) => throw const ApiException(0, ApiException.networkMessage);

      await expectLater(
        container.read(bookingsControllerProvider.notifier).reportProblem(repo.served.first, ResourceReportCategory.dirty, null),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'isNetworkError', true)),
      );

      expect(repo.fetches, 1);
      expect(container.read(bookingsControllerProvider).value!.single.reportOpen, false);
    });
  });

  group('when a different student logs in', () {
    // Student A is logged in and has read their bookings; the next to log in is B.
    Future<(ProviderContainer, _ScriptedBookings, AuthController)> asStudentA() async {
      final repo = _ScriptedBookings([_seat('A-booking', resourceId: 'sA', reportOpen: true, canReport: false)]);
      // Riverpod retries a failed fetch for about 40 seconds; the test of a fetch that failed for good turns that off.
      final container = ProviderContainer(retry: (_, __) => null, overrides: mockRepositoryOverrides(bookings: repo));
      addTearDown(container.dispose);
      final auth = container.read(authControllerProvider.notifier);
      await auth.login('aditi.sharma@thapar.edu', 'anything');
      expect((await container.read(bookingsControllerProvider.future)).single.id, 'A-booking');
      return (container, repo, auth);
    }

    Future<void> switchToB(AuthController auth) async {
      await auth.logOut();
      await auth.register('Second Student', 'second@thapar.edu', 'password123');
    }

    test("A's refresh still in flight when B logs in lands without changing B's bookings", () async {
      final (container, repo, auth) = await asStudentA();
      container.listen(bookingsControllerProvider, (_, __) {});
      final notifier = container.read(bookingsControllerProvider.notifier);

      // A's quiet refresh is on the wire (it will answer with A's booking, reported)...
      repo.gate = Completer<void>();
      final staleGate = repo.gate!;
      final stale = notifier.refreshQuietly();
      // ...when A logs out and B logs in, whose own fetch answers at once.
      repo.gate = null;
      repo.served = [_seat('B-booking', resourceId: 'sB')];
      await switchToB(auth);
      expect((await container.read(bookingsControllerProvider.future)).single.id, 'B-booking');

      staleGate.complete();
      await stale;

      final booking = container.read(bookingsControllerProvider).value!.single;
      expect(booking.id, 'B-booking');
      expect(booking.reportOpen, false);
      expect(booking.canReport, true);
    });

    test("A's report still on the wire when B logs in does not mark B's bookings", () async {
      final (container, repo, auth) = await asStudentA();
      container.listen(bookingsControllerProvider, (_, __) {});
      final notifier = container.read(bookingsControllerProvider.notifier);

      // A's report is being sent (the server will accept it)...
      repo.reportGate = Completer<void>();
      final release = repo.reportGate!;
      final aReports = notifier.reportProblem(repo.served.first, ResourceReportCategory.dirty, null);
      // ...when A logs out and B logs in. B has a booking on the same desk, which the server does not mark for them.
      repo.reportGate = null;
      repo.served = [_seat('B-booking', resourceId: 'sA')];
      await switchToB(auth);
      expect((await container.read(bookingsControllerProvider.future)).single.id, 'B-booking');
      final fetchesBefore = repo.fetches;

      release.complete();
      await aReports;

      final booking = container.read(bookingsControllerProvider).value!.single;
      expect(booking.id, 'B-booking');
      expect(booking.reportOpen, false);
      expect(booking.canReport, true);
      expect(repo.fetches, fetchesBefore); // nothing was read on A's behalf
    });

    // A's write (a cancel or a check-in) is on the wire when A logs out and B logs in. While
    // B's own fetch is pending Riverpod still holds A's list on the state, so a local update
    // written from A's answer would put A's bookings (with A's report buttons) in front of B.
    for (final write in <(String, Future<void> Function(BookingsController))>[
      ('cancel', (c) => c.cancel('A-booking')),
      ('check-in', (c) => c.checkIn('A-booking')),
    ]) {
      test("A's ${write.$1} answering after B logged in leaves B's pending list alone", () async {
        final (container, repo, auth) = await asStudentA();
        container.listen(bookingsControllerProvider, (_, __) {});
        final notifier = container.read(bookingsControllerProvider.notifier);

        // A's write is being sent (the server will accept it)...
        repo.writeGate = Completer<void>();
        final release = repo.writeGate!;
        final aWrites = write.$2(notifier);
        // ...when A logs out and B logs in, whose own fetch is still on its way.
        repo.writeGate = null;
        repo.gate = Completer<void>();
        final bGate = repo.gate!;
        repo.served = [_seat('B-booking', resourceId: 'sB')];
        await switchToB(auth);
        expect(container.read(bookingsControllerProvider).isReloading, true); // A's list rides on the loading state

        release.complete();
        await aWrites;

        // Still loading B's list: A's answer wrote nothing, so A's bookings cannot be drawn as data.
        final during = container.read(bookingsControllerProvider);
        expect(during.isLoading, true);
        expect(during.isReloading, true);

        bGate.complete();
        final arrived = await container.read(bookingsControllerProvider.future);
        expect(arrived.single.id, 'B-booking');
        final state = container.read(bookingsControllerProvider);
        expect(state.isLoading, false);
        expect(state.value!.single.id, 'B-booking');
        expect(state.value!.single.canReport, true);
      });
    }

    test("A's refused cancel answering after B logged in does not reload B's list", () async {
      final (container, repo, auth) = await asStudentA();
      container.listen(bookingsControllerProvider, (_, __) {});
      final notifier = container.read(bookingsControllerProvider.notifier);

      repo.writeGate = Completer<void>();
      final release = repo.writeGate!;
      repo.writeError = const ConflictException('This booking cannot be cancelled.');
      final aCancels = notifier.cancel('A-booking');
      repo.writeGate = null;
      repo.served = [_seat('B-booking', resourceId: 'sB')];
      await switchToB(auth);
      await container.read(bookingsControllerProvider.future);
      final fetchesBefore = repo.fetches;

      release.complete();
      await expectLater(aCancels, throwsA(isA<ConflictException>())); // A still hears why

      await pumpEventQueue();
      expect(repo.fetches, fetchesBefore); // but A's stale answer does not make B's list load again
      expect(container.read(bookingsControllerProvider).value!.single.id, 'B-booking');
    });

    test('within one student a cancel still removes the booking and a check-in still updates it', () async {
      final (container, repo, _) = await asStudentA();
      repo.served = [
        _seat('A-booking', resourceId: 'sA', canReport: false),
        _seat('A-2', resourceId: 'sA2').copyWith(status: BookingStatus.inWindow),
      ];
      await container.read(bookingsControllerProvider.notifier).refreshQuietly();
      final notifier = container.read(bookingsControllerProvider.notifier);
      expect(container.read(bookingsControllerProvider).value!.last.status, BookingStatus.inWindow);

      await notifier.checkIn('A-2');
      final afterCheckIn = container.read(bookingsControllerProvider).value!;
      expect(afterCheckIn.map((b) => b.id), ['A-booking', 'A-2']);
      expect(afterCheckIn.last.status, BookingStatus.checkedIn);

      await notifier.cancel('A-booking');
      expect(container.read(bookingsControllerProvider).value!.map((b) => b.id), ['A-2']);
    });

    test("B's refreshQuietly does its own fetch instead of joining A's in flight", () async {
      final (container, repo, auth) = await asStudentA();
      container.listen(bookingsControllerProvider, (_, __) {});
      final notifier = container.read(bookingsControllerProvider.notifier);

      repo.gate = Completer<void>();
      final staleGate = repo.gate!;
      final stale = notifier.refreshQuietly();
      repo.gate = null;
      repo.served = [_seat('B-booking', resourceId: 'sB')];
      await switchToB(auth);
      await container.read(bookingsControllerProvider.future);
      final fetchesBefore = repo.fetches;

      // B has reported a desk since: B's refresh must see it, not wait for A's.
      repo.served = [_seat('B-booking', resourceId: 'sB', reportOpen: true, canReport: false)];
      await notifier.refreshQuietly().timeout(const Duration(seconds: 1));

      expect(repo.fetches, fetchesBefore + 1);
      expect(container.read(bookingsControllerProvider).value!.single.reportOpen, true);

      staleGate.complete();
      await stale;
      expect(container.read(bookingsControllerProvider).value!.single.id, 'B-booking');
    });

    test("B's own refreshes still join each other", () async {
      final (container, repo, auth) = await asStudentA();
      container.listen(bookingsControllerProvider, (_, __) {});
      await switchToB(auth);
      await container.read(bookingsControllerProvider.future);
      final notifier = container.read(bookingsControllerProvider.notifier);
      repo.gate = Completer<void>();
      final fetchesBefore = repo.fetches;

      final first = notifier.refreshQuietly();
      final second = notifier.refreshQuietly();
      repo.gate!.complete();
      await Future.wait([first, second]);

      expect(repo.fetches, fetchesBefore + 1);
    });

    test("the tick does not bring back A's bookings when B's fetch has failed", () async {
      final (container, repo, auth) = await asStudentA();
      container.listen(bookingsControllerProvider, (_, __) {});
      repo.offline = true;

      await switchToB(auth);
      await expectLater(container.read(bookingsControllerProvider.future), throwsA(isA<ApiException>()));
      // Riverpod keeps A's list beside the error; a second's tick must not turn it back into data.
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      final state = container.read(bookingsControllerProvider);
      expect(state.hasError, true);
      expect(state.isLoading, false);
    });
  });
}
