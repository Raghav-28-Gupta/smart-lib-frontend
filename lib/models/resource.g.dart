// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resource.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Resource _$ResourceFromJson(Map<String, dynamic> json) => Resource(
      id: json['id'] as String,
      name: json['name'] as String,
      type: $enumDecode(_$ResourceTypeEnumMap, json['type']),
      takenSlotsToday: (json['takenSlotsToday'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      location: json['location'] as String?,
      row: (json['row'] as num?)?.toInt(),
      column: (json['column'] as num?)?.toInt(),
      zoneFront: json['zoneFront'] as String?,
      status: $enumDecodeNullable(_$ResourceStatusEnumMap, json['status'],
              unknownValue: ResourceStatus.available) ??
          ResourceStatus.available,
    );

const _$ResourceTypeEnumMap = {
  ResourceType.seat: 'seat',
  ResourceType.room: 'room',
};

const _$ResourceStatusEnumMap = {
  ResourceStatus.available: 'available',
  ResourceStatus.offline: 'offline',
};
