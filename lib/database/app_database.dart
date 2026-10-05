part of '../main.dart';

class AppDatabase {
  Database? _database;

  Future<Database> get database async {
    final Database? openedDatabase = _database;
    if (openedDatabase != null) return openedDatabase;

    final String databaseDirectory = await getDatabasesPath();
    final String databasePath = path_util.join(
      databaseDirectory,
      StorageSchema.databaseName,
    );

    final Database createdDatabase = await openDatabase(
      databasePath,
      version: StorageSchema.databaseVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeDatabase,
    );
    _database = createdDatabase;
    return createdDatabase;
  }

  Future<void> _createTables(Database database, int version) async {
    await database.execute('''
      CREATE TABLE ${StorageSchema.draftTable} (
        id TEXT PRIMARY KEY,
        course_number INTEGER NOT NULL,
        course_title TEXT NOT NULL,
        participation_mode TEXT NOT NULL,
        my_display_name TEXT NOT NULL,
        partner_display_name TEXT NOT NULL,
        first_asker_is_me INTEGER NOT NULL,
        current_question_index INTEGER NOT NULL,
        saved_at TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE ${StorageSchema.completionTable} (
        id TEXT PRIMARY KEY,
        course_number INTEGER NOT NULL,
        course_title TEXT NOT NULL,
        participation_mode TEXT NOT NULL,
        my_name TEXT NOT NULL,
        partner_name TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        my_signed_at TEXT NOT NULL,
        partner_signed_at TEXT,
        grace_reflection TEXT NOT NULL,
        grace_reflection_pending INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_completion_course
      ON ${StorageSchema.completionTable}(course_number)
    ''');
    await database.execute('''
      CREATE INDEX idx_completion_date
      ON ${StorageSchema.completionTable}(completed_at)
    ''');
  }

  Future<void> _upgradeDatabase(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    // 다음 데이터베이스 버전에서 순차적인 migration을 추가합니다.
  }
}
