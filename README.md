# Harness Engineering Starter Kit
# BMAD + Claude Code + Codex Desktop 통합 운영 구조

## 개요

이 키트는 **Codex Desktop(구현) + Claude Code(품질 보장)** 조합으로
100% AI 개발을 수행하기 위한 harness engineering 스타터 템플릿입니다.

```
기획/설계: Claude Code + BMAD
  PRD → Architecture → Epics/Stories

Phase A: Codex Desktop (구현, Epic 단위)
  story마다: bmad-create-story → bmad-dev-story → validate

Phase B: Claude Code (품질 보장, Epic 단위)
  bmad-code-review → 오류 직접 수정 → 테스트 보강
```

## 사전 조건

- Claude Code CLI, Codex Desktop, Git, Node.js 20+
- jq 설치 완료 (`brew install jq` 또는 `sudo apt-get install -y jq`)

---

## 셋업 순서

### 1단계: 이 레파지토리를 프로젝트에 복사

프로젝트 시작 전 이 레파지토리 전체를 복사하여 붙여넣습니다.
BMAD와 하네스 파일이 모두 포함되어 있습니다.

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

## 1단계: 프로젝트 초기화
architecture.md의 기술 스택에 맞게 프로젝트를 초기화해줘.
- 프로젝트 scaffolding (적절한 create 명령 또는 수동 초기화)
- package.json (또는 해당 언어의 프로젝트 파일)
- TypeScript 설정 (tsconfig.json) — 해당 시
- 린팅 설정 (ESLint 등)
- 포맷팅 설정 (Prettier 등)
- 테스트 프레임워크 설정 (Vitest, Jest, Playwright 등)
- .gitignore 보완 (기술 스택에 맞게)

## 2단계: 하네스 파일 커스터마이징
- scripts/validate.sh → 실제 빌드/타입체크/린트/테스트 명령으로 교체
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
- .github/workflows/ci.yml 생성
  - trigger: push to main, PR to main
  - steps: lint → typecheck → test → build → npm audit
- Phase B에서 main에 merge할 때 마지막 안전망 역할

## 6단계: 검증
- scripts/validate.sh를 실행해서 모든 명령이 정상 동작하는지 확인
```

### 5단계: Phase A — Codex Desktop으로 구현 (Epic 단위)

Codex Desktop을 열고 아래 프롬프트를 입력합니다.

```
Epic 1의 story를 순서대로 처리해.

각 story마다:
1. bmad-create-story 스킬(.agents/skills/bmad-create-story)로 story 파일 생성
2. bmad-dev-story 스킬(.agents/skills/bmad-dev-story)로 구현 (TDD: red-green-refactor)
3. ./scripts/validate.sh 실행하여 검증
4. 통과 시 커밋: feat(<story-이름>): implement story
5. 실패 시 수정 후 재검증, 3회 실패 시 skip하고 다음으로
6. sprint-status.yaml은 스킬 워크플로우가 자동 업데이트

규칙:
- AGENTS.md의 모든 규칙을 따를 것
- docs/agents/ 아래 규칙 참조
- story별 브랜치 생성: story/<story-이름>
- validate.sh 통과한 story만 커밋
- 이전 story의 학습을 다음 story에 반영
```

> Epic 1이 끝나면 Phase B로 넘어갑니다.
>
> **검증 흐름**: Codex가 각 story 구현 후 `validate.sh`를 자동 실행합니다.
> `validate.sh`는 빌드, 린트, 테스트, 보안 체크, 성능 체크를 7단계로 수행합니다.
> `smoke.sh`(핵심 플로우 테스트)는 Phase B에서 최종 검증 시 실행됩니다.

### 6단계: Phase B — Claude Code로 리뷰 + 수정 (Epic 단위)

Claude Code를 열고 아래 프롬프트를 입력합니다.

```
Epic 1의 구현 결과를 리뷰하고 수정해줘.

1. sprint-status.yaml에서 review 상태인 story 확인
2. 각 story의 코드를 bmad-code-review 스킬로 리뷰
   (Blind Hunter + Edge Case Hunter + Acceptance Auditor 3층 병렬 리뷰)
