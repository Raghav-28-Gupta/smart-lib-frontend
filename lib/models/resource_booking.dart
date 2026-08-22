import 'resource.dart';
export 'resource.dart';

enum BookingStatus { upcomingFar, inWindow, checkedIn, released }

class ResourceBooking {
  const ResourceBooking({
    required this.id,
    required this.resourceName,
    required this.type,
    required this.startTime,
    required this.timeSlot,
    required this.status,
    this.graceRemainingSeconds = 0,
  });

  final String id;
  final String resourceName;
  final ResourceType type;
  final DateTime startTime;
  final String timeSlot;
  final BookingStatus status;
  final int graceRemainingSeconds;

  ResourceBooking copyWith(
          {BookingStatus? status, int? graceRemainingSeconds}) =>
      ResourceBooking(
        id: id,
        resourceName: resourceName,
        type: type,
        startTime: startTime,
        timeSlot: timeSlot,
        status: status ?? this.status,
        graceRemainingSeconds:
            graceRemainingSeconds ?? this.graceRemainingSeconds,
      );
}
