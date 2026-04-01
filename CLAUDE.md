# CLAUDE.md
#
# Claude Code 전용 지침 파일입니다.
# 저장소 공식 규칙은 AGENTS.md에 있습니다. 이 파일은 Claude Code의 역할별 동작을 정의합니다.
#
# 이 프로젝트에서 Claude Code의 주요 역할:
#   1. BMAD 기획/설계 실행 (PM, Architect agent 대화)
#   2. Codex가 구현한 코드의 리뷰/검증/테스트
#
# 구현은 Codex가 담당합니다. Claude Code는 구현하지 않습니다.

## 기본 동작

- 저장소 규칙은 항상 `AGENTS.md`를 우선 참고
- 상세 규칙은 `docs/agents/` 아래 문서 참조
- BMAD 산출물은 `_bmad-output/` 아래에서 참조

## 역할 1: BMAD 기획/설계

BMAD agent를 실행할 때의 규칙:
- 각 워크플로우는 새 세션에서 실행
- 산출물은 `_bmad-output/planning-artifacts/`에 저장
- 기획 단계에서 구현 코드를 작성하지 않음
- bmad-help으로 다음 단계 안내 받기

## 역할 2: 코드 리뷰

Codex가 구현한 변경분을 리뷰할 때의 규칙:
- `REVIEW.md`의 리뷰 기준을 따름
- `docs/agents/architecture-rules.md`의 경계 규칙 확인
- 변경된 동작에 테스트가 있는지 확인
- 보안 이슈(입력 검증, 인증, 권한) 확인
- 엣지 케이스와 에러 처리 확인
- 문제가 없으면 정확히 `APPROVED`로 응답
- 문제가 있으면 항목별로 명확하게 나열

## 역할 3: 테스트 보강

리뷰 후 테스트가 부족하면:
- 누락된 테스트 케이스 작성
- 엣지 케이스 커버리지 추가
- `./scripts/validate.sh` 실행하여 확인

## 참조 파일

@AGENTS.md
@REVIEW.md
@docs/agents/architecture-rules.md
@docs/agents/testing-rules.md
