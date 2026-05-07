#!/usr/bin/env bash
# ============================================================================
# scripts/validate.sh
#
# Epic 단위 전체 검증 스크립트
# Story 단위 빠른 검증은 validate-quick.sh를 사용하세요.
#
# 사용법:
#   ./scripts/validate.sh                          # 전체 실행 (summary 모드)
#   ./scripts/validate.sh --from=test              # 테스트 단계부터 재개
#   VALIDATE_OUTPUT_MODE=verbose ./scripts/validate.sh  # 전체 출력
#
# --from 옵션:
#   --from=typecheck  타입 체크부터 (의존성 설치 건너뜀)
#   --from=lint       린트부터
#   --from=test       테스트부터
#   --from=build      빌드부터
#   --from=security   보안 체크부터
#
# 환경변수:
#   VALIDATE_OUTPUT_MODE  summary (기본) | verbose
#
# 로그 위치:
#   state/validate/latest/*.log   (최신 실행)
#   state/validate/epic-*/*.log   (timestamped 아카이브)
#
# 종료코드: 0 = 성공, 1 = 실패
# ============================================================================
set -e

# ── 헬퍼 로드 ──
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib/validate-utils.sh"

# ── --from 옵션 파싱 ──
SKIP_INSTALL=false
SKIP_TYPECHECK=false
SKIP_LINT=false
SKIP_TEST=false
SKIP_BUILD=false

case "${1:-}" in
  --from=typecheck)
    SKIP_INSTALL=true
    ;;
  --from=lint)
    SKIP_INSTALL=true; SKIP_TYPECHECK=true
    ;;
  --from=test)
    SKIP_INSTALL=true; SKIP_TYPECHECK=true; SKIP_LINT=true
    ;;
  --from=build)
    SKIP_INSTALL=true; SKIP_TYPECHECK=true; SKIP_LINT=true; SKIP_TEST=true
    ;;
  --from=security)
    SKIP_INSTALL=true; SKIP_TYPECHECK=true; SKIP_LINT=true; SKIP_TEST=true; SKIP_BUILD=true
    ;;
  "")
    ;; # 전체 실행
  *)
    echo "Unknown option: $1"
    echo "Usage: ./scripts/validate.sh [--from=typecheck|lint|test|build|security]"
    exit 1
    ;;
esac

# ── 초기화 ──
init_validate "epic"

if [ -n "${1:-}" ]; then
  echo " Resuming from: ${1#--from=}"
  echo ""
fi

# ── Template 감지: package.json 없으면 npm 관련 단계 모두 skip ──
HAS_PACKAGE_JSON=false
if [ -f package.json ]; then
  HAS_PACKAGE_JSON=true
fi

# ── 1. 의존성 설치 ──
if [ "$SKIP_INSTALL" = false ]; then
  if [ "$HAS_PACKAGE_JSON" = false ]; then
    run_step_skip "01" "install" "no package.json (template state)"
  else
    run_step "01" "install" "npm install --prefer-offline" || exit 1
  fi
else
  run_step_skip "01" "install" "--from"
fi

# ── 2. 타입 체크 ──
if [ "$SKIP_TYPECHECK" = false ]; then
  if [ "$HAS_PACKAGE_JSON" = false ]; then
    run_step_skip "02" "typecheck" "no package.json (template state)"
  else
    TYPECHECK_CMD=""
    if grep -q '"typecheck"' package.json 2>/dev/null; then
      TYPECHECK_CMD="npm run typecheck"
    elif [ -f tsconfig.json ] && [ -x node_modules/.bin/tsc ]; then
      TYPECHECK_CMD="npx tsc --noEmit"
    fi

    if [ -z "$TYPECHECK_CMD" ]; then
      run_step_skip "02" "typecheck" "no typecheck script or local tsc binary"
    else
      run_step "02" "typecheck" "$TYPECHECK_CMD" || exit 1
    fi
  fi
else
  run_step_skip "02" "typecheck" "--from"
fi

# ── 3. 린트 ──
if [ "$SKIP_LINT" = false ]; then
  if [ "$HAS_PACKAGE_JSON" = false ]; then
    run_step_skip "03" "lint" "no package.json (template state)"
  else
    run_step "03" "lint" "npm run lint" || exit 1
  fi
else
  run_step_skip "03" "lint" "--from"
fi

