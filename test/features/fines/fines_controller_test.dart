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
/// or the answer held back on demand.
class _ScriptedFines implements FineRepository {
  _ScriptedFines(this.summary);

  FinesSummary summary;
  int fetches = 0;
  bool offline = false;
  Completer<void>? gate;

  @override
  Future<FinesSummary> myFines() async {
    fetches++;
    await gate?.future;
    if (offline) throw const ApiException(0, ApiException.networkMessage);
    return summary;
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

  test("a different user logging in gets their own fines, not the last user's", () async {
    final (container, repo) = await loaded(_owing([_fine('f1')]));
    final auth = container.read(authControllerProvider.notifier);
    await auth.login('aditi.sharma@thapar.edu', 'anything');
    await container.read(finesControllerProvider.future);
    final before = repo.fetches;

    await auth.logOut();
    await auth.register('Second Student', 'second@thapar.edu', 'password123');
    await container.read(finesControllerProvider.future);
    expect(repo.fetches, greaterThan(before));
  });
}
