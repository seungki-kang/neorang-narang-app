part of '../main.dart';

/// Adapts the existing conflict snapshots without applying their contents on read.
/// IDs use the original immutable snapshots, not array positions or dates.
class LegacyCompletionRecovery {
  LegacyCompletionRecovery(this.snapshot);
  final Map<String, dynamic> snapshot;
  CompletionRecord get before => CompletionRecord.fromJson(
    Map<String, dynamic>.from(snapshot['saved'] as Map),
  );
  GraceDraft get draft =>
      GraceDraft.fromJson(Map<String, dynamic>.from(snapshot['draft'] as Map));
  String get reflection =>
      draft.pendingRecord?.graceReflection ?? draft.reflection;
  CompletionRecord get desired => before.withGraceReflection(reflection);
  String get id => crypto.sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'saved': before.toJson(),
            'draft': draft.toJson(),
            'choice': snapshot['choice'],
          }),
        ),
      )
      .toString();
  DateTime? get attemptedAt => snapshot['lastAttemptAt'] == null
      ? draft.lastAttemptAt
      : DateTime.parse(snapshot['lastAttemptAt'] as String);
}

class LegacyRecoveryRepository {
  static Future<void>? _tail;
  Future<T> _serial<T>(Future<T> Function() work) {
    final previous = _tail;
    final result = previous == null
        ? Future<T>.sync(work)
        : previous.then((_) => work());
    late final Future<void> barrier;
    final completed = result.whenComplete(() {
      if (identical(_tail, barrier)) _tail = null;
    });
    barrier = completed.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    _tail = barrier;
    return completed;
  }

  Future<List<LegacyCompletionRecovery>> list() => _serial(
    () async => (await GraceConflictRecovery.archives())
        .map(LegacyCompletionRecovery.new)
        .toList(),
  );
  Future<void> _write(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(entries);
    if (!await prefs.setString(GraceConflictRecovery.archiveKey, raw) ||
        prefs.getString(GraceConflictRecovery.archiveKey) != raw) {
      throw StateError('legacy_recovery_write_failed');
    }
  }

  Future<void> append(Map<String, dynamic> snapshot) => _serial(() async {
    final entries = await GraceConflictRecovery.archives();
    final id = LegacyCompletionRecovery(snapshot).id;
    if (!entries.any((e) => LegacyCompletionRecovery(e).id == id)) {
      entries.add(snapshot);
      await _write(entries);
    }
  });
  Future<void> markAttempt(String id, DateTime time) => _serial(() async {
    final entries = await GraceConflictRecovery.archives();
    final index = entries.indexWhere(
      (e) => LegacyCompletionRecovery(e).id == id,
    );
    if (index < 0) throw StateError('legacy_recovery_missing');
    entries[index] = {
      ...entries[index],
      'lastAttemptAt': time.toIso8601String(),
    };
    await _write(entries);
  });
  Future<void> remove(String id) => _serial(() async {
    final entries = await GraceConflictRecovery.archives();
    final remaining = entries
        .where((e) => LegacyCompletionRecovery(e).id != id)
        .toList();
    if (entries.length != remaining.length) await _write(remaining);
  });
  Future<void> removeForRecord(String id) => _serial(() async {
    final entries = await GraceConflictRecovery.archives();
    final remaining = entries
        .where(
          (e) =>
              (e['saved'] as Map)['id'] != id &&
              (e['draft'] as Map)['id'] != id,
        )
        .toList();
    if (entries.length != remaining.length) await _write(remaining);
  });
}
