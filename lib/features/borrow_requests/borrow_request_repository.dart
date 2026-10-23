// lib/features/borrow_requests/borrow_request_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../models/borrow_request.dart';
import '../catalog/book_repository.dart';

/// The student's borrow requests -- the backend's /borrow-requests. Borrowing
/// is a request a librarian approves; the loan appears once they do.
abstract class BorrowRequestRepository {
  /// Pending requests, and those declined or expired in the last 7 days, newest first.
  Future<List<BorrowRequest>> mine();

  /// Asks to borrow [bookId]. The server holds a copy while the request waits.
  Future<BorrowRequest> create(String bookId);

  /// Withdraws a pending request; its copy goes back to the shelf.
  Future<void> cancel(String requestId);
}

class HttpBorrowRequestRepository implements BorrowRequestRepository {
  HttpBorrowRequestRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<BorrowRequest>> mine() async {
    final res = await guardApi(() => _dio.get<List<dynamic>>('/borrow-requests/me'));
    return res.data!.map((j) => BorrowRequest.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<BorrowRequest> create(String bookId) async {
    final res = await guardApi(() => _dio.post<Map<String, dynamic>>('/borrow-requests', data: {'bookId': bookId}));
    return BorrowRequest.fromJson(res.data!);
  }

  @override
  Future<void> cancel(String requestId) async {
    await guardApi(() => _dio.post<Object?>('/borrow-requests/${Uri.encodeComponent(requestId)}/cancel'));
  }
}

/// Test double. Mirrors the server's refusals and keeps requests in memory,
/// newest first.
class MockBorrowRequestRepository implements BorrowRequestRepository {
  MockBorrowRequestRepository(this._books, {List<BorrowRequest> requests = const []}) : _mine = List.of(requests);

  final BookRepository _books;
  final List<BorrowRequest> _mine;
  int _nextId = 1;

  @override
  Future<List<BorrowRequest>> mine() async => List.of(_mine);

  @override
  Future<BorrowRequest> create(String bookId) async {
    if (_mine.any((r) => r.bookId == bookId && r.status == BorrowRequestStatus.pending)) {
      throw const ConflictException("You've already requested this book.");
    }
    final now = DateTime.now();
    final r = BorrowRequest(
      id: 'br-${_nextId++}',
      bookId: bookId,
      bookTitle: (await _books.getById(bookId))?.title ?? '',
      status: BorrowRequestStatus.pending,
      requestedAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
    );
    _mine.insert(0, r);
    return r;
  }

  @override
  Future<void> cancel(String requestId) async {
    final i = _mine.indexWhere((r) => r.id == requestId && r.status == BorrowRequestStatus.pending);
    if (i == -1) throw const ConflictException('This request is no longer pending.');
    _mine.removeAt(i);
  }

  /// Plays a librarian's decision on the pending request for [bookId], as the
  /// server then reports it: an approved request drops off the list.
  void decide(String bookId, BorrowRequestStatus status, {String? reason}) {
    final i = _mine.indexWhere((r) => r.bookId == bookId && r.status == BorrowRequestStatus.pending);
    final r = _mine.removeAt(i);
    if (status == BorrowRequestStatus.approved) return;
    _mine.insert(
      i,
      BorrowRequest(
        id: r.id,
        bookId: r.bookId,
        bookTitle: r.bookTitle,
        status: status,
        requestedAt: r.requestedAt,
        expiresAt: r.expiresAt,
        decidedAt: DateTime.now(),
        declineReason: reason,
      ),
    );
  }
}

final borrowRequestRepositoryProvider =
    Provider<BorrowRequestRepository>((ref) => HttpBorrowRequestRepository(ref.watch(apiClientProvider)));