3. REJECTED 항목은 직접 수정해줘
4. 누락된 테스트가 있으면 보강
5. scripts/validate.sh + scripts/smoke.sh 최종 검증
6. 모든 story APPROVED 후 main에 merge
7. sprint-status.yaml 업데이트 (review → done)
```

### 7단계: 다음 Epic 또는 완료

```
Phase A (Codex Desktop): Epic 2 구현
Phase B (Claude Code): Epic 2 리뷰
...반복...
```

### 실패한 Story 처리

Phase B에서 직접 수정이 어려운 경우:

```bash
claude
```

```
state/epic-1-progress.json 또는 sprint-status.yaml에서
failed/skip된 story를 확인하고,
reviews/epic-1/ 아래 리뷰 결과를 읽어서 문제를 파악한 후 수정해줘.
```

---

## 가벼운 작업 (Quick Flow)

BMAD 풀코스 없이 간단한 수정/기능 추가를 할 때도 Phase A/B 패턴을 따릅니다.

### Quick Flow Phase A: Codex Desktop에서 구현

```
아래 작업을 bmad-quick-dev 스킬로 처리해.

작업 내용: [여기에 작업 설명]

규칙:
- AGENTS.md의 규칙을 따를 것
- docs/agents/ 아래 모든 규칙 참조 (security, performance, deploy 포함)
- story 브랜치 생성: feature/<작업-이름>
- ./scripts/validate.sh 실행하여 검증 통과 후 커밋
```

또는 Barry(빠른 구현 전문가)를 호출:

```
bmad-agent-quick-flow-solo-dev에게 아래 작업을 시켜줘.

작업 내용: [여기에 작업 설명]

규칙:
- AGENTS.md 규칙 준수
- docs/agents/ 규칙 참조
- validate.sh 통과 후 커밋
```

### Quick Flow Phase B: Claude Code에서 검증

```
feature/ 브랜치의 변경 사항을 리뷰하고 수정해줘.

