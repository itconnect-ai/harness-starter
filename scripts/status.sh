#!/usr/bin/env bash
# ============================================================================
# scripts/status.sh
#
# 모든 epic의 진행 상태를 한눈에 보여주는 대시보드 스크립트
#
# 사용법: ./scripts/status.sh
# ============================================================================

echo "══════════════════════════════════════════════════════"
echo "▶ Harness Status Dashboard"
echo "══════════════════════════════════════════════════════"
echo ""

# state 폴더의 모든 epic progress 파일 확인
found=false
for state_file in state/epic-*-progress.json; do
  [ -f "$state_file" ] || continue
  found=true

  epic_num=$(jq -r '.epic' "$state_file" 2>/dev/null)
  completed=$(jq '.completed | length' "$state_file" 2>/dev/null)
  failed=$(jq '.failed | length' "$state_file" 2>/dev/null)
  skipped=$(jq '.skipped | length' "$state_file" 2>/dev/null)
  in_progress=$(jq -r '.in_progress // "none"' "$state_file" 2>/dev/null)
  updated=$(jq -r '.updated_at // "unknown"' "$state_file" 2>/dev/null)
  total=$((completed + failed + skipped))

  echo "  Epic $epic_num:"
  echo "    ✅ Completed : $completed"
  echo "    ❌ Failed    : $failed"
  echo "    ⛔ Skipped   : $skipped"
  echo "    📊 Total     : $total"
  echo "    🔄 In progress: $in_progress"
  echo "    🕐 Last update: $updated"

  # 실패 목록
  if [ "$failed" -gt 0 ]; then
    echo "    ❌ Failed stories:"
    jq -r '.failed[] | "       - \(.story): \(.reason)"' "$state_file" 2>/dev/null
  fi

  echo ""
done

if [ "$found" = false ]; then
  echo "  No epic progress files found in state/"
  echo "  Run: ./scripts/run-epic.sh <epic-number> to start"
fi

echo "══════════════════════════════════════════════════════"
