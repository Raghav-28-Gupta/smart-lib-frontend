// test/features/loans/http_loan_repository_test.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/models/loan.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/stub_http_adapter.dart';

void main() {
  (HttpLoanRepository, StubHttpAdapter) repo(FutureOr<StubResponse> Function(RequestOptions) respond) {
    final dio = buildApiClient(TokenStore(InMemoryTokenPersistence()));
    final stub = StubHttpAdapter(respond);
    dio.httpClientAdapter = stub;
    return (HttpLoanRepository(dio), stub);
  }

  test('activeLoans fetches and parses the user\'s loans', () async {
    final (loans, stub) = repo((_) => StubResponse(200, fixture('loans_me')));
    final result = await loans.activeLoans();
    expect(stub.requests.single.path, '/loans/me');
    expect(result, hasLength(4));
    expect(result.singleWhere((l) => l.bookId == 'b4').status, LoanStatus.overdue);
  });

  test('createLoan borrows the book and returns the new loan', () async {
    final (loans, stub) = repo((_) => StubResponse(201, fixture('loan_created')));
    final loan = await loans.createLoan('b12');
    expect(stub.requests.single.method, 'POST');
    expect(stub.requests.single.path, '/loans');
    expect(stub.requests.single.data, {'bookId': 'b12'});
    expect(loan.bookId, 'b12');
  });

  test('renew posts to the loan and returns it as the server sent it', () async {
    final (loans, stub) = repo((_) => StubResponse(200, fixture('loan_renewed')));
    final loan = await loans.renew('loan-1');
    expect(stub.requests.single.method, 'POST');
    expect(stub.requests.single.path, '/loans/loan-1/renew');
    // Plain data mapping -- the "Renewed" flash is the controller's business.
    expect(loan.justRenewed, false);
  });

  test('returnLoan posts the return', () async {
    final (loans, stub) = repo((_) => StubResponse(200, fixture('loan_renewed')));
    await loans.returnLoan('loan-1');
    expect(stub.requests.single.method, 'POST');
    expect(stub.requests.single.path, '/loans/loan-1/return');
  });

  test('a refused renewal carries the server\'s reason', () async {
    final (loans, _) = repo((_) => const StubResponse(409, {'error': '1 student is waiting for this title.'}));
    await expectLater(
      loans.renew('loan-4'),
      throwsA(isA<ConflictException>().having((e) => e.message, 'message', '1 student is waiting for this title.')),
    );
  });
}
