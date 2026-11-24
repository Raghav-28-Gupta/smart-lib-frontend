// lib/features/loans/loans_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/clock.dart';
import '../../core/time_format.dart';
import '../../core/ui/ui_controller.dart';
import '../../models/borrow_request.dart';
import '../../models/loan.dart';
import '../../models/reservation.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pending_refresh.dart';
import '../borrow_requests/borrow_requests_controller.dart';
import '../catalog/catalog_providers.dart';
import '../fines/fines_controller.dart';
import '../fines/fines_section.dart';
import '../notices/notices_controller.dart';
import '../notices/notices_section.dart';
import '../waitlist/waitlist_controller.dart';
import 'loans_controller.dart';

const _updateTheApp = "Update the app to see this item's status.";

class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({super.key});
  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  // Requests being withdrawn: their Cancel button is off until the server answers.
  final _cancelling = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(uiControllerProvider.notifier).onConfirmReturnLoan =
          (id, report) => ref.read(loansControllerProvider.notifier).returnLoan(id, report: report);
      _refreshOnOpen();
    });
  }

  /// The lists were loaded when the student first needed them (the loans usually
  /// on Home), so they can predate a payment, a waive or adjustment of a fine, a
  /// loan a librarian marked lost, or a notice the library wrote. Each time this
  /// screen opens it asks the server once for each, quietly: a failure keeps what
  /// is on screen. A list still loading is itself that fresh fetch, so only that
  /// one is skipped (the fines and notices are first loaded by this screen, while
  /// the loans were usually loaded long before). Each visit to the tab builds a
  /// new screen (the tabs are a plain ShellRoute), so this runs on every visit.
  void _refreshOnOpen() {
    if (!mounted) return;
    if (!ref.read(loansControllerProvider).isLoading) {
      ref.read(loansControllerProvider.notifier).refreshQuietly();
    }
    if (!ref.read(finesControllerProvider).isLoading) {
      ref.read(finesControllerProvider.notifier).refreshQuietly();
    }
    if (!ref.read(noticesControllerProvider).isLoading) {
      ref.read(noticesControllerProvider.notifier).refreshQuietly();
    }
  }

  String _dueLabel(DateTime d) => '${d.month}/${d.day}';

  // The 30-second re-check while a request waits: an approval turns it into
  // a loan, so both lists are refetched, quietly.
  void _recheck() {
    ref.read(borrowRequestsControllerProvider.notifier).refreshQuietly();
    ref.read(loansControllerProvider.notifier).refreshQuietly();
  }

  Future<void> _cancelRequest(BorrowRequest r) async {
    setState(() => _cancelling.add(r.id));
    try {
      await ref
          .read(uiControllerProvider.notifier)
          .attempt(() => ref.read(borrowRequestsControllerProvider.notifier).cancel(r.id), success: 'Request cancelled.');
    } finally {
      if (mounted) setState(() => _cancelling.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loans = ref.watch(loansControllerProvider);
    // When a different student logs in these lists rebuild, and Riverpod carries the
    // last student's list along on the loading state (`isReloading`) and beside the
    // error if the fetch fails, so `.value` would still be theirs. Read as not
    // loaded until this student's answer arrives. (The loans need no guard:
    // `loans.when` shows its loading or error branch there.)
    T? own<T>(AsyncValue<T> list) => list.isReloading || list.hasError ? null : list.value;
    // Held copies first: they pass to the next student when the hold runs out.
    final waitlist = [...?own(ref.watch(waitlistControllerProvider))]
      ..sort((a, b) => a.status == b.status ? 0 : (a.status == ReservationStatus.held ? -1 : 1));
    final requests = (own(ref.watch(borrowRequestsControllerProvider)) ?? const <BorrowRequest>[]).latestPerBook();
    // Known to be empty, not merely not loaded yet: a student with fines but
    // nothing else must not see the empty state flash first.
    final noFines = own(ref.watch(finesControllerProvider))?.fines.isEmpty ?? false;
    // A student whose only news is a notice (the outcome of a report on a book they
    // returned) must see it, not the empty state, so that waits for the notices too.
    // They are secondary, though: a list that could not be loaded does not keep the
    // empty state away. The error shows at once, retries included; a loading state
    // still holding the last student's error is not theirs (as for the fines below).
    final noticesState = ref.watch(noticesControllerProvider);
    final noticesFailed = noticesState.hasError && (!noticesState.isLoading || noticesState.retrying);
    final noNotices = noticesFailed || (own(noticesState)?.isEmpty ?? false);
    return PendingRefresh(
      active: requests.anyPending,
      onTick: _recheck,
      child: Scaffold(
        appBar: AppBar(title: const Text('My Loans')),
        body: loans.when(
          loading: () => ListView(padding: const EdgeInsets.all(20), children: const [
            LoadingSkeleton(height: 84), SizedBox(height: 10), LoadingSkeleton(height: 84),
          ]),
          error: (e, st) => ErrorState(title: "Couldn't load your loans", onRetry: () => ref.invalidate(loansControllerProvider)),
          data: (items) {
            if (items.isEmpty && waitlist.isEmpty && requests.isEmpty && noFines && noNotices) {
              return EmptyState(
                icon: Icons.menu_book, title: 'No active loans',
                body: 'Search the catalog to borrow your first book.',
                actionLabel: 'Browse the catalog',
                onAction: () => context.go('/search'),
              );
            }
            final heading = Theme.of(context).textTheme.titleSmall;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Hides itself when there are none, while they load and when they fail.
                const NoticesSection(),
                if (requests.isNotEmpty) ...[
                  Text('Requests', style: heading),
                  const SizedBox(height: 6),
                  for (final r in requests) _requestCard(context, r),
                  const SizedBox(height: 14),
                ],
                if (waitlist.isNotEmpty) ...[
                  Text('Waitlist', style: heading),
                  const SizedBox(height: 6),
                  for (final r in waitlist) _waitlistCard(context, r),
                  const SizedBox(height: 14),
                ],
                // The Fines section is always below, so the loans are always headed.
                Text('On loan', style: heading),
                const SizedBox(height: 6),
                if (items.isEmpty) const Text('No active loans.'),
                for (final l in items) _loanCard(context, l),
                const SizedBox(height: 14),
                const FinesSection(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _requestCard(BuildContext context, BorrowRequest r) {
    final book = ref.watch(bookByIdProvider(r.bookId)).value;
    final status = switch (r.status) {
      BorrowRequestStatus.pending =>
        'Waiting for a librarian · expires ${dayTimeLabel(r.expiresAt, now: ref.read(clockProvider)())}',
      BorrowRequestStatus.declined => r.declineReason == null ? 'Declined by the library' : 'Declined — ${r.declineReason}',
      BorrowRequestStatus.expired => 'Expired — no librarian approved it in time',
      _ => _updateTheApp,
    };
    return Card(child: ListTile(
      leading: book == null ? null : BookCover(book: book, width: 30, height: 42),
      title: Text(r.bookTitle),
      subtitle: Text(status),
      trailing: r.status == BorrowRequestStatus.pending
          ? TextButton(
              onPressed: _cancelling.contains(r.id) ? null : () => _cancelRequest(r),
              child: const Text('Cancel request'))
          : null,
      onTap: () => context.push('/book/${r.bookId}'),
    ));
  }

  Widget _waitlistCard(BuildContext context, Reservation r) {
    final book = ref.watch(bookByIdProvider(r.bookId)).value;
    final until = r.claimExpiresAt;
    final status = switch (r.status) {
      ReservationStatus.held => until == null
          ? 'Held for you — borrow it soon'
          : 'Held for you until ${dayTimeLabel(until, now: ref.read(clockProvider)())} — borrow it before then',
      ReservationStatus.waiting => r.queuePosition == null ? 'On the waitlist' : '#${r.queuePosition} in line',
      ReservationStatus.unknown => _updateTheApp,
    };
    return Card(child: ListTile(
      leading: book == null ? null : BookCover(book: book, width: 30, height: 42),
      title: Text(book?.title ?? ''),
      subtitle: Text(status, style: r.status == ReservationStatus.held ? const TextStyle(fontWeight: FontWeight.w600) : null),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/book/${r.bookId}'),
    ));
  }

  Widget _loanCard(BuildContext context, Loan l) {
    final book = ref.watch(bookByIdProvider(l.bookId)).value;
    if (l.status == LoanStatus.unknown) {
      return Card(child: ListTile(title: Text(book?.title ?? ''), subtitle: const Text(_updateTheApp)));
    }
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (book != null) BookCover(book: book, width: 36, height: 50),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(book?.title ?? '', style: Theme.of(context).textTheme.titleSmall),
            Text(book?.author ?? ''),
            Text(
              l.status == LoanStatus.overdue ? 'Overdue — was due ${_dueLabel(l.dueDate)}' : 'Due ${_dueLabel(l.dueDate)}',
              style: TextStyle(color: l.status == LoanStatus.overdue ? Theme.of(context).colorScheme.error : null, fontWeight: FontWeight.w600),
            ),
            if (l.status == LoanStatus.overdue) Text('Fine: ₹${l.fineAmount} and counting'),
          ])),
        ]),
        if (l.justRenewed) Text('Renewed — now due ${_dueLabel(l.dueDate)}'),
        if (l.canRenew == false) Text('Renewal unavailable — ${l.blockedReason}'),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: l.canRenew
                ? () => ref.read(uiControllerProvider.notifier).attempt(() => ref.read(loansControllerProvider.notifier).renew(l.id))
                : null,
            child: const Text('Renew'),
          )),
          const SizedBox(width: 8),
          // Off while this loan's return is on the wire (the dialog closed at once, so
          // nothing else shows it): a second return would be refused and its toast
          // would replace "Returned. Thanks for the report."
          Expanded(child: TextButton(
            onPressed: ref.read(loansControllerProvider.notifier).isReturning(l.id)
                ? null
                : () => ref.read(uiControllerProvider.notifier).askReturnLoan(l.id),
            child: const Text('Return'),
          )),
        ]),
      ]),
    ));
  }
}
