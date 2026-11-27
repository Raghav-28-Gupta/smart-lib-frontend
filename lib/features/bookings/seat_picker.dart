// lib/features/bookings/seat_picker.dart
//
// The Seats tab under the day chips, time first: a strip of times, each with how
// many desks are free; then the zone chips, the chosen zone's map and its
// legend; then the seats that are not on a map yet. The pick goes back to the
// booking flow through the callbacks; this widget holds no booking state.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../models/resource.dart';
import '../../widgets/empty_state.dart';
import 'seat_map.dart';
import 'seat_map_view.dart';
import 'time_slots.dart';

/// The time the Seats tab shows: the student's [chosen] time when it is one of
/// the slots and has not passed, else the time the tab opens on ([defaultSlot]).
/// A time that is not a slot (a conflict alternative's own window) counts as
/// none chosen, and so does one that passed while the student looked on: its
/// desks would read free though none can be booked. Null when no time is left.
String? shownSlot(List<Resource> seats, int dateIndex, String? chosen, {required DateTime now}) =>
    chosen != null && kSlotHours.containsKey(chosen) && !slotHasPassed(dateIndex, chosen, now: now)
        ? chosen
        : defaultSlot(seats, dateIndex, now: now);

/// The widest the Seats tab grows; on a wide window it is centred.
const kSeatPickerMaxWidth = 600.0;

class SeatPicker extends StatelessWidget {
  const SeatPicker({
    super.key,
    required this.seats,
    required this.dateIndex,
    required this.now,
    required this.selectedSlot,
    required this.selectedZone,
    required this.selectedSeat,
    required this.onChooseTime,
    required this.onChooseZone,
    required this.onPickSeat,
    required this.onSeeTomorrow,
    required this.onShowRooms,
  });

  /// Every seat for the day, placed or not, offline ones included.
  final List<Resource> seats;
  final int dateIndex;
  final DateTime now;
  final String? selectedSlot;

  /// The zone the student chose; the first zone when null or gone.
  final String? selectedZone;
  final Resource? selectedSeat;
  final ValueChanged<String> onChooseTime;
  final ValueChanged<String> onChooseZone;

  /// A free seat was tapped at the time shown.
  final void Function(Resource seat, String slot) onPickSeat;
  final VoidCallback onSeeTomorrow;
  final VoidCallback onShowRooms;

  @override
  Widget build(BuildContext context) {
    final slot = shownSlot(seats, dateIndex, selectedSlot, now: now);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSeatPickerMaxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _SectionLabel('Pick a time'),
            _TimeStrip(seats: seats, dateIndex: dateIndex, now: now, selected: slot, onChoose: onChooseTime),
            if (slot == null)
              dateIndex == 0
                  ? EmptyState(
                      icon: Icons.event_busy,
                      title: 'No times left today',
                      body: 'Every time today has passed or is full.',
                      actionLabel: 'See tomorrow',
                      onAction: onSeeTomorrow,
                    )
                  : EmptyState(
                      icon: Icons.event_busy,
                      title: 'No seats free on this date',
                      body: 'Try another day, or book a group room instead.',
                      actionLabel: 'Show Rooms',
                      onAction: onShowRooms,
                    )
            else
              ..._desks(context, slot),
          ]),
        ),
      ),
    );
  }

  List<Widget> _desks(BuildContext context, String slot) {
    final zones = zonesOf(seats);
    final zone = zones.where((z) => z.name == selectedZone).firstOrNull ?? zones.firstOrNull;
    final unplaced = unplacedSeats(seats);
    // The pick shows only at the time it was made for.
    final seat = selectedSeat;
    final pickedId = seat != null && selectedSlot == slot ? seat.id : null;
    return [
      const _SectionLabel('Pick a desk'),
      if (zone != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final z in zones)
              ChoiceChip(
                key: Key('zoneChip-${z.name}'),
                showCheckmark: false,
                label: Text('${z.name} · ${freeCount(z.desks.values, slot)} free'),
                selected: z.name == zone.name,
                onSelected: (_) => onChooseZone(z.name),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SeatMapView(
            key: ValueKey(zone.name),
            zone: zone,
            slot: slot,
            pickedId: pickedId,
            onPick: (desk) => onPickSeat(desk, slot),
          ),
        ),
        const SizedBox(height: 10),
        _Legend(withOffline: zone.desks.values.any((s) => s.status == ResourceStatus.offline)),
      ],
      if (unplaced.isNotEmpty) ...[
        const _SectionLabel('Not on the map yet'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in unplaced) _unplacedChip(s, slot, picked: s.id == pickedId),
          ]),
        ),
      ],
    ];
  }

  /// A seat with no place on a map, as a chip: free or taken at [slot], and
  /// picked exactly like a desk on the map.
  Widget _unplacedChip(Resource seat, String slot, {required bool picked}) {
    final taken = deskStateOf(seat, slot, picked: picked) == DeskState.taken;
    return ChoiceChip(
      key: Key('unplaced-${seat.id}'),
      showCheckmark: false,
      label: Text(taken ? '${seat.name} · taken' : seat.name),
      selected: picked && !taken,
      onSelected: taken ? null : (_) => onPickSeat(seat, slot),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
      ),
    );
  }
}

