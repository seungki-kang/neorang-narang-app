# 너랑나랑 강제 종료·업데이트 보존 검증 1.0
기준일 2026-10-22. 원본 lib/DB/교재/기존 테스트/기존 실행기 미수정. 설치는 tool에 진단용 Dart 엔트리와 실행기, docs/reviews에 이 문서를 추가한다. 기존 같은 파일은 Downloads/NN-Lifecycle-Backup-시간에 백업한다.

## 실행
NN_Test_Only를 켠다. 원본 neorang_narang_app 프로젝트에서 새 실행기를 사용한다. 일반 Medium_Phone을 대상으로 하지 않는다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\CHGO-VibeCodeing\neorang_narang_app\tool\Test-NN-Lifecycle.ps1"
```

검사 중 원본 코드 편집을 멈춘다. 처음에는 APK 두 개를 빌드하므로 수 분 걸릴 수 있다. 단계별 15초 진행 안내, 기본 단계 제한 600초. 제한을 늘릴 때 -StepTimeoutSeconds 1200. 로그/결과/APK A/B/해시는 원본 test-results/lifecycle-시간 아래 저장한다.

## 격리
매번 새 로컬 사본과 새 앱 ID com.example.neorang_narang_app.lifecycle.r<난수>를 쓴다. 일반 앱 ID와 다르고 이전 devicetest ID와도 다르다. NN_Test_Only 이름으로 기기를 자동 검색하고 일반 앱이 설치되어 있으면 중단한다. namespace와 applicationId 모두 분리하며 APK의 최종 앱 ID·버전 코드를 aapt로 검사한다. 모든 설치/강제 종료/실행은 검색된 테스트 전용 기기와 고유 ID에 한정된다. 검사 앱 자체도 SQLite 경로의 앱 ID가 lifecycle 테스트 형식이 아니면 initializeStorage 전에 거부한다.

ADB install -r로만 설치한다. 앱 삭제/pm clear/에뮬레이터 초기화 명령은 없다. 보고서가 달라도 일반 앱의 기존 데이터를 복원하는 도구로 표현하지 않는다. 이전에 없어진 데이터는 이 검증으로 되살아나지 않는다.

## 실제 검사 순서
1. 현재 원본을 사본에 복사/해시 비교. 별도 진단 엔트리와 실제 lib를 flutter analyze로 검사한다.
2. debug APK A (versionCode 100001) 설치. 실제 initializeStorage 및 실제 Android SQLite와 SharedPreferences를 사용한다. 사용자 이름 대신 NN_LIFECYCLE_SYNTHETIC 등 인공 데이터만 생성한다.
3. 은혜 임시기록·문답 위치·참여자 이름/최근 상대방·완료 2개·삭제 보관함 1개·영구 삭제 표시·저장 실패 대기/수정 대기를 저장하고 실제 값과 예상 fixture를 비교한다.
4. 저장 완료 증거를 받은 뒤 am force-stop. pidof로 프로세스 부재 확인. 새 프로세스에서 은혜 임시기록을 필드 단위/전체 스냅샷으로 비교하고, 서명 대기 상태와 양쪽 서명 시각을 저장한다.
5. 다시 force-stop 후 새 프로세스에서 서명 대기/정확한 시각/기록/설정을 비교한다.
6. APK B (versionCode 100002) 빌드, APK ID·버전 확인, 같은 패키지에 install -r. 최초 설치 시각과 UID 연속성 확인.
7. B에서 모든 저장 내용을 스냅샷/fixture로 비교한 다음 대기 기록 재시도·보관함 복원·중복 저장 방지·영구 삭제 기록의 재생성 거부·은혜 마무리/임시기록 정리를 수행한다. 최종 완료 5개, 1장 2개/2장 3개를 정확히 확인한다.
8. 다시 force-stop/새 프로세스에서 최종 상태의 지속성을 확인한다. 이름/최근 상대방/원래 서명 시각도 보존돼야 한다.

앱은 각 실행의 launchId/PID/build/phase/status를 합성 데이터만 담은 증거 파일에 기록한다. 호스트는 이전 launchId를 재사용한 결과를 통과로 인정하지 않는다. B에서 데이터가 없으면 다시 초기 데이터를 생성하지 않고 실패한다. 스냅샷은 키/목록 순서를 정규화해 비교한다. A/B는 같은 소스이고 버전 코드와 진단 빌드 구분만 다르다.

## 범위와 한계
이 검증의 통과는 **현재 코드/현재 DB 스키마에서 저장 완료 후 프로세스 강제 종료 및 debug APK 버전 증가 덮어 설치의 보존**을 뜻한다.

아래는 미검증(NOT_RUN)이다.
- 저장 트랜잭션 도중 종료, 갑작스러운 전원 차단, 기기 재부팅, 저장 공간 부족
- 실제 과거 배포 버전에서 현재 버전으로의 업그레이드, DB schema migration
- Play Store 배포/출시 키/서명 키 교체/Android 자동 백업 복원
- 실제 휴대폰/iOS, 일반 앱 전체 화면을 누르는 UI E2E

진단 앱은 실제 저장 초기화와 저장소/서비스를 사용하지만 일반 MyApp UI를 띄우지 않는다. UI를 통한 자동 임시저장 시점·버튼 이동은 기존 widget 테스트와 별도 수동 확인이 필요하다. 앱 자체의 저장 완료 후의 내구성 검증과 저장 중 장애 검증을 구분한다.

결과 파일 summary.json에는 각 단계 PASS/NOT_RUN과 전체 PASS_FOR_REQUESTED_SCOPE/FAIL을 분리한다. 단계 실패 시 이후 설치/재시도는 수행하지 않는다. 한 번 성공한 보고서를 다른 소스의 성공으로 사용하지 않는다. 실패하면 마지막 로그 또는 해당 proof.json을 보내 원인을 확인한다. 앱 데이터나 개인 기록을 자동 수집하지 않는다.

원본 사본은 %LOCALAPPDATA%/NN-Test-Workspaces/lifecycle-*에 보관한다. 진단 APK도 테스트 전용 에뮬레이터에 남긴다. 반복 실행마다 새 패키지를 쓰므로 디스크 공간을 사용한다. 진단 종료 후 테스트 전용 앱/사본만 확인해서 수동 정리한다. 일반 앱 삭제 명령은 제공하지 않는다.

## 제작 검증
PowerShell 7 실제 파서로 PS1 두 파일 구문 오류 0개 확인. Dart 문법 파서 오류 0개 확인(Flutter analyzer 실행을 대체하지 않음). Linux PowerShell 7 + 모의 Flutter/ADB/aapt에서 5회 프로세스 실행 흐름과 잘못된 기기/앱 ID/업데이트 검증 실패/설치 식별자 변경/프로세스 잔존/분석 오류 차단, 원본 ID 보존 등 11개 검사를 통과했다. Windows/Android/Flutter 실제 실행: NOT_RUN(사용자 PC에서 실행 필요). 제공된 2026-10-22 소스 계약을 기준으로 작성. 새로운 저장 모델/생성자/빌드 설정이 바뀌면 분석 단계에서 중단하도록 한다. 이 패키지에는 코드 자동 수정이나 앱 리팩터링이 없다.
