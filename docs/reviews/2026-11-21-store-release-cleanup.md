# 스토어 출시 정리: 앱 이름, PoC 딥링크, INTERNET 권한

기준 커밋: 55bd12e (main, PR #7 병합 직후).
범위: Android·iOS 표시 이름, Android manifest의 PoC 반환 URI와 INTERNET 권한 위치, 이를 확인하는 정적 테스트, PROJECT_CONTEXT의 경로 서술. 교재·DB 스키마·저장 로직·API·동기화 코드 변경 없음.

## 변경
- 홈 화면에 표시되는 앱 이름을 `너랑나랑`으로 바꿨다. 앱바 제목과 같은 이름이다.
  - Android: main `AndroidManifest.xml`의 `android:label`(기존 `neorang_narang_app`).
  - iOS: `Info.plist`의 `CFBundleDisplayName`(기존 `Neorang Narang App`). `CFBundleName`은 그대로 둔다.
- `jesuslife-poc://auth/complete/android` 반환 URI의 intent-filter를 main manifest에서 debug manifest로 옮겼다. PR #7에서 PoC 진입 버튼을 `kDebugMode`로 숨겼으므로, release·profile 빌드에 외부에서 호출 가능한 PoC 반환 URI를 남길 이유가 없다. debug 빌드에서는 manifest 병합으로 같은 `MainActivity`에 그대로 붙는다.
  - debug manifest의 activity 이름은 main과 같은 `.MainActivity`다. `tool/Test-NN-Safe.ps1`, `tool/Test-NN-Lifecycle.ps1`은 `src` 아래 모든 manifest의 `.MainActivity`를 기준 패키지 절대 이름으로 바꾸므로 테스트 전용 ID 빌드에서도 같은 클래스로 병합된다.
- main manifest의 INTERNET 권한을 제거했다. debug manifest(Flutter 개발 도구와 PoC)와 profile manifest에 이미 있어 debug·profile 동작은 같다. release 코드에서 네트워크를 쓰는 곳은 없다: `lib/` 중 `lib/mobile/` 밖에는 HTTP 호출이 없고, 의존성(sqflite, path, shared_preferences, wakelock_plus, crypto, cupertino_icons)도 네트워크가 필요 없다.
- `PROJECT_CONTEXT.md`의 반환 URI 위치 서술을 debug manifest로 고쳤다.
- `test/release_manifest_test.dart`를 추가했다. main manifest에 PoC URI·INTERNET이 다시 들어오거나 표시 이름이 바뀌면 실패한다. 기존 테스트는 변경하지 않았다.

## 데이터 영향
- 앱 식별자·저장 형식·DB 버전·migration 변경 없음. 기기 기록 영향 없음.
- 표시 이름만 바뀌며 설치된 앱의 데이터 경로는 그대로다.

## 검증
- 정적 확인: 두 manifest XML 구문 확인, `Info.plist` 구문 확인(plistlib), `lib/`의 반환 URI 상수(`mobileReturnUri`)와 debug manifest의 scheme·host·path 일치 확인.
- Flutter/Dart SDK 없음: flutter analyze, 신규·전체 test, Android debug/release 빌드, iOS 빌드 NOT_RUN. PR의 CI(`Analysis and tests`, `Android debug build`)로 분석·테스트·debug 빌드(manifest 병합 포함)를 확인한다.
- release 빌드의 병합 manifest에 PoC URI·INTERNET이 없는지 aapt 확인 NOT_RUN.
- debug 빌드에서 PoC 로그인 브라우저 왕복 실기기 확인 NOT_RUN.
- Device SQLite·Lifecycle 스크립트 실행 NOT_RUN(전용 에뮬레이터 필요).

## 남은 확인
- release 서명 설정(현재 debug 키 사용)은 이번 범위 밖이다. 업로드 키 생성은 사용자가 직접 한다.
- 앱 아이콘은 초기 커밋 이후 바뀌지 않았다. 스토어 출시 전 교체 여부를 확인한다.
