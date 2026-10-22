# 기존 미커밋 변경 점검 — 2026-10-16

## 범위와 보존
neorang-narang-dev 스킬 및 docs/governance의 COMMON_PRINCIPLES.md, PROJECT_CONTEXT.md, CHECKLIST.md를 적용했다. 브랜치는 feature/history-edit-delete-recovery. 시작 시 수정 41개와 미추적 11개, 총 52개이며 스테이징 없음. 기존 변경을 수정·삭제·되돌리지 않았다. 코드 수정, format, reset, clean, commit, push, 사용자 DB 접근은 하지 않았다. 이 점검 문서만 새로 추가했다.

## 변경 분류
기능/관련 테스트/의존성/기존 보고서 25개, 포맷·줄바꿈만 변경된 파일 27개다. HEAD diff, 문자열을 보존하며 공백과 쉼표를 제외한 토큰 비교, 기존 보고서와 신규 파일 내용을 확인했다. 토큰 비교는 보조 근거이며 전체 Dart 파서 검증은 아니다.

기능 관련 25개:
- lib/data/storage_schema.dart, lib/database/app_database.dart: SQLite v2 및 추가 테이블.
- lib/main.dart: 신규 part와 crypto 연결.
- lib/pages/completion_history_page.dart, completion_signature_page.dart, home_page.dart, pending_grace_page.dart: 상세·저장 대기 화면 연결 및 신규 완료 저장 연결.
- lib/repositories/completion_repository.dart, grace_draft_repository.dart, sqlite_completion_repository.dart: 수정·삭제·재시도·이전 사본 처리.
- lib/models/completion_recovery.dart, lib/pages/completion_detail_page.dart, lib/pages/unsaved_records_page.dart, lib/repositories/completion_editing_store.dart, lib/repositories/legacy_recovery_repository.dart, lib/services/completion_actions.dart: 신규 기능 구현.
- test/grace_draft_test.dart, test/question_draft_save_regression_test.dart: 완료 정리 대기 및 조건부 메뉴 기대 변경.
- test/history_recovery_repository_test.dart, test/history_recovery_widget_test.dart, test/unsaved_records_route_regression_test.dart: 신규 회귀 테스트.
- pubspec.yaml, pubspec.lock: crypto 직접 의존성과 SQLite FFI 테스트 의존성.
- 기존 docs/reviews/2026-10-16-history-edit-delete-recovery.md, 2026-10-16-unsaved-route-android-fix.md.

포맷/줄바꿈 27개:
- lib/app.dart, lib/data/question_data.dart.
- lib/models/chapter_progress.dart, completion_record.dart, participation_mode.dart, question_draft.dart, question_item.dart.
- lib/pages/course_selection_page.dart, grace_reflection_page.dart, participant_setup_page.dart, preparation_page.dart, usage_guide_page.dart.
- lib/repositories/participant_preferences.dart, question_draft_repository.dart, sqlite_question_draft_repository.dart.
- lib/services/storage_failure.dart, storage_initializer.dart.
- lib/utils/name_utils.dart, text_utils.dart.
- lib/widgets/continue_question_card.dart, progress_card.dart.
- test/completion_flow_regression_test.dart, grace_conflict_recovery_test.dart, grace_navigation_test.dart, participant_preferences_test.dart, storage_protection_test.dart, widget_test.dart.

기능 외 포맷 변경이 섞여 있으나 별도 무관한 기능 추가는 발견하지 못했다. question_data.dart의 교재 문자열 변경은 발견하지 못했다. 모델 두 파일은 Git 상태에는 변경이 있으나 일반 diff에는 내용 차이가 없어 줄바꿈 변경으로 분류했다.

