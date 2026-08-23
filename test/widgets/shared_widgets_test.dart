import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/models/book.dart';
import 'package:smartlib_frontend/widgets/book_cover.dart';
import 'package:smartlib_frontend/widgets/empty_state.dart';
import 'package:smartlib_frontend/widgets/error_state.dart';
import 'package:smartlib_frontend/widgets/reliability_ring.dart';

void main() {
  testWidgets('EmptyState shows title, body, and an optional action button', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EmptyState(
      icon: Icons.search, title: 'No results', body: 'Try another search.',
      actionLabel: 'Clear search', onAction: () => tapped = true,
    ))));
    expect(find.text('No results'), findsOneWidget);
    expect(find.text('Try another search.'), findsOneWidget);
    await tester.tap(find.text('Clear search'));
    expect(tapped, true);
  });

  testWidgets('ErrorState shows the retry button and calls onRetry', (tester) async {
    var retried = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ErrorState(title: "Couldn't load your dashboard", onRetry: () => retried = true),
    )));
    expect(find.text("Couldn't load your dashboard"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, true);
  });

  testWidgets('BookCover shows the initial letter on the palette color', (tester) async {
    const book = Book(
      id: 'b1', title: 'Clean Code', author: 'Robert C. Martin', genre: 'Software Eng.',
      description: 'd', totalCopies: 4, availableCopies: 2, waitlistCount: 0,
      coverPalette: CoverPalette.accent2,
    );
    await tester.pumpWidget(MaterialApp(
        theme: buildSmartLibTheme(),
        home: const Scaffold(
          body: BookCover(book: book, width: 100, height: 140),
        )));
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('ReliabilityRing shows the center label', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: ReliabilityRing(fraction: 0.5, centerLabel: 'Building back up'),
    )));
    expect(find.text('Building back up'), findsOneWidget);
  });
}
