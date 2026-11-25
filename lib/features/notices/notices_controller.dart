// lib/features/notices/notices_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_exception.dart';
import '../../models/notice.dart';
import '../auth/auth_controller.dart';
import 'notice_repository.dart';

/// The logged-in student's library notices, for the Library notices section on
/// My Loans (the loan and fine kinds) and on My Bookings (the booking kinds): one
/// controller and one list per student, filtered by kind where it is shown. The
/// student only reads them: the library writes them.
class NoticesController extends AsyncNotifier<List<Notice>> {
  // Bumped by every build(). This notifier outlives a rebuild (a different student
  // logging in), so a quiet refresh begun for the last student must neither land in
  // the next student's state nor be joined by their `refreshQuietly`.
  int _generation = 0;

  @override
  Future<List<Notice>> build() {
    _generation++;
    _refreshing = null;
    // Outlives a logout, so keyed on who is logged in -- a different user
    // means a fresh fetch, never the previous user's notices. (Riverpod keeps the
    // previous user's value on the loading state; a screen must not draw it, see
    // `isReloading` in `NoticesSection`.)
    ref.watch(authControllerProvider.select((s) => s.user?.id));
    return ref.read(noticeRepositoryProvider).myNotices();
  }

  Future<void>? _refreshing;

  /// The re-check when My Loans or My Bookings opens (and after a successful
  /// check-in or cancel on My Bookings): a librarian's reminder, a
  /// booking's reminder or recorded no-show, or the outcome of a dispute or a report,
  /// arrives while the student is elsewhere. Shows what the server says now, and
  /// keeps what is shown if the request fails. A call made while another is in
  /// flight joins it, unless that one was begun for a student who has since logged
  /// out.
  Future<void> refreshQuietly() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final generation = _generation;
    return _refreshing = _refresh(generation).whenComplete(() {
      // After a rebuild `_refreshing` is the next student's (or null): not ours to clear.
      if (generation == _generation) _refreshing = null;
    });
  }

  Future<void> _refresh(int generation) async {
    try {
      final fresh = await ref.read(noticeRepositoryProvider).myNotices();
      // The answer to the previous student's request, arriving after the next one
      // logged in: theirs, so it is dropped.
      if (generation == _generation) state = AsyncValue.data(fresh);
    } on ApiException {
      // Keep what's shown; the next time My Loans or My Bookings opens tries again.
    }
  }
}

final noticesControllerProvider = AsyncNotifierProvider<NoticesController, List<Notice>>(NoticesController.new);
