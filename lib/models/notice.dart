import 'package:json_annotation/json_annotation.dart';
import 'json_converters.dart';

part 'notice.g.dart';

/// What a library notice is about. [unknown] stands in for a kind this version
/// doesn't know, so one new kind never fails the whole list: the notice still
/// shows its title and body.
enum NoticeKind {
  @JsonValue('overdue_reminder')
  overdueReminder,
  @JsonValue('overdue_escalation')
  overdueEscalation,
  @JsonValue('dispute_outcome')
  disputeOutcome,
  @JsonValue('report_outcome')
  reportOutcome,
  @JsonValue('booking_reminder')
  bookingReminder,
  @JsonValue('no_show')
  noShow,
  @JsonValue('no_show_outcome')
  noShowOutcome,
  unknown,
}

/// One message from the library to the student, from GET /notices/me: an overdue
/// reminder, a booking's reminder or recorded no-show, or the outcome of a dispute
/// or a report. The server's text is shown as written.
@JsonSerializable(createToJson: false)
class Notice {
  const Notice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory Notice.fromJson(Map<String, dynamic> json) => _$NoticeFromJson(json);

  final String id;

  @JsonKey(unknownEnumValue: NoticeKind.unknown)
  final NoticeKind kind;

  final String title;
  final String body;

  /// When the library wrote it.
  @JsonKey(fromJson: localDateTime)
  final DateTime createdAt;
}
