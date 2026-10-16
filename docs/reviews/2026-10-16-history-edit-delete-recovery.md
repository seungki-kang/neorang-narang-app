# 문답 기록 수정·삭제 및 저장 대기 복구 — 2026-10-16

후속 정정: 옛 보관 화면/데이터 연결 누락을 수정한 최신 결과는 [Android 라우트 수정 보고서](2026-10-16-unsaved-route-android-fix.md)를 따른다. 아래 내용은 최초 구현 당시의 기록이다.

## 보호 및 체크포인트
- 시작 브랜치: feature/keep-screen-awake. 수정 14 + 미추적 41 = 55개, 스테이징 없음.
- 앞선 작업 전 analyze PASS, expanded test 55개 PASS. 이번 체크포인트 APK 빌드 PASS (assembleDebug 23.0s), diff --check PASS.
- 55개 전체 내용을 읽고 파일 유형·민감정보 패턴을 검사. 앱 17, 테스트 8, 문서 15, 백업 11, 테스트 로그 4. 의존성/플랫폼 생성 파일, 빌드 결과물, SQLite DB/사용자 데이터 파일, 인증정보 파일은 변경 목록에 없음. 비밀정보 패턴 발견 없음.
- 원래 40개(앱17+테스트8+문서15)와 .gitignore, 점검 보고서로 42개만 명시적으로 스테이징.
- 커밋: 8762961af0aebcadf993152007061f826752e770, Checkpoint: preserve tested storage and screen-awake work.
- 체크포인트 후 working tree clean 확인 후 feature/history-edit-delete-recovery 생성.
- 백업11·로그4는 제외하고 원래 경로에 보존. 빌드/IDE/툴 캐시/DB·journal/WAL/APK/키스토어/.env·인증 파일/백업/임시 파일 제외 규칙 보완. 제외 파일의 존재·크기 유지 재확인.
- 체크포인트 이후 추가 커밋·push 없음. reset/restore/checkout --/clean 또는 사용자 DB 열기·삭제·초기화 없음.
- 포함·제외 전체 경로는 2026-10-16-checkpoint-audit.md 참조.

## 구현 전 구조와 실제 원인
기존 CompletionRecord.id와 SQLite TEXT PRIMARY KEY가 안정적인 식별자다. 재시도에서 기존 ID를 재사용하며 날짜나 목록 순번으로 기존 ID를 재부여하지 않았다. GraceDraft.id와 pendingRecord.id가 완료 ID에 연결된다.

기존 보관함은 GraceConflictRecovery.resolve가 두 원본과 선택 결과를 SharedPreferences에 저장한 역사 사본이다. 저장 실패 대기열이 아니어서 제목만 바꾸고 사본을 자동 재저장하면 이미 처리된 기록을 덮어쓸 위험이 있었다. 기존 사본은 '나의 문답 기록 → 이전 복구 원본'으로 유지하고, 실제 미완료 GraceDraft 및 새 영구 대기 작업만 '저장되지 않은 기록'으로 보여준다.

기존 상세는 읽기 전용 bottom sheet, 계약에는 수정/삭제/영구 대기열 메서드가 없었다. ChapterProgress는 완료 건수에서 stars=count~/50, season=stars+1, countInSeason=count%50으로 계산한다.

## 데이터 흐름
### 수정
목록 카드 → CompletionDetailPage → CompletionActions → CompletionEditingStore → SQLite 구현. 은혜 본문·graceReflectionPending만 변경한다. id/장/제목/참여방식/참여자/완료시각/서명은 그대로다. 은혜 입력은 trim 후 빈 값 거부, 마음에 담기 전환은 기존 본문 제거 확인을 받는다. 저장 대기 작업을 먼저 영구 저장하고, 트랜잭션에서 기존 값 또는 이미 반영된 값과 비교 후 동일 ID UPDATE + 해당 대기 작업 DELETE. 다른 화면에서 값이 달라졌으면 덮어쓰지 않는다. 저장 중 버튼·뒤로가기 잠금, 실패 시 입력과 기존 기록 유지. 성공 시 상세와 목록을 즉시 다시 조회한다.

