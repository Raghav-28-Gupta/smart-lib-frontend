// lib/features/fines/fines_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_exception.dart';
import '../../core/ui/ui_controller.dart';
import '../../models/fine.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/note_field.dart';
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
/// card per fine. A librarian records payments and waives or lowers a fine, and
/// the change shows when My Loans is next opened. The student may dispute a fine
/// that is still owed, once: the card then reads "Under review" until the library
/// answers (see [_DisputeNote]).
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
            _DisputeNote(fine: fine, owed: owed),
          ],
        ),
      ),
    );
  }
}

/// What the card says about the student's dispute, under the fine itself.
///
/// - No dispute on a fine still owed: a **Dispute** button. Paid and waived fines
///   have none, and once a dispute exists the button never returns, whatever became
///   of it (the server allows one per fine, ever).
/// - Open: "Under review".
/// - Upheld: "The library kept this fine." and the librarian's note.
/// - Waived and adjusted say nothing more: the fine's own status, amount and
///   "Library note" already tell it. Nor does a status this version doesn't know.
class _DisputeNote extends StatelessWidget {
  const _DisputeNote({required this.fine, required this.owed});

  final Fine fine;
  final bool owed;

  @override
  Widget build(BuildContext context) {
    final dispute = fine.dispute;
    if (dispute == null) {
      if (!owed) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _askToDispute(context, fine),
          // Every card's button reads "Dispute", so a screen reader is told which fine.
          child: Semantics(label: _disputeLabel(fine), excludeSemantics: true, child: const Text('Dispute')),
        ),
      );
    }
    switch (dispute.status) {
      case DisputeStatus.open:
        return const Text('Under review', style: TextStyle(fontStyle: FontStyle.italic));
      case DisputeStatus.upheld:
        final note = dispute.note;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The library kept this fine.', style: TextStyle(fontWeight: FontWeight.w600)),
            if (note != null && note.isNotEmpty) Text(note),
          ],
        );
      case DisputeStatus.waived || DisputeStatus.adjusted || DisputeStatus.unknown:
        return const SizedBox.shrink();
    }
  }
}

/// What a screen reader says for the Dispute button of [fine]: "Dispute fine of ₹30 for
/// Operating System Concepts" (the visible text stays "Dispute"). A fine that names no
/// book or resource has nothing to add after its amount.
String _disputeLabel(Fine fine) =>
    fine.item.isEmpty ? 'Dispute fine of ${_rupees(fine.amount)}' : 'Dispute fine of ${_rupees(fine.amount)} for ${fine.item}';

Future<void> _askToDispute(BuildContext context, Fine fine) =>
    showDialog<void>(context: context, builder: (_) => _DisputeDialog(fine: fine));

/// "Dispute this fine": one required reason, sent once. The reason is limited as the
/// server limits it ([noteTooLong], shown by the shared [NoteField]): Send is off while
/// it is empty or over 300 UTF-16 code units trimmed, and what the student typed is never
/// cut. On a refusal the dialog stays with the student's words so they can send them
/// again or cancel; while the answer is awaited Send is off, so a second tap can't send a
/// second dispute.
class _DisputeDialog extends ConsumerStatefulWidget {
  const _DisputeDialog({required this.fine});

  final Fine fine;

  @override
  ConsumerState<_DisputeDialog> createState() => _DisputeDialogState();
}

class _DisputeDialogState extends ConsumerState<_DisputeDialog> {
  final _reason = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canSend {
    final reason = _reason.text.trim();
    return reason.isNotEmpty && !noteTooLong(reason) && !_sending;
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final reason = _reason.text.trim();
    setState(() => _sending = true);
    final fineId = widget.fine.id;
    final failure = await ref
        .read(uiControllerProvider.notifier)
        .attempt(() => ref.read(finesControllerProvider.notifier).dispute(fineId, reason), success: 'Dispute sent.');
    if (!mounted) return;
    // An expired session is on its way to the login screen, which says so, and the
    // dialog must not be left on top of it. Any other refusal was toasted by
    // `attempt` and the dialog stays, with the student's text.
    if (failure == null || failure is UnauthorizedException) {
      Navigator.of(context).pop();
    } else {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dispute this fine'),
      scrollable: true,
      content: NoteField(
        controller: _reason,
        label: 'Why do you think this fine is wrong?',
        enabled: !_sending,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _canSend ? _send : null, child: const Text('Send')),
      ],
    );
  }
}
