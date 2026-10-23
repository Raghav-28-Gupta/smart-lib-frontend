// lib/features/borrow_requests/borrow_requests_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_exception.dart';
import '../../models/borrow_request.dart';
import '../auth/auth_controller.dart';
import 'borrow_request_repository.dart';

/// The logged-in student's borrow requests, shared by the book pages and My Loans.
class BorrowRequestsController extends AsyncNotifier<List<BorrowRequest>> {
  // Titles with a request in flight. A second tap would come back "already
  // requested" and read as a failure.
  final _requesting = <String>{};

  @override
  Future<List<BorrowRequest>> build() {
    // Keyed on who is logged in, like the loans: a different user gets a
    // fresh fetch, never the previous user's requests.
    ref.watch(authControllerProvider.select((s) => s.user?.id));
    return ref.read(borrowRequestRepositoryProvider).mine();
  }

  Future<void> request(String bookId) async {
    if (!_requesting.add(bookId)) return;
    try {
      final r = await ref.read(borrowRequestRepositoryProvider).create(bookId);
      state = AsyncValue.data([r, ...(state.value ?? [])]);
    } on ApiException catch (e) {
      _refetchIfStale(e);
      rethrow;
    } finally {
      _requesting.remove(bookId);
    }
  }

  Future<void> cancel(String requestId) async {
    try {
      await ref.read(borrowRequestRepositoryProvider).cancel(requestId);
    } on ApiException catch (e) {
      _refetchIfStale(e);
      rethrow;
    }
    state = AsyncValue.data((state.value ?? []).where((r) => r.id != requestId).toList());
  }

  /// The 30-second re-check: shows what the server says now, and keeps what
  /// it had if the request fails -- a network blip must not turn the screen
  /// into an error page. The next re-check tries again.
  Future<void> refreshQuietly() async {
    try {
      final fresh = await ref.read(borrowRequestRepositoryProvider).mine();
      state = AsyncValue.data(fresh);
    } on ApiException {
      // Keep what's shown.
    }
  }

  // The caller reports the failure; this keeps the list true to the server.
  void _refetchIfStale(ApiException e) {
    if (e.meansStaleState) ref.invalidateSelf();
  }
}

extension BorrowRequestLookup on List<BorrowRequest> {
  /// The newest request for [bookId] the student can still see, if any.
  BorrowRequest? latestFor(String bookId) {
    for (final r in this) {
      if (r.bookId == bookId) return r;
    }
    return null;
  }

  /// The newest request per title: an old answer is moot once the student asks again.
  List<BorrowRequest> latestPerBook() {
    final seen = <String>{};
    return [for (final r in this) if (seen.add(r.bookId)) r];
  }

  bool get anyPending => any((r) => r.status == BorrowRequestStatus.pending);
}

final borrowRequestsControllerProvider =
    AsyncNotifierProvider<BorrowRequestsController, List<BorrowRequest>>(BorrowRequestsController.new);
