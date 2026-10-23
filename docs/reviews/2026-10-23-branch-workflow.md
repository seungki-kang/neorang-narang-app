# 너랑나랑 브랜치 운영 점검

기준 커밋: 9d2bbae (main), 2026-10-23.
승인 범위: 생명일기와 같은 간소화 브랜치·PR 운영 점검 및 보완.

## 코드 확인

- AGENTS.md 및 governance 3문서 확인.
- 기존 .github/workflows/nn-ci.yml에 push/PR/수동 실행 구성 존재.
- Windows, Flutter 3.47.4, 분석·일반 테스트·coverage·seed 22022 순서 변경 테스트 존재.
- Android debug build가 host-tests 성공 후 실행됨.
- 기존 CI와 실행 도구는 수정하지 않음.
- CONTRIBUTING.md와 PR 템플릿 추가, README 연결 보완.
- 앱 코드·교재 문구·SQLite·의존성 변경 없음.

## 검증

- git diff --check: PASS.
- README 문서 및 지침 내 기존 경로 확인: PASS.
- 패치 기준 커밋 적용 검사: 패키징 단계에서 별도 확인.
- Flutter 분석·테스트·APK: NOT_RUN (문서 변경 범위, 기존 CI 실행으로 확인 필요).
- GitHub CI 실행 결과: 이번 브랜치에서는 미확인.
- main 보호 규칙: UNKNOWN. 관리자 설정 또는 인증된 API로 별도 확인 필요.
- 실제 모바일 SQLite·강제 종료·재시작·서명: NOT_RUN.

저장소 파일 점검과 실제 보호 규칙 활성화는 구분한다. PR 병합과 로컬 main 동기화 후 반영 완료로 판단한다.
