//
// Renders via showDialog(), not inline in the widget tree — an AlertDialog
// placed directly in a Stack has no barrier and doesn't float centered, so it
// would not actually behave like a dialog. This widget just listens and drives
// the real dialog route; place one instance anywhere under the MaterialApp.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/return_report.dart';
import '../../widgets/note_field.dart';
import 'ui_controller.dart';
import 'ui_state.dart';

class ConfirmDialogHost extends ConsumerStatefulWidget {
  const ConfirmDialogHost({super.key});
  @override
  ConsumerState<ConfirmDialogHost> createState() => _ConfirmDialogHostState();
}

class _ConfirmDialogHostState extends ConsumerState<ConfirmDialogHost> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(uiControllerProvider.select((s) => s.dialog), (prev, next) {
      if (next != null && !_open) {
        _open = true;
        showDialog<void>(context: context, builder: (_) => _buildDialog(next)).then((_) {
          _open = false;
          if (ref.read(uiControllerProvider).dialog != null) {
            ref.read(uiControllerProvider.notifier).closeDialog();
          }
        });
      } else if (next == null && _open) {
        _open = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    });
    return const SizedBox.shrink();
  }

  Widget _buildDialog(DialogRequest dialog) {
    final notifier = ref.read(uiControllerProvider.notifier);
    switch (dialog.kind) {
      case DialogKind.returnLoan:
        return _ReturnDialog(onCancel: notifier.closeDialog, onReturn: notifier.confirmReturnLoan);
      case DialogKind.cancelBooking:
        return AlertDialog(
          title: const Text('Cancel this booking?'),
          content: const Text("This can't be undone."),
          actions: [
            TextButton(onPressed: notifier.closeDialog, child: const Text('Keep it')),
            FilledButton(onPressed: notifier.confirmDialog, child: const Text('Cancel booking')),
          ],
        );
      case DialogKind.reliabilityInfo:
        return AlertDialog(
          title: const Text('How reliability works'),
          content: const Text(
            "Reliability reflects your recent booking history. It goes down after a missed "
            "booking and recovers automatically after a few on-time bookings in a row. It's never "
            "permanently lowered, and any effect on booking priority is small and capped.",
          ),
          actions: [FilledButton(onPressed: notifier.closeDialog, child: const Text('Got it'))],
        );
    }
  }
}

String _categoryLabel(ReportCategory category) => switch (category) {
      ReportCategory.damaged => 'Damaged',
      ReportCategory.missingPages => 'Missing pages',
      ReportCategory.other => 'Other',
    };

/// "Return this book?", with an optional report of a problem with the copy. It
/// holds its own choices, so closing it and opening it again starts blank. The
/// report is valid when a category is chosen, the trimmed note fits the limit
/// ([noteTooLong]: the server's count, shown by the shared [NoteField]), and the
/// note is there for Other; Return is off until then. A note that is only spaces
/// is no note.
class _ReturnDialog extends StatefulWidget {
  const _ReturnDialog({required this.onCancel, required this.onReturn});

  final VoidCallback onCancel;

  /// Called with the report, or null when the student reports nothing.
  final ValueChanged<ReturnReport?> onReturn;

  @override
  State<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<_ReturnDialog> {
  final _note = TextEditingController();
  bool _reporting = false;
  ReportCategory? _category;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _trimmedNote => _note.text.trim();

  bool get _valid {
    if (!_reporting) return true;
    final category = _category;
    if (category == null) return false;
    final note = _trimmedNote;
    if (noteTooLong(note)) return false;
    return category != ReportCategory.other || note.isNotEmpty;
  }

  void _return() {
    if (!_valid) return;
    final category = _category;
    if (!_reporting || category == null) return widget.onReturn(null);
    final note = _trimmedNote;
    widget.onReturn(ReturnReport(category: category, note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final category = _category;
    return AlertDialog(
      title: const Text('Return this book?'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This will be marked returned right away.'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _reporting,
            onChanged: (ticked) => setState(() => _reporting = ticked ?? false),
            title: const Text('Report a problem with this copy'),
          ),
          if (_reporting) ...[
            RadioGroup<ReportCategory>(
              groupValue: category,
              onChanged: (chosen) => setState(() => _category = chosen),
              child: Column(
                children: [
                  for (final option in ReportCategory.values)
                    RadioListTile<ReportCategory>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: option,
                      title: Text(_categoryLabel(option)),
                    ),
                ],
              ),
            ),
            NoteField(
              controller: _note,
              label: category == ReportCategory.other ? 'Note (required)' : 'Note (optional)',
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
        FilledButton(onPressed: _valid ? _return : null, child: const Text('Return')),
      ],
    );
  }
}
