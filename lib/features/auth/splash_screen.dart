// lib/features/auth/splash_screen.dart
import 'package:flutter/material.dart';

/// Shown while the startup session check runs.
///
/// Deliberately static -- no progress indicator, no repeating animation.
/// Widget tests boot the app and call pumpAndSettle while this is on screen,
/// and an indeterminate spinner never settles, so every one of them would
/// hang until timeout. The check is fast enough that a spinner would barely
/// show anyway. Styled like the login screen's wordmark, so the hand-off
/// between the two doesn't jump.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book, size: 40),
            const SizedBox(height: 8),
            Text('SmartLib', style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}
