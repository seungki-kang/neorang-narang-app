# Android release 서명 안내

Google Play에 올릴 AAB는 **업로드 키**로 서명합니다. 업로드 키와 비밀번호는 개발자 PC에서 직접 만들고 보관하며, 저장소·메신저·이메일에 올리지 않습니다.

빌드 설정(`android/app/build.gradle.kts`)은 `android/key.properties`를 읽어 release 빌드를 서명합니다. 이 파일이 없거나 값이 비어 있거나 키 파일 경로가 틀리면 release APK/AAB 빌드를 멈추고 이유를 알려 줍니다. debug 키로 대신 서명하지 않습니다. debug 빌드와 CI(`Android debug build`)는 이 설정과 관계없이 그대로 동작합니다.

## 1. 업로드 키 만들기 (처음 한 번)

PowerShell에서 실행합니다. `keytool`은 JDK에 들어 있습니다. 명령을 찾지 못하면 `flutter doctor -v`의 Java 경로나 Android Studio 설치 폴더의 `jbr\bin\keytool.exe`를 사용합니다.

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\keys" | Out-Null
keytool -genkey -v -keystore "$env:USERPROFILE\keys\neorangnarang-upload.jks" `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- 키스토어 비밀번호와 키 비밀번호를 묻습니다. 같은 값을 써도 됩니다.
- 이름·조직 질문에는 개발사 정보(Jesuslab)를 입력합니다. 앱에 표시되지는 않습니다.
- 키 파일은 **저장소 폴더 밖**(위 예시처럼 사용자 폴더의 `keys`)에 둡니다.

## 2. 키 보관

- 키 파일(`neorangnarang-upload.jks`)은 PC 밖 두 곳 이상에 백업합니다. 예: 암호화한 USB, 비밀번호 관리자 첨부.
- 두 비밀번호는 비밀번호 관리자에 저장합니다.
- Google Play 앱 서명(Play App Signing)을 쓰면 실제 앱 서명 키는 Google이 보관합니다. 업로드 키를 잃어버려도 Play Console에서 업로드 키 재설정을 요청할 수 있지만, 처리에 시간이 걸리므로 백업이 우선입니다.

## 3. `android/key.properties` 만들기

`android/key.properties.example`을 같은 폴더에 `key.properties`로 복사하고 값을 바꿉니다.

```properties
storeFile=C:/Users/사용자이름/keys/neorangnarang-upload.jks
storePassword=키스토어_비밀번호
keyAlias=upload
keyPassword=키_비밀번호
```

- 경로는 역슬래시(`\`) 대신 슬래시(`/`)로 적습니다. 상대 경로는 `android` 폴더 기준입니다.
- 비밀번호에 `\`가 있으면 `\\`로 적습니다. properties 형식에서 `\`는 특수 문자입니다.
- 파일은 UTF-8로 저장합니다. 경로에 한글 폴더가 있어도 됩니다.
- `key.properties`, `*.jks`, `*.keystore`는 `.gitignore`에 있어 Git에 올라가지 않습니다. 커밋 전에 `git status`에 보이지 않는지 확인합니다.

## 4. release 빌드

```powershell
flutter build appbundle --release
```

결과물은 `build\app\outputs\bundle\release\app-release.aab`입니다. 서명을 확인하려면:

```powershell
keytool -printcert -jarfile build\app\outputs\bundle\release\app-release.aab
```

출력의 소유자(Owner)가 1단계에서 입력한 정보이고 `Android Debug`가 아니어야 합니다.

## 5. 알아 둘 점

- `flutter run --release`, `flutter build apk --release`도 release 빌드라 `key.properties`가 필요합니다.
- 버전은 `pubspec.yaml`의 `version`(예: `1.0.0+1`)에서 정합니다. Play에 새로 올릴 때마다 `+` 뒤 숫자(versionCode)를 올립니다.
- 현재 CI는 debug 빌드만 합니다. 나중에 CI에서 release AAB를 만들려면 키를 GitHub Secrets에 넣는 별도 설계가 필요합니다. 그때도 키 파일을 저장소에 넣지 않습니다.
