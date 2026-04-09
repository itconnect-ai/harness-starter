# 배포 전 체크리스트

운영 서버에 배포하기 전에 확인해야 할 항목입니다.
validate.sh와 CI가 자동으로 잡는 항목 외에, 사람이 직접 확인해야 하는 항목을 정리합니다.

## 자동 검증 (validate.sh + CI)

이 항목들은 자동으로 검증됩니다. 통과하지 않으면 배포할 수 없습니다.

- [x] 타입 체크 통과
- [x] 린트 통과
- [x] 테스트 통과 (단위 + 회귀)
- [x] 빌드 성공
- [x] 하드코딩 시크릿 없음
- [x] .env 파일 커밋 없음

## 수동 확인: DB 백업

- [ ] `scripts/backup.sh`가 존재하고 프로젝트에 맞게 설정되어 있는가
  - 없다면: `db-backup-setup` 스킬로 생성 (README "백업 설정" 참조)
- [ ] 배포 직전 수동 백업 실행: `./scripts/backup.sh`
- [ ] 백업 파일 크기가 0이 아닌지 확인
- [ ] 오프사이트 동기화가 설정되어 있다면 최근 동기화 성공 여부 확인

## 수동 확인: SEO/AEO/GEO

- [ ] sitemap이 모든 공개 페이지를 포함하는가
- [ ] robots 정책이 비공개 경로를 disallow하는가
- [ ] 변경된 페이지의 메타데이터가 콘텐츠와 일치하는가 (→ [페이지 수정 후 체크리스트](page-update.md))
- [ ] JSON-LD 스키마가 Google Rich Results Test를 통과하는가

## 수동 확인: 인프라

- [ ] `.env.production`의 환경변수가 최신인가 (새 변수 추가 여부)
- [ ] `.env.example`에 새 변수가 반영되어 있는가
- [ ] Docker 이미지 빌드가 정상인가 (`docker compose build`)
- [ ] health check 엔드포인트가 응답하는가 (`/healthz`, `/readyz`)
- [ ] 포트 충돌이 없는가 (architecture 문서의 포트 레지스트리 확인)

## 수동 확인: 데이터

- [ ] DB 마이그레이션이 필요한 변경이 있는가
- [ ] 마이그레이션 스크립트가 준비되어 있는가
- [ ] 롤백 계획이 있는가 (마이그레이션 되돌리기 또는 백업 복원)

## 배포 후

- [ ] health check 정상 응답 확인
- [ ] 핵심 사용자 플로우 수동 테스트 (또는 `scripts/smoke.sh`)
- [ ] Google Search Console에서 크롤링 오류 없는지 확인
- [ ] 에러 로그 모니터링 (배포 후 30분)

---

## LLM에게 전달할 프롬프트

배포 전 아래 프롬프트를 LLM에게 전달하면 자동화 가능한 항목을 처리합니다:

```
배포 전 최종 검증을 실행해줘.

1. ./scripts/validate.sh 실행
2. ./scripts/smoke.sh 실행
3. scripts/backup.sh가 존재하는지 확인 — 없으면 알려줘
4. .env.example에 누락된 환경변수가 없는지 확인
5. sitemap과 robots 설정이 정상인지 확인
6. 변경된 페이지의 metadata/JSON-LD가 콘텐츠와 일치하는지 확인
   (docs/agents/seo-rules.md 참조)

문제가 있으면 직접 수정해줘.
```
