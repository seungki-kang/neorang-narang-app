# 너랑나랑 PC 소스 기준 공통 인증 후보

기준: Windows 작업 트리 HEAD cff3012와 `Neorang-Auth-Source-20261123-071437.zip`의 6개 파일. 사용자 미커밋 변경은 승인된 현재 기준으로 보존한다. 공개 main 8e080ce 기준의 `Add_Neorang_Common_Login_Flutter.patch`는 이 PC에 적용하지 않는다.

## 변경

- 기존 `com.example.neorang_narang_app.MainActivity`의 기록 백업 암호화 채널과 기존 `ready/open/returnUri` 동작을 보존하고, debug에서만 허용되는 `openCommonAuth` 분기만 추가한다. 허용 목적지는 `http://127.0.0.1:8000/api/v1/mobile/neorang-narang/authorize`이며 state 단일 값·형식·사용자정보/fragment 부재도 검사한다.
- 별도 진입점 `lib/main_common_auth.dart`, `lib/common_auth/`의 메모리 세션/PKCE/transport를 추가한다. 기존 `main.dart`, home/mobile/SQLite/백업 페이지와 Gradle/pubspec/manifest는 패치에서 변경하지 않는다. 업로드·동의·큐·삭제 처리를 호출하지 않는다.
- 앱 반환 URI는 기존 `jesuslife-poc://auth/complete/android`를 사용한다. 콜드 시작은 메모리 transaction이 없어 거부한다. 기존 PoC와 새 entrypoint를 혼합해서 실행하지 않는다.
- 기본 `NEORANG_DEV_LOGIN`은 false이며 release에서는 kDebugMode가 false여서 비활성이다. 공개 `NEORANG_AUTH0_CLIENT_ID`만 앱에 전달한다. Client Secret은 서버 설정에만 둔다.

## 확인 근거

2026-11-23 사용자 보고: 백엔드 새 profile unit 9개 OK, disabled settings/CA 검사 PASS, binding 시험 ROLLBACK 성공, 실제 `NEORANG_COMMON_BINDING_READY`, enabled runtime probe PASS. 생명일기는 실제 Android 로그인→로그아웃→재로그인 성공 보고가 있다. 이는 너랑나랑 Android 인증 성공을 뜻하지 않는다. NN 로그인·로그아웃·재로그인 수동 검증은 아직 NOT_RUN이다. 앱 간 동일 canonical account_id와 다른 앱 세션 격리는 별도 실행 검증이 필요하다.

Dart format(5파일) PASS. 업로드 MainActivity에서 새 branch를 제거하면 바이트 단위로 원본과 같음을 검사했다. 첨부 6개 파일 기준 patch apply 및 비대상 파일 보존 검사 결과는 배포 전 검증 산출물에 기록한다. 현재 실행 환경의 Dart는 3.5.4이고 대상 pubspec은 ^3.13.3이므로 Flutter unit/analyze/Android 빌드는 NOT_RUN이다. SDK 제약을 낮추거나 lockfile을 바꾸지 않는다.

## Windows 다음 검증

현재 사용자 작업 트리에서 `git apply --check`가 통과할 때만 새 패치를 적용한다. reset/checkout/stash/pull 또는 기존 파일 덮어쓰기 zip 배포를 하지 않는다. Kotlin 파일은 적용 직전 별도 임시 백업을 보관한다.

```powershell
flutter test test/common_auth --no-pub
flutter test test/common_auth --no-pub --dart-define=NEORANG_DEV_LOGIN=true
flutter analyze lib/main_common_auth.dart lib/common_auth test/common_auth
flutter test test/mobile_sync_test.dart --no-pub --reporter expanded --timeout 60s
```

실패하면 중단하고 진단 라벨만 공유한다. 토큰/콜백 쿼리/설정 원문은 공유하지 않는다. 현재 patch는 앱 개발 후보이며 운영 배포가 아니다.

실제 설치 전 `adb -s emulator-5554 shell pm list packages com.example.neorang_narang_app`으로 기존 앱 설치 여부를 확인한다. 결과가 있으면 설치/삭제/clear를 진행하지 않는다. 빈 Medium Phone에서만 새 entrypoint를 시험한다. NN Restore/Test 기기와 기존 앱 데이터를 변경하지 않는다. 단순 --target 변경은 applicationId를 분리하지 않으므로 기존 앱에 무조건 덮어 설치하지 않는다.

NN/LD dev 서버는 8000 포트를 공유한다. 기존 LD 서버 창에서 Ctrl+C로 정상 종료한 뒤 NN `scripts.neorang_common_cloud serve`를 선택하고 adb reverse를 확인한다. 두 서버를 동시에 시작하지 않는다. 실제 실행은 user PC에서 추후 검증한다.

커밋·push·기존 작업 정리·추가 DB 변경·앱 설치·배포는 이번 패치 준비에서 수행하지 않았다.
