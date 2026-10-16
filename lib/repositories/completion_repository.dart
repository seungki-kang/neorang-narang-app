part of '../main.dart';

/// A single envelope commits records and recovery operations together. v1 is
/// preserved; once v2 exists it is authoritative, including explicit deletions.
class CompletionRepository implements CompletionEditingStore {
  static const _storageKey = 'neorang_narang_completion_records_v1';
  static const stateKey = 'neorang_narang_completion_state_v2';
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

  Future<_CompletionState> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(stateKey);
    try {
      if (raw != null) {
        return _CompletionState.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      }
      final legacy = prefs.getString(_storageKey);
      return _CompletionState(
        legacy == null
            ? []
            : (jsonDecode(legacy) as List)
                  .map(
                    (v) => CompletionRecord.fromJson(
                      Map<String, dynamic>.from(v as Map),
                    ),
                  )
                  .toList(),
        [],
        <String>{},
      );
    } catch (_) {
      throw const StorageReadException();
    }
  }

  Future<void> _write(_CompletionState state) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(stateKey, jsonEncode(state.toJson()))) {
      throw StateError('completion_write_failed');
    }
  }

  @override
  Future<List<CompletionRecord>> loadAll() =>
      _serial(() async => (await _read()).records);
  @override
  Future<CompletionRecord?> findById(String id) async =>
      (await loadAll()).where((r) => r.id == id).firstOrNull;
  @override
  Future<void> add(CompletionRecord record) => _serial(() async {
    final state = await _read();
    if (state.deleted.contains(record.id)) {
      throw StateError('completion_deleted');
    }
    final old = state.records.where((r) => r.id == record.id).firstOrNull;
    applyRecovery(
      CompletionRecovery(record: record, attemptedAt: DateTime.now()),
      old,
    );
    if (old == null) {
      state.records.add(record);
      await _write(state);
    }
  });
  @override
  Future<int> countForCourse(int courseNumber) async =>
      (await loadAll()).where((r) => r.courseNumber == courseNumber).length;
  @override
  Future<List<CompletionRecord>> pendingGraceRecords() async =>
      (await loadAll()).where((r) => r.graceReflectionPending).toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  @override
  Future<void> saveGraceReflection(String recordId, String reflection) =>
      _serial(() async {
        final state = await _read();
        final index = state.records.indexWhere((r) => r.id == recordId);
        if (index < 0) throw StateError('completion_missing');
        state.records[index] = state.records[index].withGraceReflection(
          reflection,
        );
        await _write(state);
      });
  @override
  Future<void> stageRecovery(CompletionRecovery entry) => _serial(() async {
    CompletionRecovery.fromJson(entry.toJson());
    final state = await _read();
    if (state.deleted.contains(entry.record.id)) {
      throw StateError('completion_deleted');
    }
    final old = state.recoveries.where((r) => r.id == entry.id).firstOrNull;
    if (old != null &&
        (!sameCompletion(old.record, entry.record) ||
            (old.before == null) != (entry.before == null) ||
            (old.before != null &&
                !sameCompletion(old.before!, entry.before!)))) {
      throw StateError('recovery_conflict');
    }
    state.recoveries.removeWhere((r) => r.id == entry.id);
    state.recoveries.add(entry);
    await _write(state);
  });
  @override
  Future<List<CompletionRecovery>> listRecoveries() =>
      _serial(() async => (await _read()).recoveries);
  @override
  Future<void> retryRecovery(String recoveryId) => _serial(() async {
    final state = await _read();
    final entry = state.recoveries.where((r) => r.id == recoveryId).firstOrNull;
    if (entry == null) return;
    if (state.deleted.contains(entry.record.id)) {
      throw StateError('completion_deleted');
    }
    final index = state.records.indexWhere((r) => r.id == entry.record.id);
    final saved = applyRecovery(entry, index < 0 ? null : state.records[index]);
    if (index < 0) {
      state.records.add(saved);
    } else {
      state.records[index] = saved;
    }
    state.recoveries.removeWhere((r) => r.id == recoveryId);
    await _write(state);
  });
  @override
  Future<void> discardRecovery(String recoveryId) => _serial(() async {
    final state = await _read();
    final entry = state.recoveries.where((r) => r.id == recoveryId).firstOrNull;
    if (entry == null) return;
    if (entry.before == null &&
        !state.records.any((r) => r.id == entry.record.id)) {
      state.deleted.add(entry.record.id);
    }
    state.recoveries.removeWhere((r) => r.id == recoveryId);
    await _write(state);
  });
  @override
  Future<void> deleteById(String id) => _serial(() async {
    final state = await _read();
    state.records.removeWhere((r) => r.id == id);
    state.recoveries.removeWhere((r) => r.record.id == id);
    state.deleted.add(id);
    await _write(state);
  });
  Future<void> purgeRetainedCopy(String id) => _serial(() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      List<CompletionRecord> old;
      try {
        old = (jsonDecode(raw) as List)
            .map(
              (v) => CompletionRecord.fromJson(
                Map<String, dynamic>.from(v as Map),
              ),
            )
            .toList();
      } catch (_) {
        throw const StorageReadException();
      }
      final remaining = old.where((r) => r.id != id).toList();
      if (remaining.length != old.length &&
          !await prefs.setString(
            _storageKey,
            jsonEncode(remaining.map((r) => r.toJson()).toList()),
          )) {
        throw StateError('legacy_cleanup_failed');
      }
    }
    if (prefs.getString(stateKey) != null) {
      final state = await _read();
      if (state.records.any((r) => r.id == id) ||
          state.recoveries.any((r) => r.record.id == id)) {
        state.records.removeWhere((r) => r.id == id);
        state.recoveries.removeWhere((r) => r.record.id == id);
        state.deleted.add(id);
        await _write(state);
      }
    }
  });
  @override
  Future<List<String>> deletedIds() =>
      _serial(() async => (await _read()).deleted.toList());
  @override
  Future<bool> wasDeleted(String id) =>
      _serial(() async => (await _read()).deleted.contains(id));
}

class _CompletionState {
  _CompletionState(this.records, this.recoveries, this.deleted);
  final List<CompletionRecord> records;
  final List<CompletionRecovery> recoveries;
  final Set<String> deleted;
  factory _CompletionState.fromJson(Map<String, dynamic> json) {
    final state = _CompletionState(
      (json['records'] as List)
          .map(
            (v) =>
                CompletionRecord.fromJson(Map<String, dynamic>.from(v as Map)),
          )
          .toList(),
      (json['recoveries'] as List)
          .map(
            (v) => CompletionRecovery.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          )
          .toList(),
      (json['deleted'] as List).cast<String>().toSet(),
    );
    if (state.records.map((r) => r.id).toSet().length != state.records.length ||
        state.recoveries.map((r) => r.id).toSet().length !=
            state.recoveries.length) {
      throw const StorageReadException();
    }
    return state;
  }
  Map<String, dynamic> toJson() => {
    'records': records.map((r) => r.toJson()).toList(),
    'recoveries': recoveries.map((r) => r.toJson()).toList(),
    'deleted': deleted.toList(),
  };
}
