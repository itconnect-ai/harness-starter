# Harness Engineering Starter Kit

이 키트는 **Codex Desktop(구현) + Claude Code(리뷰)** 조합으로
100% AI 개발을 수행하기 위한 harness engineering 스타터 템플릿입니다.

---

## 셋업 순서

### 1단계: 이 레파지토리를 프로젝트에 복사

프로젝트 시작 전 이 레파지토리 전체를 복사하여 붙여넣습니다.
BMAD와 하네스 파일이 모두 포함되어 있습니다.

> 하네스 초기화(git hooks, GitHub Secret Scanning, Branch Protection)는
> **4단계 프로젝트 초기화 프롬프트에서 Claude Code가 자동 실행**합니다.
> 수동 설정은 필요 없습니다.
>
> 수동 실행이 필요한 경우만: `./scripts/setup/init-harness.sh` (또는 `.ps1`)

### 2단계: BMAD 설치

```bash
npx bmad-method install
```

### 3단계: BMAD 기획/설계 (Claude Code)

완료 후 아래 산출물이 존재해야 합니다:
- `_bmad-output/planning-artifacts/PRD.md`
- `_bmad-output/planning-artifacts/architecture.md`
- `_bmad-output/planning-artifacts/epics/` (epic 파일들)

### 4단계: 프로젝트 초기화 + 하네스 커스터마이징 (Claude Code)

**새 Claude Code 세션**에서 아래 프롬프트를 실행합니다.
프로젝트 scaffolding부터 하네스 설정까지 한 번에 처리됩니다.

```
이 프로젝트의 BMAD 산출물을 참고하여 아래 작업을 순서대로 실행해줘.

참고 파일:
- _bmad-output/planning-artifacts/PRD.md
- _bmad-output/planning-artifacts/architecture.md

## 0단계: 하네스 자동 초기화 (최초 1회만)
아래 스크립트를 먼저 실행해 git hooks, GitHub Secret Scanning, Branch
Protection을 자동 설정해줘. 여러 번 실행해도 안전(멱등성 보장).
- bash/WSL/macOS/Linux: `./scripts/setup/init-harness.sh`
- Windows PowerShell: `./scripts/setup/init-harness.ps1`

이 스크립트가 내부적으로 순차 실행하는 것:
  1) ./scripts/setup/install-git-hooks.sh
     (pre-commit, commit-msg 활성화 — core.hooksPath 방식)
  2) ./scripts/setup/setup-repo.sh
     (gh CLI 있고 origin 설정된 경우에만 자동 실행.
      없으면 skip + 추후 수동 실행 안내 출력)

이후 자동으로 적용되는 것:
- git commit 시 lint + Conventional Commits 형식 검증
- git push 시 GitHub Secret Scanning이 하드코딩 키 차단
- main/develop 대상 PR은 CI + Gitleaks + CodeQL 통과해야만 merge 가능

## 1단계: 프로젝트 초기화
architecture.md의 기술 스택에 맞게 프로젝트를 초기화해줘.
- 프로젝트 scaffolding (적절한 create 명령 또는 수동 초기화)
- package.json (또는 해당 언어의 프로젝트 파일)
- (해당시) TypeScript 설정 (tsconfig.json)
- 린팅 설정 (ESLint 등)
- 포맷팅 설정 (Prettier 등)
- 테스트 프레임워크 설정 (Vitest, Jest, Playwright 등)
- .gitignore 보완 (기술 스택에 맞게)

## 2단계: 하네스 파일 커스터마이징
- scripts/validate.sh → 실제 빌드/타입체크/린트/테스트 명령으로 교체
- scripts/validate-quick.sh → 기술 스택에 맞게 테스트 러너 확인 (vitest/jest --changed 지원 여부)
- scripts/smoke.sh → PRD의 핵심 사용자 플로우 기반 스모크 테스트 대상 정의
- docs/agents/architecture-rules.md → architecture.md의 레이어 구조, 모듈 경계 반영
- docs/agents/coding-rules.md → 실제 기술 스택에 맞는 규칙, 로거 경로 지정
- docs/agents/testing-rules.md → 실제 테스트 프레임워크, 커버리지 기준
- docs/agents/security-rules.md → CORS 허용 도메인, 인증 방식에 맞게 조정
- docs/agents/performance-rules.md → 사용하는 ORM/프레임워크에 맞게 조정
- docs/agents/deploy-rules.md → 배포 환경(Docker, Vercel, Fly.io 등)에 맞게 조정, 포트 레지스트리 작성
- AGENTS.md → Repo map의 소스 코드 경로를 실제 구조에 맞게

## 3단계: Claude Code 환경 업데이트
- CLAUDE.md의 "Build, Test & Quality" 섹션을 실제 명령으로 갱신
- .claude/hooks/run-checks.sh의 대상 확장자를 기술 스택에 맞게 조정

## 4단계: Docker 환경 (해당 시)

- Docker를 사용한다면:

  - dev/docker-compose.dev.yml 생성 (로컬 개발 전용)
    - 볼륨 마운트로 핫리로드
    - 디버그 포트 노출
    - .env.development 참조

  - 루트 docker-compose.yml 생성 (운영 서버 전용)
    - restart: always, 리소스 제한(memory/CPU)
    - healthcheck 정의
    - 디버그 포트 미노출
    - .env.production 참조

  - Dockerfile: multi-stage build (deps → build → runtime)
  - .dockerignore: node_modules, .git, .env*, coverage, dist
  - .env.example (커밋용, 변수 목록만 — 실제 값 없음)
  - 모든 포트는 환경변수: ${PORT:-3000}, ${DB_PORT:-5432}
  - DB 볼륨은 named volume, 프로덕션은 external: true
  - docs/agents/deploy-rules.md의 모든 규칙 준수

- Docker를 사용하지 않는다면 이 단계 건너뛰기

## 5단계: CI/CD

- .github/workflows/ci.yml (quality gate)
  - trigger: push to main/develop, PR to main/develop
  - steps: lint → typecheck → test → build → coverage → npm audit → docker build 검증
- .github/workflows/deploy.yml (배포)
  - trigger: CI 성공 후 main에서 workflow_run
  - steps: SSH로 사내 Docker 서버 접속 → git pull + docker compose up

- 회사 표준 흐름: story/* → develop → main → 자동 배포

## 6단계: 검증
- 현재 OS/셸에 맞는 validate 진입점을 실행해서 모든 명령이 정상 동작하는지 확인
  - bash/WSL/macOS/Linux: `./scripts/validate.sh`
  - Windows PowerShell: `./scripts/validate.ps1`
```

