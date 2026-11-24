// test/models/fine_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/models/fine.dart';
import '../support/fixtures.dart';

void main() {
  FinesSummary summary(String name) => FinesSummary.fromJson(fixture(name) as Map<String, dynamic>);

  // The overdue fine the capture writes by returning Aditi's overdue loan.
  Fine overdue(String name) => summary(name).fines.singleWhere((f) => f.reason == FineReason.overdue);

  // The captured outstanding fine as raw JSON, to edit a copy for the values
  // the capture doesn't produce.
  Map<String, dynamic> rawFine() =>
      ((fixture('fines_me') as Map<String, dynamic>)['fines'] as List).cast<Map<String, dynamic>>().first;

  test('parses an outstanding fine', () {
    final s = summary('fines_me');
    final fine = overdue('fines_me');
    expect(fine.status, FineStatus.outstanding);
    expect(fine.amount, 30.0);
    expect(fine.originalAmount, 30.0);
    expect(fine.wasAdjusted, false);
    expect(fine.item, isNotEmpty);
    expect(fine.note, isNull);
    expect(s.outstandingTotal, 30.0);
  });

  test('parses the adjusted fine with its note and original amount', () {
    final s = summary('fines_me_adjusted');
    final fine = overdue('fines_me_adjusted');
    expect(fine.status, FineStatus.adjusted);
    expect(fine.amount, 20.0);
    expect(fine.originalAmount, 30.0);
    expect(fine.wasAdjusted, true);
    expect(fine.note, 'Returned during exam week');
    // An adjusted fine is still owed, at its new amount.
    expect(s.outstandingTotal, 20.0);
  });

  test('parses paid', () {
    final s = summary('fines_me_paid');
    final fine = overdue('fines_me_paid');
    expect(fine.status, FineStatus.paid);
    expect(fine.amount, 20.0);
    // The note and the original amount outlive the payment.
    expect(fine.originalAmount, 30.0);
    expect(fine.note, 'Returned during exam week');
    expect(s.outstandingTotal, 0.0);
  });

  test('reads amounts sent as JSON integers', () {
    // The wire value is `30`, not `30.0` -- a hand-written `as double` throws.
    final raw = fixture('fines_me') as Map<String, dynamic>;
    expect(rawFine()['amount'], isA<int>());
    expect(raw['outstandingTotal'], isA<int>());
    expect(overdue('fines_me').amount, isA<double>());
    expect(summary('fines_me').outstandingTotal, isA<double>());
  });

  test('maps date to a local time at the same instant', () {
    final raw = rawFine();
    final fine = Fine.fromJson(raw);
    expect(fine.date.isUtc, false);
    expect(fine.date.isAtSameMomentAs(DateTime.parse(raw['date'] as String)), true);
  });

  test('an unknown status maps to unknown', () {
    expect(Fine.fromJson({...rawFine(), 'status': 'disputed'}).status, FineStatus.unknown);
  });

  test('no_show maps to noShow and lost to lost', () {
    expect(Fine.fromJson({...rawFine(), 'reason': 'no_show'}).reason, FineReason.noShow);
    expect(Fine.fromJson({...rawFine(), 'reason': 'lost'}).reason, FineReason.lost);
    expect(Fine.fromJson(rawFine()).reason, FineReason.overdue);
    // A reason a later version adds doesn't fail the list either.
    expect(Fine.fromJson({...rawFine(), 'reason': 'damaged'}).reason, FineReason.unknown);
  });

  test('waived and a null note parse', () {
    final waived = Fine.fromJson({...rawFine(), 'status': 'waived', 'amount': 0, 'originalAmount': 30, 'note': 'Medical leave'});
    expect(waived.status, FineStatus.waived);
    expect(waived.wasAdjusted, true);
    expect(waived.note, 'Medical leave');
    expect(Fine.fromJson({...rawFine(), 'note': null}).note, isNull);
  });

  group('a dispute on the fine', () {
    test('parses an open dispute', () {
      // The fine the student disputed: still outstanding, with its dispute open and
      // no library answer yet.
      final fine = overdue('fines_me_disputed');
      expect(fine.status, FineStatus.outstanding);
      expect(fine.amount, 30.0);
      expect(fine.dispute, isNotNull);
      expect(fine.dispute!.status, DisputeStatus.open);
      expect(fine.dispute!.note, isNull);
    });

    test('parses a fine with a closed dispute', () {
      // The librarian lowered the disputed fine (naming the dispute), which closed it:
      // the dispute stays on the fine, with the adjustment's reason as its note.
      final fine = overdue('fines_me_adjusted');
      expect(fine.status, FineStatus.adjusted);
      expect(fine.dispute, isNotNull);
      expect(fine.dispute!.status, DisputeStatus.adjusted);
      expect(fine.dispute!.note, 'Returned during exam week');
      // The closed dispute outlives the payment.
      expect(overdue('fines_me_paid').dispute!.status, DisputeStatus.adjusted);
    });

    test('a fine without the key has no dispute', () {
      // The server sends `dispute: null` for a fine nobody disputed...
      expect(rawFine().containsKey('dispute'), true);
      expect(overdue('fines_me').dispute, isNull);
      // ...and an older server leaves the key out altogether.
      final withoutKey = rawFine()..remove('dispute');
      expect(Fine.fromJson(withoutKey).dispute, isNull);
    });

    test('an unknown dispute status maps to unknown', () {
      final fine = Fine.fromJson({
        ...rawFine(),
        'dispute': {'status': 'escalated', 'note': 'A later version of the library.'},
      });
      expect(fine.dispute, isNotNull);
      expect(fine.dispute!.status, DisputeStatus.unknown);
      expect(fine.dispute!.note, 'A later version of the library.');
    });

    test('every status the server sends maps to its own value', () {
      DisputeStatus statusOf(String wire) => Fine.fromJson({
            ...rawFine(),
            'dispute': {'status': wire, 'note': null},
          }).dispute!.status;
      expect(statusOf('open'), DisputeStatus.open);
      expect(statusOf('waived'), DisputeStatus.waived);
      expect(statusOf('adjusted'), DisputeStatus.adjusted);
      expect(statusOf('upheld'), DisputeStatus.upheld);
    });
  });
}
