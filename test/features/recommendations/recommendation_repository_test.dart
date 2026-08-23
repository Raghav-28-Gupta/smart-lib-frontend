// test/features/recommendations/recommendation_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/recommendations/recommendation_repository.dart';

void main() {
  test('no loan history returns the "popular right now" copy and sections', () async {
    final repo = MockRecommendationRepository(MockBookRepository());
    final data = await repo.recommendationsFor(hasLoanHistory: false);
    expect(data.note, "You haven't borrowed anything yet — here's what's popular right now.");
    expect(data.sections.first.title, 'Trending in the library');
    expect(data.sections.first.books.map((b) => b.id), ['b12', 'b5', 'b9', 'b1']);
  });

  test('has loan history returns the "based on your loans" copy and sections', () async {
    final repo = MockRecommendationRepository(MockBookRepository());
    final data = await repo.recommendationsFor(hasLoanHistory: true);
    expect(data.note, 'Based on your last few loans.');
    expect(data.sections.first.title, 'Because you borrowed Introduction to Algorithms');
  });
}
