// lib/features/bookings/booking_flow_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/clock.dart';
import '../../core/time_format.dart';
import '../../core/ui/ui_controller.dart';
import '../../models/resource_booking.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import 'booking_flow_controller.dart';
import 'seat_map.dart';
import 'seat_picker.dart';
import 'time_slots.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _dateLabel(int i) {
  if (i == 0) return 'Today';
  if (i == 1) return 'Tomorrow';
  return _weekdays[DateTime.now().add(Duration(days: i)).weekday - 1];
}

String _dateSub(int i) {
  final d = DateTime.now().add(Duration(days: i));
  return '${_months[d.month - 1]} ${d.day}';
}

class BookingFlowScreen extends ConsumerWidget {
  const BookingFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(bookingFlowControllerProvider);
    final notifier = ref.read(bookingFlowControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Book a Resource')),
      body: flow.step == BookingFlowStep.pick ? _buildPick(context, ref, flow, notifier) : _buildConfirm(context, ref, flow, notifier),
    );
  }

  Widget _buildPick(BuildContext context, WidgetRef ref, BookingFlowState flow, BookingFlowController notifier) {
    final resourcesAsync = ref.watch(bookingResourcesProvider);
    final now = ref.read(clockProvider)();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<ResourceType>(
          segments: const [
            ButtonSegment(value: ResourceType.seat, label: Text('Seats')),
            ButtonSegment(value: ResourceType.room, label: Text('Rooms')),
          ],
          selected: {flow.type},
          onSelectionChanged: (s) => notifier.setType(s.first),
        ),
      ),
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                key: Key('dateChip-$i'),
                label: Column(children: [Text(_dateLabel(i)), Text(_dateSub(i), style: const TextStyle(fontSize: 10))]),
                selected: flow.dateIndex == i,
                onSelected: (_) => notifier.setDateIndex(i),
              ),
            ),
        ]),
      ),
      // Emptiness comes from the server's answer for this type and date. It
      // used to be hard-coded as "rooms, 2+ days out" -- a rule copied from the
      // mock repository that would have hidden real rooms forever.
      Expanded(child: resourcesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => ErrorState(title: "Couldn't load availability", onRetry: () => ref.invalidate(bookingResourcesProvider)),
              data: (resources) => resources.isEmpty
                  ? _noneFree(flow.type, notifier)
                  // Seats pick the time first, then a desk on the map; rooms keep the list.
                  : flow.type == ResourceType.seat
                      ? SeatPicker(
                          seats: resources,
                          dateIndex: flow.dateIndex,
                          now: now,
                          selectedSlot: flow.selectedSlot,
                          selectedZone: flow.selectedZone,
                          selectedSeat: flow.selectedResource,
                          onChooseTime: notifier.chooseTime,
                          onChooseZone: notifier.chooseZone,
                          onPickSeat: notifier.pickSlot,
                          onSeeTomorrow: () => notifier.setDateIndex(1),
                          onShowRooms: () => notifier.setType(ResourceType.room),
                        )
                      : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                itemCount: resources.length,
                itemBuilder: (context, i) {
                  final r = resources[i];
                  return Card(child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.name, style: Theme.of(context).textTheme.titleSmall),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final slot in kTimeSlots)
                          if (r.takenSlotsToday.contains(slot) || slotHasPassed(flow.dateIndex, slot, now: now))
                            Chip(label: Text(slot), backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest)
                          else
                            ChoiceChip(
                              label: Text(slot),
                              selected: flow.selectedResource?.id == r.id && flow.selectedSlot == slot,
                              onSelected: (_) => notifier.pickSlot(r, slot),
                            ),
                      ]),
                    ]),
                  ));
                },
              ),
            )),
      // A time alone is no pick on the Seats tab: its bar waits for a desk.
      if (flow.type == ResourceType.seat && _seatPickStands(flow, resourcesAsync.value, now))
        _seatBar(context, flow, notifier)
      else if (flow.type == ResourceType.room && flow.selectedSlot != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Expanded(child: Text('${flow.selectedResource?.name}\n${_dateLabel(flow.dateIndex)} · ${flow.selectedSlot}')),
            FilledButton(onPressed: notifier.goToConfirm, child: const Text('Continue')),
          ]),
        ),
    ]);
  }

  /// Whether the Seats tab's pick can still be booked as the map shows it: made
  /// at the time the strip shows (not at one that has since passed), on a seat
  /// that is still free then in the seats as loaded (not one taken or taken out
  /// of service since, say after "Change slot" and a reload). A conflict
  /// alternative is booked at the server's own window, so it stands as it was.
  bool _seatPickStands(BookingFlowState flow, List<Resource>? seats, DateTime now) {
    final pick = flow.selectedResource;
    final slot = flow.selectedSlot;
    if (pick == null || slot == null) return false;
    if (flow.alternativeWindow != null) return true;
    if (seats == null || slot != shownSlot(seats, flow.dateIndex, slot, now: now)) return false;
    final seat = seats.where((s) => s.id == pick.id).firstOrNull;
    return seat != null && isFreeAt(seat, slot);
  }

  /// The Seats tab's bar once a desk is picked: "Reading Room A · Desk 14" over
  /// "Today · 3:00 PM to 4:00 PM", and Continue to the confirm step.
  Widget _seatBar(BuildContext context, BookingFlowState flow, BookingFlowController notifier) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('seatBar'),
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_deskLine(flow.selectedResource!), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text('${_dateLabel(flow.dateIndex)} · ${_slotRange(flow)}'),
              ]),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: notifier.goToConfirm, child: const Text('Continue')),
          ]),
        ),
      ),
    );
  }

  /// "Reading Room A · Desk 14": the zone and the desk's number, or the seat's
  /// own name when it has no zone (a seat not on a map, or a conflict
  /// alternative, which carries no location) or no number ("Window Nook", not
  /// "Reading Room A · Desk Win").
  String _deskLine(Resource seat) {
    final zone = seat.location;
    if (zone == null || zone.trim().isEmpty || !RegExp(r'\d').hasMatch(seat.name)) return seat.name;
    return '$zone · Desk ${deskLabel(seat.name)}';
  }

  /// "3:00 PM to 4:00 PM". A conflict alternative is booked at the server's own
  /// window, so that window is what the bar shows.
  String _slotRange(BookingFlowState flow) {
    final window = flow.alternativeWindow;
    if (window != null) return '${clockLabel(window.start)} to ${clockLabel(window.end)}';
    final slot = flow.selectedSlot!;
    return kSlotHours.containsKey(slot) ? '$slot to ${slotEndLabel(slot)}' : slot;
  }

  Widget _noneFree(ResourceType type, BookingFlowController notifier) {
    final rooms = type == ResourceType.room;
    return EmptyState(
      icon: Icons.event_busy,
      title: rooms ? 'No rooms free on this date' : 'No seats free on this date',
      body: rooms ? 'Try another day, or look at individual seats instead.' : 'Try another day, or book a group room instead.',
      actionLabel: rooms ? 'Show Seats' : 'Show Rooms',
      onAction: () => notifier.setType(rooms ? ResourceType.seat : ResourceType.room),
    );
  }

  Widget _buildConfirm(BuildContext context, WidgetRef ref, BookingFlowState flow, BookingFlowController notifier) {
    final result = flow.result;
    if (result != null) {
      final requested = result.status == BookingStatus.requested;
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(requested ? Icons.schedule : Icons.check_circle, size: 56),
          const SizedBox(height: 10),
          Text(requested ? 'Request sent' : 'Booked', style: Theme.of(context).textTheme.titleLarge),
          Text('${flow.selectedResource?.name}, ${_dateLabel(flow.dateIndex)} · ${flow.selectedSlot}'),
          if (requested) ...[
            const SizedBox(height: 8),
            Text(
              "We'll hold the slot until ${dayTimeLabel(result.expiresAt ?? result.startTime.add(kCheckInGracePeriod), now: ref.read(clockProvider)())}. Check My Bookings for the librarian's answer.",
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
              onPressed: () {
                notifier.reset();
                context.go('/bookings');
              },
              child: const Text('View My Bookings')),
        ]),
      ));
    }
    if (flow.conflictAlternatives != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('That slot was just taken', style: Theme.of(context).textTheme.titleMedium),
          if (flow.conflictAlternatives!.isEmpty)
            const Text('Nothing similar is free right now. Try another time or day.')
          else
            const Text("Someone booked it a moment before you confirmed. Here's what's still open:"),
          const SizedBox(height: 12),
          for (final alt in flow.conflictAlternatives!)
            Card(child: ListTile(
              title: Text(alt.resourceName),
              subtitle: Text('${_dateLabel(flow.dateIndex)} · ${alt.timeSlot}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => notifier.pickAlternative(alt),
            )),
          // Back to the map at the same time, without the refused desk. Rooms keep
          // their pick, as they always have.
          TextButton(
            onPressed: () => notifier.backToPicker(clearDesk: flow.type == ResourceType.seat),
            child: const Text('Choose a different slot myself'),
          ),
        ]),
      );
    }
    // Rooms wait for a librarian, so their confirm step asks rather than books.
    final room = flow.selectedResource?.type == ResourceType.room;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(room ? 'Confirm your request' : 'Confirm your booking', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('${flow.selectedResource?.name}\n${_dateLabel(flow.dateIndex)} · ${flow.selectedSlot}'),
        )),
        const SizedBox(height: 12),
        Text(room
            ? 'A librarian approves room bookings. If none does before your 15-minute grace period ends, the request expires.'
            : 'Check in within 15 minutes of your start time, or the slot is released automatically for someone else.'),
        const SizedBox(height: 16),
        // A conflict is handled in the flow itself; any other refusal (say, the
        // slot passed while the user sat here) is reported as a toast.
        FilledButton(
          onPressed: () => ref.read(uiControllerProvider.notifier).attempt(notifier.confirm),
          child: Text(room ? 'Send request' : 'Confirm booking'),
        ),
        TextButton(onPressed: notifier.backToPicker, child: const Text('Change slot')),
      ]),
    );
  }
}
