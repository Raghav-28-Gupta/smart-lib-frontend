// test/features/auth/http_auth_repository_test.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/auth/auth_repository.dart';
import 'package:smartlib_frontend/models/app_user.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/stub_http_adapter.dart';

void main() {
  late TokenStore tokens;
  setUp(() => tokens = TokenStore(InMemoryTokenPersistence()));

  (HttpAuthRepository, StubHttpAdapter) repo(FutureOr<StubResponse> Function(RequestOptions) respond) {
    final dio = buildApiClient(tokens);
    final stub = StubHttpAdapter(respond);
    dio.httpClientAdapter = stub;
    return (HttpAuthRepository(dio, tokens), stub);
  }

  Future<String> authError(Future<Object?> Function() call) async {
    try {
      await call();
    } on AuthException catch (e) {
      return e.message;
    }
    fail('expected an AuthException');
  }

  group('login', () {
    test('posts the credentials, keeps the token, and returns the user', () async {
      final (auth, stub) = repo((_) => StubResponse(200, fixture('auth_login')));
      final user = await auth.login('aditi.sharma@thapar.edu', 'password123');

      expect(stub.requests.single.path, '/auth/login');
      expect(stub.requests.single.data, {'email': 'aditi.sharma@thapar.edu', 'password': 'password123'});
      expect(user.id, 'u1');
      expect(user.role, UserRole.student);
      expect(tokens.token, '<redacted-jwt>');
    });

    test('shows the server\'s mismatch message on a 401', () async {
      final (auth, _) = repo((_) => const StubResponse(401, {'error': "That email and password don't match our records."}));
      expect(await authError(() => auth.login('a@thapar.edu', 'wrong')), "That email and password don't match our records.");
      expect(tokens.token, isNull);
    });

    test('shows the network message when the server is unreachable', () async {
      final (auth, _) = repo((o) => throw DioException.connectionError(requestOptions: o, reason: 'refused'));
      expect(await authError(() => auth.login('a@thapar.edu', 'pw')), ApiException.networkMessage);
    });
  });

  group('register', () {
    test('keeps the token and returns the new user', () async {
      final (auth, stub) = repo((_) => StubResponse(201, fixture('auth_login')));
      final user = await auth.register('Aditi Sharma', 'aditi.sharma@thapar.edu', 'password123');
      expect(stub.requests.single.path, '/auth/register');
      expect(user.name, 'Aditi Sharma');
      expect(tokens.token, '<redacted-jwt>');
    });

    test('says plainly when the email is taken', () async {
      // The only way register can conflict, so the copy doesn't depend on
      // whatever the database error happened to say.
      final (auth, _) = repo((_) => const StubResponse(409, {'error': 'A record with that field already exists.'}));
      expect(await authError(() => auth.register('A', 'taken@thapar.edu', 'password123')),
          'An account with that email already exists.');
    });

    test('shows the backend\'s field message on a 400, not "Invalid request body"', () async {
      final (auth, _) = repo((_) => const StubResponse(400, {
            'error': 'Invalid request body',
            'details': {
              'formErrors': <String>[],
              'fieldErrors': {
                'password': ['Password must be at least 8 characters'],
              },
            },
          }));
      expect(await authError(() => auth.register('A', 'a@thapar.edu', 'short')), 'Password must be at least 8 characters');
    });
  });

  group('me', () {
    test('fetches the current user with the saved token', () async {
      await tokens.save('saved-jwt');
      final (auth, stub) = repo((_) => StubResponse(200, fixture('auth_me')));
      final user = await auth.me();
      expect(stub.requests.single.path, '/auth/me');
      expect(stub.requests.single.headers['Authorization'], 'Bearer saved-jwt');
      expect(user.email, 'aditi.sharma@thapar.edu');
    });

    test('lets a rejected token surface as UnauthorizedException', () async {
      // The controller decides what a 401 here means, so it isn't flattened
      // into an AuthException.
      await tokens.save('expired-jwt');
      final (auth, _) = repo((_) => StubResponse(401, fixture('error_401')));
      await expectLater(auth.me(), throwsA(isA<UnauthorizedException>()));
    });
  });
}
