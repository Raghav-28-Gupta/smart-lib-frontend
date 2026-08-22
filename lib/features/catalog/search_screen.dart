import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_skeleton.dart';
import 'book_repository.dart';
import 'catalog_providers.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchResultsProvider);
    final activeGenre = ref.watch(activeGenreProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Title or author'),
              onChanged: (v) =>
                  ref.read(searchQueryProvider.notifier).state = v,
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final g in kGenres)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(g),
                      selected: g == activeGenre,
                      onSelected: (_) =>
                          ref.read(activeGenreProvider.notifier).state = g,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: results.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  LoadingSkeleton(height: 64),
                  SizedBox(height: 10),
                  LoadingSkeleton(height: 64),
                ],
              ),
              error: (e, st) => ErrorState(
                title: "Couldn't load the catalog",
                onRetry: () => ref.invalidate(searchResultsProvider),
              ),
              data: (books) {
                if (books.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off,
                    title: 'No results',
                    body:
                        'Nothing matches "$query". Try a different title, author or genre.',
                    actionLabel: 'Clear search',
                    onAction: () {
                      ref.read(searchQueryProvider.notifier).state = '';
                      ref.read(activeGenreProvider.notifier).state = 'All';
                    },
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      child: Text(
                          '${books.length} ${books.length == 1 ? 'result' : 'results'}'),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: books.length,
                        itemBuilder: (context, i) {
                          final b = books[i];
                          final availLabel = b.availableCopies > 0
                              ? '${b.availableCopies} available'
                              : (b.waitlistCount > 0
                                  ? '${b.waitlistCount} waiting'
                                  : 'Join waitlist');
                          return ListTile(
                            leading: BookCover(book: b, width: 40, height: 56),
                            title: Text(b.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle:
                                Text('${b.author}\n$availLabel', maxLines: 2),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {},
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
