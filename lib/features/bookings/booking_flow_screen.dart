// lib/features/bookings/booking_flow_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/resource.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import 'booking_flow_controller.dart';
import 'booking_repository.dart';

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
    final isEmptyCombo = flow.type == ResourceType.room && flow.dateIndex >= 2;
    final resourcesAsync = ref.watch(bookingResourcesProvider);

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
      Expanded(child: isEmptyCombo
          ? EmptyState(
              icon: Icons.event_busy,
              title: 'No rooms free on this date',
              body: 'Try another day, or look at individual seats instead.',
              actionLabel: 'Show Seats',
              onAction: () => notifier.setType(ResourceType.seat),
            )
          : resourcesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => ErrorState(title: "Couldn't load availability", onRetry: () => ref.invalidate(bookingResourcesProvider)),
              data: (resources) => ListView.builder(
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
                          if (r.takenSlotsToday.contains(slot))
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
      if (flow.selectedSlot != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Expanded(child: Text('${flow.selectedResource?.name}\n${_dateLabel(flow.dateIndex)} · ${flow.selectedSlot}')),
            FilledButton(onPressed: notifier.goToConfirm, child: const Text('Continue')),
          ]),
        ),
    ]);
  }

  Widget _buildConfirm(BuildContext context, WidgetRef ref, BookingFlowState flow, BookingFlowController notifier) {
    if (flow.result != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, size: 56),
          const SizedBox(height: 10),
          Text('Booked', style: Theme.of(context).textTheme.titleLarge),
          Text('${flow.selectedResource?.name}, ${_dateLabel(flow.dateIndex)} · ${flow.selectedSlot}'),
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
          const Text("Someone booked it a moment before you confirmed. Here's what's still open:"),
          const SizedBox(height: 12),
          for (final alt in flow.conflictAlternatives!)
            Card(child: ListTile(
              title: Text(alt.resource.name),
              subtitle: Text('${_dateLabel(flow.dateIndex)} · ${alt.timeSlot}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => notifier.pickAlternative(alt),
            )),
          TextButton(onPressed: notifier.backToPicker, child: const Text('Choose a different slot myself')),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Confirm your booking', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('${flow.selectedResource?.name}\n${_dateLabel(flow.dateIndex)} · ${flow.selectedSlot}'),
        )),
        const SizedBox(height: 12),
        const Text('Check in within 15 minutes of your start time, or the slot is released automatically for someone else.'),
        const SizedBox(height: 16),
        FilledButton(onPressed: notifier.confirm, child: const Text('Confirm booking')),
        TextButton(onPressed: notifier.backToPicker, child: const Text('Change slot')),
      ]),
    );
  }
}
