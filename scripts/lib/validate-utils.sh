#!/usr/bin/env bash
# ============================================================================
# scripts/lib/validate-utils.sh
#
# validate.sh / validate-quick.sh 공용 헬퍼 라이브러리
#
# 제공 기능:
#   - 출력 모드 분리 (summary / verbose)
#   - 로그 아티팩트 구조 (state/validate/latest/*.log)
#   - Node/CLI 실행 래퍼 (exit code 정확 전파 + 로그 저장)
#   - 노이즈 디렉터리 제외 grep 래퍼
#   - 실패 요약 출력
#
# 사용법:
#   source "$(dirname "$0")/lib/validate-utils.sh"
#   init_validate "epic"   # 또는 "quick"
#   run_step "01" "typecheck" "npm run typecheck"
#   finish_validate
# ============================================================================

# ── 출력 모드 ──
# VALIDATE_OUTPUT_MODE: summary (기본) | verbose
VALIDATE_OUTPUT_MODE="${VALIDATE_OUTPUT_MODE:-summary}"

# ── 로그 디렉터리 ──
VALIDATE_LOG_DIR=""
VALIDATE_LOG_LATEST=""
VALIDATE_RUN_TYPE=""
VALIDATE_LATEST_IS_LINK=false

# ── 결과 추적 ──
VALIDATE_TOTAL_STEPS=0
VALIDATE_PASSED_STEPS=0
VALIDATE_FAILED_STEP=""
VALIDATE_FAILED_CODE=0
VALIDATE_START_TIME=0

# ── 노이즈 제외 패턴 (grep --exclude-dir) ──
NOISE_EXCLUDE_DIRS=(
  .git
  node_modules
  .venv
  venv
  dist
  build
  coverage
  .next
  .turbo
  .cache
  .tmp
  playwright-report
  test-results
  __pycache__
)

# ============================================================================
# 초기화
# ============================================================================

init_validate() {
  local run_type="${1:-epic}"  # "epic" 또는 "quick"
  VALIDATE_RUN_TYPE="$run_type"
  VALIDATE_START_TIME=$(date +%s)

  # timestamped 디렉터리 생성
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local run_dir="state/validate/${run_type}-${timestamp}"
  mkdir -p "$run_dir"

  # latest 심링크 (또는 복사)
  VALIDATE_LOG_LATEST="state/validate/latest"
  rm -rf "$VALIDATE_LOG_LATEST" 2>/dev/null
  # 심링크 시도, 실패 시 (Windows 등) finish 단계에서 복사
  if ln -s "$(basename "$run_dir")" "$VALIDATE_LOG_LATEST" 2>/dev/null && [ -L "$VALIDATE_LOG_LATEST" ]; then
    VALIDATE_LATEST_IS_LINK=true
  else
    rm -rf "$VALIDATE_LOG_LATEST" 2>/dev/null
    mkdir -p "$VALIDATE_LOG_LATEST"
    VALIDATE_LATEST_IS_LINK=false
  fi

  VALIDATE_LOG_DIR="$run_dir"

  if [ "$VALIDATE_OUTPUT_MODE" = "summary" ]; then
    echo "======================================"
    echo " Validation Start (${run_type}-level)"
    echo " Mode: summary (set VALIDATE_OUTPUT_MODE=verbose for full output)"
    echo " Logs: ${VALIDATE_LOG_DIR}/"
    echo "======================================"
  fi
}

# ============================================================================
# 단계 실행 래퍼
# ============================================================================

# run_step <step_num> <step_name> <command...>
#
# - stdout/stderr를 로그 파일에 저장
# - summary 모드: 시작/종료/소요시간만 출력
# - verbose 모드: 실시간 출력 + 로그 파일 저장
# - exit code를 정확히 전파
run_step() {
  local step_num="$1"
  local step_name="$2"
  shift 2
  local cmd="$*"

  VALIDATE_TOTAL_STEPS=$((VALIDATE_TOTAL_STEPS + 1))

  local log_file="${VALIDATE_LOG_DIR}/${step_num}-${step_name}.log"
  local step_start
  step_start=$(date +%s)

  local step_exit=0

  if [ "$VALIDATE_OUTPUT_MODE" = "verbose" ]; then
    # verbose: 실시간 출력 + 로그 파일 저장
    echo ""
    echo "[${step_num}] ${step_name}..."
    eval "$cmd" 2>&1 | tee "$log_file" || step_exit=${PIPESTATUS[0]}
    # PIPESTATUS가 안 먹히는 환경 대비
    if [ $step_exit -eq 0 ] && [ "${PIPESTATUS[0]:-0}" -ne 0 ]; then
      step_exit=${PIPESTATUS[0]}
    fi
  else
    # summary: 로그 파일에만 저장, 콘솔에는 한 줄 요약
    printf "[%s] %-20s " "$step_num" "$step_name"
    eval "$cmd" > "$log_file" 2>&1
    step_exit=$?
  fi

  local step_end
  step_end=$(date +%s)
  local elapsed=$((step_end - step_start))

  if [ $step_exit -eq 0 ]; then
    VALIDATE_PASSED_STEPS=$((VALIDATE_PASSED_STEPS + 1))
    sync_latest_logs
    if [ "$VALIDATE_OUTPUT_MODE" = "summary" ]; then
      echo "PASSED (${elapsed}s)"
    else
      echo "[${step_num}] ${step_name}: PASSED (${elapsed}s)"
    fi
  else
    VALIDATE_FAILED_STEP="$step_name"
    VALIDATE_FAILED_CODE=$step_exit
    sync_latest_logs
    if [ "$VALIDATE_OUTPUT_MODE" = "summary" ]; then
      echo "FAILED (${elapsed}s)"
      print_failure_summary "$step_num" "$step_name" "$step_exit" "$log_file"
    else
      echo "[${step_num}] ${step_name}: FAILED (exit: ${step_exit}, ${elapsed}s)"
      echo "  Log: ${log_file}"
    fi
    return $step_exit
  fi

  return 0
}

