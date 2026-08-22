import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_user.dart';
import 'auth_repository.dart';

class AuthState {
  const AuthState(
      {this.loggedIn = false,
      this.user,
      this.submitting = false,
      this.validationMessage});

  final bool loggedIn;
  final AppUser? user;
  final bool submitting;
  final String? validationMessage;

  AuthState copyWith(
          {bool? loggedIn,
          AppUser? user,
          bool? submitting,
          String? validationMessage,
          bool clearValidation = false}) =>
      AuthState(
        loggedIn: loggedIn ?? this.loggedIn,
        user: user ?? this.user,
        submitting: submitting ?? this.submitting,
        validationMessage: clearValidation
            ? null
            : (validationMessage ?? this.validationMessage),
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

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
      state = state.copyWith(loggedIn: true, user: user, submitting: false);
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
      state = state.copyWith(loggedIn: true, user: user, submitting: false);
    } on AuthException catch (e) {
      state = state.copyWith(submitting: false, validationMessage: e.message);
    }
  }

  void logOut() => state = const AuthState();
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
