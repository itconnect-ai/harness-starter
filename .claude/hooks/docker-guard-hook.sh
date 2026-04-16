#!/usr/bin/env bash
# ============================================================================
# .claude/hooks/docker-guard-hook.sh
#
# PreToolUse hook: AI가 Bash로 'docker compose up/down/restart/run' 또는
# 'prisma migrate deploy', 'flyway migrate' 등을 호출하면, 먼저 권장 래퍼
# 사용을 안내하고, 일반 'docker compose' 명령이면 guard 스크립트를 실행.
#
# 차단 정책 (exit code):
#   0 = 통과 (정보만 출력)
#   2 = 차단 (위험 명령 직접 호출 감지 시)
#
# 대상 명령:
#   - 'docker compose' 계열 (up/down/restart/run/build) → guard 실행
#   - 'prisma migrate deploy' / 'flyway migrate' / 'alembic upgrade head'
#     → 차단 + db-migrate.sh 래퍼 사용 안내
#
# settings.json에 다음과 같이 등록:
#   "PreToolUse": [{
#     "matcher": "Bash",
#     "hooks": [{
#       "type": "command",
#       "if": "Bash(docker *) || Bash(npx prisma *) || Bash(prisma *) || Bash(flyway *) || Bash(alembic *)",
#       "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/docker-guard-hook.sh"
#     }]
#   }]
# ============================================================================

# stdin에서 JSON 읽기
input=$(cat)

# Bash 명령 추출
cmd=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$cmd" ]; then
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-.}"
cd "$project_dir" || exit 0

# ── 1. 파괴적 마이그레이션 직접 호출 차단 ──
if echo "$cmd" | grep -qE '(prisma migrate deploy|prisma db push|flyway migrate|alembic upgrade)'; then
  cat >&2 <<EOF

✗ BLOCKED: 마이그레이션 명령을 직접 호출하지 마세요.

감지된 명령:
  $cmd

대신 안전 래퍼를 사용하세요:

  ./scripts/db-migrate.sh --cmd "$cmd"

래퍼가 자동으로:
  1. 환경(dev/prod)을 docker-guard로 검증
  2. 마이그레이션 직전 pg_dump로 백업
  3. 실패 시 복원 명령 출력
을 수행합니다.

상세: docs/agents/migration-rules.md

우회가 반드시 필요하면 사용자에게 명시적 승인을 받으세요.
EOF
  exit 2
fi

# ── 2. docker compose down -v 차단 (볼륨 삭제로 데이터 유실) ──
if echo "$cmd" | grep -qE 'docker (compose |-compose )?(down[[:space:]]+-v|down[[:space:]]+--volumes)'; then
  cat >&2 <<EOF

✗ BLOCKED: 'docker compose down -v' 는 볼륨을 삭제하여 DB 데이터가 영구 소실됩니다.

감지된 명령:
  $cmd

허용되는 대체 명령:
  docker compose down         # 컨테이너만 정리 (볼륨 유지)
  docker compose stop         # 정지만

데이터 초기화가 정말 필요하면 사용자에게 명시 승인을 받으세요.
상세: docs/agents/docker-rules.md, docs/agents/migration-rules.md §4-4
EOF
  exit 2
fi

# ── 3. docker compose up/restart/build는 guard 정보 출력 ──
if echo "$cmd" | grep -qE 'docker (compose |-compose )?(up|restart|build|run)'; then
  if [ -x scripts/docker-guard.sh ]; then
    echo "" >&2
    echo "ℹ Running docker-guard.sh before '$cmd'..." >&2
    # 정보성 출력 — 차단하지 않음
    ./scripts/docker-guard.sh 2>&1 | sed 's/^/  /' >&2 || true
    echo "" >&2
    echo "(위반이 감지되어도 이 hook은 차단하지 않습니다. --strict 실행은 AI 책임)" >&2
  fi
fi

exit 0
