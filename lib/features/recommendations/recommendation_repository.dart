// lib/features/recommendations/recommendation_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/recommendation.dart';
import '../catalog/book_repository.dart';
import '../loans/loans_controller.dart';

abstract class RecommendationRepository {
  Future<RecommendationsData> recommendationsFor({required bool hasLoanHistory});
}

const _newSections = [
  ('Trending in the library', 'Most borrowed this month', ['b12', 'b5', 'b9', 'b1']),
  ('Popular in Computer Science', 'Trending with CSE students', ['b1', 'b5', 'b7', 'b8']),
];

const _returningSections = [
  ('Because you borrowed Introduction to Algorithms', 'More in algorithms & theory', ['b5', 'b7', 'b6']),
  ('Students who read what you did also liked', 'Borrowed by similar readers', ['b12', 'b11']),
];

class MockRecommendationRepository implements RecommendationRepository {
  MockRecommendationRepository(this._books);
  final BookRepository _books;

  @override
  Future<RecommendationsData> recommendationsFor({required bool hasLoanHistory}) async {
    final note = hasLoanHistory ? 'Based on your last few loans.' : "You haven't borrowed anything yet — here's what's popular right now.";
    final sectionSeeds = hasLoanHistory ? _returningSections : _newSections;
    final sections = <RecommendationSection>[];
    for (final (title, caption, ids) in sectionSeeds) {
      final books = [for (final id in ids) if (await _books.getById(id) case final b?) b];
      sections.add(RecommendationSection(title: title, caption: caption, books: books));
    }
    return RecommendationsData(note: note, sections: sections);
  }
}

final recommendationRepositoryProvider = Provider<RecommendationRepository>((ref) => MockRecommendationRepository(ref.watch(bookRepositoryProvider)));

final recommendationsProvider = FutureProvider.autoDispose((ref) async {
  final hasHistory = (ref.watch(loansControllerProvider).value ?? []).isNotEmpty;
  return ref.watch(recommendationRepositoryProvider).recommendationsFor(hasLoanHistory: hasHistory);
});
