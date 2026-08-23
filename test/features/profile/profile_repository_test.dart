// test/features/profile/profile_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/profile/profile_repository.dart';

void main() {
  test('the seeded demo account (u1) is Building back up', () async {
    final repo = MockProfileRepository();
    final p = await repo.reliabilityFor('u1');
    expect(p.tier, 'Building back up');
    expect(p.ringFraction, 0.5);
    expect(p.history.length, 4);
  });

  test('any other user id gets a fresh Good standing profile', () async {
    final repo = MockProfileRepository();
    final p = await repo.reliabilityFor('u-new-123');
    expect(p.tier, 'Good standing');
    expect(p.ringFraction, 1.0);
    expect(p.history, isEmpty);
  });
}
