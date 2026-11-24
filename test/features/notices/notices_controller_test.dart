// test/features/notices/notices_controller_test.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/notices/notice_repository.dart';
import 'package:smartlib_frontend/features/notices/notices_controller.dart';
import 'package:smartlib_frontend/models/notice.dart';
import '../../support/mock_overrides.dart';

Notice _notice(String id, {NoticeKind kind = NoticeKind.overdueReminder}) => Notice(
      id: id, kind: kind, title: 'Overdue book reminder', body: 'Your copy was due and is 3 days overdue.',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

/// Serves whatever [served] holds, counting fetches, with the network failing
/// or the answer held back on demand. The answer is what [served] held when the
/// request was made (what the server knew then), however long the gate holds it.
class _ScriptedNotices implements NoticeRepository {
  _ScriptedNotices(this.served);

  List<Notice> served;
  int fetches = 0;
  bool offline = false;
  Completer<void>? gate;

  @override
  Future<List<Notice>> myNotices() async {
    fetches++;
    final answer = List.of(served);
    await gate?.future;
    if (offline) throw const ApiException(0, ApiException.networkMessage);
    return answer;
  }
}

void main() {
  Future<(ProviderContainer, _ScriptedNotices)> loaded(List<Notice> notices) async {
    final repo = _ScriptedNotices(notices);
    final container = ProviderContainer(overrides: mockRepositoryOverrides(notices: repo));
    addTearDown(container.dispose);
    await container.read(noticesControllerProvider.future);
    return (container, repo);
  }

  test("loads the student's notices", () async {
    final (container, _) = await loaded([_notice('n1'), _notice('n2')]);
    expect(container.read(noticesControllerProvider).value!.map((n) => n.id), ['n1', 'n2']);
  });

  test('the default mock has no notices', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    expect(await container.read(noticesControllerProvider.future), isEmpty);
  });

  test('refreshQuietly shows what the server says now', () async {
    final (container, repo) = await loaded([_notice('n1')]);
    repo.served = [_notice('n2', kind: NoticeKind.overdueEscalation), _notice('n1')];

    await container.read(noticesControllerProvider.notifier).refreshQuietly();

    final notices = container.read(noticesControllerProvider).value!;
    expect(notices.map((n) => n.id), ['n2', 'n1']);
    expect(notices.first.kind, NoticeKind.overdueEscalation);
  });

  test('refreshQuietly keeps the data on a network error', () async {
    final (container, repo) = await loaded([_notice('n1')]);

    repo.offline = true;
    await container.read(noticesControllerProvider.notifier).refreshQuietly();

    final state = container.read(noticesControllerProvider);
    expect(repo.fetches, 2); // it did ask, and the ask failed
    expect(state.hasError, false);
    expect(state.value!.single.id, 'n1');
  });

  test('joins a fetch in flight', () async {
    final (container, repo) = await loaded([_notice('n1')]);
    repo.gate = Completer<void>();
    final notifier = container.read(noticesControllerProvider.notifier);

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
    // Student A is logged in and has read their notices; the next to log in is B.
    Future<(ProviderContainer, _ScriptedNotices, AuthController)> asStudentA() async {
      final repo = _ScriptedNotices([_notice('A-notice')]);
      final container = ProviderContainer(overrides: mockRepositoryOverrides(notices: repo));
      addTearDown(container.dispose);
      final auth = container.read(authControllerProvider.notifier);
      await auth.login('aditi.sharma@thapar.edu', 'anything');
      expect((await container.read(noticesControllerProvider.future)).single.id, 'A-notice');
      return (container, repo, auth);
    }

    Future<void> switchToB(AuthController auth) async {
      await auth.logOut();
      await auth.register('Second Student', 'second@thapar.edu', 'password123');
    }

    test("they get their own notices, and A's stay flagged as reloading until those arrive", () async {
      final (container, repo, auth) = await asStudentA();
      // A screen is watching, as My Loans does.
      container.listen(noticesControllerProvider, (_, __) {});
      repo.served = [_notice('B-notice')];
      repo.gate = Completer<void>();
      final fetchesBefore = repo.fetches;

      await switchToB(auth);

      // Riverpod keeps A's list attached to the loading state; `isReloading` is
      // how a screen tells it must not draw it.
      final during = container.read(noticesControllerProvider);
      expect(repo.fetches, greaterThan(fetchesBefore));
      expect(during.isReloading, true);
      expect(during.hasError, false);

      repo.gate!.complete();
      expect((await container.read(noticesControllerProvider.future)).single.id, 'B-notice');
      final state = container.read(noticesControllerProvider);
      expect(state.isLoading, false);
      expect(state.value!.single.id, 'B-notice');
    });

    test('a refresh started for student A never overwrites student B after a switch', () async {
      final (container, repo, auth) = await asStudentA();
      container.listen(noticesControllerProvider, (_, __) {});
      final notifier = container.read(noticesControllerProvider.notifier);

      // A's quiet refresh is on the wire (it will answer with A's notices)...
      repo.gate = Completer<void>();
      final staleGate = repo.gate!;
      final stale = notifier.refreshQuietly();
      // ...when A logs out and B logs in, whose own fetch answers at once.
      repo.gate = null;
      repo.served = [_notice('B-notice')];
      await switchToB(auth);
      expect((await container.read(noticesControllerProvider.future)).single.id, 'B-notice');

      staleGate.complete();
      await stale;

      expect(container.read(noticesControllerProvider).value!.single.id, 'B-notice');
    });

    test("B's refreshQuietly does its own fetch instead of joining A's in flight", () async {
      final (container, repo, auth) = await asStudentA();
      container.listen(noticesControllerProvider, (_, __) {});
      final notifier = container.read(noticesControllerProvider.notifier);

      repo.gate = Completer<void>();
      final staleGate = repo.gate!;
      final stale = notifier.refreshQuietly();
      repo.gate = null;
      repo.served = [_notice('B-notice')];
      await switchToB(auth);
      await container.read(noticesControllerProvider.future);
      final fetchesBefore = repo.fetches;

      // The library has since written B another notice: B's refresh must see it,
      // not wait for A's.
      repo.served = [_notice('B-newer'), _notice('B-notice')];
      await notifier.refreshQuietly().timeout(const Duration(seconds: 1));

      expect(repo.fetches, fetchesBefore + 1);
      expect(container.read(noticesControllerProvider).value!.map((n) => n.id), ['B-newer', 'B-notice']);

      staleGate.complete();
      await stale;
      expect(container.read(noticesControllerProvider).value!.map((n) => n.id), ['B-newer', 'B-notice']);
    });

    test("B's own refreshes still join each other", () async {
      // The generation only separates students: within one student the join stays.
      final (container, repo, auth) = await asStudentA();
      container.listen(noticesControllerProvider, (_, __) {});
      await switchToB(auth);
      await container.read(noticesControllerProvider.future);
      final notifier = container.read(noticesControllerProvider.notifier);
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
