# docs/agents/coding-rules.md
#
# 코드 작성 시 에이전트가 따라야 하는 규칙입니다.
# ⚠️ 프로젝트의 기술 스택에 맞게 수정하세요.
# 기본 언어 컨벤션(camelCase, PascalCase 등)은 에이전트가 이미 알고 있으므로
# 이 프로젝트 특유의 규칙만 기록합니다.

## 파일 구조

- 한 파일에 하나의 주요 export
- 파일 크기 300줄 이하 권장 (초과 시 분리)
- index 파일은 re-export 용도로만 사용

## 환경 설정

- 모든 설정값은 환경변수로 관리 (하드코딩 금지)
- 포트, URL, DB 연결 문자열을 소스 코드에 직접 쓰지 않음
- `.env.example`에 필요한 변수 목록 유지

## 로깅

- `console.log`를 프로덕션 코드에서 사용하지 않음
- 프로젝트 로거 사용 (pino, winston 등 — 기술 스택에 맞게 선택)
- 로그는 JSON 구조화 형식: `{ timestamp, level, message, requestId, service }`
- 로그 레벨: error, warn, info, debug

## 에러 처리

- 모든 외부 호출에 try-catch 또는 에러 경계 적용
- 사용자에게 의미 있는 에러 메시지 제공
- 에러 로그에 context 포함 (어떤 작업 중 발생했는지)
- 내부 에러 상세는 클라이언트에 노출하지 않음

## 의존성

- 새 의존성 추가 시 이유를 커밋 메시지에 기록
- 유사 기능의 기존 의존성이 있으면 새로 추가하지 않음
- dev dependency와 production dependency 구분

## 커밋

- 형식: `type(scope): description`
- type: feat, fix, refactor, test, docs, chore
- scope: story 이름 또는 모듈 이름
- 하나의 커밋에 하나의 논리적 변경
