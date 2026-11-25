import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:neorang_narang_app/common_auth/neorang_narang_dev_login.dart';
import 'package:neorang_narang_app/common_auth/neorang_narang_one_api_auth_client.dart';
import 'package:flutter_test/flutter_test.dart';

const transaction = '11111111-1111-4111-8111-111111111111';
const account = '22222222-2222-4222-8222-222222222222';
final credential = 't' * 43;
final authorize =
    'http://127.0.0.1:8000/api/v1/mobile/neorang-narang/authorize?state=${'s' * 43}';

class FakeTransport implements NeorangAuthTransport {
  final calls =
      <({String method, Uri uri, Map<String, String> headers, String? body})>[];
  ({int status, String body}) response = (status: 200, body: '{}');
  bool uncertain = false;
  Object? failure;

  @override
  Future<({int status, String body})> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    calls.add((method: method, uri: uri, headers: headers, body: body));
    if (failure != null) throw failure!;
    if (uncertain) throw StateError('synthetic secret must not escape');
    return response;
  }
}

void main() {
  late FakeTransport transport;
  late NeorangOneApiAuthClient client;
  Map<String, Object> validExchange() => {
        'access_token': credential,
        'token_type': 'Bearer',
        'sub': account,
        'expires_at': 1893542400,
      };
  Future<NeorangAuthSession> exchange() => client.exchange(
        transaction: transaction,
        code: 'c' * 43,
        verifier: 'v' * 43,
      );
  setUp(() {
    transport = FakeTransport();
    client = NeorangOneApiAuthClient(
      transport: transport,
      clientId: 'synthetic-development-client',
      now: () => DateTime.utc(2030),
    );
  });

  test('disabled by default without any HTTP attempt', () async {
    if (NeorangDevLogin.enabled) return;
    await expectLater(client.start('c' * 43), throwsStateError);
    await expectLater(exchange(), throwsStateError);
    await expectLater(client.session(credential), throwsStateError);
    await expectLater(client.logout(credential), throwsStateError);
    expect(transport.calls, isEmpty);
  });

  group('offline development adapter', () {
    test('safe stages distinguish HTTP, timeout and response format', () async {
      final stages = <String>[];
      client = NeorangOneApiAuthClient(
        transport: transport,
        clientId: 'synthetic-development-client',
        onStage: stages.add,
      );
      for (final status in [401, 422, 503]) {
        transport.response = (status: status, body: 'synthetic-private-body');
        await expectLater(client.start('c' * 43), throwsStateError);
        expect(stages.removeLast(), 'HTTP rejected (POST login-transactions: $status)');
      }
      transport.failure = TimeoutException('synthetic-private-detail');
      await expectLater(client.start('c' * 43), throwsStateError);
      expect(stages.removeLast(), 'Login request timeout');
      transport.failure = NeorangAuthTransportFailure(
        'Login request connection failed',
      );
      await expectLater(client.start('c' * 43), throwsStateError);
      expect(stages.removeLast(), 'Login request connection failed');
      transport.failure = null;
      transport.response = (status: 200, body: 'synthetic-private-body');
      await expectLater(client.start('c' * 43), throwsStateError);
      expect(stages.removeLast(), 'Response format validation');
      transport.response = (status: 200, body: '{}');
      await expectLater(client.start('c' * 43), throwsStateError);
      expect(stages.removeLast(), 'Authorization URL validation');
      expect(transport.calls, hasLength(7));
    });

    test(
      'IO transport sends a UTF-8 byte length to length-delimited servers',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final body = jsonEncode({'synthetic': '합성'});
        final received = server.first.then((request) async {
          final length = request.contentLength;
          final chunked = request.headers.chunkedTransferEncoding;
          final decoded = await utf8.decoder.bind(request).join();
          request.response.statusCode = length > 0 ? 200 : 422;
          request.response.write('{}');
          await request.response.close();
          return (length: length, chunked: chunked, body: decoded);
        });
        try {
          final response = await NeorangIoAuthTransport().send(
            'POST',
            Uri.parse('http://127.0.0.1:${server.port}/'),
            {'Content-Type': 'application/json'},
            body,
          );
          final request = await received;
          expect(response.status, 200);
          expect(request.length, utf8.encode(body).length);
          expect(request.chunked, isFalse);
          expect(request.body, body);
        } finally {
          await server.close(force: true);
        }
      },
    );

    test('exact four routes, binding, headers and Unix seconds', () async {
      transport.response = (
        status: 200,
        body: jsonEncode({
          'transaction': transaction,
          'authorize_url': authorize,
        }),
      );
      expect((await client.start('c' * 43)).transaction, transaction);
      expect(jsonDecode(transport.calls.last.body!), {
        'app_id': 'neorang_narang',
        'client_id': 'synthetic-development-client',
        'return_uri': NeorangDevLogin.returnUri.toString(),
        'challenge': 'c' * 43,
      });
      transport.response = (status: 200, body: jsonEncode(validExchange()));
      final result = await exchange();
      expect(result.accountId, account);
      expect(result.expiresAt, DateTime.utc(2030, 1, 2));
      expect(jsonDecode(transport.calls.last.body!), {
        'app_id': 'neorang_narang',
        'client_id': 'synthetic-development-client',
        'return_uri': NeorangDevLogin.returnUri.toString(),
        'transaction': transaction,
        'code': 'c' * 43,
        'verifier': 'v' * 43,
      });
      transport.response = (
        status: 200,
        body: jsonEncode({'sub': account, 'app_id': 'neorang_narang'}),
      );
      expect(await client.session(credential), account);
      transport.response = (status: 204, body: '');
      await client.logout(credential);
      expect(transport.calls.map((c) => c.method), [
        'POST',
        'POST',
        'GET',
        'POST',
      ]);
      expect(transport.calls.map((c) => c.uri.path), [
        for (final path in [
          'login-transactions',
          'session-exchange',
          'session',
          'logout',
        ])
          '/api/v1/mobile/neorang-narang/$path',
      ]);
      for (final call in transport.calls.skip(2)) {
        expect(call.headers['Authorization'], 'Bearer $credential');
        expect(call.body, isNull);
      }
    });

    test('malformed start and unsafe authorization URLs rejected', () async {
      for (final body in [
        'not json',
        '[]',
        '{}',
        jsonEncode({'transaction': 7, 'authorize_url': authorize}),
        for (final url in [
          'https://other/authorize',
          '$authorize&state=duplicate',
          '$authorize#fragment',
          '$authorize&extra=x',
        ])
          jsonEncode({'transaction': transaction, 'authorize_url': url}),
      ]) {
        transport.response = (status: 200, body: body);
        await expectLater(client.start('c' * 43), throwsStateError);
      }
    });

    test(
      'malformed exchange field types, token kind and expiry rejected',
      () async {
        final mutations = <String, List<Object?>>{
          'access_token': [null, 3, '', 'bad\r\nheader'],
          'sub': [null, 3, '', 'auth0|external'],
          'token_type': [null, 'bearer', 'Basic'],
          'expires_at': [
            null,
            '1893542400',
            1893542400.0,
            1893456000,
            -1,
            8640000000001,
          ],
        };
        for (final entry in mutations.entries) {
          for (final value in entry.value) {
            transport.response = (
              status: 200,
              body: jsonEncode({...validExchange(), entry.key: value}),
            );
            await expectLater(exchange(), throwsStateError);
          }
        }
        for (final body in ['broken', 'null', '[]', '{}']) {
          transport.response = (status: 200, body: body);
          await expectLater(exchange(), throwsStateError);
        }
      },
    );

    test('app mismatch and invalid session subject rejected', () async {
      for (final data in [
        {'sub': account, 'app_id': 'life_diary'},
        {'sub': account},
        {'sub': 3, 'app_id': 'neorang_narang'},
      ]) {
        transport.response = (status: 200, body: jsonEncode(data));
        await expectLater(client.session(credential), throwsStateError);
      }
    });

    test(
      'non-success status never retried or accepted, including redirects',
      () async {
        for (final status in [201, 302, 401, 422, 503]) {
          transport.response = (
            status: status,
            body: jsonEncode(validExchange()),
          );
          final before = transport.calls.length;
          await expectLater(exchange(), throwsStateError);
          expect(transport.calls.length, before + 1);
        }
        transport.response = (status: 200, body: '{}');
        await expectLater(client.logout(credential), throwsStateError);
        transport.response = (status: 204, body: '{}');
        await expectLater(client.logout(credential), throwsStateError);
      },
    );

    test(
      'uncertain HTTP exchange consumes callback; no retry or session request',
      () async {
        final login = NeorangDevLogin(
          client: client,
          openBrowser: (_) async {},
          createPkce: () => (verifier: 'v' * 43, challenge: 'c' * 43),
          now: () => DateTime.utc(2030),
        );
        transport.response = (
          status: 200,
          body: jsonEncode({
            'transaction': transaction,
            'authorize_url': authorize,
          }),
        );
        await login.login();
        transport.uncertain = true;
        final callback = NeorangDevLogin.returnUri.replace(
          queryParameters: {'transaction': transaction, 'code': 'c' * 43},
        );
        await expectLater(login.handleCallback(callback), throwsStateError);
        await expectLater(login.handleCallback(callback), throwsStateError);
        expect(transport.calls, hasLength(2));
        expect(login.signedIn, isFalse);
      },
    );
  }, skip: !NeorangDevLogin.enabled);
}
