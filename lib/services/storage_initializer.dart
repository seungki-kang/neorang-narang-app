part of '../main.dart';

const String _legacyMigrationKey =
    'neorang_narang_shared_preferences_to_sqlite_v1';

bool get _supportsMobileSqlite {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

Future<void> initializeStorage() async {
  final QuestionDraftRepository legacyDraftStore =
      QuestionDraftRepository();
  final CompletionRepository legacyCompletionStore = CompletionRepository();

  if (!_supportsMobileSqlite) {
    questionDraftRepository = legacyDraftStore;
    completionRepository = legacyCompletionStore;
    return;
  }

  final AppDatabase appDatabase = AppDatabase();
  final SqliteQuestionDraftRepository sqliteDraftStore =
      SqliteQuestionDraftRepository(appDatabase);
  final SqliteCompletionRepository sqliteCompletionStore =
      SqliteCompletionRepository(appDatabase);

  await _migrateLegacyStorage(
    legacyDraftStore: legacyDraftStore,
    legacyCompletionStore: legacyCompletionStore,
    sqliteDraftStore: sqliteDraftStore,
    sqliteCompletionStore: sqliteCompletionStore,
  );

  questionDraftRepository = sqliteDraftStore;
  completionRepository = sqliteCompletionStore;
}

Future<void> _migrateLegacyStorage({
  required QuestionDraftStore legacyDraftStore,
  required CompletionStore legacyCompletionStore,
  required QuestionDraftStore sqliteDraftStore,
  required CompletionStore sqliteCompletionStore,
}) async {
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  if (preferences.getBool(_legacyMigrationKey) == true) return;

  final QuestionDraft? legacyDraft = await legacyDraftStore.load();
  final QuestionDraft? sqliteDraft = await sqliteDraftStore.load();
  if (legacyDraft != null && sqliteDraft == null) {
    await sqliteDraftStore.save(legacyDraft);
  }

  final List<CompletionRecord> legacyRecords =
      await legacyCompletionStore.loadAll();
  for (final CompletionRecord record in legacyRecords) {
    await sqliteCompletionStore.add(record);
  }

  // 기존 데이터는 삭제하지 않습니다. SQLite 복사가 끝난 사실만 기록합니다.
  await preferences.setBool(_legacyMigrationKey, true);
}
