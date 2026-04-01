# CLAUDE.md
#
# Claude Code 전용 지침 파일입니다.
# 저장소 공식 규칙은 AGENTS.md에 있습니다.
#
# 이 프로젝트에서 Claude Code의 역할:
#   1. BMAD 기획/설계 실행 (PM, Architect agent 대화)
#   2. Epic 오케스트레이션 (Codex 호출 → 검증 → 리뷰 → 머지)
#   3. Codex 구현 코드의 리뷰/검증/테스트 보강

## 기본 동작

- 저장소 규칙은 항상 `AGENTS.md`를 우선 참고
- 상세 규칙은 `docs/agents/` 아래 문서 참조
- BMAD 산출물은 `_bmad-output/` 아래에서 참조
- `.claude/skills/bmad-*/` 내용을 수정하지 않음

## 역할 1: BMAD 기획/설계

BMAD agent를 실행할 때의 규칙:
- 각 워크플로우는 새 세션에서 실행
- 산출물은 `_bmad-output/planning-artifacts/`에 저장
- 기획 단계에서 구현 코드를 작성하지 않음
- bmad-help으로 다음 단계 안내 받기

## 역할 2: Epic 오케스트레이션

대화형 세션에서 Epic의 story를 순서대로 처리할 때의 규칙:
- story별 브랜치 생성: `story/<story-이름>`
- Codex 호출: `codex exec --full-auto "프롬프트"` (Bash tool 사용)
- 구현 후 `./scripts/validate.sh` 실행으로 검증
- 검증 통과 시 직접 코드 리뷰 (REVIEW.md 기준)
- REJECTED 시 리뷰 사유를 포함하여 Codex에 수정 지시
- APPROVED 시 main에 merge
- 진행 상태를 `state/` 파일에 기록
- 3회 실패 시 skip하고 다음 story로 진행

## 역할 3: 코드 리뷰

Codex가 구현한 변경분을 리뷰할 때의 규칙:
- `REVIEW.md`의 리뷰 기준을 따름
- `docs/agents/architecture-rules.md`의 경계 규칙 확인
- 변경된 파일을 직접 Read/Grep으로 확인 (텍스트 diff만 보지 않음)
- 변경된 동작에 테스트가 있는지 확인
- 보안 이슈(입력 검증, 인증, 권한) 확인
- 엣지 케이스와 에러 처리 확인
- 문제가 없으면 정확히 `APPROVED`로 응답
- 문제가 있으면 항목별로 명확하게 나열

## 역할 4: 테스트 보강

리뷰 후 테스트가 부족하면:
- 누락된 테스트 케이스 작성
- 엣지 케이스 커버리지 추가
- `./scripts/validate.sh` 실행하여 확인

## Build, Test & Quality
# ⚠️ 기획 완료 후 기술 스택에 맞게 아래 명령을 수정하세요.
# 통합 초기화 프롬프트가 이 섹션을 자동으로 채웁니다.

- Dev server: `npm run dev`
- Build: `npm run build`
- Test: `npm run test`
- Lint: `npm run lint`
- Type check: `npm run typecheck`
- 작업 완료 전 반드시: `npm run lint && npm run typecheck`

## 참조 파일

@AGENTS.md
@REVIEW.md
@docs/agents/architecture-rules.md
@docs/agents/testing-rules.md
@docs/agents/coding-rules.md
@docs/agents/workflow-rules.md
