// lib/features/profile/profile_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../models/profile_reliability.dart';
import '../auth/auth_controller.dart';

abstract class ProfileRepository {
  /// The logged-in user's reliability. No user id: the server reads it from
  /// the token, so one user can't ask for another's.
  Future<ProfileReliability> reliability();
}

class HttpProfileRepository implements ProfileRepository {
  HttpProfileRepository(this._dio);

  final Dio _dio;

  @override
  Future<ProfileReliability> reliability() async {
    final res = await guardApi(() => _dio.get<Map<String, dynamic>>('/profile/reliability'));
    return ProfileReliability.fromJson(res.data!);
  }
}

/// Test double. Defaults to the seeded demo account; [newUser] gives a fresh
/// account in Good standing instead.
class MockProfileRepository implements ProfileRepository {
  MockProfileRepository({this.newUser = false});

  final bool newUser;

  @override
  Future<ProfileReliability> reliability() async {
    if (!newUser) {
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

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => HttpProfileRepository(ref.watch(apiClientProvider)));

final profileProvider = FutureProvider.autoDispose<ProfileReliability>((ref) async {
  // Keyed on who is logged in, so a different user never sees this one's
  // score. Only the id is watched: other auth changes needn't refetch.
  final userId = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (userId == null) throw StateError('No logged-in user');
  return ref.watch(profileRepositoryProvider).reliability();
});
