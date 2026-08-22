import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/catalog/search_screen.dart';

void main() {
  testWidgets('shows all 12 seeded books by default', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildSmartLibTheme(),
        home: const SearchScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('12 results'), findsOneWidget);
  });

  testWidgets('typing a query with no matches shows the empty state',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildSmartLibTheme(),
        home: const SearchScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nonexistent book title');
    await tester.pumpAndSettle();
    expect(find.text('No results'), findsOneWidget);
    expect(find.text('Clear search'), findsOneWidget);
  });
}
