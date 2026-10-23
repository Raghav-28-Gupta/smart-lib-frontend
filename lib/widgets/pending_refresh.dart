// lib/widgets/pending_refresh.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

/// How often a screen with a request waiting for a librarian re-checks it.
const kPendingRecheckInterval = Duration(seconds: 30);

/// While [active], calls [onTick] every [interval], so a librarian's answer
/// shows up without a manual refresh. Stops as soon as [active] turns false or
/// the screen goes away.
class PendingRefresh extends StatefulWidget {
  const PendingRefresh({
    super.key,
    required this.active,
    required this.onTick,
    required this.child,
    this.interval = kPendingRecheckInterval,
  });

  final bool active;
  final VoidCallback onTick;
  final Widget child;
  final Duration interval;

  @override
  State<PendingRefresh> createState() => _PendingRefreshState();
}

class _PendingRefreshState extends State<PendingRefresh> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PendingRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active && _timer == null) {
      // Reads widget.onTick on every tick, so a rebuilt callback is used.
      _timer = Timer.periodic(widget.interval, (_) => widget.onTick());
    } else if (!widget.active) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
