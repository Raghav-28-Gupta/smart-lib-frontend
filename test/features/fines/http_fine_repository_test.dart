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

  test("GET /fines/me carries each fine's dispute", () async {
    final (fines, _) = repo((_) => StubResponse(200, fixture('fines_me_disputed')));
    final summary = await fines.myFines();
    final fine = summary.fines.singleWhere((f) => f.reason == FineReason.overdue);
    expect(fine.status, FineStatus.outstanding);
    expect(fine.dispute?.status, DisputeStatus.open);
  });

  test('POST /fines/:id/dispute sends the reason', () async {
    // The answer is `{ id, status: 'open' }`; the app reads the dispute back from the fines.
    final (fines, stub) = repo((_) => const StubResponse(201, {'id': 'd1', 'status': 'open'}));
    await fines.dispute('fine/1', 'The desk scanned my return a day late.');
    expect(stub.requests.single.method, 'POST');
    // The id is escaped into the path, like every other id the app sends.
    expect(stub.requests.single.path, '/fines/fine%2F1/dispute');
    expect(stub.requests.single.data, {'reason': 'The desk scanned my return a day late.'});
  });

  test("a 409 maps to ConflictException with the server's message", () async {
    for (final message in [
      "You've already disputed this fine.",
      "This fine can't be disputed because it is already paid or waived.",
    ]) {
      final (fines, _) = repo((_) => StubResponse(409, {'error': message}));
      await expectLater(
        fines.dispute('f1', 'It was returned on time.'),
        throwsA(isA<ConflictException>().having((e) => e.message, 'message', message)),
      );
    }
  });

  test("a 404 carries the server's message, and a network failure has status 0", () async {
    final (gone, _) = repo((_) => const StubResponse(404, {'error': 'Fine not found'}));
    await expectLater(
      gone.dispute('f1', 'It was returned on time.'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404).having((e) => e.message, 'message', 'Fine not found')),
    );
    final (offline, _) = repo((o) => throw DioException.connectionError(requestOptions: o, reason: 'offline'));
    await expectLater(
      offline.dispute('f1', 'It was returned on time.'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 0)),
    );
  });
}
