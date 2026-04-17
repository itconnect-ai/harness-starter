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

각 항목 실패 시 **어디서 실패했는지** 사용자에게 명확히 보고하고 중단.

### 0-1. install.sh 설치 결과물 확인
install.sh 파일 자체가 아닌, 설치로 생긴 결과물 확인:
```bash
if ! (test -d docs/agents && test -f scripts/validate.sh && test -f .githooks/pre-commit); then
  echo "STOP [0-1]: harness 설치 결과물이 없습니다."
  echo "  1단계 install.sh(또는 install.ps1)를 먼저 실행해 주세요."
  exit 1
fi
```

### 0-2. 작업 디렉토리 고정
```bash
cd "$(git rev-parse --show-toplevel)" || { echo "STOP [0-2]: git repo 아님"; exit 1; }
```

### 0-3. Git 상태 분리 판정 (install 산출물 vs 기존 변경)

Brownfield 정상 경로에서는 install.sh 직후 harness 파일들이 uncommitted
상태입니다. 이 경우 즉시 중단하지 말고 **install 산출물만 dirty인지, 아니면
기존 사용자 변경이 섞였는지** 판별:

```bash
# harness 설치 경로 (install.sh의 ESSENTIAL_PATHS와 일치)
HARNESS_RE='^(CLAUDE\.md|AGENTS\.md|REVIEW\.md|README-brownfield\.md|\.gitattributes|\.gitleaks\.toml|docs/agents/|docs/checklists/|docs/future-upgrades/|docs/decisions/README\.md|docs/org/docker-port-registry\.template\.md|templates/|scripts/|\.claude/hooks/|\.claude/settings\.json|\.githooks/|\.github/workflows/(ci|security|release|deploy|dependabot-auto-merge)\.yml|\.github/dependabot\.yml|state/learning-loop\.json|state/progress-template\.json|state/README\.md|feedback/incident-template\.yaml|feedback/incidents/README\.md|reviews/README\.md|plans/README\.md|private/README\.md)'

TOTAL_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
NON_HARNESS_DIRTY=$(git status --porcelain | awk '{ $1=""; sub(/^ /,""); print }' \
  | grep -Ev "$HARNESS_RE" | grep -c . || true)

case "$TOTAL_DIRTY:$NON_HARNESS_DIRTY" in
  0:*)
    echo "[0-3] working tree clean — 진행"
    NEED_BASE_COMMIT=false
    ;;
  *:0)
    echo "[0-3] harness 설치 산출물만 dirty — base commit 생성 후 진행"
    NEED_BASE_COMMIT=true
    ;;
  *)
    echo "STOP [0-3]: harness 무관한 기존 변경 ${NON_HARNESS_DIRTY}건 감지됨."
    echo "  다음 중 선택해 주세요:"
    echo "    (a) git stash push -m 'pre-harness' 후 진행 (끝에 pop 안내)"
    echo "    (b) 먼저 git commit 후 이 프롬프트 재실행"
    echo "    (c) 중단"
    echo "  혼재된 상태에서 진행하면 이번 harness commit에 무관한 변경이 섞입니다."
    exit 1
    ;;
esac
```

사용자가 (a) stash를 선택했으면 실행 후 진행. 완료 후 9단계 보고에
`git stash pop` 안내 추가.

### 0-4. PowerShell cmdlet 호출 금지
AI가 Claude Code의 Bash 도구를 쓰는 한 bash 환경이 보장됩니다. 프롬프트
전반에서 PowerShell 전용 명령(`Remove-Item`, `Get-Content` 등) 호출 금지.
모든 명령은 bash 문법만 사용.

### 0-5. 세션 상태 파일 생성 (`state/harness-integration/session.env`)

**중요**: Claude/Codex의 Bash tool은 각 호출이 **새 프로세스**입니다.
`TIMESTAMP=$(date ...)` 같은 shell 변수는 다음 호출에서 사라집니다. 따라서
세션 상태를 파일에 저장하고 매 단계 시작 시 source:

```bash
mkdir -p state/harness-integration

# 재실행 시 기존 session.env가 있으면 유지 (TIMESTAMP 고정 보장)
if [ -f state/harness-integration/session.env ]; then
  # shellcheck disable=SC1091
  . state/harness-integration/session.env
  echo "[0-5] 기존 session.env 로드 — TIMESTAMP=$TIMESTAMP"
else
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  cat > state/harness-integration/session.env <<EOF
# Harness brownfield integration session — 이 파일은 단계 간 상태 공유용
TIMESTAMP=$TIMESTAMP
NEED_BASE_COMMIT=${NEED_BASE_COMMIT:-false}
EOF
  echo "[0-5] session.env 신규 생성 — TIMESTAMP=$TIMESTAMP"
fi
```

### 0-6. 공용 helper 함수 정의 (`state/harness-integration/helpers.sh`)

단계 간 재사용되는 bash 함수를 파일로 저장하고 source:

