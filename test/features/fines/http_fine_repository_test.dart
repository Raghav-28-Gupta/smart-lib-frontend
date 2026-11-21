// test/features/fines/http_fine_repository_test.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/fines/fine_repository.dart';
import 'package:smartlib_frontend/models/fine.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/stub_http_adapter.dart';

void main() {
  (HttpFineRepository, StubHttpAdapter) repo(FutureOr<StubResponse> Function(RequestOptions) respond) {
    final dio = buildApiClient(TokenStore(InMemoryTokenPersistence()));
    final stub = StubHttpAdapter(respond);
    dio.httpClientAdapter = stub;
    return (HttpFineRepository(dio), stub);
  }

  test('GET /fines/me parses the summary', () async {
    final (fines, stub) = repo((_) => StubResponse(200, fixture('fines_me_adjusted')));
    final summary = await fines.myFines();
    expect(stub.requests.single.method, 'GET');
    expect(stub.requests.single.path, '/fines/me');
    final fine = summary.fines.singleWhere((f) => f.reason == FineReason.overdue);
    expect(fine.status, FineStatus.adjusted);
    expect(fine.amount, 20.0);
    expect(fine.originalAmount, 30.0);
    expect(summary.outstandingTotal, 20.0);
  });

  test('401 maps to UnauthorizedException', () async {
    final (fines, _) = repo((_) => StubResponse(401, fixture('error_401')));
    await expectLater(fines.myFines(), throwsA(isA<UnauthorizedException>()));
  });

  test('a network failure maps to an ApiException with status 0', () async {
    final (fines, _) = repo((o) => throw DioException.connectionError(requestOptions: o, reason: 'offline'));
    await expectLater(fines.myFines(), throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 0)));
  });
}
