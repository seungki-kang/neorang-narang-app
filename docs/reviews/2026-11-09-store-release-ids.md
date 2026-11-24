# 스토어 출시 준비: 앱 식별자와 시험 기능 숨김

기준 커밋: cff3012 (main).
범위: Android·iOS 앱 식별자, 홈 화면의 합성 자료 연동 시험 버튼, 이를 참조하는 기기 검사 스크립트와 문서 경로. 교재·DB 스키마·저장 로직·API 변경 없음.

## 변경
- 앱 식별자를 `com.jesuslab.neorangnarang`으로 변경했다. 사용자 결정: 개발사 Jesuslab(개인사업자), 도메인 없음. Google Play는 `com.example` 패키지를 받지 않는다.
  - Android: `namespace`, `applicationId`, `MainActivity.kt` 패키지와 경로(`kotlin/com/jesuslab/neorangnarang/`).
  - iOS: Runner `PRODUCT_BUNDLE_IDENTIFIER`(Debug·Release·Profile)와 RunnerTests.
  - macOS·Linux·Windows 식별자는 스토어 대상이 아니어서 변경하지 않았다.
- `tool/Test-NN-Safe.ps1`, `tool/Test-NN-Lifecycle.ps1`의 `$baseId`와 `tool/nn_lifecycle_probe.dart`의 테스트 경로 정규식을 새 식별자로 맞췄다. 스크립트가 `namespace`와 `applicationId`가 같은 값이라고 가정하므로 둘을 함께 바꿨다. 테스트 전용 ID(`.devicetest`, `.lifecycle.r<난수>`) 구조는 그대로다.
- 홈 앱바의 합성 자료 연동 시험 버튼에 `kDebugMode` 조건을 추가했다. release·profile 빌드에서는 보이지 않는다. `MobilePocPage`와 동기화 코드, 테스트는 변경하지 않았다.
- `PROJECT_CONTEXT.md`의 MainActivity 경로를 새 경로로 고쳤다.

## 데이터 영향
- 앱 식별자가 바뀌면 기기에서는 다른 앱이 된다. 이전 식별자로 설치한 개발·테스트 기기의 기록은 새 앱으로 넘어오지 않는다. 출시 전이라 일반 사용자 영향은 없다.
- 저장 형식·DB 버전·migration 변경 없음.
- `jesuslife/mobile_browser` 채널과 `jesuslife-poc` 반환 URI는 패키지명과 무관하여 그대로다.

## 검증
- 정적 확인: Android·iOS·tool·lib·docs/governance에 `com.example.neorang_narang_app`, `com.example.neorangNarangApp` 잔존 없음(macOS·Linux·Windows 제외). 과거 review 문서의 기존 ID 서술은 당시 기록으로 보존.
- 시험 버튼 조건은 컴파일 상수 `kDebugMode`라 host widget test(debug)에서는 release 숨김을 재현할 수 없어 회귀 테스트를 추가하지 않았다. 기존 테스트는 홈의 이 버튼을 참조하지 않는다.
- Flutter/Dart SDK 없음: flutter analyze, 전체 test, Android debug/release 빌드, iOS 빌드 NOT_RUN. PR의 CI(`Analysis and tests`, `Android debug build`)로 분석·테스트·debug 빌드를 확인한다.
- Device SQLite·Lifecycle 스크립트 실행 NOT_RUN(전용 에뮬레이터 필요). 새 `$baseId`로 패턴 치환이 맞는지 기기 실행으로 확인 필요.
- release 빌드에서 버튼이 보이지 않는지 실기기 확인 NOT_RUN.

## 남은 확인
- release 서명 설정(현재 debug 키 사용, build.gradle.kts TODO)은 이번 범위 밖이다. Play 업로드 전에 업로드 키를 만들어야 한다.
- INTERNET 권한은 PoC가 debug에서 쓰므로 main manifest에 남겼다.
