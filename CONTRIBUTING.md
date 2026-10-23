# 너랑나랑 개발 운영 지침

## 기준

`main → 작업 브랜치 → PR → CI 통과 → 병합` 방식을 사용합니다. develop/release/hotfix를 상시 두는 전통적인 Git Flow 대신 현재 개발 규모에 맞춘 간소화 방식입니다. AGENTS.md와 docs/governance/의 COMMON_PRINCIPLES.md, PROJECT_CONTEXT.md, CHECKLIST.md를 먼저 읽습니다.

## 브랜치 이름

| 목적 | 예시 |
| --- | --- |
| 기능 | `feature/archive-search` |
| 오류 수정 | `fix/grace-autosave` |
| 동작 보존 리팩토링 | `refactor/completion-flow` |
| 문서 | `docs/nn-branch-workflow` |
| CI·도구 | `chore/ci-maintenance` |

한 PR은 한 목적을 갖습니다. main 직접 push와 강제 push는 사용하지 않습니다. 기존 작업 브랜치의 후속 수정은 새 커밋으로 추가합니다.

## 작업 시작

```powershell
Set-Location 'D:\CHGO-VibeCodeing\neorang_narang_app'
git status --short --branch
```

기존 추적 파일의 수정이 있으면 먼저 그 작업을 정리합니다. 개인 기록·오류 로그·미추적 문서를 임의로 삭제하거나 커밋하지 않습니다.

```powershell
git switch main
git pull --ff-only origin main
git switch -c feature/archive-search
```

브랜치 이름은 실제 작업에 맞춥니다. 각 명령이 실패하면 다음 단계를 실행하지 말고 원인을 확인합니다.

## 개발과 검증

승인된 교재 문구·신학 표현·학습 표시와 wakelock 동작을 보존합니다. 생명일기 7문항이나 CHGO 서버 기능을 이 앱에 필수로 추가하지 않습니다. 저장 변경은 기존 기록·임시저장·migration 호환성을 검토합니다. 민감한 이름·원문·토큰은 로그나 PR에 넣지 않습니다.

기존 도구를 사용해 CI와 같은 검사를 수행합니다.

```powershell
./tool/Invoke-NN-CI.ps1 -Mode Tests
./tool/Invoke-NN-CI.ps1 -Mode Apk
```

Tests는 lockfile 준수 의존성 설치, 분석, 전체 테스트·coverage 및 seed 22022 순서 변경 테스트를 실행합니다. Apk는 설치 없이 Android debug APK를 빌드합니다. 실행하지 못한 검사는 NOT_RUN으로 적고, 변경과 검증을 docs/reviews/에 남깁니다. 문서만 수정했다면 변경 내용·링크를 확인하고 기능 테스트 재실행 여부를 명시합니다.

실제 모바일 SQLite·OS 강제 종료·재시작·release 서명·실기기 동작은 위 CI만으로 검증됐다고 표현하지 않습니다.

## 커밋과 PR

변경된 파일을 검토하고 실제 작업 파일만 git add에 지정합니다. git add .로 오류 로그와 개인 기록을 함께 올리지 않습니다.

```powershell
git diff
git diff --cached --check
git diff --cached
```

스테이징 내용을 확인한 뒤 커밋하고 작업 브랜치를 push합니다. PR의 base는 main으로 지정하고 템플릿에 목적·동작·검증·데이터 영향을 기록합니다.

필수로 확인할 기존 CI job:

- `Analysis and tests` (GitHub Actions)
- `Android debug build` (GitHub Actions, 분석·테스트 성공 후 실행)

실패·대기 상태에서는 병합하지 않습니다. 최신 main 반영이 필요하면 기존 작업 브랜치에서 아래 명령을 사용하고 충돌 해결 후 관련 검사를 다시 실행합니다.

```powershell
git fetch origin
git merge origin/main
git push
```

## main 보호 규칙 설정

저장소 관리자가 GitHub Settings → Rules → Rulesets에서 설정합니다. 이 문서나 패치만으로 보호 규칙이 활성화되지는 않습니다. 기존 규칙이 있다면 새 규칙을 중복 생성하지 말고 확인·보완합니다.

| 항목 | 설정 |
| --- | --- |
| 이름 예시 | `main-ci-protection` |
| Enforcement | Active |
| 대상 | main만 |
| Bypass | 비움 |
| Require a pull request | 체크 |
| Required approvals | 혼자 개발 시 0 |
| Require status checks | 위 두 job을 실제 검색 결과에서 선택, 소스 GitHub Actions |
| Require branches up to date | 체크 |
| Restrict deletions / Block force pushes | 체크 |
| Restrict updates | 해제 |

필수 검사 이름은 최근 실행 결과에서 선택합니다. 임의 문자열로 새 검사를 만들지 않습니다. Android job은 host-tests에 의존하므로 두 검사 모두 완료를 확인합니다.

## 병합 이후

```powershell
git switch main
git pull --ff-only origin main
git status --short --branch
```

병합한 원격 브랜치는 필요하면 삭제합니다. 로컬 브랜치는 merge 병합이면 git branch -d 브랜치이름으로 정리할 수 있습니다. Squash/Rebase 병합으로 삭제가 거절되면 강제 삭제 대신 이력을 확인합니다.

## 배포

실제 출시를 결정할 때 pubspec 버전·변경 이력·데이터 이전·기기 검증을 맞추고 검증된 배포 커밋에 vX.Y.Z 태그를 붙입니다. 이번 지침 추가는 새 버전 배포가 아닙니다. 배포 버전 수정과 다음 버전 개발을 동시에 유지하게 되면 release/hotfix 운영 도입을 별도로 결정합니다.
