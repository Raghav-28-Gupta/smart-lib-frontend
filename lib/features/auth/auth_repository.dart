import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_user.dart';

class AuthException implements Exception {
  AuthException(this.message);

  final String message;
}

abstract class AuthRepository {
  Future<AppUser> login(String email, String password);
  Future<AppUser> register(String name, String email, String password);
}

class MockAuthRepository implements AuthRepository {
  static const _seededEmail = 'aditi.sharma@thapar.edu';
  static const _seededUser = AppUser(
      id: 'u1', name: 'Aditi Sharma', email: _seededEmail, roll: '1024160143');

  @override
  Future<AppUser> login(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (email != _seededEmail) {
      throw AuthException("That email and password don't match our records.");
    }
    return _seededUser;
  }

  @override
  Future<AppUser> register(String name, String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return AppUser(
        id: 'u-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        email: email,
        roll: 'Pending');
  }
}

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => MockAuthRepository());
