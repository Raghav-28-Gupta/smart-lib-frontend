// test/features/waitlist/waitlist_controller_test.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/waitlist/waitlist_controller.dart';
import 'package:smartlib_frontend/features/waitlist/waitlist_repository.dart';
import 'package:smartlib_frontend/models/reservation.dart';
import '../../support/mock_overrides.dart';

/// The mock, counting fetches, with leave made to fail and join to stall on demand.
class _ScriptedWaitlistRepository extends MockWaitlistRepository {
  _ScriptedWaitlistRepository({super.reservations}) : super(MockBookRepository());

  int fetches = 0;
  int joinCalls = 0;
  Object? leaveError;
  Completer<void>? joinGate;

  @override
  Future<List<Reservation>> mine() {
    fetches++;
    return super.mine();
  }

  @override
  Future<Reservation> join(String bookId) async {
    joinCalls++;
    await joinGate?.future;
    return super.join(bookId);
  }

  @override
  Future<void> leave(String reservationId) async {
    if (leaveError != null) throw leaveError!;
    return super.leave(reservationId);
  }
}

const _waiting = Reservation(id: 'res-b2', bookId: 'b2', status: ReservationStatus.waiting, queuePosition: 3);

void main() {
  Future<(ProviderContainer, _ScriptedWaitlistRepository)> loaded({List<Reservation> reservations = const []}) async {
    final repo = _ScriptedWaitlistRepository(reservations: reservations);
    final container = ProviderContainer(overrides: mockRepositoryOverrides(waitlist: repo));
    addTearDown(container.dispose);
    await container.read(waitlistControllerProvider.future);
    return (container, repo);
  }

  test("loads the student's waitlist", () async {
    final (container, _) = await loaded(reservations: [_waiting]);
    expect(container.read(waitlistControllerProvider).value, [_waiting]);
  });

  test("joining adds the server's entry, with its place in line", () async {
    final (container, _) = await loaded();
    await container.read(waitlistControllerProvider.notifier).join('b2');
    final entry = container.read(waitlistControllerProvider).value!.single;
    expect(entry.bookId, 'b2');
    expect(entry.status, ReservationStatus.waiting);
    // b2 has two students queued already.
    expect(entry.queuePosition, 3);
  });

  test('leaving removes the entry', () async {
    final (container, _) = await loaded(reservations: [_waiting]);
    await container.read(waitlistControllerProvider.notifier).leave('res-b2');
    expect(container.read(waitlistControllerProvider).value, isEmpty);
  });

  test('a refused leave is reported, and the list is refetched -- it was stale', () async {
    // e.g. the hold already ran out and passed to the next student.
    final (container, repo) = await loaded(reservations: [_waiting]);
    repo.leaveError = const ConflictException('This reservation is no longer active.');
    await expectLater(
      container.read(waitlistControllerProvider.notifier).leave('res-b2'),
      throwsA(isA<ConflictException>()),
    );
    await container.read(waitlistControllerProvider.future);
    expect(repo.fetches, 2);
  });

  test('a double tap on Join joins once', () async {
    // The second request would come back "already on the waitlist".
    final (container, repo) = await loaded();
    repo.joinGate = Completer<void>();
    final notifier = container.read(waitlistControllerProvider.notifier);
    final first = notifier.join('b2');
    final second = notifier.join('b2');
    repo.joinGate!.complete();
    await Future.wait([first, second]);
    expect(repo.joinCalls, 1);
    expect(container.read(waitlistControllerProvider).value, hasLength(1));
  });

  test("a different user logging in gets their own waitlist, not the last user's", () async {
    final (container, repo) = await loaded(reservations: [_waiting]);
    final auth = container.read(authControllerProvider.notifier);
    await auth.login('aditi.sharma@thapar.edu', 'anything');
    await container.read(waitlistControllerProvider.future);
    final before = repo.fetches;

    await auth.logOut();
    await auth.register('Second Student', 'second@thapar.edu', 'password123');
    await container.read(waitlistControllerProvider.future);
    expect(repo.fetches, greaterThan(before));
  });
}
