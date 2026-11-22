// test/features/fines/fines_controller_test.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/fines/fine_repository.dart';
import 'package:smartlib_frontend/features/fines/fines_controller.dart';
import 'package:smartlib_frontend/models/fine.dart';
import '../../support/mock_overrides.dart';

Fine _fine(String id, {FineStatus status = FineStatus.outstanding, double amount = 30}) => Fine(
      id: id, reason: FineReason.overdue, item: 'Database System Concepts', amount: amount,
      originalAmount: amount, status: status, date: DateTime.now(),
    );

/// Serves whatever [summary] holds, counting fetches, with the network failing
/// or the answer held back on demand. The answer is what [summary] held when the
/// request was made (what the server knew then), however long the gate holds it.
class _ScriptedFines implements FineRepository {
  _ScriptedFines(this.summary);

  FinesSummary summary;
  int fetches = 0;
  bool offline = false;
  Completer<void>? gate;

  @override
  Future<FinesSummary> myFines() async {
    fetches++;
    final answer = summary;
    await gate?.future;
    if (offline) throw const ApiException(0, ApiException.networkMessage);
    return answer;
  }
}

FinesSummary _owing(List<Fine> fines) => FinesSummary(fines: fines, outstandingTotal: fines.fold(0, (t, f) => t + f.amount));

