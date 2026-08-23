import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/features/health/health_check_screen.dart';

void main() {
  testWidgets('health screen renders both backend statuses', (tester) async {
    // The providers are overridden so this test covers the widget wiring only —
    // it doesn't need either backend running.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthCheckProvider.overrideWith((ref) => 'ok'),
          aiHealthCheckProvider.overrideWith((ref) => 'ok'),
        ],
        child: const MaterialApp(home: HealthCheckScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backend status: ok'), findsOneWidget);
    expect(find.text('AI backend status: ok'), findsOneWidget);
  });

  testWidgets('health screen surfaces a failed backend call', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthCheckProvider.overrideWith((ref) => Future<String>.error('down')),
          aiHealthCheckProvider.overrideWith((ref) => 'ok'),
        ],
        child: const MaterialApp(home: HealthCheckScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Backend status error'), findsOneWidget);
    expect(find.text('AI backend status: ok'), findsOneWidget);
  });
}
