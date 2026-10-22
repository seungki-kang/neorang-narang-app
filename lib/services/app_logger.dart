part of '../main.dart';

enum AppLogEvent { completionSaveFailed, storageReadFailed }

/// Only fixed event names are accepted. Never pass names or reflection text.
abstract final class AppLogger {
  static void error(AppLogEvent event) {
    debugPrint('level=ERROR event=${event.name}');
  }
}
