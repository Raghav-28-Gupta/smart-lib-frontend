// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_alternative.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BookingAlternative _$BookingAlternativeFromJson(Map<String, dynamic> json) =>
    BookingAlternative(
      resourceId: json['resourceId'] as String,
      resourceName: json['resourceName'] as String,
      resourceType: $enumDecode(_$ResourceTypeEnumMap, json['resourceType']),
      startTime: localDateTime(json['startTime'] as String),
      endTime: localDateTime(json['endTime'] as String),
    );

const _$ResourceTypeEnumMap = {
  ResourceType.seat: 'seat',
  ResourceType.room: 'room',
};
