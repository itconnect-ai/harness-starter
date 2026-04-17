# 기존 프로젝트에 Harness 입히기 (Brownfield)

이미 코드·CI·배포 파이프라인이 돌고 있는 프로젝트에 harness를 단계적으로 적용하는 가이드입니다.
신규 프로젝트 셋업은 [README.md](README.md)를 참고하세요.

---

## 핵심 원칙

**`install.sh`의 기본 모드가 이미 brownfield 친화적**입니다 — 기존 파일은 자동 skip하고 덮어쓰지 않습니다. `--force`는 쓰지 마세요.

```bash
# 기존 프로젝트 루트에서
curl -fsSL https://raw.githubusercontent.com/itconnect-ai/harness-test/main/scripts/install.sh -o install.sh
bash install.sh --dry-run   # 무엇이 설치되고 무엇이 skip될지 먼저 확인
bash install.sh             # 실제 설치 (기존 파일 skip)
```

---

## 3단계 롤아웃

단일 big-bang 대신 **단계별로 적용**하세요. 한 번에 전부 켜면 어디서 깨졌는지 추적 불가.

### Phase A — 문서만 (1주차: 팀 합의)

install.sh가 자동으로 추가하는 것 (기존에 없으니 충돌 0):

- `docs/agents/` (12개 규칙 문서)
- `docs/checklists/`, `docs/future-upgrades/`, `templates/`
- `AGENTS.md`, `CLAUDE.md`, `REVIEW.md` (기존에 있으면 skip — **수동 병합 필요**, 아래 표 참고)

이 시점에는 harness가 **참고 자료로만** 작동합니다. 아무것도 강제되지 않으므로 팀이 편하게 읽고 합의할 수 있습니다.

### Phase B — 검증 스크립트 + git hooks (2주차: 개발자 경험)

```bash
# 1. scripts/ 전체 (기존 이름 겹치는 것만 skip)
# 2. .githooks/ + .claude/hooks/ + .claude/settings.json
./scripts/setup/init-harness.sh   # git hooks 활성화 + (조건부) GitHub 보안 설정
```

**주의**: 기존에 **husky**가 있으면 아래 "husky 충돌 해결" 섹션 먼저 처리.

이 시점부터:
- `git commit`이 Conventional Commits 형식 검증
- `git push`가 GitHub Secret Scanning 통과
- `./scripts/validate.sh`로 로컬 검증 가능

### Phase C — 자동화 (3주차 이후: CI/CD)

```bash
# 1. .github/workflows/ + .github/dependabot.yml
# 2. setup-repo.sh로 Branch Protection 적용
./scripts/setup/setup-repo.sh
```

이 시점부터:
- PR은 CI + Gitleaks + CodeQL + Trivy 통과해야만 merge
- Dependabot이 주간 PR 생성
- `v*.*.*` 태그 push 시 GitHub Release 자동 생성

---

## 수동 병합 필요 — install.sh가 skip하는 영역

기존에 이미 있으면 install.sh가 건드리지 않습니다. **수동 병합**하세요:

| 기존 파일 | 병합 방법 |
|---|---|
| `README.md` | harness의 내용을 본인 README에 **append하지 말고**, `README-harness.md`로 저장해 참고 |
| `CLAUDE.md` | "Build, Test & Quality" 섹션 + `@import` 목록을 본인 내용에 추가 |
| `AGENTS.md` | "Docker & DB 작업 의무 규칙" + "참조 파일" 목록을 추가 |
| `.gitignore` | `state/validate/`, `state/db-backups/`, `private/*`, `docs/org/docker-port-registry.md` 규칙 append |
| `.gitattributes` | `*.sh eol=lf`, `.githooks/* eol=lf` append |
| `.github/workflows/ci.yml` | **병합 필요**. Phase 1의 `quality-gate` job 이름만 맞추면 branch protection 작동. 기존 단계 유지 + 누락된 단계(coverage, audit 등) 추가 |
| `.github/dependabot.yml` | 기존에 있으면 `updates:` 배열에 harness 항목 추가 |
| `.claude/settings.json` | `hooks` 객체를 병합 (PreToolUse/PostToolUse/SessionStart/Stop 각각 배열 병합) |
| `package.json` scripts | harness가 가정하는 이름과 맞추기: `lint`, `typecheck`, `test`, `build` |

**병합 명령 예시**:
```bash
# 기존 파일과 비교해서 어디를 병합해야 할지 diff로 확인
bash install.sh --dry-run > install-plan.txt
# 충돌 지점은 git stash + install.sh --force로 적용 + 수동 병합 후 stash pop
```

---

## husky 충돌 해결

harness는 `core.hooksPath` 방식을 쓰고 husky는 `.git/hooks/` 심링크 방식을 씁니다. **둘 다 유지 불가**.

