// test/models/recommendation_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/models/recommendation.dart';
import '../support/fixtures.dart';

void main() {
  test('parses GET /recommendations/me, with each section book parsed as a Book', () {
    final data = RecommendationsData.fromJson(fixture('recommendations_me') as Map<String, dynamic>);
    expect(data.note, startsWith('Personalized picks are on the way'));
    expect(data.sections, hasLength(1));

    final trending = data.sections.single;
    expect(trending.title, 'Trending in the library');
    expect(trending.caption, 'Most borrowed in the last 30 days');
    expect(trending.books, isNotEmpty);
    expect(trending.books.first.title, 'Database System Concepts');
  });

  test('parses an empty library, which returns no sections', () {
    final data = RecommendationsData.fromJson(const {
      'note': 'No recommendations available yet.',
      'sections': <Object>[],
    });
    expect(data.sections, isEmpty);
  });
}
