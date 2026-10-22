# 너랑나랑 구조·성능 점검 및 1차 리팩터링
기준: NN_Refactor_Review_20261022_184718.zip / 2026-10-22

## 판단
기존 폴더 분리는 독립 라이브러리 분리가 아니다. main.dart에 part 지시문 41개가 연결돼 있다.
이번 패치는 의존성이 없는 모델·유틸리티 5개만 독립시켜 part 연결을 36개로 줄인다.
화면·저장소 전체를 한 번에 모듈화하지 않는다. 저장 순서·복구 보장과 공개 테스트 계약을 먼저 유지한다.

## 확인한 코드와 우선순위
|근거|현재 상태|조치|
|main.dart 및 모델/유틸리티|다섯 파일이 Flutter·저장소와 동일 라이브러리로 결합|import/export 방식으로 독립. main.dart import 호환 유지|
|home_page.dart|두 버튼에서 기록 화면 진입·복귀 후 재조회 코드 반복|openHistory 메서드 하나로 통합|
|services/completion_actions.dart pending|deleted IDs·복구 항목마다 findById/wasDeleted 및 레거시 읽기|데이터량에 따라 쿼리/역직렬화 증가 가능. 실제 호출 수 측정 후 일괄 조회 설계|
|completion_signature_page.dart|단일 ID 확인에도 loadAll로 전체 본문을 두 번 조회 가능|findById 계약을 활용하는 후속 변경 후보. 저장 후 검증과 테스트 대역 호환을 보존해야 함|
|completion_history_page.dart|전체 기록 메모리 적재 후 필터·정렬. SQLite도 이미 날짜 정렬|장기 기록량 증가 시 비용 가능. 페이지 조회는 목록·통계·복구 일관성 계약 추가 후 진행|
|deleted_records_page.dart|ListView children에 모든 삭제 기록 위젯과 원문 생성|삭제 기록이 많을 때 builder 전환 후보. 측정 없이 현재 메모리 누수로 단정하지 않음|
|grace_reflection_page.dart|300ms debounce·timer 취소·observer 해제 존재|기존 임시저장/수명주기 보존|
|question_page.dart|627줄, 문답·대화상자·진행저장 결합|후속 분리 후보. 줄 수 자체는 결함이 아니며 wakelock 동작 보존|
|SQLite/SharedPreferences 구현|공통 인터페이스 아래 플랫폼별 저장 전략|두 구현을 겉보기 중복이라 합치지 않음. 트랜잭션·JSON 보존 방식 다름|
|AppDatabase|장/날짜 인덱스 존재, 복구 테이블 포함|이번 DB 스키마·마이그레이션 변경 없음|
|lib 아래 backup 파일|예전 코드 백업 여러 개 존재|실행 Dart가 아니므로 삭제/성능 개선으로 계산하지 않음|

## 이번 변경
수정: main.dart, HomePage, 다섯 순수 모듈. 모델/함수 본문은 그대로 이동.
추가: 직접 import와 main.dart 재노출의 타입·함수 동일성 회귀 테스트 1개.
기존 테스트를 완화하거나 삭제하지 않음. 저장소·DB·교재 질문·서명·복구 코드 불변.
이번 변경으로 앱 시작 속도/메모리가 개선됐다고 주장하지 않는다.

## 검증 상태
로컬: Dart 구문 트리 검사와 part 파일 연결 확인, 순수 모듈 본문 보존 비교, 변경 범위 확인.
PowerShell: 구문 검사 및 설치·재설치·충돌 차단·패키지 손상 차단 모의 검증.
Flutter analyze / flutter test / Android build: 이 환경에 SDK가 없으므로 NOT_RUN.
설치 도구는 사용자 PC에서 안전 검사 Quick(분석·전체 PC 테스트)와 APK 빌드를 실행한다.
기존 180개 테스트/82.69%와 SQLite·lifecycle 통과는 변경 전 근거이며 이번 변경의 통과로 대체하지 않는다.
모바일 재검증은 기존 Test-NN-Safe Device와 Test-NN-Lifecycle을 사용한다. 일반 앱에서 integration_test를 직접 실행하지 않는다.

## 다음 단계와 측정 기준
수정 전 기준을 남기려면 설치 전에 아래 profile 절차를 먼저 수행한다.
이후 동일 기기·데이터량·동작·빌드 모드에서 재측정한다. 시작 첫 실행과 이후 실행을 구분.
DB 변경 없는 이번 소규모 모듈 분리에서 눈에 띄는 성능 향상을 기대하지 않는다.
다음 우선순위는 저장 조회 중복 측정 → 서비스 계약 분리 → 목록 비용 → 화면 분리.

### 실제 Android 기기에서 측정
1. 일반 앱의 기록을 별도로 백업한다. 이번 패키지는 기기에 설치하지 않고 PC 검사/APK 빌드만 한다.
2. 실제 휴대폰을 연결하고 flutter devices로 ID를 확인한다.
3. 기존 디버그 서명과 설치 호환을 확인한 개발 기기에서 flutter run --profile -d <휴대폰ID> 실행.
   이 명령은 기기에 설치한다. 배포본/키가 다른 기기에서는 실행하지 않고 별도 테스트 기기를 사용한다.
4. 출력된 DevTools에서 Performance와 Memory를 연다. 디버그/에뮬레이터 값으로 출시 성능을 단정하지 않는다.
5. 준비된 비개인 테스트 기록 0·100·1000개에서 시작, 기록목록 열기, 스크롤, 상세 열기/닫기,
   수정·삭제·복원을 같은 순서로 수행한다. 대량 fixture는 일반 앱 DB에 직접 주입하지 않는다.
6. 각 동작을 5회 측정하고 UI/raster frame 시간·끊긴 프레임·Dart heap/RSS를 기록한다.
   화면을 20회 왕복하고 GC 후 retained 객체/heap이 계속 증가하는지 확인한다.
   GC 전 최고치나 프로세스 RSS 한 번만으로 누수를 판단하지 않는다.
7. 재설치/데이터 삭제 없이 수정 전후 결과를 비교한다. 저장된 원문은 로그/화면 캡처에 포함하지 않는다.

|기기/OS/앱 커밋|모드/주사율|기록수|동작|반복수|중앙값 시간|프레임 지연|GC 후 heap/RSS|
|미측정|profile|미측정|시작/목록/저장/복원|5|NOT_RUN|NOT_RUN|NOT_RUN|

60Hz 프레임 예산은 약16.7ms, 120Hz 약8.3ms. 메모리 목표는 고정 임의값보다 동작 후 안정화 여부로 판단.
실기기 측정 결과가 없으므로 전체 성능 최적화 완료나 속도 향상률을 발표하지 않는다.