**옵션 1: harness로 통일 (권장)**
```bash
npm uninstall husky
npx husky uninstall 2>/dev/null || true
# 기존 husky 훅의 내용을 .githooks/pre-commit 등으로 옮기기
./scripts/setup/install-git-hooks.sh
```

**옵션 2: husky 유지**
```bash
# harness의 .githooks/* 내용을 .husky/ 아래로 옮김
cp .githooks/pre-commit .husky/pre-commit
cp .githooks/commit-msg .husky/commit-msg
rm -rf .githooks
# setup/install-git-hooks.sh는 실행하지 않음
```

---

## 적용 후 필수 커스터마이징

harness 규칙 파일들은 **일반론**으로 쓰여있어 기존 프로젝트에 맞게 조정해야 합니다:

- [ ] `docs/agents/architecture-rules.md` — 기존 레이어 구조 반영
- [ ] `docs/agents/coding-rules.md` — 기존 ESLint/Prettier·로거 이름 반영
- [ ] `docs/agents/testing-rules.md` — 실제 테스트 러너·커버리지 기준
- [ ] `docs/agents/deploy-rules.md` — 실제 배포 타겟 반영
- [ ] `docs/agents/docker-rules.md` — 기존 docker-compose 네이밍과 비교
- [ ] `scripts/validate.sh` — `npm run lint` 부분을 실제 명령(`pnpm lint`, `yarn test` 등)으로
- [ ] `.claude/hooks/run-checks.sh` — 변경 파일 확장자 조정 (Go면 `.go`, Python이면 `.py`)
- [ ] `CLAUDE.md`의 "Build, Test & Quality" 섹션 — 실제 명령으로

---

## 검증

적용 후 실제로 작동하는지 확인:

```bash
# 1. validate가 기존 테스트와 잘 맞는지
./scripts/validate.sh

# 2. commit hook이 기존 워크플로우 안 깨는지
echo "# test" >> temp.md && git add temp.md
git commit -m "test(harness): verify hook"
git reset HEAD~1 && rm temp.md

# 3. 임시 PR로 CI 통과 확인
git checkout -b chore/harness-integration
git push -u origin chore/harness-integration
gh pr create --draft --title "[test] harness integration"
# CI 통과하면 harness가 정상 작동. 실패하면 로그 확인 후 수정.
```

---

## 롤백

Phase별로 분리 적용했다면 역순으로 되돌릴 수 있습니다:

```bash
# Phase C 롤백 (workflow만 비활성화)
mv .github/workflows/security.yml .github/workflows/security.yml.disabled
mv .github/workflows/dependabot-auto-merge.yml ...disabled
# 또는 Branch Protection의 required checks 해제 (GitHub UI)

# Phase B 롤백 (git hooks 비활성화)
git config --unset core.hooksPath
# 또는
rm -rf .githooks .claude/hooks .claude/settings.json

# Phase A 롤백 (문서 제거 — 거의 할 일 없음)
rm -rf docs/agents docs/checklists docs/future-upgrades templates
```

harness 파일 전체를 한 번에 제거하려면:
```bash
# install.sh가 설치한 경로 기준으로 삭제
# 단, 수동 병합한 파일(README/CLAUDE.md 등)은 개별 복구 필요
```

---

## 자주 발생하는 문제

| 증상 | 원인 | 해결 |
|---|---|---|
| `git commit` 시 "Conventional Commits 형식이 아닙니다" | commit 메시지가 `type(scope): description` 형식 아님 | 메시지 형식 맞추거나, 1회 허용은 `git commit --no-verify` |
| `docker-guard-hook.sh`가 `prisma migrate deploy`를 차단 | 래퍼 미사용 | `./scripts/db-migrate.sh --cmd "prisma migrate deploy"` 사용 |
| CI의 `required status checks` 이름 불일치 | 기존 job 이름이 `quality-gate`와 다름 | `setup-repo.sh`의 contexts 수정 또는 기존 CI job 이름을 `quality-gate`로 변경 |
| Windows에서 `install.sh` 실행 실패 | Git Bash 미설치 또는 CRLF 문제 | Git for Windows 설치 + `git config core.autocrlf input` |
| `validate.sh`가 template 상태 기준 skip 출력만 반복 | `package.json` 없거나 npm 스크립트 이름 불일치 | `scripts/validate.sh`의 `npm run *` 부분을 프로젝트 실제 명령으로 교체 |

---

## 추가 자료

- 전체 하네스 구조: [README.md](README.md)
- 규칙 상세: [docs/agents/](docs/agents/)
- 향후 확장 가이드: [docs/future-upgrades/](docs/future-upgrades/)
- Docker/DB 작업 지시 표준: [README.md의 "Docker / DB 작업 지시 표준"](README.md) 섹션
