// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_reliability.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProfileReliability _$ProfileReliabilityFromJson(Map<String, dynamic> json) =>
    ProfileReliability(
      tier: json['tier'] as String,
      ringFraction: (json['ringFraction'] as num).toDouble(),
      note: json['note'] as String,
      history: (json['history'] as List<dynamic>)
          .map((e) => $enumDecode(_$ActivityDotEnumMap, e))
          .toList(),
    );

const _$ActivityDotEnumMap = {
  ActivityDot.ok: 'ok',
  ActivityDot.miss: 'miss',
};
