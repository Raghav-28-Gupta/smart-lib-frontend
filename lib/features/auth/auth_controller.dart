import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_exception.dart';
import '../../core/auth/token_store.dart';
import '../../models/app_user.dart';
import 'auth_repository.dart';

/// `unknown` while the startup session check is still running -- the router
/// holds the user on the splash screen until it resolves either way.
enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState(
      {this.status = AuthStatus.unknown,
      this.user,
      this.submitting = false,
      this.validationMessage});

  final AuthStatus status;
  final AppUser? user;
  final bool submitting;
  final String? validationMessage;

  bool get loggedIn => status == AuthStatus.authenticated;

  AuthState copyWith(
          {AuthStatus? status,
          AppUser? user,
          bool? submitting,
          String? validationMessage,
          bool clearValidation = false}) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        submitting: submitting ?? this.submitting,
        validationMessage: clearValidation
            ? null
            : (validationMessage ?? this.validationMessage),
      );
}

class AuthController extends Notifier<AuthState> {
  static const sessionExpiredMessage = 'Your session has expired. Please log in again.';

  @override
  AuthState build() {
    final tokens = ref.read(tokenStoreProvider);
    tokens.addListener(_onTokenChanged);
    ref.onDispose(() => tokens.removeListener(_onTokenChanged));

    // build() can't await, so the check is scheduled rather than run inline;
    // until it resolves, the status stays unknown and the splash stays up.
    Future.microtask(restoreSession);
    return const AuthState();
  }

  // The API interceptor drops the token when the server rejects it. If that
  // happens while logged in, the session is over -- say so, rather than
  // silently dropping the user on the login screen.
  void _onTokenChanged() {
    if (!ref.mounted) return;
    if (ref.read(tokenStoreProvider).token == null && state.status == AuthStatus.authenticated) {
      state = const AuthState(status: AuthStatus.unauthenticated, validationMessage: sessionExpiredMessage);
    }
  }

  // Only ever resolve *from* unknown: never clobber a login that raced the
  // check, and never touch a controller disposed while it was awaiting.
  bool get _stillRestoring => ref.mounted && state.status == AuthStatus.unknown;

  /// Resolves the startup status from the token saved by a previous launch.
  /// Must always resolve -- the user is held on the splash screen until it does.
  Future<void> restoreSession() async {
    if (!_stillRestoring) return;
    final tokens = ref.read(tokenStoreProvider);
    final token = await tokens.restore();
    if (!_stillRestoring) return;
    if (token == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }

    try {
      final user = await ref.read(authRepositoryProvider).me();
      if (!_stillRestoring) return;
      state = state.copyWith(status: AuthStatus.authenticated, user: user);
    } on UnauthorizedException {
      // Expired or revoked. Over HTTP the interceptor already cleared it; this
      // makes the outcome independent of how the rejection arrived.
      await tokens.clear();
      if (_stillRestoring) state = state.copyWith(status: AuthStatus.unauthenticated);
    } catch (e) {
      // Server unreachable, or something unexpected. Neither is a verdict on
      // the token, so it's kept for the next launch -- but the user still has
      // to land somewhere, and login is where they can act.
      debugPrint('AuthController: session restore failed: $e');
      if (_stillRestoring) state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  void clearValidation() => state = state.copyWith(clearValidation: true);

  Future<void> login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      state =
          state.copyWith(validationMessage: 'Enter your email and password.');
      return;
    }
    state = state.copyWith(submitting: true, clearValidation: true);
    try {
      final user =
          await ref.read(authRepositoryProvider).login(email, password);
      state = state.copyWith(status: AuthStatus.authenticated, user: user, submitting: false);
    } on AuthException catch (e) {
      state = state.copyWith(submitting: false, validationMessage: e.message);
    }
  }

  Future<void> register(String name, String email, String password) async {
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      state = state.copyWith(
          validationMessage: 'Fill in all fields to create your account.');
      return;
    }
    state = state.copyWith(submitting: true, clearValidation: true);
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .register(name, email, password);
      state = state.copyWith(status: AuthStatus.authenticated, user: user, submitting: false);
    } on AuthException catch (e) {
      state = state.copyWith(submitting: false, validationMessage: e.message);
    }
  }

  Future<void> logOut() async {
    // Unauthenticated, not a fresh AuthState(): that would be `unknown`, and
    // the router would park the user on the splash with nothing to move them.
    // Set before clearing the token, so the token listener doesn't read a
    // deliberate logout as an expired session.
    state = const AuthState(status: AuthStatus.unauthenticated);
    await ref.read(tokenStoreProvider).clear();
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
