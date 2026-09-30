import 'package:json_annotation/json_annotation.dart';

part 'app_user.g.dart';

/// Mirrors the backend's `Role` enum; the wire values are the enum names.
enum UserRole { student, admin }

@JsonSerializable(createToJson: false)
class AppUser {
  const AppUser(
      {required this.id,
      required this.name,
      required this.email,
      required this.roll,
      this.role = UserRole.student});

  factory AppUser.fromJson(Map<String, dynamic> json) => _$AppUserFromJson(json);

  final String id;
  final String name;
  final String email;
  final String roll;

  /// Not used by the student app yet -- carried so the admin console can
  /// route on it later without re-capturing fixtures or re-running codegen.
  /// Defaults to the least-privileged role when absent.
  final UserRole role;
}
