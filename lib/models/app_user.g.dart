// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppUser _$AppUserFromJson(Map<String, dynamic> json) => AppUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      roll: json['roll'] as String,
      role: $enumDecodeNullable(_$UserRoleEnumMap, json['role']) ??
          UserRole.student,
    );

const _$UserRoleEnumMap = {
  UserRole.student: 'student',
  UserRole.admin: 'admin',
};
