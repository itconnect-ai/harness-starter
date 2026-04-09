# docs/agents/deploy-rules.md

#

# 배포 및 Docker 규칙입니다.

# ⚠️ 프로젝트의 배포 환경에 맞게 수정하세요.

## 환경 분리

- 개발 환경: `dev/docker-compose.dev.yml` + `.env.development`
- 운영 환경: 루트 `docker-compose.yml` + `.env.production`
- `.env.example`만 커밋 (실제 값 없이 변수 목록만)
- 모든 설정값은 환경변수로 관리, 소스 코드에 하드코딩 금지

## 포트 관리

- 포트 번호를 소스 코드에 하드코딩하지 않음
- docker-compose에서 `${PORT:-3000}` 패턴으로 환경변수 사용
- 서비스 간 통신은 Docker 내부 DNS 사용 (포트 노출 불필요)
- 프로젝트별 포트 레지스트리를 architecture 문서에 기록

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
