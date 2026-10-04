part of '../main.dart';

/// SQLite 도입 때 사용할 데이터베이스 규격의 기준값입니다.
///
/// 숫자를 바로 코드에 반복해서 쓰지 않고 한곳에서 관리하면
/// 향후 데이터 마이그레이션과 버전 상승이 쉬워집니다.
abstract final class StorageSchema {
  static const String databaseName = 'neorang_narang.db';
  static const int databaseVersion = 1;

  static const String completionTable = 'completion_records';
  static const String draftTable = 'question_drafts';

  static const String activeDraftId = 'active_question_draft';
}
