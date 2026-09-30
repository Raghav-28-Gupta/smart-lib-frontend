// test/features/auth/splash_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/auth/splash_screen.dart';

void main() {
  testWidgets('shows the wordmark', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildSmartLibTheme(), home: const SplashScreen()));
    expect(find.text('SmartLib'), findsOneWidget);
  });

  testWidgets('settles -- nothing on it animates forever', (tester) async {
    // Every widget test that boots the app calls pumpAndSettle while the
    // splash is up. An indeterminate spinner never settles, so each of them
    // would hang for the default 10-minute timeout. A short timeout here
    // turns that regression into one fast, obvious failure.
    await tester.pumpWidget(MaterialApp(theme: buildSmartLibTheme(), home: const SplashScreen()));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
  });
}
