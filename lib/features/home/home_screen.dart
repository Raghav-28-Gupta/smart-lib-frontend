// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/book_cover.dart';
import '../auth/auth_controller.dart';
import '../bookings/bookings_controller.dart';
import '../catalog/catalog_providers.dart';
import '../loans/loans_controller.dart';
import '../recommendations/recommendation_repository.dart';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final loans = ref.watch(loansControllerProvider).value ?? [];
    final bookings = ref.watch(bookingsControllerProvider).value ?? [];
    final recs = ref.watch(recommendationsProvider).value;

    final firstName = (auth.user?.name ?? '').split(' ').first;
    final greeting = loans.isNotEmpty ? 'Welcome back, $firstName' : 'Welcome, $firstName';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(greeting, style: Theme.of(context).textTheme.titleLarge),
                    const Text('Central Library'),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => context.go('/profile'),
                child: CircleAvatar(child: Text(_initials(auth.user?.name ?? ''))),
              ),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => context.go('/search'),
                  child: const _QuickAction(icon: Icons.search, label: 'Search'),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.go('/loans'),
                  child: const _QuickAction(icon: Icons.menu_book, label: 'My Loans'),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.go('/bookings'),
                  child: const _QuickAction(icon: Icons.event, label: 'Bookings'),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Active loans', style: Theme.of(context).textTheme.titleSmall),
                TextButton(onPressed: () => context.go('/loans'), child: const Text('See all')),
              ],
            ),
            if (loans.isEmpty)
              const Text('No active loans yet — search the catalog to borrow your first book.')
            else
              Consumer(builder: (context, ref, _) {
                final book = ref.watch(bookByIdProvider(loans.first.bookId)).value;
                if (book == null) return const SizedBox.shrink();
                return Card(
                  child: ListTile(
                    leading: BookCover(book: book, width: 34, height: 46),
                    title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Due ${loans.first.dueDate.month}/${loans.first.dueDate.day}'),
                  ),
                );
              }),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Upcoming bookings', style: Theme.of(context).textTheme.titleSmall),
                TextButton(onPressed: () => context.go('/bookings'), child: const Text('See all')),
              ],
            ),
            if (bookings.isEmpty)
              const Text('No bookings yet — reserve a seat or room to get started.')
            else
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event),
                  title: Text(bookings.first.resourceName),
                  subtitle: Text(bookings.first.timeSlot),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Icon(Icons.auto_awesome, size: 16),
                  const SizedBox(width: 6),
                  Text('Recommended for you', style: Theme.of(context).textTheme.titleSmall),
                ]),
                TextButton(
                  onPressed: () => context.push('/recommendations'),
                  child: const Text('See all'),
                ),
              ],
            ),
            if (recs != null) ...[
              Text(recs.sections.first.caption, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 8),
              SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recs.sections.first.books.take(4).length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final b = recs.sections.first.books[i];
                    return SizedBox(
                      width: 104,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BookCover(book: b, width: 104, height: 120),
                          const SizedBox(height: 4),
                          Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}
