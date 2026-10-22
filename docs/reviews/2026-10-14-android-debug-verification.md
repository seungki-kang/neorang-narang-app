# Android 디버그 빌드 검증 — 2026-10-14

## 이번 실행
- flutter build apk --debug: PASS, exit 0. Gradle assembleDebug 38.3s. Built build/app/outputs/flutter-apk/app-debug.apk.
- APK 실물 파일 존재 및 크기 확인: PASS.
- flutter devices: PASS, exit 0. Windows, Chrome, Edge만 표시. Android 기기 연결 없음.
- 기존 앱 설치/삭제, 앱 데이터 초기화, 커밋/업로드 수행 없음. 소스/테스트 수정 없음.

## 직전 테스트와 구분
expected is not defined 생성 오류 해결 및 test/question_draft_save_regression_test.dart 파일 존재 재확인. 직전 최종 flutter analyze PASS, 신규 12개 개별 PASS, 전체 55개 PASS (기존 43 + 신규 12). 이번 Android 빌드 단계에서는 해당 테스트를 재실행하지 않음.

## Android 수동 검증
Android 기기가 감지되지 않아 앱 실행 및 다음 항목은 NOT_RUN / 미검증:
1. 홈 상단 복구 보관함: 진행 초안 없는 상태 및 초안 있는 상태에서 열기.
2. 문답 몇 항목 진행 → 저장하고 나가기 → 홈 이어하기: 같은 장/참여자/문항 위치 확인.
3. 문답 화면 이름 변경 → 저장 완료 후 종료·재실행 → 이어하기: 수정한 이름과 위치 확인. 참여자 설정의 이름 기억과 문답 진행의 표시 이름은 별도 저장임.
4. 은혜 입력 → 임시저장 완료 표시 확인 → 종료·재실행 → 은혜 이어쓰기: 원문 확인.
5. 완료 전 건수 확인 → 완료 확인/저장 → 기록 상세 및 홈 확인 → 재실행: 내용/서명 시각 보존, 1건만 증가, 초안 카드 정리, 연속 탭 중복 없음 확인.

## 기존 데이터 유지 실행 방법
USB 디버깅 허용 후 flutter devices로 Android 연결 확인. adb install -r build/app/outputs/flutter-apk/app-debug.apk로 기존 패키지 업데이트 후 기기에서 앱 실행. 서명 또는 패키지 불일치 오류가 나면 중단하고 확인하며 uninstall/데이터 삭제로 우회하지 않음. 실제 SQLite 동작, 프로세스 재실행 복원은 APK 빌드 성공만으로 통과 판정하지 않음.