### 삭제
정확한 확인 문구 → Repository.deleteById → 트랜잭션으로 해당 완료/대기 작업 삭제 + 삭제 ID 표식 저장 → 삭제 재조회 확인 → 목록 갱신 → 상세 pop. 연결된 은혜 초안/이전 복구 원본이 있으면 함께 정리한다고 확인창에 알린다. 다른 ID는 변경하지 않는다. 취소·실패는 선행 UI 삭제가 없다. 응답 유실 시 삭제 표식과 부재를 재조회해 결과를 확인한다.

SharedPreferences에 남은 과거 이전 사본·은혜 초안·충돌 사본은 삭제 대상 ID만 후속 정리한다. 두 저장 기술 간 트랜잭션은 불가능하므로 실패하면 삭제 표식으로 재생성을 차단하고 다음 홈/대기 목록 조회에서 재시도한다. 이 경우 완료 삭제 성공과 후속 정리 대기를 구분해 사용자에게 안내한다. 손상된 원문은 자동 덮어쓰지 않는다.

### 복구
CompletionRecovery는 recordId, 수정 전 snapshot(수정일 때만), 저장 대기 snapshot, 마지막 시도 시각을 저장한다. 작업 ID는 new:recordId 또는 edit:recordId이며 목록 순번을 사용하지 않는다. 신규 재시도는 같은 PK로 기존 일치 내용을 확인하는 idempotent insert-or-verify이며, 수정 재시도는 UPDATE만 사용하고 삭제된 기록을 INSERT하지 않는다. 저장·해당 복구 삭제는 SQLite의 같은 transaction이다. 실패는 둘 다 rollback, 다른 복구는 유지한다. 이미 반영된 내용이 남으면 ID/내용 비교로 안전하게 정리한다. 자동 정리 자체가 실패하면 대기 카드를 유지한다.

임시 기록 삭제는 정상 완료를 삭제하지 않는다. 신규 미완료 작업을 버리는 경우 지연된 저장을 막기 위한 해당 ID 표식만 남긴다. 기존 GraceDraft는 서명 정보가 없으면 서명/은혜 이어쓰기로 연결한다. 오래된 초안에는 저장 시각을 지어내지 않고 '이전 기록에 시각 정보가 없습니다'를 표시한다. 홈은 로딩 완료 후 실제 대기 개수가 1개 이상일 때만 메뉴/개수를 표시한다.

## DB 및 호환성
- 사용자 요청에 따라 SQLite DB version 1 → 2. 기존 적용 migration을 수정하거나 완료·문답 테이블을 재생성하지 않고 completion_recoveries, deleted_completion_ids와 인덱스만 추가한다.
- 새 DB 생성에도 같은 v2 추가 테이블을 생성한다. 테스트 주입용 AppDatabase 경로/연결은 기본 앱 경로를 변경하지 않는다.
- 실제 SQLite 파일 v1 fixture를 열어 완료 모든 필드와 문답 위치 보존, v2 승격, 종료 후 대기 기록 재조회·재저장을 검증했다.
- 웹/그 외 플랫폼은 단일 v2 JSON envelope에 완료/대기/삭제 표식을 함께 쓰고 직렬화한다. v1 원본은 읽기 호환하며 v2가 생긴 뒤에는 v2가 기준이다. 사용자가 기록을 삭제하면 해당 ID의 이전 사본도 정리한다.
- CompletionStore 읽기/기존 완료 계약을 보존하고 수정 기능용 CompletionEditingStore를 추가했다. 새 계약을 사용하는 테스트 fake는 전체 계약을 구현한다. 기존 읽기/서명 전용 fake는 지원하지 않는 수정 동작을 가장하지 않는다.
- DB v2 사용 후 이전 APK 재설치만으로 데이터 롤백을 보장할 수 없다. 사용자 DB 파일 백업/복원 절차는 별도 검증 필요.

