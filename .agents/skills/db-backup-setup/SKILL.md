---
name: db-backup-setup
description: 운영 서버 DB 백업 시스템을 범용으로 설계·생성합니다. 일간 자동 백업, 오프사이트 동기화, 배포 전 백업을 프로젝트에 맞게 구성합니다. "백업 설정", "backup setup", "DB 백업 구성" 등의 요청 시 사용합니다.
---

# DB Backup Setup

## Overview

운영 서버에서 데이터베이스 백업 파일을 자동 생성하고, 원격 PC로 오프사이트 동기화하는 3계층 백업 시스템을 프로젝트에 맞게 설계·생성하는 스킬입니다.

어떤 프로젝트든 동일한 아키텍처를 적용할 수 있도록 범용적으로 설계되어 있으며, DB 종류(PostgreSQL, MySQL, MongoDB), 인프라 구성(Docker/직접 설치), 알림 채널(Discord/Slack)에 따라 스크립트를 자동 생성합니다.

**Args:** 프로젝트 경로 또는 `--headless` / `-H` (비대화형 모드)

**산출물:**

- `scripts/backup.sh` — 일간 자동 백업 스크립트
- `scripts/offsite-sync.sh` — 원격 PC 동기화 스크립트
- CI/CD 배포 전 백업 단계 (GitHub Actions YAML 스니펫)
- crontab 등록 명령 + SSH 키 설정 가이드

## On Activation

1. `docs/agents/backup-rules.md`를 로드하여 설계 규칙을 확인합니다.
2. 대화형 모드가 아닌 경우 (`--headless`), 프로젝트의 기존 파일에서 정보를 자동 수집합니다.
3. 아래 Discovery 단계를 시작합니다.

## Discovery — 정보 수집

사용자에게 다음 정보를 순서대로 확인합니다. 이미 프로젝트 파일(docker-compose.yml, .env, package.json 등)에서 추론할 수 있는 값은 기본값으로 제시하고 확인만 받습니다.

### Phase 1: 프로젝트 기본 정보

```
수집 항목:
- PROJECT_NAME    : 프로젝트 식별자 (package.json name 또는 디렉토리명에서 추론)
- DB_TYPE         : postgresql | mysql | mongodb (docker-compose.yml에서 추론)
- DB_ACCESS       : docker | direct (Docker 컨테이너 경유 또는 직접 접속)
- DB_CONTAINER    : Docker 컨테이너 이름 (docker-compose.yml의 container_name에서 추론)
- DB_USER         : DB 사용자명 (환경변수 또는 docker-compose.yml에서 추론)
- DB_NAME         : 데이터베이스 이름 (환경변수에서 추론)
- DB_PASS_ENV_VAR : 비밀번호 환경변수명 (예: POSTGRES_PASSWORD). 값 자체는 절대 수집하지 않음
```

**추론 전략:**

- `docker-compose.yml` 또는 `docker-compose.*.yml`에서 DB 이미지, 컨테이너명, 환경변수 파싱
- `.env.example` 또는 `.env`에서 DB 관련 환경변수명 확인
- `prisma/schema.prisma`의 `datasource` 블록에서 DB 종류 확인
- 추론한 값을 사용자에게 보여주고 확인/수정 요청

### Phase 2: 백업 정책

```
수집 항목:
- BACKUP_SCHEDULE    : cron 표현식 (기본값: "0 2 * * *" — 매일 02:00)
- LOCAL_RETENTION    : 로컬 보존 일수 (기본값: 7)
- BACKUP_DIR         : 백업 저장 경로 (기본값: "$HOME/backups")
- LOG_DIR            : 로그 경로 (기본값: "$HOME/logs")
```

### Phase 3: 오프사이트 동기화

```
수집 항목:
- ENABLE_OFFSITE     : 오프사이트 동기화 활성화 여부 (기본값: yes)
- REMOTE_HOST        : 원격 PC IP 또는 호스트명
- REMOTE_USER        : 원격 PC 사용자명
- REMOTE_DIR         : 원격 백업 경로 (기본값: "/home/{REMOTE_USER}/offsite-backups")
- REMOTE_RETENTION   : 원격 보존 일수 (기본값: 30)
- SSH_KEY_PATH       : SSH 키 경로 (기본값: "~/.ssh/id_offsite")
- MAX_RETRIES        : rsync 재시도 횟수 (기본값: 3)
- RETRY_DELAY        : 재시도 간격 초 (기본값: 10)
```

### Phase 4: 알림 설정

```
수집 항목:
- NOTIFY_METHOD      : discord | slack | none (기본값: discord)
- WEBHOOK_ENV_VAR    : 웹훅 URL 환경변수명 (기본값: DISCORD_WEBHOOK_URL 또는 SLACK_WEBHOOK_URL)
```

### Phase 5: CI/CD 통합

```
수집 항목:
- ENABLE_PREDEPLOY   : 배포 전 백업 활성화 여부 (기본값: yes)
- CI_PLATFORM        : github-actions | gitlab-ci | none (기본값: github-actions)
- DEPLOY_PATH_SECRET : 배포 경로 시크릿명 (기본값: DEPLOY_PATH) — GitHub Actions 전용
```

## Generation — 스크립트 생성

모든 정보가 수집되면 `docs/agents/backup-rules.md`의 규칙에 따라 다음 파일을 생성합니다.

