part of '../main.dart';

/// 진행 중인 문답 저장 방식이 반드시 제공해야 하는 기능입니다.
///
/// 현재는 SharedPreferences가 구현하고, 이후 SQLite 구현체를 추가합니다.
abstract interface class QuestionDraftStore {
  Future<QuestionDraft?> load();

  Future<void> save(QuestionDraft draft);

  Future<void> clear();
}

/// 완료 기록 저장 방식이 반드시 제공해야 하는 기능입니다.
///
/// 화면은 이 규격만 사용하므로 실제 저장 기술이 바뀌어도 영향을 적게 받습니다.
abstract interface class CompletionStore {
  Future<List<CompletionRecord>> loadAll();

  Future<void> add(CompletionRecord record);

  Future<int> countForCourse(int courseNumber);

  Future<List<CompletionRecord>> pendingGraceRecords();

  Future<void> saveGraceReflection(String recordId, String reflection);
}
