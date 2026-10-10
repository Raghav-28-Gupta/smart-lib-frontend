// test/core/auth/token_store_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import '../../support/fake_token_store.dart';

/// Persistence where every operation fails -- what secure storage does on
/// web when the page isn't served over HTTPS or localhost.
class _BrokenPersistence implements TokenPersistence {
  @override
  Future<String?> read() async => throw Exception('storage unavailable');
  @override
  Future<void> write(String token) async => throw Exception('storage unavailable');
  @override
  Future<void> delete() async => throw Exception('storage unavailable');
}

/// Persistence whose read finishes only when [release] is called.
class _SlowPersistence extends InMemoryTokenPersistence {
  _SlowPersistence() : super('jwt');
  final _gate = Completer<void>();
  void release() => _gate.complete();
  @override
  Future<String?> read() async {
    await _gate.future;
    return super.read();
  }
}

void main() {
  test('holds no token until one is restored or saved', () {
    expect(TokenStore(InMemoryTokenPersistence()).token, isNull);
  });

  test('restore loads a persisted token into the synchronous cache', () async {
    final store = TokenStore(InMemoryTokenPersistence('persisted-jwt'));
    expect(await store.restore(), 'persisted-jwt');
    // The Dio interceptor reads this on every request -- it must not await.
    expect(store.token, 'persisted-jwt');
  });

  test('restore yields null when nothing is persisted', () async {
    expect(await TokenStore(InMemoryTokenPersistence()).restore(), isNull);
  });

  test('a saved token survives a relaunch', () async {
    final persistence = InMemoryTokenPersistence();
    await TokenStore(persistence).save('fresh-jwt');

    final relaunched = TokenStore(persistence);
    expect(await relaunched.restore(), 'fresh-jwt');
  });

  test('clear forgets the token in memory and on disk', () async {
    final persistence = InMemoryTokenPersistence();
    final store = TokenStore(persistence);
    await store.save('jwt');
    await store.clear();

    expect(store.token, isNull);
    expect(await TokenStore(persistence).restore(), isNull);
  });

  test('notifies listeners on save and on clear', () async {
    // The auth controller listens for the token going null -- that's how a
    // 401 anywhere in the app becomes a logout.
    final store = TokenStore(InMemoryTokenPersistence());
    var notifications = 0;
    store.addListener(() => notifications++);

    await store.save('jwt');
    expect(notifications, 1);
    await store.clear();
    expect(notifications, 2);
  });

  group('when secure storage is unavailable', () {
    test('restore returns null instead of throwing', () async {
      // It runs at startup; a throw would strand the app on the splash screen.
      expect(await TokenStore(_BrokenPersistence()).restore(), isNull);
    });

    test('save still keeps the session alive in memory', () async {
      final store = TokenStore(_BrokenPersistence());
      await store.save('jwt');
      expect(store.token, 'jwt');
    });

    test('clear still logs out in memory', () async {
      final store = TokenStore(_BrokenPersistence());
      await store.save('jwt');
      await store.clear();
      expect(store.token, isNull);
    });
  });

  test('a restore that finishes after the store is disposed does not throw', () async {
    // Happens when the app (or a test's container) shuts down while a saved
    // session is still being read.
    final persistence = _SlowPersistence();
    final store = TokenStore(persistence);
    final restoring = store.restore();
    store.dispose();
    persistence.release();
    await expectLater(restoring, completes);
  });
}
