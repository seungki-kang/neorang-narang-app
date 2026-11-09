# 너랑나랑 프로젝트 기준 1.0

기준 소스: 사용자 업로드 NN_Current_Source_20261009.zip (2026-10-09)
목적: 교재 문답·함께 또는 혼자 진행·이어하기·완료 확인·은혜 돌아보기를 지원한다.
Android/iOS는 SQLite, 웹과 그 외 플랫폼은 SharedPreferences를 사용한다.
현재 로그인·서버 API·AI·결제는 이 적용 범위에 없다.
시즌·별·횟수는 학습 진행 표시이며 성숙 평가가 아니다.
완료 서명은 기기에서 누른 확인이며 인증된 전자서명이나 공유 동의가 아니다.
2026-10-09 기준으로 은혜 원문 보호·삭제·내보내기는 후속 구현 항목이었다. 현재는 삭제·휴지통 복원·영구 삭제 표식·저장 실패 복구 구현과 관련 테스트가 존재한다. 이를 암호화·키 관리·백업/삭제 정책 또는 내보내기 완료, Vault 구현으로 표현하지 않는다.
현재는 main.dart의 part인 페이지·저장소 등과 독립 import/export 모듈인 일부 모델·유틸·mobile PoC가 공존하는 혼합 구조다. 폴더 분리와 독립 모듈화를 구별하며, 기존 main export와 직접 모듈 참조의 호환성은 test/module_boundary_test.dart에서 검사한다.

## 적용 순서
1. 완료 저장 실패 복구와 재시도 ID 유지
2. 손상 JSON 보호와 시작·읽기 오류 상태
3. 임시저장·종료·완료 정리 및 이전 검증
4. 개인 원문 보호·삭제·내보내기
5. DB/콘텐츠 버전과 CI
6. 동의한 최소 학습 근거의 CHGO 연동

기존 교재 콘텐츠는 이번 변경에서 수정하지 않는다. DB 버전도 변경하지 않는다.

문답 화면의 WakelockPlus.enable/disable 및 wakelock_plus 의존성을 보존한다.

작업별 검증 선택과 의존성·기기 조건은 [CONTRIBUTING의 검증 경로](../../CONTRIBUTING.md#검증-경로)를 따른다.

## 후속 코드 확인: 로그인·동기화 PoC (2026-11-01)

위 본문은 2026-10-09 로컬 기능 기준을 보존한 것이다. 본문의 로그인·서버 API 비적용 서술은 그 기준 범위에 한정하며, 이후 추가된 아래 PoC 코드의 부재를 뜻하지 않는다. AI·결제의 적용을 확대하는 근거로도 사용하지 않는다.

- 진입점: `lib/main.dart`의 mobile_page import, `lib/pages/home_page.dart`의 `MobilePocPage` 이동, `lib/mobile/mobile_page.dart`의 화면과 `MobileSync`/`mobileRequest` 연결.
- 로그인: `lib/mobile/mobile_sync.dart`의 `beginLogin`/`finishLogin`, Android `android/app/src/main/kotlin/com/jesuslab/neorangnarang/MainActivity.kt`의 `jesuslife/mobile_browser` 채널과 브라우저 왕복, `android/app/src/main/AndroidManifest.xml`의 `jesuslife-poc` 반환 URI가 존재한다. 코드 존재는 실제 인증 성공이나 승인된 운영 인증 계약의 증거가 아니다.
- 동의·송신·철회: `mobile_sync.dart`의 `refreshStatus`/`grant`/`selectSynthetic`/`send`/`revoke`/`resumeDeletion`/`logout`. 별도 `neorang_mobile_poc.db`의 큐·삭제 의도를 사용하며, `selectSynthetic`은 기존 완료 기록을 읽지 않고 `synthetic: true`인 합성 완료를 만든다. 개인 문답·은혜 원문 동기화 완료로 표현하지 않는다.
- 통신 한계: `mobileOrigin`은 `http://127.0.0.1:8000`, API 접두사는 `/api/v1/mobile`이다. `lib/mobile/mobile_transport.dart`는 IO 구현을 조건부 선택하고, `mobile_transport_io.dart`는 HttpClient로 요청한다. 비 IO stub은 `UnsupportedError('android_only')`를 발생시킨다. 모든 플랫폼 지원이나 운영 서버 연결을 의미하지 않는다.
- 실행 근거: `test/mobile_sync_test.dart`에 관련 테스트가 있다. 기존 `docs/reviews/2026-10-30-mobile-session-review-fixes.md`, `docs/reviews/2026-10-30-mobile-sync-widget-async.md`는 SDK 시작/권한 문제와 테스트·분석 NOT_RUN을 기록한다. 이는 과거 보고이며 이번 실행 결과가 아니다. 이번 문서 작업에서도 로그인·서버·동기화 런타임은 NOT_RUN이다.
- 후속 실행 기록(2026-11-01): 감사 보고서 `NN_MOBILE_SYNC_EXECUTION_REVIEW.md`에서 위 테스트의 단독 --no-pub 실행 22개 PASS/종료 0을 확인했다. 합성 요청·임시 SQLite FFI 검증이며 enforce-lockfile을 포함한 CI 재현, 실제 서버 로그인·동기화·모바일 프로세스 재시작의 성공으로 확대하지 않는다. 앞선 NOT_RUN은 당시 기록으로 유지한다.
- 승인·운영 연결: 이번에 확인한 코드·검토 문서만으로 승인된 인증/동기화 계약, 실제 서버 가동, 운영 계정 연결 또는 서비스 활성화를 확인하지 못했다. 미확인을 승인·운영 연결의 부재로 단정하지 않는다. PoC의 존재만으로 운영 완료나 개인정보 공유 동의 완료로 판정하지 않는다.

CHECKLIST의 서버 관련 비적용 문구는 이 절을 근거로 기능·계층별 적용성을 재검토한다. 로컬 기능 기준과 PoC 검토 결과를 별도로 기록한다.
