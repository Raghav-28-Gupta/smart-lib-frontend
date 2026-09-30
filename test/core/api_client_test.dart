// test/core/api_client_test.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import '../support/fake_token_store.dart';
import '../support/fixtures.dart';
import '../support/stub_http_adapter.dart';

void main() {
  late TokenStore tokens;
  setUp(() => tokens = TokenStore(InMemoryTokenPersistence()));

  /// A real client -- real interceptors -- with the network replaced.
  (Dio, StubHttpAdapter) client(FutureOr<StubResponse> Function(RequestOptions) respond) {
    final dio = buildApiClient(tokens);
    final stub = StubHttpAdapter(respond);
    dio.httpClientAdapter = stub;
    return (dio, stub);
  }

  Future<ApiException> failure(Dio dio, String path) async {
    try {
      await guardApi(() => dio.get<Object?>(path));
    } on ApiException catch (e) {
      return e;
    }
    fail('expected $path to throw an ApiException');
  }

  group('auth header', () {
    test('attaches the Bearer token when one is held', () async {
      await tokens.save('jwt-123');
      final (dio, stub) = client((_) => const StubResponse(200, {'ok': true}));
      await dio.get<Object?>('/loans/me');
      expect(stub.requests.single.headers['Authorization'], 'Bearer jwt-123');
    });

    test('sends no Authorization header when logged out', () async {
      final (dio, stub) = client((_) => const StubResponse(200, <Object>[]));
      await dio.get<Object?>('/books/search');
      expect(stub.requests.single.headers.containsKey('Authorization'), false);
    });
  });

  group('401', () {
    test('clears the token when the server rejects it', () async {
      await tokens.save('expired-jwt');
      final (dio, _) = client((_) => StubResponse(401, fixture('error_401')));
      final e = await failure(dio, '/loans/me');
      expect(e, isA<UnauthorizedException>());
      expect(tokens.token, isNull);
    });

    test('does not notify when there was no token to clear', () async {
      // A wrong-password login is a 401 too; it must not look like a logout.
      var notifications = 0;
      tokens.addListener(() => notifications++);
      final (dio, _) = client((_) => StubResponse(401, fixture('error_401')));
      await failure(dio, '/auth/login');
      expect(notifications, 0);
    });

    test('does not clear a newer token than the one that was rejected', () async {
      // A slow request from an old session fails after the user has already
      // logged in again -- it must not wipe out the fresh login.
      await tokens.save('old-jwt');
      final (dio, _) = client((_) async {
        await tokens.save('new-jwt');
        return StubResponse(401, fixture('error_401'));
      });
      await failure(dio, '/loans/me');
      expect(tokens.token, 'new-jwt');
    });
  });

  group('error mapping', () {
    test('surfaces the server\'s message on a 409', () async {
      final (dio, _) = client((_) => StubResponse(409, fixture('error_409')));
      final e = await failure(dio, '/loans');
      expect(e, isA<ConflictException>());
      expect(e.statusCode, 409);
      expect(e.message, 'You already have this book borrowed.');
    });

    test('keeps a 409\'s details, where booking alternatives live', () async {
      final (dio, _) = client((_) => StubResponse(409, fixture('booking_conflict_409')));
      final e = await failure(dio, '/bookings');
      expect((e.details! as Map)['alternatives'], hasLength(2));
    });

    test('maps a 404 with its message', () async {
      final (dio, _) = client((_) => StubResponse(404, fixture('error_404')));
      final e = await failure(dio, '/books/does-not-exist');
      expect(e.statusCode, 404);
      expect(e.message, 'Book not found');
    });

    test('maps a 400 with the validation details', () async {
      final (dio, _) = client((_) => StubResponse(400, fixture('error_400')));
      final e = await failure(dio, '/bookings');
      expect(e.statusCode, 400);
      expect((e.details! as Map)['fieldErrors'], contains('resourceId'));
    });

    test('falls back to a generic message when the body is not the API\'s shape', () async {
      // Express's own 404 for an unknown route is an HTML page.
      final (dio, _) = client((_) => const StubResponse(404, '<pre>Cannot GET /nope</pre>'));
      final e = await failure(dio, '/nope');
      expect(e.statusCode, 404);
      expect(e.message, 'Something went wrong. Please try again.');
    });

    test('turns an unreachable server into a friendly network error', () async {
      final (dio, _) = client((options) => throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection refused',
          ));
      final e = await failure(dio, '/books/search');
      expect(e.isNetworkError, true);
      expect(e.message, "Can't reach the library server. Check your connection and try again.");
    });

    test('treats a timeout as a network error', () async {
      final (dio, _) = client((options) => throw DioException.receiveTimeout(
            requestOptions: options,
            timeout: const Duration(seconds: 5),
          ));
      final e = await failure(dio, '/books/search');
      expect(e.isNetworkError, true);
    });
  });

  test('guardApi passes a successful response straight through', () async {
    final (dio, _) = client((_) => const StubResponse(200, {'status': 'ok'}));
    final res = await guardApi(() => dio.get<Map<String, dynamic>>('/health'));
    expect(res.data!['status'], 'ok');
  });
}
