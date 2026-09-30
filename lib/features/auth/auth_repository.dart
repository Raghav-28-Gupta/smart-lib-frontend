import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/auth/token_store.dart';
import '../../models/app_user.dart';

/// A login or registration failure, with a message ready for the auth form.
class AuthException implements Exception {
  AuthException(this.message);

  final String message;
}

abstract class AuthRepository {
  Future<AppUser> login(String email, String password);
  Future<AppUser> register(String name, String email, String password);

  /// The user the saved token belongs to. Used to restore a session on
  /// launch, so failures surface as the underlying [ApiException] -- the
  /// caller decides whether a 401 and a network error mean different things
  /// (they do).
  Future<AppUser> me();
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._dio, this._tokens);

  final Dio _dio;
  final TokenStore _tokens;

  @override
  Future<AppUser> login(String email, String password) =>
      _authenticate('/auth/login', {'email': email, 'password': password});

  @override
  Future<AppUser> register(String name, String email, String password) => _authenticate(
        '/auth/register',
        {'name': name, 'email': email, 'password': password},
        // The only way registering can conflict -- so this copy doesn't depend
        // on whatever the database's unique-constraint error happened to say.
        conflictMessage: 'An account with that email already exists.',
      );

  @override
  Future<AppUser> me() async {
    final res = await guardApi(() => _dio.get<Map<String, dynamic>>('/auth/me'));
    return AppUser.fromJson(res.data!);
  }

  Future<AppUser> _authenticate(String path, Map<String, String> body, {String? conflictMessage}) async {
    try {
      final res = await guardApi(() => _dio.post<Map<String, dynamic>>(path, data: body));
      final data = res.data!;
      await _tokens.save(data['token'] as String);
      return AppUser.fromJson(data['user'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw AuthException(_formMessage(e, conflictMessage));
    }
  }

  /// Copy for the auth form. A 401 is already the right sentence (the backend
  /// wrote it to match the form), and a network error already has one.
  static String _formMessage(ApiException e, String? conflictMessage) {
    if (e is ConflictException && conflictMessage != null) return conflictMessage;
    // A 400's own message is just "Invalid request body"; the useful part is
    // the backend's per-field message ("Password must be at least 8
    // characters"), so show the first one rather than duplicate the rules here.
    if (e.statusCode == 400) {
      final fieldErrors = (e.details as Map?)?['fieldErrors'];
      if (fieldErrors is Map) {
        for (final messages in fieldErrors.values) {
          if (messages is List && messages.isNotEmpty) return messages.first.toString();
        }
      }
    }
    return e.message;
  }
}

/// Kept as a test double: accepts any password for the seeded account, and
/// has no notion of tokens.
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

  @override
  Future<AppUser> me() async => _seededUser;
}

final authRepositoryProvider = Provider<AuthRepository>(
    (ref) => HttpAuthRepository(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider)));
