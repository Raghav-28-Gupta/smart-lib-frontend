// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resource_booking.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NoShowDisputeInfo _$NoShowDisputeInfoFromJson(Map<String, dynamic> json) =>
    NoShowDisputeInfo(
      status: $enumDecode(_$NoShowDisputeStatusEnumMap, json['status'],
          unknownValue: NoShowDisputeStatus.unknown),
      note: json['note'] as String?,
    );

const _$NoShowDisputeStatusEnumMap = {
  NoShowDisputeStatus.open: 'open',
  NoShowDisputeStatus.overturned: 'overturned',
  NoShowDisputeStatus.upheld: 'upheld',
  NoShowDisputeStatus.unknown: 'unknown',
};

NoShowInfo _$NoShowInfoFromJson(Map<String, dynamic> json) => NoShowInfo(
      canDispute: json['canDispute'] as bool? ?? false,
      dispute: json['dispute'] == null
          ? null
          : NoShowDisputeInfo.fromJson(json['dispute'] as Map<String, dynamic>),
    );

ResourceBooking _$ResourceBookingFromJson(Map<String, dynamic> json) =>
    ResourceBooking(
      id: json['id'] as String,
      resourceName: json['resourceName'] as String,
      type: $enumDecode(_$ResourceTypeEnumMap, json['resourceType']),
      startTime: localDateTime(json['startTime'] as String),
      endTime: localDateTime(json['endTime'] as String),
      status: $enumDecode(_$BookingStatusEnumMap, json['frontendStatus'],
          unknownValue: BookingStatus.unknown),
      graceRemainingSeconds:
          (json['graceRemainingSeconds'] as num?)?.toInt() ?? 0,
      expiresAt: localDateTimeOrNull(json['expiresAt'] as String?),
      declineReason: json['declineReason'] as String?,
      cancelReason: json['cancelReason'] as String?,
      movedFrom: json['movedFrom'] as String?,
      resourceId: json['resourceId'] as String? ?? '',
      canReport: json['canReport'] as bool? ?? false,
      reportOpen: json['reportOpen'] as bool? ?? false,
      noShow: json['noShow'] == null
          ? null
          : NoShowInfo.fromJson(json['noShow'] as Map<String, dynamic>),
    );

const _$ResourceTypeEnumMap = {
  ResourceType.seat: 'seat',
  ResourceType.room: 'room',
};

const _$BookingStatusEnumMap = {
  BookingStatus.upcomingFar: 'upcomingFar',
  BookingStatus.inWindow: 'inWindow',
  BookingStatus.checkedIn: 'checkedIn',
  BookingStatus.released: 'released',
  BookingStatus.requested: 'requested',
  BookingStatus.declined: 'declined',
  BookingStatus.expired: 'expired',
  BookingStatus.cancelledByLibrary: 'cancelledByLibrary',
  BookingStatus.unknown: 'unknown',
};
