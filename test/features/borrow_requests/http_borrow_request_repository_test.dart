// test/features/borrow_requests/http_borrow_request_repository_test.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/borrow_requests/borrow_request_repository.dart';
import 'package:smartlib_frontend/models/borrow_request.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/stub_http_adapter.dart';

void main() {
  (HttpBorrowRequestRepository, StubHttpAdapter) repo(FutureOr<StubResponse> Function(RequestOptions) respond) {
    final dio = buildApiClient(TokenStore(InMemoryTokenPersistence()));
    final stub = StubHttpAdapter(respond);
    dio.httpClientAdapter = stub;
    return (HttpBorrowRequestRepository(dio), stub);
  }

  test("mine fetches the student's requests", () async {
    final (requests, stub) = repo((_) => StubResponse(200, fixture('borrow_requests_me')));
    final list = await requests.mine();
    expect(stub.requests.single.path, '/borrow-requests/me');
    expect(list.map((r) => r.bookId), containsAll(['b12', 'b5']));
  });

  test('create posts the book and returns the pending request', () async {
    final (requests, stub) = repo((_) => StubResponse(201, fixture('borrow_request_created')));
    final r = await requests.create('b12');
    expect(stub.requests.single.method, 'POST');
    expect(stub.requests.single.path, '/borrow-requests');
    expect(stub.requests.single.data, {'bookId': 'b12'});
    expect(r.status, BorrowRequestStatus.pending);
  });

  test('cancel posts the withdrawal', () async {
    final (requests, stub) = repo((_) => StubResponse(200, fixture('borrow_request_created')));
    await requests.cancel('br-1');
    expect(stub.requests.single.method, 'POST');
    expect(stub.requests.single.path, '/borrow-requests/br-1/cancel');
  });

  test("a refused request carries the server's reason", () async {
    final (requests, _) = repo((_) => const StubResponse(409, {'error': "You've already requested this book."}));
    await expectLater(
      requests.create('b12'),
      throwsA(isA<ConflictException>().having((e) => e.message, 'message', "You've already requested this book.")),
    );
  });
}