# ── 4a. 테스트 ──
if [ "$SKIP_TEST" = false ]; then
  if [ "$HAS_PACKAGE_JSON" = false ]; then
    run_step_skip "04a" "test" "no package.json (template state)"
    run_step_skip "04b" "regression-test" "no package.json (template state)"
  else
    TEST_CMD=""
    if grep -q '"test"' package.json 2>/dev/null; then
      TEST_CMD="npm run test"
    elif [ -x node_modules/.bin/vitest ]; then
      TEST_CMD="npx vitest run"
    elif [ -x node_modules/.bin/jest ]; then
      TEST_CMD="npx jest --runInBand"
    fi

    if [ -z "$TEST_CMD" ]; then
      run_step_skip "04a" "test" "no test script or local vitest/jest binary"
    else
      run_step "04a" "test" "$TEST_CMD" || exit 1
    fi

    # 4b. Regression 테스트
    if [ -d "tests/regression" ] && [ "$(ls -A tests/regression/ 2>/dev/null)" ]; then
      REGRESSION_TEST_CMD=""
      if [ -x node_modules/.bin/vitest ]; then
        REGRESSION_TEST_CMD="npx vitest run tests/regression/"
      elif [ -x node_modules/.bin/jest ]; then
        REGRESSION_TEST_CMD="npx jest --runInBand --testPathPattern=tests/regression/"
      elif grep -q '"test"' package.json 2>/dev/null; then
        REGRESSION_TEST_CMD="npm run test -- tests/regression/"
      fi

      if [ -z "$REGRESSION_TEST_CMD" ]; then
        run_step_skip "04b" "regression-test" "no supported test runner"
      else
        run_step "04b" "regression-test" "$REGRESSION_TEST_CMD" || exit 1
      fi
    else
      run_step_skip "04b" "regression-test" "no tests/regression/ found"
    fi
  fi
else
  run_step_skip "04a" "test" "--from"
  run_step_skip "04b" "regression-test" "--from"
fi

# ── 5. 빌드 ──
if [ "$SKIP_BUILD" = false ]; then
  if [ "$HAS_PACKAGE_JSON" = false ]; then
    run_step_skip "05" "build" "no package.json (template state)"
  else
    run_step "05" "build" "npm run build" || exit 1
  fi
else
  run_step_skip "05" "build" "--from"
fi

# ── 6. 보안 체크 ──
# 보안/성능 체크는 run_step 래퍼 대신 직접 처리 (warning 카운트 방식)
echo ""
if [ "$VALIDATE_OUTPUT_MODE" = "summary" ]; then
  printf "[06] %-20s " "security"
else
  echo "[06] security..."
fi

SECURITY_LOG="${VALIDATE_LOG_DIR}/06-security.log"
SECURITY_WARNINGS=0

{
  # 하드코딩된 시크릿 패턴 감지 (노이즈 디렉터리 제외)
  if safe_grep_rn \
    -iE "(api[_-]?key|secret|password|token)\s*[:=]\s*['\"][a-zA-Z0-9]{8,}" \
    src/ \
    --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" | \
    grep -v "process\.env\|\.env\.\|\.example\|test\|mock\|fake\|dummy" ; then
    echo "WARNING: Possible hardcoded secret detected in source code"
    SECURITY_WARNINGS=$((SECURITY_WARNINGS+1))
  fi

  # .env 파일이 git에 추가되었는지
  if git diff --cached --name-only 2>/dev/null | grep -E "^\.env(\.\w+)?$" | grep -v "\.example" ; then
    echo "WARNING: .env file staged for commit"
    SECURITY_WARNINGS=$((SECURITY_WARNINGS+1))
  fi

  # destructive docker compose volume deletion pattern
  DESTRUCTIVE_DOCKER_VOLUME_PATTERN="down -[v]\|down --[v]olumes"
  if safe_grep_rn "$DESTRUCTIVE_DOCKER_VOLUME_PATTERN" scripts/ ; then
    echo "WARNING: destructive docker compose volume removal command found in scripts (destroys DB data)"
    SECURITY_WARNINGS=$((SECURITY_WARNINGS+1))
  fi

  if [ $SECURITY_WARNINGS -gt 0 ]; then
    echo "Security check: $SECURITY_WARNINGS warning(s) found"
  else
    echo "Security check: PASSED"
  fi
} > "$SECURITY_LOG" 2>&1

VALIDATE_TOTAL_STEPS=$((VALIDATE_TOTAL_STEPS + 1))
VALIDATE_PASSED_STEPS=$((VALIDATE_PASSED_STEPS + 1))

if [ "$VALIDATE_OUTPUT_MODE" = "summary" ]; then
  if [ $SECURITY_WARNINGS -gt 0 ]; then
    echo "WARN (${SECURITY_WARNINGS} warning(s)) — log: ${SECURITY_LOG}"
  else
    echo "PASSED"
  fi
