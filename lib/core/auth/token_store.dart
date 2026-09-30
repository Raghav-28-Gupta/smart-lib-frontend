// lib/core/auth/token_store.dart
//
// The one place the auth token lives at runtime.
//
// It's a leaf in the provider graph on purpose. The Dio interceptor needs the
// token, and the auth controller sets it -- if the interceptor read the token
// *through* the auth controller, the graph would cycle (apiClient -> auth
// controller -> auth repository -> apiClient). Both depend on this instead.
//
// The token is cached in memory so the interceptor can read it synchronously
// on every request: secure storage is async, and on Android every read is a
// platform-channel round trip.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the token is persisted between launches. Deliberately narrow --
/// it's the only thing [TokenStore] needs from storage, and it lets tests
/// substitute memory for the platform keystore.
abstract interface class TokenPersistence {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureTokenPersistence implements TokenPersistence {
  const SecureTokenPersistence([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _key = 'smartlib.authToken';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Holds the current token and notifies listeners when it changes -- which
/// is how a 401 anywhere in the app becomes a logout.
///
/// Persistence failures degrade to "session not remembered" rather than
/// throwing: secure storage is unavailable on web unless the page is served
/// over HTTPS or localhost. In-memory state is authoritative for the session.
/// (If storage can't be written, nothing was persisted, so a failed delete
/// can't resurrect a session later.)
class TokenStore extends ChangeNotifier {
  TokenStore(this._persistence);

  final TokenPersistence _persistence;
  String? _token;

  /// Synchronous on purpose -- read on every outgoing request.
  String? get token => _token;

  /// Loads a token persisted by a previous launch. Never throws: it runs at
  /// startup, and a failure there would strand the app on the splash screen.
  Future<String?> restore() async {
    try {
      _token = await _persistence.read();
    } catch (e) {
      debugPrint('TokenStore: could not read the persisted token: $e');
      _token = null;
    }
    notifyListeners();
    return _token;
  }

  Future<void> save(String token) async {
    _token = token;
    notifyListeners();
    try {
      await _persistence.write(token);
    } catch (e) {
      debugPrint('TokenStore: could not persist the token; this session will not survive a relaunch: $e');
    }
  }

  Future<void> clear() async {
    _token = null;
    notifyListeners();
    try {
      await _persistence.delete();
    } catch (e) {
      debugPrint('TokenStore: could not delete the persisted token: $e');
    }
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) {
  final store = TokenStore(const SecureTokenPersistence());
  ref.onDispose(store.dispose);
  return store;
});
