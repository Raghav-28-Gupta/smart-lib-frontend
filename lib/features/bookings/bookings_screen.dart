// lib/features/bookings/bookings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ui/ui_controller.dart';
import '../../models/resource_booking.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_skeleton.dart';
import 'bookings_controller.dart';

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});
  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(uiControllerProvider.notifier).onConfirmCancelBooking =
          (id) => ref.read(bookingsControllerProvider.notifier).cancel(id);
    });
  }

  String _startsIn(DateTime start) {
    final d = start.difference(DateTime.now());
    if (d.inMinutes <= 0) return 'now';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? 'in ${h}h ${m}m' : 'in ${m}m';
  }

  String _graceLabel(int seconds) {
    final mm = seconds ~/ 60;
    final ss = seconds % 60;
    return '$mm:${ss < 10 ? '0' : ''}$ss';
  }

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(bookingsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings'), actions: [
        TextButton(onPressed: () {}, child: const Text('New')), // wired to go_router in Task 13
      ]),
      body: bookings.when(
        loading: () => ListView(padding: const EdgeInsets.all(20), children: const [
          LoadingSkeleton(height: 90), SizedBox(height: 10), LoadingSkeleton(height: 90),
        ]),
        error: (e, st) => ErrorState(title: "Couldn't load your bookings", onRetry: () => ref.invalidate(bookingsControllerProvider)),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.event_busy, title: 'No upcoming bookings',
              body: 'Reserve a seat or room to get started.',
              actionLabel: 'Book a resource', onAction: () {},
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final b = items[i];
              return Card(child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.resourceName, style: Theme.of(context).textTheme.titleSmall),
                  Text(b.timeSlot),
                  if (b.status == BookingStatus.upcomingFar) ...[
                    Text('Starts ${_startsIn(b.startTime)} · check-in opens 10 min before'),
                    Row(children: [
                      const Expanded(child: OutlinedButton(onPressed: null, child: Text('Check In'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextButton(
                        onPressed: () => ref.read(uiControllerProvider.notifier).askCancelBooking(b.id),
                        child: const Text('Cancel'),
                      )),
                    ]),
                  ] else if (b.status == BookingStatus.inWindow) ...[
                    Text('Check in within ${_graceLabel(b.graceRemainingSeconds)}'),
                    Row(children: [
                      Expanded(child: FilledButton(
                        onPressed: () => ref.read(bookingsControllerProvider.notifier).checkIn(b.id),
                        child: const Text('Check In'),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: TextButton(
                        onPressed: () => ref.read(uiControllerProvider.notifier).askCancelBooking(b.id),
                        child: const Text('Cancel'),
                      )),
                    ]),
                  ] else if (b.status == BookingStatus.checkedIn)
                    const Text('Enjoy your session.')
                  else
                    const Text('This booking was released after the grace period.'),
                ]),
              ));
            },
          );
        },
      ),
    );
  }
}
