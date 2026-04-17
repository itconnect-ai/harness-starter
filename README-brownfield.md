# 기존 프로젝트에 Harness 입히기 (Brownfield)

신규 프로젝트 셋업은 [README.md](README.md) 참고.

---

## 1단계: 필수 파일 설치

기존 프로젝트 루트에서 아래 명령어 실행:

**bash / WSL / macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/itconnect-ai/harness-test/main/scripts/install.sh | bash
```

**Windows PowerShell:**
```powershell
iwr https://raw.githubusercontent.com/itconnect-ai/harness-test/main/scripts/install.ps1 -UseBasicParsing | iex
```

기본 모드는 기존 파일 skip — 충돌 없이 안전.

---

## 2단계: Claude Code에 통합 프롬프트 붙여넣기

Claude Code를 열고 **아래 프롬프트 전체를 복사해서 실행**.

> 지원 범위:
> - **언어**: Node.js/TypeScript (완전 지원), Python/Go/Rust/Java (감지 + 명령 매핑 지원)
> - **CI**: GitHub Actions (완전 지원), 다른 CI(GitLab/CircleCI/Jenkins/Bitbucket/Azure)는 감지 후 사용자에게 처리 선택 요청
> - **Monorepo**: npm/pnpm/yarn workspaces, turborepo, nx, lerna 감지 지원
> - **실행 환경**: Claude Code의 Bash 도구(내부적으로 bash). Windows도 동일
> - **멱등성**: 여러 번 실행해도 안전 (이미 병합된 내용은 skip, 백업은 타임스탬프로 구분)

````markdown
# Harness Brownfield 통합

이 프로젝트는 기존 코드베이스입니다. 방금 `scripts/install.sh` (또는
`install.ps1`)로 harness 필수 파일들이 추가됐습니다. 기존 프로젝트 구성과
**충돌 없이 통합**해 주세요. 기본은 append/merge, 모순되는 부분만 백업 후
교체합니다.

## 0. 사전 조건 검증 (최우선, 실패 시 중단)

아래 중 하나라도 실패하면 stop하고 사용자에게 보고:

1. **install.sh 설치 결과물 확인** (install.sh 파일 자체가 아닌, 설치로
   생긴 파일들):
   ```bash
   test -d docs/agents && test -f scripts/validate.sh && test -f .githooks/pre-commit
   ```
   위 3개 중 하나라도 없으면 → "1단계 install.sh(또는 install.ps1)를 먼저
   실행해 주세요" 출력 후 중단.

2. **작업 디렉토리 고정**: 모든 명령을 프로젝트 루트에서 실행.
   세션 시작 시 한 번:
   ```
   cd "$(git rev-parse --show-toplevel)"
   ```

3. **git 상태 확인**: `git status --porcelain`의 출력이 비어있지 않으면
   uncommitted 변경 있음. 사용자에게 아래 중 하나 선택 요청:
   - `git stash push -m "pre-harness-integration"` 후 진행 (끝에 pop 안내)
   - 먼저 `git commit` 후 진행
   - 중단

4. **PowerShell cmdlet 호출 금지**: AI가 Claude Code의 Bash 도구를 쓰는
   한 bash 환경이 보장됨. 별도 체크 불필요. 단, 프롬프트 전반에서
   PowerShell 전용 명령(`Remove-Item`, `Get-Content` 등) 호출 금지. 모든
   명령은 bash 문법만 사용.

5. **세션 TIMESTAMP 고정**: 아래를 세션 시작 시 **단 한 번** 설정하고
   이후 모든 백업 파일명에 재사용.
   ```
   TIMESTAMP=$(date +%Y%m%d_%H%M%S)
   ```

6. **docs/legacy/ 디렉토리 사전 생성**:
   ```
   mkdir -p docs/legacy
   ```

7. **멱등성 체크** (재실행 시): 이전 실행의 흔적이 있으면 중복 작업을
   피하기 위해 감지:
   - `git log --oneline | grep -c "chore(harness):"` — 이전 harness 통합
     commit이 3개 이상이면 이미 실행됨. 사용자에게 "이미 harness 통합
     이력 감지됨. 차이분만 적용할까요, 아니면 중단할까요?" 질문.
   - `docs/legacy/*.bak` 파일이 있으면 이전 실행의 백업. 이번 실행은
     `${TIMESTAMP}` 접미사로 자동 구분되므로 덮어쓰지 않음.

## 1. 현황 분석 (읽기만, 수정 금지)

### 1-a. 프로젝트 구성 파악

**언어·스택 감지** (아래 매핑에 모두 해당하는 파일을 감지):

| 파일 | 의미 |
|---|---|
| `package.json` | Node.js/TypeScript (lint/typecheck/test/build scripts 확인) |
| `pyproject.toml` / `requirements.txt` / `poetry.lock` / `uv.lock` | Python (ruff/pytest/poetry/uv 감지) |
| `go.mod` | Go (gofmt/go vet/go test) |
| `Cargo.toml` | Rust (cargo fmt/clippy/test) |
| `pom.xml` / `build.gradle` / `build.gradle.kts` | Java/Kotlin (mvn/gradle) |
| `Gemfile` | Ruby |

**패키지 매니저 감지**:
- Node: `package-lock.json` → npm, `yarn.lock` → yarn, `pnpm-lock.yaml` → pnpm
- Python: `poetry.lock` → poetry, `uv.lock` → uv, 그 외 → pip
- 없으면 기본값 가정 (npm)

**Monorepo 감지**:
- `package.json`의 `workspaces` 필드
- `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `lerna.json` 존재 여부
- 감지되면 사용자에게 "루트만 적용 vs 각 패키지별 적용" 질문

**기존 CI 시스템 감지**:
- `.github/workflows/*.yml` — GitHub Actions (harness 기본)
- `.gitlab-ci.yml` — GitLab CI
- `.circleci/config.yml` — CircleCI
- `Jenkinsfile` — Jenkins
- `bitbucket-pipelines.yml` — Bitbucket Pipelines
- `azure-pipelines.yml` — Azure Pipelines

GitHub Actions 외 다른 CI 감지되면 D 섹션(사용자 선택)에 포함.

**기타 읽기** (수정 없이):
- `ls -la` 루트
- `.github/workflows/` 안의 모든 yml
- 기존 `.gitignore`, `.gitattributes`
- 기존 `CLAUDE.md`, `AGENTS.md`, `README.md` (있으면)
- `.husky/` 디렉토리 존재 여부
- 기존 `docker-compose*.yml`, `Dockerfile`
- 테스트 러너 감지 (vitest/jest/mocha/pytest/go test/cargo test 등)

**주 언어 비율 계산** (노이즈 제외):
```
git ls-files | grep -v -E '^(node_modules|\.git|dist|build|coverage|vendor|\.venv|venv|__pycache__|target|\.next|\.turbo)/' \
  | awk -F. '{print $NF}' | sort | uniq -c | sort -rn | head -10
```

### 1-b. Harness 규칙과 모순되는 기존 내용 감지

기존 `CLAUDE.md`, `AGENTS.md`, `README.md` 내용을 **의미 기반으로 분석**
(한국어·영어·일본어 등 언어 무관). 아래 패턴과 **의미가 같으면** 감지:

| 모순 패턴 (예시) | Harness 기준 |
|---|---|
| "main에 직접 push" / "push directly to main" | develop → main 흐름 |
| "console.log 사용 가능" / "ok to use print()" | 구조화 로거 강제 |
| "docker compose down -v 사용" | 절대 금지 |
| "prisma/flyway migrate 직접 호출" | `./scripts/db-migrate.sh` 래퍼 필수 |
| "husky 기반 pre-commit" | `.githooks/` 또는 선택된 옵션에 맞게 |
| "validate 없이 commit" | validate-quick 통과 후 commit 필수 |
| "feature/ 브랜치만 사용" (develop 없음) | story/* → develop → main |
| "SSH 키 저장소 커밋" / 기타 security-rules 위배 | 교체 |
| "환경 구분 없이 docker" / "dev/prod 혼용" | compose name 환경 접미사 + x-environment 라벨 |

추가로 AI 판단: harness의 `docs/agents/*-rules.md` 12개와 상반되는
**모든 구문**을 의미 기반으로 목록화.

### 1-c. 통합 계획 출력

분석 결과를 아래 형식으로 출력:

```
## 통합 계획

### A. 신규 설치 (충돌 없음, install.sh가 이미 처리)
- [파일 목록]

### B. 병합 — 누락 섹션 append (기존 내용 보존)
- .gitignore: [추가할 라인]
- .gitattributes: [추가할 규칙]
- .github/workflows/ci.yml: [누락 step]
- .github/dependabot.yml: [누락 ecosystem]
- .claude/settings.json: [hooks 병합]
- CLAUDE.md/AGENTS.md의 누락 섹션
- package.json scripts alias (있으면)

### C. 모순 교체 — 기존 내용이 harness와 충돌 (docs/legacy/에 백업)
- CLAUDE.md:
  - [섹션]: "[기존]" → "[harness 기준]"
- AGENTS.md:
  - [섹션]: "[기존]" → "[harness 기준]"
- README.md:
  - [섹션]: "[기존]" → "[harness 기준]"

### D. 사용자 선택 필요
- husky 감지됨: 옵션 A(harness 통일) vs B(husky 유지) — 어느 쪽?
- CI job 이름: 기존 '[감지된 이름]' → 'quality-gate'로 rename?
  (rename yes면 setup-repo.sh를 마지막에 재실행해 branch protection
  required checks 업데이트)
- 기존 CI 시스템 '[감지된 시스템]' 감지 (예: GitLab CI):
  (a) 기존 유지 + harness GH Actions 제거
  (b) GH Actions 추가 (기존과 병행)
  (c) 마이그레이션 (기존 제거, harness GH Actions로 교체)
- Monorepo 감지: 루트만 적용 vs 각 패키지에 적용?

### E. 스택별 커스터마이징 (자동 수정)
- 언어: [감지 결과] / 패키지 매니저: [감지 결과] / 테스트 러너: [감지]
- scripts/validate.sh, validate-quick.sh: 명령 교체
  [현재: npm run lint → 변경: <감지된 명령>]
- scripts/db-migrate.sh: DB 도구 매핑 확인 (prisma/flyway/alembic/...)
- .claude/hooks/run-checks.sh: 확장자 [ts/tsx → 실제]
- docs/agents/coding-rules.md: 로거 [감지 결과]
- docs/agents/testing-rules.md: 러너 [감지 결과]
- docs/agents/deploy-rules.md: 배포 타겟 [감지 결과]
```

## 2. 사용자 승인 (일괄 게이트 — 단 1회)

분석 출력(A~E)을 보여준 뒤 **한 번에 묻고** 대답을 기다리세요:

```
위 계획 전체로 진행할까요?
  - yes: 계획대로 실행 (C 교체 + E 커스터마이징 모두 자동)
  - no: 중단
  - 항목 제외: "C의 CLAUDE.md 3번째 항목 제외" 같은 형식으로 지정
  - D의 선택은 아래 답변에 포함:
      husky: A 또는 B
      CI rename: yes 또는 no
      기존 CI 처리: a/b/c
      monorepo: root-only 또는 per-package
```

"yes"만 답하면 → D 기본값: husky A, CI rename yes, 기존 CI b(병행), monorepo root-only.

사용자 응답 전에는 어떤 파일도 수정 금지.

## 3. 단계별 자동 병합

각 단계마다 **정확한 파일만 `git add`** 하여 독립 commit. 다른 변경이
섞이지 않도록.

**3-1. .gitignore 병합** (`chore(harness): merge .gitignore rules`)

기존 파일 끝에 append (중복 라인 제외):
```
# ── Harness Engineering rules ──────────────────────
state/validate/
state/db-backups/
private/*
!private/README.md
docs/org/docker-port-registry.md
docs/org/*.local.md
```

```
git add .gitignore
git commit -m "chore(harness): merge .gitignore rules"
```

**3-2. .gitattributes 병합** (`chore(harness): merge .gitattributes`)

기존에 `*.sh eol=lf` 없으면 추가. `.githooks/* eol=lf` 추가.
```
git add .gitattributes
git commit -m "chore(harness): merge .gitattributes"
```

**3-3. CLAUDE.md 병합 + 모순 교체** (`chore(harness): align CLAUDE.md with harness`)

3-a. 기존 CLAUDE.md가 있고 1-b에서 감지한 모순 구문이 있으면:
- `cp CLAUDE.md docs/legacy/CLAUDE.md.${TIMESTAMP}.bak`
- 모순되는 섹션을 harness 기준 문구로 치환 (섹션 단위)
- 한 섹션 안에서 일부만 모순이면 그 부분만 치환, 주변 맥락 보존

3-b. `@import` 지시 섹션이 없으면 파일 끝에 추가 (12개 규칙 파일 import).

3-c. "Build, Test & Quality" 섹션을 **감지된 패키지 매니저 + scripts로
생성/업데이트**. 4개 명령(lint / typecheck / test / build) 각각에 대해
아래 매핑 참고:

| 스택 | lint | typecheck | test | build |
|---|---|---|---|---|
| npm | `npm run lint` | `npm run typecheck` | `npm run test` | `npm run build` |
| pnpm | `pnpm lint` | `pnpm typecheck` | `pnpm test` | `pnpm build` |
| yarn | `yarn lint` | `yarn typecheck` | `yarn test` | `yarn build` |
| Python (poetry) | `poetry run ruff check .` | `poetry run mypy .` | `poetry run pytest` | `poetry build` |
| Python (uv) | `uv run ruff check .` | `uv run mypy .` | `uv run pytest` | `python -m build` |
| Python (pip) | `ruff check .` | `mypy .` | `pytest` | `python -m build` |
| Go | `gofmt -l . && go vet ./...` | (Go는 컴파일이 typecheck) | `go test ./...` | `go build ./...` |
| Rust | `cargo fmt --check && cargo clippy -- -D warnings` | (Rust는 컴파일이 typecheck) | `cargo test` | `cargo build --release` |
| Java (Maven) | `mvn checkstyle:check` | (컴파일이 typecheck) | `mvn test` | `mvn package` |
| Java (Gradle) | `./gradlew check` | (컴파일이 typecheck) | `./gradlew test` | `./gradlew build` |

**중요**:
- npm만 `run` **필수**, pnpm/yarn은 `run` 생략 가능 (둘 다 허용, 프로젝트
  기존 스타일 따름)
- Go/Rust처럼 typecheck가 build에 통합된 언어는 해당 칸을 비우고 build만
  명시 (프롬프트 결과물에도 해당 칸 생략 또는 "N/A — build에 통합")
- 프로젝트별로 이 매핑과 다른 명령을 쓰면 실제 scripts/Makefile의 내용을
  우선

기존 CLAUDE.md 없으면 3-c만 수행 (install.sh로 이미 설치됨).

```
git add CLAUDE.md docs/legacy/CLAUDE.md.${TIMESTAMP}.bak
git commit -m "chore(harness): align CLAUDE.md with harness"
```

**3-4. AGENTS.md 병합 + 모순 교체** (`chore(harness): align AGENTS.md with harness`)

4-a. 기존 AGENTS.md에 1-b 모순 있으면:
- `cp AGENTS.md docs/legacy/AGENTS.md.${TIMESTAMP}.bak`
- 모순 섹션 치환

4-b. "Docker & DB 작업 의무 규칙" 섹션이 없으면 추가.
4-c. "참조 파일" 목록이 없거나 불완전하면 harness 기준 12개 규칙 파일로
     교체/추가.
4-d. "Repo map" 섹션이 있으면 **기존 포맷 유지하며** 실제 디렉토리 구조로
     업데이트 (`git ls-files | head`, `ls src/`, `ls apps/` 결과 참고).

```
git add AGENTS.md docs/legacy/AGENTS.md.${TIMESTAMP}.bak
git commit -m "chore(harness): align AGENTS.md with harness"
```

**3-4b. README.md 모순 교체** (`chore(harness): align README.md with harness`)

기존 README.md에 1-b 모순이 있으면:
- `cp README.md docs/legacy/README.md.${TIMESTAMP}.bak`
- 모순 섹션만 치환. 프로젝트 고유 소개/설치/라이선스 등 harness와 무관한
  내용은 보존.

모순 없으면 skip.
```
git add README.md docs/legacy/README.md.${TIMESTAMP}.bak
git commit -m "chore(harness): align README.md with harness"
```

**3-5. husky 충돌 해결** (`chore(harness): resolve husky conflict`)

`.husky/` 디렉토리 있을 때 D에서 선택된 옵션 실행:

- **옵션 A (harness 통일)**:
  1. `mv .husky .husky.backup.${TIMESTAMP}` (원본 보존)
  2. 기존 `.husky/pre-commit` 내용을 `.githooks/pre-commit` **상단**에
     병합 (harness 내용은 그 아래에 유지)
  3. `.husky/commit-msg` 있으면 `.githooks/commit-msg`와 병합
  4. `npm uninstall husky` + package.json scripts에서 `"prepare":
     "husky install"` 제거

- **옵션 B (husky 유지)**: (전제: `.husky/` 디렉토리가 이미 존재)
  1. `.husky/pre-commit` 파일 처리:
     - 이미 있으면 → 기존 내용 **상단에 유지**하고 `.githooks/pre-commit`
       내용을 그 **아래에 append** (덮어쓰지 않음)
     - 없으면 → `.githooks/pre-commit`을 `.husky/pre-commit`으로 복사
  2. `.husky/commit-msg`도 동일 로직
  3. `.githooks/` 디렉토리 제거 (중복 방지)
  4. `core.hooksPath` 설정하지 않음 (husky가 자체 훅 경로 관리)
  5. package.json에 `"prepare": "husky install"` (또는 husky 9의 `"prepare":
     "husky"`)이 없으면 사용자에게 추가 제안

```
git add -A
git commit -m "chore(harness): resolve husky conflict (option <A|B>)"
```

**3-6. CI workflow 병합** (`chore(harness): merge CI workflow`)

**D의 "기존 CI 처리" 답변에 따라 분기**:

**옵션 a (기존 유지 + harness GH Actions 제거)**:
- 감지된 비 GH Actions CI(GitLab 등) 유지
- `rm .github/workflows/ci.yml .github/workflows/security.yml
  .github/workflows/release.yml .github/workflows/deploy.yml
  .github/workflows/dependabot-auto-merge.yml` — install.sh가 설치한 GH
  Actions 파일 제거
- `.github/dependabot.yml`은 유지 (Dependabot은 GitHub 기능이므로 기존 CI
  시스템과 무관하게 작동)
- 기존 CI에 Phase 1의 해당하는 job을 추가하라는 **안내만** 출력 (자동
  변환은 위험 — skip)

**옵션 b (병행)**:
- 기존 비 GH Actions CI와 harness GH Actions 둘 다 유지
- 두 시스템이 동시에 돌면 중복 실행 — 사용자에게 경고:
  ```
  ⚠ 기존 <GitLab CI 등>과 harness GH Actions가 동시에 빌드합니다.
    CI 리소스·시간이 2배로 듭니다. 일정 기간 안정성 확인 후
    옵션 a 또는 c로 전환 권장.
  ```

**옵션 c (마이그레이션)**:
- 기존 CI 파일 보존 후 제거:
  - `.gitlab-ci.yml` → `docs/legacy/.gitlab-ci.yml.${TIMESTAMP}.bak`
  - 동일하게 Jenkinsfile, `.circleci/config.yml` 등
- `git rm <기존 CI 파일>`
- harness GH Actions 유지

**기존 GitHub Actions(`.github/workflows/ci.yml`)가 이미 있는 경우 (옵션과 무관)**:
- harness의 ci.yml과 diff해서 **누락된 step만** 추가 (coverage, audit
  upload, docker-build job 등)
- 기존 trigger(main/develop) 유지
- D에서 "CI rename yes"면:
  1. 기존 job 이름을 `quality-gate`로 rename
  2. job 안의 모든 step은 그대로 유지 (기존 + 추가된 것)
  3. 이 rename으로 기존 branch protection의 required status checks가
     깨짐 → 마지막 7단계에서 `setup-repo.sh` 재실행 필수

```
git add .github/workflows/ docs/legacy/    # 옵션 c면 docs/legacy/ 포함
# 옵션 a면 .gitlab-ci.yml 등은 변경 없음, git rm으로 제거된 파일들만 스테이징
git commit -m "chore(harness): merge CI workflow (<선택된 옵션>)"
```

**3-7. Dependabot 병합** (`chore(harness): merge dependabot`)

기존 `.github/dependabot.yml` 있으면:
- updates 배열에서 `(package-ecosystem, directory)` 조합이 겹치는 것은
  **기존 설정 유지** (schedule/limit 차이 무시)
- 겹치지 않는 ecosystem만 추가
- 차이점은 commit 메시지 본문에 summary로 기록

없으면 harness 것 유지.
```
git add .github/dependabot.yml
git commit -m "chore(harness): merge dependabot"
```

**3-8. Claude Code hooks 병합** (`chore(harness): merge .claude/settings.json`)

`.claude/settings.json` 있으면 hooks 객체의 각 배열을 병합:
- 각 이벤트(`PreToolUse`, `PostToolUse`, `SessionStart`, `Stop`)별로
- **dedup key = `matcher + if + command` 3개 조합**
- 동일 키면 skip, 다르면 배열에 추가

```
git add .claude/settings.json
git commit -m "chore(harness): merge .claude/settings.json"
```

**3-9. package.json / 빌드 매니페스트 scripts 검증** (`chore(harness): add script aliases`)

lint / typecheck / test / build **4개 모두** 검증:

| harness 가정 | 실제 확인 | 조치 |
|---|---|---|
| `npm run lint` | scripts.lint 존재? | 있으면 유지. 없고 eslint dep만 있으면 `"lint": "eslint ."` 제안 |
| `npm run typecheck` | scripts.typecheck 존재? | 없고 `check`가 있으면 `"typecheck": "npm run check"` alias 제안. 없고 tsc만 있으면 `"typecheck": "tsc --noEmit"` 제안 |
| `npm run test` | scripts.test 존재? | 없으면 감지된 러너로 제안 |
| `npm run build` | scripts.build 존재? | 없고 Next/Vite 감지되면 해당 명령, 없으면 skip |

**사용자 확인 없이 자동 추가 금지**. 변경 제안을 출력하고 사용자가 동의
(yes/각 항목 수락)해야 저장.

Python/Go/Rust 프로젝트면 이 단계는 skip. 대신 validate.sh를 4단계에서
언어별 명령으로 교체.

## 4. 스택별 커스터마이징 (E 섹션 실행)

이 단계는 3개의 독립 commit으로 나뉨: 4-1 스크립트 커스터마이징,
4-2 테스트 러너 `--changed` 지원 검증, 4-3 Docker compose 검증/교정.

**4-1. 스크립트 + 규칙 문서 커스터마이징** (`chore(harness): customize for <언어+매니저+러너>`)

**Monorepo 스코프 처리**: D에서 `monorepo: per-package`를 선택했으면:
- `scripts/`는 루트에 유지 (공통)
- 그러나 `scripts/validate.sh`의 실행 명령이 각 workspace에서 돌도록
  수정 (예: pnpm workspace면 `pnpm -r run lint`, turborepo면 `turbo run
  lint`)
- 각 패키지 디렉토리에 `docs/agents/` 심볼릭 링크 또는 README 참조로
  "이 규칙은 repo 루트의 docs/agents/를 따릅니다" 안내 생성 (요청한 경우만)

`monorepo: root-only`를 선택했으면 루트만 처리.

**기본 커스터마이징 (스코프와 무관)**:

- `scripts/validate.sh`, `validate-quick.sh`의 `npm run *` 명령을 **3-3c의
  매핑 테이블**과 동일한 규칙으로 감지된 언어/매니저에 맞게 교체.
  (`validate-quick.sh`의 silent full-test fallback 제거 로직은 절대 건드리지
  않음 — 기존 성능 개선 유지)
- `.claude/hooks/run-checks.sh`의 case 문 확장자를 주 언어에 맞게 조정
  (예: Python이면 `*.py` 추가, Go이면 `*.go`)
- `docs/agents/architecture-rules.md`에 "## 프로젝트 실제 구조" 섹션 추가
  (기존 섹션 유지, 파일 끝에 append. Monorepo면 workspace 트리 포함)
- `docs/agents/coding-rules.md`에 "## 감지된 로거" 섹션 추가
- `docs/agents/testing-rules.md`에 "## 감지된 테스트 환경" 섹션 추가
  (러너 + 커버리지 기준이 있으면 포함)
- `docs/agents/deploy-rules.md`에 "## 감지된 배포 타겟" 섹션 추가
  (Dockerfile / vercel.json / fly.toml / netlify.toml / Procfile 등)

```
git add scripts/validate.sh scripts/validate-quick.sh .claude/hooks/run-checks.sh docs/agents/architecture-rules.md docs/agents/coding-rules.md docs/agents/testing-rules.md docs/agents/deploy-rules.md
git commit -m "chore(harness): customize for <언어+매니저+러너>"
```

**4-2. 테스트 러너 `--changed` 지원 검증** (`chore(harness): verify test runner performance`)

Story 단위 `validate-quick`이 빠르려면 테스트 러너가 "변경 파일만 테스트"
기능을 지원해야 합니다. 감지된 러너 기준으로 체크:

| 러너 | 지원 플래그 | 상태 |
|---|---|---|
| vitest | `--changed <ref>` | ✅ 완전 지원 |
| jest | `--changedSince=<ref>` | ✅ 완전 지원 |
| pytest | `--lf` / `--ff` / pytest-testmon | ⚠️ 부분 지원 (플러그인 필요) |
| mocha | 없음 | ❌ 미지원 |
| go test | 파일 레벨 지원 (`go test ./pkg/...`) | ⚠️ 디렉토리 기반 |
| cargo test | 없음 | ❌ 미지원 |

**미지원(❌) 또는 부분(⚠️)이면 사용자에게 경고 출력**:

```
⚠ 감지된 테스트 러너 <이름>은 --changed 기능을 지원하지 않습니다.
  validate-quick이 story 단위로 전체 테스트를 돌리게 됩니다.
  story당 5~10분+ 소요 가능 (과거 해결된 문제의 재발).

  권장 조치:
  1. vitest/jest로 전환 (JS/TS 프로젝트)
  2. pytest-testmon 같은 플러그인 도입
  3. validate-quick.sh가 test 단계를 skip하도록 수정
     (typecheck + lint만 돌리고 test는 validate.sh에만)
```

사용자 응답에 따라:
- "전환"/"플러그인 도입" → 사용자가 수동 진행. 프롬프트는 여기까지.
- "test skip" → `validate-quick.sh`에서 테스트 단계를 주석 처리하고 이유 기록.

```
git add scripts/validate-quick.sh   # test skip 선택한 경우만
git commit -m "chore(harness): verify test runner performance"
```

**4-3. Docker compose 검증/교정** (`chore(harness): audit docker-compose files`)

기존 `docker-compose*.yml`이 있으면 `docs/agents/docker-rules.md`와
`deploy-rules.md` 기준으로 검사:

검사 항목:
1. `name:` 필드 존재 여부 + 환경 접미사 (`-dev` / `-staging`)
2. `x-environment:` 라벨 존재 (값: `production`/`development`/`staging`)
3. 컨테이너명이 `<접두사>-<역할>` 패턴 준수, 금지 패턴(`-1`, `-new`,
   `_backend` 등) 부재
4. 볼륨 `external: true` + `name:` 명시 (DB 볼륨인 경우)
5. Backend/DB/Redis의 호스트 포트 바인딩이 주석 처리됐는지 (운영)
6. `restart: unless-stopped` 또는 `restart: always` 명시

위반 감지 시:
```
⚠ docker-compose 위반 감지:
  - docker-compose.yml: name 필드 없음, x-environment 라벨 없음
  - 컨테이너 'web-backend-1': 숫자 suffix 금지 패턴 (docker-rules §1-3 위배)
  - DB 볼륨 'postgres_data': external 선언 없음 (재생성 시 데이터 유실 위험)

  수정할까요? (각 항목 수락/거부 가능)
```

**위험도별 수정 분류** — 사용자에게 각 그룹별로 승인 받기:

**🟢 안전 수정 (즉시 적용 가능, 실행 중 container 영향 없음)**:
- `name:` 필드 없으면 추가 (예: `name: <디렉토리명>`, 운영이면 접미사
  없음, 개발이면 `-dev`)
- `x-environment:` 라벨 추가
- `restart:` 정책 추가

**🟡 중간 위험 (재배포 시 container 재생성 필요)**:
- 볼륨 `external: true` + `name:` 명시 추가 — **기존 볼륨이 있으면 이
  조치 전에 `docker volume create --name <기존-이름>`로 external 볼륨으로
  전환 필요**. AI는 기존 볼륨 이름 확인 + 전환 명령을 사용자에게 제시만
  하고 실행은 사용자 승인 후 진행.
- Backend/DB/Redis 호스트 포트 바인딩 주석 처리 — 로컬 접근 도구(DBeaver
  등)가 끊김. 사용자에게 확인.

**🔴 고위험 (데이터 유실 또는 서비스 중단 가능)**:
- **컨테이너 이름 rename은 자동 수행 금지**. 기존 실행 중 container를
  참조하는 외부 시스템(monitoring, scripts)을 깨뜨림. 대안:
  ```
  ⚠ 컨테이너명 'web-backend-1'이 금지 패턴 위반.
    자동 rename은 데이터 유실 위험이 있어 수행하지 않습니다.
    권장 절차 (수동):
    1. 현재 container 중지: docker compose stop
    2. compose 파일에서 container_name을 'web-backend'로 수정
    3. 외부 참조(monitoring, nginx proxy) 업데이트
    4. docker compose up -d
    5. 데이터 확인 후 기존 container 제거: docker rm web-backend-1
  ```

사용자 승인 받은 항목만 수정. 원본은 `docs/legacy/docker-compose.yml.${TIMESTAMP}.bak`
백업.

```
git add docker-compose*.yml docs/legacy/
git commit -m "chore(harness): audit docker-compose files (safe-only)"
```

(docker-compose 파일이 없으면 4-3 단계 skip)

## 5. 검증 (`chore(harness): verify integration`)

```
./scripts/validate.sh
```

실패하면 원인 로그 분석 후 수정 → 재시도. **최대 3회 시도 후 중단**하고
사용자에게 실패 내용 보고. 무한 루프 금지.

성공하면:
```
git add -A
git commit -m "chore(harness): verify integration"
```
(변경이 없으면 이 commit은 생략)

## 6. git hooks 활성화

D에서 husky 옵션 A 선택했으면:
```
./scripts/setup/install-git-hooks.sh
```
옵션 B(husky 유지) 선택했으면 이 단계 skip.

## 7. GitHub 보안 설정 (조건부)

```
gh auth status
```

- 인증됨 + origin 있음 + `D의 CI rename=yes`:
  ```
  ./scripts/setup/setup-repo.sh
  ```
  (CI rename 때문에 branch protection의 required status checks 업데이트
  필요)
- 인증됨 + origin 있음 + CI rename=no: `setup-repo.sh` 실행 (신규 보안
  설정 목적)
- 인증 안 됨: skip하고 "gh auth login 후 `./scripts/setup/setup-repo.sh`
  수동 실행 필요"로 안내.

## 8. 최종 푸시

```
git push
```

## 9. 완료 보고 (정해진 템플릿 사용)

```
## Harness Brownfield 통합 완료

### 감지 결과
- 언어: <Node.js/TypeScript, Python 등>
- 패키지 매니저: <npm/yarn/pnpm/poetry/uv/...>
- 테스트 러너: <vitest/jest/pytest/...>
- 기존 CI: <GitHub Actions / GitLab / ...>
- Monorepo: <yes (turborepo) / no>
- husky: <없음 / 감지됨 → 옵션 A or B로 처리>

### 처리된 변경 (commit 수)
- .gitignore / .gitattributes: <N>개
- CLAUDE.md / AGENTS.md / README.md 병합·교체: <N>개 섹션
- docs/legacy/ 에 백업된 원본: <파일 목록>
- CI workflow / dependabot / .claude hooks: 병합
- 스택별 커스터마이징 (4-1): <요약>
- 테스트 러너 --changed 검증 (4-2): <지원 / 미지원 → 조치>
- docker-compose 검증 (4-3): <위반 N개 수정 / 파일 없음>
- 총 commit: <N>개

### 검증
- validate.sh: <통과 / 실패 원인>
- git hooks 활성화: <yes / no(옵션 B)>
- GitHub 보안 설정: <적용 / skip 사유>
- 성능 위험 (4-2에서 경고 발생한 경우): <현재 러너 미지원 → story 단위
  속도 저하 가능성 알림>

### 다음 단계
- 팀에 "harness 도입됨" 공지 (커밋 범위: <A..B>)
- docs/agents/ 규칙 파일 팀 리뷰
- 첫 Epic으로 Phase A/B/C 흐름 시험 적용
- [CI rename yes인 경우] GitHub의 기존 required status checks 이름
  업데이트 확인

### 롤백이 필요하면
- 전체 되돌리기: git reset --hard <통합 전 SHA>
- 특정 단계만: git revert <해당 commit SHA>
- 원본 복구: docs/legacy/ 안의 .${TIMESTAMP}.bak 파일 참조
```

## A~E 섹션 ↔ 실행 단계 매핑

| 섹션 | 실행 단계 | 비고 |
|---|---|---|
| A. 신규 설치 | (프롬프트 외) install.sh | 이미 처리됨 |
| B. 누락 append | 3-1 / 3-2 / 3-6(누락 step) / 3-7 / 3-8 / 3-9 / 3-3·3-4·3-4b 일부 | |
| C. 모순 교체 | 3-3 / 3-4 / 3-4b (백업 후 치환) | docs/legacy/ 저장 |
| D. 사용자 선택 | 3-5(husky) / 3-6(CI rename) / 7(기존 CI 처리) / 4-1(monorepo 스코프) | 2단계 답변에 포함 |
| E. 커스터마이징 | 4-1 (스크립트·규칙 문서) / 4-2 (테스트 러너 검증) / 4-3 (docker-compose 검증) | 스택 감지 기반 |

## 강제 규칙 (절대 위반 금지)

- **사전 조건(0단계) 실패 시 즉시 중단**. install.sh 설치 결과물 미존재
  또는 uncommitted 상태에서 진행 금지.
- **멱등성 보장**: 이미 병합된 내용은 다시 append하지 않음. 이미 교체된
  섹션은 다시 교체하지 않음. dedup은 실제 내용(라인·섹션 헤더·JSON key)
  기준. 재실행 시 0단계 7번 멱등성 체크 통과해야 진행.
- **세션 TIMESTAMP 1회 고정**: 모든 백업 파일이 동일 timestamp 공유.
  재실행 시에는 새 TIMESTAMP가 생성되어 이전 백업과 충돌하지 않음.
- **bash 문법 전용**: PowerShell cmdlet 호출 금지. 모든 명령은 bash.
- **프로젝트 루트에서 실행**: 매 단계 시작 시 `cd "$(git rev-parse
  --show-toplevel)"`로 확인.
- **읽고 수정**: 모든 기존 파일은 반드시 먼저 읽은 뒤 수정.
- **백업 후 교체**: 모순 교체는 반드시 `docs/legacy/<파일>.${TIMESTAMP}.bak`
  백업 후 수정. 백업 없이 교체 금지.
- **섹션 단위 교체**: 전체 파일 덮어쓰기 금지. markdown heading 또는
  명확한 블록 단위. harness 무관 내용(프로젝트 소개/라이선스/기여
  가이드 등)은 건드리지 않음.
- **독립 commit**: 각 단계를 독립 commit으로. 정확한 파일만 `git add`
  (다른 변경 섞이면 불가).
- **최대 3회 시도**: 5단계 validate 실패 시 최대 3회. 이후 중단 + 보고.
  4-2 테스트 러너 검증에서 경고가 나오더라도 사용자가 수용하면 이 제한은
  적용 안 됨 (경고는 기록만).
- **실패 시 중단**: 어느 단계든 실패하면 stop하고 사용자에게 보고.
  그때까지의 commit은 rollback 가능한 상태로 남아있음.
- **승인 게이트 1회 + 필요 시 확인**: 2단계 일괄 승인 + D 답변은 필수.
  4-2(테스트 러너 경고)와 4-3(docker-compose 위반)은 위반 발견 시에만
  짧은 확인 요청 (수락/거부).
- **성능 보존**: `validate-quick.sh`의 silent full-test fallback 제거
  로직 및 PostToolUse hook의 "변경 파일만 eslint" 로직은 절대 건드리지
  않음. 과거 해결된 "story당 2~3시간" 문제의 재발 방지.
````

---

## AI가 자동 처리하는 것 (요약)

| 영역 | 처리 방법 |
|---|---|
| 신규 파일 설치 | install.sh가 skip-safe로 이미 처리 |
| .gitignore / .gitattributes | 헤더 구분 후 append (중복 제외) |
| CLAUDE.md / AGENTS.md / README.md — **누락 섹션** | append (기존 내용 보존) |
| CLAUDE.md / AGENTS.md / README.md — **모순 섹션** | **자동 교체** + 원본 `docs/legacy/<파일>.${TIMESTAMP}.bak` 백업 |
| husky 충돌 | 사용자 선택 후 A(harness 통일) 또는 B(husky 유지) 자동 실행 |
| CI workflow | 기존 구조 유지 + 누락 step만 추가. job rename은 사용자 선택 |
| 기존 비 GitHub Actions CI | 사용자 선택 (유지/병행/마이그레이션) |
| Monorepo | 사용자 선택 (루트만 vs 각 패키지) |
| Dependabot | 겹치지 않는 ecosystem만 추가 |
| Claude settings | matcher+if+command 3조합 키로 중복 제거 후 병합 |
| package.json scripts | 4개(lint/typecheck/test/build) 모두 검증, alias 사용자 확인 후 추가 |
| 스택별 커스터마이징 | 언어/매니저/러너/배포 타겟 감지 후 자동 수정 |
| 검증 | validate.sh 실패 시 최대 3회 재시도 |
| 배포 | GitHub 인증 조건부 자동 실행 |

**사용자가 직접 하는 일**:
1. `curl | bash` (bash) 또는 `iwr | iex` (PowerShell) 한 번
2. Claude Code에 프롬프트 붙여넣기
3. 분석 결과 확인 후 "yes" 또는 D 답변 1회
4. 끝

---

## 롤백

각 단계가 독립 commit이므로 특정 단계만 되돌리기 쉽습니다:

```bash
# 가장 최근 병합 되돌리기
git reset --soft HEAD~1

# 특정 commit만 되돌리기
git log --oneline | grep "chore(harness)"
git revert <해당 commit SHA>

# harness 통합 commit 전체를 한 번에 되돌리기
# (통합 시작 전 SHA가 <BASE>라고 가정)
git reset --hard <BASE>
```

원본 복구는 `docs/legacy/<파일>.<YYYYMMDD_HHMMSS>.bak`에서:
```bash
cp docs/legacy/CLAUDE.md.20260417_143012.bak CLAUDE.md
git commit -am "revert(harness): restore CLAUDE.md from legacy"
```

---

## 문제 해결

| 증상 | 해결 |
|---|---|
| 0단계에서 install.sh 없다고 중단 | 1단계 install.sh/ps1 먼저 실행 |
| 0단계에서 uncommitted 경고 | `git stash` 후 프롬프트 재실행, 완료 후 `git stash pop` |
| validate.sh 3회 실패 후 중단 | 로그(`state/validate/latest/*.log`) 수동 확인 + scripts/validate.sh의 명령어가 프로젝트와 맞는지 검증 |
| husky 제거 후 팀원 로컬에서 훅 안 돎 | 팀원이 pull 후 `./scripts/setup/install-git-hooks.sh` 1회 실행 필요 |
| CI rename 후 기존 PR 영원히 "대기" | `./scripts/setup/setup-repo.sh` 재실행하여 required status checks 업데이트. 또는 GitHub UI에서 수동 갱신 |
| 기존 GitLab CI 유지 중인데 harness GH Actions도 남음 | D에서 "a(GH Actions 제거)" 선택 또는 수동으로 `.github/workflows/` 제거 |
| Monorepo에서 루트만 적용 → 개별 패키지에서 validate 안 됨 | 각 패키지에서 프롬프트 재실행 (scope=per-package) 또는 수동으로 scripts 복사 |
| Python 프로젝트인데 scripts/validate.sh가 npm 그대로 | 4단계 커스터마이징이 제대로 안 됨. 수동으로 validate.sh 편집하여 `ruff check`, `pytest` 등으로 교체 |
| Windows에서 install.sh 실행 안 됨 | `install.ps1` 사용 (Git Bash 자동 호출). Git for Windows 필요 |

---

## 추가 자료

- 전체 하네스 구조: [README.md](README.md)
- 규칙 상세: [docs/agents/](docs/agents/)
- 향후 확장 가이드: [docs/future-upgrades/](docs/future-upgrades/)
