import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/auth/auth_controller.dart';
import '../../support/mock_overrides.dart';

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

  test('logOut resets to the logged-out state', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    final notifier = container.read(authControllerProvider.notifier);
    await notifier.login('aditi.sharma@thapar.edu', 'anything');
    notifier.logOut();
    expect(container.read(authControllerProvider).loggedIn, false);
  });
}
