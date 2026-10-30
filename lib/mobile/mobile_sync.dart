import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

const mobileReturnUri = 'jesuslife-poc://auth/complete/android';
const mobileOrigin = 'http://127.0.0.1:8000';
const mobilePrefix = '/api/v1/mobile';

String randomSecret() =>
    base64UrlEncode(List<int>.generate(32, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');

String newSyncId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

typedef MobileRequest = Future<Map<String, dynamic>> Function(
  String method,
  String path,
  Map<String, dynamic>? body,
  String? bearer,
);

/// Additive, separate auxiliary database. Existing records/recovery DB is never
/// opened here. openDatabase runs onCreate/onUpgrade in one SQLite transaction.
Future<void> createMobileTables(DatabaseExecutor db) async {
  await db.execute(
    'CREATE TABLE mobile_queue (sync_id TEXT PRIMARY KEY, '
    'account TEXT NOT NULL, generation INTEGER NOT NULL, payload TEXT NOT NULL, '
    "status TEXT NOT NULL DEFAULT 'queued', UNIQUE(account,generation))",
  );
  await db.execute(
    'CREATE TABLE mobile_deletions (account TEXT NOT NULL, '
    "generation INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'pending', "
    'PRIMARY KEY(account,generation))',
  );
}

class MobileSync extends ChangeNotifier {
  MobileSync(this.db, this.request);
  final Database db;
  final MobileRequest request;
  String? _token;
  String? account;
  int? _expires;
  String? _verifier;
  String? _transaction;
  int _epoch = 0;
  int? generation;
  bool consentActive = false;
  bool deletionPending = false;
  bool _sending = false;
  bool _revoking = false;
  bool _authenticating = false;
  bool get loggedIn {
    if (_token == null || _expires == null) return false;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 < _expires!;
  }

  String get _bearer {
    if (!loggedIn) throw StateError('login_required');
    return _token!;
  }

  Future<Map<String, dynamic>> _authenticatedRequest(
    String method,
    String path,
    Map<String, dynamic>? body,
    String token,
  ) async {
    final epoch = _epoch;
    try {
      return await request(method, path, body, token);
    } on StateError catch (error) {
      if (error.message == 'login_required' &&
          epoch == _epoch &&
          token == _token) {
        ++_epoch;
        _token = null;
        _expires = null;
        _authenticating = false;
        consentActive = false;
        notifyListeners();
      }
      rethrow;
    }
  }

  void cancelPendingLogin() {
    if (_verifier == null && _transaction == null && !_authenticating) return;
    ++_epoch;
    if (_authenticating) {
      _token = null;
      _expires = null;
      consentActive = false;
    }
    _verifier = null;
    _transaction = null;
    _authenticating = false;
  }

  Future<String> beginLogin() async {
    if (loggedIn || _authenticating) throw StateError('login_in_progress');
    final epoch = ++_epoch;
    _verifier = randomSecret();
    final challenge = base64UrlEncode(
      sha256.convert(ascii.encode(_verifier!)).bytes,
    ).replaceAll('=', '');
    final result = await request('POST', '$mobilePrefix/login-transactions', {
      'challenge': challenge,
      'return_uri': mobileReturnUri,
    }, null);
    if (epoch != _epoch) throw StateError('login_cancelled');
    _transaction = result['transaction'] as String;
    final url = result['authorize_url'] as String;
    final parsed = Uri.parse(url);
    if (parsed.origin != mobileOrigin ||
        parsed.path != '$mobilePrefix/authorize') {
      throw StateError('invalid_authorize_url');
    }
    return url;
  }

  Future<void> finishLogin(String value) async {
    final uri = Uri.parse(value);
    if (uri.scheme != 'jesuslife-poc' ||
        uri.authority != 'auth' ||
        uri.path != '/complete/android' ||
        uri.fragment.isNotEmpty ||
        uri.queryParametersAll.length != 2 ||
        uri.queryParametersAll.values.any((v) => v.length != 1) ||
        _transaction == null ||
        _verifier == null ||
        _authenticating ||
        uri.queryParameters['transaction'] != _transaction) {
      throw StateError('invalid_handoff');
    }
    final epoch = _epoch;
    final verifier = _verifier!;
    final transaction = _transaction!;
    _authenticating = true;
    _verifier = null;
    _transaction = null;
    try {
      final result = await request('POST', '$mobilePrefix/session-exchange', {
        'transaction': transaction,
        'code': uri.queryParameters['code'],
        'verifier': verifier,
        'return_uri': mobileReturnUri,
      }, null);
      if (epoch != _epoch) throw StateError('login_cancelled');
      _token = result['access_token'] as String;
      _expires = result['expires_at'] as int;
      account = result['sub'] as String;
      generation = null;
      consentActive = false;
      await resumeDeletion();
      if (epoch != _epoch) throw StateError('login_cancelled');
      await refreshStatus();
      if (epoch != _epoch) throw StateError('login_cancelled');
    } finally {
      if (epoch == _epoch) _authenticating = false;
      notifyListeners();
    }
  }

  Future<void> refreshStatus() async {
    final epoch = _epoch;
    final result = await _authenticatedRequest(
      'GET',
      '$mobilePrefix/consent',
      null,
      _bearer,
    );
    if (epoch != _epoch) return;
    generation = result['generation'] as int;
    consentActive = result['active'] as bool;
    notifyListeners();
  }

  Future<void> grant() async {
    final epoch = _epoch;
    await resumeDeletion();
    if (epoch != _epoch) return;
    if (deletionPending) throw StateError('deletion_pending');
    final result = await _authenticatedRequest(
      'POST',
      '$mobilePrefix/consent',
      null,
      _bearer,
    );
    if (epoch != _epoch) return;
    generation = result['generation'] as int;
    consentActive = result['active'] as bool;
    notifyListeners();
  }

  Future<void> selectSynthetic(int course) async {
    if (!loggedIn ||
        !consentActive ||
        generation == null ||
        _revoking ||
        deletionPending) {
      throw StateError('consent_required');
    }
    // Immutable account/generation/UUID snapshot. Never reads completion records.
    final owner = account!;
    final gen = generation!;
    final id = newSyncId();
    final payload = {
      'sync_id': id,
      'generation': gen,
      'course_number': course,
      'participation_mode': 'solo',
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'synthetic': true,
    };
    await db.transaction((txn) async {
      if (_revoking ||
          !consentActive ||
          owner != account ||
          gen != generation) {
        throw StateError('selection_cancelled');
      }
      final deleted = await txn.query(
        'mobile_deletions',
        where: 'account=? AND generation>=?',
        whereArgs: [owner, gen],
        limit: 1,
      );
      if (deleted.isNotEmpty) throw StateError('consent_revoked');
      await txn.insert('mobile_queue', {
        'sync_id': id,
        'account': owner,
        'generation': gen,
        'payload': jsonEncode(payload),
        'status': 'queued',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    notifyListeners();
  }

  Future<void> send() async {
    if (_sending || _revoking || deletionPending || !consentActive) {
      throw StateError('send_unavailable');
    }
    final token = _bearer;
    final epoch = _epoch;
    final owner = account!;
    final gen = generation;
    _sending = true;
    try {
      final rows = await db.query(
        'mobile_queue',
        where: 'account=? AND generation=? AND status IN (?, ?)',
        whereArgs: [owner, gen, 'queued', 'sent'],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('select_synthetic_first');
      if (epoch != _epoch ||
          owner != account ||
          gen != generation ||
          _revoking ||
          deletionPending ||
          !consentActive) {
        return;
      }
      final row = rows.single;
      await _authenticatedRequest(
        'POST',
        '$mobilePrefix/synthetic-completion',
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        token,
      );
      if (epoch != _epoch ||
          owner != account ||
          gen != generation ||
          _revoking ||
          deletionPending ||
          !consentActive) {
        return;
      }
      await db.update(
        'mobile_queue',
        {'status': 'sent'},
        where: 'sync_id=? AND account=? AND generation=? AND status=?',
        whereArgs: [row['sync_id'], owner, gen, 'queued'],
      );
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> revoke() async {
    if (account == null || generation == null || generation! < 1) {
      throw StateError('known_consent_required');
    }
    final owner = account!;
    final gen = generation!;
    final epoch = _epoch;
    // Persist intent BEFORE the network. In-flight upload responses cannot undo it.
    _revoking = true;
    consentActive = false;
    deletionPending = true;
    notifyListeners();
    try {
      await db.transaction((txn) async {
        await txn.insert('mobile_deletions', {
          'account': owner,
          'generation': gen,
          'status': 'pending',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.update(
          'mobile_queue',
          {'status': 'cancelled'},
          where: 'account=? AND generation<=?',
          whereArgs: [owner, gen],
        );
      });
      if (epoch != _epoch || owner != account) {
        throw StateError('same_account_login_required');
      }
      await resumeDeletion();
    } finally {
      _revoking = false;
      notifyListeners();
    }
  }

  Future<bool> resumeDeletion() async {
    final owner = account;
    if (owner == null) return false;
    final epoch = _epoch;
    final rows = await db.query(
      'mobile_deletions',
      where: 'account=? AND status=?',
      whereArgs: [owner, 'pending'],
    );
    if (epoch != _epoch || owner != account) return false;
    deletionPending = rows.isNotEmpty;
    for (final row in rows) {
      if (epoch != _epoch || owner != account) return false;
      final result = await _authenticatedRequest(
        'POST',
        '$mobilePrefix/consent/revoke',
        {'generation': row['generation']},
        _bearer,
      );
      if (epoch != _epoch || owner != account) return false;
      if (result['deletion_status'] != 'complete' ||
          (result['deletion_through'] as int) < (row['generation'] as int)) {
        throw StateError('deletion_unconfirmed');
      }
      await db.update(
        'mobile_deletions',
        {'status': 'confirmed'},
        where: 'account=? AND generation=?',
        whereArgs: [owner, row['generation']],
      );
    }
    if (epoch == _epoch) deletionPending = false;
    notifyListeners();
    return rows.isNotEmpty;
  }

  Future<void> logout() async {
    final token = _token;
    ++_epoch;
    _token = null;
    _expires = null;
    _authenticating = false;
    _transaction = null;
    _verifier = null;
    consentActive = false;
    // Keep last owner/generation to allow offline withdrawal of that owner's queue.
    notifyListeners();
    if (token != null) {
      await request('POST', '$mobilePrefix/logout', null, token);
    }
  }
}
