# 조직 Docker 포트 레지스트리 (Template)

이 문서는 조직이 관리하는 **모든 프로젝트의 Docker 포트/접두사/볼륨명**을 한 곳에 기록하는 레지스트리입니다. 이 파일은 **template**이며, 실제 값은 각 조직이 복사·채워서 사용합니다.

## 사용법

1. 이 파일을 `docs/org/docker-port-registry.md`로 복사
2. 아래 표를 조직 프로젝트에 맞게 채움
3. **실제 IP, 백업 서버 주소 등 내부 정보**가 들어가면 `.gitignore`에 `docs/org/docker-port-registry.md`를 추가하거나 private submodule로 분리
4. `docs/agents/docker-rules.md`, `docs/agents/deploy-rules.md`가 이 파일을 참조하여 포트·접두사·볼륨명을 결정

---

## 1. 포트 할당 원칙

숫자 범위를 먼저 정해두면 프로젝트가 늘어나도 충돌하지 않습니다.

| 용도 | 권장 범위 | 비고 |
|---|---|---|
| Frontend | 31xx | 프로젝트당 1개 |
| Backend | 32xx | 디버깅 시에만 노출 |
| Gateway / Public API | 41xx | Reverse Proxy 뒤에 숨김 권장 |
| Database | 54xx | 기본 비공개 |
| Redis | 64xx | 기본 비공개 |
| Object/Vector Storage | 90xx | MinIO는 9000/9001 고정 |
| 모니터링(Prometheus 등) | 91xx | 9100은 node_exporter 예약 |

예: `31x0`, `32x0`, `41x0`, `54x0`, `64x0` — 여기서 `x`는 프로젝트 일련번호(1·2·3…) 또는 사업부 구분.

## 2. 머신별 배치 (권장)

같은 머신에 너무 많은 프로젝트를 돌리면 포트 관리가 어려워집니다. 머신별로 배치를 명시합니다.

### Linux 서버 (운영)

| 프로젝트 | Frontend | Backend | Gateway | DB | Redis | 도메인 | 메모리 | Extra Services | Object/Vector | 백업 대상 |
|---|---|---|---|---|---|---|---|---|---|---|
| (예시) myapp | 3100 | 3200 | 4100 | 5400 | 6400 | myapp.example.com | 8GB | — | — | O |
| ... | | | | | | | | | | |

### MacOS 로컬 (운영 또는 개발)

| 프로젝트 | Frontend | Backend | Gateway | DB | Redis | 도메인 | 메모리 | Extra Services | Object/Vector |
|---|---|---|---|---|---|---|---|---|---|
| (예시) another | 3110 | 3210 | 4110 | 5410 | 6410 | another.example.com | 4GB | — | — |
| ... | | | | | | | | | |

---

## 3. 네이밍 표준 (프로젝트별)

`docs/agents/docker-rules.md §1-1`의 규칙에 따라:

| 프로젝트 | 접두사 | 네트워크 | DB 볼륨 | 환경 |
|---|---|---|---|---|
| (예시) myapp (prod) | `myapp` | `myapp-net` | `myapp_postgres_data` | production |
| (예시) myapp (dev) | `myapp-dev` | `myapp-dev-net` | `myapp-dev_postgres_data` | development |
| ... | | | | |

**주의**: "DB 볼륨" 열의 값은 `docker volume ls`에 나타나는 **최종 이름**입니다. compose에서 `external: true` + `name:` 선언 필수 (`docs/agents/docker-rules.md §4-2`).

---

## 4. Extra Public Services / Object-Vector 상세

특정 프로젝트가 표준 5개 서비스(frontend/backend/gateway/db/redis) 외에 추가 공개 서비스를 돌릴 때:

| 프로젝트 | 서비스 | 포트 | 컨테이너명 | 설명 |
|---|---|---|---|---|
| (예시) myapp | auth | 4101 | `myapp-auth` | OAuth 중계 |
| (예시) myapp | file | 4102 | `myapp-file` | 파일 업로드 API |
| (예시) myapp | MinIO | 9000/9001 | `myapp-minio` | S3 호환 객체 저장소 |
| ... | | | | |

**용어 정의**:
- **Extra Public Services**: 프로젝트당 01~09 사이 번호 (예: 4101, 4102)
- **Object/Vector**: 파일 저장소/벡터 검색 저장소 포트
- **MinIO**: 9000(API)/9001(Console)만 사용. 9100은 Prometheus 예약.

---

## 5. 백업 정책 (조직 공통)

`docs/agents/backup-rules.md`의 4계층 백업 구조를 따르되, **조직 고유 값**은 아래에 명시:

| 항목 | 값 (예시) |
|---|---|
| 일간 백업 시각 | 02:00 KST |
| 로컬 보존 일수 | 7일 |
| 오프사이트 백업 서버 | `backup@<내부-IP>` ⚠️ 실제 IP는 public repo에 커밋하지 말 것 |
| 오프사이트 경로 | `/home/backup_user/offsite-backups` |
| 오프사이트 보존 일수 | 30일 |
| 알림 채널 | `DISCORD_WEBHOOK_URL` (환경변수, .env에 저장) |

---

## 6. 체크리스트 (새 프로젝트 등록 시)

- [ ] §2의 포트 표에 행 추가 (머신 배치 확정)
- [ ] §3의 네이밍 표에 접두사/네트워크/볼륨 추가 (prod/dev 2행)
- [ ] 포트가 다른 프로젝트와 충돌하지 않음을 확인
- [ ] 접두사가 `docs/agents/docker-rules.md §1-3` 금지 패턴(숫자 suffix, `app`, `api` 등)과 겹치지 않음
- [ ] MinIO 사용 시 9000/9001 고정
- [ ] 도메인이 있으면 Reverse Proxy 설정 방법도 기록

---

## 7. 보안 주의

**이 파일을 public 저장소에 그대로 두지 마세요**. 다음 중 하나를 택하세요:

- `docs/org/docker-port-registry.md`를 `.gitignore`에 추가
- `docs/org/`를 private submodule로 분리
- 내부 Wiki(Notion, Confluence)로 이관하고 여기서는 링크만

⚠️ IP 주소, 내부 도메인, 백업 서버 정보 등은 공격 표면을 늘립니다.
