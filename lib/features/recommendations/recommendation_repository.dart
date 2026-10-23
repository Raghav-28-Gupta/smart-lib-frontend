// lib/features/recommendations/recommendation_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../models/recommendation.dart';
import '../auth/auth_controller.dart';
import '../catalog/book_repository.dart';

abstract class RecommendationRepository {
  /// Recommendations for the logged-in user. The server decides the note and
  /// sections -- including whether the user has borrowed before -- so the
  /// client no longer works that out from its own loans list.
  Future<RecommendationsData> recommendations();
}

class HttpRecommendationRepository implements RecommendationRepository {
  HttpRecommendationRepository(this._dio);

  final Dio _dio;

  @override
  Future<RecommendationsData> recommendations() async {
    final res = await guardApi(() => _dio.get<Map<String, dynamic>>('/recommendations/me'));
    return RecommendationsData.fromJson(res.data!);
  }
}

const _newSections = [
  ('Trending in the library', 'Most borrowed this month', ['b12', 'b5', 'b9', 'b1']),
  ('Popular in Computer Science', 'Trending with CSE students', ['b1', 'b5', 'b7', 'b8']),
];

const _returningSections = [
  ('Because you borrowed Introduction to Algorithms', 'More in algorithms & theory', ['b5', 'b7', 'b6']),
  ('Students who read what you did also liked', 'Borrowed by similar readers', ['b12', 'b11']),
];

/// Test double. Defaults to a user with loans, like the seeded demo account;
/// [hasLoanHistory] false gives the first-time-borrower answer instead.
class MockRecommendationRepository implements RecommendationRepository {
  MockRecommendationRepository(this._books, {this.hasLoanHistory = true});
  final BookRepository _books;
  final bool hasLoanHistory;

  @override
  Future<RecommendationsData> recommendations() async {
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

final recommendationRepositoryProvider =
    Provider<RecommendationRepository>((ref) => HttpRecommendationRepository(ref.watch(apiClientProvider)));

// No longer watches the loans list: the server computes the note itself.
// Auto-disposed, so it refetches when Home is shown again; a request creates no
// loan until a librarian approves it, so nothing refreshes it explicitly. Keyed
// on the user so it never shows one user's picks to the next.
final recommendationsProvider = FutureProvider.autoDispose((ref) async {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  return ref.watch(recommendationRepositoryProvider).recommendations();
});
