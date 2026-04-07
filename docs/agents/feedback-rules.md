# docs/agents/feedback-rules.md
#
# 과거 Epic에서 반복된 실수 패턴을 정리한 활성 교훈 파일입니다.
# 이 파일은 Phase C 회고에서 재작성됩니다 (쌓는 파일이 아님).
#
# 운영 규칙:
#   - 최대 10개 active rule만 유지 (초과 시 가장 오래된 것 retire)
#   - 각 규칙은 source incident id를 가짐
#   - 최근 2 Epic 동안 재발 없으면 retired로 이동
#   - 기계적으로 판별 가능한 패턴은 validate.sh로 승격 후 여기서 제거

## Active Rules

아직 회고가 실행되지 않았습니다.
Phase C 회고 후 이 섹션이 자동으로 채워집니다.

<!-- 예시 형식:
### 1. 테스트 누락 (missing-tests)
- source: epic-1-story-3
- 발견: Phase B 리뷰에서 2회 반복
- 규칙: 비즈니스 로직 변경 시 반드시 관련 테스트 추가
- 승격 상태: active (validate.sh 승격 검토 중)

### 2. N+1 쿼리 (n-plus-one-query)
- source: epic-1-story-5
- 발견: Phase B 리뷰에서 3회 반복
- 규칙: ORM 사용 시 include/eager loading 필수
- 승격 상태: validate.sh에 자동 감지 추가됨 → retired
-->

## Retired Rules

없음