### 5단계: Phase A — Codex Desktop으로 구현 (Epic 단위)

Codex Desktop을 열고 아래 프롬프트를 입력합니다.

```
Epic 1의 story를 순서대로 처리해.

각 story마다:
1. bmad-create-story 스킬(.agents/skills/bmad-create-story)로 story 파일 생성
2. bmad-dev-story 스킬(.agents/skills/bmad-dev-story)로 구현 (TDD: red-green-refactor)
   - dev-story 스킬이 자체적으로 테스트 작성 + 실행 + DoD 검증을 수행함
   - sprint-status.yaml도 스킬이 자동으로 in-progress → review로 업데이트
3. dev-story 완료 후 현재 OS/셸에 맞는 validate-quick 실행하여 하네스 검증 (lint + typecheck + 관련 테스트)
   - bash/WSL/macOS/Linux: `./scripts/validate-quick.sh`
   - Windows PowerShell: `./scripts/validate-quick.ps1`
   - 실패 시 로그 확인: state/validate/latest/*.log
4. 통과 시 commit + push 필수: git add -A && git commit -m "feat(<story-이름>): implement story" && git push
5. 실패 시 수정 후 재검증, 3회 실패 시 skip하고 다음으로
6. push 완료 후에만 다음 story로 진행

모든 story 완료 후:
7. 현재 OS/셸에 맞는 validate 실행 (Epic 단위 통합 검증)
   - bash/WSL/macOS/Linux: `./scripts/validate.sh`
   - Windows PowerShell: `./scripts/validate.ps1`
8. 실패 시 로그 확인 후 수정: state/validate/latest/*.log
9. 수정 후 현재 OS/셸에 맞는 validate 재개
   - bash/WSL/macOS/Linux: `./scripts/validate.sh --from=실패단계`
   - Windows PowerShell: `./scripts/validate.ps1 --from=실패단계`
10. 전체 통과 후 commit + push

규칙:
- AGENTS.md의 모든 규칙을 따를 것
- docs/agents/ 아래 규칙 참조
- **docs/agents/feedback-rules.md를 반드시 읽고 과거 실수를 반복하지 말 것**
- story별 브랜치 생성: story/<story-이름>
- 현재 OS/셸에 맞는 validate-quick 진입점 통과한 story만 commit + push
- push 없이 다음 story 진행 금지
- 이전 story의 학습을 다음 story에 반영
```

