// test/models/loan_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/models/loan.dart';
import '../support/fixtures.dart';

void main() {
  List<Loan> loansMe() => (fixture('loans_me') as List)
      .map((j) => Loan.fromJson(j as Map<String, dynamic>))
      .toList();

  test('parses GET /loans/me, matching the seeded demo loans', () {
    final loans = loansMe();
    expect(loans, hasLength(4));

    final overdue = loans.singleWhere((l) => l.bookId == 'b4');
    expect(overdue.status, LoanStatus.overdue);
    expect(overdue.fineAmount, 30.0);
    expect(overdue.canRenew, true);

    final blocked = loans.singleWhere((l) => l.bookId == 'b8');
    expect(blocked.status, LoanStatus.normal);
    expect(blocked.canRenew, false);
    expect(blocked.blockedReason, '1 student is waiting for this title.');

    expect(loans.singleWhere((l) => l.bookId == 'b3').blockedReason, isNull);
  });

  test('reads fineAmount sent as a JSON integer', () {
    // The wire value is `30`, not `30.0` -- a hand-written `as double` throws.
    final raw = (fixture('loans_me') as List).cast<Map<String, dynamic>>();
    expect(raw.singleWhere((j) => j['bookId'] == 'b4')['fineAmount'], isA<int>());
    expect(loansMe().singleWhere((l) => l.bookId == 'b4').fineAmount, isA<double>());
  });

  test('maps dueAt to a local dueDate at the same instant', () {
    final raw = (fixture('loans_me') as List).first as Map<String, dynamic>;
    final loan = Loan.fromJson(raw);
    // Rendered as month/day, so a UTC value would show the wrong date near
    // midnight.
    expect(loan.dueDate.isUtc, false);
    // DateTime == also compares the zone, so a local and a UTC value at the
    // same moment are unequal -- compare instants explicitly.
    expect(loan.dueDate.isAtSameMomentAs(DateTime.parse(raw['dueAt'] as String)), true);
  });

  test('never sets justRenewed from the wire -- it is client-only UI state', () {
    final renewed = Loan.fromJson(fixture('loan_renewed') as Map<String, dynamic>);
    expect(renewed.justRenewed, false);
    expect(renewed.bookId, 'b1');
  });

  test('parses the loan returned by POST /loans', () {
    final created = Loan.fromJson(fixture('loan_created') as Map<String, dynamic>);
    expect(created.bookId, 'b12');
    expect(created.status, LoanStatus.normal);
    expect(created.fineAmount, 0.0);
  });
}
