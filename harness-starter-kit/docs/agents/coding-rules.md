# docs/agents/coding-rules.md
#
# 코드 작성 시 에이전트가 따라야 하는 규칙입니다.
# ⚠️ 프로젝트의 기술 스택에 맞게 수정하세요.

## 네이밍

- 파일: kebab-case (예: user-profile.ts)
- 컴포넌트: PascalCase (예: UserProfile)
- 함수/변수: camelCase (예: getUserProfile)
- 상수: UPPER_SNAKE_CASE (예: MAX_RETRY_COUNT)
- 타입/인터페이스: PascalCase (예: UserProfile)

## 파일 구조

- 한 파일에 하나의 주요 export
- 파일 크기 300줄 이하 권장 (초과 시 분리)
- index 파일은 re-export 용도로만 사용

## 에러 처리

- 모든 외부 호출에 try-catch 또는 에러 경계 적용
- 사용자에게 의미 있는 에러 메시지 제공
- 에러 로그에 context 포함 (어떤 작업 중 발생했는지)

## 의존성

- 새 의존성 추가 시 이유를 커밋 메시지에 기록
- 유사 기능의 기존 의존성이 있으면 새로 추가하지 않음
- dev dependency와 production dependency 구분

## 커밋

- 형식: `type(scope): description`
- type: feat, fix, refactor, test, docs, chore
- scope: story 이름 또는 모듈 이름
- 하나의 커밋에 하나의 논리적 변경
