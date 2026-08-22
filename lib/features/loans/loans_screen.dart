// lib/features/loans/loans_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ui/ui_controller.dart';
import '../../models/loan.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_skeleton.dart';
import '../catalog/catalog_providers.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('My Loans')),
      body: loans.when(
        loading: () => ListView(padding: const EdgeInsets.all(20), children: const [
          LoadingSkeleton(height: 84), SizedBox(height: 10), LoadingSkeleton(height: 84),
        ]),
        error: (e, st) => ErrorState(title: "Couldn't load your loans", onRetry: () => ref.invalidate(loansControllerProvider)),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.menu_book, title: 'No active loans',
              body: 'Search the catalog to borrow your first book.',
              actionLabel: 'Browse the catalog', onAction: () {},
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final l = items[i];
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
                      onPressed: l.canRenew ? () => ref.read(loansControllerProvider.notifier).renew(l.id) : null,
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
            },
          );
        },
      ),
    );
  }
}
