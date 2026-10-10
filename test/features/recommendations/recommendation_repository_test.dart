// test/features/recommendations/recommendation_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/recommendations/recommendation_repository.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/stub_http_adapter.dart';

void main() {
  group('HttpRecommendationRepository', () {
    test('fetches the user\'s recommendations; the server picks the note', () async {
      final dio = buildApiClient(TokenStore(InMemoryTokenPersistence()));
      final stub = StubHttpAdapter((_) => StubResponse(200, fixture('recommendations_me')));
      dio.httpClientAdapter = stub;
      final data = await HttpRecommendationRepository(dio).recommendations();
      expect(stub.requests.single.path, '/recommendations/me');
      expect(data.sections.single.title, 'Trending in the library');
    });
  });

  group('MockRecommendationRepository', () {
    test('with no loan history, returns the "popular right now" copy and sections', () async {
      final repo = MockRecommendationRepository(MockBookRepository(), hasLoanHistory: false);
      final data = await repo.recommendations();
      expect(data.note, "You haven't borrowed anything yet — here's what's popular right now.");
      expect(data.sections.first.title, 'Trending in the library');
      expect(data.sections.first.books.map((b) => b.id), ['b12', 'b5', 'b9', 'b1']);
    });

    test('defaults to a user with loans, like the seeded demo account', () async {
      final data = await MockRecommendationRepository(MockBookRepository()).recommendations();
      expect(data.note, 'Based on your last few loans.');
      expect(data.sections.first.title, 'Because you borrowed Introduction to Algorithms');
    });
  });
}
