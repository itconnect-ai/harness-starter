# REVIEW.md
#
# Claude Code가 코드 리뷰 시 참고하는 기준 문서입니다.
# 이 파일은 Claude Code의 Code Review 기능과 claude -p 리뷰 모두에 적용됩니다.

## 리뷰 범위

- 현재 브랜치의 main 대비 diff만 리뷰
- story 범위를 벗어난 변경이 있으면 지적
- 기존 코드의 문제는 리뷰하지 않음 (pre-existing 이슈 무시)

## 필수 확인 항목

### 1. 아키텍처 경계

- `docs/agents/architecture-rules.md`에 정의된 레이어 경계 준수 여부
- 허용되지 않은 cross-layer 의존성 여부
- 새 패턴 도입 시 `docs/decisions/`에 기록 여부

### 2. 기능 정확성

- story의 acceptance criteria를 충족하는지
- 엣지 케이스 처리 (null, empty, boundary values)
- 에러 처리 (try-catch, fallback, 사용자 피드백)

### 3. 테스트

- 변경된 동작에 대한 테스트 존재 여부
- 테스트가 실제 동작을 검증하는지 (단순 스냅샷이 아닌)
- 핵심 경로의 통합 테스트 여부

### 4. 보안

- 사용자 입력 검증
- 인증/권한 체크
- 민감 정보 노출 여부
- SQL injection, XSS 등 기본 보안 패턴

### 5. 코드 품질

- 네이밍 일관성
- 중복 코드 여부
- 불필요한 복잡성
- 주석이 필요한 곳에 주석 존재

## 판정 기준

### APPROVED 조건 (모두 충족 시)

- validate.sh 통과
- 아키텍처 경계 위반 없음
- 변경 동작에 테스트 존재
- 보안 이슈 없음
- story acceptance criteria 충족

### REJECTED 조건 (하나라도 해당 시)

- validate.sh 실패
- 아키텍처 경계 위반
- 보안 취약점 발견
- acceptance criteria 미충족
- 테스트 없이 핵심 로직 변경

## 리뷰 출력 형식

문제가 없을 때:
```
APPROVED
Summary: [변경 요약 1줄]
```

문제가 있을 때:
```
REJECTED
Issues:
1. [CRITICAL] 파일:라인 - 설명
2. [IMPORTANT] 파일:라인 - 설명
3. [NIT] 파일:라인 - 설명
Suggestion: [수정 방향]
```
