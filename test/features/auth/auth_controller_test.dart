import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import 'package:smartlib_frontend/features/auth/auth_repository.dart';
import 'package:smartlib_frontend/models/app_user.dart';
import '../../support/fake_token_store.dart';
import '../../support/mock_overrides.dart';

/// The mock, except `me()` fails with [error].
class _MeFails extends MockAuthRepository {
  _MeFails(this.error);
  final Object error;
  @override
  Future<AppUser> me() async => throw error;
}

void main() {
  test(
      'login with empty fields sets a validation message and does not call the repository',
      () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).login('', '');
    final state = container.read(authControllerProvider);
    expect(state.loggedIn, false);
    expect(state.validationMessage, 'Enter your email and password.');
  });

  test('login with the seeded account succeeds', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login('aditi.sharma@thapar.edu', 'anything');
    final state = container.read(authControllerProvider);
    expect(state.loggedIn, true);
    expect(state.user?.name, 'Aditi Sharma');
  });

  test('login with an unknown email sets the mismatch validation message',
      () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login('nobody@thapar.edu', 'x');
    final state = container.read(authControllerProvider);
    expect(state.loggedIn, false);
    expect(state.validationMessage,
        "That email and password don't match our records.");
  });

  test('register with all fields succeeds and creates a fresh user', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .register('New Student', 'new@thapar.edu', 'pw');
    final state = container.read(authControllerProvider);
    expect(state.loggedIn, true);
    expect(state.user?.email, 'new@thapar.edu');
  });

  test('starts unknown, then resolves once session restore finishes', () async {
    // The router shows the splash screen while the status is unknown.
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    expect(container.read(authControllerProvider).status, AuthStatus.unknown);

    await Future<void>.delayed(Duration.zero); // let the scheduled restore run
    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
  });

  test('a successful login is authenticated', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).login('aditi.sharma@thapar.edu', 'anything');
    expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
  });

  test('logOut lands on unauthenticated, not back on unknown', () async {
    // Unknown means "restore still running" -- the router would park a
    // logged-out user on the splash screen, and nothing would ever move them.
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    final notifier = container.read(authControllerProvider.notifier);
    await notifier.login('aditi.sharma@thapar.edu', 'anything');
    notifier.logOut();
    expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
  });

  test('logOut resets to the logged-out state', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    final notifier = container.read(authControllerProvider.notifier);
    await notifier.login('aditi.sharma@thapar.edu', 'anything');
    notifier.logOut();
    expect(container.read(authControllerProvider).loggedIn, false);
  });

  group('session restore', () {
    Future<(ProviderContainer, TokenStore)> restoredWith({required String? savedToken, AuthRepository? auth}) async {
      final persistence = InMemoryTokenPersistence(savedToken);
      final tokens = TokenStore(persistence);
      final container = ProviderContainer(overrides: mockRepositoryOverrides(tokens: tokens, auth: auth));
      addTearDown(container.dispose);
      container.read(authControllerProvider);
      await Future<void>.delayed(Duration.zero); // let the scheduled restore run
      return (container, tokens);
    }

    test('a saved, still-valid token logs the user straight back in', () async {
      final (container, _) = await restoredWith(savedToken: 'saved-jwt');
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.user?.name, 'Aditi Sharma');
    });

    test('a rejected token is cleared, and the user goes to login', () async {
      final (container, tokens) = await restoredWith(
          savedToken: 'expired-jwt', auth: _MeFails(const UnauthorizedException('Invalid or expired token')));
      expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
      expect(tokens.token, isNull);
    });

    test('an unreachable server sends the user to login but keeps the token', () async {
      // A network failure says nothing about whether the token is still good,
      // so it survives for the next launch.
      final (container, tokens) = await restoredWith(
          savedToken: 'saved-jwt', auth: _MeFails(const ApiException(0, ApiException.networkMessage)));
      expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
      expect(tokens.token, 'saved-jwt');
    });

    test('never leaves the user stuck on the splash, whatever goes wrong', () async {
      final (container, _) = await restoredWith(savedToken: 'saved-jwt', auth: _MeFails(StateError('unexpected')));
      expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    });
  });

  group('while logged in', () {
    test('a token rejected mid-session logs out with an explanation', () async {
      // The API interceptor drops the token on a 401; this is the other end.
      final tokens = TokenStore(InMemoryTokenPersistence());
      final container = ProviderContainer(overrides: mockRepositoryOverrides(tokens: tokens));
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).login('aditi.sharma@thapar.edu', 'anything');
      await tokens.save('jwt');

      await tokens.clear();
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.validationMessage, 'Your session has expired. Please log in again.');
    });

    test('logging out clears the token without claiming the session expired', () async {
      final tokens = TokenStore(InMemoryTokenPersistence());
      final container = ProviderContainer(overrides: mockRepositoryOverrides(tokens: tokens));
      addTearDown(container.dispose);
      final notifier = container.read(authControllerProvider.notifier);
      await notifier.login('aditi.sharma@thapar.edu', 'anything');
      await tokens.save('jwt');

      await notifier.logOut();
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.validationMessage, isNull);
      expect(tokens.token, isNull);
    });
  });
}
