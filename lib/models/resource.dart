import 'package:json_annotation/json_annotation.dart';

part 'resource.g.dart';

/// Wire values are the enum names: 'seat' / 'room'.
enum ResourceType { seat, room }

/// Wire values are the enum names. `offline` is a seat a librarian took out of
/// service: the server lists it only when asked (`includeOffline=true`), with no
/// taken slots, and nobody can book it. A value a later server adds reads as
/// `available` (see [Resource.status]).
enum ResourceStatus { available, offline }

// The backend also sends `capacity`; no student screen shows it, so it isn't mapped.
@JsonSerializable(createToJson: false)
class Resource {
  const Resource(
      {required this.id,
      required this.name,
      required this.type,
      required this.takenSlotsToday,
      this.location,
      this.row,
      this.column,
      this.zoneFront,
      this.status = ResourceStatus.available});

  factory Resource.fromJson(Map<String, dynamic> json) => _$ResourceFromJson(json);

  final String id;
  final String name;
  final ResourceType type;

  /// Slot labels from the kTimeSlots vocabulary, computed by the server for
  /// the requested date.
  final List<String> takenSlotsToday;

  /// The zone a seat belongs to ("Reading Room A"), null for a room or an
  /// older server's seat with none.
  final String? location;

  /// Where the seat stands in its zone's grid, 1-based; both null for a seat that
  /// is not on the map, and for a room. An older server sends neither.
  final int? row;
  final int? column;

  /// What the front of the seat's zone faces ("Windows"), null when unset.
  final String? zoneFront;

  /// An older server sends none, and an unknown value reads as available too, so
  /// a seat is never hidden by a status this app does not know.
  @JsonKey(defaultValue: ResourceStatus.available, unknownEnumValue: ResourceStatus.available)
  final ResourceStatus status;

  /// Whether the seat has a place on its zone's map: a row, a column and a
  /// non-blank location. The server keeps these together; this reads the same
  /// rule from what arrived.
  bool get isPlaced => row != null && column != null && (location?.trim().isNotEmpty ?? false);
}
