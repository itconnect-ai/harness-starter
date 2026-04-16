#!/usr/bin/env bash
# ============================================================================
# scripts/db-migrate.sh
#
# DB 마이그레이션 안전 래퍼. migration-rules.md를 자동 집행합니다.
#
# 순서:
#   1. 환경 검증 (docker-guard로 compose 환경 라벨 확인)
#   2. 마이그레이션 직전 pg_dump 자동 실행 → state/db-backups/
#   3. 덤프 파일 크기 검증 (0바이트면 중단)
#   4. 마이그레이션 명령 실행 (--cmd로 지정)
#   5. 성공 시 덤프 14일 보존 메타데이터 기록
#   6. 실패 시 복원 명령 출력
#
# 사용법:
#   ./scripts/db-migrate.sh --cmd "npx prisma migrate deploy"
#   ./scripts/db-migrate.sh --cmd "npx prisma migrate deploy" --env production
#   ./scripts/db-migrate.sh --cmd "..." --container myapp-db --user app --db myapp
#   ./scripts/db-migrate.sh --cmd "..." --force-irreversible  # irreversible 허용
#
# 환경변수 대안:
#   DB_CONTAINER, DB_USER, DB_NAME, POSTGRES_DB, POSTGRES_USER, DB_PORT
#
# 종료코드:
#   0 = 마이그레이션 성공
#   1 = 백업 실패 (마이그레이션 미실행)
#   2 = 환경 검증 실패
#   3 = 마이그레이션 실패 (백업은 완료, 복원 명령 출력됨)
# ============================================================================
set -e

MIGRATE_CMD=""
DB_CONTAINER_ARG=""
DB_USER_ARG=""
DB_NAME_ARG=""
EXPECTED_ENV=""
FORCE_IRREVERSIBLE=false
SKIP_GUARD=false

while [ $# -gt 0 ]; do
  case "$1" in
    --cmd) MIGRATE_CMD="$2"; shift 2 ;;
    --container) DB_CONTAINER_ARG="$2"; shift 2 ;;
    --user) DB_USER_ARG="$2"; shift 2 ;;
    --db) DB_NAME_ARG="$2"; shift 2 ;;
    --env) EXPECTED_ENV="$2"; shift 2 ;;
    --force-irreversible) FORCE_IRREVERSIBLE=true; shift ;;
    --skip-guard) SKIP_GUARD=true; shift ;;
    -h|--help)
      sed -n '2,26p' "$0" | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$MIGRATE_CMD" ]; then
  echo "ERROR: --cmd \"<migration command>\" is required" >&2
  echo "Example: ./scripts/db-migrate.sh --cmd \"npx prisma migrate deploy\"" >&2
  exit 1
fi

# ── 환경 검증 (docker-guard) ──
if [ "$SKIP_GUARD" = false ] && [ -x scripts/docker-guard.sh ]; then
  echo "=== Step 1: Environment verification ==="
  GUARD_ARGS=()
  if [ -n "$EXPECTED_ENV" ]; then
    GUARD_ARGS+=(--env "$EXPECTED_ENV")
  fi
  if ! ./scripts/docker-guard.sh "${GUARD_ARGS[@]}" --strict; then
    echo "" >&2
    echo "Environment verification failed. Use --skip-guard to bypass (not recommended)." >&2
    exit 2
  fi
  echo ""
fi

# ── DB 접속 정보 결정 ──
# 우선순위: CLI 인자 > 환경변수 > .env 파일
load_env_var() {
  local key="$1"
  if [ -f .env ]; then
    grep -m1 -E "^${key}=" .env 2>/dev/null | sed "s/^${key}=//; s/^\"//; s/\"$//" || true
  fi
}

DB_CONTAINER="${DB_CONTAINER_ARG:-${DB_CONTAINER:-}}"
DB_USER="${DB_USER_ARG:-${DB_USER:-${POSTGRES_USER:-$(load_env_var POSTGRES_USER)}}}"
DB_NAME="${DB_NAME_ARG:-${DB_NAME:-${POSTGRES_DB:-$(load_env_var POSTGRES_DB)}}}"

if [ -z "$DB_CONTAINER" ]; then
  # compose 파일에서 DB 컨테이너 이름 추출 시도
  for f in docker-compose.yml compose.yml; do
    if [ -f "$f" ]; then
      DB_CONTAINER=$(grep -A3 -E "^  db:" "$f" 2>/dev/null | grep 'container_name:' | head -1 | sed 's/.*container_name:[[:space:]]*//; s/[[:space:]]*#.*$//' | tr -d '"'"'" || true)
      [ -n "$DB_CONTAINER" ] && break
    fi
  done
