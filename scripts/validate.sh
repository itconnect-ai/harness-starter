#!/usr/bin/env bash
# ============================================================================
# scripts/validate.sh
#
# 모든 에이전트가 작업 완료 전 실행하는 공통 검증 스크립트입니다.
# 프로젝트의 기술 스택에 맞게 명령을 수정하세요.
#
# 사용법: ./scripts/validate.sh
# 종료코드: 0 = 성공, 1 = 실패
# ============================================================================
set -e

echo "══════════════════════════════════════"
echo "▶ Validation Start"
echo "══════════════════════════════════════"

# ── 1. 의존성 설치 ──
echo ""
echo "▶ [1/5] Install dependencies..."
npm install --silent 2>/dev/null || {
  echo "⚠ npm install failed"
  exit 1
}

# ── 2. 타입 체크 ──
echo ""
echo "▶ [2/5] Type check..."
npm run typecheck 2>/dev/null || npx tsc --noEmit 2>/dev/null || {
  echo "⚠ Type check failed"
  exit 1
}

# ── 3. 린트 ──
echo ""
echo "▶ [3/5] Lint..."
npm run lint 2>/dev/null || {
  echo "⚠ Lint failed"
  exit 1
}

# ── 4. 테스트 ──
echo ""
echo "▶ [4/5] Tests..."
npm run test 2>/dev/null || {
  echo "⚠ Tests failed"
  exit 1
}

# ── 5. 빌드 ──
echo ""
echo "▶ [5/5] Build..."
npm run build 2>/dev/null || {
  echo "⚠ Build failed"
  exit 1
}

echo ""
echo "══════════════════════════════════════"
echo "✅ Validation PASSED"
echo "══════════════════════════════════════"
