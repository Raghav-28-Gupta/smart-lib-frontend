import 'package:json_annotation/json_annotation.dart';
import '../core/time_format.dart';
import 'json_converters.dart';
import 'resource.dart';

part 'booking_alternative.g.dart';

/// One suggestion from a POST /bookings 409: a slot that was free when the
/// server checked. Carries the server's exact window, so taking it can resend
/// those instants verbatim instead of re-deriving them from a label.
@JsonSerializable(createToJson: false)
class BookingAlternative {
  const BookingAlternative({
    required this.resourceId,
    required this.resourceName,
    required this.resourceType,
    required this.startTime,
    required this.endTime,
  });

  factory BookingAlternative.fromJson(Map<String, dynamic> json) => _$BookingAlternativeFromJson(json);

  final String resourceId;
  final String resourceName;
  final ResourceType resourceType;

  @JsonKey(fromJson: localDateTime)
  final DateTime startTime;

  @JsonKey(fromJson: localDateTime)
  final DateTime endTime;

  /// The slot-chip label, e.g. '5:00 PM'. Derived from [startTime] rather
  /// than read from the payload's own `timeSlot`, which the server formats in
  /// *its* timezone -- this one is in the user's.
  String get timeSlot => clockLabel(startTime);

  /// The Resource the booking flow selects when this alternative is taken.
  /// The 409 carries no availability grid, and the confirm screen shows
  /// none, so an empty `takenSlotsToday` is accurate rather than a stub.
  Resource toResource() => Resource(id: resourceId, name: resourceName, type: resourceType, takenSlotsToday: const []);
}
