#!/usr/bin/env bash
# ============================================================================
# scripts/status.sh
#
# 모든 epic의 진행 상태를 한눈에 보여주는 대시보드 스크립트
#
# Primary source: _bmad-output/implementation-artifacts/sprint-status.yaml
# Secondary source: state/epic-*-progress.json (run-epic.sh CLI fallback)
#
# 사용법: ./scripts/status.sh
# ============================================================================

SPRINT_STATUS="_bmad-output/implementation-artifacts/sprint-status.yaml"

echo "══════════════════════════════════════════════════════"
echo "▶ Harness Status Dashboard"
echo "══════════════════════════════════════════════════════"
echo ""

# ── Primary: sprint-status.yaml ──────────────────────────
if [ -f "$SPRINT_STATUS" ]; then
  echo "── Sprint Status (sprint-status.yaml) ──"
  echo ""

  # Count epics by status
  done_count=$(grep -c 'status:.*done' "$SPRINT_STATUS" 2>/dev/null || echo 0)
  in_progress_count=$(grep -c 'status:.*in-progress' "$SPRINT_STATUS" 2>/dev/null || echo 0)
  backlog_count=$(grep -c 'status:.*backlog' "$SPRINT_STATUS" 2>/dev/null || echo 0)

  echo "  Summary:"
  echo "    Done        : $done_count"
  echo "    In Progress : $in_progress_count"
  echo "    Backlog     : $backlog_count"
  echo ""

  # Show non-done items (epics and stories that are not 'done')
  # Parse YAML manually: look for epic/story lines and their status
  current_epic=""
  while IFS= read -r line; do
    # Detect epic headers (lines like "  epic-1:" or "  1:")
    if echo "$line" | grep -qE '^\s{0,4}[a-zA-Z0-9_-]+:$'; then
      current_epic=$(echo "$line" | sed 's/[: ]//g')
      continue
    fi

    # Detect name field
    if echo "$line" | grep -qE '^\s+name:'; then
      current_name=$(echo "$line" | sed 's/.*name:\s*//')
      continue
    fi

    # Detect status field - show non-done items
    if echo "$line" | grep -qE '^\s+status:'; then
      status=$(echo "$line" | sed 's/.*status:\s*//')
      if [ "$status" != "done" ] && [ -n "$current_epic" ]; then
        echo "  [$status] $current_epic: ${current_name:-}"
      fi
    fi
  done < "$SPRINT_STATUS"

  echo ""
else
  echo "  sprint-status.yaml not found at: $SPRINT_STATUS"
  echo "  This file is created by BMAD sprint planning."
  echo ""
fi

# ── Secondary: run-epic.sh state files ───────────────────
echo "── run-epic.sh State Files ──"
echo ""

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

  echo "  Epic $epic_num (run-epic.sh):"
  echo "    Completed   : $completed"
  echo "    Failed      : $failed"
  echo "    Skipped     : $skipped"
  echo "    Total       : $total"
  echo "    In progress : $in_progress"
  echo "    Last update : $updated"

  # Failed stories list
  if [ "$failed" -gt 0 ]; then
    echo "    Failed stories:"
    jq -r '.failed[] | "       - \(.story): \(.reason)"' "$state_file" 2>/dev/null
  fi

  echo ""
done

if [ "$found" = false ]; then
  echo "  No run-epic.sh state files found in state/"
  echo "  These are created when using: ./scripts/run-epic.sh <epic-number>"
  echo ""
fi

echo "══════════════════════════════════════════════════════"