```bash
cat > state/harness-integration/helpers.sh <<'EOF'
# 단계 간 공용 helper 함수

# 방어 구문: 사용 전 필수 변수 확인
require_timestamp() {
  : "${TIMESTAMP:?TIMESTAMP not set — state/harness-integration/session.env 재생성 필요}"
}

# 파일/디렉토리가 실제 존재할 때만 git add (백업 파일이 없을 때 실패 방지)
stage_if_exists() {
  local p
  for p in "$@"; do
    if [ -e "$p" ]; then
      git add -- "$p"
    fi
  done
}

# staged 변경이 없으면 commit 생략
commit_if_staged() {
  local msg="$1"
  if git diff --cached --quiet; then
    echo "  (staged 변경 없음 — commit 생략)"
    return 0
  fi
  git commit -m "$msg"
}

# 파일이 있을 때만 rm (rm -f로 통일해 없는 파일 오류 차단)
rm_if_exists() {
  local p
  for p in "$@"; do
    [ -e "$p" ] && rm -f -- "$p"
  done
}

# 백업 생성: symlink/권한/모드 보존 (cp -a)
backup_to_legacy() {
  local src="$1"
  require_timestamp
  mkdir -p docs/legacy
  cp -a -- "$src" "docs/legacy/$(basename "$src").${TIMESTAMP}.bak"
}
EOF
echo "[0-6] helpers.sh 생성"
```

이후 **모든 단계는 시작 시** 다음 3줄로 세션 상태 복원:
```bash
cd "$(git rev-parse --show-toplevel)"
. state/harness-integration/session.env
. state/harness-integration/helpers.sh
require_timestamp
```

### 0-7. docs/legacy/ 디렉토리 사전 생성
```bash
mkdir -p docs/legacy
```

### 0-8. 멱등성 체크 (재실행 시)

이전 실행의 흔적 감지:
- `git log --oneline | grep -c "chore(harness):"` ≥ 5 면 **이미 통합 완료** 상태
  (base commit + 최소 .gitignore/.gitattributes/CLAUDE/AGENTS 4~5개 이상)
- 이 경우 사용자에게 3가지 선택지 제시:
  1. **차이분만 재적용** (권장): 현재 상태와 harness 기준을 비교해 누락된
     항목만 추가. 이미 병합된 내용은 skip.
  2. **특정 단계만 재실행**: 단계 번호 지정 (예: "4-3만 재실행").
  3. **중단**.

`docs/legacy/*.bak`는 새 `${TIMESTAMP}` 접미사로 자동 구분되므로 덮어쓰지
않습니다. 같은 날 재실행 시 초 단위 timestamp가 달라야 하는데, 0-5에서
session.env가 있으면 기존 TIMESTAMP 유지이므로 **재실행은 세션이 끝난 뒤**
`rm state/harness-integration/session.env` 후 다시 0단계부터.

### 0-9. Base commit (NEED_BASE_COMMIT=true인 경우)

0-3에서 harness 산출물만 dirty라고 판정됐으면 여기서 base commit:

```bash
. state/harness-integration/session.env
if [ "${NEED_BASE_COMMIT:-false}" = "true" ]; then
  # harness 경로만 정확히 staging
  git status --porcelain | awk '{ $1=""; sub(/^ /,""); print }' \
    | grep -E "$HARNESS_RE" \
    | xargs -r -I{} git add -- "{}"
  git commit -m "chore(harness): install base files"
  # 이후 단계에서는 NEED_BASE_COMMIT 재확인 불필요
  sed -i.tmp 's/^NEED_BASE_COMMIT=.*/NEED_BASE_COMMIT=false/' state/harness-integration/session.env
  rm -f state/harness-integration/session.env.tmp
fi
```

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

분석 출력(A~E)을 보여준 뒤 **반드시 멈추고** 답변을 기다리세요. 사용자
응답 전 어떤 파일도 수정 금지.

**D 항목 감지 여부에 따라 승인 방식이 달라집니다**:

### 2-a. D 항목이 하나도 감지되지 않은 경우

아래 4개가 모두 "해당 없음"일 때만:
- husky: `.husky/` 디렉토리 없음
- 기존 GH Actions `ci.yml`: `.github/workflows/ci.yml` 없음 또는 harness와
  동일 (rename 불필요)
- 기존 비 GH Actions CI: 감지 안 됨
- Monorepo: workspaces/turbo/nx/lerna 감지 안 됨

이 경우 **"yes" 단독 답변으로 진행**.

```
위 계획으로 진행할까요? [yes / no]
```

### 2-b. D 항목이 하나라도 감지된 경우

"yes" 단독 답변은 **거부**합니다. 위험 경고를 먼저 출력하고, 각 항목에
명시 답변 또는 `use defaults`를 요구하세요:

```
⚠ 아래 D 항목은 팀 workflow·branch protection·데이터에 영향을 줍니다.
  기본값만 "yes"로 적용하면 의도치 않은 부작용이 발생할 수 있습니다.

감지된 D 항목:
  - husky: 감지됨 / 감지 안 됨
  - CI rename: ci.yml의 기존 job id '<감지된 id>' 발견 — rename 필요 여부
  - 기존 비 GH Actions CI: '<감지된 시스템>' / 없음
  - Monorepo: '<감지된 도구>' / 없음

기본값 적용 시 발생하는 부작용:
  - husky A: 기존 husky 훅 제거 + .githooks로 전환. 팀원이 pull 후
    scripts/setup/install-git-hooks.sh를 재실행해야 훅 활성화.
  - CI rename yes: 기존 job id/name이 'quality-gate'로 변경됨. 현재
    branch protection의 required status checks가 기존 이름을 참조 중이면
    **PR 영원히 대기** 발생. 마지막 7단계에서 setup-repo.sh 재실행으로
    이름 동기화 필요.
  - 기존 CI b(병행): 기존 GitLab CI 등과 harness GH Actions가 동시
    빌드 — 리소스·시간 2배.
  - monorepo root-only: 각 패키지의 validate가 루트에서 일괄 돌아가
    일부 패키지 이슈 누락 가능.

다음 중 하나로 답변해 주세요:

(1) 명시 답변 — 각 항목에 yes/no/선택 지정
    husky: A 또는 B
    CI rename: yes 또는 no
    기존 CI 처리: a / b / c
    monorepo: root-only / per-package

(2) "use defaults" — 위 부작용을 인지하고 기본값 일괄 적용 선언
    (husky A / CI rename yes / 기존 CI b / monorepo root-only)

(3) "no" — 중단
```

