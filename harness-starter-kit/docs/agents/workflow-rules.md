# docs/agents/workflow-rules.md
#
# 이 프로젝트의 작업 흐름 규칙입니다.
# BMAD + Harness Engineering 통합 워크플로우를 정의합니다.

## 도구별 역할 분담

| 역할 | 도구 | 설명 |
|---|---|---|
| 기획/설계 | Claude Code | BMAD agent 실행, PRD/Architecture/Epic/Story 생성 |
| 구현 | Codex | Story 기반 코드 구현 |
| 리뷰/검증 | Claude Code | 코드 리뷰, 테스트 보강, 품질 판정 |

## Story 구현 흐름 (Codex가 따라야 할 순서)

1. AGENTS.md의 "Start here" 루틴 실행
2. 대상 story 파일 읽기
3. 관련 architecture 확인
4. 구현
5. `./scripts/validate.sh` 실행
6. 통과 시 커밋: `feat(story-이름): 설명`
7. 실패 시 수정 후 재검증

## 코드 리뷰 흐름 (Claude Code가 따라야 할 순서)

1. 브랜치의 main 대비 diff 확인
2. REVIEW.md 기준으로 리뷰
3. docs/agents/architecture-rules.md 대비 경계 확인
4. 판정: APPROVED 또는 REJECTED + 이유

## 세션 규칙

- 각 story는 독립 세션에서 처리
- 하나의 세션에서 여러 story를 처리하지 않음
- 세션 종료 시 state/ 파일 업데이트

## 브랜치 규칙

- story별 브랜치: `story/<story-이름>`
- main은 항상 검증 통과 상태 유지
- 머지 전 validate.sh 필수 통과

## 실패 처리

- validate 실패: 수정 후 재시도
- 리뷰 거부: 지적 사항 수정 후 재리뷰
- 3회 실패: skip 처리하고 수동 확인 대상으로 표시