void main() {
  Future<(ProviderContainer, _ScriptedFines)> loaded(FinesSummary summary) async {
    final repo = _ScriptedFines(summary);
    final container = ProviderContainer(overrides: mockRepositoryOverrides(fines: repo));
    addTearDown(container.dispose);
    await container.read(finesControllerProvider.future);
    return (container, repo);
  }

  test("loads the student's fines", () async {
    final (container, _) = await loaded(_owing([_fine('f1')]));
    final summary = container.read(finesControllerProvider).value!;
    expect(summary.fines.single.id, 'f1');
    expect(summary.outstandingTotal, 30.0);
  });

  test('the default mock has no fines', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    final summary = await container.read(finesControllerProvider.future);
    expect(summary.fines, isEmpty);
    expect(summary.outstandingTotal, 0.0);
  });

  test('refreshQuietly shows what the server says now', () async {
    final (container, repo) = await loaded(_owing([_fine('f1')]));
    repo.summary = _owing([_fine('f1', status: FineStatus.paid), _fine('f2')]);

    await container.read(finesControllerProvider.notifier).refreshQuietly();

    final summary = container.read(finesControllerProvider).value!;
    expect(summary.fines.map((f) => f.id), ['f1', 'f2']);
    expect(summary.fines.first.status, FineStatus.paid);
  });

  test('refreshQuietly keeps the data on a network error', () async {
    final (container, repo) = await loaded(_owing([_fine('f1')]));

    repo.offline = true;
    await container.read(finesControllerProvider.notifier).refreshQuietly();

    final state = container.read(finesControllerProvider);
    expect(repo.fetches, 2); // it did ask, and the ask failed
    expect(state.hasError, false);
    expect(state.value!.fines.single.id, 'f1');
  });

  test('refreshQuietly joins a fetch in flight', () async {
    final (container, repo) = await loaded(_owing([_fine('f1')]));
    repo.gate = Completer<void>();
    final notifier = container.read(finesControllerProvider.notifier);

    final first = notifier.refreshQuietly();
    final second = notifier.refreshQuietly();
    repo.gate!.complete();
    await Future.wait([first, second]);

    expect(repo.fetches, 2); // the load, and one refresh for both callers

    // The join ends with the fetch: a later call asks again.
    await notifier.refreshQuietly();
    expect(repo.fetches, 3);
  });

  group('when a different student logs in', () {
    // Student A is logged in and has read their fines; the next to log in is B.
    Future<(ProviderContainer, _ScriptedFines, AuthController)> asStudentA() async {
      final repo = _ScriptedFines(_owing([_fine('A-fine')]));
      final container = ProviderContainer(overrides: mockRepositoryOverrides(fines: repo));
      addTearDown(container.dispose);
      final auth = container.read(authControllerProvider.notifier);
      await auth.login('aditi.sharma@thapar.edu', 'anything');
      expect((await container.read(finesControllerProvider.future)).fines.single.id, 'A-fine');
      return (container, repo, auth);
    }

    Future<void> switchToB(AuthController auth) async {
      await auth.logOut();
      await auth.register('Second Student', 'second@thapar.edu', 'password123');
    }

    test("they get their own fines, and A's stay flagged as reloading until those arrive", () async {
      final (container, repo, auth) = await asStudentA();
      // A screen is watching, as My Loans does.
      container.listen(finesControllerProvider, (_, __) {});
      repo.summary = _owing([_fine('B-fine')]);
      repo.gate = Completer<void>();
      final fetchesBefore = repo.fetches;

      await switchToB(auth);

      // Riverpod keeps A's list attached to the loading state; `isReloading` is
      // how a screen tells it must not draw it.
      final during = container.read(finesControllerProvider);
      expect(repo.fetches, greaterThan(fetchesBefore));
      expect(during.isReloading, true);
      expect(during.hasError, false);

      repo.gate!.complete();
      final arrived = await container.read(finesControllerProvider.future);
      expect(arrived.fines.single.id, 'B-fine');
      final state = container.read(finesControllerProvider);
      expect(state.isLoading, false);
      expect(state.value!.fines.single.id, 'B-fine');
    });

    test("A's refresh still in flight when B logs in lands without changing B's fines", () async {
      final (container, repo, auth) = await asStudentA();
      container.listen(finesControllerProvider, (_, __) {});
      final notifier = container.read(finesControllerProvider.notifier);

      // A's quiet refresh is on the wire (it will answer with A's fines)...
      repo.gate = Completer<void>();
      final staleGate = repo.gate!;
      final stale = notifier.refreshQuietly();
      // ...when A logs out and B logs in, whose own fetch answers at once.
      repo.gate = null;
      repo.summary = _owing([_fine('B-fine')]);
      await switchToB(auth);
      expect((await container.read(finesControllerProvider.future)).fines.single.id, 'B-fine');

      staleGate.complete();
      await stale;

      expect(container.read(finesControllerProvider).value!.fines.single.id, 'B-fine');
    });

    test("B's refreshQuietly does its own fetch instead of joining A's in flight", () async {
      final (container, repo, auth) = await asStudentA();
      container.listen(finesControllerProvider, (_, __) {});
      final notifier = container.read(finesControllerProvider.notifier);

      repo.gate = Completer<void>();
      final staleGate = repo.gate!;
      final stale = notifier.refreshQuietly();
      repo.gate = null;
      repo.summary = _owing([_fine('B-fine')]);
      await switchToB(auth);
      await container.read(finesControllerProvider.future);
      final fetchesBefore = repo.fetches;

      // B has paid something since: B's refresh must see it, not wait for A's.
      repo.summary = _owing([_fine('B-fine', status: FineStatus.paid)]);
      await notifier.refreshQuietly().timeout(const Duration(seconds: 1));

      expect(repo.fetches, fetchesBefore + 1);
      expect(container.read(finesControllerProvider).value!.fines.single.status, FineStatus.paid);

      staleGate.complete();
      await stale;
      expect(container.read(finesControllerProvider).value!.fines.single.status, FineStatus.paid);
    });

    test("B's own refreshes still join each other", () async {
      // The generation only separates students: within one student the join stays.
      final (container, repo, auth) = await asStudentA();
      container.listen(finesControllerProvider, (_, __) {});
      await switchToB(auth);
      await container.read(finesControllerProvider.future);
      final notifier = container.read(finesControllerProvider.notifier);
      repo.gate = Completer<void>();
      final fetchesBefore = repo.fetches;

      final first = notifier.refreshQuietly();
      final second = notifier.refreshQuietly();
      repo.gate!.complete();
      await Future.wait([first, second]);

      expect(repo.fetches, fetchesBefore + 1);
    });
  });
}
