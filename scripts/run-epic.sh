#!/usr/bin/env bash
# ============================================================================
# scripts/run-epic.sh
#
# Epic 단위 반자동 실행 스크립트
# BMAD story를 Codex로 구현하고 Claude Code로 리뷰하는 파이프라인
#
# 특징:
#   - Epic 단위 배치 처리 (80개 story를 한 번에 돌리지 않음)
#   - 상태 파일 기반 재시작 (중간에 죽어도 이어서 처리)
#   - Rate limit 감지 + 자동 대기 + 재시도
#   - 모든 단계에 timeout (hang 방지)
#   - Story 간 순차 실행 + 머지 (의존성 보장)
#   - 실패 story 격리 (하나 실패해도 나머지 진행)
#
# 사용법:
#   ./scripts/run-epic.sh <epic-번호>
#   ./scripts/run-epic.sh 1
#   ./scripts/run-epic.sh 3
#
# 재시작:
#   같은 명령 다시 실행하면 마지막 성공 지점부터 이어서 처리
#
# 필수 조건:
#   - codex CLI 설치 및 로그인 완료
#   - claude CLI 설치 및 로그인 완료
#   - git 설정 완료
#   - _bmad-output/planning-artifacts/epics/ 아래 story 파일 존재
#
# ============================================================================
set -uo pipefail
# set -e를 쓰지 않음: 개별 실패를 직접 처리하기 위해

# ============================================================================
# 설정값 (필요에 따라 조정)
# ============================================================================

# 입력
EPIC_NUM="${1:-}"
if [ -z "$EPIC_NUM" ]; then
  echo "❌ Usage: ./scripts/run-epic.sh <epic-number>"
  echo "   Example: ./scripts/run-epic.sh 1"
  exit 1
fi

# 경로 (BMAD 기본 구조에 맞춤)
EPIC_DIR="_bmad-output/planning-artifacts/epics/epic-${EPIC_NUM}"
STATE_DIR="state"
STATE_FILE="${STATE_DIR}/epic-${EPIC_NUM}-progress.json"
REVIEW_DIR="reviews/epic-${EPIC_NUM}"
LOG_DIR="reviews/epic-${EPIC_NUM}/logs"

# Timeout (초)
CODEX_TIMEOUT=1200    # 20분 - 복잡한 story용. 단순하면 600(10분)으로 줄여도 됨
CLAUDE_TIMEOUT=300    # 5분
VALIDATE_TIMEOUT=180  # 3분

# 재시도
MAX_RETRIES=2         # 최대 재시도 횟수 (0 = 재시도 없음)
RATE_LIMIT_WAIT=600   # Rate limit 감지 시 대기 시간 (초) = 10분
COOLDOWN=30           # Story 사이 쿨다운 (초) - rate limit 방지

# Codex 설정
CODEX_SANDBOX="--full-auto"  # 필요 시 --sandbox workspace-write 로 변경

# ============================================================================
# 유틸리티 함수
# ============================================================================

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  echo "[$(timestamp)] $*"
}

log_to_file() {
  local file="$1"
  shift
  echo "[$(timestamp)] $*" >> "$file"
}

# ============================================================================
# 상태 관리 함수
# ============================================================================

init_state() {
  mkdir -p "$STATE_DIR" "$REVIEW_DIR" "$LOG_DIR"
  if [ ! -f "$STATE_FILE" ]; then
    cat > "$STATE_FILE" << 'EOF'
{
  "epic": "",
  "started_at": "",
  "updated_at": "",
  "completed": [],
  "failed": [],
  "skipped": [],
  "in_progress": null
}
EOF
    # epic 번호와 시작 시간 기록
    local tmp=$(mktemp)
    jq --arg e "$EPIC_NUM" --arg t "$(timestamp)" \
      '.epic = $e | .started_at = $t | .updated_at = $t' \
      "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  fi
}

