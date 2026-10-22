# 저장 대기 화면 실제 Android 연결 수정 — 2026-10-16

## 기준 및 보호
AGENTS.md와 docs/governance 3개를 다시 확인. feature/history-edit-delete-recovery의 기존 미커밋 변경을 그대로 유지하고 사용자 요청에 따라 수정했다. 커밋/push/reset/restore/checkout --/clean, uninstall/pm clear, DB 삭제/초기화 없음. 실제 기록을 다시 저장하거나 삭제하는 버튼은 누르지 않았다.

## 정확한 원인과 조사
전체 소스/테스트/문서에서 복구 보관함, 저장되지 않은 기록, PendingGracePage, UnsavedRecordsPage 및 두 페이지 파일 참조를 검색했다.

1. 새 unsaved_records_page.dart 파일은 있었지만 실제 클래스 이름은 GraceRecoveryArchivePage였다. 홈은 이 새 대기열 화면을 열었다.
2. completion_history_page.dart의 별도 '이전 복구 원본' 아이콘은 LegacyGraceArchivePage를 열었다. 이 클래스는 grace_draft_repository.dart 안의 읽기 전용 옛 화면이며 AppBar 제목 '복구 보관함'과 버튼 없는 카드 구현이 그대로 남아 있었다. 에뮬레이터에서 관찰한 제목·구성과 정확히 일치한다.
3. 기존 데이터는 SharedPreferences의 neorang_narang_grace_conflict_archive_v1에 있는 사본 1개였다. 완료값과 대기값이 다르며 active GraceDraft는 없었다. 기존 CompletionActions.pending()는 이 사본을 역사 기록으로 제외했다. 따라서 홈의 신규 대기 메뉴는 나타나지 않고, 사용자는 기록 화면의 옛 경로로 사본만 볼 수 있었다.
4. PendingGracePage는 main.dart part만 있었고 실제 라우트 참조는 없었다. 새 화면과 옛 사본 화면이 중복으로 유지된 것이 문제이며 SQLite 저장 실패나 migration 실패가 아니다.
5. 수정 전 설치 APK SHA-256 = 로컬 APK SHA-256 = E415B6B5EAA1D0040BB7D2A8001DF63594C8E1EF98BD48836FE896782DCE060B. 오래된 APK 설치가 원인이 아니었다. 이전 구현의 별도 사본 화면/데이터 연결 누락을 놓친 것이다.

## 수정한 라우트와 데이터 처리
- 홈 및 나의 문답 기록의 조건부 메뉴 → UnsavedRecordsPage.
- PendingGracePage, LegacyGraceArchivePage, GraceRecoveryArchivePage는 파일/공개 진입점을 삭제하지 않고 같은 새 화면을 렌더링하는 호환 래퍼로 통합. 별도 읽기 전용 옛 화면 구현과 옛 제목 제거.
- LegacyRecoveryRepository로 기존 사본을 원본을 바꾸지 않고 목록에 어댑트한다. 기존 완료 ID를 대상으로 하며 사본의 SHA-256으로 작업을 안정적으로 식별한다. 날짜/목록 순번을 ID로 사용하지 않는다. 이미 있던 crypto 패키지를 직접 앱 의존성으로 등록했다.
- 기존 사본은 사용자의 다시 저장 확인 전 완료 내용을 반영하지 않는다. 상세 확인은 읽기 전용이다.
- 수정 재시도는 기존 사본의 완료 snapshot을 기준으로 optimistic UPDATE만 한다. 새 완료 INSERT 금지 trigger로 검증. 더 최신 내용이 있거나 ID/참여자 정보가 다르면 덮어쓰지 않고 대기 보존.
- 실패 후 영구 대기열과 옛 사본이 같은 ID/내용이면 하나의 카드로 합치고, 성공/임시 삭제 때 연결된 해당 사본만 정리한다. 다른 사본/완료는 유지한다.
- 마지막 시도 시각은 재시도할 때만 기록한다. 옛 시각이 없으면 임의 생성하지 않고 정보 없음으로 표시한다. 시각을 기록해도 사본 ID는 바뀌지 않는다.
- 신규 재시도의 동일 ID 중복 방지, SQLite UPDATE/INSERT + 대기 삭제 transaction, 삭제 ID 부활 방지 규칙은 기존 구현 유지. SQLite DB version 2 유지, 이번 수정에 추가 DB migration 없음.
- 임시 기록 삭제 확인창을 사용자 지정 제목/본문으로 변경. 완료 행/횟수/시즌은 변경하지 않는다.
- 홈과 기록 화면 모두 실제 대기 개수만 표시. 마지막 처리 후 메뉴 제거 및 앱 재생성 후 유지 검증.