# run_step_skip <step_num> <step_name> <reason>
# --from 옵션으로 건너뛴 단계 표시
run_step_skip() {
  local step_num="$1"
  local step_name="$2"
  local reason="${3:-skipped}"

  VALIDATE_TOTAL_STEPS=$((VALIDATE_TOTAL_STEPS + 1))
  VALIDATE_PASSED_STEPS=$((VALIDATE_PASSED_STEPS + 1))

  if [ "$VALIDATE_OUTPUT_MODE" = "summary" ]; then
    printf "[%s] %-20s SKIPPED (%s)\n" "$step_num" "$step_name" "$reason"
  else
    echo ""
    echo "[${step_num}] ${step_name}... SKIPPED (${reason})"
  fi
}

sync_latest_logs() {
  if [ "$VALIDATE_LATEST_IS_LINK" = true ]; then
    return 0
  fi

  if [ -z "$VALIDATE_LOG_LATEST" ] || [ "$VALIDATE_LOG_LATEST" = "$VALIDATE_LOG_DIR" ]; then
    return 0
  fi

  mkdir -p "$VALIDATE_LOG_LATEST"
  cp -a "${VALIDATE_LOG_DIR}/." "$VALIDATE_LOG_LATEST/" 2>/dev/null || \
    cp -R "${VALIDATE_LOG_DIR}/." "$VALIDATE_LOG_LATEST/" 2>/dev/null || true
}

# ============================================================================
# 실패 요약 출력
# ============================================================================

print_failure_summary() {
  local step_num="$1"
  local step_name="$2"
  local exit_code="$3"
  local log_file="$4"

  echo ""
  echo "── Failure Detail ──────────────────────"
  echo "  Step:      [${step_num}] ${step_name}"
  echo "  Exit code: ${exit_code}"
  echo "  Log:       ${log_file}"

  if [ -f "$log_file" ]; then
    local line_count
    line_count=$(wc -l < "$log_file" | tr -d ' ')

    # 테스트 러너의 구조화 출력이 있으면 우선 사용
    # (vitest/jest의 실패 테스트 요약 패턴 감지)
    local test_failures
    test_failures=$(grep -E "^[[:space:]]*(FAIL|✕|×|✗|FAILED)" "$log_file" 2>/dev/null | head -20)

    if [ -n "$test_failures" ]; then
      echo "  Failed tests:"
      echo "$test_failures" | sed 's/^/    /'
      echo ""
    fi

    # 마지막 50줄 (또는 파일이 짧으면 전체)
    local tail_lines=50
    if [ "$line_count" -le "$tail_lines" ]; then
      tail_lines="$line_count"
    fi
    echo "  Last ${tail_lines} lines:"
    tail -"$tail_lines" "$log_file" | sed 's/^/    /'
  fi
  echo "────────────────────────────────────────"
}

# ============================================================================
# 검증 완료
# ============================================================================

finish_validate() {
  local end_time
  end_time=$(date +%s)
  local total_elapsed=$((end_time - VALIDATE_START_TIME))
  sync_latest_logs

  echo ""
  if [ -n "$VALIDATE_FAILED_STEP" ]; then
    echo "======================================"
    echo " Validation FAILED"
    echo "  Failed at: ${VALIDATE_FAILED_STEP} (exit: ${VALIDATE_FAILED_CODE})"
    echo "  Steps:     ${VALIDATE_PASSED_STEPS}/${VALIDATE_TOTAL_STEPS} passed"
    echo "  Duration:  ${total_elapsed}s"
    echo "  Logs:      ${VALIDATE_LOG_DIR}/"
    echo "======================================"
    return 1
  else
    echo "======================================"
    echo " Validation PASSED"
    echo "  Steps:    ${VALIDATE_PASSED_STEPS}/${VALIDATE_TOTAL_STEPS} passed"
    echo "  Duration: ${total_elapsed}s"
    echo "  Logs:     ${VALIDATE_LOG_DIR}/"
    echo "======================================"
    return 0
  fi
}

# ============================================================================
# grep 래퍼 (노이즈 디렉터리 제외)
# ============================================================================

# safe_grep <grep_args...>
# node_modules, dist, .git 등을 자동 제외하는 grep 래퍼
safe_grep() {
  local exclude_args=""
  for dir in "${NOISE_EXCLUDE_DIRS[@]}"; do
    exclude_args="$exclude_args --exclude-dir=$dir"
  done
  # shellcheck disable=SC2086
  grep $exclude_args "$@"
}

# safe_grep_rn <pattern> <path> [--include=*.ts ...]
# -rn 옵션이 포함된 편의 래퍼
safe_grep_rn() {
  local pattern="$1"
  local path="$2"
  shift 2
  safe_grep -rn "$@" "$pattern" "$path" 2>/dev/null
}
