// lib/features/profile/profile_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/profile_reliability.dart';
import '../auth/auth_controller.dart';

abstract class ProfileRepository {
  Future<ProfileReliability> reliabilityFor(String userId);
}

class MockProfileRepository implements ProfileRepository {
  @override
  Future<ProfileReliability> reliabilityFor(String userId) async {
    if (userId == 'u1') {
      return const ProfileReliability(
        tier: 'Building back up',
        ringFraction: 0.5,
        note: 'You missed a booking on Aug 14 (Group Room 201). Complete 1 more on-time booking to return to Great standing.',
        history: [ActivityDot.ok, ActivityDot.ok, ActivityDot.miss, ActivityDot.ok],
      );
    }
    return const ProfileReliability(
      tier: 'Good standing',
      ringFraction: 1.0,
      note: 'No missed bookings yet. Reliability reflects your booking history over time, and can lightly affect priority access to high-demand resources during busy periods.',
      history: [],
    );
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => MockProfileRepository());

final profileProvider = FutureProvider.autoDispose<ProfileReliability>((ref) async {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) throw StateError('No logged-in user');
  return ref.watch(profileRepositoryProvider).reliabilityFor(user.id);
});
