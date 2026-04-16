# private/

이 폴더는 **외부 공개하면 안 되는 내부 정보**를 보관하는 곳입니다. `.gitignore`가 이 폴더 전체를 기본적으로 Git에서 제외합니다(이 `README.md`만 예외).

## 어떤 파일을 넣어야 하나

다음 성격의 파일을 이 폴더에 배치하세요:

- 사내 IP 주소, 내부 도메인
- 백업 서버 접속 정보
- 실제 값이 채워진 포트 레지스트리 (`docker-port-registry.md`)
- SSH 키, 개인 API 키 (실제 값이 필요한 경우)
- 고객사 목록, 내부 서비스 상세
- 사내 보안 정책 원본 문서

외부 공개 가능한 **template**과 **규칙 문서**는 `docs/` 아래에 그대로 둡니다:

- `docs/org/docker-port-registry.template.md` — 공개 template (커밋됨)
- `private/docker-port-registry.md` — 실제 값 (커밋 제외)

## 사용 규칙

1. **새 파일을 추가하기 전** Git에서 제외되는지 확인: `git status`에 해당 파일이 안 나와야 함
2. **이미 커밋된 내부 정보를 발견**하면: 먼저 `private/`으로 이동, `.gitignore`에서 제외, Git 히스토리에서 제거(`git filter-repo` 또는 BFG)
3. **다른 사람과 공유**해야 하면: Notion, 내부 Wiki, 또는 private submodule로 이관. 이 폴더 자체를 zip으로 보내지 말 것

## AI 에이전트 지침

AI 도구(Claude Code, Codex 등)는 이 폴더의 파일을 **참조만** 하고 절대 외부로 내보내지 않아야 합니다:

- 커밋 메시지에 내부 정보 포함 금지 (`pre-commit` hook이 `.env` 유형은 차단하지만 `private/` 내용도 경계)
- 이슈/PR 본문, 외부 도구(웹훅, Slack)에 원문 복사 금지
- 스크린샷/로그에 내부 IP가 포함되지 않도록 주의

## 복구

실수로 커밋한 파일은 아래로 복구:

```bash
# 1. private/로 이동 + git 추적 해제
git mv <파일> private/<파일>
git rm --cached <파일>
git commit -m "chore(security): move <파일> to private/"

# 2. 이미 원격에 푸시되었으면 히스토리 재작성 필요 (위험)
#    git filter-repo --path <파일> --invert-paths
#    그 후 force-push (팀원에게 알림 필수)
```