> Epic 1이 끝나면 Phase B로 넘어갑니다.
>
> **검증 흐름**: Story 단위에서는 현재 OS/셸에 맞는 `validate-quick` 진입점으로 빠르게 검증합니다.
> bash/WSL/macOS/Linux는 `validate-quick.sh`, Windows PowerShell은 `validate-quick.ps1`를 사용합니다.
> Epic의 모든 Story 완료 후에도 같은 방식으로 `validate.sh` 또는 `validate.ps1`를 사용해 전체 통합 검증(순차 테스트 + 빌드 + 보안 + 성능)을 실행합니다.
> `smoke.sh` 또는 `smoke.ps1`(핵심 플로우 테스트)는 Phase B에서 최종 검증 시 실행됩니다.
>
> **검증 출력**: 기본 summary 모드로 단계별 성공/실패만 표시합니다.
> 실패 시 로그 경로가 출력되며, `state/validate/latest/*.log`에서 상세 로그를 확인할 수 있습니다.
> 전체 출력이 필요하면 bash/WSL/macOS/Linux는 `VALIDATE_OUTPUT_MODE=verbose`, Windows PowerShell은 `$env:VALIDATE_OUTPUT_MODE='verbose'`를 설정하세요.

> **운영체제 감지 원칙**: 프롬프트에도 "현재 OS/셸을 먼저 확인하고 그에 맞는 검증 진입점을 선택하라"를 넣을 수 있습니다.
> 다만 실제 자동화 안정성은 프롬프트보다 스크립트 진입점(`.sh`/`.ps1`)에 반영하는 쪽이 더 높습니다.

### 6단계: Phase B — Claude Code로 리뷰 + 수정 (Epic 단위)

Claude Code를 열고 아래 프롬프트를 입력합니다.

```
Epic 1의 구현 결과를 리뷰하고 수정해줘.

1. sprint-status.yaml에서 review 상태인 story 확인
2. 각 story의 코드를 bmad-code-review 스킬(.claude/skills/bmad-code-review)로 리뷰
   - spec 파일로 해당 story 파일을 지정 (story의 acceptance criteria 기준 검증)
   - REVIEW.md도 함께 참조하여 아키텍처/보안/성능 기준 적용
   - (Blind Hunter + Edge Case Hunter + Acceptance Auditor 3층 병렬 리뷰)
3. REJECTED 항목은 직접 수정
4. 누락된 테스트가 있으면 보강
5. 현재 OS/셸에 맞는 validate + smoke 진입점으로 최종 검증
   - bash/WSL/macOS/Linux: `./scripts/validate.sh` + `./scripts/smoke.sh`
   - Windows PowerShell: `./scripts/validate.ps1` + `./scripts/smoke.ps1`
   - 실패 시 로그 확인: state/validate/latest/*.log
6. 모든 story APPROVED 후 **develop** 브랜치에 merge (회사 표준: develop → CI → main → 자동 배포)
7. sprint-status.yaml 업데이트 (review → done)
```

### 7단계: Phase C — 회고 + Harness 강화 (Epic 완료 후)

Phase B 완료 후, **같은 Claude Code 세션**에서 이어서 실행합니다.

