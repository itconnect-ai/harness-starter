# docs/agents/backup-rules.md

#

# 데이터베이스 백업 시스템 설계 규칙입니다.

# 모든 프로젝트에 범용 적용할 수 있는 백업 아키텍처를 정의합니다.

# ⚠️ 프로젝트의 DB 종류와 인프라 환경에 맞게 변수를 조정하세요.

## 백업 아키텍처 개요

모든 운영 프로젝트는 다음 4계층 백업 체계를 갖춰야 합니다:

```
┌─────────────────────────────────────────────────────┐
│  1. 일간 자동 백업 (cron)                             │
│     scripts/backup.sh → ~/backups/{DB}_{DATE}.sql.gz │
├─────────────────────────────────────────────────────┤
│  2. 오프사이트 동기화                                  │
│     scripts/offsite-sync.sh → 원격 PC로 rsync 전송    │
├─────────────────────────────────────────────────────┤
│  3. 배포 전 자동 백업 (CI/CD)                          │
│     CI workflow → {DB}_predeploy_{DATE}.sql.gz        │
├─────────────────────────────────────────────────────┤
│  4. 마이그레이션 전 자동 백업 (db-migrate.sh 래퍼)     │
│     → state/db-backups/pre-migrate-{TS}.dump.gz       │
│     실패 시 복원 명령 자동 출력                         │
│     (상세: docs/agents/migration-rules.md)            │
└─────────────────────────────────────────────────────┘
```

각 계층의 역할이 다릅니다:
- 1·2계층은 **일상 재해 복구** (하드웨어 장애, 실수)
- 3계층은 **배포 롤백** (코드 버그로 인한 데이터 오염)
- 4계층은 **스키마 변경 보호** (마이그레이션 실패/데이터 유실) — 가장 빈번, 가장 피하기 쉬운 사고

## 필수 수집 정보

백업 시스템을 구성하기 전에 반드시 다음 정보를 확인합니다:

| 항목               | 설명                  | 예시                                |
| ------------------ | --------------------- | ----------------------------------- |
| `PROJECT_NAME`     | 프로젝트 식별자       | `my_app`                            |
| `DB_TYPE`          | 데이터베이스 종류     | `postgresql`, `mysql`, `mongodb`    |
| `DB_CONTAINER`     | Docker 컨테이너 이름  | `my-app-postgres`                   |
| `DB_USER`          | DB 접속 사용자        | `app_user`                          |
| `DB_NAME`          | 데이터베이스 이름     | `my_app_db`                         |
| `BACKUP_SCHEDULE`  | cron 표현식           | `0 2 * * *` (매일 02:00)            |
| `LOCAL_RETENTION`  | 로컬 보존 일수        | `7`                                 |
| `REMOTE_HOST`      | 오프사이트 백업 PC IP | `192.168.0.31`                      |
| `REMOTE_USER`      | 원격 PC 사용자        | `backup_user`                       |
| `REMOTE_DIR`       | 원격 백업 경로        | `/home/backup_user/offsite-backups` |
| `REMOTE_RETENTION` | 원격 보존 일수        | `30`                                |
| `SSH_KEY_PATH`     | SSH 키 경로           | `~/.ssh/id_offsite`                 |
| `NOTIFY_METHOD`    | 알림 방식             | `discord`, `slack`, `none`          |
| `WEBHOOK_ENV_VAR`  | 웹훅 URL 환경변수명   | `DISCORD_WEBHOOK_URL`               |

## 스크립트 설계 규칙

### 1. 일간 백업 스크립트 (`scripts/backup.sh`)

**필수 구현 사항:**

- `set -euo pipefail` 로 시작 (엄격 모드)
- 환경변수 기본값 패턴: `${VAR:-default_value}`
- `.env` 파일에서 웹훅 URL 자동 로드
- 백업 디렉토리 자동 생성 (`mkdir -p`)
- 타임스탬프 포맷: `YYYYMMDD_HHMMSS`
- 백업 파일명: `{DB_NAME}_{TIMESTAMP}.sql.gz`

**DB별 덤프 명령:**

