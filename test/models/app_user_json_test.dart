// test/models/app_user_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/models/app_user.dart';
import '../support/fixtures.dart';

void main() {
  test('parses GET /auth/me', () {
    final user = AppUser.fromJson(fixture('auth_me') as Map<String, dynamic>);
    expect(user.id, 'u1');
    expect(user.name, 'Aditi Sharma');
    expect(user.email, 'aditi.sharma@thapar.edu');
    expect(user.roll, '1024160143');
    expect(user.role, UserRole.student);
  });

  test('parses the user nested in POST /auth/login', () {
    final body = fixture('auth_login') as Map<String, dynamic>;
    final user = AppUser.fromJson(body['user'] as Map<String, dynamic>);
    expect(user.id, 'u1');
    expect(user.role, UserRole.student);
  });

  test('parses an admin role', () {
    // Every captured fixture is the seeded student, so the admin value is
    // hand-built -- it's what proves role is decoded rather than defaulted.
    final user = AppUser.fromJson(const {
      'id': 'a1',
      'name': 'Librarian',
      'email': 'admin@thapar.edu',
      'roll': 'Pending',
      'role': 'admin',
    });
    expect(user.role, UserRole.admin);
  });

  test('defaults to student when role is absent', () {
    final user = AppUser.fromJson(const {
      'id': 'u2',
      'name': 'Old Client Payload',
      'email': 'old@thapar.edu',
      'roll': 'Pending',
    });
    expect(user.role, UserRole.student);
  });
}