update_timestamp() {
  local tmp=$(mktemp)
  jq --arg t "$(timestamp)" '.updated_at = $t' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

mark_in_progress() {
  local story="$1"
  local tmp=$(mktemp)
  jq --arg s "$story" '.in_progress = $s' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  update_timestamp
}

mark_completed() {
  local story="$1"
  local tmp=$(mktemp)
  jq --arg s "$story" \
    '.completed += [$s] | .completed |= unique | .in_progress = null' \
    "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  update_timestamp
}

mark_failed() {
  local story="$1" reason="${2:-unknown}"
  local tmp=$(mktemp)
  jq --arg s "$story" --arg r "$reason" \
    '.failed += [{"story": $s, "reason": $r}] | .in_progress = null' \
    "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  update_timestamp
}

mark_skipped() {
  local story="$1" reason="${2:-max retries}"
  local tmp=$(mktemp)
  jq --arg s "$story" --arg r "$reason" \
    '.skipped += [{"story": $s, "reason": $r}] | .in_progress = null' \
    "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  update_timestamp
}

is_already_processed() {
  local story="$1"
  jq -e --arg s "$story" \
    '(.completed | index($s) != null) or
     (.failed | map(.story) | index($s) != null) or
     (.skipped | map(.story) | index($s) != null)' \
    "$STATE_FILE" >/dev/null 2>&1
}

# ============================================================================
# Rate limit 감지
# ============================================================================

check_rate_limit() {
  local log_file="$1"
  if [ -f "$log_file" ]; then
    if grep -qiE "usage.limit|rate.limit|quota|too.many.requests|429" "$log_file" 2>/dev/null; then
      return 0  # rate limit 감지됨
    fi
  fi
  return 1  # rate limit 아님
}

wait_for_rate_limit() {
  local tool="$1"
  log "⏳ $tool rate limit detected. Waiting ${RATE_LIMIT_WAIT}s ($(( RATE_LIMIT_WAIT / 60 ))m)..."
  log "   Resume at: $(date -d "+${RATE_LIMIT_WAIT} seconds" '+%H:%M:%S' 2>/dev/null || date -v+${RATE_LIMIT_WAIT}S '+%H:%M:%S' 2>/dev/null || echo "~$(( RATE_LIMIT_WAIT / 60 ))min later")"
  sleep "$RATE_LIMIT_WAIT"
}

# ============================================================================
# 안전한 git 작업
# ============================================================================

safe_checkout_main() {
  git checkout main 2>/dev/null || git checkout master 2>/dev/null || {
    log "⚠ Cannot checkout main/master branch"
    return 1
  }
  git pull --ff-only 2>/dev/null || true
}

safe_create_branch() {
  local branch="$1"
  git branch -D "$branch" 2>/dev/null || true
  git checkout -b "$branch"
}

safe_merge_to_main() {
  local branch="$1"
  safe_checkout_main || return 1
  git merge "$branch" --no-edit 2>/dev/null || {
    log "⚠ Merge conflict on $branch"
    git merge --abort 2>/dev/null || true
    return 1
  }
  git branch -d "$branch" 2>/dev/null || true
  return 0
}

# ============================================================================
# 메인 Story 처리 함수
# ============================================================================

process_story() {
  local story_file="$1"
  local story_name=$(basename "$story_file" .md)
  local branch_name="story/${story_name}"
  local codex_log="${LOG_DIR}/${story_name}-codex.log"
  local claude_log="${LOG_DIR}/${story_name}-claude.log"
  local validate_log="${LOG_DIR}/${story_name}-validate.log"
  local review_file="${REVIEW_DIR}/${story_name}-review.md"

  log "────────────────────────────────────────"
  log "▶ [$story_name] Processing..."
  log "────────────────────────────────────────"

  mark_in_progress "$story_name"

  local retry=0
  local success=false

  while [ $retry -le $MAX_RETRIES ] && [ "$success" = false ]; do

    if [ $retry -gt 0 ]; then
      log "🔄 [$story_name] Retry $retry/$MAX_RETRIES"
      sleep $COOLDOWN
    fi

    # ── Step 1: 브랜치 준비 ──────────────────────────────────────
    log "  [1/4] Preparing branch..."
    safe_checkout_main || {
      log "  ⚠ Cannot prepare branch"
      retry=$((retry + 1))
      continue
    }
    safe_create_branch "$branch_name"

    # ── Step 2: Codex 구현 ───────────────────────────────────────
    log "  [2/4] Codex implementing... (timeout: ${CODEX_TIMEOUT}s)"

    local codex_exit=0
    timeout "$CODEX_TIMEOUT" codex exec $CODEX_SANDBOX \
      "You are implementing a story for a software project.

INSTRUCTIONS:
1. Read the AGENTS.md file for repository rules
2. Read the story file at: $story_file
3. Read the architecture: _bmad-output/planning-artifacts/architecture.md
4. Implement the story following ALL acceptance criteria
5. Follow coding rules in docs/agents/coding-rules.md
6. Add or update tests for changed behavior
7. Run ./scripts/validate.sh and fix any failures
8. Commit with message: feat($story_name): implement story

IMPORTANT:
- Stay within the scope of this story only
- Do not refactor unrelated code
- Do not add dependencies without justification
- Ensure validate.sh passes before your final commit" \
      > "$codex_log" 2>&1 || codex_exit=$?

    if [ $codex_exit -ne 0 ]; then
      log "  ⚠ Codex exited with code $codex_exit"

      if [ $codex_exit -eq 124 ]; then
        log "  ⚠ Codex timed out after ${CODEX_TIMEOUT}s"
        log_to_file "$codex_log" "TIMEOUT after ${CODEX_TIMEOUT}s"
      fi

      if check_rate_limit "$codex_log"; then
        wait_for_rate_limit "Codex"
      fi

      safe_checkout_main || true
      retry=$((retry + 1))
      continue
    fi

    # 커밋이 있는지 확인
    local commit_count=$(git log main..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [ "$commit_count" = "0" ]; then
      log "  ⚠ Codex made no commits. Skipping."
      safe_checkout_main || true
      retry=$((retry + 1))
      continue
    fi

    log "  ✓ Codex completed ($commit_count commits)"

    # ── Step 3: Validate ─────────────────────────────────────────
    log "  [3/4] Validating... (timeout: ${VALIDATE_TIMEOUT}s)"

    local validate_exit=0
    timeout "$VALIDATE_TIMEOUT" ./scripts/validate.sh \
      > "$validate_log" 2>&1 || validate_exit=$?

    if [ $validate_exit -ne 0 ]; then
      log "  ⚠ Validation failed (exit: $validate_exit)"
      log "     See: $validate_log"
      safe_checkout_main || true
      retry=$((retry + 1))
      continue
    fi

    log "  ✓ Validation passed"

    # ── Step 4: Claude 리뷰 ──────────────────────────────────────
    log "  [4/4] Claude reviewing... (timeout: ${CLAUDE_TIMEOUT}s)"

    local review_result=""
    local claude_exit=0

    review_result=$(timeout "$CLAUDE_TIMEOUT" claude -p \
      "You are reviewing code changes on a feature branch.

TASK: Review the git diff of the current branch against main.

REVIEW CRITERIA (from REVIEW.md):
1. Architecture boundaries: Check docs/agents/architecture-rules.md
2. Tests: Verify changed behavior has test coverage
3. Security: Input validation, auth checks, no sensitive data exposure
4. Story scope: Changes should be within the story scope only
5. Code quality: Naming consistency, error handling, no unnecessary complexity

STORY CONTEXT: Read $story_file for acceptance criteria.

OUTPUT FORMAT:
- If all criteria pass, respond with exactly: APPROVED
- If issues found, respond with: REJECTED followed by numbered issues

Be strict but fair. Only flag real issues, not style preferences." \
      2>"$claude_log") || claude_exit=$?

    if [ $claude_exit -ne 0 ]; then
      log "  ⚠ Claude review failed (exit: $claude_exit)"

      if [ $claude_exit -eq 124 ]; then
        log "  ⚠ Claude timed out"
      fi

      if check_rate_limit "$claude_log"; then
        wait_for_rate_limit "Claude"
      fi

      safe_checkout_main || true
      retry=$((retry + 1))
      continue
    fi

    # 리뷰 결과 저장
    echo "$review_result" > "$review_file"

    # ── Step 5: 판정 ─────────────────────────────────────────────
    if echo "$review_result" | grep -qi "^APPROVED"; then
      log "  ✅ [$story_name] APPROVED"

      if safe_merge_to_main "$branch_name"; then
        mark_completed "$story_name"
        success=true
        log "  ✓ Merged to main"
      else
        log "  ⚠ Merge failed"
        mark_failed "$story_name" "merge-conflict"
        safe_checkout_main || true
        success=true  # 실패로 기록하고 다음으로
      fi
    else
      log "  ❌ [$story_name] REJECTED"
      log "     Review saved: $review_file"
      mark_failed "$story_name" "review-rejected"
      safe_checkout_main || true
      success=true  # 실패로 기록하고 다음으로
    fi

    retry=$((retry + 1))
  done

  # 모든 재시도 소진
  if [ "$success" = false ]; then
    log "  ⛔ [$story_name] All retries exhausted"
    mark_skipped "$story_name" "retries-exhausted"
    safe_checkout_main 2>/dev/null || true
  fi

  return 0
}

# ============================================================================
# 메인 실행
# ============================================================================

main() {
  # 초기화
  init_state

  # Story 파일 수집 (파일명 기준 정렬)
  local stories=()
  while IFS= read -r -d '' file; do
    stories+=("$file")
  done < <(find "$EPIC_DIR" -name "story-*.md" -print0 2>/dev/null | sort -zV)

  if [ ${#stories[@]} -eq 0 ]; then
    log "❌ No story files found in $EPIC_DIR"
    log "   Expected files like: ${EPIC_DIR}/story-1.md, story-2.md, ..."
    log ""
    log "   Story 파일 이름이 다르면 위 find 패턴을 수정하세요."
    log "   예: story-*.md → *.story.md"
    exit 1
  fi

  # 이미 처리된 수 계산
  local total=${#stories[@]}
  local already_done=0
  for sf in "${stories[@]}"; do
    local sn=$(basename "$sf" .md)
    if is_already_processed "$sn"; then
      already_done=$((already_done + 1))
    fi
  done

  echo ""
  log "══════════════════════════════════════════════════════"
  log "▶ Epic $EPIC_NUM: $total stories ($already_done already processed)"
  log "  State: $STATE_FILE"
  log "  Reviews: $REVIEW_DIR/"
  log "══════════════════════════════════════════════════════"
  echo ""

  if [ $already_done -eq $total ]; then
    log "✅ All stories already processed. Nothing to do."
    log "   To reprocess, delete $STATE_FILE and run again."
    exit 0
  fi

  # Story 순차 처리
  local processed=0
  for story_file in "${stories[@]}"; do
    local story_name=$(basename "$story_file" .md)

    # 이미 처리된 story 건너뛰기
    if is_already_processed "$story_name"; then
      continue
    fi

    processed=$((processed + 1))
    local remaining=$((total - already_done - processed + 1))

    log ""
    log "[$processed of $((total - already_done))] Remaining: $remaining"

    process_story "$story_file"

    # Story 간 쿨다운 (마지막 story 제외)
    if [ $remaining -gt 1 ]; then
      log "⏱ Cooldown ${COOLDOWN}s before next story..."
      sleep "$COOLDOWN"
    fi
  done

  # ── 최종 보고 ──
  echo ""
  log "══════════════════════════════════════════════════════"
  log "▶ Epic $EPIC_NUM Processing Complete"
  log "══════════════════════════════════════════════════════"
  log ""
  log "  Completed : $(jq '.completed | length' "$STATE_FILE")"
  log "  Failed    : $(jq '.failed | length' "$STATE_FILE")"
  log "  Skipped   : $(jq '.skipped | length' "$STATE_FILE")"
  log ""

  # 실패 목록 출력
  local fail_count=$(jq '.failed | length' "$STATE_FILE")
  if [ "$fail_count" -gt 0 ]; then
    log "  ❌ Failed stories:"
    jq -r '.failed[] | "     - \(.story): \(.reason)"' "$STATE_FILE"
    log ""
  fi

  local skip_count=$(jq '.skipped | length' "$STATE_FILE")
  if [ "$skip_count" -gt 0 ]; then
    log "  ⛔ Skipped stories:"
    jq -r '.skipped[] | "     - \(.story): \(.reason)"' "$STATE_FILE"
    log ""
  fi

  log "  State file : $STATE_FILE"
  log "  Review dir : $REVIEW_DIR/"
  log "  Log dir    : $LOG_DIR/"
  log ""
  log "  ▶ 실패/스킵된 story는 수동으로 확인하세요."
  log "  ▶ 이 스크립트를 다시 실행하면 미처리 story만 처리합니다."
  log "══════════════════════════════════════════════════════"
}

main
