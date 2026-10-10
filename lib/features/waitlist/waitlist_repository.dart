// lib/features/waitlist/waitlist_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../models/reservation.dart';
import '../catalog/book_repository.dart';

/// The student's waitlist entries -- the backend's /reservations.
abstract class WaitlistRepository {
  /// Live entries only: waiting, or with a copy held.
  Future<List<Reservation>> mine();

  Future<Reservation> join(String bookId);

  /// Leaves the queue, or gives up a held copy (it passes to the next student).
  Future<void> leave(String reservationId);
}

class HttpWaitlistRepository implements WaitlistRepository {
  HttpWaitlistRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<Reservation>> mine() async {
    final res = await guardApi(() => _dio.get<List<dynamic>>('/reservations/me'));
    return res.data!.map((j) => Reservation.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<Reservation> join(String bookId) async {
    final res = await guardApi(() => _dio.post<Map<String, dynamic>>('/reservations', data: {'bookId': bookId}));
    return Reservation.fromJson(res.data!);
  }

  @override
  Future<void> leave(String reservationId) async {
    await guardApi(() => _dio.delete<Object?>('/reservations/${Uri.encodeComponent(reservationId)}'));
  }
}

/// Test double. Mirrors the server's refusals, and takes the place in line
/// from the book's waitlist count.
class MockWaitlistRepository implements WaitlistRepository {
  MockWaitlistRepository(this._books, {List<Reservation> reservations = const []})
      : _mine = List.of(reservations);

  final BookRepository _books;
  final List<Reservation> _mine;
  int _nextId = 1;

  @override
  Future<List<Reservation>> mine() async => List.of(_mine);

  @override
  Future<Reservation> join(String bookId) async {
    if (_mine.any((r) => r.bookId == bookId)) {
      throw const ConflictException("You're already on the waitlist for this title.");
    }
    final ahead = (await _books.getById(bookId))?.waitlistCount ?? 0;
    final r = Reservation(
      id: 'res-${_nextId++}',
      bookId: bookId,
      status: ReservationStatus.waiting,
      queuePosition: ahead + 1,
    );
    _mine.add(r);
    return r;
  }

  @override
  Future<void> leave(String reservationId) async {
    final before = _mine.length;
    _mine.removeWhere((r) => r.id == reservationId);
    if (_mine.length == before) throw const ConflictException('This reservation is no longer active.');
  }
}

final waitlistRepositoryProvider =
    Provider<WaitlistRepository>((ref) => HttpWaitlistRepository(ref.watch(apiClientProvider)));