```bash
# PostgreSQL (Docker)
docker exec ${DB_CONTAINER} pg_dump \
  -U ${DB_USER} -d ${DB_NAME} \
  --no-owner --no-privileges \
  | gzip > ${BACKUP_FILE}

# MySQL (Docker)
docker exec ${DB_CONTAINER} mysqldump \
  -u ${DB_USER} -p${DB_PASS} ${DB_NAME} \
  --single-transaction --routines --triggers \
  | gzip > ${BACKUP_FILE}

# MongoDB (Docker)
docker exec ${DB_CONTAINER} mongodump \
  --db ${DB_NAME} --archive \
  --gzip > ${BACKUP_FILE}

# PostgreSQL (직접 접속, Docker 없이)
PGPASSWORD=${DB_PASS} pg_dump \
  -h localhost -U ${DB_USER} -d ${DB_NAME} \
  --no-owner --no-privileges \
  | gzip > ${BACKUP_FILE}
```

**필수 검증 단계:**

1. 덤프 명령 실행 성공 여부 (`$?` 확인)
2. 백업 파일 존재 및 크기 확인 (`-f` && `-s`)
3. 압축 무결성 검증 (`gzip -t`)
4. 검증 실패 시 알림 전송 후 `exit 1`

**보존 정책:**

```bash
# 로컬: N일 초과 백업 자동 삭제
find ${BACKUP_DIR} -name "${DB_NAME}_*.sql.gz" -mtime +${RETENTION_DAYS} -print -delete
```

**오프사이트 연동:**

- 백업 성공 후 `offsite-sync.sh` 호출
- 오프사이트 실패는 일일 백업 성공에 영향 없음 (`|| true` 패턴)

### 2. 오프사이트 동기화 스크립트 (`scripts/offsite-sync.sh`)

**필수 구현 사항:**

- SSH 키 인증 (비밀번호 인증 금지)
- `BatchMode=yes` (대화형 프롬프트 차단)
- `ConnectTimeout=10` (빠른 실패)
- 재시도 로직: 최대 3회, 10초 간격
- 단일 파일 / 전체 디렉토리 모드 지원

**전송 방식:**

```bash
rsync -avz --compress \
  -e "ssh -i ${SSH_KEY} -o ConnectTimeout=10 -o BatchMode=yes" \
  ${SOURCE} \
  ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/
```

**원격 보존 정책:**

```bash
# 원격 서버에서 N일 초과 백업 삭제
ssh ${SSH_OPTS} ${REMOTE_USER}@${REMOTE_HOST} \
  "find ${REMOTE_DIR} -name '*.sql.gz' -mtime +${REMOTE_RETENTION_DAYS} -print -delete"
```

**실패 처리:**

- SSH 연결 실패 → 알림 후 `exit 1`
- rsync 재시도 모두 실패 → 알림 후 `exit 1`
- 오프사이트 실패가 일간 백업을 중단시키지 않음

### 3. 배포 전 자동 백업 (CI/CD)

**GitHub Actions 워크플로우에 삽입할 단계:**

```yaml
- name: 배포 전 DB 백업
  run: |
    BACKUP_DIR="$HOME/backups"
    mkdir -p "$BACKUP_DIR"
    DATE=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_predeploy_${DATE}.sql.gz"

    # 컨테이너 실행 중인 경우에만 백업
    if docker inspect ${DB_CONTAINER} --format='{{.State.Status}}' 2>/dev/null | grep -q "running"; then
      # [DB별 덤프 명령 삽입]
      # 파일 크기 검증
      if [ ! -s "$BACKUP_FILE" ]; then
        echo "백업 실패 — 배포 중단"
        exit 1
      fi
    fi
```

**핵심 규칙:**

- 배포 코드 적용 **이전에** 백업 실행
- 백업 실패 시 배포 **중단** (`exit 1`)
- 오프사이트 동기화는 비차단(non-blocking)으로 호출
- 롤백 섹션에 복원 명령 문서화

## 알림 시스템

**Discord 웹훅:**

```bash
send_notification() {
  local message="$1"
  if [ -n "${WEBHOOK_URL:-}" ]; then
    curl -s -H "Content-Type: application/json" \
      -d "{\"content\": \"$message\"}" \
      "$WEBHOOK_URL" > /dev/null 2>&1 || true
  fi
}
```

**Slack 웹훅:**

```bash
send_notification() {
  local message="$1"
  if [ -n "${WEBHOOK_URL:-}" ]; then
    curl -s -X POST -H "Content-Type: application/json" \
      -d "{\"text\": \"$message\"}" \
      "$WEBHOOK_URL" > /dev/null 2>&1 || true
  fi
}
```

**알림 메시지 규격:**