```
이번 Epic의 리뷰 결과를 분석하고 harness를 강화해줘.

1. 아래 파일들을 모두 읽고 반복된 실수 패턴을 찾아줘:
   - reviews/epic-1/*.md (리뷰 결과)
   - reviews/epic-1/logs/*-validate.log (validate 실패 로그)
   - reviews/epic-1/logs/*-codex.log (Codex 실행 로그)
   - state/validate/latest/*.log (최신 validate 단계별 로그)
   - state/epic-1-progress.json (failed/skipped story)
2. 발견된 패턴마다 feedback/incidents/에 YAML 기록
   (feedback/incident-template.yaml 형식 참고)
3. 각 incident에 대해 재현 테스트를 tests/regression/에 작성
   (예: tests/regression/epic-1-missing-limit.test.ts)
   다음 Epic의 전체 validate 단계에서 자동으로 실행됨
4. state/learning-loop.json 업데이트 (패턴별 발생 횟수)
5. 승격 정책에 따라 조치:
   - 1회: 기록만
   - 2회: docs/agents/feedback-rules.md에 활성 규칙 추가
   - 3회+ (기계적으로 판별 가능한 경우만): 전체 validate 스크립트에 blocking check로 추가 (warning이 아닌 exit 1)
   - 아키텍처 성격: docs/agents/architecture-rules.md 또는 docs/decisions/에 ADR
6. feedback-rules.md는 최대 10개 active rule 유지
   - 2 Epic 동안 재발 없으면 retired로 이동
   - 전체 validate 스크립트로 승격된 항목은 제거
7. harness 파일을 수정했으면 반드시 현재 OS/셸에 맞는 검증 진입점으로 재검증
   - bash/WSL/macOS/Linux: `bash -n scripts/validate.sh && ./scripts/validate.sh`
   - Windows PowerShell: `./scripts/validate.ps1`
8. 검증 통과 후 커밋: chore(harness): Epic 1 회고 반영
9. 이번 Epic의 merged된 story 브랜치 정리 (archive tag로 복구 포인트 보존):
   - dry-run: ./scripts/cleanup-branches.sh
   - 확인 후 실행: ./scripts/cleanup-branches.sh --apply
   - 삭제된 브랜치는 archive/<name>/<date> 태그로 영구 보존됨

핵심: incident를 기록만 하면 아카이브일 뿐입니다.
재현 테스트(regression test)를 함께 만들어야 다음 Epic에서 자동 재발 방지가 됩니다.
```

### 8단계: 다음 Epic 또는 완료

```
Phase A (Codex Desktop): Epic 2 구현
Phase B (Claude Code): Epic 2 리뷰
Phase C (Claude Code): Epic 2 회고
...반복...
```

---

## 가벼운 작업 (Quick Flow)

BMAD 풀코스 없이 간단한 수정/기능 추가를 할 때도 Phase A/B 패턴을 따릅니다.

### Quick Flow Phase A: Codex Desktop에서 구현

```
아래 작업을 bmad-quick-dev 스킬(.agents/skills/bmad-quick-dev)로 처리해.

작업 내용: [여기에 작업 설명]

규칙:
- AGENTS.md의 규칙을 따를 것
- docs/agents/ 아래 모든 규칙 참조 (security, performance, deploy 포함)
- story 브랜치 생성: feature/<작업-이름>
- 구현 완료 후 현재 OS/셸에 맞는 validate-quick 진입점 실행하여 빠른 검증
  - bash/WSL/macOS/Linux: `./scripts/validate-quick.sh`
  - Windows PowerShell: `./scripts/validate-quick.ps1`
- 검증 통과 후 commit + push
```

또는 Barry(빠른 구현 전문가)를 호출:

```
bmad-agent-quick-flow-solo-dev(.agents/skills/bmad-agent-quick-flow-solo-dev)에게 아래 작업을 시켜줘.

작업 내용: [여기에 작업 설명]

규칙:
- AGENTS.md 규칙 준수
- docs/agents/ 규칙 참조
- 구현 완료 후 현재 OS/셸에 맞는 validate-quick 진입점 통과 후 commit + push
```

### Quick Flow Phase B: Claude Code에서 검증

```
feature/ 브랜치의 변경 사항을 리뷰하고 수정해줘.

1. git diff main 확인
2. bmad-code-review 스킬(.claude/skills/bmad-code-review)로 리뷰
   - REVIEW.md를 참조하여 판정 기준 적용
3. REJECTED 항목 직접 수정
4. 현재 OS/셸에 맞는 validate 진입점 실행하여 최종 검증
   - bash/WSL/macOS/Linux: `./scripts/validate.sh`
   - Windows PowerShell: `./scripts/validate.ps1`
   - 실패 시 로그 확인: state/validate/latest/*.log
5. APPROVED 후 develop에 merge (CI 통과하면 develop → main 승격 PR)
```

> Quick Flow도 현재 OS/셸에 맞는 전체 validate 진입점 검증 + bmad-code-review 리뷰는 동일하게 적용됩니다.
> smoke는 핵심 플로우를 건드린 경우에만 현재 OS/셸에 맞는 진입점으로 실행합니다.


---

## Docker / DB 작업 지시 표준

AI에게 Docker 또는 DB 마이그레이션 작업을 시키실 때는 **환경을 한국어로 명시**하세요. "dev", "prod" 같은 영어 약어는 사용자-AI 사이 혼동을 유발합니다.

### 표준 지시 문구

```
<프로젝트명> 개발 환경으로 docker 구성해
<프로젝트명> 운영 환경으로 docker 구성해
<프로젝트명> 개발 환경에서 마이그레이션 돌려
<프로젝트명> 운영 환경에 배포용 compose 만들어
```

