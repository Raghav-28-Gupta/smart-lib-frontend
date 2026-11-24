// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fine.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FineDispute _$FineDisputeFromJson(Map<String, dynamic> json) => FineDispute(
      status: $enumDecode(_$DisputeStatusEnumMap, json['status'],
          unknownValue: DisputeStatus.unknown),
      note: json['note'] as String?,
    );

const _$DisputeStatusEnumMap = {
  DisputeStatus.open: 'open',
  DisputeStatus.waived: 'waived',
  DisputeStatus.adjusted: 'adjusted',
  DisputeStatus.upheld: 'upheld',
  DisputeStatus.unknown: 'unknown',
};

Fine _$FineFromJson(Map<String, dynamic> json) => Fine(
      id: json['id'] as String,
      reason: $enumDecode(_$FineReasonEnumMap, json['reason'],
          unknownValue: FineReason.unknown),
      item: json['item'] as String,
      amount: (json['amount'] as num).toDouble(),
      originalAmount: (json['originalAmount'] as num).toDouble(),
      status: $enumDecode(_$FineStatusEnumMap, json['status'],
          unknownValue: FineStatus.unknown),
      date: localDateTime(json['date'] as String),
      note: json['note'] as String?,
      dispute: json['dispute'] == null
          ? null
          : FineDispute.fromJson(json['dispute'] as Map<String, dynamic>),
    );

const _$FineReasonEnumMap = {
  FineReason.overdue: 'overdue',
  FineReason.noShow: 'no_show',
  FineReason.lost: 'lost',
  FineReason.unknown: 'unknown',
};

const _$FineStatusEnumMap = {
  FineStatus.outstanding: 'outstanding',
  FineStatus.adjusted: 'adjusted',
  FineStatus.paid: 'paid',
  FineStatus.waived: 'waived',
  FineStatus.unknown: 'unknown',
};

FinesSummary _$FinesSummaryFromJson(Map<String, dynamic> json) => FinesSummary(
      fines: (json['fines'] as List<dynamic>)
          .map((e) => Fine.fromJson(e as Map<String, dynamic>))
          .toList(),
      outstandingTotal: (json['outstandingTotal'] as num).toDouble(),
    );
