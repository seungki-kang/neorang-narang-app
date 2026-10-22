# 홈 보관함 및 문답 저장 실패 처리 — 2026-10-14

## 기준과 범위
AGENTS.md, docs/governance/COMMON_PRINCIPLES.md, PROJECT_CONTEXT.md, CHECKLIST.md를 확인했다. 시작 전 git status --short로 기존 다수 수정/미추적 파일을 확인했다. reset/checkout/clean 및 커밋/업로드 없이 현재 작업 트리 위에 수정했다.

## 변경 파일과 이유
- lib/pages/home_page.dart: 삭제 확인창의 복구 보관함 버튼을 홈 AppBar로 이동. 진행 초안, 은혜 초안, 읽기 오류와 무관하게 열 수 있음. 기존 '첫 화면 위의 복구 보관함' 안내와 실제 위치 일치.
- lib/pages/question_page.dart: 최초 저장, 이전/다음, 이름 수정, 저장 후 나가기를 공통 저장 처리로 연결. 저장 성공 전 위치/이름은 유지. 실패한 동일 QuestionDraft와 나가기 의도를 메모리에 유지하고 한국어 안내 및 다시 저장 제공. 실패한 이름 입력도 표시·보존. 저장 중/미해결 실패/대화상자 중 조작 잠금. 나가기는 저장 성공 및 PopScope 갱신 후 실행. 저장 응답 예외 시 정확한 초안 재조회 일치로 성공 확인. 화면 해제 후 setState 방지. 이름 대화상자가 컨트롤러 수명을 직접 관리하도록 변경.
- test/question_draft_save_regression_test.dart: 신규 12개 widget 회귀 테스트. 최초 실패/동일 초안 재시도, 다음·이전 실패 위치 보존, 두 이름 보존, 나가기 실패·재시도, 지연 저장 중 중복·편집·뒤로 차단, 저장 후 응답 실패 재조회, dispose 후 응답, 빈 상태/문답 초안/은혜 초안/손상 상태의 보관함 진입.
- 이 보고서 추가. 기존 테스트 수정 없음. test/widget_test.dart 시작 시 내용과 동일 확인.

## 보존
교재 문항, 완료 집계·과정 선택 규칙, 기존 저장 데이터, 저장소 형식/DB 버전/스키마, 패키지, Wakelock enable/disable 유지. 개인 입력/예외 원문 로그 추가 없음. 과거 테스트 결과 파일 덮어쓰기 없음.

## 중간 오류와 해결
- 테스트 파일 생성 JavaScript 문자열에서 Dart 보간을 JavaScript가 해석하여 expected is not defined 발생. 해당 시도에서는 파일 생성 안 됨. 생성 코드 수정 후 파일 존재 확인. 신규 파일 생성 전의 43개 통과를 최종 근거로 사용하지 않음.
- 신규 이름 수정 테스트에서 A TextEditingController was used after being disposed 발견. Dialog pop의 Future는 전환 애니메이션 종료보다 먼저 반환될 수 있어 기존 조기 dispose가 문제였음. 별도 Stateful 대화상자의 dispose에서 해제하도록 수정.
- 신규 중복 조작 테스트에서 RawTooltip을 IconButton으로 캐스팅한 탐색 오류 수정. IconButton의 tooltip 속성으로 탐색.
- 정적 분석 스타일 지적 4개 수정 후 재검증.

## 최종 실행 근거
- dart format lib/pages/question_page.dart test/question_draft_save_regression_test.dart: PASS, 최종 0 changed.
- flutter analyze: PASS, exit 0, No issues found! (2.0s).
- 신규 파일 개별 flutter test: PASS, 12 tests, All tests passed!.
- 최종 flutter test: PASS, exit 0, 55 tests, All tests passed!. 기존 43 + 신규 12. 출력에 신규 파일 실행 확인.
- 일반 exec 프로세스 초기화 오류 발생 후 승인된 샌드박스 밖 실행 사용.

## 미검증 및 한계
실제 Android/iOS SQLite, 실기기 종료·재시작/OS 강제 종료, APK 빌드: NOT_RUN. 이번 회귀 테스트는 제어 저장소와 SharedPreferences mock 기반. 실제 Android SQLite 통합 테스트는 기존에 없으며 이번에도 추가하지 않았다. 저장 실패 상태의 대기 이름/동작은 현재 화면 메모리에 보존하며, 저장 성공 전 프로세스 강제 종료까지 영구 보존하는 것은 보장하지 않는다. 저장과 재조회가 모두 실패하면 상태를 확정하지 않고 안내와 잠금·재시도를 유지한다.
