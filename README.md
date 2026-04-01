# Harness Engineering Starter Kit
# BMAD + Claude Code + Codex 통합 운영 구조

## 개요

이 키트는 **Claude Code(대화형 오케스트레이터) + Codex(구현 엔진)** 조합으로
100% AI 개발을 수행하기 위한 harness engineering 스타터 템플릿입니다.

**핵심 원칙**: Claude Code 대화형 세션이 전체 파이프라인을 오케스트레이션합니다.
Codex는 Claude Code가 Bash tool을 통해 호출하는 구현 엔진입니다.

```
Claude Code (대화형 세션)
  ├── BMAD 기획/설계 (PRD → Architecture → Stories)
  ├── 프로젝트 초기화 + 하네스 설정
  ├── Epic 오케스트레이션
  │     ├── codex exec로 구현 호출
  │     ├── validate.sh로 검증
  │     ├── 직접 코드 리뷰 (Read/Grep/Glob)
  │     ├── REJECTED → codex exec로 수정 지시
  │     └── APPROVED → merge
  └── 실패 story 수동 보완
```

## 사전 조건

- Claude Code CLI 설치 및 로그인 완료
- Codex CLI 설치 및 로그인 완료 (`npm i -g @openai/codex`)
- Git 설정 완료
- BMAD 설치 완료 (이 레파지토리에 포함됨)
- jq 설치 완료 (`brew install jq` 또는 `sudo apt-get install -y jq`)
- Node.js 20+

---

## 셋업 순서

### 1단계: 이 레파지토리를 프로젝트에 복사

프로젝트 시작 전 이 레파지토리 전체를 복사하여 붙여넣습니다.
BMAD와 하네스 파일이 모두 포함되어 있습니다.

### 2단계: BMAD 업데이트

프로젝트 루트에서 실행합니다. 최신 버전일 경우 업데이트가 필요 없습니다.

```bash
cd your-project
npx bmad-method install
```

### 3단계: BMAD 기획/설계 (Claude Code 대화형)

하네스 파일은 아직 템플릿 상태입니다. 먼저 BMAD로 기획/설계를 완료해야 합니다.
기획이 끝나야 기술 스택, 아키텍처 레이어, 빌드 명령이 확정되고,
그래야 하네스 파일을 프로젝트에 맞게 수정할 수 있습니다.

```bash
claude
```

Claude Code 대화형 세션에서 BMAD 워크플로우를 실행합니다:

```
bmad-help
→ Analysis (선택): bmad-brainstorming, bmad-product-brief
→ Planning (필수): bmad-create-prd → PRD.md 생성
→ Solutioning (필수): bmad-create-architecture → architecture.md 생성
→ bmad-create-epics-and-stories → epics/stories 생성
→ bmad-check-implementation-readiness → 정합성 확인
```

완료 후 아래 산출물이 존재해야 합니다:
- `_bmad-output/planning-artifacts/PRD.md`
- `_bmad-output/planning-artifacts/architecture.md`
- `_bmad-output/planning-artifacts/epics/` (story 파일들)

### 4단계: 프로젝트 초기화 + 하네스 커스터마이징

BMAD 기획이 끝난 후, **새 Claude Code 세션**에서 아래 프롬프트를 실행합니다.
이 프롬프트 하나로 프로젝트 scaffolding부터 하네스 설정까지 한 번에 처리됩니다.

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
- docs/agents/architecture-rules.md → architecture.md의 레이어 구조, 모듈 경계, 의존성 방향 반영
- docs/agents/coding-rules.md → 실제 기술 스택에 맞는 네이밍, 파일 구조, 에러 처리 규칙
- docs/agents/testing-rules.md → 실제 테스트 프레임워크, 실행 명령, 커버리지 기준
- AGENTS.md → Repo map의 소스 코드 경로를 실제 구조에 맞게

## 3단계: Claude Code 환경 업데이트
- CLAUDE.md의 "Build, Test & Quality" 섹션을 실제 명령으로 갱신
- .claude/hooks/run-checks.sh의 대상 확장자를 기술 스택에 맞게 조정

## 4단계: CI/CD (선택)
- .github/workflows/ci.yml 생성
  - trigger: push to main, PR to main
  - steps: lint → typecheck → test → build → npm audit

