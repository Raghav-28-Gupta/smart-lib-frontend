// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reservation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Reservation _$ReservationFromJson(Map<String, dynamic> json) => Reservation(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      status: $enumDecode(_$ReservationStatusEnumMap, json['status']),
      queuePosition: (json['queuePosition'] as num?)?.toInt(),
      claimExpiresAt: localDateTimeOrNull(json['claimExpiresAt'] as String?),
    );

const _$ReservationStatusEnumMap = {
  ReservationStatus.waiting: 'waiting',
  ReservationStatus.held: 'fulfilled',
};
