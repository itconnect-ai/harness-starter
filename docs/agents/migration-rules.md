# docs/agents/migration-rules.md

데이터베이스 스키마 마이그레이션 시 **데이터 유실을 구조적으로 방지**하기 위한 규칙입니다. AI 에이전트가 마이그레이션을 실행할 때 이 규칙을 반드시 따라야 합니다.

관련 규칙: `backup-rules.md` (백업 아키텍처), `deploy-rules.md` (환경 분리), `docker-rules.md` (컨테이너 기본 규칙).

---

## 1. 핵심 원칙

1. **모든 마이그레이션은 `scripts/db-migrate.sh` 래퍼를 통해서만 실행**
   - `prisma migrate deploy`, `flyway migrate`, `alembic upgrade` 등을 직접 호출하지 않음
   - 래퍼가 자동 pg_dump → migrate → 실패 시 복원 명령 출력 → 성공 시 덤프 14일 보존을 담당
2. **마이그레이션 전 백업 필수** — 어떤 규모든 예외 없음
3. **파괴적 변경은 2단계 마이그레이션** (deprecate → remove)
4. **모든 마이그레이션은 원칙적으로 reversible** — 불가피한 경우 명시 + 사용자 승인
5. **운영 DB에 직접 `DROP TABLE`, `DROP COLUMN`, `TRUNCATE` 금지** — 반드시 마이그레이션 파일을 거침

---

## 2. 파괴적 변경의 2단계 마이그레이션

`DROP COLUMN`, `DROP TABLE`, `RENAME COLUMN`, 타입 축소(`VARCHAR(255)` → `VARCHAR(50)`) 등은 **한 번에 실행하지 않습니다**.

### 2-1. DROP COLUMN 예시

**잘못된 방식 (금지)**:
```sql
ALTER TABLE users DROP COLUMN legacy_email;
```
→ 구버전 앱이 해당 컬럼을 읽는 순간 500 에러. 한 번 drop하면 복구 불가.

**올바른 방식 (2단계)**:

1단계 마이그레이션 — **deprecate**:
```sql
-- 컬럼은 유지하되 앱 코드에서 사용 중단
-- 이 마이그레이션을 배포하고 최소 1개 릴리즈 주기 관찰
COMMENT ON COLUMN users.legacy_email IS 'DEPRECATED: remove after 2026-05-01';
```
- 앱 코드를 먼저 배포해 `legacy_email` 참조를 전부 제거
- 로그/메트릭으로 해당 컬럼 접근이 0인지 최소 1주 관찰

2단계 마이그레이션 — **remove** (1단계 배포 후 최소 1주 뒤):
```sql
ALTER TABLE users DROP COLUMN legacy_email;
```

### 2-2. RENAME 패턴

"이름만 바꾸는" 단일 마이그레이션 금지. 항상:
1. **새 컬럼 추가** + 데이터 복제 (dual-write 기간)
2. 앱 코드가 새 컬럼을 읽도록 전환
3. 관찰 기간 후 **기존 컬럼 drop**

### 2-3. 타입 축소

`VARCHAR(255)` → `VARCHAR(50)`, `TEXT` → `VARCHAR` 같은 축소는 기존 데이터 truncation 위험. 반드시:
1. 실제 데이터 길이 분석 (`SELECT MAX(LENGTH(col)) FROM table`)
2. 새 컬럼 생성 후 앱 전환 + 관찰
3. 기존 컬럼 drop

---

## 3. Reversible 마이그레이션

### 3-1. 원칙

모든 마이그레이션 파일은 `up`과 `down`을 모두 정의합니다. Prisma는 기본적으로 down을 지원 안 하지만, 별도 rollback 마이그레이션 파일을 쌍으로 만들어 대응합니다.

### 3-2. Reversible이 어려운 경우

- `DROP COLUMN` 실행 후 데이터 복원은 백업 없이 불가
- 규칙: **마이그레이션 직전 자동 pg_dump를 rollback으로 간주**. `db-migrate.sh`가 자동 생성
- 마이그레이션 파일 상단에 rollback 방법을 주석으로 명시:

```sql
-- Migration: 0042_drop_legacy_email.sql
-- Reversible: NO (data loss)
-- Rollback: restore from pre-migration dump at state/db-backups/pre-migrate-YYYYMMDD-HHMMSS.dump
-- Approval: @사용자 on 2026-04-17
```

### 3-3. Irreversible 마이그레이션 체크리스트

irreversible 마이그레이션은 `db-migrate.sh`가 아래를 강제합니다:

- [ ] 마이그레이션 파일 헤더에 `Reversible: NO` 명시
- [ ] Rollback 방법 주석 명시 (dump 경로 포함)
- [ ] `--force-irreversible` 플래그 필요 (사용자가 명시적으로 확인)
- [ ] 프로덕션 환경이면 추가로 `--env=production` 명시 (이중 확인)
- [ ] 마이그레이션 직전 덤프가 성공했는지 파일 크기 검증

---

## 4. 기존 프로젝트 이관 절차 (Migration between setups)

기존 compose 구성(다른 이름/볼륨 규칙)에서 `docker-rules.md` 표준으로 이관할 때 데이터 유실 없이 따르는 절차입니다.

### 4-1. 사전 보고

사용자에게 다음 결과를 보고하고 이관 대상과 보존 대상을 확정받습니다:

```bash
docker ps -a
docker volume ls
docker network ls
```

