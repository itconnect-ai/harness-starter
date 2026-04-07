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

echo "======================================"
echo " Validation Start"
echo "======================================"

# ── 1. 의존성 설치 ──
echo ""
echo "[1/7] Install dependencies..."
npm install --prefer-offline || {
  echo "FAIL: npm install failed"
  exit 1
}

# ── 2. 타입 체크 ──
echo ""
echo "[2/7] Type check..."
npm run typecheck 2>&1 || npx tsc --noEmit 2>&1 || {
  echo "FAIL: Type check failed"
  exit 1
}

# ── 3. 린트 ──
echo ""
echo "[3/7] Lint..."
npm run lint 2>&1 || {
  echo "FAIL: Lint failed"
  exit 1
}

# ── 4a. 테스트 ──
echo ""
echo "[4a/8] Tests..."
npm run test 2>&1 || {
  echo "FAIL: Tests failed"
  exit 1
}

# ── 4b. Regression 테스트 (Phase C에서 생성된 재현 테스트) ──
if [ -d "tests/regression" ] && [ "$(ls -A tests/regression/ 2>/dev/null)" ]; then
  echo ""
  echo "[4b/8] Regression tests..."
  npx vitest run tests/regression/ 2>&1 || \
  npx jest --testPathPattern=tests/regression/ 2>&1 || \
  npm run test -- --testPathPattern=regression 2>&1 || {
    echo "FAIL: Regression tests failed"
    exit 1
  }
  echo "Regression tests: PASSED"
else
  echo "[4b/8] Regression tests: skipped (no tests/regression/ found)"
fi

# ── 5. 빌드 ──
echo ""
echo "[5/8] Build..."
npm run build 2>&1 || {
  echo "FAIL: Build failed"
  exit 1
}

# ── 6. 보안 체크 ──
echo ""
echo "[6/8] Security checks..."
SECURITY_WARNINGS=0

# 하드코딩된 시크릿 패턴 감지
if grep -rn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  -iE "(api[_-]?key|secret|password|token)\s*[:=]\s*['\"][a-zA-Z0-9]{8,}" src/ 2>/dev/null | \
  grep -v "process\.env\|\.env\.\|\.example\|test\|mock\|fake\|dummy" ; then
  echo "WARNING: Possible hardcoded secret detected in source code"
  SECURITY_WARNINGS=$((SECURITY_WARNINGS+1))
fi

# .env 파일이 git에 추가되었는지
if git diff --cached --name-only 2>/dev/null | grep -E "^\.env(\.\w+)?$" | grep -v "\.example" ; then
  echo "WARNING: .env file staged for commit"
  SECURITY_WARNINGS=$((SECURITY_WARNINGS+1))
fi

# docker-compose down -v 패턴 (DB 데이터 삭제 위험)
if grep -rn "down -v\|down --volumes" scripts/ 2>/dev/null; then
  echo "WARNING: 'docker-compose down -v' found in scripts (destroys DB data)"
  SECURITY_WARNINGS=$((SECURITY_WARNINGS+1))
fi

if [ $SECURITY_WARNINGS -gt 0 ]; then
  echo "Security check: $SECURITY_WARNINGS warning(s) found"
else
  echo "Security check: PASSED"
fi

# ── 7. 성능 체크 ──
echo ""
echo "[7/8] Performance checks..."
PERF_WARNINGS=0

# 바운드 없는 findMany() 감지
if grep -rn "findMany()" src/ --include="*.ts" 2>/dev/null | grep -v "take:\|limit:\|where:" ; then
  echo "WARNING: findMany() without take/limit may return unbounded results"
  PERF_WARNINGS=$((PERF_WARNINGS+1))
fi

# 전체 lodash import 감지
if grep -rn "from 'lodash'" src/ --include="*.ts" --include="*.tsx" 2>/dev/null | grep -v "lodash/" ; then
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

# ── 8. Blocking 체크 (Phase C에서 승격된 패턴) ──
# Phase C 회고에서 3회+ 반복된 패턴은 여기에 blocking check로 추가합니다.
# 아래 BLOCKING_ERRORS 카운터가 0이 아니면 validate가 실패합니다.
echo ""
echo "[8/8] Blocking checks (promoted from Phase C)..."
BLOCKING_ERRORS=0

# ── Phase C 승격 패턴은 아래에 추가 ──
# 예시 (승격 시 주석 해제하고 패턴에 맞게 수정):
# if grep -rn "하드코딩패턴" src/ --include="*.ts" 2>/dev/null; then
#   echo "BLOCKED: [incident-id] 설명"
#   BLOCKING_ERRORS=$((BLOCKING_ERRORS+1))
# fi

if [ $BLOCKING_ERRORS -gt 0 ]; then
  echo "Blocking check: $BLOCKING_ERRORS error(s) — FAIL"
  exit 1
else
  echo "Blocking check: PASSED (no promoted patterns)"
fi

echo ""
echo "======================================"
echo " Validation PASSED"
echo "======================================"
