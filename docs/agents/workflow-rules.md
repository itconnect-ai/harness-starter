# docs/agents/workflow-rules.md
#
# 이 프로젝트의 작업 흐름 규칙입니다.
# BMAD + Harness Engineering 통합 워크플로우를 정의합니다.

## 도구별 역할 분담

| Phase | 도구 | 역할 | BMAD 스킬 |
|---|---|---|---|
| 기획/설계 | Claude Code | PRD, Architecture, Epics 생성 | bmad-create-prd, bmad-create-architecture, bmad-create-epics-and-stories |
| Phase A: 구현 | Codex Desktop | Story 생성 + 구현 (Epic 단위) | bmad-create-story, bmad-dev-story |
| Phase B: 품질 보장 | Claude Code | 코드 리뷰 + 수정 + 테스트 보강 (Epic 단위) | bmad-code-review |

## Phase A: Codex Desktop 흐름 (Epic 단위)

각 story마다 순서대로:
1. `bmad-create-story` 스킬로 story 파일 생성 (풀 컨텍스트 엔진)
2. `bmad-dev-story` 스킬로 구현 (TDD: red-green-refactor)
3. `./scripts/validate.sh` 실행
4. 통과 시 **commit + push 필수**: `git add -A && git commit -m "feat(story-이름): 설명" && git push`
5. sprint-status.yaml 업데이트 (스킬이 자동 처리)
6. 실패 시 수정 후 재검증, 3회 실패 시 skip
7. 다음 story로 진행

**중요:** validate 통과한 story는 반드시 commit과 push를 완료해야 다음 story로 진행할 수 있다. push 없이 다음 story 진행은 금지.

Codex Desktop 모델 설정:
- 모델: chatgpt-5.4
- 사고수준: xhigh (`-c model_reasoning_effort=xhigh`)

## Phase B: Claude Code 흐름 (Epic 단위)

Epic 전체를 대상으로:
1. sprint-status.yaml에서 완료된 story 확인
2. 각 story 브랜치의 코드를 `bmad-code-review` 스킬로 리뷰
3. REJECTED 항목 직접 수정 (Edit/Write, Hooks 자동 작동)
4. 누락 테스트 보강
5. `./scripts/validate.sh` + `./scripts/smoke.sh` 최종 검증
6. 모든 story APPROVED 후 main에 merge
7. sprint-status.yaml 업데이트 (review → done)

## Phase C: Claude Code 회고 + Harness 강화 (Epic 완료 후)

Phase B 완료 후 실행:
1. `reviews/epic-N/` 아래 리뷰 결과 (*.md + logs/*-validate.log + *-codex.log) 분석
2. `state/epic-N-progress.json`에서 failed/skipped story 확인
3. 반복된 REJECTED 패턴과 validate 실패 패턴을 식별
4. `feedback/incidents/`에 incident YAML 생성 (incident-template.yaml 참고)
5. 각 incident에 대해 재현 테스트를 `tests/regression/`에 작성 (다음 Epic에서 자동 실행)
6. `state/learning-loop.json` 업데이트 (패턴별 발생 횟수)
7. 승격 정책에 따라 조치:
   - 1회: 기록만
   - 2회: `docs/agents/feedback-rules.md`에 활성 규칙 추가
   - 3회+ 또는 치명적 (기계적으로 판별 가능한 경우만): `scripts/validate.sh`에 **blocking check**로 추가 (warning이 아닌 exit 1)
   - 아키텍처 성격: `docs/agents/architecture-rules.md` 또는 `docs/decisions/`에 ADR
8. **`.claude/hooks/`는 Claude Phase B에만 적용됨** — 공통 강제는 `scripts/validate.sh` 또는 CI 우선
9. **완료 기준**: harness 파일(validate.sh, rules, hooks)을 수정했으면 반드시 `bash -n scripts/validate.sh && ./scripts/validate.sh` 재실행하여 harness 자체가 깨지지 않았는지 확인
10. 검증 통과 후 커밋: `chore(harness): Epic N 회고 반영`

feedback-rules.md 운영 규칙:
- 최대 10개 active rule만 유지
- 각 규칙은 source incident id를 가짐
- 최근 2 Epic 동안 재발 없으면 retired로 이동
- 기계적 판별 가능 패턴이 validate.sh로 승격되면 여기서 제거

## Quick Flow (가벼운 작업)

BMAD 풀코스가 필요 없는 간단한 작업:
- Claude Code에서 `bmad-quick-dev` 스킬 사용
- 또는 `bmad-agent-quick-flow-solo-dev` (Barry) 호출
- spec → implement → review → present를 한 세션에서 처리

## 브랜치 규칙

- story별 브랜치: `story/<story-이름>`
- main은 항상 검증 통과 상태 유지
- Phase A에서는 story 브랜치에 커밋
- Phase B에서 APPROVED 후 main에 merge

## 실패 처리

- Phase A validate 실패: Codex가 수정 후 재시도 (3회까지)
- Phase B 리뷰 거부: Claude Code가 직접 수정
- 3회 실패: skip 처리하고 수동 확인 대상으로 표시
