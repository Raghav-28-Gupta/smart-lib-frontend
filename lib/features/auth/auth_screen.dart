import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_controller.dart';

enum _AuthMode { login, register }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  _AuthMode mode = _AuthMode.login;
  final loginEmail = TextEditingController();
  final loginPassword = TextEditingController();
  final regName = TextEditingController();
  final regEmail = TextEditingController();
  final regPassword = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final notifier = ref.read(authControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.menu_book, size: 40),
                const SizedBox(height: 8),
                Text('SmartLib',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center),
                Text('Central Library · Thapar Institute',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 20),
                SegmentedButton<_AuthMode>(
                  segments: const [
                    ButtonSegment(
                        value: _AuthMode.login, label: Text('Log in')),
                    ButtonSegment(
                        value: _AuthMode.register,
                        label: Text('Create account')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) {
                    setState(() => mode = s.first);
                    notifier.clearValidation();
                  },
                ),
                if (auth.validationMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(auth.validationMessage!),
                  ),
                ],
                const SizedBox(height: 20),
                if (mode == _AuthMode.login) ...[
                  TextField(
                      controller: loginEmail,
                      decoration: const InputDecoration(
                          labelText: 'Email', hintText: 'you@thapar.edu')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: loginPassword,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Password', hintText: '••••••••')),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: auth.submitting
                        ? null
                        : () =>
                            notifier.login(loginEmail.text, loginPassword.text),
                    child: auth.submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Log in'),
                  ),
                ] else ...[
                  TextField(
                      controller: regName,
                      decoration: const InputDecoration(
                          labelText: 'Full name', hintText: 'Aditi Sharma')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: regEmail,
                      decoration: const InputDecoration(
                          labelText: 'Email', hintText: 'you@thapar.edu')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: regPassword,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Password', hintText: '••••••••')),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: auth.submitting
                        ? null
                        : () => notifier.register(
                            regName.text, regEmail.text, regPassword.text),
                    child: auth.submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Create account'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
