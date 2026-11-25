// lib/features/bookings/bookings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_exception.dart';
import '../../core/clock.dart';
import '../../core/time_format.dart';
import '../../core/ui/ui_controller.dart';
import '../../models/resource_booking.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/note_field.dart';
import '../../widgets/pending_refresh.dart';
import '../notices/notices_controller.dart';
import '../notices/notices_section.dart';
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
      _refreshOnOpen();
    });
  }

  /// The lists were loaded when the student first needed them (the bookings usually on
  /// Home), so they can predate a librarian's cancel or move, or a notice the library
  /// wrote (a reminder, a recorded no-show, the answer to a dispute). Each time this screen
  /// opens it asks the server once for each, quietly: a failure keeps what is on screen.
  /// A list still loading is itself that fresh fetch, so only that one is skipped (the
  /// notices may be loaded long before the bookings, or the other way round). The notices
  /// are a list of their own and never delay or replace the bookings. Each visit to the tab
  /// builds a new screen (the tabs are a plain ShellRoute), so this runs on every visit.
  void _refreshOnOpen() {
    if (!mounted) return;
    if (!ref.read(bookingsControllerProvider).isLoading) {
      ref.read(bookingsControllerProvider.notifier).refreshQuietly();
    }
    _refreshNoticesQuietly();
  }

  /// The notices' quiet refresh, on open and on every tick of the pending-request re-check
  /// (a "starts soon" reminder is written up to 30 minutes before the start, while the student
  /// may be waiting right here). Through the per-user controller, which joins a fetch in flight
  /// (the open and the tick of its first frame share one request) and keeps the list when the
  /// request fails. Skipped while the notices are loading: that load is itself the fresh fetch.
  void _refreshNoticesQuietly() {
    if (!ref.read(noticesControllerProvider).isLoading) {
      ref.read(noticesControllerProvider.notifier).refreshQuietly();
    }
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

  /// Under the status: "Reported" once the student has an open report on this seat or
  /// room, else a **Report a problem** button when the server says this booking
  /// entitles them to one. Nothing for any other booking. Several cards say the same
  /// words, so the button's label for a screen reader names the seat or room.
  Widget _reportLine(ResourceBooking b) {
    if (b.reportOpen) return const Text('Reported', style: TextStyle(fontStyle: FontStyle.italic));
    if (!b.canReport) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () => _askToReport(context, b),
        child: Semantics(
          label: 'Report a problem with ${b.resourceName}',
          excludeSemantics: true,
          child: const Text('Report a problem'),
        ),
      ),
    );
  }

  /// What a released booking says. The server lists a recorded no-show as released too (an
  /// older app shows the plain text for it), and tells the two apart with `noShow`: null is
  /// a plain release, which keeps its old text. A no-show reads "Missed. A no-show was
  /// recorded." with a **Dispute** button while the server says it may still be disputed
  /// (`canDispute`: no dispute yet and inside the 7 days; the app never works that out).
  /// Once disputed the button is gone and a line says where the dispute stands, below the
  /// missed line so the student is told WHAT is under review or stands: "Under review" while
  /// it waits (and for a status this version doesn't know), "No-show stands" once a librarian
  /// kept it. When a librarian overturned it, it is no longer a no-show, so the card says only
  /// "No-show removed". An answer carries the librarian's note on its own line when there is
  /// one. Several cards say "Dispute", so the button's label for a screen reader names the
  /// seat or room.
  List<Widget> _releasedLines(ResourceBooking b) {
    final noShow = b.noShow;
    if (noShow == null) return [const Text('This booking was released after the grace period.')];
    const missed = Text('Missed. A no-show was recorded.');
    final dispute = noShow.dispute;
    if (dispute == null) {
      return [
        missed,
        if (noShow.canDispute)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _askToDispute(context, b.id),
              child: Semantics(
                label: 'Dispute the no-show for ${b.resourceName}',
                excludeSemantics: true,
                child: const Text('Dispute'),
              ),
            ),
          ),
      ];
    }
    return switch (dispute.status) {
      NoShowDisputeStatus.open || NoShowDisputeStatus.unknown => [
          missed,
          const Text('Under review', style: TextStyle(fontStyle: FontStyle.italic)),
        ],
      NoShowDisputeStatus.overturned => _noShowAnswer('No-show removed', dispute.note),
      NoShowDisputeStatus.upheld => [missed, ..._noShowAnswer('No-show stands', dispute.note)],
    };
  }

  List<Widget> _noShowAnswer(String answer, String? note) => [
        Text(answer, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (note != null && note.isNotEmpty) Text(note),
      ];

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
        // Nothing to act on: no Check In, and no Cancel for a booking that is already cancelled.
        BookingStatus.cancelledByLibrary => [
            Text(b.cancelReason == null ? 'Cancelled by the library' : 'Cancelled by the library — ${b.cancelReason}'),
          ],
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
        BookingStatus.released => _releasedLines(b),
        BookingStatus.unknown => [const Text("Update the app to see this item's status.")],
      };

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(bookingsControllerProvider);
    final waiting = bookings.value?.any((b) => b.status == BookingStatus.requested) ?? false;
    return PendingRefresh(
      active: waiting,
      // A librarian's answer shows up within half a minute, and so does a new notice.
      onTick: () {
        ref.read(bookingsControllerProvider.notifier).refreshQuietly();
        _refreshNoticesQuietly();
      },
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
              itemCount: items.length + 1,
              itemBuilder: (context, i) {
                // The library's notices about a booking, above the first one. Absent when
                // there are none, while they load and when they fail to load.
                if (i == 0) return const NoticesSection(kinds: bookingNoticeKinds);
                final b = items[i - 1];
                return Card(child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.resourceName, style: Theme.of(context).textTheme.titleSmall),
                    Text(b.timeSlot),
                    if (b.movedFrom != null) Text('Moved from ${b.movedFrom} by the library'),
                    ..._statusLines(b),
                    _reportLine(b),
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

String _categoryLabel(ResourceReportCategory category) => switch (category) {
      ResourceReportCategory.notWorking => 'Not working',
      ResourceReportCategory.dirty => 'Dirty',
      ResourceReportCategory.other => 'Other',
    };

Future<void> _askToReport(BuildContext context, ResourceBooking booking) =>
    showDialog<void>(context: context, builder: (_) => _ReportDialog(booking: booking));

Future<void> _askToDispute(BuildContext context, String bookingId) =>
    showDialog<void>(context: context, builder: (_) => _NoShowDisputeDialog(bookingId: bookingId));

/// "Report a problem" with a seat or room: what is wrong (none is chosen for the
/// student) and a note, which Other requires. Send is off until a category is chosen,
/// the trimmed note fits the limit ([noteTooLong]: the server's count, shown by the
/// shared [NoteField]), and the note is there for Other; a note that is only
/// spaces is no note and goes as none. On a refusal the dialog stays with the student's
/// choices so they can send again or cancel; while the answer is awaited Send is off, so
/// a second tap can't send a second report.
class _ReportDialog extends ConsumerStatefulWidget {
  const _ReportDialog({required this.booking});

  final ResourceBooking booking;

  @override
  ConsumerState<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<_ReportDialog> {
  final _note = TextEditingController();
  ResourceReportCategory? _category;
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _trimmedNote => _note.text.trim();

  bool get _valid {
    final category = _category;
    if (category == null || _sending) return false;
    final note = _trimmedNote;
    if (noteTooLong(note)) return false;
    return category != ResourceReportCategory.other || note.isNotEmpty;
  }

  Future<void> _send() async {
    final category = _category;
    if (category == null || !_valid) return;
    final note = _trimmedNote;
    final booking = widget.booking;
    setState(() => _sending = true);
    final failure = await ref.read(uiControllerProvider.notifier).attempt(
          () => ref.read(bookingsControllerProvider.notifier).reportProblem(booking, category, note.isEmpty ? null : note),
          success: 'Thanks, the library has your report.',
        );
    if (!mounted) return;
    // An expired session is on its way to the login screen, which says so, and the
    // dialog must not be left on top of it. Any other refusal was toasted by
    // `attempt` and the dialog stays, with the student's choices.
    if (failure == null || failure is UnauthorizedException) {
      Navigator.of(context).pop();
    } else {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = _category;
    return AlertDialog(
      title: const Text('Report a problem'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.booking.resourceName, style: Theme.of(context).textTheme.titleSmall),
          RadioGroup<ResourceReportCategory>(
            groupValue: category,
            onChanged: (chosen) {
              if (!_sending) setState(() => _category = chosen);
            },
            child: Column(
              children: [
                for (final option in ResourceReportCategory.values)
                  RadioListTile<ResourceReportCategory>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: option,
                    title: Text(_categoryLabel(option)),
                  ),
              ],
            ),
          ),
          NoteField(
            controller: _note,
            enabled: !_sending,
            label: category == ResourceReportCategory.other ? 'Note (required)' : 'Note (optional)',
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _valid ? _send : null, child: const Text('Send')),
      ],
    );
  }
}

/// "Dispute this no-show": one required reason, sent once (the fine dispute's dialog, for a
/// booking). The reason is limited as the server limits it ([noteTooLong], shown by the
/// shared [NoteField]): Send is off while it is empty or over 300 UTF-16 code units
/// trimmed, and what the student typed is never cut. On a refusal the dialog stays with
/// the student's words so they can send them again or cancel; while the answer is awaited
/// Send is off, so a second tap can't send a second dispute.
class _NoShowDisputeDialog extends ConsumerStatefulWidget {
  const _NoShowDisputeDialog({required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<_NoShowDisputeDialog> createState() => _NoShowDisputeDialogState();
}

class _NoShowDisputeDialogState extends ConsumerState<_NoShowDisputeDialog> {
  final _reason = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canSend {
    final reason = _reason.text.trim();
    return reason.isNotEmpty && !noteTooLong(reason) && !_sending;
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final reason = _reason.text.trim();
    setState(() => _sending = true);
    final bookingId = widget.bookingId;
    final failure = await ref
        .read(uiControllerProvider.notifier)
        .attempt(() => ref.read(bookingsControllerProvider.notifier).disputeNoShow(bookingId, reason), success: 'Dispute sent.');
    if (!mounted) return;
    // An expired session is on its way to the login screen, which says so, and the
    // dialog must not be left on top of it. Any other refusal was toasted by
    // `attempt` and the dialog stays, with the student's text.
    if (failure == null || failure is UnauthorizedException) {
      Navigator.of(context).pop();
    } else {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dispute this no-show'),
      scrollable: true,
      content: NoteField(
        controller: _reason,
        label: 'Why do you think this no-show is wrong?',
        enabled: !_sending,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _canSend ? _send : null, child: const Text('Send')),
      ],
    );
  }
}
