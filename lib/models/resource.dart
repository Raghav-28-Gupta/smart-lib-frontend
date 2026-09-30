import 'package:json_annotation/json_annotation.dart';

part 'resource.g.dart';

/// Wire values are the enum names: 'seat' / 'room'.
enum ResourceType { seat, room }

// The backend also sends `location` and `capacity`; no student screen shows
// them, so they aren't mapped.
@JsonSerializable(createToJson: false)
class Resource {
  const Resource(
      {required this.id,
      required this.name,
      required this.type,
      required this.takenSlotsToday});

  factory Resource.fromJson(Map<String, dynamic> json) => _$ResourceFromJson(json);

  final String id;
  final String name;
  final ResourceType type;

  /// Slot labels from the kTimeSlots vocabulary, computed by the server for
  /// the requested date.
  final List<String> takenSlotsToday;
}
