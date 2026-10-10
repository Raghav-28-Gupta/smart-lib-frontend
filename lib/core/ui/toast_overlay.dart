import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui_controller.dart';

/// A [MaterialApp.builder] that layers the toast above every route.
///
/// The book detail and booking flow screens are pushed over the tab shell, so
/// a host inside the shell sat underneath them and their toasts never showed.
Widget withToasts(BuildContext context, Widget? child) =>
    Stack(fit: StackFit.expand, children: [child ?? const SizedBox.shrink(), const ToastHost()]);

class ToastHost extends ConsumerStatefulWidget {
  const ToastHost({super.key});
  @override
  ConsumerState<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends ConsumerState<ToastHost> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toast = ref.watch(uiControllerProvider.select((s) => s.toast));
    if (toast != null) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 2400), () {
        if (mounted) ref.read(uiControllerProvider.notifier).clearToast();
      });
    }
    if (toast == null) return const SizedBox.shrink();
    return Positioned(
      // Clear of the tab shell's NavigationBar (80 high) -- the host sits
      // above every route now, not inside the shell's body.
      bottom: MediaQuery.viewPaddingOf(context).bottom + 80 + 14, left: 14, right: 14,
      child: Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(toast, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
        ),
      ),
    );
  }
}
