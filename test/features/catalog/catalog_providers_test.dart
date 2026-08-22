import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/catalog/catalog_providers.dart';

void main() {
  test('searchResultsProvider returns all 12 books by default', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final books = await container.read(searchResultsProvider.future);
    expect(books.length, 12);
  });

  test('searchResultsProvider filters by query across title and author',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(searchQueryProvider.notifier).state = 'clean code';
    final books = await container.read(searchResultsProvider.future);
    expect(books.single.id, 'b8');
  });

  test('searchResultsProvider filters by genre', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeGenreProvider.notifier).state = 'Fiction';
    final books = await container.read(searchResultsProvider.future);
    expect(books.map((b) => b.id).toSet(), {'b9', 'b10'});
  });

  test('bookByIdProvider returns the matching book', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final book = await container.read(bookByIdProvider('b12').future);
    expect(book?.title, 'Atomic Habits');
  });
}
