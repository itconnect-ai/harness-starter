#!/usr/bin/env bash
# ============================================================================
# scripts/validate-quick.sh
#
# Story 단위 빠른 검증 스크립트
# lint + typecheck + 변경된 파일 관련 테스트만 실행합니다.
# 전체 검증(validate.sh)은 Epic 완료 시 실행합니다.
#
# 사용법:
#   ./scripts/validate-quick.sh                               # summary 모드 (기본)
#   VALIDATE_OUTPUT_MODE=verbose ./scripts/validate-quick.sh  # 전체 출력
#   VALIDATE_BASE_REF=origin/develop ./scripts/validate-quick.sh  # base ref 지정
#
# 환경변수:
#   VALIDATE_OUTPUT_MODE  summary (기본) | verbose
#   VALIDATE_BASE_REF     비교 기준 브랜치 (기본: origin/develop → develop → origin/main → main 자동 탐색)
#
# 로그 위치:
#   state/validate/latest/*.log   (최신 실행)
#   state/validate/quick-*/*.log  (timestamped 아카이브)
#
# 종료코드: 0 = 성공, 1 = 실패
#
# 설계 원칙:
#   - 전체 테스트 suite로 silent fallback 하지 않음 (story 단위 검증이 느려지는 주 원인)
#   - 도구(vitest/jest)가 없으면 명시적 ERROR로 알림
#   - 템플릿 상태(package.json 없음)에서는 우아하게 SKIP
# ============================================================================
set -e

# ── 헬퍼 로드 ──
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib/validate-utils.sh"

# ── 초기화 ──
init_validate "quick"

# 조기 종료(예: run_step ... || exit 1)에도 요약·로그 경로가 출력되도록
# EXIT trap에 finalize 등록. exit code는 trap이 보존(side-effect만 수행).
HARNESS_FINALIZE_DONE=false
__harness_finalize_once() {
  if [ "$HARNESS_FINALIZE_DONE" = true ]; then
    return 0
  fi
  HARNESS_FINALIZE_DONE=true
  finish_validate || true
}
trap __harness_finalize_once EXIT

# ── 기준 브랜치 결정 ──
BASE_REF="${VALIDATE_BASE_REF:-}"
if [ -z "$BASE_REF" ]; then
  for ref in origin/develop develop origin/main main; do
    if git rev-parse --verify "$ref" >/dev/null 2>&1; then
      BASE_REF="$ref"
      break
    fi
  done
fi

# ── 1. 타입 체크 ──
if [ ! -f package.json ]; then
  run_step_skip "01" "typecheck" "no package.json (template state)"
else
  TYPECHECK_CMD=""
  if grep -q '"typecheck"' package.json 2>/dev/null; then
    TYPECHECK_CMD="npm run typecheck"
  elif [ -f tsconfig.json ] && [ -x node_modules/.bin/tsc ]; then
    # tsc --incremental로 증분 캐시 활용 (story 단위에서 특히 효과적)
    TYPECHECK_CMD="npx tsc --noEmit --incremental"
  fi

  if [ -z "$TYPECHECK_CMD" ]; then
    run_step_skip "01" "typecheck" "no typecheck script or tsc binary"
  else
    run_step "01" "typecheck" "$TYPECHECK_CMD" || exit 1
  fi
fi

# ── 2. 린트 ──
if [ ! -f package.json ]; then
  run_step_skip "02" "lint" "no package.json (template state)"
elif ! grep -q '"lint"' package.json 2>/dev/null; then
  run_step_skip "02" "lint" "no lint script in package.json"
else
  run_step "02" "lint" "npm run lint" || exit 1
fi

# ── 3. 변경된 파일 관련 테스트만 실행 ──
# 설계: base ref 대비 변경된 소스 파일이 있을 때만 실행.
# 전체 테스트 suite로 silent fallback 하지 않음 — 도구가 없으면 ERROR로 알림.
if [ ! -f package.json ]; then
  run_step_skip "03" "related-tests" "no package.json (template state)"
elif [ -z "$BASE_REF" ]; then
  run_step_skip "03" "related-tests" "no base ref found (develop/main)"
else
  TRACKED_CHANGED=$(git diff --name-only "$BASE_REF" -- '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null || true)
  UNTRACKED_CHANGED=$(git ls-files --others --exclude-standard -- '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null || true)
  CHANGED=$(printf "%s\n%s\n" "$TRACKED_CHANGED" "$UNTRACKED_CHANGED" | sed '/^$/d' | tr '\n' ' ')

  if [ -z "$CHANGED" ]; then
    run_step_skip "03" "related-tests" "no changed source files vs $BASE_REF"
  else
    # vitest/jest binary 직접 호출 (npm script fallback 없음 — story 단위 빠른 피드백 보장)
    TEST_CMD="${HARNESS_RELATED_TEST_CMD:-}"
    if [ -z "$TEST_CMD" ]; then
      if [ -x node_modules/.bin/vitest ]; then
        TEST_CMD="npx vitest related --run --reporter=verbose $CHANGED"
      elif [ -x node_modules/.bin/jest ]; then
        TEST_CMD="npx jest --findRelatedTests $CHANGED --passWithNoTests"
      fi
    fi

    if [ -z "$TEST_CMD" ]; then
      echo ""
      echo "[03] related-tests        ERROR" >&2
      echo "Story-level validation requires vitest or jest to run related tests only." >&2
      echo "Install one of:" >&2
      echo "  npm install -D vitest" >&2
      echo "  npm install -D jest" >&2
      echo "" >&2
      echo "Full test suite is intentionally NOT used as fallback — it makes per-story" >&2
      echo "validation too slow (5-10min). Use validate.sh for full-suite runs." >&2
      exit 1
    fi

    run_step "03" "related-tests" "$TEST_CMD" || exit 1
  fi
fi

# ── 완료 ──
__harness_finalize_once
