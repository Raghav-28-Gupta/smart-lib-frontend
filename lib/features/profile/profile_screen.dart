// lib/features/profile/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ui/ui_controller.dart';
import '../../models/profile_reliability.dart';
import '../../widgets/error_state.dart';
import '../../widgets/reliability_ring.dart';
import '../auth/auth_controller.dart';
import 'profile_repository.dart';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(
          title: "Couldn't load your profile",
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (p) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              CircleAvatar(
                radius: 28,
                child: Text(_initials(auth.user?.name ?? '')),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.user?.name ?? '',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text('${auth.user?.roll ?? ''} · ${auth.user?.email ?? ''}'),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  ReliabilityRing(
                    fraction: p.ringFraction,
                    centerLabel: p.tier,
                  ),
                  const SizedBox(height: 10),
                  Text(p.note, textAlign: TextAlign.center),
                  if (p.history.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final h in p.history)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: h == ActivityDot.ok
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                      ],
                    ),
                    const Text('Recent activity', style: TextStyle(fontSize: 11)),
                  ],
                  TextButton(
                    onPressed: () => ref
                        .read(uiControllerProvider.notifier)
                        .showReliabilityInfo(),
                    child: const Text('How reliability works'),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logOut(),
              child: const Text('Log out'),
            ),
          ],
        ),
      ),
    );
  }
}
