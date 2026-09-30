import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_exception.dart';
import 'auth/token_store.dart';

/// Base URL of the Node backend — the only service the client ever talks to.
///
/// An Android emulator can't see the host's `localhost`; 10.0.2.2 is the alias
/// that routes back to it. Override at build time for a real device or a
/// deployed backend:
///
///   flutter run --dart-define=SMARTLIB_API_BASE_URL=http://192.168.1.20:3000
String resolveBaseUrl() {
  const override = String.fromEnvironment('SMARTLIB_API_BASE_URL');
  if (override.isNotEmpty) return override;

  // defaultTargetPlatform rather than dart:io's Platform — dart:io doesn't
  // exist on web, and importing it breaks the web build outright.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:3000';
  }
  return 'http://localhost:3000';
}

/// Attaches the Bearer token to every request, and drops the token when the
/// server rejects it -- the TokenStore's listeners turn that into a logout.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokens);

  final TokenStore _tokens;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokens.token;
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      final sent = err.requestOptions.headers['Authorization'];
      // Clear only the token that was actually rejected. A slow request from
      // an old session can fail after the user has logged in again, and must
      // not wipe out the fresh login. No token sent (a wrong-password login)
      // means nothing to clear.
      if (sent != null && sent == 'Bearer ${_tokens.token}') {
        unawaited(_tokens.clear());
      }
    }
    handler.next(err);
  }
}

/// The app's one HTTP client. Separate from the provider so tests can build
/// a real one -- real interceptors -- and swap only the network layer.
Dio buildApiClient(TokenStore tokens) {
  return Dio(
    BaseOptions(
      baseUrl: resolveBaseUrl(),
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  )..interceptors.add(AuthInterceptor(tokens));
}

// Watches the TokenStore *instance*, which never changes -- so Dio is built
// once and never torn down mid-request when the user logs in or out.
final apiClientProvider = Provider<Dio>((ref) => buildApiClient(ref.watch(tokenStoreProvider)));

/// Awaits an API request, surfacing any failure as an [ApiException] with a
/// message fit to show the user -- so repositories deal in one error type.
///
/// Mapping lives here rather than in an interceptor because Dio re-wraps
/// anything an interceptor rejects as a DioException, which would leave every
/// caller unwrapping it anyway.
Future<T> guardApi<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on DioException catch (e) {
    throw ApiException.fromDioException(e);
  }
}

/// Phase 1 wiring proof: client -> Node backend.
final healthCheckProvider = FutureProvider<String>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get<Map<String, dynamic>>('/health');
  return response.data!['status'] as String;
});

/// Phase 1 wiring proof: client -> Node backend -> FastAPI service.
final aiHealthCheckProvider = FutureProvider<String>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get<Map<String, dynamic>>('/health/ai');
  return response.data!['status'] as String;
});
