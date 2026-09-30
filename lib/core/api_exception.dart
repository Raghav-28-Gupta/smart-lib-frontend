// lib/core/api_exception.dart
//
// Every failed API call surfaces as an ApiException carrying a message fit to
// show the user. The backend already writes those: every error it sends is
// `{error: string, details?: unknown}` (backend/src/middleware/errorHandler.ts),
// so the mapping mostly just lifts `error` out.
import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.details});

  /// The HTTP status, or 0 when no response arrived at all.
  final int statusCode;

  /// Safe to show the user as-is.
  final String message;

  /// The response's `details`, when present -- validation field errors on a
  /// 400, booking alternatives on a POST /bookings 409.
  final Object? details;

  bool get isNetworkError => statusCode == 0;

  static const networkMessage = "Can't reach the library server. Check your connection and try again.";
  static const genericMessage = 'Something went wrong. Please try again.';

  factory ApiException.fromDioException(DioException e) {
    final response = e.response;
    if (response == null) {
      final unreachable = switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.connectionError =>
          true,
        _ => false,
      };
      return ApiException(0, unreachable ? networkMessage : genericMessage);
    }

    final status = response.statusCode ?? 0;
    final body = response.data;
    // Anything not in the API's shape -- Express's own HTML 404 for an
    // unknown route, say -- gets a generic message rather than raw markup.
    final message = body is Map && body['error'] is String ? body['error'] as String : genericMessage;
    final details = body is Map ? body['details'] : null;

    return switch (status) {
      401 => UnauthorizedException(message),
      409 => ConflictException(message, details: details),
      _ => ApiException(status, message, details: details),
    };
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The token is missing, expired, or the credentials didn't match.
class UnauthorizedException extends ApiException {
  const UnauthorizedException(String message) : super(401, message);
}

/// The request clashed with current state -- already borrowed, slot taken,
/// renewal blocked by a waitlist.
class ConflictException extends ApiException {
  const ConflictException(String message, {super.details}) : super(409, message);
}
