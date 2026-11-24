# 개발용 세션 복구 — PC 검증 대기

기준: 20261123-194901 원본과 적용 완료한 홈 계정 패치. 기존 검증 문서는 변경하지 않는다.

추가 기능은 별도 PERSIST_LOGIN 플래그로 기본 비활성화다. 기존 DEV_LOGIN 조건과 Android debug 조건도 필요하다. 생명일기는 ONE_API_LOGIN 모드에만 연결한다. 클라이언트 주입 테스트에는 기본적으로 네이티브 저장소를 연결하지 않는다.

Keystore AES-256-GCM 키로 별도 세션 JSON을 암호화한다. 앱 전용 noBackupFilesDir의 AtomicFile에 저장하며 앱 패키지·Client ID·loopback 개발 프로필을 AAD와 파일명에 결합한다. 평문 토큰, verifier, Auth0 Client Secret은 파일이나 로그에 기록하지 않는다. PKCE와 대기 callback은 저장하지 않는다. Android 공식 KeyGenParameterSpec 예제를 참고했다: https://developer.android.com/reference/kotlin/android/security/keystore/KeyGenParameterSpec

재시작 시 서버 session 확인 후에만 인증 상태로 복원한다. 네트워크 실패 시 저장 자격은 유지하지만 로그인 성공은 표시하지 않는다. 만료·잘못된 형식·계정 불일치는 삭제한다. 통신 오류와 서버 거부를 구별하는 기존 클라이언트 계약이 없어 서버 거부 후에도 만료 전까지 저장 자격을 유지하고 복구 실패로 처리한다. 자동 토큰 갱신은 추가하지 않는다.

로그아웃은 네트워크 요청 전에 pending 표식을 저장한다. 재시작 시 pending은 세션 복원이 아닌 폐기 재시도를 수행한다. 서버 요청 성공 후 로컬 자격을 삭제한다. 저장 오류 시 일반 로그인 성공으로 가장하지 않는다. Keystore 손상·재설치·백업 복원에 대한 실제 기기 복구 검증은 별도이며 이 패치는 이를 완료로 주장하지 않는다.

SQLite·기록·초안·완료·공유 동의·백업 데이터는 읽거나 쓰지 않는다. 로그인은 업로드 동의가 아니다.

검증: 기존 소스 변경 범위 확인과 패치 적용·역적용 PASS. SDK가 없어 새 Dart 테스트, analyze, Kotlin 빌드, 강제종료/재시작/오프라인 기기 검증 NOT_RUN. 기존 홈 패치의 PASS는 이번 기능에 재사용하지 않는다.

## PC 검증 결과 — 2026-11-24

- 전체 flutter analyze: PASS, No issues found.
- 전체 회귀 테스트: 240 PASS, 23 SKIP, 실패 없음.
- 인증·세션 복구 활성화 테스트: 27 PASS.
- Android 수동 확인: 로그인 후 프로세스 종료·재실행 시 자동 복구 성공.
- 로그아웃 후 재실행 시 로그인되지 않은 상태 유지 확인.
- 포트 연결 차단 후 재실행 시 로그인 성공 표시 차단 확인.
- 연결 복원 후 로그인 상태 복구 버튼으로 새 인증 없이 복구 성공.
- 위 결과는 앞 절의 해당 NOT_RUN 항목을 갱신한다.
- 만료 전 개발 세션 복구 검증이며, 자동 갱신·운영 배포·보안 감사 완료를 의미하지 않는다.

## 스테이징 사본 검증 — 2026-11-24
- checkout-index로 별도 사본 생성, 기존 미스테이징 변경 제외.
- offline/enforce-lockfile 의존성 준비 PASS.
- 전체 analyze PASS, 인증 활성화 테스트 27 PASS.
- Android 기기 검증은 앞서 전체 작업 트리에서 수행한 결과이며, 이 사본의 기기 빌드 검증은 별도임.

## 최신 main 통합 검증 - 2026-11-24

- Android 패키지 com.jesuslab.neorangnarang 변경과 공통 인증 연결을 함께 보존.
- 기존 합성 시험 버튼의 debug 전용 제한과 공통 인증 활성화 시 숨김 조건을 함께 보존.
- 전체 analyze PASS.
- 전체 테스트 246 PASS, 23 SKIP.
- 인증 활성화 테스트 27 PASS.
- 지속 로그인 플래그를 켠 Android debug APK 빌드 PASS.
- 통합 APK의 설치 및 새 패키지에서의 실제 로그인 검증은 아직 NOT_RUN.
