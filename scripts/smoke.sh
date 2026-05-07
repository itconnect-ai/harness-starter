#!/usr/bin/env bash
# ============================================================================
# scripts/smoke.sh
#
# 핵심 사용자 플로우를 검증하는 스모크 테스트입니다.
# 중요한 경로가 깨지지 않았는지 빠르게 확인합니다.
# 프로젝트의 핵심 플로우에 맞게 수정하세요.
#
# 사용법: ./scripts/smoke.sh
#
# 환경변수:
#   HARNESS_SMOKE_CMD     명시적 스모크 명령 (다른 모든 자동 감지를 우회)
#   HARNESS_SMOKE_TIMEOUT 초 단위 timeout (기본 600 = 10분)
#
# 행 회피 설계:
#   - npm run test:e2e / npm run test 직접 호출 금지
#     ("test": "vitest" 같은 스크립트가 watch 모드로 진입해 무한 행 발생)
#   - test:e2e 스크립트가 있으면 그대로 실행하되 timeout으로 캡
#   - 그 외에는 vitest/jest binary 직접 호출
# ============================================================================
set -e

echo "══════════════════════════════════════"
echo " Smoke Test Start"
echo "══════════════════════════════════════"

if [ ! -f package.json ]; then
  echo "SKIPPED: no package.json (template state)"
  exit 0
fi

SMOKE_TIMEOUT="${HARNESS_SMOKE_TIMEOUT:-600}"
HARNESS_TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  HARNESS_TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  HARNESS_TIMEOUT_BIN="gtimeout"
fi

run_with_cap() {
  if [ -n "$HARNESS_TIMEOUT_BIN" ] && [ "$SMOKE_TIMEOUT" -gt 0 ]; then
    $HARNESS_TIMEOUT_BIN -k 30s "${SMOKE_TIMEOUT}s" bash -c "$1"
  else
    bash -c "$1"
  fi
}

# 우선순위:
#   1. HARNESS_SMOKE_CMD (명시 우회)
#   2. test:e2e 스크립트 (있으면)
#   3. vitest/jest binary 직접 호출
if [ -n "${HARNESS_SMOKE_CMD:-}" ]; then
  echo " Running HARNESS_SMOKE_CMD..."
  run_with_cap "$HARNESS_SMOKE_CMD"
elif grep -q '"test:e2e"' package.json 2>/dev/null; then
  echo " Running npm run test:e2e..."
  run_with_cap "npm run test:e2e --silent"
elif [ -x node_modules/.bin/vitest ]; then
  echo " Running vitest run (smoke fallback)..."
  run_with_cap "npx vitest run"
elif [ -x node_modules/.bin/jest ]; then
  echo " Running jest --runInBand --ci (smoke fallback)..."
  run_with_cap "npx jest --runInBand --ci"
else
  echo "SKIPPED: no HARNESS_SMOKE_CMD, test:e2e script, or vitest/jest binary"
  exit 0
fi

echo ""
echo "══════════════════════════════════════"
echo " Smoke Test PASSED"
echo "══════════════════════════════════════"
