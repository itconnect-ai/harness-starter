# REVIEW.md
#
# Claude Code가 코드 리뷰 시 참고하는 기준 문서입니다.
# bmad-code-review 스킬과 함께 사용됩니다.

## 리뷰 범위

- 현재 브랜치의 main 대비 diff만 리뷰
- story 범위를 벗어난 변경이 있으면 지적
- 기존 코드의 문제는 리뷰하지 않음 (pre-existing 이슈 무시)

## 필수 확인 항목

### 1. 아키텍처 경계

- `docs/agents/architecture-rules.md`에 정의된 레이어 경계 준수 여부
- 허용되지 않은 cross-layer 의존성 여부
- 새 패턴 도입 시 `docs/decisions/`에 기록 여부
- health check 엔드포인트 존재 여부 (서비스인 경우)
- API 버저닝 패턴 준수 여부

### 2. 기능 정확성

- story의 acceptance criteria를 충족하는지
- 엣지 케이스 처리 (null, empty, boundary values)
- 에러 처리 (try-catch, fallback, 사용자 피드백)

### 3. 테스트

- 변경된 동작에 대한 테스트 존재 여부
- 테스트가 실제 동작을 검증하는지 (단순 스냅샷이 아닌)
- 핵심 경로의 통합 테스트 여부

### 4. 보안 (docs/agents/security-rules.md 기준)

- 하드코딩된 시크릿 없음 (API 키, 비밀번호, 토큰)
- 사용자 입력 검증 (zod 등)
- 인증/인가 체크 존재
- SQL injection, XSS 방지 패턴
- 내부 에러 메시지 클라이언트 노출 없음
- CORS가 `origin: '*'`가 아닌지

### 5. 성능 (docs/agents/performance-rules.md 기준)

- N+1 쿼리 패턴 없음
- 리스트 쿼리에 LIMIT 존재
- 이벤트 리스너 cleanup 존재
- 전체 라이브러리 import 없음
- API 엔드포인트 페이지네이션

### 6. 배포 (docs/agents/deploy-rules.md 기준)

- 포트/URL 하드코딩 없음
- Dockerfile 레이어 순서 최적화
- docker-compose에 named volume 사용
- graceful shutdown 핸들링

### 7. 코드 품질

- 네이밍 일관성
- 중복 코드 여부
- 불필요한 복잡성
- 구조화된 로깅 사용 (console.log 금지)

## 판정 기준

### APPROVED 조건 (모두 충족 시)

- validate.sh 통과
- 아키텍처 경계 위반 없음
- 변경 동작에 테스트 존재
- 보안 이슈 없음
- 성능 안티패턴 없음
- story acceptance criteria 충족

### REJECTED 조건 (하나라도 해당 시)

- validate.sh 실패
- 아키텍처 경계 위반
- 보안 취약점 발견
- 하드코딩된 시크릿/포트
- acceptance criteria 미충족
- 테스트 없이 핵심 로직 변경

## 리뷰 출력 형식

```
APPROVED
Summary: [변경 요약 1줄]
```

```
REJECTED
Issues:
1. [CRITICAL] 파일:라인 - 설명
2. [IMPORTANT] 파일:라인 - 설명
3. [NIT] 파일:라인 - 설명
Suggestion: [수정 방향]
```
