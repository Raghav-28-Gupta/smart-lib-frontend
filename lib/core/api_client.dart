import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final apiClientProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: resolveBaseUrl(),
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
});

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
