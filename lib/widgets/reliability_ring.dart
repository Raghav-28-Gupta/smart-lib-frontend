import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/smartlib_tokens.dart';

class ReliabilityRing extends StatelessWidget {
  const ReliabilityRing({super.key, required this.fraction, required this.centerLabel, this.size = 120});
  final double fraction;
  final String centerLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<SmartLibTokens>();
    return SizedBox(
      width: size, height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(size, size),
          painter: _RingPainter(
            fraction: fraction,
            track: tokens?.neutral[300] ?? const Color(0xFFdcd3c4),
            fill: tokens?.accent2[600] ?? const Color(0xFF728157),
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(centerLabel, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          Text('Reliability', style: Theme.of(context).textTheme.labelSmall),
        ]),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.track, required this.fill});
  final double fraction;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.083;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final trackPaint = Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = stroke;
    final fillPaint = Paint()..color = fill..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.fraction != fraction;
}
