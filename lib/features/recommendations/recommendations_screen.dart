// lib/features/recommendations/recommendations_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/error_state.dart';
import 'recommendation_repository.dart';

class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(recommendationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recommended for You')),
      body: recs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(
          title: "Couldn't load recommendations",
          onRetry: () => ref.invalidate(recommendationsProvider),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(data.note, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            for (final section in data.sections) ...[
              Text(section.title, style: Theme.of(context).textTheme.titleSmall),
              Text(section.caption, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 8),
              SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: section.books.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final b = section.books[i];
                    return GestureDetector(
                      onTap: () => context.push('/book/${b.id}'),
                      child: SizedBox(
                        width: 104,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BookCover(book: b, width: 104, height: 120),
                            const SizedBox(height: 4),
                            Text(
                              b.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}
