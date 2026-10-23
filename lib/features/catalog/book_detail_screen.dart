// lib/features/catalog/book_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/clock.dart';
import '../../core/time_format.dart';
import '../../core/ui/ui_controller.dart';
import '../../models/borrow_request.dart';
import '../../models/reservation.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pending_refresh.dart';
import '../borrow_requests/borrow_requests_controller.dart';
import '../loans/loans_controller.dart';
import '../waitlist/waitlist_controller.dart';
import 'catalog_providers.dart';

class BookDetailScreen extends ConsumerStatefulWidget {
  const BookDetailScreen({super.key, required this.bookId});
  final String bookId;
  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  // Requests being withdrawn: their Cancel button is off until the server answers.
  final _cancelling = <String>{};

  Future<void> _request() async {
    final error = await ref.read(uiControllerProvider.notifier).attempt(
          () => ref.read(borrowRequestsControllerProvider.notifier).request(widget.bookId),
          success: 'Request sent. A librarian will review it soon.',
        );
    if (!mounted) return;
    // A request holds a copy, and a copy held for you from the waitlist turns
    // into the request. Not worth a refetch when the server couldn't be reached.
    if (error == null || error.meansStaleState) {
      _refreshAvailability();
      ref.invalidate(waitlistControllerProvider);
    }
  }

  Future<void> _cancelRequest(BorrowRequest r) async {
    setState(() => _cancelling.add(r.id));
    try {
      final error = await ref.read(uiControllerProvider.notifier).attempt(
            () => ref.read(borrowRequestsControllerProvider.notifier).cancel(r.id),
            success: 'Request cancelled.',
          );
      if (!mounted) return;
      if (error == null || error.meansStaleState) _refreshAvailability();
    } finally {
      if (mounted) setState(() => _cancelling.remove(r.id));
    }
  }

  // The 30-second re-check while a request waits. An approval turns it into a
  // loan, so both lists are refetched -- quietly, keeping what's shown if the
  // network blips. Once the request is answered, the copy it held is back on
  // the shelf (or held for the next waitlisted student), so the book and the
  // waitlist are refetched too.
  Future<void> _recheck() async {
    await Future.wait([
      ref.read(borrowRequestsControllerProvider.notifier).refreshQuietly(),
      ref.read(loansControllerProvider.notifier).refreshQuietly(),
    ]);
    if (!mounted) return;
    final latest = ref.read(borrowRequestsControllerProvider).value?.latestFor(widget.bookId);
    if (latest?.status != BorrowRequestStatus.pending) {
      _refreshAvailability();
      ref.invalidate(waitlistControllerProvider);
    }
  }

  Future<void> _joinWaitlist() async {
    final error = await ref.read(uiControllerProvider.notifier).attempt(
          () => ref.read(waitlistControllerProvider.notifier).join(widget.bookId),
        );
    if (!mounted) return;
    // The queue length changed -- or was stale. Not worth a refetch when the
    // server couldn't be reached.
    if (error == null || error.meansStaleState) _refreshAvailability();
  }

  Future<void> _leaveWaitlist(Reservation r) async {
    final error = await ref.read(uiControllerProvider.notifier).attempt(
          () => ref.read(waitlistControllerProvider.notifier).leave(r.id),
          success: r.status == ReservationStatus.held
              ? 'Released. It goes to the next student in line.'
              : "You've left the waitlist.",
        );
    if (!mounted) return;
    if (error == null || error.meansStaleState) _refreshAvailability();
  }

  String _heldLine(Reservation r) {
    final until = r.claimExpiresAt;
    if (until == null) return 'A copy is held for you.';
    return 'A copy is held for you until ${dayTimeLabel(until, now: ref.read(clockProvider)())}.';
  }

  String _outcomeLine(BorrowRequest r) => switch (r.status) {
        BorrowRequestStatus.declined => r.declineReason == null
            ? 'Your request was declined by the library.'
            : 'Your request was declined: ${r.declineReason}',
        BorrowRequestStatus.expired => 'Your request expired before a librarian approved it.',
        _ => '',
      };

