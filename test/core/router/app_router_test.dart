// test/core/router/app_router_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/core/router/app_router.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/auth/splash_screen.dart';
import '../../support/fake_token_store.dart';
import '../../support/mock_overrides.dart';

/// Holds the startup session check open until [gate] completes, so a test can
/// observe the app while the check is still running.
class _GatedRestoreController extends AuthController {
  _GatedRestoreController(this.gate);
  final Completer<void> gate;

  @override
  Future<void> restoreSession() async {
    await gate.future;
    await super.restoreSession();
  }
}

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

  testWidgets('holds on the splash while the session check runs, then moves to login', (tester) async {
    // While the check is unresolved the app doesn't know where the user
    // belongs -- it must show the splash, not a login screen they'd then be
    // yanked away from.
    final gate = Completer<void>();
    final container = ProviderContainer(overrides: [
      ...mockRepositoryOverrides(),
      authControllerProvider.overrideWith(() => _GatedRestoreController(gate)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildSmartLibTheme(),
        routerConfig: container.read(routerProvider),
      ),
    ));
    // Settling here also proves the splash, in place, animates nothing forever.
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Log in'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('Log in'), findsWidgets);
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

  testWidgets('a saved session goes straight to Home, never showing login', (tester) async {
    final tokens = TokenStore(InMemoryTokenPersistence('saved-jwt'));
    final container = ProviderContainer(overrides: mockRepositoryOverrides(tokens: tokens));
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildSmartLibTheme(),
        routerConfig: container.read(routerProvider),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
    // Home starts the bookings grace-period timer; dispose inside the test
    // body, as the other Home-landing tests here do, so it's cancelled
    // before the binding checks for pending timers.
    container.dispose();
  });
}
