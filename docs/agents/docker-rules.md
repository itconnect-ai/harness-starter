# docs/agents/docker-rules.md

Docker 환경 구성의 일반 원칙입니다. 환경 분리(개발/운영)는 `deploy-rules.md`, 마이그레이션은 `migration-rules.md`, 백업은 `backup-rules.md`를 참고하세요.

⚠️ 프로젝트의 포트 값, 도메인, 접두사는 조직별 포트 레지스트리(`docs/org/docker-port-registry.md` 또는 동등한 내부 문서)에 따라 결정합니다. 이 문서는 "어떻게 결정하는가"의 규칙을 정의합니다.

---

## 1. 네이밍 표준 (중복 생성 방지)

AI 도구가 유사 이름의 컨테이너를 중복 생성하는 사고를 막기 위한 규칙입니다.

### 1-1. 프로젝트 접두사

`docker compose` 사용 시 compose 파일 최상단에 `name:` 필드로 프로젝트명을 고정합니다.

- 접두사는 소문자 + 하이픈 없는 한 단어 (예: `bcreator`, `itconnect`, `workmate`)
- 컨테이너명은 `<접두사>-<역할>` 형태 (예: `bcreator-frontend`, `bcreator-db`)
- 네트워크명: `<접두사>-net`
- DB 볼륨명: `<접두사>_postgres_data` (또는 DB 종류에 맞게 `<접두사>_<db>_data`)

### 1-2. 허용되는 컨테이너명

표준 역할 이름만 허용합니다:

- `<접두사>-frontend`
- `<접두사>-backend`
- `<접두사>-gateway`
- `<접두사>-db`
- `<접두사>-redis`
- 조직 포트 레지스트리의 "Extra Public Services" 및 "Object/Vector" 열에 명시된 서비스 (예: `<접두사>-auth`, `<접두사>-minio`)

### 1-3. 금지 패턴

다음 패턴은 AI가 헷갈리기 쉬워 **전면 금지**합니다:

- 숫자 suffix: `<접두사>-backend-1`, `<접두사>-db-2`
- "new" / "old" suffix: `<접두사>-backend-new`, `<접두사>-db-old`
- 언더스코어 변형: `<접두사>_backend`, `<접두사>_db`
- 역할 중복 표현: `<접두사>-app`, `<접두사>-api`, `<접두사>-api-server`, `<접두사>-server`

### 1-4. 파일 규칙

- Compose 파일 최상단에 반드시 `name:` 명시 (프로젝트명)
- 모든 서비스에 `container_name:` 명시
- 모든 서비스에 `restart: unless-stopped` 명시 (고스트 재생성 방지)
- 한 프로젝트 × 한 환경당 compose 파일은 **1개** (서브 디렉토리에 별도 compose 금지)
- Docker Desktop GUI 표시와 CLI 이름이 다르게 보여도 **CLI가 정답**. GUI에 맞춰 이름을 바꾸지 않음

---

## 2. 포트 운영 정책

### 2-1. 기본 공개 여부

| 서비스 | compose 설정 | 외부 오픈 | 설명 |
|---|---|---|---|
| Frontend | `ports: "${FRONTEND_PORT}:3000"` | O (필요 시) | 브라우저에서 직접 확인 |
| Backend | `expose: "8000"` | X (기본) | Docker 내부 통신. 디버깅 시에만 `ports:` 주석 해제 |
| Gateway | `expose` 또는 `ports: "${GATEWAY_PORT}:<내부>"` | 조건부 | Reverse Proxy가 대신 연결 |
| DB | `expose: "5432"` | X (기본) | 내부 통신. DB 클라이언트 접속 시에만 `ports:` 주석 해제 |
| Redis | `expose: "6379"` | X (기본) | 내부 통신. RedisInsight 접속 시에만 `ports:` 주석 해제 |

**핵심**: DB/Redis는 외부에 안 열어도 사용 가능. 같은 Docker 네트워크 안에 있으면 내부 DNS(`db:5432`, `redis:6379`)로 자동 통신됨. IP 하드코딩 금지.