  // Availability lives on the server now: refetch this book, and the search
  // list still mounted underneath, so neither shows a stale count.
  void _refreshAvailability() {
    ref.invalidate(bookByIdProvider(widget.bookId));
    ref.invalidate(searchResultsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final bookAsync = ref.watch(bookByIdProvider(widget.bookId));
    final loans = ref.watch(loansControllerProvider).value ?? [];
    final alreadyBorrowed = loans.any((l) => l.bookId == widget.bookId);
    final waitlist = ref.watch(waitlistControllerProvider);
    final mine = waitlist.value?.forBook(widget.bookId);
    final latest = ref.watch(borrowRequestsControllerProvider).value?.latestFor(widget.bookId);
    final pending = latest?.status == BorrowRequestStatus.pending ? latest : null;
    final outcome = latest != null &&
            (latest.status == BorrowRequestStatus.declined || latest.status == BorrowRequestStatus.expired)
        ? latest
        : null;
    final requestLabel = outcome == null ? 'Request to borrow' : 'Request again';

    return PendingRefresh(
      active: pending != null,
      onTick: _recheck,
      child: Scaffold(
        appBar: AppBar(),
        body: bookAsync.when(
          loading: () => const Padding(padding: EdgeInsets.all(20), child: LoadingSkeleton(height: 210, borderRadius: 16)),
          error: (e, st) => ErrorState(title: "Couldn't load this book", onRetry: () => ref.invalidate(bookByIdProvider(widget.bookId))),
          data: (book) {
            if (book == null) return const Center(child: Text('Select a book to view its details.'));
            final copiesLine = Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, size: 15),
              const SizedBox(width: 6),
              Text('${book.freeCopies} of ${book.totalCopies} copies available'),
            ]);
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(children: [
                BookCover(book: book, width: 148, height: 208),
                const SizedBox(height: 14),
                Text(book.title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                Text(book.author, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Chip(label: Text(book.genre)),
                const SizedBox(height: 12),
                Text(book.description),
                const SizedBox(height: 16),
                if (alreadyBorrowed) ...[
                  copiesLine,
                  const SizedBox(height: 10),
                  TextButton(
                      onPressed: () => context.go('/loans'),
                      child: const Text('Borrowed — see My Loans for the due date')),
                ] else if (pending != null) ...[
                  Text(
                    'Requested — waiting for a librarian. Expires ${dayTimeLabel(pending.expiresAt, now: ref.read(clockProvider)())}.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                      onPressed: _cancelling.contains(pending.id) ? null : () => _cancelRequest(pending),
                      child: const Text('Cancel request')),
                ] else ...[
                  if (outcome != null) ...[
                    Text(_outcomeLine(outcome), textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                  ],
                  if (mine?.status == ReservationStatus.held) ...[
                    // Held copies are refused to everyone else, so this is the
                    // one case where the request button shows although the
                    // shelf copy is held.
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.bookmark_added, size: 15),
                      const SizedBox(width: 6),
                      Flexible(child: Text(_heldLine(mine!))),
                    ]),
                    const SizedBox(height: 10),
                    FilledButton(onPressed: _request, child: Text(requestLabel)),
                    TextButton(onPressed: () => _leaveWaitlist(mine), child: const Text('Release it to the next student')),
                  ] else if (mine != null) ...[
                    const Text('Currently unavailable'),
                    Text(mine.queuePosition != null ? "You're #${mine.queuePosition} in line." : "You're on the waitlist."),
                    const SizedBox(height: 10),
                    TextButton(onPressed: () => _leaveWaitlist(mine), child: const Text('Leave waitlist')),
                  ] else if (book.freeCopies > 0) ...[
                    copiesLine,
                    const SizedBox(height: 10),
                    FilledButton(onPressed: _request, child: Text(requestLabel)),
                  ] else ...[
                    Text(book.availableCopies > 0
                        ? 'Every copy on the shelf is held for a student on the waitlist.'
                        : 'Currently unavailable'),
                    Text(book.waitlistCount > 0
                        ? '${book.waitlistCount} ${book.waitlistCount == 1 ? 'person' : 'people'} ahead of you on the waitlist.'
                        : "You'll be first in line."),
                    const SizedBox(height: 10),
                    // Disabled until the waitlist has loaded: until then the screen
                    // can't know whether you're already on it.
                    OutlinedButton(onPressed: waitlist.isLoading ? null : _joinWaitlist, child: const Text('Join Waitlist')),
                  ],
                ],
              ]),
            );
          },
        ),
      ),
    );
  }
}
