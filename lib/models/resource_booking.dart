import 'package:json_annotation/json_annotation.dart';
import '../core/time_format.dart';
import 'json_converters.dart';
import 'resource.dart';
export 'resource.dart';

part 'resource_booking.g.dart';

/// Wire values are the backend's `frontendStatus` strings, which already use
/// these exact names. 'released' is computed server-side at read time (grace
/// window elapsed without check-in) -- it's never persisted.
enum BookingStatus { upcomingFar, inWindow, checkedIn, released }

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
  @JsonKey(name: 'frontendStatus')
  final BookingStatus status;

  final int graceRemainingSeconds;

  /// '3:00 – 5:00 PM'. Derived from the real times rather than stored, so it
  /// can't disagree with them -- and it renders bookings that don't start
  /// on the hour, which a lookup into kTimeSlots could not.
  String get timeSlot => timeRangeLabel(startTime, endTime);

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
      );
}
