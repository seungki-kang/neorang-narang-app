import 'dart:convert';
import 'auth_session_store.dart';
import 'package:flutter/foundation.dart';

/// Offline-testable preparation only. No production composition or storage I/O.
abstract interface class NeorangAuthClient {
  Future<({String transaction, Uri authorizeUrl})> start(String challenge);
  Future<NeorangAuthSession> exchange({
    required String transaction,
    required String code,
    required String verifier,
  });
  Future<String> session(String credential);
  Future<void> logout(String credential);
}

class NeorangAuthSession {
  const NeorangAuthSession(this.credential, this.accountId, this.expiresAt);
  final String credential;
  final String accountId;
  final DateTime expiresAt;

  @override
  String toString() => 'NeorangAuthSession(redacted)';
}

class NeorangDevLogin {
  NeorangDevLogin({
    required this.client,
    this.store,
    required this.openBrowser,
    required this.createPkce,
    DateTime Function()? now,
    this.onStage,
    this.operationTimeout = const Duration(seconds: 15),
  }) : _now = now ?? DateTime.now;

  static const enabled = kDebugMode &&
      bool.fromEnvironment('NEORANG_DEV_LOGIN', defaultValue: false);
  static final returnUri = Uri.parse(
    'jesuslife-poc://auth/complete/android',
  );
  final void Function(String stage)? onStage;
  final Duration operationTimeout;
  final NeorangAuthClient client;
  final AuthSessionStore? store;
  final Future<void> Function(Uri) openBrowser;
  // Future Android adapter must supply random verifier + S256 challenge.
  final ({String verifier, String challenge}) Function() createPkce;
  final DateTime Function() _now;
  String? _transaction;
  String? _verifier;
  bool _busy = false;
  NeorangAuthSession? _session;

  bool get signedIn {
    if (_session != null && !_session!.expiresAt.isAfter(_now())) {
      _session = null;
    }
    return _session != null;
  }

  NeorangAuthSession? get activeSession => signedIn ? _session : null;

  Future<void> _save(NeorangAuthSession session, {bool logoutPending = false}) async {
    await store?.write(jsonEncode({
      'version': 1,
      'credential': session.credential,
      'account': session.accountId,
      'expires': session.expiresAt.toUtc().toIso8601String(),
      'logout_pending': logoutPending,
    }));
  }

  /// Network errors retain the sealed credential, but never expose a session.
  /// A persisted logout intent must be revoked before another login is allowed.
  Future<void> restore() async {
    if (!enabled || _busy) throw StateError('Session recovery unavailable');
    if (store == null) return;
    _busy = true;
    _session = null;
    _clearPending();
    try {
      final raw = await store!.read();
      if (raw == null) return;
      NeorangAuthSession saved;
      bool pending;
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['version'] != 1 || data['logout_pending'] is! bool) {
          throw FormatException();
        }
        saved = NeorangAuthSession(data['credential'] as String,
            data['account'] as String, DateTime.parse(data['expires'] as String));
        pending = data['logout_pending'] as bool;
        if (saved.credential.isEmpty || saved.accountId.isEmpty) {
          throw FormatException();
        }
      } catch (_) {
        await store!.clear();
        throw StateError('Stored session invalid; login again');
      }
      if (!saved.expiresAt.isAfter(_now())) {
        await store!.clear();
        return;
      }
      if (pending) {
        await client.logout(saved.credential).timeout(operationTimeout);
        await store!.clear();
        return;
      }
      final account = await client.session(saved.credential).timeout(operationTimeout);
      if (account != saved.accountId) {
        await store!.clear();
        throw StateError('Stored session invalid; login again');
      }
      _session = saved;
    } finally {
      _busy = false;
    }
  }

  Future<void> login() async {
    if (!enabled) throw StateError('Development login disabled');
    if (_busy || signedIn) throw StateError('Login unavailable');
    if (store != null) {
      await restore();
      if (signedIn) return;
    }
    _busy = true;
    _clearPending();
    try {
      final pkce = createPkce();
      onStage?.call('Login request');
      final start =
          await client.start(pkce.challenge).timeout(operationTimeout);
      onStage?.call('Authorization URL validation');
      final url = start.authorizeUrl;
      if (url.scheme != 'http' ||
          url.host != '127.0.0.1' ||
          url.port != 8000 ||
          url.userInfo.isNotEmpty ||
          url.path != '/api/v1/mobile/neorang-narang/authorize' ||
          url.fragment.isNotEmpty ||
          url.queryParametersAll.length != 1 ||
          url.queryParametersAll['state']?.length != 1 ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$')
              .hasMatch(url.queryParameters['state'] ?? '')) {
        throw StateError('Invalid authorization response');
      }
      _transaction = start.transaction;
      _verifier = pkce.verifier;
      onStage?.call('Browser launch');
      await openBrowser(url).timeout(operationTimeout);
      onStage?.call('Callback wait');
    } catch (_) {
      _clearPending();
      throw StateError('Login failed; start a new login');
    } finally {
      _busy = false;
    }
  }

  /// Receives the Android handoff, never an Auth0 token or server callback.
  Future<void> handleCallback(Uri uri) async {
    if (!enabled) throw StateError('Development login disabled');
    if (_busy) throw StateError('Login busy');
    onStage?.call('Callback validation');
    final transaction = _transaction;
    final verifier = _verifier;
    _clearPending(); // Every attempt is single use, including failed exchange.
    final query = uri.queryParametersAll;
    if (transaction == null ||
        verifier == null ||
        // Null preserves URI components; normalize both sides for comparison.
        uri.replace(query: '', fragment: '') !=
            returnUri.replace(query: '', fragment: '') ||
        uri.fragment.isNotEmpty ||
        query.length != 2 ||
        query['transaction']?.length != 1 ||
        query['code']?.length != 1 ||
        query['transaction']!.single != transaction ||
        !RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(query['code']!.single)) {
      throw StateError('Invalid login callback; start a new login');
    }
    _busy = true;
    try {
      onStage?.call('One-time exchange');
      final session = await client
          .exchange(
            transaction: transaction,
            code: query['code']!.single,
            verifier: verifier,
          )
          .timeout(operationTimeout);
      onStage?.call('Session validation');
      if (session.credential.isEmpty ||
          session.accountId.isEmpty ||
          !session.expiresAt.isAfter(_now()) ||
          await client.session(session.credential).timeout(operationTimeout) !=
              session.accountId) {
        throw StateError('Invalid session');
      }
      await _save(session);
      _session = session;
    } catch (_) {
      _session = null;
      throw StateError('Login failed; start a new login');
    } finally {
      _busy = false;
    }
  }

  Future<void> logout() async {
    if (_busy) throw StateError('Login busy');
    _busy = true;
    _clearPending();
    try {
      var session = _session;
      if (session == null && store != null) {
        final raw = await store!.read();
        if (raw != null) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          if (data['version'] != 1) throw StateError('Stored session invalid');
          session = NeorangAuthSession(data['credential'] as String,
              data['account'] as String, DateTime.parse(data['expires'] as String));
        }
      }
      if (session == null) return;
      // Persist intent before attempting any network request. A crash or network
      // failure cannot turn this credential into an active restored session.
      await _save(session, logoutPending: true);
      onStage?.call('Logout request');
      await client.logout(session.credential).timeout(operationTimeout);
      await store?.clear();
      _session = null;
    } catch (_) {
      throw StateError('Logout failed; retry logout');
    } finally {
      _busy = false;
    }
  }

  void _clearPending() {
    _transaction = null;
    _verifier = null;
  }
}
