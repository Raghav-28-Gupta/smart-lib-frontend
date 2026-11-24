// lib/features/notices/notices_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/notice.dart';
import 'notices_controller.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// '20 Nov 2026', as the Fines section dates a fine. Expects a local DateTime.
String _dateLabel(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// The library's messages to the student (a librarian's overdue reminder, the
/// outcome of a dispute or a report), at the top of My Loans. Notices are
/// secondary, so the section is simply absent when there are none, while they
/// load and when they could not be loaded -- no error text; My Loans asks again the
/// next time it opens.
class NoticesSection extends ConsumerWidget {
  const NoticesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(noticesControllerProvider);
    // Not `.value` as it stands: when a different student logs in the controller
    // rebuilds, and Riverpod carries the last student's list along on every state
    // until their own answer settles it -- the reload (`isReloading`), and beside
    // the error if the fetch fails -- so it would show their notices to this
    // student. A quiet refresh never enters a loading state, and a failed one keeps
    // the data, so those still show the last list.
    final notices = state.isReloading || state.hasError ? null : state.value;
    if (notices == null || notices.isEmpty) return const SizedBox.shrink();
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
    // A formal notice stands out. A kind this version doesn't know is drawn like
    // any other: its title and body are all that matter.
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
