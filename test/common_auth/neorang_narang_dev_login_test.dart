import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neorang_narang_app/common_auth/neorang_narang_dev_login.dart';

class FakeAuth implements NeorangAuthClient {
  final calls = <String>[];
  Future<void>? holdStart;
  bool failExchange = false;
  bool failLogout = false;
  @override
  Future<({String transaction, Uri authorizeUrl})> start(
    String challenge,
  ) async {
    calls.add('start');
    await holdStart;
    return (
      transaction: 'synthetic-transaction',
      authorizeUrl: Uri.parse(
        'http://127.0.0.1:8000/api/v1/mobile/neorang-narang/authorize?state=${'a' * 43}',
      ),
    );
  }

  @override
  Future<NeorangAuthSession> exchange({
    required String transaction,
    required String code,
    required String verifier,
  }) async {
    calls.add('exchange');
    if (failExchange) throw StateError('synthetic failure');
    return NeorangAuthSession(
      'synthetic-credential',
      'synthetic-account',
      DateTime.utc(2030, 1, 2),
    );
  }

  @override
  Future<String> session(String credential) async {
    calls.add('session');
    return 'synthetic-account';
  }

  @override
  Future<void> logout(String credential) async {
    calls.add('logout');
    if (failLogout) throw StateError('synthetic failure');
  }
}

void main() {
  late FakeAuth client;
  late NeorangDevLogin login;
  late List<Uri> browsers;
  var now = DateTime.utc(2030);
  final callback = NeorangDevLogin.returnUri.replace(
    queryParameters: {'transaction': 'synthetic-transaction', 'code': 'b' * 43},
  );
  setUp(() {
    now = DateTime.utc(2030);
    client = FakeAuth();
    browsers = [];
    login = NeorangDevLogin(
      client: client,
      openBrowser: (uri) async {
        browsers.add(uri);
      },
      createPkce: () => (verifier: 'v' * 43, challenge: 'c' * 43),
      now: () => now,
    );
  });
  test('default flag prevents all auth and browser activity', () async {
    if (NeorangDevLogin.enabled) return;
    await expectLater(login.login(), throwsStateError);
    await expectLater(login.handleCallback(callback), throwsStateError);
    expect(client.calls, isEmpty);
    expect(browsers, isEmpty);
  });
  group('explicit development opt-in', () {
    test(
      'start timeout releases controller; late response cannot launch browser',
      () async {
        final held = Completer<void>();
        client.holdStart = held.future;
        final stages = <String>[];
        login = NeorangDevLogin(
          client: client,
          openBrowser: (uri) async {
            browsers.add(uri);
          },
          createPkce: () => (verifier: 'v' * 43, challenge: 'c' * 43),
          now: () => now,
          onStage: stages.add,
          operationTimeout: const Duration(milliseconds: 20),
        );
        await expectLater(login.login(), throwsStateError);
        expect(stages.last, 'Login request');
        held.complete();
        await Future<void>.delayed(Duration.zero);
        expect(browsers, isEmpty);
        client.holdStart = null;
        await login.login();
        expect(browsers, hasLength(1));
      },
    );
    test(
      'browser timeout consumes pending login and permits explicit retry',
      () async {
        final held = Completer<void>();
        var launches = 0;
        final stages = <String>[];
        login = NeorangDevLogin(
          client: client,
          openBrowser: (_) {
            launches++;
            return launches == 1 ? held.future : Future.value();
          },
          createPkce: () => (verifier: 'v' * 43, challenge: 'c' * 43),
          now: () => now,
          onStage: stages.add,
          operationTimeout: const Duration(milliseconds: 20),
        );
        await expectLater(login.login(), throwsStateError);
        expect(stages.last, 'Browser launch');
        await expectLater(login.handleCallback(callback), throwsStateError);
        expect(client.calls, ['start']);
        held.complete();
        await login.login();
        await login.handleCallback(callback);
        expect(login.signedIn, isTrue);
        expect(launches, 2);
      },
    );
    test('direct login, callback, expiry and isolated logout', () async {
      await login.login();
      expect(browsers, hasLength(1));
      await login.handleCallback(callback);
      expect(login.signedIn, isTrue);
      await expectLater(login.handleCallback(callback), throwsStateError);
      await login.logout();
      expect(login.signedIn, isFalse);
      expect(client.calls, ['start', 'exchange', 'session', 'logout']);
      await login.login();
      await login.handleCallback(callback);
      now = DateTime.utc(2030, 1, 2);
      expect(login.signedIn, isFalse);
    });
    test('invalid callbacks never exchange and consume the attempt', () async {
      final invalidCallbacks = [
        callback.replace(scheme: 'other'),
        callback.replace(host: 'other'),
        callback.replace(path: '/complete/other'),
        callback.replace(userInfo: 'other'),
        callback.replace(port: 8000),
        callback.replace(fragment: 'extra'),
        Uri.parse('$callback&code=extra'),
        Uri.parse('$callback&transaction=extra'),
        Uri.parse('$callback&extra=value'),
        callback.replace(queryParameters: {'code': 'b' * 43}),
        callback.replace(
          queryParameters: {'transaction': 'other', 'code': 'b' * 43},
        ),
        for (final code in ['b' * 42, 'b' * 129, '${'b' * 42}!'])
          callback.replace(
            queryParameters: {
              'transaction': 'synthetic-transaction',
              'code': code,
            },
          ),
      ];
      for (final invalidCallback in invalidCallbacks) {
        await login.login();
        await expectLater(
          login.handleCallback(invalidCallback),
          throwsStateError,
        );
        await expectLater(login.handleCallback(callback), throwsStateError);
      }
      expect(client.calls, List.filled(invalidCallbacks.length, 'start'));
    });
    test('lost exchange is never automatically retried', () async {
      client.failExchange = true;
      await login.login();
      await expectLater(login.handleCallback(callback), throwsStateError);
      await expectLater(login.handleCallback(callback), throwsStateError);
      expect(client.calls, ['start', 'exchange']);
      expect(login.signedIn, isFalse);
    });
    test('failed logout can explicitly retry revocation', () async {
      await login.login();
      await login.handleCallback(callback);
      client.failLogout = true;
      await expectLater(login.logout(), throwsStateError);
      expect(login.signedIn, isTrue);
      client.failLogout = false;
      await login.logout();
      expect(login.signedIn, isFalse);
    });
  }, skip: !NeorangDevLogin.enabled);
}
