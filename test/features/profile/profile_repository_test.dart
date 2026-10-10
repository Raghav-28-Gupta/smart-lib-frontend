// test/features/profile/profile_repository_test.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/profile/profile_repository.dart';
import 'package:smartlib_frontend/models/profile_reliability.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/stub_http_adapter.dart';

void main() {
  group('HttpProfileRepository', () {
    (HttpProfileRepository, StubHttpAdapter) repo(FutureOr<StubResponse> Function(RequestOptions) respond) {
      final dio = buildApiClient(TokenStore(InMemoryTokenPersistence()));
      final stub = StubHttpAdapter(respond);
      dio.httpClientAdapter = stub;
      return (HttpProfileRepository(dio), stub);
    }

    test('fetches the logged-in user\'s reliability -- the server knows who from the token', () async {
      final (profile, stub) = repo((_) => StubResponse(200, fixture('profile_reliability')));
      final p = await profile.reliability();
      expect(stub.requests.single.path, '/profile/reliability');
      expect(p.tier, 'Building back up');
      expect(p.history, [ActivityDot.miss, ActivityDot.ok]);
    });

    test('lets a failure through so the screen can offer Retry', () async {
      final (profile, _) = repo((_) => StubResponse(401, fixture('error_401')));
      await expectLater(profile.reliability(), throwsA(isA<UnauthorizedException>()));
    });
  });

  group('MockProfileRepository', () {
    test('defaults to the seeded demo account, Building back up', () async {
      final p = await MockProfileRepository().reliability();
      expect(p.tier, 'Building back up');
      expect(p.ringFraction, 0.5);
      expect(p.history.length, 4);
    });

    test('can stand in for a brand-new account in Good standing', () async {
      final p = await MockProfileRepository(newUser: true).reliability();
      expect(p.tier, 'Good standing');
      expect(p.ringFraction, 1.0);
      expect(p.history, isEmpty);
    });
  });
}
