# 너랑나랑 테스트 운영 개선 1.1 — 2026-10-22

## 목적과 범위
기존 테스트의 기대값을 완화하거나 테스트를 삭제하지 않고 실행 운영을 개선한다. lib, 교재 문구, DB 스키마, 저장 알고리즘은 수정하지 않는다. 테스트는 앱 실행 속도를 자동 최적화하는 도구가 아니라 오류와 회귀를 탐지하는 수단이다. 성능 개선은 별도 측정 근거가 있어야 한다.

## 실행
ZIP을 풀고 Install-NN-Safe.ps1을 실행한다. 설치는 tool/Test-NN-Safe.ps1과 이 문서를 추가하며, 기존 실행기의 Full 모드가 차단되지 않은 경우 백업 후 차단한다. 기존 테스트와 기대값은 보존한다. 기존 실행기가 이미 차단되었다면 재변경하지 않는다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\CHGO-VibeCodeing\neorang_narang_app\tool\Test-NN-Safe.ps1" -Mode Quick
```

- Quick: 분석 + 전체 PC 테스트 1회. 반복 개발의 기본.
- Standard: 분석 + 전체 PC 테스트/커버리지 + 고정 시드 순서 변경 검사. 저장 로직 변경 또는 배포 준비 때.
- Device: PC 테스트를 반복하지 않고 Android SQLite 9개를 별도 사본에서 실행. NN_Test_Only가 실행 중이어야 함.
- 모드 변경은 위 명령 끝의 Quick을 Standard 또는 Device로 바꾸면 된다. Windows PowerShell 5.1 이상 전용.
- Quick/Standard는 pub get을 자동 실행하지 않는다. 의존성을 변경한 경우 일반 프로젝트에서 flutter pub get을 먼저 실행한다.
- 실행 중에는 소스 편집을 멈춘다. 실행 전후 해시가 다르면 전체 판정은 FAIL이다.

## 기기 검사 보호
매 실행마다 새로운 로컬 작업 폴더에 lib/test/integration_test/assets/android/pubspec/분석 설정을 복사한다. 생성 폴더는 재사용하지 않으므로 삭제된 파일이 남지 않는다. 원본과 복사본의 SHA-256을 비교한다. namespace와 applicationId를 모두 테스트 ID로 바꾸고 MainActivity는 원래 전체 클래스 경로를 사용한다. APK를 먼저 빌드하여 aapt로 실제 앱 ID를 확인한다. 설치 직전에 에뮬레이터 이름과 일반 앱 미설치 상태를 재확인한다. --no-uninstall을 사용한다. 에뮬레이터 번호는 고정하지 않고 NN_Test_Only 이름으로 찾는다. 일반 앱용 Medium_Phone은 설치 대상으로 사용하지 않는다.

원본 Android 설정의 namespace/applicationId가 바뀌거나 product flavor를 도입하면 자동 적용을 중단하거나 APK ID 검사가 실패할 수 있다. 그때는 실행기를 새 구조에 맞춰 검토해야 한다. 임의 우회하지 않는다. 원본의 .git/build/.dart_tool/.gradle/coverage/test-results/.idea는 복사하지 않으며 reparse point는 거부한다. 테스트 데이터는 기존 통합 테스트의 임시 DB만 사용한다.

이전 neorang_narang_device_test 폴더는 이번 실행기가 사용하지 않는다. 원본 프로젝트만 편집한다. 새로운 사본은 %LOCALAPPDATA%/NN-Test-Workspaces 아래 보관하며 반복 생성으로 디스크를 사용한다. 실행 중이 아닐 때 진단이 끝난 사본 폴더만 수동 정리할 수 있다. 자동 삭제 기능은 없다.

## 결과와 실행 제한
원본 test-results/optimized-시간 아래 단계별 로그, 소스 해시, summary.json을 남긴다. Standard는 lcov와 coverage-summary.json도 남긴다. 15초 간격 상태를 표시하고 단계별 기본 600초를 초과하면 이번 실행기가 만든 자식 프로세스 트리만 종료한다. 실제 테스트는 개별 60초 제한. 컴파일이 느린 환경은 -StepTimeoutSeconds 1200 사용. 코드가 멈추는 오류를 무한 대기로 숨기지 않는다. 제한 시간 초과의 종료 결과는 124/FAIL이다. 앱 데이터 초기화, ADB 서버 재시작, 전체 Java/Dart 프로세스 종료는 하지 않는다.

기기 검사 실패 시에도 작업 사본을 남겨 원인 분석이 가능하다. 개인정보를 실행기 자체 로그에 수집하지 않는다. Flutter/기존 테스트 출력에 민감 정보가 포함되지 않는지는 별도 관리가 필요하다. 결과 공유 시 개인 내용을 확인한다. 백업/데이터 복원 기능을 제공하는 도구로 표현하지 않는다.

## 검증 상태와 한계
이전 사용자 실행 증거: PC 180개 및 순서 변경 검사 통과, 분리 Android SQLite 9개 통과/exit 0. 이 새 실행기에서 재검증한 결과는 아니다.
새 패키지: PowerShell 7의 실제 파서로 PS1 두 파일 구문 오류 0개를 확인했다. Linux PowerShell 7에서 Flutter/ADB/aapt를 모의 실행하여 설치·재설치 시 차단 유지·Quick/Standard/Device 성공 경로·일반 에뮬레이터 차단·일반 앱 설치 기기 차단·잘못된 APK ID 차단·실패 전파·원본 앱 ID 보존 등 10개 계약 검사를 통과했다. 모의 검사는 실제 Flutter 또는 Android 테스트가 아니다. Windows PowerShell 5.1, 실제 Flutter를 사용한 새 실행기의 검증은 NOT_RUN이다. 테스트 사본의 namespace 변경 방식과 --no-uninstall 조합은 앞서 사용자 실행에서 통과했다.
OS 강제 종료 복원, 앱 업데이트 데이터 보존, 실제 휴대폰/iOS, 출시 서명, 성능 벤치마크는 NOT_RUN이다. Quick PASS가 Device PASS를 뜻하지 않으며, 100% 커버리지를 강제로 목표로 삼지 않는다. 기존 SQLite 테스트 9개는 저장소 수준이며 전체 UI 테스트를 대체하지 않는다.

## 운영 권장
일반 변경은 Quick, 저장/복구 변경은 Standard와 Device를 실행한다. 실패한 테스트를 제거하거나 기대값을 약화하지 않는다. 회귀 테스트는 실제 결함의 원인과 해결 계약을 검증한다. 변경 후 전체 lib 리팩터링은 이번 범위에 포함하지 않는다.
