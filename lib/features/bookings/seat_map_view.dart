// lib/features/bookings/seat_map_view.dart
//
// One zone of the seat map: the bar marking the front of the room, and every
// placed desk at its real row and column. A cell with no desk is left empty,
// which is how aisles and missing desks show. The zone, the time and the pick
// come from SeatPicker; this only draws them.

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import '../../core/theme/smartlib_tokens.dart';
import '../../models/resource.dart';
import 'seat_map.dart';

/// How a desk reads at the chosen time.
enum DeskState { free, taken, offline, selected }

/// [seat]'s [DeskState] at [slot]. Out of service wins over everything, then
/// taken: a desk that cannot be booked never reads as free or as the pick.
DeskState deskStateOf(Resource seat, String slot, {required bool picked}) {
  if (seat.status == ResourceStatus.offline) return DeskState.offline;
  if (!isFreeAt(seat, slot)) return DeskState.taken;
  return picked ? DeskState.selected : DeskState.free;
}

/// The smallest a desk is drawn, in logical pixels. A zone that would need
/// smaller desks keeps this size and scrolls sideways instead.
const kMinDeskSize = 28.0;

/// The largest a desk is drawn, so a narrow zone on a wide map does not turn
/// into a few giant tiles.
const kMaxDeskSize = 56.0;

const _columnGap = 3.0;
const _rowGap = 5.0;
const _panelPadding = 8.0;

/// The side of a desk when [columns] of them share [width]: as large as fits,
/// within [kMinDeskSize] and [kMaxDeskSize].
double deskSizeFor(double width, int columns) {
  final fit = (width - (columns - 1) * _columnGap) / columns;
  return fit.clamp(kMinDeskSize, kMaxDeskSize).toDouble();
}

/// The theme colours of the four desk states.
class DeskPalette {
  const DeskPalette._({
    required this.free,
    required this.freeBorder,
    required this.freeText,
    required this.taken,
    required this.takenText,
    required this.offline,
    required this.offlineBorder,
    required this.offlineHatch,
    required this.offlineText,
    required this.pick,
    required this.pickBorder,
    required this.panel,
    required this.front,
    required this.frontText,
  });

  factory DeskPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.extension<SmartLibTokens>() ?? SmartLibTokens.standard();
    return DeskPalette._(
      // Free: outlined, the lightest thing on the panel.
      free: t.neutral[100]!,
      freeBorder: t.neutral[600]!,
      freeText: t.text,
      // Taken: filled and muted, no outline.
      taken: t.neutral[400]!,
      takenText: t.neutral[700]!,
      // Out of service: hatched, so it never reads as taken or free.
      offline: t.neutral[200]!,
      offlineBorder: t.neutral[500]!,
      offlineHatch: t.neutral[400]!,
      offlineText: t.neutral[600]!,
      // Your pick: the theme's olive, the colour of the selected day and time
      // chips (ChoiceChip's selected colour, secondaryContainer, is the
      // secondary in this theme). The primary is the copper of the buttons.
      pick: theme.colorScheme.secondary,
      pickBorder: t.accent2[800]!,
      panel: theme.colorScheme.surface,
      front: t.neutral[400]!,
      frontText: t.neutral[700]!,
    );
  }

  final Color free;
  final Color freeBorder;
  final Color freeText;
  final Color taken;
  final Color takenText;
  final Color offline;
  final Color offlineBorder;
  final Color offlineHatch;
  final Color offlineText;
  final Color pick;
  final Color pickBorder;
  final Color panel;
  final Color front;
  final Color frontText;
}

/// Rounder at the back than at the front, like a chair seen from above.
BorderRadius _deskRadius(double size) =>
    BorderRadius.vertical(top: Radius.circular(size * 0.3), bottom: Radius.circular(size * 0.12));

/// A desk's face in [state]: the map draws it with [label], the legend
/// without. It is only paint; [SeatMapView] makes the desk a button.
class DeskFace extends StatelessWidget {
  const DeskFace({super.key, required this.state, required this.size, this.label});

