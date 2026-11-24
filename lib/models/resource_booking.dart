import 'package:json_annotation/json_annotation.dart';
import '../core/time_format.dart';
import 'json_converters.dart';
import 'resource.dart';
export 'resource.dart';

part 'resource_booking.g.dart';

/// Wire values are the backend's `frontendStatus` strings, which already use
/// these exact names. 'released' is computed server-side at read time (grace
/// window elapsed without check-in) -- it's never persisted. A room booking
/// is 'requested' until a librarian decides; 'declined' and 'expired' are its
/// two unhappy endings. [cancelledByLibrary] is a booking a librarian cancelled
/// (the student's own cancel never appears in the list). [unknown] stands in
/// for a status this version doesn't know, so one new value never fails the
/// whole list.
enum BookingStatus { upcomingFar, inWindow, checkedIn, released, requested, declined, expired, cancelledByLibrary, unknown }

/// What a student can say is wrong with a seat or room they booked. These are the
/// three categories `POST /reports` takes for a resource (`not_working`, `dirty`,
/// `other`); the copy categories are offered only when a book is returned.
enum ResourceReportCategory {
  notWorking('not_working'),
  dirty('dirty'),
  other('other');

  const ResourceReportCategory(this.wireName);

  /// How the server spells it.
  final String wireName;
}

/// How long after its start a booking can still be checked into. Mirrors
/// GRACE_PERIOD_MINUTES in backend/src/config/constants.ts.
const kCheckInGracePeriod = Duration(minutes: 15);

// Order the time-driven statuses move through. checkedIn and cancelledByLibrary
// are outside it: only a check-in or a librarian reaches them, never the clock.
const _progress = [BookingStatus.upcomingFar, BookingStatus.inWindow, BookingStatus.released];

@JsonSerializable(createToJson: false)
class ResourceBooking {
  const ResourceBooking({
    required this.id,
    required this.resourceName,
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.graceRemainingSeconds = 0,
    this.expiresAt,
    this.declineReason,
    this.cancelReason,
    this.movedFrom,
    this.resourceId = '',
    this.canReport = false,
    this.reportOpen = false,
  });

  factory ResourceBooking.fromJson(Map<String, dynamic> json) => _$ResourceBookingFromJson(json);

  final String id;

  /// The seat or room booked: what a report of it names. Empty from a server that
  /// predates reports, which never marks a booking `canReport` either.
  @JsonKey(defaultValue: '')
  final String resourceId;
  final String resourceName;

  @JsonKey(name: 'resourceType')
  final ResourceType type;

  @JsonKey(fromJson: localDateTime)
  final DateTime startTime;

  @JsonKey(fromJson: localDateTime)
  final DateTime endTime;

  // `status` on the wire is the raw DB value ('booked', 'checked_in', ...);
  // the UI's four states come from `frontendStatus`.
  @JsonKey(name: 'frontendStatus', unknownEnumValue: BookingStatus.unknown)
  final BookingStatus status;

  final int graceRemainingSeconds;

  /// A room request's deadline: its start plus the grace period. Null otherwise.
  @JsonKey(fromJson: localDateTimeOrNull)
  final DateTime? expiresAt;

  /// Set only on a declined request, and only if the librarian gave one.
  final String? declineReason;

  /// Set only on a booking the library cancelled, and only if the librarian
  /// gave a reason.
  final String? cancelReason;

  /// The name of the resource a librarian moved this booking off. The server
  /// sends it for a week after the move and null otherwise.
  final String? movedFrom;

  /// This booking entitles the student to report its seat or room (a booking that
  /// started within the last week or starts within a day, which they have not yet
  /// reported). The server decides; the app only offers the button.
  @JsonKey(defaultValue: false)
  final bool canReport;

  /// The student has an open report on this booking's resource, so the card reads
  /// "Reported". True for every booking of theirs on that resource.
  @JsonKey(defaultValue: false)
  final bool reportOpen;

  /// '3:00 – 5:00 PM'. Derived from the real times rather than stored, so it
  /// can't disagree with them -- and it renders bookings that don't start
  /// on the hour, which a lookup into kTimeSlots could not.
  String get timeSlot => timeRangeLabel(startTime, endTime);

  /// This booking as of [now], computed the way the server computes it at read
  /// time (bookingService.ts computeWindow): upcoming before the start, then
  /// a [kCheckInGracePeriod] check-in window, then released.
  ///
  /// The bookings list isn't refetched while the app is open, so without
  /// this a booking made in advance would never become checkable. Grace is
  /// recomputed from the start time rather than decremented, so a timer that
  /// stalls in the background can't leave extra time on the clock. And it
  /// only ever moves forward: if the device clock runs behind the server's,
  /// a booking the server already opened stays open.
  ResourceBooking advancedTo(DateTime now) {
    if (!_progress.contains(status)) return this;
    final graceEnd = startTime.add(kCheckInGracePeriod);
    final BookingStatus computed;
    if (now.isBefore(startTime)) {
      computed = BookingStatus.upcomingFar;
    } else if (!now.isAfter(graceEnd)) {
      computed = BookingStatus.inWindow;
    } else {
      computed = BookingStatus.released;
    }
    final next = _progress.indexOf(computed) > _progress.indexOf(status) ? computed : status;
    return copyWith(
      status: next,
      graceRemainingSeconds: next == BookingStatus.inWindow ? graceEnd.difference(now).inSeconds.clamp(0, kCheckInGracePeriod.inSeconds) : 0,
    );
  }

  ResourceBooking copyWith({BookingStatus? status, int? graceRemainingSeconds, bool? canReport, bool? reportOpen}) =>
      ResourceBooking(
        id: id,
        resourceId: resourceId,
        resourceName: resourceName,
        type: type,
        startTime: startTime,
        endTime: endTime,
        status: status ?? this.status,
        graceRemainingSeconds:
            graceRemainingSeconds ?? this.graceRemainingSeconds,
        expiresAt: expiresAt,
        declineReason: declineReason,
        cancelReason: cancelReason,
        movedFrom: movedFrom,
        canReport: canReport ?? this.canReport,
        reportOpen: reportOpen ?? this.reportOpen,
      );
}
