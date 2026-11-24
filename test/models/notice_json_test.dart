// test/models/notice_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/models/notice.dart';
import '../support/fixtures.dart';

void main() {
  // The captured list holds the reminder the admin sent for the demo student's
  // overdue loan; as raw JSON, to edit a copy for the values the capture doesn't produce.
  List<Map<String, dynamic>> raw() => (fixture('notices_me') as List).cast<Map<String, dynamic>>();

  test('parses a notice from the fixture', () {
    final notices = raw().map(Notice.fromJson).toList();
    final reminder = notices.singleWhere((n) => n.kind == NoticeKind.overdueReminder);
    expect(reminder.id, isNotEmpty);
    expect(reminder.title, 'Overdue book reminder');
    expect(reminder.body, startsWith('Your copy of'));
    expect(reminder.body, contains('overdue'));
    // A local time at the same instant as the UTC stamp on the wire.
    final stamp = raw().firstWhere((n) => n['id'] == reminder.id)['createdAt'] as String;
    expect(reminder.createdAt.isUtc, false);
    expect(reminder.createdAt.isAtSameMomentAs(DateTime.parse(stamp)), true);
  });

  test('an unknown kind maps to unknown and keeps title and body', () {
    final notice = Notice.fromJson({...raw().first, 'kind': 'fine_waived_by_magic', 'title': 'A new sort of notice', 'body': 'Some text.'});
    expect(notice.kind, NoticeKind.unknown);
    expect(notice.title, 'A new sort of notice');
    expect(notice.body, 'Some text.');
  });

  test('every kind the server sends maps to its own value', () {
    expect(Notice.fromJson({...raw().first, 'kind': 'overdue_reminder'}).kind, NoticeKind.overdueReminder);
    expect(Notice.fromJson({...raw().first, 'kind': 'overdue_escalation'}).kind, NoticeKind.overdueEscalation);
    expect(Notice.fromJson({...raw().first, 'kind': 'dispute_outcome'}).kind, NoticeKind.disputeOutcome);
    expect(Notice.fromJson({...raw().first, 'kind': 'report_outcome'}).kind, NoticeKind.reportOutcome);
  });
}