## 이번 실행 검증
- D:\flutter\bin\flutter.bat analyze: PASS, exit 0, No issues found, 분석 출력 기준 51.0초. 최초 제한 환경 실행은 출력 없이 대기해 중단했고, 승인된 제한 밖 실행 결과다.
- D:\flutter\bin\flutter.bat test --reporter expanded: PASS, exit 0, 114개, 테스트 진행 출력 00:08. 2분 이상 멈춘 테스트 없음. 의존성 확인 뒤 승인된 제한 밖 환경에서 실행했다.
- git diff --check: PASS, exit 0. CRLF 변환 예고 경고가 있었으나 공백 오류는 없었다.
- format, APK build, Android/iOS 실제 동작, 실제 사용자 DB 업그레이드/백업/복원: NOT_RUN. 기존 보고서의 과거 실행 결과와 이번 결과를 구분한다.

## DB 및 기록 보존 분석
DB version 1→2. onUpgrade는 oldVersion<2에서 completion_recoveries, deleted_completion_ids 및 인덱스만 추가한다. 기존 completion_records와 question_drafts의 삭제/재생성은 없다. 신규 생성도 추가 테이블을 만든다. 이번 전체 테스트에 v1 파일 fixture 업그레이드, 기존 완료 모든 필드와 문답 행 비교, v2 재열기와 대기 재시도가 포함되어 통과했다. 실제 모바일 사용자 DB에 대한 이번 검증은 아니다.

수정은 동일 ID의 은혜 본문/대기 상태만 UPDATE하며 수정 전 snapshot과 충돌을 검사한다. 신규 저장 재시도는 ID 및 내용 확인으로 중복을 방지한다. SQLite 기록 반영과 복구 대기 제거는 같은 트랜잭션이며 실패 rollback 테스트가 있다. SharedPreferences는 완료·대기·삭제 표식을 단일 v2 envelope로 저장하고 v1 읽기를 지원한다. v2 손상 시 v1로 조용히 되돌려 덮어쓰지 않고 읽기 오류로 처리한다.

주의 사항:
1. 현재 삭제는 휴지통 이관이 아니다. completion_detail_page.dart의 확인은 되돌릴 수 없다고 알리고, SqliteCompletionRepository.deleteById는 완료 행과 연결된 복구 payload를 DELETE한다. SharedPreferences 구현도 해당 기록을 제거한다. 삭제 ID 표식은 부활 방지용이며 복원 원본이 아니다. 스킬의 '삭제 기록은 복구 보관함을 거치도록 한다', '복원과 영구 삭제를 구분한다'와 불일치한다. 현재 보관함은 저장 실패/충돌 대기 복구 기능이다.
2. SQLite와 SharedPreferences 후속 정리는 원자적이지 않다. 삭제 표식으로 부활을 방지하고 다음 조회에서 정리를 재시도하지만 손상된 이전 사본의 정리 실패는 pending() 전체 로딩을 실패시킬 수 있다.
3. v2 DB 및 SharedPreferences 사용 뒤 이전 APK 설치만으로 안전한 데이터 롤백을 보장하지 못한다. 백업/복원 절차는 NOT_RUN이다.
4. 저장 장치 쓰기 실패 시 새 복구 payload의 영구 보존 자체를 보장하지 못한다. 기존 평문 저장과 백업 정책도 그대로다.
5. PROJECT_CONTEXT.md에는 DB 버전을 변경하지 않는다는 기준이 남아 있다. 기존 구현 보고서는 과거 사용자 승인에 따른 v2라고 기록하지만, 이번 세션에서 그 승인 자체를 독립 확인하지는 않았다. 기준 문서와 구현의 정합성 확인이 필요하다.

## 커밋 판단
정적 분석과 자동 테스트 기준은 통과했다. 그러나 복원 가능한 삭제 보관함이 요구사항이면 현재 상태의 기능 완료 커밋은 권장하지 않는다. 즉시 영구 삭제가 승인된 의도인지 및 DB v2 기준을 확인하고 판단해야 한다. 포맷 변경 27개는 기능과 구분해 검토할 수 있다. 실제 배포 가능 판정은 이번 범위 밖이며 미실행 항목이 남아 있다. 커밋과 push는 하지 않았다.