## 5단계: 검증
- scripts/validate.sh를 실행해서 모든 명령이 정상 동작하는지 확인
```

### 5단계: Epic 실행 (대화형 — 기본 방식)

**새 Claude Code 세션**에서 아래 프롬프트로 Epic을 실행합니다.

```bash
claude --permission-mode acceptEdits
```

```
Epic 1의 story를 순서대로 처리해줘.

진행 방법:
1. _bmad-output/planning-artifacts/epics/epic-1/ 아래 story 파일을 번호순으로 읽기
2. state/epic-1-progress.json이 있으면 이미 처리된 story는 건너뛰기
3. 각 story마다:
   a. story 브랜치 생성: git checkout -b story/<story-이름>
   b. codex exec --full-auto "프롬프트" 로 구현 (프롬프트에 AGENTS.md 규칙, story 내용, architecture 참조 포함)
   c. scripts/validate.sh 실행
   d. 실패 시 → codex exec로 에러 내용 전달하며 수정 지시 → 재검증
   e. 통과 시 → 코드 리뷰 (REVIEW.md 기준으로 diff 확인, 변경 파일 읽기, 아키텍처 경계 검증)
   f. REJECTED → 리뷰 사유를 codex exec에 전달하여 수정 → 재리뷰
   g. APPROVED → main에 merge
   h. 3회 실패 시 skip
4. 진행 상태를 state/epic-1-progress.json에 저장 (세션 중단 시 이어서 가능)
5. 리뷰 결과를 reviews/epic-1/에 저장
```

> **세션이 끊긴 경우**: 같은 프롬프트를 다시 실행하면 state 파일을 읽고 이어서 처리합니다.

### 6단계: 실패한 Story 수동 처리

```bash
claude
```

```
state/epic-1-progress.json의 failed story 목록을 확인하고,
reviews/epic-1/ 아래 리뷰 결과를 읽어서 문제를 파악한 후 수정해줘.
```

---

## 무인 배치 실행 (대안)

대화형 세션이 아닌 완전 무인 자동화가 필요할 때 (예: 밤새 돌리기):

```bash
# Epic 1 무인 실행
./scripts/run-epic.sh 1

# Timeout 커스터마이징
CODEX_TIMEOUT=7200 ./scripts/run-epic.sh 1