**파싱 규칙**:
- `"yes"` 단독 답변 → **거부하고 재질문**. "D 항목 감지됨. (1)(2)(3) 중
  선택해 주세요"로 응답.
- `"use defaults"` → 기본값 일괄 적용 + 사용자에게 "위 부작용을 이해한
  것으로 간주합니다" 고지.
- (1) 명시 답변 → 답변된 값 그대로 적용. 누락 항목은 감지 안 됐거나 기본값
  적용이 안전한 항목으로 간주 (별도 질문 없이 진행).

### 2-c. 답변 저장

사용자 답변을 session.env에 기록하여 3단계 이후에서 재사용:

```bash
cat >> state/harness-integration/session.env <<EOF
HUSKY_OPTION=<A|B|none>
CI_RENAME=<yes|no|none>
EXISTING_CI_ACTION=<a|b|c|none>
MONOREPO_SCOPE=<root-only|per-package|none>
EOF
```

## 3. 단계별 자동 병합

**모든 단계 시작 시** 아래 3줄로 세션 상태 복원:
```bash
cd "$(git rev-parse --show-toplevel)"
. state/harness-integration/session.env
. state/harness-integration/helpers.sh
require_timestamp
```

각 단계마다 `stage_if_exists` + `commit_if_staged` 패턴을 사용해
조건부 staging·commit을 수행합니다. 대상 파일이 없거나 staged 변경이
없으면 **commit은 자동 생략**됩니다.

**3-1. .gitignore 병합** (`chore(harness): merge .gitignore rules`)

기존 파일 끝에 append (중복 라인 제외). 헤더 이미 있으면 전체 skip:
```bash
if ! grep -q "── Harness Engineering rules ──" .gitignore 2>/dev/null; then
  cat >> .gitignore <<'EOF'

# ── Harness Engineering rules ──────────────────────
state/validate/
state/db-backups/
private/*
!private/README.md
docs/org/docker-port-registry.md
docs/org/*.local.md
EOF
fi

stage_if_exists .gitignore
commit_if_staged "chore(harness): merge .gitignore rules"
```

**3-2. .gitattributes 병합** (`chore(harness): merge .gitattributes`)

기존에 없는 규칙만 append:
```bash
if [ -f .gitattributes ]; then
  grep -q '^\*\.sh.*eol=lf' .gitattributes || echo '*.sh text eol=lf' >> .gitattributes
  grep -q '^\.githooks/\*' .gitattributes || echo '.githooks/* text eol=lf' >> .gitattributes
else
  cat > .gitattributes <<'EOF'
*.sh text eol=lf
.githooks/* text eol=lf
EOF
fi

stage_if_exists .gitattributes
commit_if_staged "chore(harness): merge .gitattributes"
```

**3-3. CLAUDE.md 병합 + 모순 교체** (`chore(harness): align CLAUDE.md with harness`)

3-a. 기존 CLAUDE.md가 있고 1-b에서 감지한 모순 구문이 있으면:
```bash
backup_to_legacy CLAUDE.md   # cp -a로 symlink/권한 보존 + TIMESTAMP 접미사
```
- 모순되는 섹션을 harness 기준 문구로 치환 (섹션 단위)
- 한 섹션 안에서 일부만 모순이면 그 부분만 치환, 주변 맥락 보존

3-b. `@import` 지시 **누락분만 추가** (전체 추가 아님):

기존 CLAUDE.md에 `@import` 섹션이 이미 있으면 현재 참조된 규칙 파일을
파싱하고, harness 12개 중 **누락된 것만** append:

```bash
HARNESS_IMPORTS=(
  "@AGENTS.md"
  "@REVIEW.md"
  "@docs/agents/architecture-rules.md"
  "@docs/agents/coding-rules.md"
  "@docs/agents/testing-rules.md"
  "@docs/agents/workflow-rules.md"
  "@docs/agents/security-rules.md"
  "@docs/agents/performance-rules.md"
  "@docs/agents/deploy-rules.md"
  "@docs/agents/docker-rules.md"
  "@docs/agents/migration-rules.md"
  "@docs/agents/backup-rules.md"
  "@docs/agents/feedback-rules.md"
  "@docs/agents/seo-rules.md"
)

MISSING=()
for imp in "${HARNESS_IMPORTS[@]}"; do
  if [ -f CLAUDE.md ]; then
    grep -Fq "$imp" CLAUDE.md || MISSING+=("$imp")
  else
    MISSING+=("$imp")
  fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  {
    echo ""
    echo "# ── Harness @import (누락분만 자동 추가) ──"
    printf '%s\n' "${MISSING[@]}"
  } >> CLAUDE.md
fi
```

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

```bash
# 백업 파일은 3-a에서 생성된 경우에만 존재. stage_if_exists가 처리.
stage_if_exists CLAUDE.md "docs/legacy/CLAUDE.md.${TIMESTAMP}.bak"
commit_if_staged "chore(harness): align CLAUDE.md with harness"
```

