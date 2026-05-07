#!/usr/bin/env bash
# ============================================================================
# scripts/install.sh
#
# Harness Engineering Starter Kit의 **필수 파일만** 다른 프로젝트에 설치.
# 전체 clone 대신 이 스크립트로 받으면:
#   - BMAD 스킬 디렉토리(.agents/skills, .claude/skills)는 제외 → 기존 설치 사용
#   - docs/changelog/ 등 template 전용 파일 제외
#   - 파일 수 ~2,400개 → ~250개로 축소
#   - 다른 프로젝트 소스코드와 충돌 위험 최소화
#
# 원격 1줄 실행 (target 프로젝트 루트에서):
#   curl -fsSL https://raw.githubusercontent.com/itconnect-ai/harness-starter/main/scripts/install.sh | bash
#
# 또는 먼저 다운로드 후 확인:
#   curl -fsSL https://raw.githubusercontent.com/itconnect-ai/harness-starter/main/scripts/install.sh -o install.sh
#   bash install.sh --dry-run        # 무엇을 설치할지만 표시
#   bash install.sh                  # 실제 설치 (기존 파일은 skip)
#   bash install.sh --force          # 기존 파일 덮어쓰기
#   bash install.sh --branch develop # 특정 브랜치에서 설치
#
# 환경변수:
#   HARNESS_TEMPLATE_REPO  기본 itconnect-ai/harness-starter
#   HARNESS_BRANCH         기본 main
#   HARNESS_TARGET         기본 $PWD
#
# 설치 후 다음 단계:
#   1. ./scripts/setup/init-harness.sh  # git hooks + GitHub 보안 설정
#   2. README.md Setup 1/2 프롬프트 실행 # 프로젝트 초기화
# ============================================================================
set -e

REPO="${HARNESS_TEMPLATE_REPO:-itconnect-ai/harness-starter}"
BRANCH="${HARNESS_BRANCH:-main}"
TARGET="${HARNESS_TARGET:-$PWD}"
DRY_RUN=false
FORCE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,36p' "$0" | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── 필수 경로 매니페스트 ──
# 파일 또는 디렉토리. 디렉토리는 재귀 복사.
# 제외 대상: .agents/skills, .claude/skills, docs/changelog, private/(README만),
#            _bmad-output, plans/(README만), reviews/(README만) 등
ESSENTIAL_PATHS=(
  # 최상위 문서
  "CLAUDE.md"
  "AGENTS.md"
  "REVIEW.md"
  "README-brownfield.md"
  # Git·GitHub 설정
  ".gitattributes"
  ".gitleaks.toml"
  # 규칙 문서
  "docs/agents"
  "docs/checklists"
  "docs/future-upgrades"
  "docs/decisions/README.md"
  "docs/org/docker-port-registry.template.md"
  # 템플릿
  "templates"
  # 스크립트 (전체)
  "scripts"
  # Claude Code hooks + 설정 (skills는 제외)
  ".claude/hooks"
  ".claude/settings.json"
  # Git hooks
  ".githooks"
  # GitHub Actions + Dependabot
  ".github/workflows"
  ".github/dependabot.yml"
  # 상태·피드백·리뷰·plans 템플릿만 (실제 데이터 제외)
  "state/learning-loop.json"
  "state/progress-template.json"
  "state/README.md"
  "feedback/incident-template.yaml"
  "feedback/incidents/README.md"
  "reviews/README.md"
  "plans/README.md"
  # private/ 폴더 용도 설명 (실제 내부 정보는 각 프로젝트에서 채움)
  "private/README.md"
)

# ── 의존성 확인 ──
if ! command -v tar >/dev/null 2>&1; then
  echo "ERROR: tar 필요" >&2
  exit 1
fi

DOWNLOADER=""
if command -v curl >/dev/null 2>&1; then
  DOWNLOADER="curl"
elif command -v wget >/dev/null 2>&1; then
  DOWNLOADER="wget"
else
  echo "ERROR: curl 또는 wget 필요" >&2
  exit 1
fi

# ── 시작 ──
echo "=============================================="
echo " Harness Engineering Starter — 필수 파일 설치"
echo "=============================================="
echo "  Template: github.com/$REPO@$BRANCH"
echo "  Target:   $TARGET"
if [ "$DRY_RUN" = true ]; then
  echo "  Mode:     DRY RUN"
