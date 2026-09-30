// test/support/stub_http_adapter.dart
//
// Replaces Dio's network layer in tests. Hand-rolled rather than adding
// http_mock_adapter: this is all the API tests need.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

class StubResponse {
  const StubResponse(this.status, [this.body]);
  final int status;

  /// Encoded as JSON unless it's already a String (e.g. an HTML error page).
  final Object? body;
}

class StubHttpAdapter implements HttpClientAdapter {
  /// [respond] may also throw a DioException to simulate a network failure.
  StubHttpAdapter(this.respond);

  final FutureOr<StubResponse> Function(RequestOptions options) respond;

  /// Every request that reached the "network", in order.
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final r = await respond(options);
    final isText = r.body is String;
    return ResponseBody.fromString(
      isText ? r.body! as String : jsonEncode(r.body),
      r.status,
      headers: {
        Headers.contentTypeHeader: [isText ? 'text/html' : Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
