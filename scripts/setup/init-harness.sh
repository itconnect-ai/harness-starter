#!/usr/bin/env bash
# ============================================================================
# scripts/setup/init-harness.sh
#
# 하네스 자동 초기화 — template 복사 후 1회 실행.
# install-git-hooks.sh + setup-repo.sh를 순차 실행합니다.
#
# 실행 가능한 단계만 자동 진행하고, 전제 조건이 안 된 단계는
# 명시 skip + 추후 수동 실행 안내. 에러로 중단되지 않습니다.
#
# 전제 조건:
#   - git repo 내부에서 실행 (git rev-parse 통과)
#
# 선택 조건 (있으면 더 많이 자동 처리):
#   - gh CLI 설치 + gh auth login 완료 → GitHub 보안 설정까지 자동
#   - git remote origin 설정됨        → branch protection까지 자동
#
# 사용법:
#   ./scripts/setup/init-harness.sh            # 자동 실행
#   ./scripts/setup/init-harness.sh --dry-run  # 무엇을 할지만 표시
#
# 멱등성: 여러 번 실행해도 안전. 이미 설정된 것은 덮어쓰거나 skip.
# ============================================================================
set -e

DRY_RUN=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      sed -n '2,23p' "$0" | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# git repo 내부인지 확인
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: git repo 아님. 'git init' 또는 git clone 후 실행하세요." >&2
  exit 1
fi

cd "$(git rev-parse --show-toplevel)"

echo "=== 하네스 자동 초기화 ==="
if [ "$DRY_RUN" = true ]; then
  echo "(dry-run 모드 — 실제 변경하지 않음)"
fi
echo ""

# ── [1/2] Git hooks 설치 (항상 실행 가능) ──
echo "[1/2] Git hooks 설치"
if [ ! -x scripts/setup/install-git-hooks.sh ]; then
  echo "  ⚠ scripts/setup/install-git-hooks.sh 없음 — skip"
elif [ "$DRY_RUN" = true ]; then
  echo "  [DRY RUN] ./scripts/setup/install-git-hooks.sh 실행 예정"
else
  if ./scripts/setup/install-git-hooks.sh 2>&1 | sed 's/^/  /'; then
    echo "  ✓ hooks 활성화"
  else
    echo "  ⚠ hooks 설정 실패 — 위 로그 확인"
  fi
fi

# ── [2/2] GitHub repo 보안 설정 (전제 조건 충족 시만) ──
echo ""
echo "[2/2] GitHub repo 보안 설정"

SKIP_REASON=""

if ! command -v gh >/dev/null 2>&1; then
  SKIP_REASON="gh CLI 미설치"
elif ! gh auth status >/dev/null 2>&1; then
  SKIP_REASON="gh 인증 미완료 ('gh auth login' 필요)"
elif ! git remote get-url origin >/dev/null 2>&1; then
  SKIP_REASON="git origin 미설정 (GitHub repo 생성 + 'git remote add origin' 필요)"
fi

if [ -n "$SKIP_REASON" ]; then
  echo "  ⏭ SKIP — $SKIP_REASON"
  echo ""
  echo "  전제 조건 충족 후 수동 실행:"
  echo "    ./scripts/setup/setup-repo.sh"
elif [ ! -x scripts/setup/setup-repo.sh ]; then
  echo "  ⚠ scripts/setup/setup-repo.sh 없음 — skip"
elif [ "$DRY_RUN" = true ]; then
  echo "  [DRY RUN] ./scripts/setup/setup-repo.sh --dry-run 호출..."
  echo ""
  ./scripts/setup/setup-repo.sh --dry-run 2>&1 | sed 's/^/  /' || true
else
  if ./scripts/setup/setup-repo.sh 2>&1 | sed 's/^/  /'; then
    echo "  ✓ repo 보안 설정 완료"
  else
    echo "  ⚠ 일부 설정 실패 — 위 로그 확인. private repo는 GHAS 라이선스 필요할 수 있음"
  fi
fi

echo ""
echo "=== 하네스 초기화 완료 ==="
echo ""
echo "다음 단계:"
echo "  1. BMAD 산출물 확인: _bmad-output/planning-artifacts/"
echo "  2. BMAD 스킬 확인:   .agents/skills + .claude/skills"
echo "  3. 프로젝트 초기화:  README.md의 Setup 1/2 프롬프트 실행"
