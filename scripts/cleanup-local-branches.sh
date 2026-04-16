#!/usr/bin/env bash
# ============================================================================
# scripts/cleanup-local-branches.sh
#
# 로컬의 merged + remote에서 사라진 브랜치를 정리합니다.
# 원격 자동 정리는 .github/workflows/cleanup-stale-branches.yml 담당.
#
# 사용법:
#   ./scripts/cleanup-local-branches.sh          # dry-run (무엇을 지울지 보여주기만)
#   ./scripts/cleanup-local-branches.sh --apply  # 실제 삭제
# ============================================================================
set -e

APPLY=false
if [ "${1:-}" = "--apply" ]; then
  APPLY=true
fi

# 원격에서 사라진 브랜치 추적 제거
git fetch --prune origin >/dev/null 2>&1 || true

# 보호 브랜치
PROTECTED='^(main|develop|release/.*|hotfix/.*)$'

# main/develop에 merged 된 로컬 브랜치
CURRENT=$(git rev-parse --abbrev-ref HEAD)

echo "=== Local branches to clean up ==="

for base in main develop; do
  if ! git rev-parse --verify "$base" >/dev/null 2>&1; then
    continue
  fi

  git branch --merged "$base" | grep -v '^\*' | sed 's/^[[:space:]]*//' | while read -r branch; do
    [ -z "$branch" ] && continue
    [ "$branch" = "$CURRENT" ] && continue

    if echo "$branch" | grep -qE "$PROTECTED"; then
      continue
    fi

    if [ "$APPLY" = true ]; then
      echo "  [DELETE] $branch (merged to $base)"
      git branch -d "$branch" 2>/dev/null || true
    else
      echo "  [WOULD DELETE] $branch (merged to $base)"
    fi
  done
done

if [ "$APPLY" = false ]; then
  echo ""
  echo "Dry-run only. Run with --apply to actually delete."
fi
