// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resource_booking.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ResourceBooking _$ResourceBookingFromJson(Map<String, dynamic> json) =>
    ResourceBooking(
      id: json['id'] as String,
      resourceName: json['resourceName'] as String,
      type: $enumDecode(_$ResourceTypeEnumMap, json['resourceType']),
      startTime: localDateTime(json['startTime'] as String),
      endTime: localDateTime(json['endTime'] as String),
      status: $enumDecode(_$BookingStatusEnumMap, json['frontendStatus']),
      graceRemainingSeconds:
          (json['graceRemainingSeconds'] as num?)?.toInt() ?? 0,
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
};
