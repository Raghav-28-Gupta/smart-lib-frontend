import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../models/book.dart';
import 'book_repository.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');
final activeGenreProvider = StateProvider<String>((ref) => 'All');

final searchResultsProvider =
    FutureProvider.autoDispose<List<Book>>((ref) async {
  final repo = ref.watch(bookRepositoryProvider);
  return repo.search(
      query: ref.watch(searchQueryProvider),
      genre: ref.watch(activeGenreProvider));
});

final bookByIdProvider =
    FutureProvider.family.autoDispose<Book?, String>((ref, id) async {
  return ref.watch(bookRepositoryProvider).getById(id);
});
