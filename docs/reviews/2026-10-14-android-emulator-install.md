# Android 가상기기 설치 — 2026-10-14

- flutter devices: PASS. sdk gphone64 x86 64, emulator-5554, Android 15 API 35.
- 최초 adb 명령: PATH 미등록으로 실행 안 됨. 설치 시도 전 단계의 CommandNotFoundException.
- Android SDK platform-tools/adb.exe -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk: PASS, exit 0, Performing Streamed Install / Success.
- 방금 빌드한 APK 사용. uninstall, 데이터 초기화, 커밋, 업로드 없음.
- 앱 실행, 실제 기존 기록 보존, 홈 보관함 등 수동 검증: NOT_RUN. 설치 성공만으로 데이터 보존을 실측했다고 주장하지 않음.
- 다음 수동 확인: 가상기기 앱 목록에서 너랑나랑 실행 → 홈 상단 상자 아이콘(복구 보관함) → 보관함 화면 또는 빈 기록 안내 확인 → 뒤로 홈 복귀. 기존 기록/초안이 있으면 유지 여부 확인.