**3-4. AGENTS.md 병합 + 모순 교체** (`chore(harness): align AGENTS.md with harness`)

4-a. 기존 AGENTS.md에 1-b 모순 있으면:
```bash
backup_to_legacy AGENTS.md
```
모순 섹션 치환.

4-b. "Docker & DB 작업 의무 규칙" 섹션이 없으면 추가.
4-c. "참조 파일" 목록이 없거나 불완전하면 harness 기준 12개 규칙 파일
     중 **누락분만** 추가 (3-b의 누락분 패턴과 동일).
4-d. "Repo map" 섹션이 있으면 **기존 포맷 유지하며** 실제 디렉토리 구조로
     업데이트 (`git ls-files | head`, `ls src/`, `ls apps/` 결과 참고).

```bash
stage_if_exists AGENTS.md "docs/legacy/AGENTS.md.${TIMESTAMP}.bak"
commit_if_staged "chore(harness): align AGENTS.md with harness"
```

**3-4b. README.md 모순 교체** (`chore(harness): align README.md with harness`)

기존 README.md에 1-b 모순이 있으면:
```bash
backup_to_legacy README.md
```
모순 섹션만 치환. 프로젝트 고유 소개/설치/라이선스 등 harness와 무관한
내용은 보존.

모순 없으면 이 단계 전체 skip (백업도 만들지 않음).

```bash
stage_if_exists README.md "docs/legacy/README.md.${TIMESTAMP}.bak"
commit_if_staged "chore(harness): align README.md with harness"
```

**3-5. husky 충돌 해결** (`chore(harness): resolve husky conflict`)

`.husky/` 디렉토리 없으면 이 단계 전체 skip.

**husky 버전 감지** (v8과 v9의 제거 명령이 다름):
```bash
HUSKY_VER="unknown"
if [ -f package.json ]; then
  # prepare script로 버전 식별
  if grep -qE '"prepare"\s*:\s*"husky install"' package.json; then
    HUSKY_VER="v8"
  elif grep -qE '"prepare"\s*:\s*"husky"' package.json; then
    HUSKY_VER="v9"
  fi
fi

# 패키지 매니저 감지 (workspace 포함)
PKG_MGR="npm"
[ -f pnpm-lock.yaml ] && PKG_MGR="pnpm"
[ -f yarn.lock ] && PKG_MGR="yarn"

# workspace root 감지 (monorepo 대비)
WORKSPACE_ROOT=""
if [ -f pnpm-workspace.yaml ]; then WORKSPACE_ROOT="pnpm-workspace"; fi
if [ -f package.json ] && grep -q '"workspaces"' package.json; then WORKSPACE_ROOT="npm-yarn-workspaces"; fi
```

`D의 HUSKY_OPTION` 값에 따라 분기:

### 옵션 A (harness 통일)

```bash
# 1. .husky/ 전체를 docs/legacy/ 로 보존 (symlink/권한 포함)
backup_to_legacy .husky

# 2. 기존 husky 훅 내용을 harness 훅에 병합 (harness 내용은 유지하고 그
#    아래에 기존 내용 append — 순서 중요: 기존 커스텀 로직은 "먼저" 실행
#    되도록 상단 배치)
for hook in pre-commit commit-msg pre-push; do
  if [ -f ".husky/$hook" ] && [ -f ".githooks/$hook" ]; then
    # 1) 백업은 backup_to_legacy로 이미 완료
    # 2) 기존 내용 → 임시 파일
    tmp=$(mktemp)
    # husky shebang/husky.sh import 라인은 제외하고 실제 훅 본문만 추출
    sed -E '/^#!/d; /husky\.sh/d' ".husky/$hook" > "$tmp"

    # 3) harness 훅의 기존 내용을 새 파일에 기록
    tmp2=$(mktemp)
    {
      head -1 ".githooks/$hook"  # shebang 유지
      echo ""
      echo "# ── Legacy hook content from .husky/$hook (migrated by harness) ──"
      cat "$tmp"
      echo ""
      echo "# ── Harness default behavior ──"
      tail -n +2 ".githooks/$hook"
    } > "$tmp2"
    mv "$tmp2" ".githooks/$hook"
    chmod +x ".githooks/$hook"
    rm -f "$tmp"
  fi
done

# 3. husky 제거 (패키지 매니저·버전별 명령)
case "$PKG_MGR" in
  npm)  npm uninstall husky ;;
  pnpm) pnpm remove husky ;;
  yarn) yarn remove husky ;;
esac
# workspace라면 루트에서만 제거 (하위 package가 husky를 써도 보통 루트에만 설치됨)

# 4. package.json의 prepare script 제거 (v8/v9 공통 처리)
if command -v jq >/dev/null 2>&1 && [ -f package.json ]; then
  tmp=$(mktemp)
  jq 'if .scripts.prepare then del(.scripts.prepare) else . end' package.json > "$tmp" && mv "$tmp" package.json
fi

# 5. .husky/ 디렉토리 제거 (이미 backup_to_legacy로 docs/legacy/에 보존됨)
[ -d .husky ] && rm -rf -- .husky

# 6. .githooks/ 활성화는 이후 6단계 install-git-hooks.sh에서 수행
```

### 옵션 B (husky 유지)

(전제: `.husky/` 디렉토리 존재)

