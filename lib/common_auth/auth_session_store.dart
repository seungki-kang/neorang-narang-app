import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class AuthSessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// App-private Android Keystore adapter. No diary/learning record access.
class AndroidAuthSessionStore implements AuthSessionStore {
  AndroidAuthSessionStore(this.binding);
  final String binding;
  static const enabled = kDebugMode && bool.fromEnvironment('NEORANG_PERSIST_LOGIN');
  static const _channel = MethodChannel('jesuslife/session_vault');
  Map<String, Object> get _arguments => {'binding': binding};
  void _check() {
    if (!enabled || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw StateError('Session storage unavailable');
    }
  }
  @override
  Future<String?> read() async {
    _check();
    return _channel.invokeMethod<String>('read', _arguments);
  }
  @override
  Future<void> write(String value) async {
    _check();
    await _channel.invokeMethod<void>('write', {..._arguments, 'value': value});
  }
  @override
  Future<void> clear() async {
    _check();
    await _channel.invokeMethod<void>('clear', _arguments);
  }
}
