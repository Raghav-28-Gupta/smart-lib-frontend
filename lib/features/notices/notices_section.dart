// lib/features/notices/notices_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/notice.dart';
import 'notices_controller.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// '20 Nov 2026', as the Fines section dates a fine. Expects a local DateTime.
String _dateLabel(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// The kinds about a booking (the reminder before it starts, a recorded no-show, the
/// answer to a dispute of one): My Bookings shows these, My Loans every other kind.
const bookingNoticeKinds = {NoticeKind.bookingReminder, NoticeKind.noShow, NoticeKind.noShowOutcome};

/// Every kind but the booking ones: the loan and fine kinds, and [NoticeKind.unknown], so a
/// kind a later server adds stays where an older app already shows it, on My Loans.
final loanNoticeKinds = Set<NoticeKind>.unmodifiable({...NoticeKind.values}.difference(bookingNoticeKinds));

/// The library's messages to the student (a librarian's overdue reminder, the
/// outcome of a dispute or a report, a booking's reminder or recorded no-show), the ones
/// of [kinds]: at the top of My Loans ([loanNoticeKinds]) and of My Bookings
/// ([bookingNoticeKinds]), both reading the one per-user [NoticesController]. Notices are
/// secondary, so the section is simply absent when there are none of its kinds, while they
/// load and when they could not be loaded -- no heading, no empty text, no error text; its
/// screen asks again the next time it opens.
class NoticesSection extends ConsumerWidget {
  const NoticesSection({super.key, required this.kinds});

  final Set<NoticeKind> kinds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(noticesControllerProvider);
    // Not `.value` as it stands: when a different student logs in the controller
    // rebuilds, and Riverpod carries the last student's list along on every state
    // until their own answer settles it -- the reload (`isReloading`), and beside
    // the error if the fetch fails -- so it would show their notices to this
    // student. A quiet refresh never enters a loading state, and a failed one keeps
    // the data, so those still show the last list.
    final all = state.isReloading || state.hasError ? null : state.value;
    final notices = [...?all?.where((n) => kinds.contains(n.kind))];
    if (notices.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Library notices', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final n in notices) _NoticeCard(n),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard(this.notice);

  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A formal notice stands out. Every other kind -- a booking's reminder, a recorded
    // no-show, one this version doesn't know -- is drawn like any other: its title and
    // body, as the server worded them, are all that matter.
    final escalation = notice.kind == NoticeKind.overdueEscalation;
    final accent = theme.colorScheme.primary;
    final shape = theme.cardTheme.shape;
    return Card(
      shape: escalation && shape is RoundedRectangleBorder ? shape.copyWith(side: BorderSide(color: accent)) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notice.title, style: TextStyle(fontWeight: FontWeight.bold, color: escalation ? accent : null)),
            const SizedBox(height: 2),
            Text(notice.body),
            const SizedBox(height: 4),
            Text(_dateLabel(notice.createdAt), style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