### 2-2. Gateway 내부 포트

호스트 포트(`GATEWAY_PORT`)는 포트 레지스트리를 따르되, **컨테이너 내부 포트**는 해당 게이트웨이의 실제 listen 포트에 맞춥니다:

- nginx: 내부 `80`
- Traefik: 내부 `80` (HTTP) 또는 `8080` (대시보드)
- 템플릿에 `8080`이 써 있어도 **맹목 복사 금지**. 실제 서비스에 맞게 수정.

### 2-3. Reverse Proxy

Nginx Proxy Manager 권장. 외부 공개 포트는 **80(HTTP) / 443(HTTPS)** 2개만 열고 도메인별로 분기합니다. 내부 프로젝트 포트는 NPM 뒤에 숨김.

### 2-4. 도메인 상태 변화 대응

| 상황 | 조치 |
|---|---|
| 도메인 없음 | 포트로 직접 접속 (`localhost:3140`). 바로 시작 가능 |
| 도메인 생김 | Reverse Proxy 설정만 추가. Docker 내부 구조 변경 없음 |
| 도메인 변경 | Reverse Proxy 설정 + `.env`의 `PUBLIC_URL`만 수정. 내부 포트/컨테이너/네트워크 유지 |

### 2-5. 포트 충돌 방지

- 동일 호스트에 여러 프로젝트가 돌 때는 조직 포트 레지스트리를 따름
- MinIO는 **9000/9001만 사용** (9100은 Prometheus 표준 포트와 충돌)
- 호스트 포트는 compose 파일에 숫자 하드코딩 금지. 모두 `.env` 환경변수로 주입

---

## 3. 작업 전후 검증 (AI 강제 조건)

### 3-1. 사전 검증

Docker 작업 시작 **전** 반드시 현재 상태를 확인합니다:

```bash
docker ps -a --filter "name=<접두사>" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
docker network ls --filter "name=<접두사>"
docker volume ls --filter "name=<접두사>"
```

자동화: `./scripts/docker-guard.sh --prefix <접두사>` (또는 `.ps1`) 사용.

### 3-2. 사전 검증 결과 처리

- **동일 접두사 컨테이너가 이미 존재** → 삭제·재생성하지 말고 사용자에게 먼저 보고
- **기존 `docker-compose.yml`이 있음** → 새로 만들지 말고 수정
- **허용 목록 외 컨테이너 발견** → 중단, 사용자 확인 필요

### 3-3. 사후 검증

작업 완료 후 동일 명령으로 재검증합니다. 허용 목록(§1-2) 외 컨테이너가 있으면 실패 처리.

---

## 4. docker-compose 작성 규칙

### 4-1. 공통 규칙

- 포트는 전부 `.env`의 변수로 주입. compose 파일에 숫자 하드코딩 금지
- 네트워크는 외부 네트워크가 아닌 프로젝트 전용 네트워크 사용
- 볼륨명은 조직 포트 레지스트리의 값 그대로 (`<접두사>_postgres_data`)
- 컨테이너 간 통신은 서비스명 DNS (`db:5432`, `redis:6379`)
- MacOS Apple Silicon 호환성 문제 발생 시에만 `platform: linux/amd64` 활성화. 이 경우에도 이름·포트 절대 변경 금지

### 4-2. 볼륨 재사용/이관 시 external 선언

볼륨 이름을 `<접두사>_postgres_data`로 **최종 고정**하려면 `external: true`와 `name:`을 명시합니다:

```yaml
volumes:
  postgres_data:
    external: true
    name: <접두사>_postgres_data
```

이 선언이 없으면 Compose는 `<compose-project-name>_<volume-key>` 형태로 자동 접두사를 붙여 이름이 흐트러집니다.

### 4-3. 서비스 가감

- 프로젝트가 Redis를 안 쓰면 Redis 서비스 **생략**
- nginx·MinIO·Qdrant 등은 §1-2 허용 목록 범위 안에서 추가
- 템플릿은 **참고용**. 서비스 목록을 강제하지 않음

