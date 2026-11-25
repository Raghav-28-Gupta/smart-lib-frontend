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

  group('booking notices', () {
    // `notices_me_no_show_outcome` is captured (tool/capture_fixtures.dart: the admin overturns the
    // demo student's no-show). The capture reaches only that outcome, not the other kinds: no sweep
    // runs there, and no one upholds.
    List<Map<String, dynamic>> outcomeRaw() => (fixture('notices_me_no_show_outcome') as List).cast<Map<String, dynamic>>();

    // CONSTRUCTED, not captured: a captured notice's keys with the backend's copy (spec section 7).
    // The booking's day and time read as the backend writes them: a day as `Thu, Oct 22` and a
    // slot as `2–3 PM` (an en dash, no spaces), so a `no_show` body holds `(Thu, Oct 22, 2–3 PM)`
    // and a reminder `<Resource>, 2–3 PM.`
    Map<String, dynamic> constructed(String kind, String title, String body) =>
        {...outcomeRaw().first, 'kind': kind, 'title': title, 'body': body};

    test('the three new notice kinds parse and an unknown kind still maps to unknown', () {
      final reminder = Notice.fromJson(constructed(
        'booking_reminder',
        'Your booking starts soon',
        'Group Room 201 · 4 seats, 2–3 PM. Check in within 15 minutes of the start or the slot is released.',
      ));
      expect(reminder.kind, NoticeKind.bookingReminder);
      expect(reminder.title, 'Your booking starts soon');
      expect(reminder.body, startsWith('Group Room 201 · 4 seats, 2–3 PM. '));

      final missed = Notice.fromJson(constructed(
        'no_show',
        'Missed booking',
        "You didn't check in to Group Room 201 · 4 seats (Mon, Nov 23, 9–10 AM), so the slot was released and a no-show was "
            'recorded. Your reliability score went from 57 to 52. If this is wrong, you can dispute it from My Bookings within 7 days.',
      ));
      expect(missed.kind, NoticeKind.noShow);
      expect(missed.title, 'Missed booking');
      expect(missed.body, contains('(Mon, Nov 23, 9–10 AM)'));
      expect(missed.body, contains('you can dispute it from My Bookings within 7 days.'));

      // The captured one: the librarian overturned the student's no-show, with a note. The day is
      // written `Mon, Nov 23` and the score is the one restored.
      final outcome = outcomeRaw().map(Notice.fromJson).singleWhere((n) => n.kind == NoticeKind.noShowOutcome);
      expect(outcome.id, isNotEmpty);
      expect(outcome.title, 'No-show removed');
      expect(outcome.body, startsWith('The library removed the no-show for Group Room 201 · 4 seats ('));
      expect(outcome.body, contains('and restored your reliability score to'));
      expect(outcome.body, contains('Note from the library: The desk scanner was down that morning'));
      expect(outcome.createdAt.isUtc, false);

      // An upheld outcome is the same kind with other words (CONSTRUCTED: nothing in the capture upholds).
      final upheld = Notice.fromJson(constructed('no_show_outcome', 'No-show stands', 'The library kept the no-show for Group Room 201 · 4 seats (Mon, Nov 23).'));
      expect(upheld.kind, NoticeKind.noShowOutcome);

      // A kind a later server adds is still unknown, with its words intact.
      final later = Notice.fromJson(constructed('no_show_appeal_window', 'A newer sort of notice', 'Some text.'));
      expect(later.kind, NoticeKind.unknown);
      expect(later.title, 'A newer sort of notice');
      expect(later.body, 'Some text.');
    });
  });
}