  final DeskState state;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = DeskPalette.of(context);
    final (fill, border, text) = switch (state) {
      DeskState.free => (p.free, p.freeBorder, p.freeText),
      DeskState.taken => (p.taken, p.taken, p.takenText),
      DeskState.offline => (p.offline, p.offlineBorder, p.offlineText),
      DeskState.selected => (p.pick, p.pickBorder, Colors.white),
    };
    final radius = _deskRadius(size);
    final label = this.label;
    return DecoratedBox(
      decoration: BoxDecoration(color: fill, border: Border.all(color: border, width: 1.5), borderRadius: radius),
      child: CustomPaint(
        painter: state == DeskState.offline ? _HatchPainter(p.offlineHatch, radius) : null,
        child: SizedBox(
          width: size,
          height: size,
          child: label == null
              ? null
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: text,
                          fontSize: (size * 0.4).clamp(10, 15).toDouble(),
                          fontWeight: state == DeskState.selected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Diagonal stripes across an out-of-service desk.
class _HatchPainter extends CustomPainter {
  _HatchPainter(this.color, this.radius);

  final Color color;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    canvas.save();
    canvas.clipRRect(radius.toRRect(Offset.zero & size).deflate(1.5));
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius;
}

/// The words a screen reader says after "Desk 14,".
const _stateWords = {
  DeskState.free: 'free',
  DeskState.taken: 'taken',
  DeskState.offline: 'out of service',
  DeskState.selected: 'selected',
};

/// [zone]'s map at [slot]: its front bar, then its grid. Desks fit the width
/// down to [kMinDeskSize]; past that the grid scrolls sideways. A free desk, or
/// the pick, calls [onPick]; taken and out-of-service desks do nothing.
class SeatMapView extends StatefulWidget {
  const SeatMapView({super.key, required this.zone, required this.slot, required this.pickedId, required this.onPick});

  final SeatZoneMap zone;
  final String slot;

  /// The id of the seat picked at [slot], if any.
  final String? pickedId;
  final ValueChanged<Resource> onPick;

  @override
  State<SeatMapView> createState() => _SeatMapViewState();
}

class _SeatMapViewState extends State<SeatMapView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DeskPalette.of(context);
    final zone = widget.zone;
    return Material(
      color: p.panel,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(_panelPadding),
        child: LayoutBuilder(builder: (context, constraints) {
          final inner = constraints.maxWidth;
          final desk = deskSizeFor(inner, zone.columns);
          final gridWidth = zone.columns * desk + (zone.columns - 1) * _columnGap;
          final front = zone.front;
          return Column(children: [
            if (front != null) _FrontBar(label: front, width: gridWidth < inner ? gridWidth : inner),
            Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: ScrollConfiguration(
                // A mouse can drag the map sideways too, as a finger can. The
                // Scrollbar above is the only one, so the platform adds none.
                behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet(), scrollbars: false),
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: inner),
                    child: Center(child: _grid(desk)),
                  ),
                ),
              ),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _grid(double desk) {
    final zone = widget.zone;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (var row = 1; row <= zone.rows; row++)
        Padding(
          padding: EdgeInsets.only(top: row == 1 ? 0 : _rowGap),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var column = 1; column <= zone.columns; column++) ...[
              if (column > 1) const SizedBox(width: _columnGap),
              _cell(zone.desks[(row, column)], desk),
            ],
          ]),
        ),
    ]);
  }

  Widget _cell(Resource? seat, double size) {
    if (seat == null) return SizedBox(width: size, height: size);
    final state = deskStateOf(seat, widget.slot, picked: seat.id == widget.pickedId);
    final label = deskLabel(seat.name);
    final tappable = state == DeskState.free || state == DeskState.selected;
    final radius = _deskRadius(size);
    return Semantics(
      key: Key('desk-${seat.id}'),
      container: true,
      button: true,
      enabled: tappable,
      selected: state == DeskState.selected,
      label: 'Desk $label, ${_stateWords[state]}',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(children: [
          ExcludeSemantics(child: DeskFace(state: state, size: size, label: label)),
          // Over the face, so the splash shows on top of it.
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: radius,
                onTap: tappable ? () => widget.onPick(seat) : null,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The curved bar at the top of a zone, with what its front faces in small
/// capitals ("WINDOWS").
class _FrontBar extends StatelessWidget {
  const _FrontBar({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = DeskPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Column(children: [
        Container(
          width: width,
          height: 8,
          decoration: BoxDecoration(
            color: p.front,
            borderRadius: BorderRadius.vertical(top: Radius.elliptical(width / 2, 8)),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label.toUpperCase(),
          semanticsLabel: 'Front of the room: $label',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: p.frontText,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
              ),
        ),
      ]),
    );
  }
}