이 문구를 받으면 AI는 자동으로 다음을 수행:

1. `./scripts/docker-guard.sh --env development|production`로 현재 compose 상태 검증
2. compose 파일의 `name:` (운영=`<접두사>` vs 개발=`<접두사>-dev`)과 `x-environment:` (`production` vs `development`) 라벨이 지시와 일치하는지 교차 확인
3. 불일치 또는 중복 컨테이너 감지 시 중단 후 보고
4. 마이그레이션이면 `./scripts/db-migrate.sh --cmd "..." --env <환경>` 래퍼로 실행

### 내부 값은 영어 유지

지시 문구는 한국어이지만 **파일 값·CLI 인자는 영어**를 유지합니다 (범용성·도구 호환성):

- `x-environment: production` / `x-environment: development`
- `--env production` / `--env development`
- 사용자가 `"개발 환경으로 구성해"` 라고 지시 → AI는 내부적으로 `--env development`로 변환

### 상세 규칙

- Docker 일반: `docs/agents/docker-rules.md`
- 환경 분리·compose name 규칙: `docs/agents/deploy-rules.md`
- DB 마이그레이션 안전: `docs/agents/migration-rules.md`

---

## 파일 구조

```
├── CLAUDE.md                          Claude Code 지침 (Phase B: 리뷰+수정)
├── AGENTS.md                          저장소 공식 규칙 (Phase A+B 공용)
├── REVIEW.md                          코드 리뷰 기준
├── .gitignore                         추적 제외 파일
│
├── .agents/skills/                    Codex용 BMAD 스킬 (Phase A)
│   ├── bmad-create-story/             story 생성 (풀 컨텍스트 엔진)
│   ├── bmad-dev-story/                story 구현 (TDD)
│   ├── db-backup-setup/               DB 백업 시스템 설정 스킬
│   └── ...
│
├── .claude/
│   ├── settings.json                  Hook 설정
│   ├── hooks/
│   │   ├── block-rm.sh                위험 명령 차단
│   │   ├── check-feedback-rules.sh    세션 시작 시 활성 피드백 규칙 표시
│   │   ├── docker-guard-hook.sh       docker/마이그레이션 명령 실행 전 안전 차단
│   │   ├── run-checks.sh              편집 파일만 eslint (빠른 피드백)
│   │   └── warn-uncommitted.sh        세션 종료 시 uncommitted changes 경고
│   └── skills/                        Claude Code용 BMAD 스킬 (Phase B)
│       ├── bmad-code-review/          3층 병렬 코드 리뷰
│       └── ...
│
├── .githooks/                         Git hook (husky 없이 core.hooksPath 방식)
│   ├── pre-commit                     staged 파일 eslint + .env 차단 + 대형 커밋 경고
│   └── commit-msg                     Conventional Commits 형식 검증
│
├── docs/
│   ├── agents/
│   │   ├── architecture-rules.md      아키텍처 경계, API 버저닝, health check
│   │   ├── backup-rules.md            DB 백업 시스템 설계 규칙 (4계층)
│   │   ├── coding-rules.md            코드 작성, 로깅 표준, 환경변수
│   │   ├── testing-rules.md           테스트 규칙, 격리, 4층 검증 체계
│   │   ├── security-rules.md          보안 (시크릿, 인증, 입력검증, 에러노출)
│   │   ├── performance-rules.md       성능 (N+1, LIMIT, 이벤트 cleanup)
│   │   ├── deploy-rules.md            배포 (환경 분리, compose name 환경 접미사, graceful shutdown)
│   │   ├── docker-rules.md            Docker 네이밍/포트/검증 일반 원칙
│   │   ├── migration-rules.md         DB 마이그레이션 데이터 유실 방지
│   │   ├── workflow-rules.md          Phase A/B/C 작업 흐름
│   │   ├── feedback-rules.md          과거 실수 패턴 활성 교훈
│   │   └── seo-rules.md              SEO/AEO/GEO 구현 규칙
│   ├── changelog/                     하네스 개선 이력 (비개발자 요약 포함)
│   ├── future-upgrades/               미도입 기능 도입 가이드 (OIDC/OTel/ZAP/Scorecard)
│   ├── checklists/
│   │   ├── page-update.md             페이지 수정 후 SEO/AEO/GEO 체크리스트
│   │   └── pre-deploy.md              배포 전 체크리스트
│   ├── decisions/                     ADR
│   └── org/
│       └── docker-port-registry.template.md  조직 포트 레지스트리 template (복사 후 private/에 실제 값)
│
├── private/                           외부 공개 금지 내부 정보 (.gitignore로 보호, README.md만 커밋)
│
├── templates/
│   ├── execplan.md                    ExecPlan 템플릿
│   └── adr.md                         ADR 템플릿
│
├── scripts/
│   ├── lib/
│   │   ├── validate-utils.sh          검증 공용 헬퍼 (래퍼, 로그, summary/verbose)
│   │   └── powershell-utils.ps1       PowerShell용 Git Bash 호출 (WSL opt-in)
│   ├── setup/
│   │   ├── init-harness.sh            하네스 자동 초기화 통합 (4단계 프롬프트에서 호출)
│   │   ├── init-harness.ps1           Windows 버전
│   │   ├── install-git-hooks.sh       .githooks/ 활성화 (init-harness가 호출)
│   │   ├── install-git-hooks.ps1      Windows 버전
│   │   ├── setup-repo.sh              GitHub repo 보안 설정 (init-harness가 호출, gh CLI 필요)
│   │   └── setup-repo.ps1             Windows 버전
│   ├── run-epic.sh                    CLI fallback (Codex Desktop 없을 때)
│   ├── validate-quick.sh              bash/WSL/macOS/Linux Story 빠른 검증
│   ├── validate-quick.ps1             Windows PowerShell Story 빠른 검증
│   ├── validate.sh                    bash/WSL/macOS/Linux Epic 전체 검증
│   ├── validate.ps1                   Windows PowerShell Epic 전체 검증
│   ├── smoke.sh                       bash/WSL/macOS/Linux 스모크 테스트
│   ├── smoke.ps1                      Windows PowerShell 스모크 테스트
│   ├── cleanup-branches.sh            로컬+원격 merged 브랜치 정리 (archive tag로 복구 보존, Phase C에서 호출)
│   ├── docker-guard.sh/.ps1           Docker 작업 전후 안전 검증 (환경 라벨 + 중복 컨테이너 감지)
│   ├── db-migrate.sh/.ps1             DB 마이그레이션 안전 래퍼 (자동 pg_dump + 실패 시 복원 안내)
│   └── status.sh                      진행 상태 대시보드
│
├── _bmad-output/
│   ├── planning-artifacts/            PRD, architecture, epics
│   └── implementation-artifacts/      sprint-status, story 파일
│
├── feedback/
│   ├── incidents/                     Phase C에서 생성되는 실수 기록 (YAML)
│   └── incident-template.yaml         incident 구조 템플릿
│
├── state/                             작업 진행 상태 + learning-loop.json
│   └── validate/                      검증 로그 아카이브
│       └── latest/                    최신 실행 로그 (단계별 *.log)
├── plans/                             ExecPlan (복잡한 작업)
└── reviews/                           리뷰 결과 + 로그
```

