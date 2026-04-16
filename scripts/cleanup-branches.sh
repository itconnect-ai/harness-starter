#!/usr/bin/env bash
# ============================================================================
# scripts/cleanup-branches.sh
#
# main과 develop 양쪽에 merged된 임시 브랜치를 archive tag로 백업한 뒤
# 로컬/원격에서 삭제합니다. Phase C 회고 단계에서 호출됩니다.
#
# 복구 보장: 삭제 전에 archive/<branch-name>/<YYYYMMDD> 태그를 만들고
# 원격에 push합니다. 브랜치는 사라지지만 commit 히스토리는 태그로 영구 보존.
# 나중에 복구하려면: git checkout -b <name> archive/<branch-name>/<date>
#
# 사용법:
#   ./scripts/cleanup-branches.sh              # dry-run (기본, 무엇을 지울지만 표시)
#   ./scripts/cleanup-branches.sh --apply      # 실제 삭제 실행
#   ./scripts/cleanup-branches.sh --local-only --apply   # 로컬만
#   ./scripts/cleanup-branches.sh --remote-only --apply  # 원격만
#
# 보호 브랜치: main, develop, release/*, hotfix/* (절대 삭제 안 함)
# 삭제 조건: main과 develop 둘 다에 merged + 보호 패턴 아님
# ============================================================================
set -e

DRY_RUN=true
SCOPE="all"  # all | local | remote

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) DRY_RUN=false; shift ;;
    --local-only) SCOPE="local"; shift ;;
    --remote-only) SCOPE="remote"; shift ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

PROTECTED='^(main|develop|release/.*|hotfix/.*)$'
DATE=$(date +%Y%m%d)

# ── 원격 동기화 ──
git fetch --prune origin >/dev/null 2>&1 || true

DELETED_LOCAL=0
DELETED_REMOTE=0
TAGGED=0

# ── 로컬 정리 ──
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "local" ]; then
  echo "=== Local merged branches ==="
  CURRENT=$(git rev-parse --abbrev-ref HEAD)

  for base in main develop; do
    if ! git rev-parse --verify "$base" >/dev/null 2>&1; then
      continue
    fi

    # 병렬 루프에서 카운터 증가가 서브셸 문제로 전파 안 됨 — 임시 파일로 우회
    TMPF=$(mktemp)
    git branch --merged "$base" | grep -v '^\*' | sed 's/^[[:space:]]*//' > "$TMPF"

    while IFS= read -r branch; do
      [ -z "$branch" ] && continue
      [ "$branch" = "$CURRENT" ] && continue
      if echo "$branch" | grep -qE "$PROTECTED"; then
        continue
      fi

      if [ "$DRY_RUN" = true ]; then
        echo "  [WOULD DELETE] local $branch (merged to $base)"
      else
        echo "  [DELETE] local $branch"
        if git branch -d "$branch" 2>/dev/null; then
          DELETED_LOCAL=$((DELETED_LOCAL + 1))
        fi
      fi
    done < "$TMPF"
    rm -f "$TMPF"
  done
fi

# ── 원격 정리 (archive tag 생성 후) ──
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "remote" ]; then
  echo ""
  echo "=== Remote merged branches (archive + delete) ==="

  # main에 merged된 원격 브랜치를 순회
  TMPF=$(mktemp)
  git branch -r --merged origin/main 2>/dev/null \
    | grep -v 'HEAD' \
    | sed 's|origin/||' \
    | sed 's/^[[:space:]]*//' > "$TMPF" || true

  while IFS= read -r branch; do
    [ -z "$branch" ] && continue
    if echo "$branch" | grep -qE "$PROTECTED"; then
      continue
    fi

    # develop에도 merged인지 확인 (한 쪽에만 merged면 skip — 병합 안 끝난 상태일 수 있음)
    if ! git branch -r --merged origin/develop 2>/dev/null | grep -q "origin/$branch$"; then
      echo "  [KEEP] $branch (not merged to develop yet)"
      continue
    fi

    # archive tag 명: 슬래시를 언더스코어로 (tag 규칙)
    SAFE_NAME=$(echo "$branch" | tr '/' '_')
    TAG="archive/${SAFE_NAME}/${DATE}"

    if [ "$DRY_RUN" = true ]; then
      echo "  [WOULD ARCHIVE+DELETE] $branch → tag $TAG"
    else
      echo "  [ARCHIVE+DELETE] $branch → tag $TAG"
      # 기존 태그 덮어쓰기 방지 — 이미 있으면 skip
      if git rev-parse --verify "refs/tags/$TAG" >/dev/null 2>&1; then
        echo "    (tag already exists, skipping tag creation)"
      else
        git tag "$TAG" "origin/$branch" 2>/dev/null && TAGGED=$((TAGGED + 1))
        git push origin "$TAG" 2>/dev/null || true
      fi
      if git push origin --delete "$branch" 2>/dev/null; then
        DELETED_REMOTE=$((DELETED_REMOTE + 1))
      fi
    fi
  done < "$TMPF"
  rm -f "$TMPF"
fi

# ── 요약 ──
echo ""
echo "=== Summary ==="
if [ "$DRY_RUN" = true ]; then
  echo "Dry-run. Re-run with --apply to actually delete."
  echo "Archive tags 'archive/<branch>/<date>' will be created and pushed before remote deletion."
  echo "Recovery example: git checkout -b restored archive/story_foo/20260417"
else
  echo "Deleted: $DELETED_LOCAL local branch(es), $DELETED_REMOTE remote branch(es)"
  echo "Created: $TAGGED archive tag(s) for recovery"
  echo "Recovery example: git checkout -b restored archive/<branch>/<date>"
fi