### 4-4. 앱 고유 env 네임스페이스 브릿지

앱이 `COO_*`, `APP_*` 같은 고유 접두사 환경변수를 쓰면 compose `environment:` 블록에서 매핑합니다. `.env`에 이중 정의 금지.

### 4-5. 참고 템플릿 (최소형)

```yaml
name: <접두사>

services:
  frontend:
    container_name: <접두사>-frontend
    ports: ["${FRONTEND_PORT}:3000"]
    env_file: .env
    restart: unless-stopped
    networks: [default]

  backend:
    container_name: <접두사>-backend
    expose: ["8000"]
    # ports: ["${BACKEND_PORT}:8000"]   # 디버깅 시에만
    env_file: .env
    depends_on: [db]
    restart: unless-stopped
    networks: [default]

  db:
    container_name: <접두사>-db
    image: postgres:16
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    expose: ["5432"]
    # ports: ["${DB_PORT}:5432"]        # DB 클라이언트 접속 시에만
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
    networks: [default]

volumes:
  postgres_data:
    external: true
    name: <접두사>_postgres_data

networks:
  default:
    name: <접두사>-net
```

---

## 5. `.env` 규칙

- 프로젝트 루트에 `.env.example` 커밋, 실제 값이 든 `.env`는 Git 제외
- 포트 값은 조직 포트 레지스트리에서 해당 프로젝트 행의 값을 그대로 복사
- `PUBLIC_URL` 단계별 교체:
  1. 도메인 없음: `http://localhost:<FRONTEND_PORT>`
  2. 도메인 연결 후: `https://<도메인>`

환경별 파일 분리 (개발/운영 공존 시):

- `.env.development` — 개발용 값
- `.env.production` — 운영용 값
- `.env` — 현재 활성 환경을 가리키는 심볼릭 링크 또는 복사본

---

## 6. 운영 단계별 진행 순서

**1단계 — 도메인 없어도 OK**
- 포트로 직접 접속 (`localhost:3100`)
- Docker 내부 통신 구조 확정
- compose 작성

**2단계 — 도메인 연결**
- Nginx Proxy Manager 설치
- 도메인 → 내부 포트 매핑
- SSL 자동 발급 (Let's Encrypt)

**3단계 — 운영 안정화**
- Backend / DB / Redis 호스트 포트 완전 차단
- 모니터링 추가 (Prometheus 등)
- DB 백업 정책 (`backup-rules.md` 참고)

---

## 7. 규칙 위반 체크리스트

프로젝트 1개 설치 완료 시 다음을 **모두** 만족해야 합니다:

- [ ] 호스트 포트가 조직 포트 레지스트리의 해당 프로젝트 값과 완전 일치
- [ ] 컨테이너명·네트워크명·볼륨명이 §1 네이밍 표준을 따름
- [ ] `docker ps -a --filter "name=<접두사>"` 결과가 §1-2 허용 목록과 정확히 일치. 숫자 붙은 변형 없음
- [ ] Backend·DB·Redis의 호스트 포트 바인딩은 주석 상태
- [ ] `.env.example`은 실제 값 없이 제공, `.env`는 Git 제외
- [ ] `docker network ls | grep <접두사>` 결과 환경당 1개
- [ ] `docker volume ls | grep <접두사>` 결과 환경당 1개
- [ ] MinIO 사용 시 9000/9001만 사용
- [ ] MacOS에서 `platform` 활성화했다면 이름·포트 변경 없음
- [ ] 기존 compose 파일을 중복 생성하지 않고 수정함

---

## 8. 관련 규칙

- 환경 분리(개발/운영 공존), compose 파일 명명, Dockerfile 최적화: `docs/agents/deploy-rules.md`
- DB 마이그레이션 데이터 보호: `docs/agents/migration-rules.md`
- DB 백업 아키텍처: `docs/agents/backup-rules.md`
- 기존 프로젝트 이관(다른 이름/구성 → 본 표준): `docs/agents/migration-rules.md` §4 이관 절차