---

## 운영 요약

| 단계 | 도구 | BMAD 스킬 | 산출물 |
|---|---|---|---|
| 기획/설계 | Claude Code | create-prd, create-architecture, create-epics | PRD, Architecture, Epics |
| 프로젝트 초기화 | Claude Code | — | scaffolding, 린팅/테스트 설정 |
| **Phase A: 구현** | **Codex Desktop** | **create-story, dev-story** | **코드 + 커밋 + story 파일** |
| **Phase B: 품질 보장** | **Claude Code** | **code-review** | **리뷰 결과 + 수정 + 테스트** |
| **Phase C: 회고** | **Claude Code** | **bmad-retrospective (선택)** | **incidents + feedback-rules 갱신 + harness 강화** |

## 검증 철학: Strict Execution, Concise Summary, Full Artifacts

이 하네스의 검증 스크립트는 세 가지 원칙을 따릅니다:

- 판정은 엄격하게 — 검증 단계, 테스트 범위, 실패 기준은 약화하지 않음
- 기본 출력은 짧게 — AI 에이전트가 소비하는 토큰을 최소화하되, 실패 원인 파악에 필요한 신호는 유지
- 원본 증거는 항상 보존 — 모든 실행의 전체 로그를 `state/validate/latest/*.log`에 단계별로 저장

| 환경변수 | 값 | 설명 |
|---|---|---|
| `VALIDATE_OUTPUT_MODE` | `summary` (기본) | 단계별 성공/실패 + 소요시간만 출력. 실패 시 로그 경로 + 핵심 출력 포함 |
| `VALIDATE_OUTPUT_MODE` | `verbose` | 전체 로그를 콘솔에 실시간 출력 (기존 방식) |

