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

### 형식 (Conventional Commits)

- 첫 줄: `type(scope): 한 줄 요약` (72자 이내)
- type: feat, fix, refactor, test, docs, chore, perf, style, ci, build
- scope: story 이름 또는 모듈 이름 (소문자/숫자/하이픈)
- 하나의 커밋에 하나의 논리적 변경
- `.githooks/commit-msg`가 첫 줄 형식을 자동 검증 (install-git-hooks.sh/.ps1로 활성화)

### AI 친화 본문 구조 (권장)

AI가 나중에 `git log --grep` 또는 `git log -- <path>`로 맥락을 찾기 쉽게 본문을 구조화합니다.

```
type(scope): 한 줄 요약

파일:
- path/to/a.ts: 이 파일에서 무엇이 바뀌었나
- path/to/b.ts: 이 파일에서 무엇이 바뀌었나

이유: 이 변경이 필요했던 배경 (버그, 요구사항, incident-id 등)

관련: story-id, incident-id, PR 번호 등
```

### 원칙

- **자주 커밋하라**: 누락·오류·소실 시 유일한 복구 수단은 git. story 단위 완료마다 반드시 commit + push
- **AI가 찾을 수 있게 써라**: 파일 경로와 변경 내용을 본문에 명시하면 미래의 에이전트가 `git log`로 역추적 가능
- **type을 과하게 세분화하지 마라**: 10개 type으로 충분. 새 type 추가 시 이 문서에 기록

### 금지

- 빈 메시지, `"update"`, `"fix"` 같은 의미 없는 한 줄 커밋
- `--amend`로 push된 커밋을 덮어쓰는 행위 (항상 새 커밋 생성)
- `--no-verify`로 hook 우회 (사용자가 명시 허락한 경우만)
