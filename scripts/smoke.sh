#!/usr/bin/env bash
# ============================================================================
# scripts/smoke.sh
#
# 핵심 사용자 플로우를 검증하는 스모크 테스트입니다.
# 중요한 경로가 깨지지 않았는지 빠르게 확인합니다.
# 프로젝트의 핵심 플로우에 맞게 수정하세요.
#
# 사용법: ./scripts/smoke.sh
# ============================================================================
set -e

echo "══════════════════════════════════════"
echo "▶ Smoke Test Start"
echo "══════════════════════════════════════"

# ⚠️ 아래는 예시입니다. 프로젝트에 맞게 수정하세요.

# E2E 테스트가 있는 경우
if npm run test:e2e --silent 2>/dev/null; then
  echo "✅ E2E tests passed"
else
  # E2E가 없으면 핵심 테스트만 실행
  echo "▶ Running critical path tests..."
  npm run test -- --grep "auth\|billing\|dashboard\|login\|signup" 2>/dev/null || {
    echo "⚠ Smoke tests failed"
    exit 1
  }
fi

echo ""
echo "══════════════════════════════════════"
echo "✅ Smoke Test PASSED"
echo "══════════════════════════════════════"