## 횟수와 시즌
수정·수정 재시도는 행을 추가하지 않는다. 삭제 후 목록은 loadAll, 홈 복귀 시 장별 loadAll 결과로 다시 계산한다. 50→49 삭제 시 시즌2/0회 → 시즌1/49회 및 2장 건수 불변을 SQLite와 UI에서 검증했다.

## 변경 파일 — 기능/테스트/의존성
- lib/data/storage_schema.dart
- lib/database/app_database.dart
- lib/main.dart
- lib/pages/completion_history_page.dart
- lib/pages/completion_signature_page.dart
- lib/pages/home_page.dart
- lib/pages/pending_grace_page.dart
- lib/repositories/completion_repository.dart
- lib/repositories/grace_draft_repository.dart
- lib/repositories/sqlite_completion_repository.dart
- test/grace_draft_test.dart
- test/question_draft_save_regression_test.dart
- pubspec.yaml
- pubspec.lock
- lib/models/completion_recovery.dart
- lib/pages/completion_detail_page.dart
- lib/pages/unsaved_records_page.dart
- lib/repositories/completion_editing_store.dart
- lib/services/completion_actions.dart
- test/history_recovery_repository_test.dart
- test/history_recovery_widget_test.dart
- 이 검토 보고서

## 요청한 전체 format으로만 변경된 파일
- lib/app.dart
- lib/data/question_data.dart
- lib/models/chapter_progress.dart
- lib/models/completion_record.dart
- lib/models/participation_mode.dart
- lib/models/question_draft.dart
- lib/models/question_item.dart
- lib/pages/course_selection_page.dart
- lib/pages/grace_reflection_page.dart
- lib/pages/participant_setup_page.dart
- lib/pages/preparation_page.dart
- lib/pages/usage_guide_page.dart
- lib/repositories/participant_preferences.dart
- lib/repositories/question_draft_repository.dart
- lib/repositories/sqlite_question_draft_repository.dart
- lib/services/storage_failure.dart
- lib/services/storage_initializer.dart
- lib/utils/name_utils.dart
- lib/utils/text_utils.dart
- lib/widgets/continue_question_card.dart
- lib/widgets/progress_card.dart
- test/completion_flow_regression_test.dart
- test/grace_conflict_recovery_test.dart
- test/grace_navigation_test.dart
- test/participant_preferences_test.dart
- test/storage_protection_test.dart
- test/widget_test.dart
교재 question_data.dart의 문자열 목록을 체크포인트와 비교하여 원문 보존 확인. 내용 변경 없이 포맷만 적용했다. Wakelock enable/disable 및 의존성 유지.

## 테스트 및 기존 테스트 변경 이유
신규 history_recovery_repository_test.dart: 32개. SharedPreferences/실제 SQLite의 ID·시각·서명·건수 보존, 양방향 상태 전환, 충돌 보호, 삭제 대상 격리, 50→49 시즌, 신규/수정 반복 재시도, 임시 삭제, 삭제 후 부활 방지, 이미 완료된 대기 정리, 불변 필드 거부, 저장/삭제 응답 유실, INSERT/UPDATE/DELETE 및 대기 삭제 trigger 실패 rollback, UPDATE 경로의 INSERT 금지, v1 파일 upgrade·reopen.

신규 history_recovery_widget_test.dart: 14개. 상세·목록 갱신, 공백 거부, 마음에 담기 확인/취소/복원, 저장 실패 입력/원본/영구 대기 보존 및 화면 재생성, 중복 저장 잠금, 삭제 취소/성공/실패, 임시 삭제 범위, 복구 실패 카드 유지, 삭제 중 잠금, 홈 시즌 갱신, 대기 0/2개 표시.

기존 question_draft_save_regression_test의 홈 메뉴 4개는 사용자 요청 '대기가 있을 때만 메뉴'에 맞게 기대를 변경. grace_draft_test의 완료 정리 검사는 로딩 중에도 있는 시작 버튼 대신 ProgressCard를 기다리도록 강화했다. 테스트 삭제 없음. 나머지 기존 테스트는 format만 적용.