```bash
# 1. harness 훅 내용을 husky 훅에 병합
for hook in pre-commit commit-msg; do
  if [ -f ".githooks/$hook" ]; then
    if [ -f ".husky/$hook" ]; then
      # 기존 husky 훅 보존하고 harness 내용 append
      {
        echo ""
        echo "# ── Harness default behavior (appended by brownfield integration) ──"
        tail -n +2 ".githooks/$hook"  # shebang 제외
      } >> ".husky/$hook"
    else
      # 복사 (cp -a로 실행권한 보존)
      cp -a -- ".githooks/$hook" ".husky/$hook"
    fi
    chmod +x ".husky/$hook"
  fi
done

# 2. .githooks/ 제거 (core.hooksPath와 husky 중복 방지)
[ -d .githooks ] && rm -rf -- .githooks

# 3. prepare script 확인·추가
if [ -f package.json ] && ! grep -qE '"prepare"\s*:' package.json; then
  echo ""
  echo "⚠ package.json에 prepare script가 없습니다. husky 버전에 맞게 추가:"
  echo "  v8: \"prepare\": \"husky install\""
  echo "  v9: \"prepare\": \"husky\""
  echo "(감지된 버전: $HUSKY_VER)"
  echo "수동으로 추가해 주세요."
fi
```

### commit

```bash
# 옵션에 따라 변경 파일이 다르므로 경로별 stage_if_exists
stage_if_exists .husky .githooks package.json pnpm-lock.yaml yarn.lock package-lock.json
find docs/legacy -maxdepth 1 -name "*.${TIMESTAMP}.bak" -print0 2>/dev/null \
  | xargs -0 -r git add --
# 삭제된 파일도 stage (husky 제거 등) — git add는 삭제 추적 안 하므로 -A 사용
git add -A .husky .githooks 2>/dev/null || true
commit_if_staged "chore(harness): resolve husky conflict (option ${HUSKY_OPTION:-none})"
```

**3-6. CI workflow 병합** (`chore(harness): merge CI workflow`)

### 3-6-1. 기존 비 GH Actions CI 처리 (EXISTING_CI_ACTION)

```bash
. state/harness-integration/session.env

HARNESS_GH_WORKFLOWS=(
  ".github/workflows/ci.yml"
  ".github/workflows/security.yml"
  ".github/workflows/release.yml"
  ".github/workflows/deploy.yml"
  ".github/workflows/dependabot-auto-merge.yml"
)

# 기존 비 GH Actions CI 파일 목록
LEGACY_CI_FILES=()
for f in .gitlab-ci.yml Jenkinsfile .circleci/config.yml \
         bitbucket-pipelines.yml azure-pipelines.yml; do
  [ -e "$f" ] && LEGACY_CI_FILES+=("$f")
done

case "${EXISTING_CI_ACTION:-none}" in
  a)
    # 기존 비 GH Actions 유지, harness GH Actions 제거
    rm_if_exists "${HARNESS_GH_WORKFLOWS[@]}"
    # .github/dependabot.yml은 유지 (Dependabot은 GitHub 기본 기능)
    echo "ℹ 기존 CI 유지. Phase 1 해당 job(security/dependabot-auto-merge 등)은"
    echo "  기존 CI에 수동 이식 필요 — 자동 변환은 위험해 skip."
    ;;
  b)
    # 병행 — 아무것도 제거하지 않음
    echo "⚠ 기존 CI와 harness GH Actions 병행. CI 리소스·시간 2배."
    ;;
  c)
    # 마이그레이션 — 기존 CI 백업 후 제거
    for f in "${LEGACY_CI_FILES[@]}"; do
      backup_to_legacy "$f"
      rm_if_exists "$f"
    done
    ;;
  none)
    # 기존 비 GH Actions CI 감지 안 됨 — 아무 작업 없음
    :
    ;;
esac
```

### 3-6-2. 기존 GH Actions `ci.yml` 병합 + matrix rename 분석

```bash
if [ -f .github/workflows/ci.yml ]; then
  # install.sh가 덮어쓰지 않았는지 확인: harness ci.yml의 'quality-gate' job
  # 없으면 기존 ci.yml이 살아있는 상태
  if ! grep -q "quality-gate:" .github/workflows/ci.yml; then
    echo "[3-6-2] 기존 ci.yml 감지 — matrix/job 정보 수집"
    # harness ci.yml 백업 (install.sh가 설치한 버전)
    # → 이미 3-6-1 옵션 a에서 제거되지 않았다면 docs/legacy/로 보존
    # 기존 ci.yml은 따로 backup_to_legacy 하지 않음 (덮어쓰기 아닌 merge라)

    # 누락된 step 추가 (coverage/audit upload/docker-build 등):
    # 실제 diff는 AI가 수동 판단. 기존 step 순서·이름·trigger 보존.
  fi
fi
```

### 3-6-3. CI rename 영향 분석 (CI_RENAME=yes인 경우만)

rename 전에 job 구조를 **반드시 출력**하고 사용자에게 rename 방식 확인:

