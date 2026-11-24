// test/features/notices/http_notice_repository_test.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/notices/notice_repository.dart';
import 'package:smartlib_frontend/models/notice.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/stub_http_adapter.dart';

void main() {
  (HttpNoticeRepository, StubHttpAdapter) repo(FutureOr<StubResponse> Function(RequestOptions) respond) {
    final dio = buildApiClient(TokenStore(InMemoryTokenPersistence()));
    final stub = StubHttpAdapter(respond);
    dio.httpClientAdapter = stub;
    return (HttpNoticeRepository(dio), stub);
  }

  test('GET /notices/me parses the list', () async {
    final (notices, stub) = repo((_) => StubResponse(200, fixture('notices_me')));
    final list = await notices.myNotices();
    expect(stub.requests.single.method, 'GET');
    expect(stub.requests.single.path, '/notices/me');
    expect(list, isNotEmpty);
    expect(list.map((n) => n.kind), contains(NoticeKind.overdueReminder));
    expect(list.first.title, isNotEmpty);
  });

  test('an empty list parses to an empty list', () async {
    final (notices, _) = repo((_) => const StubResponse(200, []));
    expect(await notices.myNotices(), isEmpty);
  });

  test('401 maps to UnauthorizedException', () async {
    final (notices, _) = repo((_) => StubResponse(401, fixture('error_401')));
    await expectLater(notices.myNotices(), throwsA(isA<UnauthorizedException>()));
  });

  test('a network failure maps to an ApiException with status 0', () async {
    final (notices, _) = repo((o) => throw DioException.connectionError(requestOptions: o, reason: 'offline'));
    await expectLater(notices.myNotices(), throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 0)));
  });
}
