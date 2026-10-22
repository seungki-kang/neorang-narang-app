# 너랑나랑 테스트 점검 및 운영 패키지 1.0

기준: 사용자 업로드 NN_Test_Review_20261022_061007.zip. 2026-10-22.

## 범위와 검증 상태

앱 lib/, 교재, DB 스키마·마이그레이션, 앱 버전은 변경하지 않았다.
기존 테스트 13개 파일을 정적으로 점검했다. test/testWidgets 호출 위치는 107곳이며 반복문으로 추가 등록되므로 실행 테스트 개수와 같지 않다.
Flutter/Dart/PowerShell/실제 Android 실행은 이 제작 환경에 도구가 없어 NOT_RUN이다. 실행 성공을 주장하지 않는다. 설치기는 사용자 PC에서 분석과 전체 테스트를 실행한다.
ZIP 무결성, 파일 해시, 적용 대상, 소스 불변, Python으로 독립 확인한 시즌 경계 기대값: 정적 검사 PASS.

## 기존 테스트의 강점

- SQLite FFI와 SharedPreferences 양쪽 저장소를 실제로 호출한다. 이전 설명처럼 모든 테스트가 단순 mock인 것은 아니다.
- v1 → v2 파일 DB 이전과 기존 문답 보존 검사가 있다.
- INSERT/UPDATE/DELETE 및 복구 정리 단계에 SQLite 트리거로 오류를 주입하고 롤백을 확인한다.
- 기록 삭제·복원·영구 삭제·지연 재시도 차단 검사가 있다.
- 저장 중 중복 클릭·뒤로가기 차단, 저장 후 응답 유실, 화면 폐기 후 비동기 완료를 검사한다.
- 강제로 무한 대기하지 않고 프레임 대기를 제한한 테스트가 있다.

## 발견 및 수정

1. 기존 throwsA(anything) 7곳을 구체화했다. history_recovery_repository_test의 신원 변경은 StorageReadException으로, SQLite 트리거 실패 6곳은 DatabaseException으로 검사한다. 다른 TypeError 등으로 실패해도 테스트가 통과하는 문제를 줄인다. 원래 검증 대상과 데이터 보존 assertion은 유지했다.
2. 기존에 store recreation과 일부 file reopen 검사가 있지만 모든 흐름의 프로세스 재시작 검증은 아니었다. 신규 5개 파일 DB 검사는 close/reopen으로 실제 디스크 재조회와 실패 트랜잭션 후 재시도를 확인한다. OS 강제 종료까지 검사했다고 표현하지 않는다.
3. integration_test 폴더가 없었다. SDK integration_test dev dependency와 실제 기기용 SQLite 검사 9개를 추가했다. FFI 실행과 모바일 sqflite 플랫폼 경로 검증을 분리한다.
4. 기존 위젯 검사 일부는 화면에 들어가는 데서 끝난다. 신규 2개는 복구의 두 선택지에서 홈 복귀·활성 시작 버튼·완료 내용·건수·임시저장 정리를 확인한다.
5. 테스트 결과를 누적 저장하는 실행 도구가 없었다. 분석·coverage·순서 변경 재실행·선택적 기기/빌드 결과를 단계별 로그와 summary.json으로 남긴다.

## 추가 테스트 구성

- storage_contract_test.dart: 공통 8개 시나리오 × prefs/SQLite = 16개.
  동시 서로 다른 저장, 동일 ID 병렬 재시도, 충돌 후 큐 회복, 빈 은혜 수정 및 휴지통 왕복, 신규 미저장 삭제 후 재등장 방지, 오래된 편집 충돌, 영구 삭제 후 재등장 차단, 복합 회차 작업 후 정확한 전체 스냅샷.
- file_restart_test.dart: 5개. 편집 복구 재연결, 정리 실패 롤백 후 재연결, 중단된 편집을 포함한 휴지통 복원, 영구 삭제 표식 재연결, 문답 임시저장 재연결 및 완료 내역 분리.
- model_contract_test.dart: 경계 9개 + 불변성/손상 복구 형식 4개 = 13개.
- recovery_finish_widget_test.dart: 두 선택지 2개.
- 합계: 일반 신규 36개. 기기 별도 9개. 런타임 테스트 개수·PASS는 PC에서 확정한다.

## 데이터 보존 및 개인정보

새로운 일반 테스트는 합성 데이터와 새 임시 파일 DB만 사용한다. 기기 테스트는 getDatabasesPath 아래 별도 nn-operations/nn-reopen 디렉터리의 fixture.db만 사용한다. 앱의 main/initializeStorage를 호출하지 않아 사용자의 정상 DB를 열지 않는다. 테스트가 만든 디렉터리만 finally/tearDown에서 삭제한다.
실제 개인 은혜 기록을 로그나 fixture로 옮기지 않는다. 검사 보고서를 외부에 공유하기 전에는 로컬 경로 등이 포함됐는지 확인한다.
새 위젯 테스트는 prefs mock이다. SharedPreferences의 실제 Android 저장·OS 종료 복구는 아직 검사하지 않는다.

## 운영상 남은 실제 제약

- LegacyRecoveryRepository 및 CompletionActions.pending는 이미 반영된 구형 복구 스냅샷을 정리한다. '선택하지 않은 원본을 영구히 보존'하는 감사 기록은 현재 정책이 아니다. 신규 위젯 테스트도 이 현재 정책을 명시한다. 영구 보존을 원하면 별도 저장 모델과 보유·삭제 정책 설계가 필요하다.
- SharedPreferences → SQLite 앱 시작 이전 경로, 실제 Android SharedPreferences 내구성, 종료/강제 종료, 저용량·권한·기기 간 이전·release 서명·접근성·작은 화면은 이번 신규 패키지로 모두 검증되지 않는다.
- 기존 FFI 테스트의 v1→v2 검증을 유지했다. 신규 기기 테스트는 v2 신규 DB이므로 실제 모바일 업그레이드 시험을 대신하지 않는다.
- 커버리지는 실행 비율이다. 임의의 80%를 합격 기준으로 넣지 않았다. 핵심 실패 상황과 검사 결과를 우선한다.
- 테스트 한 번 통과했다고 운영 중 모든 데이터 상태와 기기를 보증하지 않는다.

## 실행 결과 판정

Standard: 분석 + 전체 일반 테스트/coverage + 다른 순서로 한 번 더 실행. 기기 검사 NOT_RUN.
Full: Standard + 지정 기기의 SQLite 9개 + debug APK. OS 강제 종료와 release 서명은 여전히 NOT_RUN.
한 단계 실패하면 다음 단계 중단. summary.json의 result와 각 단계 exitCode 확인. 테스트 생략으로 녹색을 만들지 않는다.

## 공식 근거

https://docs.flutter.dev/testing/overview
https://docs.flutter.dev/testing/integration-tests
https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpAndSettle.html
https://pub.dev/packages/sqflite_common_ffi
