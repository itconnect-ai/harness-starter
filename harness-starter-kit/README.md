# Harness Engineering Starter Kit
# BMAD + Claude Code + Codex 통합 운영 구조
#
# 이 키트를 프로젝트 루트에 복사하세요.
# ⚠️ 기존 파일과 겹치지 않는지 확인 후 복사하세요.

## Quick Start

### 1. 사전 준비

```bash
# Codex CLI 설치 및 로그인
npm i -g @openai/codex
codex  # 로그인

# Claude Code 설치 및 로그인
curl -fsSL https://claude.ai/install.sh | bash
claude  # 로그인

# BMAD 설치 (아직 안 했다면)
npx bmad-method install

# jq 설치 (상태 파일 처리용)
# macOS: brew install jq
# Linux: sudo apt-get install -y jq
```

### 2. 이 키트를 프로젝트에 복사

```bash
# 프로젝트 루트에서
cp AGENTS.md /your-project/
cp CLAUDE.md /your-project/
cp REVIEW.md /your-project/
cp -r docs/ /your-project/
cp -r scripts/ /your-project/
cp -r state/ /your-project/
cp -r .harness/ /your-project/
cp -r .claude/ /your-project/
mkdir -p /your-project/plans /your-project/reviews

# 스크립트 실행 권한
chmod +x /your-project/scripts/*.sh
chmod +x /your-project/.harness/hooks/*.sh
```

### 3. 프로젝트에 맞게 수정

- `AGENTS.md` → 프로젝트 경로, 빌드 명령 확인
- `docs/agents/architecture-rules.md` → 실제 아키텍처에 맞게 수정
- `docs/agents/coding-rules.md` → 기술 스택에 맞게 수정
- `scripts/validate.sh` → 실제 빌드/테스트 명령으로 교체
- `.harness/config.json` → 프로젝트 정보 입력

### 4. BMAD로 기획 (Claude Code)

```bash
claude
# → bmad-help
# → BMAD 워크플로우 실행 (PRD → Architecture → Epics/Stories)
```

### 5. Epic 단위 자동 실행

```bash
# Epic 1 실행 (중간에 끊겨도 재실행하면 이어서 처리)
./scripts/run-epic.sh 1

# 상태 확인
./scripts/status.sh

# Epic 2 실행
./scripts/run-epic.sh 2
```

## 파일 목록

```
├── AGENTS.md                        ← 저장소 공식 운영 규칙 (Codex + Claude 공용)
├── CLAUDE.md                        ← Claude Code 역할별 지침
├── REVIEW.md                        ← 코드 리뷰 기준
├── .claude/
│   └── rules/
│       ├── review.md                ← Claude 리뷰 모드 자동 규칙
│       └── implementation.md        ← Claude BMAD 세션 규칙
├── .harness/
│   ├── config.json                  ← 하네스 설정 (timeout, retry 등)
│   ├── templates/
│   │   ├── execplan.md              ← ExecPlan 템플릿
│   │   └── adr.md                   ← ADR 템플릿
│   └── hooks/
│       └── pre-merge.sh             ← 머지 전 검증 hook
├── docs/
│   └── agents/
│       ├── architecture-rules.md    ← 아키텍처 경계 규칙
│       ├── coding-rules.md          ← 코드 작성 규칙
│       ├── testing-rules.md         ← 테스트 규칙
│       └── workflow-rules.md        ← 작업 흐름 규칙
├── scripts/
│   ├── run-epic.sh                  ← ⭐ Epic 단위 자동 실행 스크립트
│   ├── validate.sh                  ← 공통 검증 스크립트
│   ├── smoke.sh                     ← 스모크 테스트
│   └── status.sh                    ← 진행 상태 대시보드
├── state/
│   ├── README.md                    ← state 폴더 설명
│   └── progress-template.json       ← 상태 파일 템플릿
├── plans/                           ← ExecPlan 저장 (복잡한 작업만)
├── reviews/                         ← 리뷰 결과 저장
└── docs/decisions/                  ← ADR 저장
```

## 운영 규칙 요약

| 규칙 | 설명 |
|---|---|
| Epic 단위로 실행 | 80개 story를 한 번에 돌리지 않음 |
| 재시작 가능 | 같은 명령 다시 실행하면 이어서 처리 |
| 실패 격리 | 하나 실패해도 나머지 진행 |
| Rate limit 대응 | 감지 시 자동 대기 + 재시도 |
| 모든 단계에 timeout | Codex hang 방지 |
| Story 순차 + 머지 | 의존성 보장 |
