// test/features/home/home_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/home/home_screen.dart';
import 'package:smartlib_frontend/models/app_user.dart';
import '../../support/mock_overrides.dart';

class _LoggedInAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
        loggedIn: true,
        user: AppUser(
          id: 'u1',
          name: 'Aditi Sharma',
          email: 'aditi.sharma@thapar.edu',
          roll: '1024160143',
        ),
      );
}

void main() {
  testWidgets('shows the returning-user greeting and both quick-glance sections', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_LoggedInAuthController.new),
        ...mockRepositoryOverrides(),
      ],
      child: MaterialApp(theme: buildSmartLibTheme(), home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back, Aditi'), findsOneWidget);
    expect(find.text('Active loans'), findsOneWidget);
    expect(find.text('Upcoming bookings'), findsOneWidget);
  });
}
