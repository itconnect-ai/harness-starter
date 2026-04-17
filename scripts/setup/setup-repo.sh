#!/usr/bin/env bash
# ============================================================================
# scripts/setup/setup-repo.sh
#
# 새 프로젝트 GitHub repo 초기 보안 설정을 한 번에 적용합니다.
# 이 template을 복사해 새 프로젝트를 만든 직후 1회 실행.
#
# 설정 항목:
#   1. Secret Scanning + Push Protection 활성화
#   2. main 브랜치 protection (필수 status check + PR 리뷰 + force push 차단)
#   3. develop 브랜치 protection (동일 정책, develop 브랜치 존재 시)
#
# 요구사항: gh CLI 설치 + 'gh auth login' 완료 + 관리자 권한
#
# 사용법:
#   ./scripts/setup/setup-repo.sh                # 기본 설정 적용
#   ./scripts/setup/setup-repo.sh --dry-run      # 무엇을 할지만 표시
# ============================================================================
set -e

DRY_RUN=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      sed -n '2,19p' "$0" | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── 요구사항 확인 ──
if ! command -v gh >/dev/null 2>&1; then
  cat >&2 <<EOF
ERROR: gh CLI 필요.

설치: https://cli.github.com
  macOS:   brew install gh
  Windows: winget install GitHub.cli
  Linux:   https://github.com/cli/cli/blob/trunk/docs/install_linux.md
EOF
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh 인증 필요. 'gh auth login' 실행 후 재시도." >&2
  exit 1
fi

# ── repo 식별 ──
REPO=$(gh repo view --json owner,name -q '.owner.login + "/" + .name' 2>/dev/null || true)
if [ -z "$REPO" ]; then
  echo "ERROR: 현재 디렉토리가 GitHub repo가 아니거나 origin이 설정되지 않음." >&2
  exit 1
fi

echo "=== Setting up repository: $REPO ==="
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "[DRY RUN] 실제 변경하지 않음. 아래 단계를 적용 예정:"
  echo "  1. Secret Scanning + Push Protection 활성화"
  echo "  2. main 브랜치 protection 설정"
  echo "  3. develop 브랜치 protection 설정 (브랜치 존재 시)"
  exit 0
fi

# ── 1. Secret Scanning + Push Protection ──
echo "[1/3] Secret Scanning + Push Protection..."
if gh api -X PATCH "/repos/$REPO" \
  -F 'security_and_analysis[secret_scanning][status]=enabled' \
  -F 'security_and_analysis[secret_scanning_push_protection][status]=enabled' \
  >/dev/null 2>&1; then
  echo "  ✓ enabled"
else
  echo "  ⚠ 활성화 실패 (private repo는 GitHub Enterprise 또는 GHAS 라이선스 필요)"
fi

# ── 2. main branch protection ──
echo ""
echo "[2/3] main 브랜치 protection..."
# 임시 JSON 파일 생성 (here-doc을 stdin으로 전달하면 Windows Git Bash에서 문제 가능)
PROTECTION_MAIN=$(mktemp)
cat > "$PROTECTION_MAIN" <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["quality-gate", "gitleaks", "codeql"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF

if gh api -X PUT "/repos/$REPO/branches/main/protection" --input "$PROTECTION_MAIN" >/dev/null 2>&1; then
  echo "  ✓ applied"
else
  echo "  ⚠ 설정 실패 — main 브랜치가 없거나 권한 부족"
fi
rm -f "$PROTECTION_MAIN"

# ── 3. develop branch protection (optional) ──
echo ""
echo "[3/3] develop 브랜치 protection..."
if gh api "/repos/$REPO/branches/develop" >/dev/null 2>&1; then
  PROTECTION_DEV=$(mktemp)
  cat > "$PROTECTION_DEV" <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["quality-gate", "gitleaks", "codeql"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF

  if gh api -X PUT "/repos/$REPO/branches/develop/protection" --input "$PROTECTION_DEV" >/dev/null 2>&1; then
    echo "  ✓ applied"
  else
    echo "  ⚠ 설정 실패"
  fi
  rm -f "$PROTECTION_DEV"
else
  echo "  ⏭ develop 브랜치 없음 — skip (나중에 develop 생성 후 이 스크립트 재실행)"
fi

echo ""
echo "=== 완료 ==="
echo ""
echo "확인 방법:"
echo "  https://github.com/$REPO/settings/branches"
echo "  https://github.com/$REPO/settings/security_analysis"
echo ""
echo "주의: 'quality-gate', 'gitleaks', 'codeql'은 각 workflow의 job 이름입니다."
echo "      첫 실행 시 status check이 '대기 중'으로 표시될 수 있으며,"
echo "      workflow 1회 실행 후 정상 인식됩니다."
