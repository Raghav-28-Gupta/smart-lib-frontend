// test/features/bookings/booking_flow_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/bookings/booking_flow_screen.dart';

void main() {
  testWidgets('picking a free slot and confirming shows the Booked success screen', (tester) async {
    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookingFlowScreen(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9:00 AM').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();
    expect(find.text('Booked'), findsOneWidget);
  });

  testWidgets('room type 2+ days out shows the no-rooms-free empty state', (tester) async {
    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      theme: buildSmartLibTheme(), home: const BookingFlowScreen(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rooms'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dateChip-2')));
    await tester.pumpAndSettle();
    expect(find.text('No rooms free on this date'), findsOneWidget);
  });
}
