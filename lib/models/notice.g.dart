// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notice.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Notice _$NoticeFromJson(Map<String, dynamic> json) => Notice(
      id: json['id'] as String,
      kind: $enumDecode(_$NoticeKindEnumMap, json['kind'],
          unknownValue: NoticeKind.unknown),
      title: json['title'] as String,
      body: json['body'] as String,
      createdAt: localDateTime(json['createdAt'] as String),
    );

const _$NoticeKindEnumMap = {
  NoticeKind.overdueReminder: 'overdue_reminder',
  NoticeKind.overdueEscalation: 'overdue_escalation',
  NoticeKind.disputeOutcome: 'dispute_outcome',
  NoticeKind.reportOutcome: 'report_outcome',
  NoticeKind.unknown: 'unknown',
};