```bash
if [ "${CI_RENAME:-no}" = "yes" ] && [ -f .github/workflows/ci.yml ]; then
  echo "⚠ CI rename 영향 분석"
  echo ""
  echo "기존 ci.yml의 job 구조:"

  # yq가 있으면 정밀 파싱, 없으면 grep 기반 근사 분석
  if command -v yq >/dev/null 2>&1; then
    yq '.jobs | to_entries[] | {
      "job_id": .key,
      "job_name": (.value.name // .key),
      "matrix_strategy": (.value.strategy.matrix // null),
      "matrix_values": (.value.strategy.matrix | to_entries // [])
    }' .github/workflows/ci.yml
  else
    # fallback: 대략적 리스트만
    grep -E '^\s{2}[a-zA-Z0-9_-]+:$' .github/workflows/ci.yml
    echo "(yq 미설치 — 정밀 분석 불가. 아래 3옵션 중 선택 권장)"
  fi

  cat <<'ANALYSIS'

예상 required status check 이름:
  - 일반 job:  <job name>  (없으면 <job id>)
  - matrix job: <job name> (<matrix value>) — matrix 값별로 별도 check

rename 방식 3옵션:

  (1) job id만 변경 → 'quality-gate'
      required check 이름도 'quality-gate' (matrix면 'quality-gate (...)')
      기존 branch protection required checks 이름과 불일치 → PR 대기
      복구: setup-repo.sh 재실행으로 required checks 재등록

  (2) job name만 변경 → 'Quality Gate'
      job id 유지. required check는 'Quality Gate' (matrix면
      'Quality Gate (...)')
      (1)보다 완만하지만 여전히 기존 protection과 이름 차이

  (3) rename 포기 (권장)
      기존 job 이름 유지. setup-repo.sh에 기존 job 이름을
      required check contexts로 등록.

어느 옵션으로 진행할까요? (1/2/3)
ANALYSIS
  # 사용자 응답을 CI_RENAME_STYLE=1|2|3 으로 session.env에 저장
fi
```

**3옵션 선택 후 실제 변경**은 AI가 YAML 직접 편집 (yq 또는 수동). 각 옵션에 따라 `jobs.<old-id>:` → `jobs.quality-gate:` 또는 `name: ...`만 변경.

### 3-6-4. commit

```bash
# workflow 파일들과 이번 단계에서 생긴 legacy 백업만 staging
for f in .github/workflows/*.yml .github/workflows/*.yaml \
         .github/dependabot.yml; do
  stage_if_exists "$f"
done
# 이번 단계에서 생성된 legacy 백업
find docs/legacy -maxdepth 1 -name "*.${TIMESTAMP}.bak" -print0 2>/dev/null \
  | xargs -0 -r git add --
commit_if_staged "chore(harness): merge CI workflow (action=${EXISTING_CI_ACTION:-none}, rename=${CI_RENAME:-no})"
```

**3-7. Dependabot 병합** (`chore(harness): merge dependabot`)

기존 `.github/dependabot.yml` 있으면:
- updates 배열에서 `(package-ecosystem, directory)` 조합이 겹치는 것은
  **기존 설정 유지** (schedule/limit 차이 무시)
- 겹치지 않는 ecosystem만 추가
- 차이점은 commit 메시지 본문에 summary로 기록

없으면 harness 것 유지.

```bash
stage_if_exists .github/dependabot.yml
commit_if_staged "chore(harness): merge dependabot"
```

**3-8. Claude Code hooks 병합** (`chore(harness): merge .claude/settings.json`)

`.claude/settings.json` 있으면 hooks 객체의 각 배열을 병합:
- 각 이벤트(`PreToolUse`, `PostToolUse`, `SessionStart`, `Stop`)별로
- **dedup key = `matcher + if + command` 3개 조합**
- 동일 키면 skip, 다르면 배열에 추가

```bash
stage_if_exists .claude/settings.json
commit_if_staged "chore(harness): merge .claude/settings.json"
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

```bash
stage_if_exists package.json
commit_if_staged "chore(harness): add script aliases"
```

## 4. 스택별 커스터마이징 (E 섹션 실행)

이 단계는 3개의 독립 commit으로 나뉨: 4-1 스크립트 커스터마이징,
4-2 테스트 러너 `--changed` 지원 검증, 4-3 Docker compose 검증/교정.

**4-1. 스크립트 + 규칙 문서 커스터마이징** (`chore(harness): customize for <언어+매니저+러너>`)

**Monorepo 스코프 재확인 (Python multi-pyproject 주의)**:

```bash
# Python monorepo 감지: apps/*/pyproject.toml 또는 packages/*/pyproject.toml
PYTHON_MULTI_ROOT=0
for pattern in "apps/*/pyproject.toml" "packages/*/pyproject.toml" "services/*/pyproject.toml"; do
  # shellcheck disable=SC2086
  count=$(ls -1 $pattern 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 1 ]; then
    PYTHON_MULTI_ROOT=1
    break
  fi
done

if [ "$PYTHON_MULTI_ROOT" = "1" ] && [ "${MONOREPO_SCOPE:-root-only}" = "root-only" ]; then
  echo "⚠ Python multi-pyproject monorepo 감지 ($count개 pyproject.toml)."
  echo "  root-only 스코프는 각 패키지 검증을 누락시킵니다."
  echo "  per-package로 전환할까요? [yes/no]"
  # 사용자 응답에 따라 MONOREPO_SCOPE 재설정 + session.env 업데이트