else
  cat "$SECURITY_LOG"
fi

# ── 7. 성능 체크 ──
if [ "$VALIDATE_OUTPUT_MODE" = "summary" ]; then
  printf "[07] %-20s " "performance"
else
  echo ""
  echo "[07] performance..."
fi

PERF_LOG="${VALIDATE_LOG_DIR}/07-performance.log"
PERF_WARNINGS=0

{
  # 바운드 없는 findMany() 감지
  if safe_grep_rn "findMany()" src/ --include="*.ts" | grep -v "take:\|limit:\|where:" ; then
    echo "WARNING: findMany() without take/limit may return unbounded results"
    PERF_WARNINGS=$((PERF_WARNINGS+1))
  fi

  # 전체 lodash import 감지
  if safe_grep_rn "from 'lodash'" src/ --include="*.ts" --include="*.tsx" | grep -v "lodash/" ; then
    echo "WARNING: Full lodash import; use lodash/specific-function"
    PERF_WARNINGS=$((PERF_WARNINGS+1))
  fi

  # Dockerfile 레이어 순서 체크
  if [ -f Dockerfile ]; then
    COPY_ALL=$(grep -n "COPY \. " Dockerfile 2>/dev/null | head -1 | cut -d: -f1)
    NPM_CI=$(grep -n "RUN npm" Dockerfile 2>/dev/null | head -1 | cut -d: -f1)
    if [ -n "$COPY_ALL" ] && [ -n "$NPM_CI" ] && [ "$COPY_ALL" -lt "$NPM_CI" ]; then
      echo "WARNING: Dockerfile copies source before npm install (cache-busting)"
      PERF_WARNINGS=$((PERF_WARNINGS+1))
    fi
  fi

  if [ $PERF_WARNINGS -gt 0 ]; then
    echo "Performance check: $PERF_WARNINGS warning(s) found"
  else
    echo "Performance check: PASSED"
  fi
} > "$PERF_LOG" 2>&1

VALIDATE_TOTAL_STEPS=$((VALIDATE_TOTAL_STEPS + 1))
VALIDATE_PASSED_STEPS=$((VALIDATE_PASSED_STEPS + 1))

if [ "$VALIDATE_OUTPUT_MODE" = "summary" ]; then
  if [ $PERF_WARNINGS -gt 0 ]; then
    echo "WARN (${PERF_WARNINGS} warning(s)) — log: ${PERF_LOG}"
  else
    echo "PASSED"
  fi
else
  cat "$PERF_LOG"
fi

# ── 8. Blocking 체크 (Phase C에서 승격된 패턴) ──
if [ "$VALIDATE_OUTPUT_MODE" = "summary" ]; then
  printf "[08] %-20s " "blocking"
else
  echo ""
  echo "[08] blocking..."
fi

BLOCKING_LOG="${VALIDATE_LOG_DIR}/08-blocking.log"
BLOCKING_ERRORS=0

{
  # ── Phase C 승격 패턴은 아래에 추가 ──
  # 예시 (승격 시 주석 해제하고 패턴에 맞게 수정):
  # if safe_grep_rn "하드코딩패턴" src/ --include="*.ts" ; then
  #   echo "BLOCKED: [incident-id] 설명"
  #   BLOCKING_ERRORS=$((BLOCKING_ERRORS+1))
  # fi

  if [ $BLOCKING_ERRORS -gt 0 ]; then
    echo "Blocking check: $BLOCKING_ERRORS error(s) — FAIL"
  else
    echo "Blocking check: PASSED (no promoted patterns)"
  fi
} > "$BLOCKING_LOG" 2>&1

VALIDATE_TOTAL_STEPS=$((VALIDATE_TOTAL_STEPS + 1))

if [ $BLOCKING_ERRORS -gt 0 ]; then
  VALIDATE_FAILED_STEP="blocking"
  VALIDATE_FAILED_CODE=1
  if [ "$VALIDATE_OUTPUT_MODE" = "summary" ]; then
    echo "FAILED (${BLOCKING_ERRORS} error(s)) — log: ${BLOCKING_LOG}"
  else
    cat "$BLOCKING_LOG"
  fi
  finish_validate
  exit 1
else
  VALIDATE_PASSED_STEPS=$((VALIDATE_PASSED_STEPS + 1))
  if [ "$VALIDATE_OUTPUT_MODE" = "summary" ]; then
    echo "PASSED"
  else
    cat "$BLOCKING_LOG"
  fi
fi

# ── 완료 ──
finish_validate
