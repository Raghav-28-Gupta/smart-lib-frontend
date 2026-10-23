// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'borrow_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BorrowRequest _$BorrowRequestFromJson(Map<String, dynamic> json) =>
    BorrowRequest(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      bookTitle: json['bookTitle'] as String,
      status: $enumDecode(_$BorrowRequestStatusEnumMap, json['status'],
          unknownValue: BorrowRequestStatus.unknown),
      requestedAt: localDateTime(json['requestedAt'] as String),
      expiresAt: localDateTime(json['expiresAt'] as String),
      decidedAt: localDateTimeOrNull(json['decidedAt'] as String?),
      declineReason: json['declineReason'] as String?,
    );

const _$BorrowRequestStatusEnumMap = {
  BorrowRequestStatus.pending: 'pending',
  BorrowRequestStatus.approved: 'approved',
  BorrowRequestStatus.declined: 'declined',
  BorrowRequestStatus.expired: 'expired',
  BorrowRequestStatus.cancelled: 'cancelled',
  BorrowRequestStatus.unknown: 'unknown',
};
