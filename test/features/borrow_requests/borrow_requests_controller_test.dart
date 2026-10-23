// test/features/borrow_requests/borrow_requests_controller_test.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/borrow_requests/borrow_request_repository.dart';
import 'package:smartlib_frontend/features/borrow_requests/borrow_requests_controller.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/loans/loans_controller.dart';
import 'package:smartlib_frontend/models/borrow_request.dart';
import 'package:smartlib_frontend/models/loan.dart';
import '../../support/mock_overrides.dart';

/// The mock, counting how often the loans are fetched.
class _CountingLoans extends MockLoanRepository {
  int fetches = 0;

  @override
  Future<List<Loan>> activeLoans() {
    fetches++;
    return super.activeLoans();
  }
}

/// The mock, counting calls, with failures, stalls and server answers on demand.
class _ScriptedRequests extends MockBorrowRequestRepository {
  _ScriptedRequests({super.requests}) : super(MockBookRepository());

  int fetches = 0;
  int creates = 0;
  Object? mineError;
  Object? createError;
  Completer<void>? createGate;

  /// When set, fetches return this: what the server says after a decision.
  List<BorrowRequest>? serverSays;

  @override
  Future<List<BorrowRequest>> mine() {
    fetches++;
    if (mineError != null) return Future.error(mineError!);
    final answer = serverSays;
    return answer != null ? Future.value(List.of(answer)) : super.mine();
  }

  @override
  Future<BorrowRequest> create(String bookId) async {
    creates++;
    await createGate?.future;
    if (createError != null) throw createError!;
    return super.create(bookId);
  }
}

BorrowRequest _request(String id, String bookId, BorrowRequestStatus status, {Duration age = Duration.zero}) {
  final requestedAt = DateTime.now().subtract(age);
  return BorrowRequest(
    id: id,
    bookId: bookId,
    bookTitle: 'Title $bookId',
    status: status,
    requestedAt: requestedAt,
    expiresAt: requestedAt.add(const Duration(hours: 24)),
    decidedAt: status == BorrowRequestStatus.pending ? null : requestedAt.add(const Duration(hours: 1)),
  );
}

void main() {
  Future<(ProviderContainer, _ScriptedRequests)> loaded({List<BorrowRequest> requests = const []}) async {
    final repo = _ScriptedRequests(requests: requests);
    final container = ProviderContainer(overrides: mockRepositoryOverrides(borrowRequests: repo));
    addTearDown(container.dispose);
    await container.read(borrowRequestsControllerProvider.future);
    return (container, repo);
  }

  test("loads the student's requests", () async {
    final pending = _request('br-1', 'b12', BorrowRequestStatus.pending);
    final (container, _) = await loaded(requests: [pending]);
    expect(container.read(borrowRequestsControllerProvider).value, [pending]);
  });

  test('requesting puts the new pending request first', () async {
    final (container, _) = await loaded(requests: [_request('br-0', 'b5', BorrowRequestStatus.declined)]);
    await container.read(borrowRequestsControllerProvider.notifier).request('b12');
    final first = container.read(borrowRequestsControllerProvider).value!.first;
    expect(first.bookId, 'b12');
    expect(first.bookTitle, 'Atomic Habits');
    expect(first.status, BorrowRequestStatus.pending);
  });

  test('a double tap requests once', () async {
    final (container, repo) = await loaded();
    repo.createGate = Completer<void>();
    final notifier = container.read(borrowRequestsControllerProvider.notifier);
    final first = notifier.request('b12');
    final second = notifier.request('b12');
    repo.createGate!.complete();
    await Future.wait([first, second]);
    expect(repo.creates, 1);
    expect(container.read(borrowRequestsControllerProvider).value, hasLength(1));
  });

  test('a refused request is reported, and the list is refetched -- it was stale', () async {
    final (container, repo) = await loaded();
    repo.createError = const ConflictException("You've already requested this book.");
    await expectLater(
      container.read(borrowRequestsControllerProvider.notifier).request('b12'),
      throwsA(isA<ConflictException>()),
    );
    await container.read(borrowRequestsControllerProvider.future);
    expect(repo.fetches, 2);
  });

  test('a cancel the server says is no longer pending also refetches the loans -- a librarian may have approved it', () async {
    final repo = _ScriptedRequests(requests: [_request('br-1', 'b12', BorrowRequestStatus.pending)]);
    final loans = _CountingLoans();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(borrowRequests: repo, loans: loans));
    addTearDown(container.dispose);
    await container.read(borrowRequestsControllerProvider.future);
    await container.read(loansControllerProvider.future);
    final before = loans.fetches;

    // Approved while the student was away: the mock drops it from the list, so
    // cancelling it is refused like the server's 409 -- and a loan now exists.
    repo.decide('b12', BorrowRequestStatus.approved);
    await expectLater(
      container.read(borrowRequestsControllerProvider.notifier).cancel('br-1'),
      throwsA(isA<ConflictException>()),
    );
    expect(loans.fetches, before + 1);
  });

  test('cancelling removes the request', () async {
    final (container, _) = await loaded();
    final notifier = container.read(borrowRequestsControllerProvider.notifier);
    await notifier.request('b12');
    final id = container.read(borrowRequestsControllerProvider).value!.single.id;
    await notifier.cancel(id);
    expect(container.read(borrowRequestsControllerProvider).value, isEmpty);
  });

  test("refreshQuietly shows what the server says now", () async {
    final (container, repo) = await loaded(requests: [_request('br-1', 'b12', BorrowRequestStatus.pending)]);
    repo.serverSays = [];
    await container.read(borrowRequestsControllerProvider.notifier).refreshQuietly();
    expect(container.read(borrowRequestsControllerProvider).value, isEmpty);
  });

  test('refreshQuietly keeps the list when the network fails', () async {
    final pending = _request('br-1', 'b12', BorrowRequestStatus.pending);
    final (container, repo) = await loaded(requests: [pending]);
    repo.mineError = const ApiException(0, ApiException.networkMessage);
    await container.read(borrowRequestsControllerProvider.notifier).refreshQuietly();
    final state = container.read(borrowRequestsControllerProvider);
    expect(state.hasError, false);
    expect(state.value, [pending]);
  });

  test('looks up the newest request per title, and whether any is pending', () {
    final list = [
      _request('br-3', 'b12', BorrowRequestStatus.pending),
      _request('br-2', 'b12', BorrowRequestStatus.declined, age: const Duration(hours: 5)),
      _request('br-1', 'b5', BorrowRequestStatus.expired, age: const Duration(hours: 9)),
    ];
    expect(list.latestPerBook().map((r) => r.id), ['br-3', 'br-1']);
    expect(list.latestFor('b12')!.id, 'br-3');
    expect(list.latestFor('b1'), isNull);
    expect(list.anyPending, true);
    expect([list[1], list[2]].anyPending, false);
  });

  test("a different user logging in gets their own requests, not the last user's", () async {
    final (container, repo) = await loaded();
    final auth = container.read(authControllerProvider.notifier);
    await auth.login('aditi.sharma@thapar.edu', 'anything');
    await container.read(borrowRequestsControllerProvider.future);
    final before = repo.fetches;

    await auth.logOut();
    await auth.register('Second Student', 'second@thapar.edu', 'password123');
    await container.read(borrowRequestsControllerProvider.future);
    expect(repo.fetches, greaterThan(before));
  });
}