| 상태        | 메시지 접두어           |
| ----------- | ----------------------- |
| 백업 성공   | `[BACKUP OK]`           |
| 백업 실패   | `[BACKUP FAILED]`       |
| 파일 손상   | `[BACKUP CORRUPTED]`    |
| 동기화 성공 | `[OFFSITE SYNC OK]`     |
| 동기화 실패 | `[OFFSITE SYNC FAILED]` |

## 마이그레이션 전 자동 백업 (4계층)

DB 스키마 마이그레이션은 데이터 유실 사고가 가장 자주 일어나는 지점입니다. `scripts/db-migrate.sh` 래퍼가 다음 순서를 강제합니다:

1. 마이그레이션 대상 DB에 대해 `pg_dump` 실행
2. 출력물을 `state/db-backups/pre-migrate-{PROJECT}-{TIMESTAMP}.dump.gz`에 저장 + 크기 검증
3. 마이그레이션 실행 (`prisma migrate deploy`, `flyway migrate` 등)
4. 성공 시: 덤프는 `state/db-backups/`에 **14일 보관** 후 자동 삭제
5. 실패 시: 복원 명령을 콘솔에 출력 + `state/db-backups/` 에서 영구 보존

복원 예시:
```bash
gunzip < state/db-backups/pre-migrate-myapp-20260417_143012.dump.gz \
  | docker exec -i <접두사>-db pg_restore -U <user> -d <db> --clean --if-exists
```

상세 규칙과 복구 절차는 `docs/agents/migration-rules.md` 참조.

## 복원 절차

**반드시 `scripts/` 또는 CI/CD 워크플로우에 복원 명령을 문서화:**

```bash
# PostgreSQL 복원
gunzip < ~/backups/{DB_NAME}_{TIMESTAMP}.sql.gz \
  | docker exec -i ${DB_CONTAINER} psql -U ${DB_USER} -d ${DB_NAME}

# MySQL 복원
gunzip < ~/backups/{DB_NAME}_{TIMESTAMP}.sql.gz \
  | docker exec -i ${DB_CONTAINER} mysql -u ${DB_USER} -p${DB_PASS} ${DB_NAME}

# MongoDB 복원
docker exec -i ${DB_CONTAINER} mongorestore \
  --db ${DB_NAME} --archive --gzip < ~/backups/{DB_NAME}_{TIMESTAMP}.gz
```

## 사전 준비 사항 (체크리스트)

오프사이트 백업을 구성하기 전에 원격 PC에서 완료해야 할 작업:

1. **SSH 키 생성 및 배포**

   ```bash
   # 운영 서버에서 키 생성
   ssh-keygen -t ed25519 -f ~/.ssh/id_offsite -N "" -C "backup@$(hostname)"

   # 원격 PC에 공개키 등록
   ssh-copy-id -i ~/.ssh/id_offsite.pub ${REMOTE_USER}@${REMOTE_HOST}
   ```

2. **원격 PC 백업 디렉토리 생성**

   ```bash
   ssh ${REMOTE_USER}@${REMOTE_HOST} "mkdir -p ${REMOTE_DIR}"
   ```

3. **연결 테스트**

   ```bash
   ssh -i ~/.ssh/id_offsite -o BatchMode=yes ${REMOTE_USER}@${REMOTE_HOST} "echo OK"
   ```

4. **crontab 등록**

   ```bash
   crontab -e
   # 추가:
   # {CRON_EXPR} /path/to/project/scripts/backup.sh >> ~/logs/{PROJECT}-backup.log 2>&1
   ```

5. **로그 디렉토리 생성**
   ```bash
   mkdir -p ~/logs
   ```

## .env.example 추가 항목

백업 시스템 구성 시 `.env.example`에 다음 변수를 추가:

```env
# ── Database Backup ──────────────────────────────
POSTGRES_USER=
POSTGRES_DB=
POSTGRES_PASSWORD=
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
# SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
```

## 금지 사항

- 백업 파일에 DB 비밀번호를 파일명으로 포함하지 않음
- 백업 스크립트에 비밀번호를 하드코딩하지 않음 (환경변수 사용)
- 운영 DB에 `pg_dumpall` 대신 프로젝트별 `pg_dump` 사용
- 백업 파일을 Git에 커밋하지 않음 (`.gitignore`에 `*.sql.gz` 추가)
- 압축하지 않은 원본 SQL 파일을 디스크에 남기지 않음
- cron 로그를 `/var/log/`에 쓰지 않음 (권한 문제) → `~/logs/` 사용
