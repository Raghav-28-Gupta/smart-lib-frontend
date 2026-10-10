// test/features/recommendations/recommendations_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/catalog/book_repository.dart';
import 'package:smartlib_frontend/features/recommendations/recommendation_repository.dart';
import 'package:smartlib_frontend/features/recommendations/recommendations_screen.dart';
import '../../support/mock_overrides.dart';

void main() {
  testWidgets('a fresh user (no loans) sees the popular-right-now copy and sections', (tester) async {
    await tester.pumpWidget(ProviderScope(
      // The server decides the copy now; this is its answer for a user with
      // no loans.
      overrides: mockRepositoryOverrides(
        recommendations: MockRecommendationRepository(MockBookRepository(), hasLoanHistory: false),
      ),
      child: MaterialApp(
        theme: buildSmartLibTheme(),
        home: const RecommendationsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text("You haven't borrowed anything yet — here's what's popular right now."), findsOneWidget);
    expect(find.text('Trending in the library'), findsOneWidget);
  });

  testWidgets('a user with loans sees the based-on-your-loans copy', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: mockRepositoryOverrides(),
      child: MaterialApp(
        theme: buildSmartLibTheme(),
        home: const RecommendationsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Based on your last few loans.'), findsOneWidget);
    expect(find.text('Because you borrowed Introduction to Algorithms'), findsOneWidget);
  });
}
