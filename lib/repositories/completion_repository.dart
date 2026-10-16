part of '../main.dart';

class CompletionRepository implements CompletionStore {
  static const String _storageKey = 'neorang_narang_completion_records_v1';

  @override
  Future<List<CompletionRecord>> loadAll() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final String? stored = preferences.getString(_storageKey);
    if (stored == null) return [];

    try {
      final List<dynamic> decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .map(
            (item) => CompletionRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      throw const StorageReadException();
    }
  }

  @override
  Future<void> add(CompletionRecord record) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final List<CompletionRecord> records = await loadAll();
    for (final item in records) {
      if (item.id == record.id) {
        if (!item.hasSameCompletionContent(record)) {
          throw StateError('completion_identity_conflict');
        }
        return;
      }
    }
    records.add(record);
    final bool saved = await preferences.setString(
      _storageKey,
      jsonEncode(records.map((item) => item.toJson()).toList()),
    );
    if (!saved) throw StateError('completion_write_failed');
  }

  @override
  Future<int> countForCourse(int courseNumber) async {
    final List<CompletionRecord> records = await loadAll();
    return records
        .where((record) => record.courseNumber == courseNumber)
        .length;
  }

  @override
  Future<List<CompletionRecord>> pendingGraceRecords() async {
    final List<CompletionRecord> records = await loadAll();
    return records
        .where((record) => record.graceReflectionPending)
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  }

  @override
  Future<void> saveGraceReflection(String recordId, String reflection) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final List<CompletionRecord> records = await loadAll();
    final List<CompletionRecord> updated = records
        .map(
          (record) => record.id == recordId
              ? record.withGraceReflection(reflection)
              : record,
        )
        .toList();
    final bool saved = await preferences.setString(
      _storageKey,
      jsonEncode(updated.map((item) => item.toJson()).toList()),
    );
    if (!saved) throw StateError('completion_write_failed');
  }
}
