import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:neorang_narang_app/common_auth/neorang_narang_dev_login.dart';
import 'package:neorang_narang_app/common_auth/auth_session_store.dart';
import 'neorang_narang_dev_login_test.dart' show FakeAuth;

class MemoryStore implements AuthSessionStore {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async {
    if (failWrite) throw StateError('synthetic write failure');
    value = data;
  }
  @override
  Future<void> clear() async => value = null;
}
class RecoveryClient extends FakeAuth {
  bool offline = false;
  bool wrongAccount = false;
  @override
  Future<String> session(String credential) async {
    if (offline) throw StateError('synthetic offline');
    if (wrongAccount) return 'other-account';
    return super.session(credential);
  }
}
void main() {
  late MemoryStore store;
  late RecoveryClient client;
  NeorangDevLogin makeLogin() => NeorangDevLogin(
    client: client, store: store, now: () => DateTime.utc(2030),
    openBrowser: (_) async {},
    createPkce: () => (verifier: 'v' * 43, challenge: 'c' * 43),
  );
  void seed({bool pending = false, bool expired = false}) {
    store.value = jsonEncode({
      'version': 1, 'credential': 'synthetic-credential',
      'account': 'synthetic-account',
      'expires': (expired ? DateTime.utc(2029) : DateTime.utc(2031)).toIso8601String(),
      'logout_pending': pending,
    });
  }
  setUp(() { store = MemoryStore(); client = RecoveryClient(); });
  test('restoration is disabled without development login', () async {
    if (NeorangDevLogin.enabled) return;
    seed();
    await expectLater(makeLogin().restore(), throwsStateError);
    expect(client.calls, isEmpty);
  });
  group('persistent authentication', () {
    test('fresh controller validates saved session with server', () async {
      seed();
      final login = makeLogin();
      expect(login.signedIn, isFalse);
      await login.restore();
      expect(login.signedIn, isTrue);
      expect(client.calls, ['session']);
    });
    test('expired session is cleared without network access', () async {
      seed(expired: true);
      final login = makeLogin();
      await login.restore();
      expect(login.signedIn, isFalse);
      expect(store.value, isNull);
      expect(client.calls, isEmpty);
    });
    test('offline recovery keeps ciphertext data but never signs in', () async {
      seed(); client.offline = true;
      final login = makeLogin();
      await expectLater(login.restore(), throwsStateError);
      expect(login.signedIn, isFalse);
      expect(store.value, isNotNull);
      client.offline = false;
      await login.restore();
      expect(login.signedIn, isTrue);
    });
    test('account mismatch clears saved identity', () async {
      seed(); client.wrongAccount = true;
      final login = makeLogin();
      await expectLater(login.restore(), throwsStateError);
      expect(login.signedIn, isFalse);
      expect(store.value, isNull);
    });
    test('malformed saved data is cleared without network access', () async {
      store.value = 'invalid';
      await expectLater(makeLogin().restore(), throwsStateError);
      expect(store.value, isNull);
      expect(client.calls, isEmpty);
    });
    test('pending logout never calls session or restores signed in', () async {
      seed(pending: true);
      final login = makeLogin();
      await login.restore();
      expect(login.signedIn, isFalse);
      expect(client.calls, ['logout']);
      expect(store.value, isNull);
    });
    test('logout while offline persists intent across process restart', () async {
      seed(); client.failLogout = true;
      await expectLater(makeLogin().logout(), throwsStateError);
      expect(jsonDecode(store.value!)['logout_pending'], isTrue);
      final restarted = makeLogin();
      await expectLater(restarted.restore(), throwsStateError);
      expect(restarted.signedIn, isFalse);
      client.failLogout = false;
      await restarted.restore();
      expect(store.value, isNull);
      expect(client.calls.every((call) => call == 'logout'), isTrue);
    });
    test('failed intent write prevents revocation request and preserves data', () async {
      seed(); store.failWrite = true;
      await expectLater(makeLogin().logout(), throwsStateError);
      expect(client.calls, isEmpty);
      expect(jsonDecode(store.value!)['logout_pending'], isFalse);
    });
    test('successful callback persists only after server validation', () async {
      final login = makeLogin();
      await login.login();
      await login.handleCallback(NeorangDevLogin.returnUri.replace(queryParameters: {
        'transaction': 'synthetic-transaction', 'code': 'b' * 43,
      }));
      expect(login.signedIn, isTrue);
      expect(jsonDecode(store.value!)['account'], 'synthetic-account');
      expect(client.calls, ['start', 'exchange', 'session']);
    });
  }, skip: !NeorangDevLogin.enabled);
}
