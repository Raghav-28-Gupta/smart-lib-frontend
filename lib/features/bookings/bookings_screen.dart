// lib/features/bookings/bookings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/clock.dart';
import '../../core/time_format.dart';
import '../../core/ui/ui_controller.dart';
import '../../models/resource_booking.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pending_refresh.dart';
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

  Widget _cancelButton(ResourceBooking b) => Expanded(child: TextButton(
        onPressed: () => ref.read(uiControllerProvider.notifier).askCancelBooking(b.id),
        child: const Text('Cancel'),
      ));

  List<Widget> _statusLines(ResourceBooking b) => switch (b.status) {
        BookingStatus.requested => [
            Text('Waiting for a librarian · held until '
                '${dayTimeLabel(b.expiresAt ?? b.startTime.add(kCheckInGracePeriod), now: ref.read(clockProvider)())}'),
            Row(children: [_cancelButton(b)]),
          ],
        BookingStatus.declined => [
            Text(b.declineReason == null ? 'Declined by the library' : 'Declined — ${b.declineReason}'),
          ],
        BookingStatus.expired => [const Text('Expired — no librarian approved it in time')],
        BookingStatus.upcomingFar => [
            // Matches the server: check-in opens AT the start time, for
            // kCheckInGracePeriod -- not before it.
            Text('Starts ${_startsIn(b.startTime)} · check-in opens at the start time'),
            Row(children: [
              const Expanded(child: OutlinedButton(onPressed: null, child: Text('Check In'))),
              const SizedBox(width: 8),
              _cancelButton(b),
            ]),
          ],
        BookingStatus.inWindow => [
            Text('Check in within ${_graceLabel(b.graceRemainingSeconds)}'),
            Row(children: [
              Expanded(child: FilledButton(
                onPressed: () => ref.read(uiControllerProvider.notifier).attempt(() => ref.read(bookingsControllerProvider.notifier).checkIn(b.id)),
                child: const Text('Check In'),
              )),
              const SizedBox(width: 8),
              _cancelButton(b),
            ]),
          ],
        BookingStatus.checkedIn => [const Text('Enjoy your session.')],
        BookingStatus.released => [const Text('This booking was released after the grace period.')],
        BookingStatus.unknown => [const Text("Update the app to see this item's status.")],
      };

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(bookingsControllerProvider);
    final waiting = bookings.value?.any((b) => b.status == BookingStatus.requested) ?? false;
    return PendingRefresh(
      active: waiting,
      // A librarian's answer shows up within half a minute.
      onTick: () => ref.read(bookingsControllerProvider.notifier).refreshQuietly(),
      child: Scaffold(
        appBar: AppBar(title: const Text('My Bookings'), actions: [
          TextButton(onPressed: () => context.push('/booking/new'), child: const Text('New')),
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
                actionLabel: 'Book a resource', onAction: () => context.push('/booking/new'),
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
                    ..._statusLines(b),
                  ]),
                ));
              },
            );
          },
        ),
      ),
    );
  }
}