fi
```

**MONOREPO_SCOPE 값에 따라 처리**:

- `per-package`:
  - `scripts/`는 루트에 유지 (공통)
  - `scripts/validate.sh` 명령을 workspace-wide로 수정:
    - pnpm workspace: `pnpm -r run lint` (`-r`로 모든 workspace 재귀 실행)
    - yarn workspace: `yarn workspaces foreach run lint`
    - turborepo: `turbo run lint test build`
    - nx: `nx run-many -t lint test build`
    - Python: 각 pyproject.toml 디렉토리 순회하며 `cd <pkg> && <명령>`
  - 각 패키지 디렉토리에 `HARNESS.md` 생성:
    ```
    이 패키지의 코딩·테스트 규칙은 repo 루트의 docs/agents/를 따릅니다.
    자세한 내용은 <상대경로>/docs/agents/ 참조.
    ```

- `root-only`:
  - 루트에서만 명령 실행. workspace 반복 없음.

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

```bash
stage_if_exists \
  scripts/validate.sh \
  scripts/validate-quick.sh \
  .claude/hooks/run-checks.sh \
  docs/agents/architecture-rules.md \
  docs/agents/coding-rules.md \
  docs/agents/testing-rules.md \
  docs/agents/deploy-rules.md
commit_if_staged "chore(harness): customize for <언어+매니저+러너>"
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

```bash
stage_if_exists scripts/validate-quick.sh   # test skip 선택한 경우만 변경됨
commit_if_staged "chore(harness): verify test runner performance"
```

**4-3. Docker compose 검증/교정** (`chore(harness): audit docker-compose files`)

### 4-3-1. compose 파일 범위 확장 감지

```bash
COMPOSE_FILES=()
for pat in "docker-compose.yml" "docker-compose.yaml" "docker-compose.*.yml" \
           "docker-compose.*.yaml" "compose.yml" "compose.yaml" \
           "compose.*.yml" "compose.*.yaml"; do
  # shellcheck disable=SC2086
  for f in $pat; do
    [ -e "$f" ] && COMPOSE_FILES+=("$f")
  done
done

if [ ${#COMPOSE_FILES[@]} -eq 0 ]; then
  echo "[4-3] compose 파일 없음 — skip"
  # 전체 4-3 단계 skip
fi
```

### 4-3-2. 환경 판정 (수정 전 필수 — 이거 없이는 어떤 수정도 금지)

`docker-compose.yml`만 있고 `.dev.yml`이 없는 프로젝트가 많고, 파일명만으론
운영/개발 판단 불가. **환경 확인 전에는 포트 주석 처리·external 볼륨
전환·container rename·name 접미사 결정 모두 금지**.

```bash
echo "감지된 compose 파일:"
for f in "${COMPOSE_FILES[@]}"; do
  # 기존 name과 x-environment 라벨이 있으면 추정값 제시
  existing_name=$(grep -m1 -E '^name:' "$f" 2>/dev/null | sed 's/^name:[[:space:]]*//' || true)
  existing_env=$(grep -m1 -E '^x-environment:' "$f" 2>/dev/null | sed 's/^x-environment:[[:space:]]*//' || true)

  hint=""
  case "$f" in
    *dev*|*develop*) hint=" (파일명 힌트: development)" ;;
    *stag*)          hint=" (파일명 힌트: staging)" ;;
    *prod*)          hint=" (파일명 힌트: production)" ;;
  esac

  echo "  - $f: name='${existing_name:-없음}' x-environment='${existing_env:-없음}'$hint"
done

cat <<'PROMPT'

각 파일의 환경 의도를 확인해 주세요 (development / staging / production):

응답 형식 예:
  docker-compose.yml: production
  docker-compose.dev.yml: development

환경 확인 전에는 어떤 수정도 수행하지 않습니다.
PROMPT

# 사용자 응답을 session.env에 저장 — COMPOSE_ENV_<파일명>=<환경>
# 파일명에 슬래시·점이 있으면 sanitize (예: docker-compose.yml → docker_compose_yml)
```

### 4-3-3. 환경 확정 후 검사 (환경 매핑이 완성된 파일에만)

검사 항목:
1. `name:` 필드 존재 여부 + 환경 접미사 (development면 `-dev`, staging이면 `-staging`, production은 접미사 없음)
2. `x-environment:` 라벨 존재 + 사용자 확인 환경과 일치
3. 컨테이너명 `<접두사>-<역할>` 패턴 준수, 금지 패턴(`-1`, `-new`, `_backend` 등) 부재
4. 볼륨 `external: true` + `name:` 명시 (DB 볼륨인 경우)
5. Backend/DB/Redis 호스트 포트 바인딩이 주석 처리됐는지 (**production만**)
6. `restart: unless-stopped` 또는 `restart: always` 명시

`development` 환경은 5번(포트 공개)을 위반으로 보지 않음 — 개발에는 포트
공개가 정상.

### 4-3-4. 위험도별 수정 분류 (환경 확정된 파일만 대상)

**🟢 안전 수정 (즉시 적용 가능)**:
- `name:` 필드 누락 → 추가 (환경에 맞춘 접미사 포함)
- `x-environment:` 라벨 누락 → 추가
- `restart:` 정책 누락 → 추가

**🟡 중간 위험 (재배포 시 container 재생성 필요)**:
- 볼륨 `external: true` + `name:` 명시 추가 — **기존 볼륨 있으면 이
  조치 전에 `docker volume create --name <기존 이름>`으로 external 볼륨
  전환 필요**. AI는 전환 명령만 사용자에게 제시, 실행은 사용자 승인 후.
- **production에서만** Backend/DB/Redis 호스트 포트 주석 처리 — 로컬
  DB 클라이언트(DBeaver 등) 접근 차단. 사용자 재확인.

