// test/models/borrow_request_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/models/borrow_request.dart';
import '../support/fixtures.dart';

void main() {
  test('parses a new request: pending, with its 24-hour deadline in local time', () {
    final r = BorrowRequest.fromJson(fixture('borrow_request_created') as Map<String, dynamic>);
    expect(r.bookId, 'b12');
    expect(r.bookTitle, 'Atomic Habits');
    expect(r.status, BorrowRequestStatus.pending);
    expect(r.decidedAt, isNull);
    expect(r.declineReason, isNull);
    expect(r.expiresAt.isUtc, false);
    expect(r.expiresAt.difference(r.requestedAt), const Duration(hours: 24));
  });

  test("parses the student's list: the pending request and the declined one with its reason", () {
    final list = (fixture('borrow_requests_me') as List)
        .map((j) => BorrowRequest.fromJson(j as Map<String, dynamic>))
        .toList();
    expect(list.singleWhere((r) => r.bookId == 'b12').status, BorrowRequestStatus.pending);
    final declined = list.singleWhere((r) => r.bookId == 'b5');
    expect(declined.status, BorrowRequestStatus.declined);
    expect(declined.declineReason, 'This copy is set aside for a course reserve.');
    expect(declined.decidedAt, isNotNull);
  });

  test('parses an expired request (derived from the pending one: the server needs 24 hours to make one)', () {
    final raw = {
      ...fixture('borrow_request_created') as Map<String, dynamic>,
      'status': 'expired',
      'decidedAt': '2026-10-21T09:00:00.000Z',
    };
    final r = BorrowRequest.fromJson(raw);
    expect(r.status, BorrowRequestStatus.expired);
    expect(r.decidedAt!.isUtc, false);
  });

  test("a status this version doesn't know falls back to unknown instead of failing the list", () {
    final raw = {...fixture('borrow_request_created') as Map<String, dynamic>, 'status': 'escalated'};
    expect(BorrowRequest.fromJson(raw).status, BorrowRequestStatus.unknown);
  });
}
