// lib/widgets/pending_refresh.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

/// How often a screen with a request waiting for a librarian re-checks it.
const kPendingRecheckInterval = Duration(seconds: 30);

/// While [active], calls [onTick] every [interval], so a librarian's answer
/// shows up without a manual refresh. Stops as soon as [active] turns false or
/// the screen goes away.
///
/// A screen that opens already [active] is showing what the controllers last
/// held, which may predate the librarian's answer, so [onTick] is also called
/// once right after its first frame. Not when [active] turns true later: that
/// is right after the student's own request, which was just answered.
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
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) widget.onTick();
      });
    }
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
