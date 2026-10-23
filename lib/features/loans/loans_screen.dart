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
          (id) => ref.read(loansControllerProvider.notifier).returnLoan(id);
    });
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
    // Held copies first: they pass to the next student when the hold runs out.
    final waitlist = [...?ref.watch(waitlistControllerProvider).value]
      ..sort((a, b) => a.status == b.status ? 0 : (a.status == ReservationStatus.held ? -1 : 1));
    final requests = (ref.watch(borrowRequestsControllerProvider).value ?? const <BorrowRequest>[]).latestPerBook();
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
            if (items.isEmpty && waitlist.isEmpty && requests.isEmpty) {
              return EmptyState(
                icon: Icons.menu_book, title: 'No active loans',
                body: 'Search the catalog to borrow your first book.',
                actionLabel: 'Browse the catalog',
                onAction: () => context.go('/search'),
              );
            }
            final heading = Theme.of(context).textTheme.titleSmall;
            // Headings only when there's more than the loans to tell apart.
            final sectioned = requests.isNotEmpty || waitlist.isNotEmpty;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                if (sectioned) ...[
                  Text('On loan', style: heading),
                  const SizedBox(height: 6),
                  if (items.isEmpty) const Text('No active loans.'),
                ],
                for (final l in items) _loanCard(context, l),
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
          Expanded(child: TextButton(
            onPressed: () => ref.read(uiControllerProvider.notifier).askReturnLoan(l.id),
            child: const Text('Return'),
          )),
        ]),
      ]),
    ));
  }
}
