part of '../main.dart';

class SqliteQuestionDraftRepository implements QuestionDraftStore {
  SqliteQuestionDraftRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<QuestionDraft?> load() async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      StorageSchema.draftTable,
      where: 'id = ?',
      whereArgs: [StorageSchema.activeDraftId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final Map<String, Object?> row = rows.first;
    return QuestionDraft(
      courseNumber: row['course_number'] as int,
      courseTitle: row['course_title'] as String,
      participationMode: row['participation_mode'] == 'together'
          ? ParticipationMode.together
          : ParticipationMode.solo,
      myDisplayName: row['my_display_name'] as String,
      partnerDisplayName: row['partner_display_name'] as String,
      firstAskerIsMe: (row['first_asker_is_me'] as int) == 1,
      currentQuestionIndex: row['current_question_index'] as int,
      savedAt: DateTime.parse(row['saved_at'] as String),
    );
  }

  @override
  Future<void> save(QuestionDraft draft) async {
    final Database database = await _appDatabase.database;
    await database.insert(
      StorageSchema.draftTable,
      {
        'id': StorageSchema.activeDraftId,
        'course_number': draft.courseNumber,
        'course_title': draft.courseTitle,
        'participation_mode': draft.participationMode.name,
        'my_display_name': draft.myDisplayName,
        'partner_display_name': draft.partnerDisplayName,
        'first_asker_is_me': draft.firstAskerIsMe ? 1 : 0,
        'current_question_index': draft.currentQuestionIndex,
        'saved_at': draft.savedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clear() async {
    final Database database = await _appDatabase.database;
    await database.delete(
      StorageSchema.draftTable,
      where: 'id = ?',
      whereArgs: [StorageSchema.activeDraftId],
    );
  }
}
