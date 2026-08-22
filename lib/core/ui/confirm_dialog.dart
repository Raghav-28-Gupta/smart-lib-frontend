//
// Renders via showDialog(), not inline in the widget tree — an AlertDialog
// placed directly in a Stack has no barrier and doesn't float centered, so it
// would not actually behave like a dialog. This widget just listens and drives
// the real dialog route; place one instance anywhere under the MaterialApp.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        return AlertDialog(
          title: const Text('Return this book?'),
          content: const Text('This will be marked returned right away.'),
          actions: [
            TextButton(onPressed: notifier.closeDialog, child: const Text('Cancel')),
            FilledButton(onPressed: notifier.confirmDialog, child: const Text('Return')),
          ],
        );
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
