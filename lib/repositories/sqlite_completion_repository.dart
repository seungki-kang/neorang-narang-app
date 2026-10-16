part of '../main.dart';

class SqliteCompletionRepository implements CompletionEditingStore {
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
      graceReflectionPending: (row['grace_reflection_pending'] as int) == 1,
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
    await database.transaction((txn) async {
      if (await _deleted(txn, record.id)) {
        throw StateError('completion_deleted');
      }
      final existing = await txn.query(
        StorageSchema.completionTable,
        where: 'id = ?',
        whereArgs: [record.id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        if (!_fromRow(existing.single).hasSameCompletionContent(record)) {
          throw StateError('completion_identity_conflict');
        }
        return;
      }
      await txn.insert(StorageSchema.completionTable, _toRow(record));
    });
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
    final count = await database.update(
      StorageSchema.completionTable,
      {'grace_reflection': reflection, 'grace_reflection_pending': 0},
      where: 'id = ?',
      whereArgs: [recordId],
    );
    if (count != 1) throw StateError('completion_missing');
  }

  Future<bool> _deleted(DatabaseExecutor db, String id) async =>
      (await db.query(
        StorageSchema.deletedTable,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      )).isNotEmpty;
  Future<CompletionRecord?> _find(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      StorageSchema.completionTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<CompletionRecord?> findById(String id) async =>
      _find(await _appDatabase.database, id);
  @override
  Future<List<String>> deletedIds() async =>
      (await (await _appDatabase.database).query(StorageSchema.deletedTable))
          .map((r) => r['id'] as String)
          .toList();
  @override
  Future<bool> wasDeleted(String id) async =>
      _deleted(await _appDatabase.database, id);
  CompletionRecovery _recovery(Map<String, Object?> row) {
    try {
      final entry = CompletionRecovery.fromJson(
        Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
      );
      if (entry.id != row['id'] || entry.record.id != row['record_id']) {
        throw const StorageReadException();
      }
      return entry;
    } catch (_) {
      throw const StorageReadException();
    }
  }

  @override
  Future<List<CompletionRecovery>> listRecoveries() async =>
      (await (await _appDatabase.database).query(StorageSchema.recoveryTable))
          .map(_recovery)
          .toList();
  @override
  Future<void> stageRecovery(CompletionRecovery entry) async {
    CompletionRecovery.fromJson(entry.toJson());
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      if (await _deleted(txn, entry.record.id)) {
        throw StateError('completion_deleted');
      }
      final rows = await txn.query(
        StorageSchema.recoveryTable,
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      if (rows.isNotEmpty) {
        final old = _recovery(rows.single);
        if (!sameCompletion(old.record, entry.record) ||
            (old.before == null) != (entry.before == null) ||
            (old.before != null &&
                !sameCompletion(old.before!, entry.before!))) {
          throw StateError('recovery_conflict');
        }
        await txn.update(
          StorageSchema.recoveryTable,
          {'payload': jsonEncode(entry.toJson())},
          where: 'id = ?',
          whereArgs: [entry.id],
        );
      } else {
        await txn.insert(StorageSchema.recoveryTable, {
          'id': entry.id,
          'record_id': entry.record.id,
          'payload': jsonEncode(entry.toJson()),
        });
      }
    });
  }

  @override
  Future<void> retryRecovery(String recoveryId) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        StorageSchema.recoveryTable,
        where: 'id = ?',
        whereArgs: [recoveryId],
      );
      if (rows.isEmpty) return;
      final entry = _recovery(rows.single);
      if (await _deleted(txn, entry.record.id)) {
        throw StateError('completion_deleted');
      }
      final current = await _find(txn, entry.record.id);
      final saved = applyRecovery(entry, current);
      if (current == null) {
        await txn.insert(StorageSchema.completionTable, _toRow(saved));
      } else if (!sameCompletion(saved, current)) {
        final count = await txn.update(
          StorageSchema.completionTable,
          {
            'grace_reflection': saved.graceReflection,
            'grace_reflection_pending': saved.graceReflectionPending ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [saved.id],
        );
        if (count != 1) throw StateError('completion_missing');
      }
      await txn.delete(
        StorageSchema.recoveryTable,
        where: 'id = ?',
        whereArgs: [recoveryId],
      );
    });
  }

  @override
  Future<void> discardRecovery(String recoveryId) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        StorageSchema.recoveryTable,
        where: 'id = ?',
        whereArgs: [recoveryId],
      );
      if (rows.isEmpty) return;
      final entry = _recovery(rows.single);
      if (entry.before == null && await _find(txn, entry.record.id) == null) {
        await txn.insert(StorageSchema.deletedTable, {
          'id': entry.record.id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.delete(
        StorageSchema.recoveryTable,
        where: 'id = ?',
        whereArgs: [recoveryId],
      );
    });
  }

  @override
  Future<void> deleteById(String id) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.insert(StorageSchema.deletedTable, {
        'id': id,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.delete(
        StorageSchema.recoveryTable,
        where: 'record_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        StorageSchema.completionTable,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (await _find(txn, id) != null) {
        throw StateError('completion_delete_failed');
      }
    });
  }
}
