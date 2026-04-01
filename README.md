# Harness Engineering Starter Kit
# BMAD + Claude Code + Codex 통합 운영 구조

## 사전 조건

- Claude Code, Codex CLI 설치 및 로그인 완료
- Git 설정 완료
- jq 설치 완료 (`brew install jq` 또는 `sudo apt-get install -y jq`)
- Node.js 20+

---

## 셋업 순서

### 1. BMAD 설치

프로젝트 루트에서 실행합니다.

```bash
npx bmad-method install
```

설치 후 `_bmad/`와 `_bmad-output/` 폴더가 생성됩니다.

### 2. 하네스 키트 복사

이 키트의 전체 내용을 프로젝트 루트에 복사합니다.
BMAD가 생성한 `_bmad/`, `_bmad-output/`은 덮어쓰지 않습니다.

```bash
cp -rn harness-starter-kit/. /your-project/
chmod +x /your-project/scripts/*.sh /your-project/.harness/hooks/*.sh
```

> `cp -rn`은 이미 존재하는 파일을 덮어쓰지 않습니다. BMAD 파일이 보존됩니다.

### 3. BMAD 기획/설계 실행 (Claude Code)

하네스 파일은 아직 템플릿 상태입니다. 먼저 BMAD로 기획/설계를 완료해야 합니다.
기획이 끝나야 기술 스택, 아키텍처 레이어, 빌드 명령이 확정되고,
그래야 하네스 파일을 프로젝트에 맞게 수정할 수 있습니다.

```bash
claude
# → bmad-help
# → Analysis (선택): bmad-brainstorming, bmad-product-brief
# → Planning (필수): bmad-create-prd → PRD.md 생성
# → Solutioning (필수): bmad-create-architecture → architecture.md 생성
# → bmad-create-epics-and-stories → epics/stories 생성
# → bmad-check-implementation-readiness → 정합성 확인
```

완료 후 아래 산출물이 존재해야 합니다:
- `_bmad-output/planning-artifacts/PRD.md`
- `_bmad-output/planning-artifacts/architecture.md`
- `_bmad-output/planning-artifacts/epics/` (story 파일들)

### 4. 하네스 파일을 프로젝트에 맞게 수정

BMAD 기획/설계가 끝난 후, Claude Code에 아래 프롬프트를 입력하면
하네스 파일이 프로젝트에 맞게 한 번에 수정됩니다.

```
아래 파일들을 이 프로젝트의 BMAD 산출물에 맞게 수정해줘.

수정 대상:
1. scripts/validate.sh
   - architecture.md에 명시된 기술 스택의 실제 빌드, 타입체크, 린트, 테스트 명령으로 교체
   - 해당 기술 스택에 맞는 의존성 설치 명령 사용

2. scripts/smoke.sh
   - PRD의 핵심 사용자 플로우를 기반으로 스모크 테스트 대상 정의

3. docs/agents/architecture-rules.md
   - architecture.md의 레이어 구조, 모듈 경계, 의존성 방향을 반영
   - 금지 패턴을 이 프로젝트의 구조에 맞게 구체화

4. docs/agents/coding-rules.md
   - architecture.md의 기술 스택에 맞는 네이밍, 파일 구조, 에러 처리 규칙으로 수정

5. docs/agents/testing-rules.md
   - 실제 사용하는 테스트 프레임워크, 실행 명령, 커버리지 도구로 수정

6. .harness/config.json
   - project 섹션에 프로젝트 이름, 설명, 기술 스택 입력

7. AGENTS.md
   - Repo map의 소스 코드 경로를 실제 프로젝트 구조에 맞게 수정

참고할 파일:
- _bmad-output/planning-artifacts/PRD.md
- _bmad-output/planning-artifacts/architecture.md

수정 후 scripts/validate.sh를 실행해서 명령이 정상 동작하는지 확인해줘.
```

### 5. Epic 단위 자동 실행

```bash
# Epic 1 실행 (Codex 구현 → Claude 리뷰 자동 파이프라인)
./scripts/run-epic.sh 1

# 진행 상태 확인
./scripts/status.sh

# 중간에 멈추거나 rate limit에 걸려도 같은 명령으로 이어서 처리
./scripts/run-epic.sh 1

# 다음 Epic
./scripts/run-epic.sh 2
```

### 6. 실패한 Story 처리

```bash
# 실패/스킵된 story 확인
jq '.failed, .skipped' state/epic-1-progress.json

# 리뷰 결과 확인
cat reviews/epic-1/story-이름-review.md

# Codex 로그 확인 (실패 원인 분석)
cat reviews/epic-1/logs/story-이름-codex.log

# 수동 수정 후 상태 파일 초기화하여 재처리 가능
# (해당 story만 재처리하려면 state 파일에서 해당 항목 제거)
```

---

## 파일 구조

```
├── AGENTS.md                          저장소 공식 운영 규칙 (Codex+Claude 공용)
├── CLAUDE.md                          Claude Code 역할별 지침 (기획+리뷰)
├── REVIEW.md                          코드 리뷰 기준 (APPROVED/REJECTED 판정)
├── .gitignore-harness                 .gitignore에 추가할 내용
│
├── .claude/rules/
│   ├── review.md                      Claude 리뷰 모드 자동 규칙
│   └── implementation.md              Claude BMAD 세션 규칙
│
├── .harness/
│   ├── config.json                    하네스 설정 (timeout, retry, 경로)
│   ├── templates/
│   │   ├── execplan.md                ExecPlan 템플릿 (복잡한 작업용)
│   │   └── adr.md                     ADR 템플릿 (기술 결정 기록)
│   └── hooks/
│       └── pre-merge.sh               머지 전 자동 검증
│
├── docs/agents/
│   ├── architecture-rules.md          아키텍처 경계 규칙
│   ├── coding-rules.md                코드 작성 규칙
│   ├── testing-rules.md               테스트 규칙
│   └── workflow-rules.md              도구별 역할 분담 + 작업 흐름
├── docs/decisions/                    ADR 저장
│
├── scripts/
│   ├── run-epic.sh                    Epic 단위 자동 실행 스크립트
│   ├── validate.sh                    공통 검증 스크립트
│   ├── smoke.sh                       스모크 테스트
│   └── status.sh                      전체 진행 상태 대시보드
│
├── state/                             작업 진행 상태 (재시작 지원)
├── plans/                             ExecPlan 저장 (복잡한 작업만)
└── reviews/                           리뷰 결과 + 로그 저장
```

## 운영 요약

| 단계 | 도구 | 산출물 |
|---|---|---|
| 기획/설계 | Claude Code + BMAD | PRD, Architecture, Epics/Stories |
| 하네스 수정 | Claude Code | 프로젝트 맞춤 규칙/스크립트 |
| 구현 | Codex (run-epic.sh) | 코드 + 커밋 |
| 리뷰/검증 | Claude Code (run-epic.sh) | APPROVED 또는 REJECTED |

| 규칙 | 설명 |
|---|---|
| Epic 단위로 실행 | 전체 story를 한 번에 돌리지 않음 |
| 재시작 가능 | 같은 명령 다시 실행하면 이어서 처리 |
| 실패 격리 | 하나 실패해도 나머지 진행 |
| Rate limit 대응 | 감지 시 자동 대기 후 재시도 |
| 모든 단계에 timeout | Codex hang 방지 |
| Story 순차 + 머지 | 의존성 보장 |
