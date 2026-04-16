# CLAUDE.md

#

# Claude Code 전용 지침 파일입니다.

# 저장소 공식 규칙은 AGENTS.md에 있습니다.

#

# 이 프로젝트에서 Claude Code의 역할:

# 1. BMAD 기획/설계 실행 (PM, Architect agent 대화)

# 2. Epic 리뷰 + 수정 + 테스트 보강 (Phase B)

#

# 구현은 Codex Desktop이 담당합니다 (Phase A).

## 기본 동작

- 저장소 규칙은 항상 `AGENTS.md`를 우선 참고
- 도구 사용 원칙은 `AGENTS.md`를 따른다. CLI로 가능한 작업은 CLI를 우선 사용
- 상세 규칙은 `docs/agents/` 아래 문서 참조
- BMAD 산출물은 `_bmad-output/` 아래에서 참조
- `.claude/skills/bmad-*/`와 `.agents/skills/bmad-*/` 내용을 수정하지 않음

## 역할 1: BMAD 기획/설계

BMAD agent를 실행할 때의 규칙:

- 각 워크플로우는 새 세션에서 실행
- 산출물은 `_bmad-output/planning-artifacts/`에 저장
- 기획 단계에서 구현 코드를 작성하지 않음
- bmad-help으로 다음 단계 안내 받기

## 역할 2: Epic 리뷰 + 수정 (Phase B)

Codex Desktop이 구현한 Epic 전체를 리뷰하고 수정할 때의 규칙:

### 리뷰

- `bmad-code-review` 스킬로 3층 병렬 리뷰 실행
- `REVIEW.md`의 리뷰 기준을 따름
- `docs/agents/architecture-rules.md`의 경계 규칙 확인
- 변경된 파일을 직접 Read/Grep으로 확인 (텍스트 diff만 보지 않음)

### 오류 수정

- REJECTED 항목을 직접 수정 (Edit/Write)
- 수정 시 Hooks가 자동으로 lint+typecheck 실행
- 수정 후 `./scripts/validate.sh`로 재검증

### 테스트 보강

- 누락된 테스트 케이스 작성
- 엣지 케이스 커버리지 추가
- `./scripts/validate.sh` + `./scripts/smoke.sh`로 최종 검증

### 완료

- 모든 story APPROVED 후 **develop** 브랜치에 merge (회사 표준: develop → CI → main → 자동 배포)
- sprint-status.yaml 업데이트 (review → done)

## 역할 3: 가벼운 작업 (Quick Flow)

BMAD 풀코스 없이 간단한 작업을 할 때:

- `bmad-quick-dev` 스킬 사용 (spec → implement → review → present)
- 또는 `bmad-agent-quick-flow-solo-dev` (Barry) 호출

## Build, Test & Quality

# ⚠️ 기획 완료 후 기술 스택에 맞게 아래 명령을 수정하세요.

# 통합 초기화 프롬프트가 이 섹션을 자동으로 채웁니다.

- Dev server: `npm run dev`
- Build: `npm run build`
- Test: `npm run test`
- Lint: `npm run lint`
- Type check: `npm run typecheck`
- Story 검증: bash/WSL/macOS/Linux는 `./scripts/validate-quick.sh`, Windows PowerShell은 `./scripts/validate-quick.ps1`
- Epic 검증: bash/WSL/macOS/Linux는 `./scripts/validate.sh`, Windows PowerShell은 `./scripts/validate.ps1`
- 실패 재개: bash/WSL/macOS/Linux는 `./scripts/validate.sh --from=실패단계`, Windows PowerShell은 `./scripts/validate.ps1 --from=실패단계`
- 검증 로그: `state/validate/latest/*.log` (단계별 로그)
- 출력 모드: 기본 summary, `VALIDATE_OUTPUT_MODE=verbose`로 전체 출력
- 실패 디버깅: summary 출력의 로그 경로를 읽어서 원인 파악

## 참조 파일

@AGENTS.md
@REVIEW.md
@docs/agents/architecture-rules.md
@docs/agents/testing-rules.md
@docs/agents/coding-rules.md
@docs/agents/workflow-rules.md
@docs/agents/security-rules.md
@docs/agents/performance-rules.md
@docs/agents/deploy-rules.md
@docs/agents/backup-rules.md
@docs/agents/feedback-rules.md
@docs/agents/seo-rules.md
