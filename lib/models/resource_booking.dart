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
/// two unhappy endings. [unknown] stands in for a status this version doesn't
/// know, so one new value never fails the whole list.
enum BookingStatus { upcomingFar, inWindow, checkedIn, released, requested, declined, expired, unknown }

/// How long after its start a booking can still be checked into. Mirrors
/// GRACE_PERIOD_MINUTES in backend/src/config/constants.ts.
const kCheckInGracePeriod = Duration(minutes: 15);

// Order the time-driven statuses move through. checkedIn is outside it:
// only a check-in reaches it, never the clock.
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
  });

  factory ResourceBooking.fromJson(Map<String, dynamic> json) => _$ResourceBookingFromJson(json);

  final String id;
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

  ResourceBooking copyWith(
          {BookingStatus? status, int? graceRemainingSeconds}) =>
      ResourceBooking(
        id: id,
        resourceName: resourceName,
        type: type,
        startTime: startTime,
        endTime: endTime,
        status: status ?? this.status,
        graceRemainingSeconds:
            graceRemainingSeconds ?? this.graceRemainingSeconds,
        expiresAt: expiresAt,
        declineReason: declineReason,
      );
}
