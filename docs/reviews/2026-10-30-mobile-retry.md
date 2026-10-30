# 모바일 합성 자료 재시도 수정

- 기준: AGENTS.md, docs/governance/COMMON_PRINCIPLES.md, PROJECT_CONTEXT.md, CHECKLIST.md 및 neorang-narang-dev 스킬 확인.
- 브랜치: feature/mobile-broker-poc. 기존 미커밋 Android manifest/MainActivity, main.dart, home_page.dart, macOS 등록 파일과 미추적 debug/res, lib/mobile, mobile_sync_test.dart를 보존하며 작업했다. reset, clean, stage 재적용, commit/push 없음.
- 점검 근거: send가 queued만 조회하여 성공 이후 재시도 실패. 화면 _run의 포괄 오류 문구. resumeDeletion의 처리 여부 없는 반환을 화면이 삭제 완료로 해석.
- 수정 범위: mobile_sync.dart, mobile_page.dart, mobile_transport_io.dart, mobile_sync_test.dart와 이 보고서. HTTP 401/403과 연결/시간초과 오류를 구분하기 위해 기존 transport의 오류 분류만 추가. API/Auth0 변경 없음.
- 현재 계정과 동의 generation의 queued/sent만 조회하고 저장된 payload를 그대로 디코딩하여 재전송한다. 새 UUID/payload 생성 없음. cancelled 제외. 비동기 조회/전송 뒤 계정·generation·철회 상태 재확인.
- resumeDeletion은 실제 대기 삭제를 서버에서 확인했는지 bool로 반환한다. 처리할 삭제가 없으면 resume 및 수동 삭제 재개에서 기존 결과 문구를 보존한다.
- 선택 없음, 인증 실패, 통신 실패, 전송 불가, 서버 거절, 기타 실패의 안내를 분리했다. 예외 원문과 민감 자료를 출력하지 않는다.
- DB 스키마/버전 변경 없음. 실제 완료 저장소를 열거나 수정하지 않음. 기존 SQLite 초기화, 앱 삭제 없음. 상태 변경 외 UUID/payload 수정 없음.

## 회귀 테스트

기존 테스트의 기대값은 변경하지 않았다. 기존 Server fixture에 업로드 호출 내용을 기록하는 필드만 추가했다(합성 테스트 자료 전용).

- 최초 성공 후 재선택/재전송에서 같은 UUID 및 저장 payload 사용.
- sent 항목의 다른 계정 및 generation 격리, cancelled 차단, 원본 필드 보존.
- 선택 없음/인증/통신/기타 오류 문구 구분.
- widget의 실제 lifecycle resume에서 삭제 대기가 없으면 이전 전송 성공 문구 보존 및 삭제 완료 오표시 방지. 테스트용 session 주입 지점 추가.
- 기존 응답 유실, 재시작, 철회 경합, 로그아웃 및 원본 DB 보존 테스트 유지.

## 실행 결과

- Dart SDK 직접 실행으로 변경한 네 파일 format 적용: 4 files, 최종 1 changed. 이후 telemetry 로그 파일 삭제 권한 오류 발생. 전체 명령의 정상 완료로 간주하지 않음.
- `flutter analyze`: NOT_RUN. bat 실행은 SDK cache lock을 획득하지 못하고 출력 없이 대기하여 중단. 설치된 flutter_tools.snapshot 직접 실행도 cache/lockfile 접근 실패. lock 획득을 생략한 진단 실행은 cache/libimobiledevice.stamp 쓰기 권한 오류로 종료 코드 1. 분석 시작 전 실패.
- `flutter test test/mobile_sync_test.dart --reporter expanded`: NOT_RUN. 동일 SDK cache 쓰기 권한 오류, 종료 코드 1. 테스트 수집/실행 전 실패.
- 전체 테스트/Android 빌드/실기기 서버 연동: NOT_RUN.
- 현재 세션은 저장소 외부 SDK 경로 쓰기 및 권한 승격이 불가하다. SDK나 실기기 데이터를 변경하지 않았다. 쓰기 가능한 Flutter SDK 환경에서 analyze와 관련 테스트 재실행이 필요하다.