**🔴 고위험 (자동 변경 절대 금지)**:
- 컨테이너명 rename. 외부 모니터링·nginx proxy·스크립트가 기존 이름을
  참조 중일 수 있음. 아래 안내만 출력:
  ```
  ⚠ 컨테이너명 '<기존>'이 금지 패턴 위반.
    자동 rename은 데이터 유실 + 외부 참조 붕괴 위험이 있어 수행하지
    않습니다. 수동 절차:
      1. docker compose stop
      2. compose 파일에서 container_name 수정
      3. 외부 참조(monitoring, nginx proxy) 업데이트
      4. docker compose up -d
      5. 데이터 검증 후 기존 container 제거
  ```

### 4-3-5. 실행

각 위반 항목마다 사용자에게 개별 수락/거부 확인. 승인된 항목만 수정.
원본은 수정 전 반드시 백업:

```bash
for f in "${COMPOSE_FILES[@]}"; do
  # 환경이 확정된 파일에 대해서만 수정 진행
  # 실제 수정은 AI가 사용자 승인 받은 항목만 yq 또는 수동 편집
  backup_to_legacy "$f"
done

stage_if_exists "${COMPOSE_FILES[@]}"
# docs/legacy/ 아래 새 백업 파일들도 스테이징
find docs/legacy -name "*.${TIMESTAMP}.bak" -print0 \
  | xargs -0 -r git add --
commit_if_staged "chore(harness): audit docker-compose files (safe-only, env-verified)"
```

## 5. 검증 (`chore(harness): verify integration`)

```bash
cd "$(git rev-parse --show-toplevel)"
. state/harness-integration/session.env
. state/harness-integration/helpers.sh

attempt=0
MAX_ATTEMPTS=3
while [ $attempt -lt $MAX_ATTEMPTS ]; do
  attempt=$((attempt + 1))
  echo "[5] validate.sh 시도 $attempt/$MAX_ATTEMPTS"
  if ./scripts/validate.sh; then
    echo "[5] 검증 통과"
    break
  fi
  if [ $attempt -ge $MAX_ATTEMPTS ]; then
    echo "STOP [5]: validate.sh가 $MAX_ATTEMPTS회 실패."
    echo "  로그 확인: state/validate/latest/*.log"
    echo "  수동 수정 후 이 단계부터 재실행 가능."
    exit 1
  fi
  # 실패 원인을 AI가 분석해 수정 (스크립트 명령 오타, alias 누락 등).
  # 변경 후 다음 루프 iteration에서 재시도.
done

stage_if_exists \
  scripts/validate.sh scripts/validate-quick.sh \
  scripts/smoke.sh \
  .claude/hooks/run-checks.sh \
  package.json
commit_if_staged "chore(harness): verify integration"
```

## 6. git hooks 활성화

D에서 husky 옵션 A 선택했으면:
```
./scripts/setup/install-git-hooks.sh
```
옵션 B(husky 유지) 선택했으면 이 단계 skip.

## 7. GitHub 보안 설정 (조건부)

`gh auth status`가 **미인증 시 non-zero**로 종료되므로 `set -e` 아래에서
그대로 호출하면 스크립트가 멈춥니다. 반드시 `if ... then ... else` 가드
사용:

```bash
cd "$(git rev-parse --show-toplevel)"
. state/harness-integration/session.env

HAS_ORIGIN=0
git remote get-url origin >/dev/null 2>&1 && HAS_ORIGIN=1

if gh auth status >/dev/null 2>&1; then
  if [ "$HAS_ORIGIN" = "1" ]; then
    # CI rename yes였다면 branch protection required checks 갱신 필수
    ./scripts/setup/setup-repo.sh
    echo "[7] setup-repo.sh 완료"
    if [ "${CI_RENAME:-no}" = "yes" ]; then
      echo "ℹ CI rename이 적용됐습니다. setup-repo.sh가 required checks를"
      echo "  'quality-gate' 등 새 이름으로 재등록했는지 GitHub UI에서 확인하세요."
    fi
  else
    echo "[7] origin 미설정 — setup-repo.sh skip"
    echo "  나중에: git remote add origin <url> 후 ./scripts/setup/setup-repo.sh"
  fi
else
  echo "[7] gh 인증 없음 — setup-repo.sh skip"
  echo "  나중에: gh auth login 후 ./scripts/setup/setup-repo.sh"
fi
```

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

### 정리 안내 (사용자 직접 실행)
- 0-3에서 git stash를 선택했으면: `git stash pop` (충돌 시 해결)
- 세션 상태 파일 제거 (재실행 시 새 TIMESTAMP 생성 위해):
  ```
  rm -rf state/harness-integration/
  ```
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
| Windows에서 install.sh 실행 안 됨 | `install.ps1` 사용. 검증 진입점(`validate.ps1`, `validate-quick.ps1`, `smoke.ps1`)은 native PowerShell이며 Git Bash가 필수 조건이 아님 |
| Codex Desktop Windows에서 git/node/validate가 Claude와 다르게 실패 | `./scripts/doctor.ps1`로 Windows env, Git, Node child-process 상태를 먼저 확인. Phase A에서는 `./scripts/phase-a/preflight.ps1`와 `./scripts/phase-a/finalize-story.ps1` 사용 |

---

## 추가 자료

- 전체 하네스 구조: [README.md](README.md)
- 규칙 상세: [docs/agents/](docs/agents/)
- 향후 확장 가이드: [docs/future-upgrades/](docs/future-upgrades/)
