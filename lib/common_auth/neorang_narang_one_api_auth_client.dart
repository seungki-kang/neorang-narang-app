import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'neorang_narang_dev_login.dart';

/// Only fixed diagnostic labels may cross the transport boundary.
class NeorangAuthTransportFailure extends StateError {
  NeorangAuthTransportFailure(this.stage) : super(stage);
  final String stage;
}

/// A single HTTP attempt. Implementations must not retry or follow redirects.
abstract interface class NeorangAuthTransport {
  Future<({int status, String body})> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  );
}

/// Uncomposed development transport; no cookies, persistence or upload paths.
class NeorangIoAuthTransport implements NeorangAuthTransport {
  @override
  Future<({int status, String body})> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    if (!NeorangDevLogin.enabled) {
      throw StateError('Development login disabled');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await (() async {
        final request = await client.openUrl(method, uri);
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        if (body != null) {
          final bytes = utf8.encode(body);
          request.contentLength = bytes.length;
          request.add(bytes);
        }
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 65536) {
            throw StateError('Invalid authentication response');
          }
          bytes.addAll(chunk);
        }
        return (status: response.statusCode, body: utf8.decode(bytes));
      })()
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw NeorangAuthTransportFailure('Login request timeout');
    } on SocketException {
      throw NeorangAuthTransportFailure('Login request connection failed');
    } catch (_) {
      throw NeorangAuthTransportFailure('Login request transport failed');
    } finally {
      client.close(force: true);
    }
  }
}

class NeorangOneApiAuthClient implements NeorangAuthClient {
  NeorangOneApiAuthClient({
    required this.transport,
    required this.clientId,
    this.onStage,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final NeorangAuthTransport transport;
  final void Function(String stage)? onStage;
  // Supplied only after review of the dedicated development registration.
  final String clientId;
  final DateTime Function() _now;
  static const _prefix = 'http://127.0.0.1:8000/api/v1/mobile/neorang-narang';
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final _opaque = RegExp(r'^[A-Za-z0-9_-]{43}$');

  Map<String, Object> get _binding => {
        'app_id': 'neorang_narang',
        'client_id': clientId,
        'return_uri': NeorangDevLogin.returnUri.toString(),
      };

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object>? body,
    String? credential,
    int status = 200,
  }) async {
    if (!NeorangDevLogin.enabled) {
      throw StateError('Development login disabled');
    }
    try {
      if (clientId.trim().isEmpty ||
          (credential != null && !_opaque.hasMatch(credential))) {
        throw StateError('Invalid authentication input');
      }
      final response = await transport.send(
        method,
        Uri.parse('$_prefix/$path'),
        {
          'Accept': 'application/json',
          if (body != null) 'Content-Type': 'application/json',
          if (credential != null) 'Authorization': 'Bearer $credential',
        },
        body == null ? null : jsonEncode(body),
      );
      if (response.status != status) {
        onStage?.call('HTTP rejected (${response.status})');
        throw StateError('Authentication rejected');
      }
      if (status == 204) {
        if (response.body.isNotEmpty) {
          throw StateError('Invalid logout response');
        }
        return {};
      }
      onStage?.call('Response format validation');
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Invalid response');
      }
      return decoded;
    } on NeorangAuthTransportFailure catch (error) {
      onStage?.call(error.stage);
      throw StateError('Authentication request failed; no automatic retry');
    } on TimeoutException {
      onStage?.call('Login request timeout');
      throw StateError('Authentication request failed; no automatic retry');
    } catch (_) {
      // Never expose response bodies, transport exceptions or credentials.
      throw StateError('Authentication request failed; no automatic retry');
    }
  }

  @override
  Future<({String transaction, Uri authorizeUrl})> start(
    String challenge,
  ) async {
    if (!_opaque.hasMatch(challenge)) throw StateError('Invalid challenge');
    final data = await _request(
      'POST',
      'login-transactions',
      body: {..._binding, 'challenge': challenge},
    );
    onStage?.call('Authorization URL validation');
    final transaction = data['transaction'];
    final rawUrl = data['authorize_url'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (transaction is! String ||
        !_uuid.hasMatch(transaction) ||
        url == null ||
        url.scheme != 'http' ||
        url.host != '127.0.0.1' ||
        url.port != 8000 ||
        url.userInfo.isNotEmpty ||
        url.path != '/api/v1/mobile/neorang-narang/authorize' ||
        url.fragment.isNotEmpty ||
        url.queryParametersAll.length != 1 ||
        url.queryParametersAll['state']?.length != 1 ||
        !_opaque.hasMatch(url.queryParameters['state'] ?? '')) {
      throw StateError('Invalid authorization response');
    }
    return (transaction: transaction, authorizeUrl: url);
  }

  @override
  Future<NeorangAuthSession> exchange({
    required String transaction,
    required String code,
    required String verifier,
  }) async {
    if (!_uuid.hasMatch(transaction) ||
        code.length < 43 ||
        code.length > 128 ||
        verifier.length < 43 ||
        verifier.length > 128) {
      throw StateError('Invalid exchange input');
    }
    final data = await _request(
      'POST',
      'session-exchange',
      body: {
        ..._binding,
        'transaction': transaction,
        'code': code,
        'verifier': verifier,
      },
    );
    final credential = data['access_token'];
    final account = data['sub'];
    final expires = data['expires_at'];
    if (credential is! String ||
        !_opaque.hasMatch(credential) ||
        account is! String ||
        !_uuid.hasMatch(account) ||
        data['token_type'] != 'Bearer' ||
        expires is! int ||
        expires <= 0 ||
        expires > 8640000000000) {
      throw StateError('Invalid session response');
    }
    final expiry = DateTime.fromMillisecondsSinceEpoch(
      expires * 1000,
      isUtc: true,
    );
    if (!expiry.isAfter(_now())) throw StateError('Expired session response');
    return NeorangAuthSession(credential, account, expiry);
  }

  @override
  Future<String> session(String credential) async {
    final data = await _request('GET', 'session', credential: credential);
    final account = data['sub'];
    if (data['app_id'] != 'neorang_narang' ||
        account is! String ||
        !_uuid.hasMatch(account)) {
      throw StateError('Invalid session identity');
    }
    return account;
  }

  @override
  Future<void> logout(String credential) async {
    await _request('POST', 'logout', credential: credential, status: 204);
  }
}
