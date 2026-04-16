#!/usr/bin/env bash
# ============================================================================
# scripts/docker-guard.sh
#
# Docker 작업 시작 전/후에 호출하는 안전 검증 스크립트.
# 목적:
#   1. 현재 작업 디렉토리의 compose 파일에서 환경 라벨/프로젝트명을 읽어
#      사용자가 의도한 환경(dev/prod)과 일치하는지 확인
#   2. 같은 접두사로 이미 떠 있는 컨테이너/네트워크/볼륨을 조회해
#      중복 생성을 사전 차단 (docker-rules.md §3 자동화)
#   3. 허용 목록(docker-rules.md §1-2) 외 컨테이너 발견 시 경고
#
# 사용법:
#   ./scripts/docker-guard.sh                                      # 기본 검증
#   ./scripts/docker-guard.sh --prefix myapp                       # 접두사 지정
#   ./scripts/docker-guard.sh --env production                     # 의도 환경 지정
#   ./scripts/docker-guard.sh --compose docker-compose.dev.yml     # compose 파일 지정
#   ./scripts/docker-guard.sh --prefix myapp --env production --strict   # 위반 시 exit 1
#
# 종료코드:
#   0 = 안전 (진행 가능)
#   1 = 위반 감지 (--strict 모드) 또는 compose 파싱 실패
#   2 = 사용자 의도와 compose 환경 라벨 불일치
# ============================================================================
set -e

PREFIX=""
EXPECTED_ENV=""
COMPOSE_FILE=""
STRICT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --env) EXPECTED_ENV="$2"; shift 2 ;;
    --compose) COMPOSE_FILE="$2"; shift 2 ;;
    --strict) STRICT=true; shift ;;
    -h|--help)
      sed -n '2,24p' "$0" | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── compose 파일 자동 탐색 ──
if [ -z "$COMPOSE_FILE" ]; then
  for candidate in docker-compose.yml compose.yml docker-compose.dev.yml compose.dev.yml; do
    if [ -f "$candidate" ]; then
      COMPOSE_FILE="$candidate"
      break
    fi
  done
fi

echo "=== Docker Guard ==="
if [ -n "$COMPOSE_FILE" ] && [ -f "$COMPOSE_FILE" ]; then
  echo "Compose file: $COMPOSE_FILE"
else
  echo "Compose file: (not found in current directory)"
fi

# ── compose 파일에서 name / x-environment 파싱 ──
COMPOSE_NAME=""
COMPOSE_ENV=""
if [ -n "$COMPOSE_FILE" ] && [ -f "$COMPOSE_FILE" ]; then
  # 최상단 name: 값 추출 (첫 매치만)
  COMPOSE_NAME=$(grep -m1 -E '^name:' "$COMPOSE_FILE" 2>/dev/null | sed 's/^name:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d '"'"'" || true)
  # x-environment: 값 추출
  COMPOSE_ENV=$(grep -m1 -E '^x-environment:' "$COMPOSE_FILE" 2>/dev/null | sed 's/^x-environment:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d '"'"'" || true)

  echo "  name: ${COMPOSE_NAME:-<unset>}"
  echo "  x-environment: ${COMPOSE_ENV:-<unset>}"
fi

# ── 접두사 자동 추출: compose name에서 -dev 제거 ──
if [ -z "$PREFIX" ] && [ -n "$COMPOSE_NAME" ]; then
  PREFIX=$(echo "$COMPOSE_NAME" | sed 's/-dev$//; s/-staging$//')
fi

# ── 환경 의도 검증 ──
VIOLATIONS=0

if [ -n "$EXPECTED_ENV" ] && [ -n "$COMPOSE_ENV" ]; then
  if [ "$EXPECTED_ENV" != "$COMPOSE_ENV" ]; then
    echo "" >&2
    echo "✗ ENVIRONMENT MISMATCH" >&2
    echo "  Expected (--env):       $EXPECTED_ENV" >&2
    echo "  Compose x-environment:  $COMPOSE_ENV" >&2
    echo "" >&2
    echo "  If this is intentional (e.g., editing compose for another env)," >&2
    echo "  omit --env or specify the matching value." >&2
    exit 2
  fi
fi

# compose name에 -dev 접미사가 있는데 env가 production인 경우 경고
if [ -n "$COMPOSE_NAME" ]; then
  case "$COMPOSE_NAME" in
    *-dev|*-staging)
      if [ "$COMPOSE_ENV" = "production" ]; then
        echo "✗ compose name suggests dev/staging but x-environment=production" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
      ;;
    *)
      if [ "$COMPOSE_ENV" = "development" ] || [ "$COMPOSE_ENV" = "staging" ]; then
        echo "✗ compose name suggests production but x-environment=$COMPOSE_ENV" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
      ;;
  esac