실패 시 디버깅 흐름:
1. summary 출력에서 실패 단계와 로그 경로 확인
2. 해당 로그 파일을 읽어서 원인 파악 (예: `state/validate/latest/04a-test.log`)
3. 수정 후 현재 OS/셸에 맞는 validate 진입점으로 `--from=실패단계` 재개
   - bash/WSL/macOS/Linux: `./scripts/validate.sh --from=실패단계`
   - Windows PowerShell: `./scripts/validate.ps1 --from=실패단계`

## Harness 작동 매트릭스

모든 harness가 언제, 어떻게 작동하는지 한눈에 확인할 수 있습니다.

### 자동 작동 (사람 개입 불필요)

| Harness | 트리거 | 대상 | 설명 |
|---|---|---|---|
| `block-rm.sh` | Claude Code에서 Bash 명령 실행 시 | Phase B | `rm -rf` 등 위험 명령 자동 차단 |
| `run-checks.sh` | Claude Code에서 Edit/Write 시 | Phase B | 편집 파일만 eslint (빠르게), 실패 시만 노출 |
| `warn-uncommitted.sh` | Claude Code 세션 종료 시 | Phase B | uncommitted changes 있으면 경고 (차단 아님) |
| `.githooks/pre-commit` | git commit 시 | 공통 (install-git-hooks.sh 필요) | staged 파일 eslint + .env 차단 + 대형 커밋 경고 |
| `.githooks/commit-msg` | git commit 시 | 공통 (install-git-hooks.sh 필요) | Conventional Commits 형식 검증 |
| CLAUDE.md @import | Claude Code 세션 시작 시 | Phase B | 모든 규칙 파일 + REVIEW.md 자동 로드 |
| AGENTS.md | Codex Desktop 세션 시작 시 | Phase A | 저장소 규칙 자동 로드 |
| bmad-dev-story TDD | Phase A에서 story 구현 시 | Phase A | red-green-refactor 사이클 강제 |
| bmad-dev-story DoD | Phase A에서 story 완료 시 | Phase A | 10개 항목 정의 완료 검증 자동 실행 |
| sprint-status.yaml | bmad 스킬 실행 시 | Phase A | backlog→in-progress→review 자동 업데이트 |

### 프롬프트로 호출 (명시적 지시 필요)

| Harness | 호출 방법 | 대상 | 설명 |
|---|---|---|---|
| `validate-quick` | bash/WSL/macOS/Linux는 `./scripts/validate-quick.sh`, Windows PowerShell은 `./scripts/validate-quick.ps1` | Phase A (Story) | 빠른 검증 (lint + typecheck + 관련 테스트) |
| `validate` | bash/WSL/macOS/Linux는 `./scripts/validate.sh`, Windows PowerShell은 `./scripts/validate.ps1` | Phase A (Epic) / Phase B | 전체 검증 (8단계, --from 재개 지원) |
| `smoke` | bash/WSL/macOS/Linux는 `./scripts/smoke.sh`, Windows PowerShell은 `./scripts/smoke.ps1` | Phase B | 핵심 사용자 플로우 스모크 테스트 |
| `bmad-create-story` | Phase A 프롬프트에 포함 | Phase A | story 파일 생성 (풀 컨텍스트 엔진) |
| `bmad-code-review` | Phase B 프롬프트에 포함 | Phase B | 3층 병렬 리뷰 (Blind + Edge Case + Acceptance) |
| `bmad-quick-dev` | `bmad-quick-dev` 직접 호출 | Quick Flow | 가벼운 작업용 |

### 자동 (CI/CD — PR/push 시)

| Harness | 트리거 | 설명 |
|---|---|---|
| `.github/workflows/ci.yml` | main/develop에 PR 생성 또는 push 시 | lint → typecheck → test → build → coverage → audit → docker build 검증 |
| `.github/workflows/security.yml` | main/develop push/PR + 주간 월요일 09:00 KST | Gitleaks(시크릿) + CodeQL(SAST) + Trivy(의존성/Docker 이미지 CVE) |
| `.github/workflows/release.yml` | `v*.*.*` 태그 push 시 | CI 재검증 → GitHub Release 자동 생성 (changelog 포함) |
| `.github/workflows/deploy.yml` | main push + CI 성공 직후 | SSH로 사내 Docker 서버 접속 → git pull + docker compose up (+ 옵션 pre-backup/post-smoke) |
| `.github/workflows/dependabot-auto-merge.yml` | Dependabot이 PR 오픈 시 | patch/minor만 자동 approve + merge. major는 수동 대기 |
| `.github/dependabot.yml` | 매주 월요일 09:00 KST | npm/github-actions/docker 3개 ecosystem 주간 업데이트 PR 자동 생성 |

