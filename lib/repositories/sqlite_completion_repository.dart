part of '../main.dart';

class SqliteCompletionRepository implements CompletionStore {
  SqliteCompletionRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  CompletionRecord _fromRow(Map<String, Object?> row) {
    return CompletionRecord(
      id: row['id'] as String,
      courseNumber: row['course_number'] as int,
      courseTitle: row['course_title'] as String,
      participationMode: row['participation_mode'] == 'together'
          ? ParticipationMode.together
          : ParticipationMode.solo,
      myName: row['my_name'] as String,
      partnerName: row['partner_name'] as String,
      completedAt: DateTime.parse(row['completed_at'] as String),
      mySignedAt: DateTime.parse(row['my_signed_at'] as String),
      partnerSignedAt: row['partner_signed_at'] == null
          ? null
          : DateTime.parse(row['partner_signed_at'] as String),
      graceReflection: row['grace_reflection'] as String,
      graceReflectionPending:
          (row['grace_reflection_pending'] as int) == 1,
    );
  }

  Map<String, Object?> _toRow(CompletionRecord record) {
    return {
      'id': record.id,
      'course_number': record.courseNumber,
      'course_title': record.courseTitle,
      'participation_mode': record.participationMode.name,
      'my_name': record.myName,
      'partner_name': record.partnerName,
      'completed_at': record.completedAt.toIso8601String(),
      'my_signed_at': record.mySignedAt.toIso8601String(),
      'partner_signed_at': record.partnerSignedAt?.toIso8601String(),
      'grace_reflection': record.graceReflection,
      'grace_reflection_pending': record.graceReflectionPending ? 1 : 0,
    };
  }

  @override
  Future<List<CompletionRecord>> loadAll() async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      StorageSchema.completionTable,
      orderBy: 'completed_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> add(CompletionRecord record) async {
    final Database database = await _appDatabase.database;
    await database.insert(
      StorageSchema.completionTable,
      _toRow(record),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<int> countForCourse(int courseNumber) async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> result = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM ${StorageSchema.completionTable} '
      'WHERE course_number = ?',
      [courseNumber],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<List<CompletionRecord>> pendingGraceRecords() async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      StorageSchema.completionTable,
      where: 'grace_reflection_pending = ?',
      whereArgs: [1],
      orderBy: 'completed_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> saveGraceReflection(String recordId, String reflection) async {
    final Database database = await _appDatabase.database;
    await database.update(
      StorageSchema.completionTable,
      {
        'grace_reflection': reflection,
        'grace_reflection_pending': 0,
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }
}