### 4-2. DB 백업 (필수)

```bash
# 실행 중인 기존 DB 컨테이너에서
docker exec <기존-DB-컨테이너> pg_dump -U <user> -d <db> -F c -f /tmp/backup.dump
docker cp <기존-DB-컨테이너>:/tmp/backup.dump ./backup-$(date +%Y%m%d).dump

# 덤프 파일 크기 확인 — 0바이트면 실패
ls -la ./backup-*.dump
```

### 4-3. 볼륨 보존 전략 (둘 중 택 1)

**(A) 외부 볼륨 재연결 (데이터 이동 없음 — 빠름)**:
1. 기존 볼륨을 `external: true`로 선언해 이름만 바꿔 이어 씀
2. 이름만 변경이 필요하면:
   ```bash
   docker run --rm \
     -v <기존-볼륨>:/from \
     -v <새-볼륨>:/to \
     alpine sh -c "cp -a /from/. /to/"
   ```
3. 새 compose가 `external: true` + `name: <새-볼륨>`로 선언된 상태에서 up

**(B) 덤프 복원 (깨끗한 시작)**:
1. 새 compose 기동 (빈 DB)
2. `pg_restore -U <user> -d <db> /tmp/backup.dump`

### 4-4. `docker compose down` 시 `-v` 절대 금지

```bash
# 금지 (기존 볼륨 삭제됨)
docker compose down -v
docker compose down --volumes

# 허용
docker compose down
docker compose stop
```

### 4-5. CI/CD 파이프라인 동기화

컨테이너명·서비스명을 참조하는 파일들을 **함께** 수정합니다:
- `.github/workflows/*.yml`
- `scripts/*.sh`
- 배포 스크립트

이관 완료 전까지 자동 배포를 **일시 중지**합니다.

### 4-6. 이관 후 재검증

```bash
./scripts/docker-guard.sh --prefix <접두사> --env production
```

다음이 확인되어야 합니다:
- 새 이름의 컨테이너만 존재 (허용 목록 범위)
- 네트워크·볼륨 1개씩 (환경당)
- 앱 레벨 smoke test 통과 (로그인, 주요 화면, DB 조회)

이전 볼륨은 **최소 1주** 보관 후 사용자 승인 하에 제거합니다:
```bash
# 이관 성공을 확인한 뒤에만
docker volume rm <이전-볼륨>
```

---

## 5. 실시간 운영 DB 보호 규칙

### 5-1. Production에서 금지되는 즉시 실행

- `DROP DATABASE`, `DROP TABLE`, `DROP SCHEMA`
- `TRUNCATE`
- `DELETE` without `WHERE` (전체 삭제)
- `UPDATE` without `WHERE` (전체 업데이트)
- 인덱스 생성은 `CREATE INDEX CONCURRENTLY` (non-blocking) 사용

### 5-2. 마이그레이션 외 스키마 변경 금지

운영 DB에 GUI 클라이언트(DBeaver, pgAdmin)로 직접 접속해 스키마 변경 금지. 모든 변경은:
1. 마이그레이션 파일 작성
2. 코드 리뷰
3. `db-migrate.sh` 실행

### 5-3. 데이터 수정(DML) 운영 규칙

- 운영 DB에서 1건 이상 row를 수정해야 하면:
  1. `BEGIN;` 으로 트랜잭션 시작
  2. `SELECT`로 대상 확인
  3. `UPDATE/DELETE` 실행
  4. 영향받은 row 수 확인 (`SELECT`, 예상과 일치하는지)
  5. 일치하면 `COMMIT;`, 불일치면 `ROLLBACK;`
- 한 번에 10,000 row 이상 영향받는 DML은 배치 처리 (`LIMIT` + loop)

---

## 6. AI 에이전트 체크리스트

마이그레이션 작업 시작 전 AI는 다음을 확인해야 합니다:

- [ ] 사용자 지시가 "개발 환경" 또는 "운영 환경"을 한국어로 명시했는가. compose 파일의 `x-environment:` 라벨과 일치하는가
- [ ] `scripts/db-migrate.sh` 래퍼가 존재하는가 (없으면 먼저 생성)
- [ ] 마이그레이션 파일이 reversible인가, irreversible이면 헤더 주석에 명시되었는가
- [ ] `DROP COLUMN/TABLE`/RENAME이 포함되면 2단계 마이그레이션 계획을 세웠는가
- [ ] 운영 환경 마이그레이션이면 사용자의 명시적 승인을 받았는가 (`db-migrate.sh --env production --force-irreversible` 조합이 필요한 경우 별도 확인)

---

## 7. 복구 시나리오

### 7-1. 마이그레이션 실패 직후 롤백

`db-migrate.sh`가 자동으로 안내하지만, 수동으로 실행할 때:

```bash
# 1. 실패한 컨테이너 확인
docker ps -a --filter "name=<접두사>-db"

# 2. 마이그레이션 직전 덤프로 복원
gunzip < state/db-backups/pre-migrate-<timestamp>.dump.gz \
  | docker exec -i <접두사>-db pg_restore -U <user> -d <db> --clean --if-exists
```

### 7-2. 장시간 지난 뒤 복구

`backup-rules.md`의 일간/오프사이트 백업에서 복원:

```bash
gunzip < ~/backups/<db-name>_<date>.sql.gz \
  | docker exec -i <접두사>-db psql -U <user> -d <db>
```
