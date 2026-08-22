import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/auth/auth_screen.dart';

void main() {
  testWidgets(
      'submitting the login form with empty fields shows the validation message',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildSmartLibTheme(),
        home: const AuthScreen(),
      ),
    ));
    await tester.tap(find.text('Log in').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter your email and password.'), findsOneWidget);
  });

  testWidgets('switching to Create account shows the registration fields',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildSmartLibTheme(),
        home: const AuthScreen(),
      ),
    ));
    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();
    expect(find.text('Full name'), findsOneWidget);
  });
}