### 생성 파일 목록

| 파일                      | 조건                   | 설명                                |
| ------------------------- | ---------------------- | ----------------------------------- |
| `scripts/backup.sh`       | 항상                   | 일간 자동 백업 스크립트             |
| `scripts/offsite-sync.sh` | `ENABLE_OFFSITE=yes`   | 원격 PC 동기화 스크립트             |
| CI/CD 스니펫              | `ENABLE_PREDEPLOY=yes` | 배포 전 백업 단계 (복사·붙여넣기용) |

### 생성 규칙

각 스크립트를 생성할 때 반드시 따르는 규칙:

1. **backup.sh 구조:**

   ```
   #!/bin/bash
   # {PROJECT_NAME} {DB_TYPE} 일간 자동 백업 스크립트
   # 사용법: crontab 등록 명령 (아래 참조)

   set -euo pipefail

   # ── 설정 ──
   # ── 알림 함수 ──
   # ── 백업 디렉토리 생성 ──
   # ── 덤프 실행 ──
   # ── 검증 (파일 존재 + 크기 + 무결성) ──
   # ── 보존 정책 (오래된 백업 삭제) ──
   # ── 오프사이트 동기화 호출 ──
   # ── 완료 알림 ──
   ```

2. **offsite-sync.sh 구조:**

   ```
   #!/bin/bash
   # {PROJECT_NAME} 오프사이트 백업 동기화 스크립트

   set -euo pipefail

   # ── 설정 ──
   # ── 알림 함수 ──
   # ── SSH 연결 확인 ──
   # ── rsync 전송 (재시도 포함) ──
   # ── 원격 보존 정책 ──
   # ── 완료 알림 ──
   ```

3. **DB별 덤프 명령 선택:**
   - `DB_TYPE`에 따라 `backup-rules.md`의 해당 덤프 명령 사용
   - `DB_ACCESS=direct`이면 Docker 없이 직접 접속 명령 사용

4. **알림 함수 선택:**
   - `NOTIFY_METHOD`에 따라 Discord 또는 Slack 웹훅 함수 생성
   - `none`이면 알림 함수를 빈 함수(`:`만 포함)로 생성

5. **파일 권한:**
   - 생성 후 `chmod +x scripts/backup.sh scripts/offsite-sync.sh` 안내

## Post-Generation — 설정 가이드 출력

스크립트 생성 후 사용자에게 다음 설정 가이드를 출력합니다:

### 1. SSH 키 설정 (오프사이트 활성화 시)

```bash
# 1. 운영 서버에서 SSH 키 생성
ssh-keygen -t ed25519 -f {SSH_KEY_PATH} -N "" -C "backup@$(hostname)"

# 2. 원격 PC에 공개키 등록
ssh-copy-id -i {SSH_KEY_PATH}.pub {REMOTE_USER}@{REMOTE_HOST}

# 3. 연결 테스트
ssh -i {SSH_KEY_PATH} -o BatchMode=yes {REMOTE_USER}@{REMOTE_HOST} "echo OK"
```

### 2. crontab 등록

```bash
# 로그 디렉토리 생성
mkdir -p {LOG_DIR}

# crontab 등록
crontab -e
# 추가할 라인:
# {BACKUP_SCHEDULE} /path/to/project/scripts/backup.sh >> {LOG_DIR}/{PROJECT_NAME}-backup.log 2>&1
```

### 3. .env.example 업데이트

수집된 환경변수명을 `.env.example`에 추가해야 할 항목으로 안내합니다.

### 4. .gitignore 확인

`*.sql.gz`가 `.gitignore`에 포함되어 있는지 확인하고, 없으면 추가를 안내합니다.

### 5. 복원 명령

DB 종류에 맞는 복원 명령을 안내합니다 (`backup-rules.md`의 복원 절차 참조).

## Headless Mode

`--headless` 또는 `-H`로 호출된 경우:

1. 프로젝트 파일에서 모든 값을 자동 추론
2. 추론 불가능한 필수 값(REMOTE_HOST 등)이 있으면 에러 메시지 출력 후 종료
3. 추론 결과를 요약 표시 후 즉시 생성 단계 진행
4. 사용자 확인 없이 스크립트 생성 + 설정 가이드 출력

## Validation — 생성물 검증

생성 완료 후 다음을 자동 검증합니다:

1. `bash -n scripts/backup.sh` — 문법 오류 확인
2. `bash -n scripts/offsite-sync.sh` — 문법 오류 확인
3. 비밀번호/시크릿이 스크립트에 하드코딩되어 있지 않은지 확인
4. `.gitignore`에 `*.sql.gz` 포함 여부 확인

## Quick Reference

| 사용자 요청                      | 동작                                       |
| -------------------------------- | ------------------------------------------ |
| "백업 설정해줘" / "backup setup" | Discovery → Generation → Guide 전체 실행   |
| "백업 스크립트만 만들어줘"       | Phase 1-2만 수집 후 `backup.sh`만 생성     |
| "오프사이트 동기화 추가해줘"     | Phase 3만 수집 후 `offsite-sync.sh`만 생성 |
| "배포 전 백업 추가해줘"          | Phase 5만 수집 후 CI/CD 스니펫만 생성      |
| `--headless`                     | 자동 추론 → 전체 생성                      |
