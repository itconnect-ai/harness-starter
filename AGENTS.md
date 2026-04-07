# AGENTS.md
#
# 이 파일은 Codex와 Claude Code 모두가 세션 시작 시 읽는 저장소 공식 운영 규칙입니다.
# Codex Desktop은 이 파일을 자동 로드합니다.
# Claude Code는 CLAUDE.md에서 이 파일을 @import합니다.
# 60줄 안팎으로 유지하고, 상세 규칙은 docs/agents/로 분리합니다.

## 역할 분담

| Phase | 도구 | 역할 | BMAD 스킬 |
|---|---|---|---|
| Phase A | Codex Desktop | story 생성 + 구현 (Epic 단위) | bmad-create-story, bmad-dev-story |
| Phase B | Claude Code | 코드 리뷰 + 수정 + 테스트 보강 (Epic 단위) | bmad-code-review |

## Phase A: Codex Desktop 시작 루틴

1. 이 파일(AGENTS.md)의 규칙 확인
2. `_bmad-output/planning-artifacts/architecture.md` 읽기
3. `_bmad-output/implementation-artifacts/sprint-status.yaml` 확인
4. `docs/agents/` 아래 관련 규칙 참고
   - **필수**: `docs/agents/feedback-rules.md` (과거 반복 실수 패턴) 반드시 읽기
5. 대상 Epic의 story를 순서대로 처리:
   - `bmad-create-story` 스킬로 story 파일 생성
   - `bmad-dev-story` 스킬로 구현 (TDD: red-green-refactor)
   - `./scripts/validate.sh` 실행하여 검증
   - 통과 시 **commit + push 필수**: `git add -A && git commit -m "feat(story-name): 설명" && git push`
   - validate 실패 시 수정 후 재검증, 3회 실패 시 skip
6. Codex Desktop 모델 권장: chatgpt-5.4, reasoning: xhigh

## Phase B: Claude Code 시작 루틴

1. `CLAUDE.md`의 지침 확인 (이 파일은 @import됨)
2. `_bmad-output/implementation-artifacts/sprint-status.yaml` 확인
3. 완료된 story 브랜치를 `bmad-code-review` 스킬로 리뷰
4. REJECTED 항목 직접 수정 + 테스트 보강
5. `./scripts/validate.sh` + `./scripts/smoke.sh` 최종 검증

## Repo map

| 경로 | 역할 |
|---|---|
| `_bmad-output/planning-artifacts/` | PRD, architecture, epics, stories (공식 제품 문서) |
| `_bmad-output/implementation-artifacts/` | sprint-status, story 파일, 구현 산출물 |
| `.agents/skills/` | Codex용 BMAD 스킬 (create-story, dev-story 등) |
| `.claude/skills/` | Claude Code용 BMAD 스킬 (code-review 등) |
| `docs/agents/` | 에이전트 운영 규칙 (architecture, coding, testing, security, performance, deploy, workflow) |
| `docs/decisions/` | 아키텍처 결정 기록 (ADR) |
| `scripts/` | 검증, 빌드, 스모크 테스트 스크립트 |
| `feedback/` | 실수 기록(incidents) + 템플릿 |
| `state/` | 작업 진행 상태 파일 + learning-loop.json |
| `reviews/` | 코드 리뷰 결과 저장 |
| `src/` or `apps/` | 소스 코드 |
| `tests/` | 테스트 코드 |

## Tooling rules

- CLI로 수행 가능한 작업은 기본적으로 CLI를 우선 사용
- 소스 제어와 PR은 `git`, `gh`, 검증과 반복 작업은 저장소 `scripts/*`, JavaScript/TypeScript 패키지와 테스트 실행은 `npm`, `npx`, `node`, Python 작업은 `python`, `pip`, `uv`, HTTP 확인은 `curl` 또는 `http`, 브라우저/E2E는 `npx playwright`, 컨테이너 작업은 `docker`, `docker compose`, Kubernetes 작업은 `kubectl`, `helm`을 우선 사용
- 동일 작업을 내장 도구와 CLI 둘 다로 수행할 수 있으면 CLI를 선택
- 프로젝트에 공식 래퍼 스크립트나 표준 명령이 있으면 ad-hoc 명령보다 그것을 우선 사용
- CLI가 설치되어 있지 않거나 인증, 권한, 플랫폼 제약으로 실행할 수 없을 때만 대체 도구를 사용

## Validation (완료 기준)

- 작업 완료 선언 전 반드시 `./scripts/validate.sh` 실행
- critical path가 있으면 `./scripts/smoke.sh` 추가 실행
- 검증이 실패하면 완료로 간주하지 않음

## Coding rules (핵심만, 상세는 docs/agents/coding-rules.md)

- 아키텍처 경계를 준수 (docs/agents/architecture-rules.md 참고)
- 변경된 동작에 대해 테스트 추가 또는 업데이트
- 새 패턴 도입 시 docs/decisions/에 이유 기록
- 의존성 추가 시 정당한 이유 필요

## Change rules

- 변경 범위를 현재 story로 제한
- story와 관련 없는 리팩터링 금지
- 관련 문서를 같은 변경에서 업데이트
- 커밋 메시지 형식: `type(scope): description`
- type: feat, fix, refactor, test, docs, chore
- Phase A에서는 validate 통과 후 **commit + push 필수** (push 없이 다음 story 진행 금지)
