// test/core/router/app_router_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/router/app_router.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import '../../support/mock_overrides.dart';

void main() {
  testWidgets('starts on the auth screen when logged out', (tester) async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildSmartLibTheme(),
        routerConfig: container.read(routerProvider),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('SmartLib'), findsOneWidget);
    expect(find.text('Log in'), findsWidgets);
    container.dispose();
  });

  testWidgets('logging in redirects to Home and shows the tab bar', (tester) async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildSmartLibTheme(),
        routerConfig: container.read(routerProvider),
      ),
    ));
    await tester.enterText(find.byType(TextField).first, 'aditi.sharma@thapar.edu');
    await tester.enterText(find.byType(TextField).at(1), 'anything');
    await tester.tap(find.text('Log in').last);
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsWidgets); // tab bar label
    expect(find.byType(NavigationBar), findsOneWidget);
    container.dispose();
  });
}