fi
if [ "$FORCE" = true ]; then
  echo "  Force:    기존 파일 덮어쓰기"
fi
echo ""

if [ ! -d "$TARGET" ]; then
  echo "ERROR: target 디렉토리 없음: $TARGET" >&2
  exit 1
fi

# ── 임시 디렉토리 ──
TEMP=$(mktemp -d)
cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT

# ── tarball 다운로드 ──
URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"
echo "[1/3] Downloading tarball..."
echo "      $URL"

if [ "$DOWNLOADER" = "curl" ]; then
  if ! curl -fsSL "$URL" -o "$TEMP/template.tar.gz"; then
    echo "ERROR: 다운로드 실패 — repo/branch 확인" >&2
    exit 1
  fi
else
  if ! wget -q -O "$TEMP/template.tar.gz" "$URL"; then
    echo "ERROR: 다운로드 실패 — repo/branch 확인" >&2
    exit 1
  fi
fi

# ── 압축 해제 ──
echo "[2/3] Extracting..."
tar -xzf "$TEMP/template.tar.gz" -C "$TEMP"

SRC=$(find "$TEMP" -maxdepth 1 -mindepth 1 -type d | head -1)
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "ERROR: tarball 구조 예상과 다름" >&2
  exit 1
fi

# ── 복사 ──
echo "[3/3] Installing files..."
echo ""

COPIED=0
SKIPPED_EXISTS=0
SKIPPED_MISSING=0
OVERWROTE=0

for path in "${ESSENTIAL_PATHS[@]}"; do
  SRC_PATH="$SRC/$path"
  DEST_PATH="$TARGET/$path"

  if [ ! -e "$SRC_PATH" ]; then
    echo "  ⚠ source missing: $path"
    SKIPPED_MISSING=$((SKIPPED_MISSING + 1))
    continue
  fi

  if [ -e "$DEST_PATH" ] && [ "$FORCE" = false ]; then
    echo "  ⏭ exists, skip (use --force to overwrite): $path"
    SKIPPED_EXISTS=$((SKIPPED_EXISTS + 1))
    continue
  fi

  EXISTED_BEFORE=false
  [ -e "$DEST_PATH" ] && EXISTED_BEFORE=true

  if [ "$DRY_RUN" = true ]; then
    if [ "$EXISTED_BEFORE" = true ]; then
      echo "  [DRY RUN] overwrite: $path"
    else
      echo "  [DRY RUN] copy:      $path"
    fi
  else
    mkdir -p "$(dirname "$DEST_PATH")"
    # 디렉토리면 재귀 복사, 파일이면 직접
    if [ -d "$SRC_PATH" ]; then
      rm -rf "$DEST_PATH"  # 디렉토리는 깨끗이 교체
      cp -r "$SRC_PATH" "$DEST_PATH"
    else
      cp "$SRC_PATH" "$DEST_PATH"
    fi
    if [ "$EXISTED_BEFORE" = true ]; then
      echo "  ✓ $path (overwritten)"
      OVERWROTE=$((OVERWROTE + 1))
    else
      echo "  ✓ $path"
    fi
  fi
  COPIED=$((COPIED + 1))
done

# ── 실행 권한 복원 (shell 스크립트) ──
if [ "$DRY_RUN" = false ] && [ "$COPIED" -gt 0 ]; then
  find "$TARGET/scripts" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
  find "$TARGET/.claude/hooks" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
  find "$TARGET/.githooks" -type f -exec chmod +x {} \; 2>/dev/null || true
fi

# ── 요약 ──
echo ""
echo "=============================================="
echo " 완료"
echo "=============================================="
echo "  copied:            $COPIED"
echo "  overwrote:         $OVERWROTE"
echo "  skipped (exists):  $SKIPPED_EXISTS"
echo "  skipped (missing): $SKIPPED_MISSING"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN 완료. 실제 설치하려면 --dry-run 제거."
elif [ "$COPIED" -gt 0 ]; then
  echo "다음 단계:"
  echo "  1. ./scripts/setup/init-harness.sh"
  echo "     (git hooks + GitHub 보안 설정 자동화)"
  echo ""
  echo "  2. README.md Setup 1/2 프롬프트를 Claude Code에서 실행"
  echo "     (프로젝트 초기화 + 하네스 커스터마이징)"
fi
