import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/book.dart';
import 'book_repository.dart';

class _SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setValue(String value) => state = value;
}

class _ActiveGenreNotifier extends Notifier<String> {
  @override
  String build() => 'All';

  void setValue(String value) => state = value;
}

final searchQueryProvider =
    NotifierProvider<_SearchQueryNotifier, String>(_SearchQueryNotifier.new);
final activeGenreProvider =
    NotifierProvider<_ActiveGenreNotifier, String>(_ActiveGenreNotifier.new);

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
