# Android release 서명 설정

기준 커밋: b954a91 (main, PR #9 병합 직후).
범위: `android/app/build.gradle.kts`의 release 서명, `android/key.properties.example`, 서명 안내 문서, 정적 테스트. 교재·DB 스키마·저장 로직·API·Dart 코드 변경 없음. 실제 업로드 키·비밀번호는 만들지도 커밋하지도 않았다.

## 변경
- release 빌드 타입의 `signingConfig = signingConfigs.getByName("debug")`를 제거했다. debug 키로 서명된 release는 Google Play에 올릴 수 없고, 실수로 debug 서명 AAB를 만들 위험이 있다.
- `android/key.properties`(git 제외)에서 `storeFile`, `storePassword`, `keyAlias`, `keyPassword`를 UTF-8로 읽는다. 네 값이 모두 있고 키 파일이 실제로 있을 때만 `release` signingConfig를 만든다. `storeFile` 상대 경로는 `android` 폴더 기준이다.
- 설정이 없을 때 release를 서명 없이 만들거나 debug 키로 대신하지 않도록, 작업 그래프에 이 프로젝트의 `assemble*Release`/`bundle*Release`/`package*Release`가 있으면 원인(파일 없음·빈 항목·키 파일 없음)과 안내 문서 경로를 담아 `GradleException`으로 멈춘다. debug·profile 빌드와 CI의 debug 빌드는 영향이 없다.
- `android/key.properties.example`: 실제 값 없는 템플릿. `.gitignore`의 `key.properties` 패턴은 정확한 파일명만 맞으므로 예시 파일은 추적된다.
- `docs/release/android-release-signing.md`: 업로드 키 생성(keytool, PowerShell), 보관·백업, key.properties 작성, release AAB 빌드와 서명 확인, Play App Signing 설명.
- `test/release_signing_test.dart`: release가 debug 키를 참조하지 않는지, key.properties·키 파일 패턴이 git 제외인지, 템플릿에 네 항목이 있는지 확인한다. 기존 테스트는 변경하지 않았다.
- `.gitignore`(루트·android)는 이미 `key.properties`, `*.jks`, `*.keystore`를 제외하고 있어 바꾸지 않았다.

## 데이터 영향
- 앱 식별자·저장 형식·DB 버전·migration 변경 없음. 기기 기록 영향 없음.
- 동작 변화: 지금까지 `flutter run --release`, `flutter build apk --release`는 debug 키로 서명되어 실행됐지만, 이제 `android/key.properties`가 있어야 한다.
- 기기 검사 스크립트(`Test-NN-Safe.ps1`, `Test-NN-Lifecycle.ps1`)는 debug APK만 빌드하므로 영향이 없다. 두 스크립트의 `namespace`·`applicationId` 행 검사도 그대로 통과하는 형태다.

## 검증
- 정적 확인: Kotlin DSL 변경 검토(import 위치, `signingConfig` nullable 대입, `whenReady` 수신 객체), 템플릿 항목과 `.gitignore` 패턴 확인.
- Flutter/Android SDK 없음: flutter analyze, 신규·전체 test, Gradle 구성, Android debug 빌드 NOT_RUN. PR의 CI(`Analysis and tests`, `Android debug build`)로 테스트와 debug 빌드의 Gradle 구성(새 스크립트 평가 포함)을 확인한다.
- release 경로 NOT_RUN: key.properties 없이 release 빌드가 안내 메시지로 멈추는지, 실제 업로드 키로 `flutter build appbundle --release`가 서명되는지(`keytool -printcert`)는 사용자 PC에서 확인이 필요하다.

## 남은 확인
- 사용자가 업로드 키를 만들고 백업한 뒤 release AAB 빌드와 서명 확인.
- Google Play Console 앱 생성과 Play App Signing 등록.
