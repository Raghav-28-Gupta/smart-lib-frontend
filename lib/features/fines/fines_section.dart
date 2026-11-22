// lib/features/fines/fines_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/fine.dart';
import '../../widgets/loading_skeleton.dart';
import 'fines_controller.dart';

const _updateTheApp = "Update the app to see this item's status.";

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// Whole rupees: the amounts arrive as JSON numbers, but a fine is never part of a rupee.
String _rupees(double amount) => '₹${amount.toStringAsFixed(0)}';

// '20 Nov 2026'. A fine can be months old, so the year is shown. Expects a local DateTime.
String _dateLabel(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Null for a status this version doesn't know.
String? _statusLabel(FineStatus s) => switch (s) {
      FineStatus.outstanding => 'Outstanding',
      FineStatus.adjusted => 'Adjusted',
      FineStatus.paid => 'Paid',
      FineStatus.waived => 'Waived',
      FineStatus.unknown => null,
    };

/// Null for a reason this version doesn't know, which just goes unlabelled.
String? _reasonLabel(FineReason r) => switch (r) {
      FineReason.overdue => 'Overdue',
      FineReason.noShow => 'No-show',
      FineReason.lost => 'Lost book',
      FineReason.unknown => null,
    };

/// '₹50', or '₹50, was ₹150' once a librarian has lowered or waived it.
String _amountLabel(Fine f) => f.wasAdjusted ? '${_rupees(f.amount)}, was ${_rupees(f.originalAmount)}' : _rupees(f.amount);

/// The student's fines, at the bottom of My Loans: what is still owed, then one
/// card per fine. The student only reads them; a librarian records payments and
/// waives or lowers a fine, and the change shows when My Loans is next opened.
class FinesSection extends ConsumerWidget {
  const FinesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fines = ref.watch(finesControllerProvider);
    // Not `.value` as it stands: when a different student logs in the controller
    // rebuilds, and Riverpod carries the last student's list (and error) along on
    // every state until their own answer settles it -- the reload (`isReloading`),
    // and an error if the fetch fails -- so it would show their fines and library
    // notes to this student. A quiet refresh never enters a loading state, and a
    // failed one keeps the data, so those still show the last list.
    final summary = fines.isReloading || fines.hasError ? null : fines.value;
    // The error is shown at once, as for any failed load, which includes the retries
    // Riverpod makes (a loading state holding the error, flagged `retrying`). Any
    // other loading state still holds the last student's error: not shown.
    final failed = fines.hasError && (!fines.isLoading || fines.retrying);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fines', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        if (summary != null) ...[
          if (summary.outstandingTotal > 0) ...[
            Text('Outstanding: ${_rupees(summary.outstandingTotal)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
          ],
          if (summary.fines.isEmpty) const Text('No fines.'),
          for (final f in summary.fines) _FineCard(f),
        ] else if (failed) ...[
          const Text("Couldn't load your fines."),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => ref.invalidate(finesControllerProvider), child: const Text('Retry')),
          ),
        ] else
          const LoadingSkeleton(height: 60),
      ],
    );
  }
}

class _FineCard extends StatelessWidget {
  const _FineCard(this.fine);

  final Fine fine;

  @override
  Widget build(BuildContext context) {
    final status = _statusLabel(fine.status);
    // Nothing is claimed about a fine in a status this version doesn't know (is it
    // still owed? how much?), as with a loan or a request in an unknown status.
    if (status == null) {
      return Card(child: ListTile(title: Text(fine.item), subtitle: const Text(_updateTheApp)));
    }
    final theme = Theme.of(context);
    final owed = fine.status == FineStatus.outstanding || fine.status == FineStatus.adjusted;
    final reason = _reasonLabel(fine.reason);
    final note = fine.note;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(fine.item, style: theme.textTheme.titleSmall)),
                const SizedBox(width: 12),
                Text(_amountLabel(fine), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            Text([if (reason != null) reason, _dateLabel(fine.date)].join(' · ')),
            Text(status, style: TextStyle(fontWeight: FontWeight.w600, color: owed ? theme.colorScheme.error : null)),
            if (note != null && note.isNotEmpty) Text('Library note: $note'),
          ],
        ),
      ),
    );
  }
}
