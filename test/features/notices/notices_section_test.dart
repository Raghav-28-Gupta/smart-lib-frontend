// test/features/notices/notices_section_test.dart
//
// The Library notices section on its own: the filter by kind that lets My Bookings show the
// booking kinds and My Loans every other kind. The screens' own behaviour (refreshing on open,
// an account switch, the empty state) is tested with each screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/features/notices/notice_repository.dart';
import 'package:smartlib_frontend/features/notices/notices_section.dart';
import 'package:smartlib_frontend/models/notice.dart';
import '../../support/mock_overrides.dart';

// One notice per kind, each with its own words, newest first as the server lists them.
List<Notice> _everyKind() {
  final now = DateTime.now();
  return [
    for (final (i, kind) in NoticeKind.values.indexed)
      Notice(
        id: 'n$i',
        kind: kind,
        title: 'Title of ${kind.name}',
        body: 'Body of ${kind.name}',
        createdAt: now.subtract(Duration(hours: i + 1)),
      ),
  ];
}

const _bookingTitles = ['Title of bookingReminder', 'Title of noShow', 'Title of noShowOutcome'];

Future<void> _pump(WidgetTester tester, Set<NoticeKind> kinds, List<Notice> notices) async {
  await tester.pumpWidget(ProviderScope(
    overrides: mockRepositoryOverrides(notices: MockNoticeRepository(notices: notices)),
    child: MaterialApp(
      theme: buildSmartLibTheme(),
      home: Scaffold(body: SingleChildScrollView(child: NoticesSection(kinds: kinds))),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('the booking kinds and the loan kinds split every kind between them', () {
    expect(bookingNoticeKinds, {NoticeKind.bookingReminder, NoticeKind.noShow, NoticeKind.noShowOutcome});
    expect(bookingNoticeKinds.intersection(loanNoticeKinds), isEmpty);
    expect(bookingNoticeKinds.union(loanNoticeKinds), NoticeKind.values.toSet());
    // The loan and fine kinds, and a kind this version does not know, stay on My Loans.
    expect(loanNoticeKinds, containsAll([
      NoticeKind.overdueReminder, NoticeKind.overdueEscalation, NoticeKind.disputeOutcome, NoticeKind.reportOutcome,
      NoticeKind.unknown,
    ]));
  });

  testWidgets('a section for the booking kinds shows only those, and one for the loan kinds shows every other', (tester) async {
    await _pump(tester, bookingNoticeKinds, _everyKind());
    expect(find.text('Library notices'), findsOneWidget);
    for (final title in _bookingTitles) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.byType(Card), findsNWidgets(3));
    expect(find.text('Title of overdueReminder'), findsNothing);
    expect(find.text('Title of disputeOutcome'), findsNothing);
    expect(find.text('Title of unknown'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, loanNoticeKinds, _everyKind());
    expect(find.text('Library notices'), findsOneWidget);
    for (final title in _bookingTitles) {
      expect(find.text(title), findsNothing);
    }
    expect(find.byType(Card), findsNWidgets(5));
    for (final kind in loanNoticeKinds) {
      expect(find.text('Title of ${kind.name}'), findsOneWidget, reason: '$kind');
    }
  });

  testWidgets("keeps the server's order (newest first) among the notices of its kinds", (tester) async {
    await _pump(tester, bookingNoticeKinds, _everyKind());
    final tops = [for (final title in _bookingTitles) tester.getTopLeft(find.text(title)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
  });

  testWidgets('a section with no notices of its kinds renders nothing: no heading, no empty text', (tester) async {
    // Nothing at all.
    await _pump(tester, bookingNoticeKinds, const []);
    expect(find.text('Library notices'), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(tester.getSize(find.byType(NoticesSection)), Size.zero);

    // Notices, but none of this section's kinds.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, bookingNoticeKinds, [for (final n in _everyKind()) if (loanNoticeKinds.contains(n.kind)) n]);
    expect(find.text('Library notices'), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(tester.getSize(find.byType(NoticesSection)), Size.zero);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, loanNoticeKinds, [for (final n in _everyKind()) if (bookingNoticeKinds.contains(n.kind)) n]);
    expect(find.text('Library notices'), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(tester.getSize(find.byType(NoticesSection)), Size.zero);
  });

  testWidgets('a booking notice is drawn like any other: bold title, body and date, no accent', (tester) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await _pump(tester, bookingNoticeKinds, [
      Notice(
        id: 'n1', kind: NoticeKind.noShow, title: 'Missed booking', createdAt: yesterday,
        body: "You didn't check in to Group Room 201 (Thu, Oct 22, 2–3 PM), so the slot was released and a no-show was recorded.",
      ),
    ]);

    final title = tester.widget<Text>(find.text('Missed booking'));
    expect(title.style?.fontWeight, FontWeight.bold);
    expect(title.style?.color, isNull);
    expect(find.textContaining("You didn't check in to Group Room 201 (Thu, Oct 22, 2–3 PM)"), findsOneWidget);
    expect(find.text('${yesterday.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][yesterday.month - 1]} ${yesterday.year}'), findsOneWidget);
  });
}
