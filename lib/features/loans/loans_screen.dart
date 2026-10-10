// lib/features/loans/loans_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/clock.dart';
import '../../core/time_format.dart';
import '../../core/ui/ui_controller.dart';
import '../../models/loan.dart';
import '../../models/reservation.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_skeleton.dart';
import '../catalog/catalog_providers.dart';
import '../waitlist/waitlist_controller.dart';
import 'loans_controller.dart';

class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({super.key});
  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(uiControllerProvider.notifier).onConfirmReturnLoan =
          (id) => ref.read(loansControllerProvider.notifier).returnLoan(id);
    });
  }

  String _dueLabel(DateTime d) => '${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    final loans = ref.watch(loansControllerProvider);
    // Held copies first: they pass to the next student when the hold runs out.
    final waitlist = [...?ref.watch(waitlistControllerProvider).value]
      ..sort((a, b) => a.status == b.status ? 0 : (a.status == ReservationStatus.held ? -1 : 1));
    return Scaffold(
      appBar: AppBar(title: const Text('My Loans')),
      body: loans.when(
        loading: () => ListView(padding: const EdgeInsets.all(20), children: const [
          LoadingSkeleton(height: 84), SizedBox(height: 10), LoadingSkeleton(height: 84),
        ]),
        error: (e, st) => ErrorState(title: "Couldn't load your loans", onRetry: () => ref.invalidate(loansControllerProvider)),
        data: (items) {
          if (items.isEmpty && waitlist.isEmpty) {
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
              // Headings only when there's a waitlist to tell apart from the loans.
              if (waitlist.isNotEmpty) ...[
                Text('Waitlist', style: heading),
                const SizedBox(height: 6),
                for (final r in waitlist) _waitlistCard(context, r),
                const SizedBox(height: 14),
                Text('On loan', style: heading),
                const SizedBox(height: 6),
                if (items.isEmpty) const Text('No active loans.'),
              ],
              for (final l in items) _loanCard(context, l),
            ],
          );
        },
      ),
    );
  }

  Widget _waitlistCard(BuildContext context, Reservation r) {
    final book = ref.watch(bookByIdProvider(r.bookId)).value;
    final until = r.claimExpiresAt;
    final status = switch (r.status) {
      ReservationStatus.held => until == null
          ? 'Held for you — borrow it soon'
          : 'Held for you until ${dayTimeLabel(until, now: ref.read(clockProvider)())} — borrow it before then',
      ReservationStatus.waiting => r.queuePosition == null ? 'On the waitlist' : '#${r.queuePosition} in line',
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
