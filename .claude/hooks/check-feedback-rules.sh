#!/usr/bin/env bash
# ============================================================================
# .claude/hooks/check-feedback-rules.sh
#
# SessionStart Hook: 세션 시작 시 feedback-rules.md의 활성 규칙을 확인합니다.
# 가시성 목적 — 차단하지 않고 정보만 제공합니다.
# ============================================================================

project_dir="${CLAUDE_PROJECT_DIR:-.}"
rules_file="$project_dir/docs/agents/feedback-rules.md"

if [ ! -f "$rules_file" ]; then
  echo "feedback-rules.md not found" >&2
  exit 0
fi

# Active Rules 섹션에서 "### N." 패턴을 세어 활성 규칙 수 확인
active_count=$(grep -c "^### [0-9]" "$rules_file" 2>/dev/null || echo "0")

if [ "$active_count" -gt 0 ]; then
  echo "Feedback rules loaded: $active_count active rule(s)" >&2
  grep "^### [0-9]" "$rules_file" | sed 's/^/  /' >&2
fi

exit 0
