# docs/agents/deploy-rules.md

#

# 배포 및 Docker 규칙입니다.

# ⚠️ 프로젝트의 배포 환경에 맞게 수정하세요.

## 환경 분리

같은 머신에서 개발(dev)과 운영(prod)이 공존할 수 있다는 전제로 설계합니다.

### 파일 배치

- 운영: `docker-compose.yml` + `.env.production`
- 개발: `docker-compose.dev.yml` + `.env.development`
- `.env.example`만 커밋 (실제 값 없이 변수 목록만)
- `.env.development`, `.env.production`도 **기본적으로 Git 제외**. 필요 시 `.env.development.example` 템플릿만 커밋
- 모든 설정값은 환경변수로 관리, 소스 코드에 하드코딩 금지

### Compose project name 환경 접미사 (중복 충돌 방지)

같은 머신에 dev/prod가 동시에 도는 상황에서 컨테이너·네트워크·볼륨 이름이 충돌하는 것을 막기 위해, compose 파일의 `name:` 필드에 **환경 접미사**를 붙입니다:

| 환경 | compose name | 컨테이너 예시 | 네트워크 | 볼륨 |
|---|---|---|---|---|
| 운영 | `<접두사>` | `<접두사>-db` | `<접두사>-net` | `<접두사>_postgres_data` |
| 개발 | `<접두사>-dev` | `<접두사>-dev-db` | `<접두사>-dev-net` | `<접두사>-dev_postgres_data` |

중요: `<접두사>`는 `docker-rules.md §1-1`의 원칙대로 소문자 + 하이픈 없는 단어. `-dev` 접미사는 **compose name 레벨에서만** 추가하고, 컨테이너명의 역할 부분(`frontend`, `db` 등)은 건드리지 않습니다.

### 환경 라벨 (AI 혼동 방지)

AI 도구가 "지금 작업 대상이 dev인지 prod인지" 오인하는 사고를 막기 위해, **모든 compose 파일 최상단에 환경 라벨을 필수로** 기재합니다:

```yaml
name: <접두사>
# dev 환경이면: name: <접두사>-dev

x-environment: production
# dev 환경이면: x-environment: development

services:
  ...
```

- `x-environment` 값은 `production`, `development`, `staging` 중 하나
- AI는 docker 관련 작업 시작 전에 반드시 현재 작업 디렉토리의 compose 파일에서 `name:`과 `x-environment:`를 읽어 의도와 일치하는지 확인해야 함
- 자동화: `./scripts/docker-guard.sh`가 compose 파일 + 현재 사용하는 `.env` + 사용자 의도의 3자 일치를 검증

### 환경 전환 체크리스트

- [ ] compose 파일의 `name:` 값에 환경 접미사가 있는가 (또는 운영이면 없는가)
- [ ] `x-environment:` 라벨이 compose 파일 최상단에 있는가
- [ ] `--env-file` 플래그 또는 현재 셸의 환경변수가 해당 환경의 값을 가리키는가
- [ ] `docker-guard.sh`로 사전 검증 통과했는가
- [ ] 사용자 의도와 compose + .env + docker context가 3자 일치하는가

## 포트 관리

- 포트 번호를 소스 코드에 하드코딩하지 않음
- docker-compose에서 `${PORT:-3000}` 패턴으로 환경변수 사용
- 서비스 간 통신은 Docker 내부 DNS 사용 (포트 노출 불필요)
- 프로젝트별 포트 레지스트리는 `docs/org/docker-port-registry.md` (조직 내부 문서)를 따름
- 포트 레지스트리가 없는 프로젝트는 조직 표준을 먼저 수립한 후 배포 진행

## 데이터베이스 마이그레이션

- 로컬/운영 어디서든 마이그레이션은 `scripts/db-migrate.sh`(또는 `.ps1`) 래퍼를 통해 실행
- 마이그레이션 직전 자동 pg_dump, 실패 시 복원 명령 출력 (상세: `docs/agents/migration-rules.md`)
- `prisma migrate deploy`, `flyway migrate` 등을 직접 호출하지 않음

## Dockerfile 최적화

- 레이어 순서: 의존성 먼저, 소스 나중에 (캐시 최적화)
  ```
  COPY package.json package-lock.json ./
  RUN npm ci
  COPY . .
  RUN npm run build
  ```
- `COPY . .`를 `RUN npm install` 앞에 두지 않음 (캐시 무효화)
- Multi-stage build 필수 (deps → build → runtime 분리)
- `.dockerignore` 필수: node_modules, .git, .env\*, coverage, dist

## 데이터베이스 보호

- DB 데이터는 반드시 named volume 사용
- `docker-compose down -v` 또는 `--volumes` 플래그 사용 금지 (데이터 삭제됨)
- 프로덕션 DB 볼륨은 `external: true` 설정
- 스키마 변경은 마이그레이션 도구 사용 (Prisma migrate, Flyway 등)
- DROP DATABASE, DROP TABLE을 init 스크립트에 넣지 않음
- 배포 전 `scripts/backup.sh`로 백업 필수 — 상세 규칙은 `docs/agents/backup-rules.md` 참조
- 백업 시스템 구성은 `db-backup-setup` 스킬 사용

## Health Check

- 모든 서비스에 필수 엔드포인트 구현:
  - `GET /healthz` — liveness (프로세스 생존 확인)
  - `GET /readyz` — readiness (트래픽 수용 가능 여부)
- docker-compose에 healthcheck 정의 필수

## Graceful Shutdown

- 모든 서비스는 SIGTERM 핸들링 필수:
  1. 새 연결 수락 중지
  2. 진행 중인 요청 완료 대기
  3. DB 커넥션 종료
  4. process.exit(0)
- Node.js: `@godaddy/terminus` 라이브러리 권장
- Docker stop timeout: 최소 30초

## 운영 docker-compose.yml 필수 항목

- `restart: always` (또는 `unless-stopped`)
- 리소스 제한 (memory, CPU)
- healthcheck 정의
- 디버그 포트 노출하지 않음
- named volume으로 데이터 영속성 보장
