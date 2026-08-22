import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Phase 1's only screen. It exists to prove the wiring end to end:
/// client -> Node backend, and client -> Node backend -> FastAPI service.
class HealthCheckScreen extends ConsumerWidget {
  const HealthCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthCheckProvider);
    final aiHealth = ref.watch(aiHealthCheckProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('SmartLib')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StatusLine(label: 'Backend status', value: health),
            const SizedBox(height: 12),
            _StatusLine(label: 'AI backend status', value: aiHealth),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                ref.invalidate(healthCheckProvider);
                ref.invalidate(aiHealthCheckProvider);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final AsyncValue<String> value;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (status) => Text('$label: $status'),
      loading: () => const CircularProgressIndicator(),
      error: (err, _) => Text('$label error: $err', textAlign: TextAlign.center),
    );
  }
}