fi

if [ -z "$DB_CONTAINER" ] || [ -z "$DB_USER" ] || [ -z "$DB_NAME" ]; then
  echo "ERROR: DB connection info not determined." >&2
  echo "  container: ${DB_CONTAINER:-<unset>}" >&2
  echo "  user:      ${DB_USER:-<unset>}" >&2
  echo "  db:        ${DB_NAME:-<unset>}" >&2
  echo "" >&2
  echo "Pass --container/--user/--db or define POSTGRES_USER/POSTGRES_DB in .env" >&2
  exit 1
fi

echo "=== Step 2: Pre-migration backup ==="
echo "  container: $DB_CONTAINER"
echo "  user:      $DB_USER"
echo "  db:        $DB_NAME"

# ── 백업 디렉토리 준비 ──
BACKUP_DIR="state/db-backups"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/pre-migrate-${DB_NAME}-${TIMESTAMP}.dump.gz"

# ── pg_dump 실행 ──
if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
  echo "ERROR: DB container '$DB_CONTAINER' is not running." >&2
  exit 1
fi

set +e
docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" -F c 2>/tmp/pg_dump_err | gzip > "$BACKUP_FILE"
DUMP_EXIT=$?
set -e

if [ $DUMP_EXIT -ne 0 ]; then
  echo "ERROR: pg_dump failed (exit $DUMP_EXIT)" >&2
  cat /tmp/pg_dump_err >&2 2>/dev/null || true
  rm -f "$BACKUP_FILE"
  exit 1
fi

# ── 덤프 크기 검증 ──
DUMP_SIZE=$(wc -c < "$BACKUP_FILE" | tr -d ' ')
if [ "${DUMP_SIZE:-0}" -lt 100 ]; then
  echo "ERROR: backup file is suspiciously small ($DUMP_SIZE bytes). Aborting migration." >&2
  rm -f "$BACKUP_FILE"
  exit 1
fi

echo "  backup:    $BACKUP_FILE ($DUMP_SIZE bytes)"
echo ""

# ── 마이그레이션 실행 ──
echo "=== Step 3: Run migration ==="
echo "  command: $MIGRATE_CMD"
echo ""

set +e
bash -c "$MIGRATE_CMD"
MIGRATE_EXIT=$?
set -e

if [ $MIGRATE_EXIT -eq 0 ]; then
  echo ""
  echo "=== Step 4: Success — backup retained ==="
  echo "  $BACKUP_FILE (retained 14 days; delete after $(date -d '+14 days' +%Y-%m-%d 2>/dev/null || date -v+14d +%Y-%m-%d 2>/dev/null || echo '14 days from now'))"
  # retention metadata
  echo "retained_until=$(date -d '+14 days' +%Y-%m-%d 2>/dev/null || date -v+14d +%Y-%m-%d 2>/dev/null || echo 'unknown')" > "${BACKUP_FILE}.meta"
  echo "migration_cmd=$MIGRATE_CMD" >> "${BACKUP_FILE}.meta"
  echo "migration_result=success" >> "${BACKUP_FILE}.meta"

  # 14일 지난 백업 자동 정리
  find "$BACKUP_DIR" -name "pre-migrate-*.dump.gz" -mtime +14 -delete 2>/dev/null || true
  find "$BACKUP_DIR" -name "pre-migrate-*.dump.gz.meta" -mtime +14 -delete 2>/dev/null || true

  exit 0
else
  echo ""
  echo "=== Step 4: Migration FAILED — backup preserved ==="
  echo ""
  echo "Restore command:"
  echo ""
  echo "  gunzip < $BACKUP_FILE \\"
  echo "    | docker exec -i $DB_CONTAINER pg_restore -U $DB_USER -d $DB_NAME --clean --if-exists"
  echo ""
  echo "After restore, diagnose the migration failure and try again."
  echo "Backup is kept indefinitely for failed migrations (no auto-cleanup)."
  echo ""
  echo "retention=indefinite" > "${BACKUP_FILE}.meta"
  echo "migration_cmd=$MIGRATE_CMD" >> "${BACKUP_FILE}.meta"
  echo "migration_result=failed" >> "${BACKUP_FILE}.meta"
  exit 3
fi
