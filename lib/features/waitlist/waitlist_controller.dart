// lib/features/waitlist/waitlist_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_exception.dart';
import '../../models/reservation.dart';
import '../auth/auth_controller.dart';
import 'waitlist_repository.dart';

/// The logged-in student's waitlist, shared by the book screens and My Loans
/// -- so joining is remembered after the screen that did it closes.
class WaitlistController extends AsyncNotifier<List<Reservation>> {
  // Books with a join in flight. A second tap would come back "already on
  // the waitlist" and read as a failure.
  final _joining = <String>{};

  @override
  Future<List<Reservation>> build() {
    // Keyed on who is logged in, like the loans: a different user gets a
    // fresh fetch, never the previous user's queue.
    ref.watch(authControllerProvider.select((s) => s.user?.id));
    return ref.read(waitlistRepositoryProvider).mine();
  }

  Future<void> join(String bookId) async {
    if (!_joining.add(bookId)) return;
    try {
      final r = await ref.read(waitlistRepositoryProvider).join(bookId);
      state = AsyncValue.data([...(state.value ?? []), r]);
    } on ApiException catch (e) {
      _refetchIfStale(e);
      rethrow;
    } finally {
      _joining.remove(bookId);
    }
  }

  Future<void> leave(String reservationId) async {
    try {
      await ref.read(waitlistRepositoryProvider).leave(reservationId);
    } on ApiException catch (e) {
      _refetchIfStale(e);
      rethrow;
    }
    state = AsyncValue.data((state.value ?? []).where((r) => r.id != reservationId).toList());
  }

  // The caller reports the failure; this keeps the list true to the server.
  void _refetchIfStale(ApiException e) {
    if (e.meansStaleState) ref.invalidateSelf();
  }
}

extension WaitlistLookup on List<Reservation> {
  /// The entry for [bookId], if the student is queued for it or has a copy held.
  Reservation? forBook(String bookId) {
    for (final r in this) {
      if (r.bookId == bookId) return r;
    }
    return null;
  }
}

final waitlistControllerProvider =
    AsyncNotifierProvider<WaitlistController, List<Reservation>>(WaitlistController.new);
