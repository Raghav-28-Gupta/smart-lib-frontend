// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'loan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Loan _$LoanFromJson(Map<String, dynamic> json) => Loan(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      dueDate: localDateTime(json['dueAt'] as String),
      status: $enumDecode(_$LoanStatusEnumMap, json['frontendStatus']),
      fineAmount: (json['fineAmount'] as num).toDouble(),
      canRenew: json['canRenew'] as bool,
      blockedReason: json['blockedReason'] as String?,
    );

const _$LoanStatusEnumMap = {
  LoanStatus.normal: 'normal',
  LoanStatus.overdue: 'overdue',
};
