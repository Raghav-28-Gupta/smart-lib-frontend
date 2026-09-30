// test/support/fake_token_store.dart
import 'package:smartlib_frontend/core/auth/token_store.dart';

/// Token persistence backed by a field, so tests never reach a real
/// platform keystore. Reuse one instance across two TokenStores to simulate
/// an app relaunch.
class InMemoryTokenPersistence implements TokenPersistence {
  InMemoryTokenPersistence([this.stored]);

  String? stored;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String token) async => stored = token;

  @override
  Future<void> delete() async => stored = null;
}
