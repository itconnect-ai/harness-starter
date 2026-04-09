#!/usr/bin/env bash
# ============================================================================
# scripts/validate-quick.sh
#
# Story 단위 빠른 검증 스크립트
# lint + typecheck + 변경된 파일 관련 테스트만 실행합니다.
# 전체 검증(validate.sh)은 Epic 완료 시 실행합니다.
#
# 사용법:
#   ./scripts/validate-quick.sh                          # summary 모드 (기본)
#   VALIDATE_OUTPUT_MODE=verbose ./scripts/validate-quick.sh  # 전체 출력
#
# 환경변수:
#   VALIDATE_OUTPUT_MODE  summary (기본) | verbose
#
# 로그 위치:
#   state/validate/latest/*.log   (최신 실행)
#   state/validate/quick-*/*.log  (timestamped 아카이브)
#
# 종료코드: 0 = 성공, 1 = 실패
# ============================================================================
set -e

# ── 헬퍼 로드 ──
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/lib/validate-utils.sh"

# ── 초기화 ──
init_validate "quick"

# ── 1. 타입 체크 ──
run_step "01" "typecheck" "npm run typecheck 2>&1 || npx tsc --noEmit 2>&1" || exit 1

# ── 2. 린트 ──
run_step "02" "lint" "npm run lint" || exit 1

# ── 3. 변경된 파일 관련 테스트만 실행 ──
CHANGED=$(git diff --name-only main -- '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null | tr '\n' ' ')

if [ -z "$CHANGED" ]; then
  run_step_skip "03" "related-tests" "no changed source files"
else
  # vitest --changed 또는 jest --changedSince 시도
  # 실패 시 전체 테스트 fallback (출력은 로그 파일로 제한)
  run_step "03" "related-tests" \
    "npx vitest run --changed main --reporter=verbose 2>&1 || npx jest --changedSince=main --passWithNoTests 2>&1 || npm run test 2>&1" \
    || exit 1
fi

# ── 완료 ──
finish_validate
