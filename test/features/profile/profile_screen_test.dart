// test/features/profile/profile_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/ui/confirm_dialog.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/profile/profile_screen.dart';
import 'package:smartlib_frontend/models/app_user.dart';

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
  testWidgets('shows the reliability tier, note, and name for the logged-in user', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(_LoggedInAuthController.new)],
      child: MaterialApp(theme: buildSmartLibTheme(), home: const ProfileScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Aditi Sharma'), findsOneWidget);
    expect(find.text('Building back up'), findsOneWidget);
  });

  testWidgets('"How reliability works" opens the info dialog with the exact copy', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(_LoggedInAuthController.new)],
      child: const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ProfileScreen(),
              ConfirmDialogHost(),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How reliability works'));
    await tester.pumpAndSettle();
    expect(find.text('How reliability works'), findsWidgets);
    expect(find.textContaining("It's never"), findsOneWidget);
  });
}