fi

# ── 접두사 없으면 여기서 종료 ──
if [ -z "$PREFIX" ]; then
  echo ""
  echo "No prefix determined — skipping container/network/volume scan."
  echo "Pass --prefix <name> or ensure compose file has 'name:' field."
  exit 0
fi

echo ""
echo "Prefix: $PREFIX"
echo ""

# ── docker CLI 존재 확인 ──
if ! command -v docker >/dev/null 2>&1; then
  echo "⚠ docker CLI not found — skipping runtime scan."
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  echo "⚠ docker daemon not running — skipping runtime scan."
  exit 0
fi

# ── 컨테이너 조회 ──
echo "=== Containers matching '$PREFIX' ==="
CONTAINERS=$(docker ps -a --filter "name=$PREFIX" --format "{{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null || true)
if [ -z "$CONTAINERS" ]; then
  echo "  (none)"
else
  echo "$CONTAINERS" | while IFS=$'\t' read -r name image status; do
    echo "  $name | $image | $status"
  done

  # 허용 목록 외 컨테이너 검사 (docker-rules.md §1-2 기본 역할)
  ALLOWED_ROLES='^('"$PREFIX"'(-dev|-staging)?-(frontend|backend|gateway|db|redis|minio|auth|project|guide|file|qdrant|nginx))$'
  while IFS=$'\t' read -r name _ _; do
    [ -z "$name" ] && continue
    if ! echo "$name" | grep -qE "$ALLOWED_ROLES"; then
      # 조직 포트 레지스트리 확장 서비스일 수 있으므로 WARN만
      echo "  ⚠ '$name' is not in default allowed roles — verify against docker-port-registry.md" >&2
    fi
    # 금지 패턴 검사
    if echo "$name" | grep -qE "(-1$|-2$|-3$|-new$|-old$|_backend$|_db$|-api-server$|-server$)"; then
      echo "  ✗ '$name' matches forbidden pattern (numbered/new/old/underscore variant)" >&2
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done <<< "$CONTAINERS"
fi

# ── 네트워크 조회 ──
echo ""
echo "=== Networks matching '$PREFIX' ==="
NETWORKS=$(docker network ls --filter "name=$PREFIX" --format "{{.Name}}" 2>/dev/null || true)
if [ -z "$NETWORKS" ]; then
  echo "  (none)"
else
  echo "$NETWORKS" | sed 's/^/  /'
fi

# ── 볼륨 조회 ──
echo ""
echo "=== Volumes matching '$PREFIX' ==="
VOLUMES=$(docker volume ls --filter "name=$PREFIX" --format "{{.Name}}" 2>/dev/null || true)
if [ -z "$VOLUMES" ]; then
  echo "  (none)"
else
  echo "$VOLUMES" | sed 's/^/  /'
fi

# ── 최종 판정 ──
echo ""
echo "=== Result ==="
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "✗ $VIOLATIONS violation(s) detected"
  echo "  See docs/agents/docker-rules.md for naming standards"
  if [ "$STRICT" = true ]; then
    exit 1
  fi
else
  echo "✓ no violations detected"
fi

exit 0
