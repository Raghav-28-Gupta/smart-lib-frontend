// test/features/bookings/bookings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/bookings/bookings_screen.dart';

void main() {
  testWidgets('shows the far-booking and in-window copy for the seeded bookings', (tester) async {
    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookingsScreen(),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('check-in opens 10 min before'), findsOneWidget);
    expect(find.textContaining('Check in within'), findsOneWidget);
  });
}