### 규칙 파일 (에이전트가 자동 참조)

| 규칙 파일 | Phase A | Phase B | 검증 시점 |
|---|---|---|---|
| `architecture-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh |
| `coding-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + lint |
| `testing-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 |
| `security-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh 보안 체크 |
| `performance-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh 성능 체크 |
| `deploy-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh Docker 체크 |
| `feedback-rules.md` | AGENTS.md에 명시적 읽기 지시 | @import 자동 로드 | Phase A 시작 시 + Phase C에서 재작성 |
| `workflow-rules.md` | docs/agents/로 참조 | @import 자동 로드 | — |
| `REVIEW.md` | — | @import 자동 로드 | Phase B 리뷰 시 APPROVED/REJECTED 판정 기준 |
| `backup-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + 배포 전 체크리스트 |
| `seo-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + 페이지 수정 후 체크리스트 |

---

## 다른 AI 도구 사용 시 (Kiro, Antigravity 등)

이 Harness의 핵심 자산은 **도구 독립적**입니다:
- `docs/agents/*.md` (규칙 10개) — 어떤 AI 도구든 동일하게 적용
- bash/WSL/macOS/Linux는 `scripts/*.sh`, Windows PowerShell은 `scripts/*.ps1` 진입점 사용
- `REVIEW.md` — 리뷰 기준은 도구와 무관

BMAD 스킬이 없는 도구를 사용할 때는 아래 프롬프트에 규칙 파일을 직접 참조시키세요.

### 구현 프롬프트 (Phase A 대체)

```
아래 작업을 구현해줘.

작업 내용: [설명]

반드시 아래 규칙 파일을 읽고 따를 것:
- docs/agents/architecture-rules.md (레이어 경계, API 규칙, health check)
- docs/agents/coding-rules.md (파일 구조, 로깅, 에러 처리)
- docs/agents/security-rules.md (시크릿, 인증, 입력 검증)
- docs/agents/performance-rules.md (N+1, LIMIT, 이벤트 cleanup)
- docs/agents/deploy-rules.md (Docker, 포트, DB 보호)
- docs/agents/testing-rules.md (테스트 대상, 작성 원칙)
- docs/agents/backup-rules.md (DB 백업 — 해당 시)
- docs/agents/seo-rules.md (SEO/AEO/GEO — 웹 프로젝트 시)

완료 전 반드시:
- 현재 OS/셸에 맞는 validate-quick 진입점 실행하여 빠른 검증 통과
- 검증 통과 후 commit + push: git add -A && git commit -m "feat(<scope>): <설명>" && git push
```

### 리뷰 프롬프트 (Phase B 대체)

```
현재 브랜치의 변경 사항을 리뷰하고 수정해줘.

리뷰 기준: REVIEW.md 파일을 읽고 그대로 따를 것.
추가 참조: docs/agents/ 아래 모든 규칙 파일.

REJECTED 항목은 직접 수정하고,
현재 OS/셸에 맞는 validate + smoke 진입점으로 최종 검증 후
develop에 merge (CI 통과 후 main 승격).
```

> 이 프롬프트들은 BMAD 스킬 없이도 **규칙 파일 + 검증 스크립트**만으로
> Harness의 핵심 가치(문맥, 테스트 계약, 리뷰 루프)를 유지합니다.

---

## 운영 체크리스트

자동화할 수 없는 항목(콘텐츠-메타데이터 일관성, 배포 전 수동 확인 등)은 체크리스트로 관리합니다.
각 체크리스트에는 LLM에게 전달할 프롬프트도 포함되어 있습니다.

| 시점 | 체크리스트 | 설명 |
|---|---|---|
| 페이지 수정 후 | [docs/checklists/page-update.md](docs/checklists/page-update.md) | SEO 메타데이터, JSON-LD, GEO 인용 문장, OG 이미지 일관성 |
| 배포 전 | [docs/checklists/pre-deploy.md](docs/checklists/pre-deploy.md) | DB 백업, 환경변수, 마이그레이션, 인프라 확인 |

---