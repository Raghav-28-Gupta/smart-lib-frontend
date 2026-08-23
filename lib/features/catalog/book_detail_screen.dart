// lib/features/catalog/book_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_skeleton.dart';
import '../loans/loan_repository.dart';
import '../loans/loans_controller.dart';
import 'book_repository.dart';
import 'catalog_providers.dart';

class BookDetailScreen extends ConsumerStatefulWidget {
  const BookDetailScreen({super.key, required this.bookId});
  final String bookId;
  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  bool _waitlisted = false;

  Future<void> _borrow() async {
    await ref.read(bookRepositoryProvider).borrow(widget.bookId);
    final loan = await ref.read(loanRepositoryProvider).createLoan(widget.bookId);
    ref.read(loansControllerProvider.notifier).prependLoan(loan);
    ref.invalidate(bookByIdProvider(widget.bookId));
  }

  Future<void> _joinWaitlist() async {
    await ref.read(bookRepositoryProvider).joinWaitlist(widget.bookId);
    ref.invalidate(bookByIdProvider(widget.bookId));
    setState(() => _waitlisted = true);
  }

  @override
  Widget build(BuildContext context) {
    final bookAsync = ref.watch(bookByIdProvider(widget.bookId));
    final loans = ref.watch(loansControllerProvider).value ?? [];
    final alreadyBorrowed = loans.any((l) => l.bookId == widget.bookId);

    return Scaffold(
      appBar: AppBar(),
      body: bookAsync.when(
        loading: () => const Padding(padding: EdgeInsets.all(20), child: LoadingSkeleton(height: 210, borderRadius: 16)),
        error: (e, st) => ErrorState(title: "Couldn't load this book", onRetry: () => ref.invalidate(bookByIdProvider(widget.bookId))),
        data: (book) {
          if (book == null) return const Center(child: Text('Select a book to view its details.'));
          final available = book.availableCopies > 0;
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
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle, size: 15),
                  const SizedBox(width: 6),
                  Text('${book.availableCopies} of ${book.totalCopies} copies available'),
                ]),
                const SizedBox(height: 10),
                TextButton(
                    onPressed: () => context.go('/loans'),
                    child:
                        const Text('Borrowed — see My Loans for the due date')),
              ] else if (available) ...[
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle, size: 15),
                  const SizedBox(width: 6),
                  Text('${book.availableCopies} of ${book.totalCopies} copies available'),
                ]),
                const SizedBox(height: 10),
                FilledButton(onPressed: _borrow, child: const Text('Borrow this copy')),
              ] else ...[
                const Text('Currently unavailable'),
                Text(book.waitlistCount > 0
                    ? '${book.waitlistCount} ${book.waitlistCount == 1 ? 'person' : 'people'} ahead of you on the waitlist.'
                    : "You'll be first in line."),
                const SizedBox(height: 10),
                if (_waitlisted)
                  const Text("You're on the waitlist. We'll notify you when it's your turn.")
                else
                  OutlinedButton(onPressed: _joinWaitlist, child: const Text('Join Waitlist')),
              ],
            ]),
          );
        },
      ),
    );
  }
}
