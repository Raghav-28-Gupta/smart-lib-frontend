// test/models/profile_reliability_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/models/profile_reliability.dart';
import '../support/fixtures.dart';

void main() {
  test('parses GET /profile/reliability, including both history dot kinds', () {
    final r = ProfileReliability.fromJson(fixture('profile_reliability') as Map<String, dynamic>);
    expect(r.tier, 'Building back up');
    expect(r.ringFraction, 0.52);
    expect(r.note, startsWith('Your reliability score recently dropped'));
    expect(r.history, [ActivityDot.miss, ActivityDot.ok]);
  });

  test('reads a whole-number ringFraction', () {
    // A user at score 100 gets ringFraction `1` -- a JSON integer. The
    // fixture's 0.52 would never exercise this.
    final r = ProfileReliability.fromJson(const {
      'score': 100,
      'tier': 'Good standing',
      'ringFraction': 1,
      'note': 'No missed bookings yet.',
      'history': <String>[],
    });
    expect(r.ringFraction, 1.0);
    expect(r.history, isEmpty);
  });
}
