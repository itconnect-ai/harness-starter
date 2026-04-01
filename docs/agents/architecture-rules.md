# docs/agents/architecture-rules.md
#
# 이 프로젝트의 아키텍처 경계 규칙입니다.
# 에이전트가 구현/리뷰 시 이 경계를 준수해야 합니다.
#
# ⚠️ 프로젝트에 맞게 수정하세요. 아래는 일반적인 웹 SaaS 구조 예시입니다.

## 레이어 구조

```
UI (pages, components)
  ↓ (호출 가능)
Service (비즈니스 로직)
  ↓ (호출 가능)
Repository (데이터 접근)
  ↓ (호출 가능)
Config / Types (설정, 공유 타입)
```

## 경계 규칙

- UI는 Repository를 직접 호출하지 않음 (반드시 Service를 거침)
- Repository는 UI를 알지 못함
- Service는 UI 프레임워크에 의존하지 않음
- 공유 타입은 `src/shared/types/`에 위치
- 외부 API 호출은 Service 또는 전용 client 레이어에서만

## 변경 정책

- 새로운 cross-layer 의존성 추가 시 architecture.md 먼저 업데이트
- 새 프레임워크/라이브러리 도입 시 docs/decisions/에 ADR 작성
- 데이터 모델 변경 시 관련 타입 정의부터 수정

## 필수 엔드포인트

- `GET /healthz` — liveness (프로세스 생존 확인)
- `GET /readyz` — readiness (트래픽 수용 가능 여부)
- 서비스가 아닌 경우 (순수 프론트엔드 등) 해당 없음

## API 규칙

- URL 프리픽스 버저닝: `/api/v1/...`
- 리스트 엔드포인트는 반드시 페이지네이션 (offset+limit 또는 cursor)
- 표준 응답 형식: `{ "data": ..., "error": null }` / `{ "data": null, "error": { "code": "...", "message": "..." } }`
- 적절한 HTTP 상태 코드 사용 (200 성공, 4xx 클라이언트 오류, 5xx 서버 오류)

## 금지 패턴

- 전역 상태 남용 (필요 시 명시적 store 사용)
- 순환 의존성
- God object / God component
- 하드코딩된 환경 변수, 포트, URL (config에서 관리)
- 동기적 블로킹 처리 (이메일, 이미지 처리 등은 백그라운드 잡으로)
