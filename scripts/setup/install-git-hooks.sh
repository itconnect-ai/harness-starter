#!/usr/bin/env bash
# ============================================================================
# scripts/setup/install-git-hooks.sh
#
# .githooks/ 디렉토리의 git hook을 활성화합니다.
# 템플릿이 다른 프로젝트로 복사된 후 한 번 실행하면 됩니다.
#
# 활성화 방식: git core.hooksPath 설정 (husky 등 npm 의존성 불필요)
# 비활성화: git config --unset core.hooksPath
# ============================================================================
set -e

# repo 루트로 이동
cd "$(git rev-parse --show-toplevel)"

if [ ! -d .githooks ]; then
  echo "ERROR: .githooks/ 디렉토리가 없습니다." >&2
  echo "이 스크립트는 template 원본에서만 동작합니다." >&2
  exit 1
fi

# core.hooksPath 설정
git config core.hooksPath .githooks

# 실행 권한 부여 (Windows에서는 무시됨)
chmod +x .githooks/* 2>/dev/null || true

echo "Git hooks installed:"
echo "  - pre-commit: staged 파일 eslint + .env 차단 + 대형 커밋 경고"
echo "  - commit-msg: Conventional Commits 형식 검증"
echo ""
echo "비활성화: git config --unset core.hooksPath"
