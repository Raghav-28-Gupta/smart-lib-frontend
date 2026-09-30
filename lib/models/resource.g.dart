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
    );

const _$ResourceTypeEnumMap = {
  ResourceType.seat: 'seat',
  ResourceType.room: 'room',
};