/// One chip per slot, with how many seats are free then. A time that has
/// passed is struck through, and one with nothing free reads "Full"; neither
/// can be chosen. On first build the strip scrolls to the time shown, which on
/// an afternoon is far to the right.
class _TimeStrip extends StatefulWidget {
  const _TimeStrip({required this.seats, required this.dateIndex, required this.now, required this.selected, required this.onChoose});

  final List<Resource> seats;
  final int dateIndex;
  final DateTime now;
  final String? selected;
  final ValueChanged<String> onChoose;

  @override
  State<_TimeStrip> createState() => _TimeStripState();
}

class _TimeStripState extends State<_TimeStrip> {
  final _scroll = ScrollController();
  final _chipKeys = {for (final slot in kTimeSlots) slot: GlobalKey()};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Only the strip moves; Scrollable.ensureVisible would scroll the page too.
  void _revealSelected() {
    final slot = widget.selected;
    if (!mounted || slot == null || !_scroll.hasClients) return;
    final chip = _chipKeys[slot]!.currentContext?.findRenderObject();
    if (chip == null) return;
    final viewport = RenderAbstractViewport.maybeOf(chip);
    if (viewport == null) return;
    final position = _scroll.position;
    final offset = viewport.getOffsetToReveal(chip, 0.5).offset;
    _scroll.jumpTo(offset.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        for (final slot in kTimeSlots)
          KeyedSubtree(
            key: _chipKeys[slot],
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: _chip(slot)),
          ),
      ]),
    );
  }

  Widget _chip(String slot) {
    final state = slotState(widget.seats, widget.dateIndex, slot, now: widget.now);
    final passed = state == SlotState.passed;
    final count = switch (state) {
      // A count for a time that is over would only mislead.
      SlotState.passed => '',
      SlotState.full => 'Full',
      SlotState.open => '${freeCount(widget.seats, slot)} free',
    };
    return ChoiceChip(
      key: Key('timeChip-$slot'),
      showCheckmark: false,
      label: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          slot,
          semanticsLabel: passed ? '$slot, passed' : null,
          style: passed ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
        ),
        Text(count, style: const TextStyle(fontSize: 10)),
      ]),
      selected: slot == widget.selected,
      onSelected: state == SlotState.open ? (_) => widget.onChoose(slot) : null,
    );
  }
}

/// What the desk colours mean. "Out of service" only while the zone has such
/// a desk.
class _Legend extends StatelessWidget {
  const _Legend({required this.withOffline});

  final bool withOffline;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    Widget item(DeskState state, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          ExcludeSemantics(child: DeskFace(state: state, size: 14)),
          const SizedBox(width: 5),
          Text(label, style: style),
        ]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 6, children: [
        item(DeskState.free, 'Free'),
        item(DeskState.taken, 'Taken'),
        item(DeskState.selected, 'Your pick'),
        if (withOffline) item(DeskState.offline, 'Out of service'),
      ]),
    );
  }
}
