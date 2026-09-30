import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  @override
  AuthState build() {
    // build() can't await, so the check is scheduled rather than run inline;
    // until it resolves, the status stays unknown and the splash stays up.
    Future.microtask(restoreSession);
    return const AuthState();
  }

  /// Resolves the startup status. There is no persisted session to restore
  /// yet, so this settles straight on unauthenticated.
  Future<void> restoreSession() async {
    // Only ever resolves *from* unknown: never clobber a login that raced it,
    // and never touch a controller that was disposed before this ran.
    if (!ref.mounted || state.status != AuthStatus.unknown) return;
    state = state.copyWith(status: AuthStatus.unauthenticated);
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

  // Unauthenticated, not a fresh AuthState(): that would be `unknown`, and the
  // router would park the user on the splash screen with nothing to move them.
  void logOut() => state = const AuthState(status: AuthStatus.unauthenticated);
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