중간 실패: 신규 SQLite 생성에서 추가 테이블 누락을 실제 테스트가 발견하여 생성 경로 수정. 테스트의 late final 재할당은 1회 초기화로 변경. 직렬 큐가 완료 후 해제되지 않아 이전 fakeAsync 환경이 남는 문제는 완료 시 queue barrier 해제로 수정. 기존 grace 대기는 중지·조사 후 명확한 완료 상태와 제한된 pump로 해결. 화면 재생성 테스트는 Navigator까지 실제 폐기하도록 변경. 분석 스타일 지적도 수정. 최종 성공으로 이전 실패 로그를 덮어쓰지 않았다.

## 최종 검증
- dart format lib test: PASS, 최종 50 files / 0 changed.
- flutter analyze: PASS, exit 0, No issues found (2.2s).
- flutter test --reporter expanded: PASS, exit 0, 101 tests (기존55 + 신규46), 8초.
- flutter build apk --debug: PASS, exit 0, assembleDebug 22.9s. APK: build/app/outputs/flutter-apk/app-debug.apk (198824467 bytes).
- git diff --check: PASS. 스테이징 없음, 마지막 커밋은 체크포인트 그대로.

## 에뮬레이터 수동 확인 순서 — NOT_RUN
1. 사용자 데이터가 없는 시험 기기 또는 별도 복제/백업된 테스트 기기를 준비. 기존 사용자 기록을 삭제하는 실험은 하지 않는다.
2. adb -s <기기ID> install -r build/app/outputs/flutter-apk/app-debug.apk 로 업데이트. 서명 불일치 시 삭제/초기화로 우회하지 않는다.
3. 앱 실행 → 기존 완료와 진행 문답의 ID/내용/서명시각/장별 횟수가 유지되는지 확인.
4. 테스트 완료 카드 → 상세 → 수정 → 은혜 저장. 날짜/참여자/서명/총횟수 불변 및 목록 갱신 확인.
5. 마음에 담기 전환 확인창 취소 후 본문 유지, 승인 후 본문 숨김, 다시 은혜 입력 저장 확인.
6. 시험용 완료의 삭제 확인창 취소 → 건수 유지. 삭제 승인 → 상세 닫힘/해당 카드만 제거/총횟수·1장·2장·n/50 재계산 확인. 가능하면 시험 데이터 50→49 경계 확인.
7. 은혜 작성/서명 전 앱 종료 후 재실행 → 실제 대기 개수와 내용 확인. 서명 없는 대기는 다시 저장으로 서명 확인에 진입.
8. 별도 오류 주입 시험 환경에서 신규 완료 및 수정 저장 실패 유발 → 앱 종료·재실행 → 대기 카드의 기존/대기 내용과 시각 확인. 다시 저장 성공 후 해당 카드만 사라지고 신규는1건/수정은0건 증가 확인. 반복 눌러 중복 없음 확인.
9. 시험용 대기의 임시 기록 삭제 확인창에서 정상 완료가 유지됨을 확인. 연결된 완료 삭제는 해당 대기만 제거하고 다른 대기는 유지됨 확인.
10. 대기를 전부 해결한 뒤 홈 메뉴/경고 없음 확인. 문답 기록의 이전 복구 원본은 이미 처리한 사본이며 대기 건수에 포함되지 않음 확인.

## 남은 위험/미검증
Android/iOS에서 실제 실행·OS 강제 종료·플랫폼 저장 오류 주입·화면 크기별 수동 확인은 NOT_RUN. 실제 SQLite 회귀 검증은 Windows FFI의 독립 synthetic fixture에서 실행했으며 사용자 DB는 열지 않았다. SQLite↔SharedPreferences 사이 정리는 단일 트랜잭션이 아니므로 삭제 표식과 재조회로 보완한다. 손상 legacy 사본은 자동 파괴하지 않아 수동 복구가 필요할 수 있다. 저장 장치 자체가 쓰기를 거부하면 대기 기록의 새 영구 저장까지 보장할 수는 없으며 입력 화면을 유지한다. 기존 평문 저장의 암호화·내보내기·백업 정책은 이번 기능 범위에서 추가하지 않았다.
