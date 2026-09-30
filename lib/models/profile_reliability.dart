import 'package:json_annotation/json_annotation.dart';

part 'profile_reliability.g.dart';

/// Wire values are the enum names: 'ok' / 'miss'.
enum ActivityDot { ok, miss }

// The backend also sends a raw `score`; nothing renders it (the ring is
// driven by ringFraction, the label by tier), so it isn't mapped.
@JsonSerializable(createToJson: false)
class ProfileReliability {
  const ProfileReliability({
    required this.tier,
    required this.ringFraction,
    required this.note,
    required this.history,
  });

  factory ProfileReliability.fromJson(Map<String, dynamic> json) => _$ProfileReliabilityFromJson(json);

  final String tier;
  final double ringFraction;
  final String note;
  final List<ActivityDot> history;
}