## 이번 수정 파일
- lib/main.dart
- lib/pages/home_page.dart
- lib/pages/completion_history_page.dart
- lib/pages/pending_grace_page.dart
- lib/pages/unsaved_records_page.dart
- lib/repositories/grace_draft_repository.dart
- lib/repositories/legacy_recovery_repository.dart (신규)
- lib/services/completion_actions.dart
- pubspec.yaml
- pubspec.lock
- test/history_recovery_widget_test.dart
- test/question_draft_save_regression_test.dart
- test/unsaved_records_route_regression_test.dart (신규)
- 이 검토 보고서 및 이전 보고서의 후속 정정 안내

## 테스트 변경 이유 및 결과
기존 테스트 삭제 없음. 기존 두 파일의 화면 클래스 참조를 UnsavedRecordsPage로 바꾸고 사용자 지정 새 카드 라벨/확인 문구를 검사하도록 갱신했다. 실패 기대를 없애거나 저장 검증을 약화하지 않았다.

신규 13개: 홈의 실제 legacy 사본 진입/새 제목·안내·세 버튼/읽기 전용 상세, 성공 후 홈 메뉴 제거와 앱 재생성, 실패 후 원본·카드 유지와 한 번만 완료, 임시 삭제 취소/성공의 완료·시즌 불변, 기록 화면의 옛 경로 통합, 신규 저장 상세 읽기 전용, 옛 2개 공개 진입점의 새 화면 위임, 사본 ID/마지막 시도 안정성, 다른 사본/완료 보존, 최신 수정 덮어쓰기 거부, 실제 SQLite UPDATE-only/중복 거부, 손상 사본 원문 보존.

- dart format lib test: PASS, 52 files.
- flutter analyze: PASS, exit 0, No issues found (2.3s).
- flutter test --reporter expanded: PASS, exit 0, 전체 114개 (기존101 + 신규13), 8초.
- flutter build apk --debug: PASS, exit 0, assembleDebug 12.9s.
- git diff --check: PASS.

## 실제 emulator-5554 확인
- flutter devices: Android 15 API35 emulator-5554 연결 확인.
- adb -s emulator-5554 install -r ...app-debug.apk: Success.
- am start -W: Status ok, COLD.
- 새 설치 APK SHA-256 = 로컬 새 APK SHA-256 = E012D92EBF5CB177B7BCA8FA3B62969835835AA3F659DE24EA35EA0B09C672F8.
- 실제 홈의 '저장되지 않은 기록 1개' 메뉴를 눌렀다. 제목 '저장되지 않은 기록', 정확한 안내, 상태 '수정 저장 대기', 기존/대기 본문 라벨, 마지막 시도 표시 및 내용 확인/다시 저장/임시 기록 삭제 버튼의 존재를 UI 계층에서 확인. 옛 제목은 0개.
- '내용 확인'을 눌러 기존 기록 수정 유형과 양쪽 본문 라벨을 확인 후 확인 버튼으로 닫았다. 실제 내용/이름을 로그나 보고서에 출력하지 않았다.
- 재실행 후 홈 메뉴를 다시 눌러 새 제목·안내·세 버튼이 계속 표시되는 것을 재확인했다. 현재 앱은 새 대기 화면에 열어 두었다.

## 기존 SQLite 기록 보존 근거
설치 전 앱이 옛 읽기 전용 화면에 있음을 확인한 뒤 잠시 force-stop하여 private DB/설정 사본을 사용자 Temp의 비공개 작업 폴더에 복사했다. 원본 DB는 복사를 위한 읽기만 수행했고 수정·삭제하지 않았다. 사본을 readOnly로 검사했다. 설치 후 화면 확인 뒤 같은 방식으로 사본을 얻어 비교했다. 이 사본은 Git/프로젝트 폴더에 추가하지 않았다.

- PRAGMA quick_check: 전후 ok.
- 기존 완료 33개, 1장17 / 2장16: 전후 동일.
- SELECT * FROM completion_records ORDER BY id의 모든 필드 SHA-256: 전후 동일. ID/완료시각/서명/은혜 내용 포함.
- question_drafts 전체: 전후 동일.
- 기존 보관 JSON 문자열: 전후 완전히 동일, 1개 유지.
- 실제 사용자 완료 재저장/임시 삭제/완료 삭제: NOT_RUN. 이 동작들은 synthetic widget/실제 SQLite fixture 회귀 테스트로 검증했고 실제 사용자 기록에는 실행하지 않았다.
- iOS 실제 실행과 강제 전원 차단: NOT_RUN.

## 이전 보고서와 구분
2026-10-16-history-edit-delete-recovery.md의 보관 사본을 별도 옛 화면으로 유지한다는 설계는 이번 수정으로 대체된다. 이전 101개 PASS 기록은 당시 검증이며 최신 결과는 본 문서의 114개 PASS와 Android 실제 경로 확인이다. 기존 미커밋 작업/체크포인트 8762961은 유지했고 추가 커밋/push는 하지 않았다.
