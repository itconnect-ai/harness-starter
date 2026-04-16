# state/README.md
#
# 이 폴더는 에이전트의 작업 상태를 추적합니다.
#
# ── Primary Tracking: sprint-status.yaml ──
#
# 스프린트의 공식 상태는 다음 파일에서 관리됩니다:
#   _bmad-output/implementation-artifacts/sprint-status.yaml
#
# 이 파일은 BMAD 스킬(bmad-create-story, bmad-dev-story 등)이 자동으로
# 생성하고 갱신하며, 모든 epic과 story의 상태를 추적합니다.
#
# 사용 예:
#   # 전체 스프린트 상태 확인
#   cat _bmad-output/implementation-artifacts/sprint-status.yaml
#
#   # 특정 epic의 story 상태 확인 (grep으로 필터)
#   grep -A 5 'epic-1' _bmad-output/implementation-artifacts/sprint-status.yaml
#
#   # in-progress인 항목만 보기
#   grep 'status:.*in-progress' _bmad-output/implementation-artifacts/sprint-status.yaml
#
# ── Auxiliary: epic-N-progress.json (run-epic.sh 전용) ──
#
# run-epic.sh CLI 스크립트가 사용하는 보조 상태 파일입니다.
# Codex Desktop이 없을 때 CLI fallback으로 사용합니다.
#
# epic-{N}-progress.json
#   - run-epic.sh가 생성
#   - 각 epic의 story 처리 상태 (completed, failed, skipped)
#   - 스크립트를 재실행하면 이 파일을 읽어서 이어서 처리
#   - 초기화하려면 이 파일을 삭제하고 다시 실행
#
# progress-template.json
#   - 상태 파일의 템플릿 (참고용)
#
# 사용 예:
#   # Epic 1 상태 확인
#   cat state/epic-1-progress.json | jq .
#
#   # 완료된 story 목록
#   jq '.completed' state/epic-1-progress.json
#
#   # 실패한 story 목록
#   jq '.failed' state/epic-1-progress.json
#
#   # 상태 초기화 (처음부터 다시)
#   rm state/epic-1-progress.json
#
# ── Dashboard ──
#
# 전체 상태를 한눈에 보려면:
#   ./scripts/status.sh