1. git diff main 확인
2. bmad-code-review 스킬로 리뷰
3. REJECTED 항목 직접 수정
4. scripts/validate.sh 실행하여 최종 검증
5. APPROVED 후 main에 merge
```

> Quick Flow도 **validate.sh 검증 + bmad-code-review 리뷰**는 동일하게 적용됩니다.
> smoke.sh는 핵심 플로우를 건드린 경우에만 실행합니다.


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
│   └── ...
│
├── .claude/
│   ├── settings.json                  Hook 설정
│   ├── hooks/
│   │   ├── block-rm.sh                위험 명령 차단
│   │   └── run-checks.sh              편집 후 자동 lint+typecheck
│   └── skills/                        Claude Code용 BMAD 스킬 (Phase B)
│       ├── bmad-code-review/          3층 병렬 코드 리뷰
│       └── ...
│
├── docs/
│   ├── agents/
│   │   ├── architecture-rules.md      아키텍처 경계, API 버저닝, health check
│   │   ├── coding-rules.md            코드 작성, 로깅 표준, 환경변수
│   │   ├── testing-rules.md           테스트 규칙
│   │   ├── security-rules.md          보안 (시크릿, 인증, 입력검증, 에러노출)
│   │   ├── performance-rules.md       성능 (N+1, LIMIT, 이벤트 cleanup)
│   │   ├── deploy-rules.md            배포 (Docker, 포트, DB 보호, graceful shutdown)
│   │   └── workflow-rules.md          Phase A/B 작업 흐름
│   └── decisions/                     ADR
│
├── templates/
│   ├── execplan.md                    ExecPlan 템플릿
│   └── adr.md                         ADR 템플릿
│
├── scripts/
│   ├── run-epic.sh                    CLI fallback (Codex Desktop 없을 때)
│   ├── validate.sh                    공통 검증
│   ├── smoke.sh                       스모크 테스트
│   └── status.sh                      진행 상태 대시보드
│
├── _bmad-output/
│   ├── planning-artifacts/            PRD, architecture, epics
│   └── implementation-artifacts/      sprint-status, story 파일
│
├── state/                             작업 진행 상태
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

## Harness 작동 매트릭스

모든 harness가 언제, 어떻게 작동하는지 한눈에 확인할 수 있습니다.

### 자동 작동 (사람 개입 불필요)

| Harness | 트리거 | 대상 | 설명 |
|---|---|---|---|
| `block-rm.sh` | Claude Code에서 Bash 명령 실행 시 | Phase B | `rm -rf` 등 위험 명령 자동 차단 |
| `run-checks.sh` | Claude Code에서 Edit/Write 시 | Phase B | lint + typecheck 자동 실행, 실패 시만 노출 |
| CLAUDE.md @import | Claude Code 세션 시작 시 | Phase B | 모든 규칙 파일(8개) 자동 로드 |
| AGENTS.md | Codex Desktop 세션 시작 시 | Phase A | 저장소 규칙 자동 로드 |
| bmad-dev-story TDD | Phase A에서 story 구현 시 | Phase A | red-green-refactor 사이클 강제 |
| bmad-dev-story DoD | Phase A에서 story 완료 시 | Phase A | 10개 항목 정의 완료 검증 자동 실행 |
| sprint-status.yaml | bmad 스킬 실행 시 | Phase A | backlog→in-progress→review 자동 업데이트 |

### 프롬프트로 호출 (명시적 지시 필요)

| Harness | 호출 방법 | 대상 | 설명 |
|---|---|---|---|
| `validate.sh` | `./scripts/validate.sh` 또는 프롬프트에서 지시 | Phase A/B | 7단계 검증 (빌드, 린트, 테스트, 보안, 성능) |
| `smoke.sh` | `./scripts/smoke.sh` 또는 프롬프트에서 지시 | Phase B | 핵심 사용자 플로우 스모크 테스트 |
| `bmad-create-story` | Phase A 프롬프트에 포함 | Phase A | story 파일 생성 (풀 컨텍스트 엔진) |
| `bmad-code-review` | Phase B 프롬프트에 포함 | Phase B | 3층 병렬 리뷰 (Blind + Edge Case + Acceptance) |
| `bmad-quick-dev` | `bmad-quick-dev` 직접 호출 | Quick Flow | 가벼운 작업용 |

### 자동 (CI/CD — PR/push 시)

| Harness | 트리거 | 설명 |
|---|---|---|
| `.github/workflows/ci.yml` | main에 PR 생성 또는 push 시 | lint → typecheck → test → build → audit. Phase B에서 merge할 때 **마지막 안전망** |

### 규칙 파일 (에이전트가 자동 참조)

| 규칙 파일 | Phase A | Phase B | 검증 시점 |
|---|---|---|---|
| `architecture-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh |
| `coding-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + lint |
| `testing-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 |
| `security-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh 보안 체크 |
| `performance-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh 성능 체크 |
| `deploy-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh Docker 체크 |
| `workflow-rules.md` | docs/agents/로 참조 | @import 자동 로드 | — |
| `REVIEW.md` | — | @import 자동 로드 | Phase B 리뷰 시 APPROVED/REJECTED 판정 기준 |

---

## 다른 AI 도구 사용 시 (Kiro, Antigravity 등)

이 Harness의 핵심 자산은 **도구 독립적**입니다:
- `docs/agents/*.md` (규칙 7개) — 어떤 AI 도구든 동일하게 적용
- `scripts/validate.sh`, `scripts/smoke.sh` — 어떤 환경에서든 실행 가능
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

완료 전 반드시:
- ./scripts/validate.sh 실행하여 검증 통과
- 커밋 형식: feat(<scope>): <설명>
```

### 리뷰 프롬프트 (Phase B 대체)

```
현재 브랜치의 변경 사항을 리뷰하고 수정해줘.

리뷰 기준: REVIEW.md 파일을 읽고 그대로 따를 것.
추가 참조: docs/agents/ 아래 모든 규칙 파일.

REJECTED 항목은 직접 수정하고,
./scripts/validate.sh + ./scripts/smoke.sh로 최종 검증 후
main에 merge.
```

> 이 프롬프트들은 BMAD 스킬 없이도 **규칙 파일 + 검증 스크립트**만으로
> Harness의 핵심 가치(문맥, 테스트 계약, 리뷰 루프)를 유지합니다.

---

## 선택적 확장

### .worktreeinclude

`claude --worktree` 사용 시 gitignored 파일을 worktree로 복사:

```
.env
.env.local
config/local.yaml
```