# 상태 확인
./scripts/status.sh
```

> **주의**: 무인 배치 모드는 Hooks, Sub-agent, Memory, 지능적 리뷰 등
> harness 기능이 제한됩니다. 기본 방식은 대화형을 권장합니다.

| 비교 | 대화형 (기본) | 무인 배치 (fallback) |
|---|---|---|
| Hooks (위험 명령 차단, 자동 검증) | 동작 | 제한적 |
| Sub-agent 위임 | 가능 | 불가 |
| Memory 누적 | 누적됨 | 안 됨 |
| 리뷰 방식 | 파일 직접 읽기 + 도구 사용 | 텍스트 매칭 |
| REJECTED 시 수정 | Codex에 지능적 재지시 | 단순 재시도 또는 실패 |
| 실시간 가시성 | 전체 과정 보임 | tee로 로그 출력 |
| 무인 실행 | Ctrl+C 전까지 | 완전 무인 |

---

## 파일 구조

```
├── CLAUDE.md                          Claude Code 역할별 지침 (오케스트레이터)
├── AGENTS.md                          저장소 공식 운영 규칙 (Codex + Claude 공용)
├── REVIEW.md                          코드 리뷰 기준 (APPROVED/REJECTED 판정)
├── .gitignore                         추적 제외 파일
│
├── .claude/
│   ├── settings.json                  Hook 설정 (위험 명령 차단, 편집 후 자동 검증)
│   ├── hooks/
│   │   ├── block-rm.sh                PreToolUse: rm -rf 등 위험 명령 차단
│   │   └── run-checks.sh             PostToolUse: 편집 후 자동 lint + typecheck
│   └── skills/
│       ├── bmad-help/                 BMAD 스킬 (수정 금지)
│       ├── bmad-create-prd/
│       └── ...
│
├── docs/
│   ├── agents/
│   │   ├── architecture-rules.md      아키텍처 경계 규칙
│   │   ├── coding-rules.md            코드 작성 규칙
│   │   ├── testing-rules.md           테스트 규칙
│   │   └── workflow-rules.md          도구별 역할 분담 + 작업 흐름
│   └── decisions/                     ADR (아키텍처 결정 기록)
│
├── templates/
│   ├── execplan.md                    ExecPlan 템플릿 (복잡한 작업용)
│   └── adr.md                         ADR 템플릿
│
├── scripts/
│   ├── run-epic.sh                    무인 배치 실행 (fallback용)
│   ├── validate.sh                    공통 검증 (빌드/린트/테스트)
│   ├── smoke.sh                       스모크 테스트
│   └── status.sh                      진행 상태 대시보드
│
├── _bmad-output/
│   ├── planning-artifacts/            PRD, architecture, epics/stories
│   └── implementation-artifacts/      sprint-status
│
├── state/                             작업 진행 상태 (재시작 지원)
├── plans/                             ExecPlan 저장 (복잡한 작업만)
└── reviews/                           리뷰 결과 + 로그 저장
```

---

## 운영 요약

| 단계 | 도구 | 산출물 |
|---|---|---|
| 기획/설계 | Claude Code + BMAD | PRD, Architecture, Epics/Stories |
| 프로젝트 초기화 | Claude Code (통합 프롬프트) | 소스 코드 scaffolding, 린팅/테스트 설정 |
| 하네스 커스터마이징 | Claude Code (통합 프롬프트) | 프로젝트 맞춤 규칙/스크립트/Hooks |
| Epic 구현 | Claude Code (오케스트레이터) → Codex (구현) | 코드 + 커밋 + 리뷰 결과 |
| 실패 보완 | Claude Code (수동) | 수정된 코드 + 재리뷰 |

| 규칙 | 설명 |
|---|---|
| 대화형이 기본 | Claude Code 세션에서 전체 파이프라인 실행 |
| Epic 단위로 실행 | 전체 story를 한 번에 돌리지 않음 |
| 재시작 가능 | state/ 파일 기반, 같은 프롬프트로 이어서 처리 |
| 실패 격리 | 하나 실패해도 나머지 진행 |
| 모든 단계에 검증 | validate.sh + REVIEW.md 기준 코드 리뷰 |

---

## 선택적 확장

프로젝트 성장에 따라 필요할 때 추가하세요.

### Sub-agent: code-reviewer

대화형 세션에서 `@code-reviewer`로 리뷰를 위임할 수 있습니다.
`.claude/agents/code-reviewer.md`를 생성하세요:

```markdown
---
name: code-reviewer
description: Review code changes for architecture violations, missing tests, security issues. Read-only, does not modify files.
tools:
  - Read
  - Grep
  - Glob
  - Bash
disallowedTools:
  - Edit
  - Write
maxTurns: 15
---

You are a code reviewer. Review the git diff of the current branch against main.

Check against:
1. docs/agents/architecture-rules.md (layer boundaries)
2. docs/agents/testing-rules.md (test coverage)
3. docs/agents/coding-rules.md (naming, structure)
4. REVIEW.md (security, scope, quality)

Report findings as:
- CRITICAL: Must fix before merge
- WARNING: Should fix
- SUGGESTION: Optional improvement

End with: APPROVED / NEEDS_CHANGES / CRITICAL_ISSUES
```

사용: `@code-reviewer src/api/ 변경분을 리뷰해줘`

### Sub-agent: db-reader

DB가 있는 프로젝트에서 읽기 전용 쿼리 에이전트로 사용합니다.
`.claude/agents/db-reader.md`를 생성하세요:

```markdown
---
name: db-reader
description: Execute read-only database queries for debugging and data inspection.
tools:
  - Bash
model: claude-haiku-4-5
maxTurns: 10
---

You are a read-only database query agent.
ONLY execute SELECT queries. Never execute INSERT, UPDATE, DELETE, DROP, or any write operation.
```

### .worktreeinclude

`claude --worktree` 사용 시 gitignored 파일을 worktree로 복사하는 목록입니다.
프로젝트 루트에 `.worktreeinclude`를 생성하세요:

```
.env
.env.local
.env.development.local
config/local.yaml
```

### CI/CD 파이프라인

4단계 통합 프롬프트에서 "4단계: CI/CD" 섹션을 선택하면 자동 생성됩니다.
수동으로 생성하려면 `.github/workflows/ci.yml`을 작성하세요:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  quality-gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run test -- --coverage
      - run: npm run build
      - run: npm audit --audit-level=high
        continue-on-error: true
```
