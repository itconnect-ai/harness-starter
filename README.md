# Harness Engineering Starter Kit

이 키트는 **Codex Desktop(구현) + Claude Code(리뷰)** 조합으로
100% AI 개발을 수행하기 위한 harness engineering 스타터 템플릿입니다.

> **기존 프로젝트에 입히는 방법**은 [README-brownfield.md](README-brownfield.md)를 참고하세요.
> 이 README는 **신규(greenfield) 프로젝트**용이며,
> **BMAD 기획·설계·구현 계획이 이미 완료된 상태**를 전제로 합니다.

---

## 전제: BMAD 산출물 + 스킬 준비 완료

이 셋업은 BMAD 기획·설계·구현 계획이 **먼저 완료되고, BMAD 스킬도 이미
설치된 뒤** 실행됩니다. 아래 3종 산출물이 이미 손에 있어야 합니다
(경로는 상관없음):

- `PRD.md` — 제품 요구사항
- `architecture.md` — 기술 스택 + 아키텍처 설계
- `epics/` — Epic 파일들 (각 Epic에 story 목록)

**BMAD 기획을 아직 안 했다면** 이 README 범위 밖입니다. 별도 작업 공간에서
Claude Code의 BMAD 스킬(`bmad-create-prd` / `bmad-create-architecture` /
`bmad-create-epics-and-stories`)로 산출물을 먼저 만든 뒤 이 README로
돌아오세요.

Setup 1은 BMAD를 다시 설치하지 않습니다. 이미 준비된
`.agents/skills/bmad-create-story`, `.agents/skills/bmad-dev-story`,
`.claude/skills/bmad-code-review` 경로를 확인만 합니다.

---

## 사용자가 직접 할 일 (5단계)

1. BMAD 기획·설계를 진행한 프로젝트 디렉토리로 이동
   (새 디렉토리라면 BMAD 스킬 준비 후 진행)
2. BMAD 산출물 3종이 `_bmad-output/planning-artifacts/` 아래에 있는지 확인
   (PRD.md, architecture.md, epics/)
3. 그 디렉토리에서 Claude Code 실행
4. **Setup 1 → Setup 2** 프롬프트를 순서대로 붙여넣기 (셋업 완료)
5. 각 Epic마다 **Loop A(Codex) → Loop B(Claude) → Loop C(Claude)** 반복

중간 질문 (사용자 대답 필요):
- Setup 1: 스택 자동 감지 확인, 패키지 매니저, 원격 URL
- Setup 2: 원격 URL (Setup 1에서 "나중에" 택했을 때), deploy 활성화

---

### Setup 1: Bootstrap (Claude Code)

Claude Code를 열고 **아래 프롬프트 전체를 복사해서 실행**하세요.
BMAD 산출물 확인 → BMAD 스킬 경로 확인 → scaffold → git →
harness install → git hooks까지 한 번에 처리됩니다.

````markdown
# Harness Greenfield — Setup 1: Bootstrap

이 세션은 **BMAD 산출물이 `_bmad-output/planning-artifacts/` 아래에
준비되고 BMAD 스킬 경로가 이미 존재하는 프로젝트 디렉토리**에서 시작합니다. 각 단계 실패 시 STOP
조건에 따라 어디서 왜 실패했는지 명확히 출력하고 중단하세요.

## 0단계: 사전 조건 검증 (실패 시 STOP)

### 0-1. BMAD 산출물 존재 확인 (필수)

```
test -d _bmad-output/planning-artifacts \
  && test -f _bmad-output/planning-artifacts/PRD.md \
  && test -f _bmad-output/planning-artifacts/architecture.md \
  && test -d _bmad-output/planning-artifacts/epics \
  || {
    echo "STOP: BMAD 산출물 없음."
    echo "  이 README는 BMAD 기획·설계·구현 계획이 완료된 뒤 실행됩니다."
    echo "  _bmad-output/planning-artifacts/ 아래에 아래 3종을 복사 후 재실행:"
    echo "    - PRD.md"
    echo "    - architecture.md"
    echo "    - epics/ (디렉토리)"
    exit 1
  }
```

### 0-2. BMAD 스킬 경로 확인

BMAD 기획·설계를 진행한 작업 공간이므로 스킬은 이미 설치되어 있어야 합니다.
Setup 1에서는 추가 설치하지 않고 존재 여부만 검증합니다.

```
for d in .agents/skills/bmad-create-story \
         .agents/skills/bmad-dev-story \
         .claude/skills/bmad-code-review; do
  [ -d "$d" ] || {
    echo "STOP: $d 없음."
    echo "  BMAD 기획·설계를 진행한 작업 공간에서 실행하거나 BMAD 스킬 준비를 먼저 완료하세요."
    exit 1
  }
done
```

### 0-3. 디렉토리 상태 확인

허용 상태:
- `.git/` 없음 + `_bmad-output/`, `.agents/`, `.claude/` 외 비숨김 파일/디렉토리 없음 (BMAD 산출물 + BMAD 스킬만)
- 또는 `.git/` 있지만 initial commit 없음 + 같은 조건

그 외 (이미 코드 파일 존재)면 WARN:
```
if [ -n "$(ls -A | grep -vE '^(\.git|_bmad-output|\.agents|\.claude)$')" ]; then
  echo "WARN: _bmad-output/, .agents/, .claude/ 외의 파일이 이미 존재합니다."
  echo "      기존 프로젝트면 README-brownfield.md 사용 권장."
  echo "      Greenfield 계속 진행하려면 사용자 명시 승인 필요."
  # 사용자 응답 받을 때까지 다음 단계 중단
fi
```

### 0-4. 필수 도구 확인

```
for t in git curl bash; do
  command -v "$t" >/dev/null 2>&1 || { echo "STOP: $t 필요"; exit 1; }
done
```

(언어·매니저별 도구는 2단계에서 스택 감지 후 확인)

## 1단계: architecture.md 기반 스택 자동 감지

`_bmad-output/planning-artifacts/architecture.md`를 읽어 아래 정보를
추출하고 **사용자에게 확인 요청**:

- 주 언어/프레임워크 (예: "Next.js + TypeScript", "FastAPI", "Go")
- 패키지 매니저 (문서에 명시됐거나 관습상 추정되면)
- 주요 의존성 (DB, 캐시, 외부 서비스)

사용자 확인:
```
Q1 (자동 감지 결과 확인):
architecture.md 기반 감지:
  - 언어/프레임워크: <감지 결과>
  - 패키지 매니저: <감지 결과 or "모름">

이 감지가 맞나요?
  - "맞다" → 그대로 진행
  - "틀리다: <수정 내용>" → 사용자 수정 반영
```

Q1 답변 전에는 다음 단계 진행 금지.

추가 질문 (필요 시):
```
Q2. (Node.js인데 패키지 매니저 감지 실패 시) npm / pnpm / yarn 중 선택
Q3. GitHub 원격 저장소 URL? (지금 연결 or "나중에"로 Setup 2에서)
```

## 2단계: 스택별 scaffold 실행

확정된 스택에 맞는 scaffold 명령. BMAD `_bmad-output/` 디렉토리를
**건드리지 않도록** scaffold 실행 전에 백업하고 후에 복원하는 것이 안전:

```
# BMAD 산출물 임시 백업 (scaffold가 덮어쓸 경우 대비)
mkdir -p /tmp/bmad-backup-$$
cp -a _bmad-output /tmp/bmad-backup-$$/

# scaffold 실행 (스택별)
```

| 스택 | scaffold 명령 |
|---|---|
| Next.js | `npx create-next-app@latest . --ts --app --use-<매니저>` |
| Vite+React | `npm create vite@latest . -- --template react-ts` |
| FastAPI+poetry | `poetry init --no-interaction` + `app/main.py` 스켈레톤 + `poetry add fastapi uvicorn` + `poetry add --group dev pytest ruff mypy` |
| FastAPI+uv | `uv init .` + `app/main.py` 스켈레톤 + `uv add fastapi uvicorn` + `uv add --dev pytest ruff mypy` |
| Go | `go mod init <module path 질문>` + `main.go` + `go mod tidy` |
| Rust | `cargo init .` |
| Java Maven | `mvn archetype:generate -DgroupId=... -DartifactId=... -DinteractiveMode=false` |
| Java Gradle | `gradle init --type java-application --dsl kotlin --test-framework junit-jupiter --project-name <이름>` |
| 기타 | 사용자에게 scaffold 명령을 직접 받아 실행 |

scaffold 후 BMAD 백업 복원:
```
if [ ! -d _bmad-output ] || [ ! -f _bmad-output/planning-artifacts/architecture.md ]; then
  cp -a /tmp/bmad-backup-$$/_bmad-output .
fi
rm -rf /tmp/bmad-backup-$$
```

scaffold 실패 시 STOP + 실패 로그 보고. 백업은 정리.

## 3단계: git 초기화 + initial commit

```
git init -b main 2>/dev/null || { git init && git symbolic-ref HEAD refs/heads/main; }
git add -A
git commit -m "chore: initial scaffold with BMAD planning artifacts"
```

(이 커밋에 scaffold 산출물 + `_bmad-output/` 모두 포함)

## 4단계: 원격 연결 (Q3에 URL 있는 경우만)

```
if [ -n "<Q3 URL>" ] && [ "<Q3 URL>" != "나중에" ]; then
  git remote add origin "<Q3 URL>"
  git push -u origin main
fi
```

"나중에"면 skip. Setup 2에서 연결.

## 5단계: Harness 파일 설치

```
curl -fsSL https://raw.githubusercontent.com/itconnect-ai/harness-starter/main/scripts/install.sh -o /tmp/harness-install.sh
bash /tmp/harness-install.sh
rm -f /tmp/harness-install.sh
git add -A
git commit -m "chore(harness): install base files"
```

실패 시 STOP + 네트워크·저장소 URL 확인 안내.

install.sh 실행 마지막에 `CodeQL: 감지된 ... matrix [...] 적용` 라인이 출력됩니다.
프로젝트 루트의 마커 파일(`package.json`, `pyproject.toml`, `go.mod`, `pom.xml`,
`*.csproj`, `Gemfile`, `Package.swift` 등)을 보고 `.github/workflows/security.yml`
의 `language:` matrix를 자동 갱신합니다. 모노레포처럼 마커가 하위 디렉토리에 있거나
혼합 스택이라 자동 감지가 누락된 언어가 있으면 [.github/workflows/security.yml](.github/workflows/security.yml)
의 `matrix.language` 라인을 직접 수정하세요. CodeQL 지원 언어:
`actions, c-cpp, csharp, go, java-kotlin, javascript-typescript, python, ruby, swift`.

## 6단계: Git hooks 활성화

```
./scripts/setup/init-harness.sh
[ "$(git config --get core.hooksPath)" = ".githooks" ] \
  || { echo "STOP: git hooks 활성화 실패"; exit 1; }
```

setup-repo.sh 부분은 원격 없으면 자동 skip — 정상. Setup 2에서 재실행.

## 7단계: Setup 1 완료 보고

```
## Setup 1 Bootstrap 완료

- BMAD 산출물: _bmad-output/planning-artifacts/ (이식됨)
- BMAD 스킬: 기존 설치 확인 완료
- 스택: <Q1 확정 결과>
- 원격: <연결됨: <URL> / 나중에>
- 커밋: 2개 (initial scaffold / harness install)

### 다음 단계

Setup 2 프롬프트를 이 세션에 붙여넣기.
  - harness 파일을 architecture.md 기반으로 커스터마이징
  - 원격 연결 (Setup 1에서 "나중에" 택한 경우)
  - develop 브랜치 + GitHub 보안 설정
  - deploy workflow 활성화 (선택)
```

## 강제 규칙

- 0-1 (BMAD 산출물) 통과 전에는 어떤 파일도 수정 금지.
- Q1~Q3 사용자 답변 전에는 scaffold/원격 연결 실행 금지.
- 각 단계 실패 시 즉시 STOP + 어느 단계 어느 명령에서 실패했는지 출력.
- Setup 2로 자동 진행하지 말 것. 사용자가 직접 Setup 2 프롬프트를
  붙여넣어야 진행.
````

---

### Setup 2: Customization + Finalization (Claude Code)

Setup 1(Bootstrap)이 끝난 뒤 **같은 Claude Code 세션에 아래 프롬프트
전체를 붙여넣기**. harness 파일 스택별 커스터마이징 + 원격 연결 +
develop 브랜치 생성 + setup-repo + (조건부) deploy 활성화까지 한 번에
처리됩니다.

````markdown
# Harness Greenfield — Setup 2: Customization + Finalization

Setup 1(Bootstrap)이 완료된 상태에서 시작합니다. BMAD 산출물을 읽어
harness 파일을 실제 스택에 맞게 갱신하고, GitHub 원격·보안·배포 설정까지
마무리합니다.

참고 파일:
- _bmad-output/planning-artifacts/PRD.md
- _bmad-output/planning-artifacts/architecture.md

## 0단계: 사전 검증 (실패 시 중단)
1. BMAD 산출물 확인:
   test -f _bmad-output/planning-artifacts/architecture.md \
     && test -f _bmad-output/planning-artifacts/PRD.md \
     || { echo "STOP: BMAD 산출물 없음. Setup 1 재실행"; exit 1; }
2. harness 설치 결과물 확인:
   test -d docs/agents && test -f scripts/validate.sh \
     && test -f .githooks/pre-commit \
     || { echo "STOP: Setup 1 (harness install + git hooks) 먼저 완료"; exit 1; }
3. BMAD skill 사전 준비 확인:
   for d in .agents/skills/bmad-create-story \
            .agents/skills/bmad-dev-story \
            .claude/skills/bmad-code-review; do
     [ -d "$d" ] || { echo "STOP: $d 없음. BMAD 스킬이 설치된 작업 공간에서 실행하세요."; exit 1; }
   done
4. git hooks 활성 확인:
   [ "$(git config --get core.hooksPath)" = ".githooks" ] \
     || { echo "STOP: Setup 1 git hooks 활성화 먼저 완료"; exit 1; }

## 1단계: 스택 감지 + 커스터마이징 매핑 결정
architecture.md에서 기술 스택 확인. 아래 매핑 테이블로 각 스크립트·설정
파일의 명령을 결정:

| 스택 | lint | typecheck | test | build |
|---|---|---|---|---|
| Node.js (npm) | `npm run lint` | `npm run typecheck` | `npm run test` | `npm run build` |
| Node.js (pnpm) | `pnpm lint` | `pnpm typecheck` | `pnpm test` | `pnpm build` |
| Node.js (yarn) | `yarn lint` | `yarn typecheck` | `yarn test` | `yarn build` |
| Python (poetry) | `poetry run ruff check .` | `poetry run mypy .` | `poetry run pytest` | `poetry build` |
| Python (uv) | `uv run ruff check .` | `uv run mypy .` | `uv run pytest` | `python -m build` |
| Python (pip) | `ruff check .` | `mypy .` | `pytest` | `python -m build` |
| Go | `gofmt -l . && go vet ./...` | (build에 통합) | `go test ./...` | `go build ./...` |
| Rust | `cargo fmt --check && cargo clippy -- -D warnings` | (build에 통합) | `cargo test` | `cargo build --release` |
| Java (Maven) | `mvn checkstyle:check` | (build에 통합) | `mvn test` | `mvn package` |
| Java (Gradle) | `./gradlew check` | (build에 통합) | `./gradlew test` | `./gradlew build` |

npm만 `run` 필수. pnpm/yarn은 생략 가능. Go/Rust/Java는 typecheck가 build에
통합되어 별도 칸 공백.

## 2단계: harness 파일 커스터마이징
위 매핑에 따라 아래 파일을 수정:

- scripts/validate.sh, validate-quick.sh: npm 가정 명령을 실제 스택으로
  교체. **validate-quick.sh의 silent full-test fallback 제거 로직은 절대
  건드리지 말 것** (과거 해결된 story당 2~3시간 문제 재발 방지)
- scripts/smoke.sh: PRD의 핵심 사용자 플로우 기반으로 교체
- .claude/hooks/run-checks.sh: 주 언어에 맞게 case 문 확장자 조정
  (Python이면 *.py 추가, Go이면 *.go 등)
- .github/workflows/ci.yml: 스택에 맞는 run: 명령으로 교체 (Phase 1
  필수: lint / typecheck / test / build 4개 job)
- docs/agents/architecture-rules.md: architecture.md의 레이어 구조·모듈
  경계 반영
- docs/agents/coding-rules.md: 스택에 맞는 로거·규칙
- docs/agents/testing-rules.md: 실제 테스트 프레임워크·커버리지 기준
- docs/agents/security-rules.md: CORS 허용 도메인·인증 방식
- docs/agents/performance-rules.md: 사용하는 ORM/프레임워크 반영
- docs/agents/deploy-rules.md: 배포 환경 + docs/org/docker-port-registry
  작성
- CLAUDE.md "Build, Test & Quality" 섹션: 실제 명령으로 갱신
- AGENTS.md: Repo map의 소스 경로를 실제 구조에 맞게

**실패 기준**: 수정 후 scripts/validate.sh에 `npm run`이 남아있는데
실제 스택이 Node.js가 아니면 실패로 간주. 이 경우 전체 validate가 skip
또는 실패로 돌아감.

## 3단계: (해당 시) Docker 환경
Docker를 사용한다면:
- dev/docker-compose.dev.yml: 로컬 개발용 (볼륨 마운트, 디버그 포트,
  .env.development, `name: <접두사>-dev`, `x-environment: development`)
- docker-compose.yml: 운영용 (restart: always, 리소스 제한, healthcheck,
  디버그 포트 미노출, .env.production, `name: <접두사>`,
  `x-environment: production`)
- Dockerfile: multi-stage build
- .dockerignore: node_modules, .git, .env*, coverage, dist
- .env.example (커밋, 변수 목록만)
- 포트는 환경변수 (${PORT:-3000} 등)
- DB 볼륨은 named volume + external: true
- docs/agents/docker-rules.md, deploy-rules.md 전체 규칙 준수

Docker 미사용이면 이 단계 skip.

## 4단계: deploy workflow — 기본 비활성
.github/workflows/deploy.yml은 배포 서버 + secrets가 확정되기 전에는
**실행되면 안 됩니다**. install.sh가 설치한 deploy.yml에는 이미
`vars.HARNESS_DEPLOY_ENABLED == 'true'` 가드가 있으므로 GitHub에
variable을 설정하지 않으면 자동으로 skip됩니다.

이 단계에서는 아래만 확인:
- deploy.yml 파일 존재 확인
- `if: ... vars.HARNESS_DEPLOY_ENABLED == 'true'` 라인 존재 확인
- DEPLOY_HOST/DEPLOY_USER/DEPLOY_SSH_KEY/DEPLOY_APP_DIR secrets는 **8단계**
  에서 설정 (아직 하지 않음)

## 5단계: 검증
현재 OS/셸에 맞는 validate 진입점 실행:
- bash/WSL/macOS/Linux: ./scripts/validate.sh
- Windows PowerShell: ./scripts/validate.ps1

**실패 기준**:
- 모든 validate 단계가 SKIPPED로 출력되면 커스터마이징이 안 된 상태
  → Phase 2 2단계로 돌아가서 명령 교체 후 재실행
- 특정 단계 FAILED → state/validate/latest/*.log 확인 후 수정

## 6단계: 커스터마이징 커밋
git add -A
git commit -m "chore(harness): customize for <스택>"

## 7단계: 원격 연결 + develop 브랜치 + GitHub 보안 설정

사용자에게 물어보세요 (Setup 1에서 이미 원격 URL을 받았으면 skip):

```
Q4. GitHub 원격 저장소 URL? (아직 연결 안 됐으면)
    예: git@github.com:owner/repo.git
```

그다음:

```
# 1. origin 확인. Setup 1 Q3에서 이미 붙였으면 skip.
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "<Q4 URL>"
fi

# 2. main push (아직 안 했으면)
git push -u origin main

# 3. develop 브랜치 생성 + push
git checkout -b develop 2>/dev/null || git checkout develop
git push -u origin develop

# 4. main으로 돌아오기
git checkout main

# 5. gh CLI 인증 확인
if ! gh auth status >/dev/null 2>&1; then
  echo "STOP [7]: gh 인증 필요. 'gh auth login' 후 재실행"
  exit 1
fi

# 6. setup-repo.sh 실행 (Secret Scanning + Branch Protection)
./scripts/setup/setup-repo.sh
```

setup-repo.sh가 설정하는 것:
- **Secret Scanning + Push Protection** 활성화 (GHAS/GHE 필요, 없으면 skip)
- **main 브랜치 protection**: required status checks(`quality-gate`,
  `gitleaks`, `codeql`), strict, PR 리뷰 최소 1명, force push/delete 차단
- **develop 브랜치 protection**: 동일 정책

**stop 조건**:
- gh 인증 실패: `gh auth login` 후 해당 단계부터 재실행
- develop 없음 skip 로그: develop push 완료 후 setup-repo.sh 재실행

## 8단계: Deploy workflow 활성화 (조건부)

install.sh가 설치한 `.github/workflows/deploy.yml`에는
`vars.HARNESS_DEPLOY_ENABLED == 'true'` 가드가 있으므로 GitHub variable을
설정하지 않으면 deploy job이 자동 skip됩니다. **배포 인프라가 확정되기
전에는 이 단계를 건너뛰세요** (deploy.yml은 가만히 있어도 안전).

사용자에게 물어보세요:

```
Q5. 지금 deploy workflow를 활성화할까요? (yes/no/나중에)

    활성화하려면 아래 4개 secrets 값이 준비되어 있어야 합니다:
      DEPLOY_HOST     (예: 192.168.1.100)
      DEPLOY_USER     (예: deploy)
      DEPLOY_SSH_KEY  (SSH 개인키 경로, 예: ~/.ssh/deploy_key)
      DEPLOY_APP_DIR  (예: /opt/my-project)

    + GitHub에 'production' environment를 만들 권한이 있어야 합니다.
```

Q5가 "yes"면 아래 실행, 아니면 skip:

```bash
# 1. secrets 등록 (사용자가 값 제공)
gh secret set DEPLOY_HOST
gh secret set DEPLOY_USER
gh secret set DEPLOY_SSH_KEY < <SSH 키 파일 경로>
gh secret set DEPLOY_APP_DIR

# 2. production environment 생성
gh api -X PUT "/repos/{owner}/{repo}/environments/production" -F 'wait_timer=0' \
  || echo "environment 생성 실패 — 웹 UI에서 생성: Settings → Environments"

# 3. variable 설정으로 가드 해제
gh variable set HARNESS_DEPLOY_ENABLED --body "true"

# 4. 확인
gh secret list | grep DEPLOY_
gh variable list | grep HARNESS_DEPLOY_ENABLED
```

**stop 조건 (yes 선택 시)**:
- 4개 secrets 중 하나라도 값 없음 → 활성화 중단 + 준비 후 이 프롬프트
  재실행 안내
- `gh auth status` 실패 → Q5 yes 답변 전에 `gh auth login` 필요

## 9단계: Setup 2 완료 보고

아래 형식으로 사용자에게 출력:

```
## Setup 2 Customization + Finalization 완료

- 스택 커스터마이징: <요약. 예: Next.js + npm, validate.sh의 npm 명령 유지>
- 원격 연결: <연결됨: <URL> / 스킵>
- setup-repo.sh: <적용 / 스킵 사유>
- Deploy 활성화: <활성화 / 비활성(Q5 no 또는 나중에)>
- 커밋: N개

### 다음 단계

각 Epic마다 아래 3개 프롬프트를 순서대로 반복:
  Loop A: Codex Desktop에서 구현
  Loop B: Claude Code에서 리뷰 + 수정
  Loop C: Claude Code에서 회고 + Harness 강화
```

## 강제 규칙

- 사용자 Q4·Q5 답변 전에는 각 단계 실행 금지.
- 실패 시 STOP + 어느 단계에서 왜 실패했는지 출력.
- Deploy 활성화 후 첫 push가 실제 배포를 트리거하므로 secrets 누락 시
  배포 실패. 4개 모두 검증 후 variable 설정할 것.
````

---

### Loop A: 구현 (Codex Desktop — Epic마다 반복)

Codex Desktop을 열고 아래 프롬프트를 입력합니다.

> Windows/Codex 안정성: Windows PowerShell 진입점(`*.ps1`)은 native
> PowerShell 경로입니다. Git Bash/WSL은 선택 호환 계층이며 검증 필수
> 의존성이 아닙니다. Epic 시작 전에 `./scripts/doctor.ps1`와
> `./scripts/phase-a/preflight.ps1 -Epic <N>`를 실행하면 Windows env,
> Git, Node child-process 문제를 조기에 확인할 수 있습니다.
> 단, raw `node`, `npm`, `npx`, `bun` 실행 실패만으로 Phase A를 중단하지
> 마세요. 작업 가능 여부는 `./scripts/validate-quick.ps1` 또는
> `./scripts/validate.ps1` 실패로만 판단합니다.

```
Epic 1의 story를 순서대로 처리해.

## 0단계: Loop A 사전 조건 검증 (실패 시 중단)
아래 체크 후 하나라도 실패하면 "README.md의 Setup 2를 먼저 완료하세요"로
중단:

1. 현재 브랜치 확인:
   git rev-parse --abbrev-ref HEAD   # 'main' 또는 'develop' 이어야 함

2. develop 브랜치 존재:
   git rev-parse --verify develop >/dev/null 2>&1 \
     || { echo "STOP: develop 브랜치 없음. Setup 2 원격 연결 단계 완료 필요"; exit 1; }

3. origin 존재:
   git remote get-url origin >/dev/null 2>&1 \
     || { echo "STOP: origin 미설정. Setup 2 원격 연결 단계 완료 필요"; exit 1; }

4. origin/develop이 최신으로 push되어 있는지:
   git fetch origin develop 2>/dev/null
   git rev-parse origin/develop >/dev/null 2>&1 \
     || { echo "STOP: origin/develop 없음. git push -u origin develop 실행"; exit 1; }

5. BMAD skill 경로 확인:
   for d in .agents/skills/bmad-create-story \
            .agents/skills/bmad-dev-story; do
     [ -d "$d" ] || { echo "STOP: $d 없음. BMAD 스킬이 설치된 작업 공간에서 실행하세요."; exit 1; }
   done

사전 조건 통과하면 아래 실행.

각 story마다:
1. bmad-create-story 스킬(.agents/skills/bmad-create-story)로 story 파일 생성
2. bmad-dev-story 스킬(.agents/skills/bmad-dev-story)로 구현 (TDD: red-green-refactor)
   - dev-story 스킬이 자체적으로 테스트 작성 + 실행 + DoD 검증을 수행함
   - sprint-status.yaml도 스킬이 자동으로 in-progress → review로 업데이트
3. dev-story 완료 후 현재 OS/셸에 맞는 validate-quick 실행하여 하네스 검증 (lint + typecheck + 관련 테스트)
   - bash/WSL/macOS/Linux: `./scripts/validate-quick.sh`
   - Windows PowerShell: `./scripts/validate-quick.ps1`
   - 실패 시 로그 확인: state/validate/latest/*.log
4. 통과 시 story 브랜치 생성 + commit + push:
   ```
   # Windows PowerShell/Codex 권장
   ./scripts/phase-a/finalize-story.ps1 -StoryName <story-이름>

   # bash/WSL/macOS/Linux 또는 수동 경로
   git checkout -b story/<story-이름>   # 없으면 생성, 있으면 -b 생략
   git add -A
   git commit -m "feat(<story-이름>): implement story"
   git push -u origin story/<story-이름>   # 첫 push는 -u로 upstream 설정
   ```
   두 번째 이후 push는 `git push`만 해도 됨.
5. 실패 시 수정 후 재검증, 3회 실패 시 skip하고 다음으로
6. push 완료 후에만 다음 story로 진행

모든 story 완료 후:
7. 현재 OS/셸에 맞는 validate 실행 (Epic 단위 통합 검증)
   - bash/WSL/macOS/Linux: `./scripts/validate.sh`
   - Windows PowerShell: `./scripts/validate.ps1`
8. 실패 시 로그 확인 후 수정: state/validate/latest/*.log
9. 수정 후 현재 OS/셸에 맞는 validate 재개
   - bash/WSL/macOS/Linux: `./scripts/validate.sh --from=실패단계`
   - Windows PowerShell: `./scripts/validate.ps1 --from=실패단계`
10. 전체 통과 후 commit + push

규칙:
- AGENTS.md의 모든 규칙을 따를 것
- docs/agents/ 아래 규칙 참조
- **docs/agents/feedback-rules.md를 반드시 읽고 과거 실수를 반복하지 말 것**
- story별 브랜치 생성: story/<story-이름>
- 현재 OS/셸에 맞는 validate-quick 진입점 통과한 story만 commit + push
- push 없이 다음 story 진행 금지
- 이전 story의 학습을 다음 story에 반영
```

> Epic 1 구현이 끝나면 Loop B(리뷰)로 넘어갑니다.
>
> **검증 흐름**: Story 단위에서는 현재 OS/셸에 맞는 `validate-quick` 진입점으로 빠르게 검증합니다.
> bash/WSL/macOS/Linux는 `validate-quick.sh`, Windows PowerShell은 `validate-quick.ps1`를 사용합니다.
> Epic의 모든 Story 완료 후에도 같은 방식으로 `validate.sh` 또는 `validate.ps1`를 사용해 전체 통합 검증(순차 테스트 + 빌드 + 보안 + 성능)을 실행합니다.
> `smoke.sh` 또는 `smoke.ps1`(핵심 플로우 테스트)는 Loop B에서 최종 검증 시 실행됩니다.
>
> **검증 출력**: 기본 summary 모드로 단계별 성공/실패만 표시합니다.
> 실패 시 로그 경로가 출력되며, `state/validate/latest/*.log`에서 상세 로그를 확인할 수 있습니다.
> 전체 출력이 필요하면 bash/WSL/macOS/Linux는 `VALIDATE_OUTPUT_MODE=verbose`, Windows PowerShell은 `$env:VALIDATE_OUTPUT_MODE='verbose'`를 설정하세요.

> **운영체제 감지 원칙**: 프롬프트에도 "현재 OS/셸을 먼저 확인하고 그에 맞는 검증 진입점을 선택하라"를 넣을 수 있습니다.
> 다만 실제 자동화 안정성은 프롬프트보다 스크립트 진입점(`.sh`/`.ps1`)에 반영하는 쪽이 더 높습니다.
> Windows PowerShell entrypoint는 Git Bash를 내부적으로 필수 호출하지 않아야 하며,
> 이 규칙은 `.github/workflows/harness-self-test.yml`에서 검증합니다.
> Windows/Codex의 raw JS runtime sanity check는 오탐이 될 수 있습니다.
> 하네스 entrypoint가 Windows env를 복구하므로 `validate-quick.ps1` 결과를
> 기준으로 판단하세요.

### Loop B: 리뷰 + 수정 (Claude Code)

Claude Code를 열고 아래 프롬프트를 입력합니다.

```
Epic 1의 구현 결과를 리뷰하고 수정해줘.

1. sprint-status.yaml에서 review 상태인 story 확인
2. 각 story의 코드를 bmad-code-review 스킬(.claude/skills/bmad-code-review)로 리뷰
   - spec 파일로 해당 story 파일을 지정 (story의 acceptance criteria 기준 검증)
   - REVIEW.md도 함께 참조하여 아키텍처/보안/성능 기준 적용
   - (Blind Hunter + Edge Case Hunter + Acceptance Auditor 3층 병렬 리뷰)
3. REJECTED 항목은 직접 수정
4. 누락된 테스트가 있으면 보강
5. 현재 OS/셸에 맞는 validate + smoke 진입점으로 최종 검증
   - bash/WSL/macOS/Linux: `./scripts/validate.sh` + `./scripts/smoke.sh`
   - Windows PowerShell: `./scripts/validate.ps1` + `./scripts/smoke.ps1`
   - 실패 시 로그 확인: state/validate/latest/*.log
6. 모든 story APPROVED 후 **develop** 브랜치에 merge (회사 표준: develop → CI → main → 자동 배포)
7. sprint-status.yaml 업데이트 (review → done)
```

### Loop C: 회고 + Harness 강화 (Claude Code)

Loop B 완료 후, **같은 Claude Code 세션**에서 이어서 실행합니다.

첫 Epic에서는 `reviews/epic-1/`, `tests/regression/`, `state/epic-1-progress.json`
같은 파일이 아직 없을 수 있습니다. **존재하지 않으면 "missing artifact"로
기록하고 다음 항목으로 넘어가세요** — 중단하지 말 것.

```
이번 Epic의 리뷰 결과를 분석하고 harness를 강화해줘.

## 0단계: 입력 아티팩트 존재 여부 점검 (방어적 읽기)
아래 파일/디렉토리는 **있으면 읽고, 없으면 "missing artifact: <경로>"로
기록하되 중단하지 말 것**:

- reviews/epic-1/ 디렉토리 존재? 있으면 내부 *.md, logs/*.log 읽기
- state/validate/latest/*.log 존재? 있으면 읽기
- state/epic-N-progress.json 존재? (N은 현재 Epic 번호) 있으면 읽기
- tests/regression/ 디렉토리 존재? 없으면 mkdir로 생성

없는 항목은 "첫 Epic이라 아직 없음"으로 간주하고 빈 상태에서 시작.

## 실행 순서

1. 위 0단계에서 찾은 파일들을 모두 읽고 반복된 실수 패턴 탐색.
   파일이 전혀 없으면 "첫 Epic, 회고 데이터 없음"으로 기록하고 4단계로
   바로 이동.

2. 발견된 패턴마다 feedback/incidents/에 YAML 기록
   (feedback/incident-template.yaml 형식 참고)

3. 각 incident에 대해 재현 테스트를 tests/regression/에 작성
   (예: tests/regression/epic-1-missing-limit.test.ts).
   다음 Epic의 전체 validate 단계에서 자동 실행됨.

4. state/learning-loop.json 업데이트 (패턴별 발생 횟수).
   파일 없으면 state/progress-template.json 참고해서 생성.

5. 승격 정책에 따라 조치:
   - 1회: 기록만
   - 2회: docs/agents/feedback-rules.md에 활성 규칙 추가
   - 3회+ (기계적으로 판별 가능한 경우만): validate.sh에 blocking check
     (warning이 아닌 exit 1)로 추가
   - 아키텍처 성격: docs/agents/architecture-rules.md 또는 docs/decisions/
     에 ADR 작성

6. feedback-rules.md는 최대 10개 active rule 유지
   - 2 Epic 동안 재발 없으면 retired로 이동
   - validate.sh로 승격된 항목은 feedback-rules에서 제거

7. harness 파일을 수정했으면 반드시 현재 OS/셸에 맞는 검증 진입점으로
   재검증:
   - bash/WSL/macOS/Linux: bash -n scripts/validate.sh && ./scripts/validate.sh
   - Windows PowerShell: ./scripts/validate.ps1

8. 검증 통과 후 커밋: chore(harness): Epic N 회고 반영

9. 이번 Epic의 merged된 story 브랜치 정리 (origin 존재 시에만):
   - origin 없으면 이 단계 skip
   - dry-run: ./scripts/cleanup-branches.sh
   - 확인 후 실행: ./scripts/cleanup-branches.sh --apply
   - 삭제된 브랜치는 archive/<name>/<date> 태그로 영구 보존

핵심: incident를 기록만 하면 아카이브일 뿐입니다.
재현 테스트(regression test)를 함께 만들어야 다음 Epic에서 자동
재발 방지가 됩니다.
```

### 다음 Epic 또는 완료

각 Epic마다 아래 3개 프롬프트를 동일하게 반복합니다:

```
Loop A (Codex Desktop): Epic N 구현
Loop B (Claude Code): Epic N 리뷰
Loop C (Claude Code): Epic N 회고
...반복...
```

Setup 1/2는 **프로젝트 시작 시 한 번만** 실행하면 됩니다.

---

## 가벼운 작업 (Quick Flow)

BMAD 풀코스 없이 간단한 수정/기능 추가를 할 때도 Phase A/B 패턴을 따릅니다.

### Quick Flow Phase A: Codex Desktop에서 구현

```
아래 작업을 bmad-quick-dev 스킬(.agents/skills/bmad-quick-dev)로 처리해.

작업 내용: [여기에 작업 설명]

규칙:
- AGENTS.md의 규칙을 따를 것
- docs/agents/ 아래 모든 규칙 참조 (security, performance, deploy 포함)
- story 브랜치 생성: feature/<작업-이름>
- 구현 완료 후 현재 OS/셸에 맞는 validate-quick 진입점 실행하여 빠른 검증
  - bash/WSL/macOS/Linux: `./scripts/validate-quick.sh`
  - Windows PowerShell: `./scripts/validate-quick.ps1`
- 검증 통과 후 commit + push
```

또는 Barry(빠른 구현 전문가)를 호출:

```
bmad-agent-quick-flow-solo-dev(.agents/skills/bmad-agent-quick-flow-solo-dev)에게 아래 작업을 시켜줘.

작업 내용: [여기에 작업 설명]

규칙:
- AGENTS.md 규칙 준수
- docs/agents/ 규칙 참조
- 구현 완료 후 현재 OS/셸에 맞는 validate-quick 진입점 통과 후 commit + push
```

### Quick Flow Phase B: Claude Code에서 검증

```
feature/ 브랜치의 변경 사항을 리뷰하고 수정해줘.

1. git diff main 확인
2. bmad-code-review 스킬(.claude/skills/bmad-code-review)로 리뷰
   - REVIEW.md를 참조하여 판정 기준 적용
3. REJECTED 항목 직접 수정
4. 현재 OS/셸에 맞는 validate 진입점 실행하여 최종 검증
   - bash/WSL/macOS/Linux: `./scripts/validate.sh`
   - Windows PowerShell: `./scripts/validate.ps1`
   - 실패 시 로그 확인: state/validate/latest/*.log
5. APPROVED 후 develop에 merge (CI 통과하면 develop → main 승격 PR)
```

> Quick Flow도 현재 OS/셸에 맞는 전체 validate 진입점 검증 + bmad-code-review 리뷰는 동일하게 적용됩니다.
> smoke는 핵심 플로우를 건드린 경우에만 현재 OS/셸에 맞는 진입점으로 실행합니다.


---

## Docker / DB 작업 지시 표준

AI에게 Docker 또는 DB 마이그레이션 작업을 시키실 때는 **환경을 한국어로 명시**하세요. "dev", "prod" 같은 영어 약어는 사용자-AI 사이 혼동을 유발합니다.

### 표준 지시 문구

```
<프로젝트명> 개발 환경으로 docker 구성해
<프로젝트명> 운영 환경으로 docker 구성해
<프로젝트명> 개발 환경에서 마이그레이션 돌려
<프로젝트명> 운영 환경에 배포용 compose 만들어
```

이 문구를 받으면 AI는 자동으로 다음을 수행:

1. `./scripts/docker-guard.sh --env development|production`로 현재 compose 상태 검증
2. compose 파일의 `name:` (운영=`<접두사>` vs 개발=`<접두사>-dev`)과 `x-environment:` (`production` vs `development`) 라벨이 지시와 일치하는지 교차 확인
3. 불일치 또는 중복 컨테이너 감지 시 중단 후 보고
4. 마이그레이션이면 `./scripts/db-migrate.sh --cmd "..." --env <환경>` 래퍼로 실행

### 내부 값은 영어 유지

지시 문구는 한국어이지만 **파일 값·CLI 인자는 영어**를 유지합니다 (범용성·도구 호환성):

- `x-environment: production` / `x-environment: development`
- `--env production` / `--env development`
- 사용자가 `"개발 환경으로 구성해"` 라고 지시 → AI는 내부적으로 `--env development`로 변환

### 상세 규칙

- Docker 일반: `docs/agents/docker-rules.md`
- 환경 분리·compose name 규칙: `docs/agents/deploy-rules.md`
- DB 마이그레이션 안전: `docs/agents/migration-rules.md`

---

## 파일 구조

```
├── CLAUDE.md                          Claude Code 지침 (Phase B: 리뷰+수정)
├── AGENTS.md                          저장소 공식 규칙 (Phase A+B 공용)
├── REVIEW.md                          코드 리뷰 기준
├── .gitignore                         추적 제외 파일
│
├── .agents/skills/                    Codex용 BMAD 스킬 (Phase A)
│   ├── bmad-create-story/             story 생성 (풀 컨텍스트 엔진)
│   ├── bmad-dev-story/                story 구현 (TDD)
│   ├── db-backup-setup/               DB 백업 시스템 설정 스킬
│   └── ...
│
├── .claude/
│   ├── settings.json                  Hook 설정
│   ├── hooks/
│   │   ├── block-rm.sh                위험 명령 차단
│   │   ├── check-feedback-rules.sh    세션 시작 시 활성 피드백 규칙 표시
│   │   ├── docker-guard-hook.sh       docker/마이그레이션 명령 실행 전 안전 차단
│   │   ├── run-checks.sh              편집 파일만 eslint (빠른 피드백)
│   │   └── warn-uncommitted.sh        세션 종료 시 uncommitted changes 경고
│   └── skills/                        Claude Code용 BMAD 스킬 (Phase B)
│       ├── bmad-code-review/          3층 병렬 코드 리뷰
│       └── ...
│
├── .githooks/                         Git hook (husky 없이 core.hooksPath 방식)
│   ├── pre-commit                     staged 파일 eslint + .env 차단 + 대형 커밋 경고
│   └── commit-msg                     Conventional Commits 형식 검증
│
├── docs/
│   ├── agents/
│   │   ├── architecture-rules.md      아키텍처 경계, API 버저닝, health check
│   │   ├── backup-rules.md            DB 백업 시스템 설계 규칙 (4계층)
│   │   ├── coding-rules.md            코드 작성, 로깅 표준, 환경변수
│   │   ├── testing-rules.md           테스트 규칙, 격리, 4층 검증 체계
│   │   ├── security-rules.md          보안 (시크릿, 인증, 입력검증, 에러노출)
│   │   ├── performance-rules.md       성능 (N+1, LIMIT, 이벤트 cleanup)
│   │   ├── deploy-rules.md            배포 (환경 분리, compose name 환경 접미사, graceful shutdown)
│   │   ├── docker-rules.md            Docker 네이밍/포트/검증 일반 원칙
│   │   ├── migration-rules.md         DB 마이그레이션 데이터 유실 방지
│   │   ├── workflow-rules.md          Phase A/B/C 작업 흐름
│   │   ├── feedback-rules.md          과거 실수 패턴 활성 교훈
│   │   └── seo-rules.md              SEO/AEO/GEO 구현 규칙
│   ├── changelog/                     하네스 개선 이력 (비개발자 요약 포함)
│   ├── future-upgrades/               미도입 기능 도입 가이드 (OIDC/OTel/ZAP/Scorecard)
│   ├── checklists/
│   │   ├── page-update.md             페이지 수정 후 SEO/AEO/GEO 체크리스트
│   │   └── pre-deploy.md              배포 전 체크리스트
│   ├── decisions/                     ADR
│   └── org/
│       └── docker-port-registry.template.md  조직 포트 레지스트리 template (복사 후 private/에 실제 값)
│
├── private/                           외부 공개 금지 내부 정보 (.gitignore로 보호, README.md만 커밋)
│
├── templates/
│   ├── execplan.md                    ExecPlan 템플릿
│   └── adr.md                         ADR 템플릿
│
├── scripts/
│   ├── install.sh                     다른 프로젝트로 필수 파일만 install (tarball 기반)
│   ├── install.ps1                    Windows PowerShell용 설치 진입점
│   ├── lib/
│   │   ├── validate-utils.sh          검증 공용 헬퍼 (래퍼, 로그, summary/verbose)
│   │   ├── validate-utils.ps1         PowerShell native 검증 공용 헬퍼
│   │   ├── package-runner.ps1         npm/pnpm/yarn/bun 감지 + script 실행 헬퍼
│   │   ├── git-utils.ps1              Codex/Windows-safe git wrapper
│   │   └── powershell-utils.ps1       legacy Bash 호환 호출 헬퍼
│   ├── setup/
│   │   ├── init-harness.sh            하네스 자동 초기화 통합 (4단계 프롬프트에서 호출)
│   │   ├── init-harness.ps1           Windows 버전
│   │   ├── install-git-hooks.sh       .githooks/ 활성화 (init-harness가 호출)
│   │   ├── install-git-hooks.ps1      Windows 버전
│   │   ├── setup-repo.sh              GitHub repo 보안 설정 (init-harness가 호출, gh CLI 필요)
│   │   └── setup-repo.ps1             Windows 버전
│   ├── run-epic.sh                    CLI fallback (Codex Desktop 없을 때)
│   ├── validate-quick.sh              bash/WSL/macOS/Linux Story 빠른 검증
│   ├── validate-quick.ps1             Windows PowerShell Story 빠른 검증
│   ├── validate.sh                    bash/WSL/macOS/Linux Epic 전체 검증
│   ├── validate.ps1                   Windows PowerShell Epic 전체 검증
│   ├── doctor.ps1                     Windows/Codex 런타임 진단
│   ├── phase-a/                       Codex Phase A preflight/finalize wrapper
│   ├── smoke.sh                       bash/WSL/macOS/Linux 스모크 테스트
│   ├── smoke.ps1                      Windows PowerShell 스모크 테스트
│   ├── cleanup-branches.sh            로컬+원격 merged 브랜치 정리 (archive tag로 복구 보존, Phase C에서 호출)
│   ├── docker-guard.sh/.ps1           Docker 작업 전후 안전 검증 (환경 라벨 + 중복 컨테이너 감지)
│   ├── db-migrate.sh/.ps1             DB 마이그레이션 안전 래퍼 (자동 pg_dump + 실패 시 복원 안내)
│   └── status.sh                      진행 상태 대시보드
│
├── _bmad-output/
│   ├── planning-artifacts/            PRD, architecture, epics
│   └── implementation-artifacts/      sprint-status, story 파일
│
├── feedback/
│   ├── incidents/                     Phase C에서 생성되는 실수 기록 (YAML)
│   └── incident-template.yaml         incident 구조 템플릿
│
├── state/                             작업 진행 상태 + learning-loop.json
│   └── validate/                      검증 로그 아카이브
│       └── latest/                    최신 실행 로그 (단계별 *.log)
├── plans/                             ExecPlan (복잡한 작업)
└── reviews/                           리뷰 결과 + 로그
```

---

## 운영 요약

| 단계 | 도구 | BMAD 스킬 | 산출물 |
|---|---|---|---|
| 기획/설계 | Claude Code | create-prd, create-architecture, create-epics | PRD, Architecture, Epics |
| 프로젝트 초기화 | Claude Code | — | scaffolding, 린팅/테스트 설정 |
| **Phase A: 구현** | **Codex Desktop** | **create-story, dev-story** | **코드 + 커밋 + story 파일** |
| **Phase B: 품질 보장** | **Claude Code** | **code-review** | **리뷰 결과 + 수정 + 테스트** |
| **Phase C: 회고** | **Claude Code** | **bmad-retrospective (선택)** | **incidents + feedback-rules 갱신 + harness 강화** |

## 검증 철학: Strict Execution, Concise Summary, Full Artifacts

이 하네스의 검증 스크립트는 세 가지 원칙을 따릅니다:

- 판정은 엄격하게 — 검증 단계, 테스트 범위, 실패 기준은 약화하지 않음
- 기본 출력은 짧게 — AI 에이전트가 소비하는 토큰을 최소화하되, 실패 원인 파악에 필요한 신호는 유지
- 원본 증거는 항상 보존 — 모든 실행의 전체 로그를 `state/validate/latest/*.log`에 단계별로 저장

| 환경변수 | 값 | 설명 |
|---|---|---|
| `VALIDATE_OUTPUT_MODE` | `summary` (기본) | 단계별 성공/실패 + 소요시간만 출력. 실패 시 로그 경로 + 핵심 출력 포함 |
| `VALIDATE_OUTPUT_MODE` | `verbose` | 전체 로그를 콘솔에 실시간 출력 (기존 방식) |

실패 시 디버깅 흐름:
1. summary 출력에서 실패 단계와 로그 경로 확인
2. 해당 로그 파일을 읽어서 원인 파악 (예: `state/validate/latest/04a-test.log`)
3. 수정 후 현재 OS/셸에 맞는 validate 진입점으로 `--from=실패단계` 재개
   - bash/WSL/macOS/Linux: `./scripts/validate.sh --from=실패단계`
   - Windows PowerShell: `./scripts/validate.ps1 --from=실패단계`

## Harness 작동 매트릭스

모든 harness가 언제, 어떻게 작동하는지 한눈에 확인할 수 있습니다.

### 자동 작동 (사람 개입 불필요)

| Harness | 트리거 | 대상 | 설명 |
|---|---|---|---|
| `block-rm.sh` | Claude Code에서 Bash 명령 실행 시 | Phase B | `rm -rf` 등 위험 명령 자동 차단 |
| `run-checks.sh` | Claude Code에서 Edit/Write 시 | Phase B | 편집 파일만 eslint (빠르게), 실패 시만 노출 |
| `warn-uncommitted.sh` | Claude Code 세션 종료 시 | Phase B | uncommitted changes 있으면 경고 (차단 아님) |
| `.githooks/pre-commit` | git commit 시 | 공통 (install-git-hooks.sh 필요) | staged 파일 eslint + .env 차단 + 대형 커밋 경고 |
| `.githooks/commit-msg` | git commit 시 | 공통 (install-git-hooks.sh 필요) | Conventional Commits 형식 검증 |
| CLAUDE.md @import | Claude Code 세션 시작 시 | Phase B | 모든 규칙 파일 + REVIEW.md 자동 로드 |
| AGENTS.md | Codex Desktop 세션 시작 시 | Phase A | 저장소 규칙 자동 로드 |
| bmad-dev-story TDD | Phase A에서 story 구현 시 | Phase A | red-green-refactor 사이클 강제 |
| bmad-dev-story DoD | Phase A에서 story 완료 시 | Phase A | 10개 항목 정의 완료 검증 자동 실행 |
| sprint-status.yaml | bmad 스킬 실행 시 | Phase A | backlog→in-progress→review 자동 업데이트 |

### 프롬프트로 호출 (명시적 지시 필요)

| Harness | 호출 방법 | 대상 | 설명 |
|---|---|---|---|
| `validate-quick` | bash/WSL/macOS/Linux는 `./scripts/validate-quick.sh`, Windows PowerShell은 `./scripts/validate-quick.ps1` | Phase A (Story) | 빠른 검증 (lint + typecheck + 관련 테스트) |
| `validate` | bash/WSL/macOS/Linux는 `./scripts/validate.sh`, Windows PowerShell은 `./scripts/validate.ps1` | Phase A (Epic) / Phase B | 전체 검증 (8단계, --from 재개 지원) |
| `smoke` | bash/WSL/macOS/Linux는 `./scripts/smoke.sh`, Windows PowerShell은 `./scripts/smoke.ps1` | Phase B | 핵심 사용자 플로우 스모크 테스트 |
| `bmad-create-story` | Phase A 프롬프트에 포함 | Phase A | story 파일 생성 (풀 컨텍스트 엔진) |
| `bmad-code-review` | Phase B 프롬프트에 포함 | Phase B | 3층 병렬 리뷰 (Blind + Edge Case + Acceptance) |
| `bmad-quick-dev` | `bmad-quick-dev` 직접 호출 | Quick Flow | 가벼운 작업용 |

### 자동 (CI/CD — PR/push 시)

| Harness | 트리거 | 설명 |
|---|---|---|
| `.github/workflows/ci.yml` | main/develop에 PR 생성 또는 push 시 | lint → typecheck → test → build → coverage → audit → docker build 검증 |
| `.github/workflows/security.yml` | main/develop push/PR + 주간 월요일 09:00 KST | Gitleaks(시크릿) + CodeQL(SAST) + Trivy(의존성/Docker 이미지 CVE) |
| `.github/workflows/release.yml` | `v*.*.*` 태그 push 시 | CI 재검증 → GitHub Release 자동 생성 (changelog 포함) |
| `.github/workflows/deploy.yml` | main push + CI 성공 직후 | SSH로 사내 Docker 서버 접속 → git pull + docker compose up (+ 옵션 pre-backup/post-smoke) |
| `.github/workflows/dependabot-auto-merge.yml` | Dependabot이 PR 오픈 시 | patch/minor만 자동 approve + merge. major는 수동 대기 |
| `.github/dependabot.yml` | 매주 월요일 09:00 KST | npm/github-actions/docker 3개 ecosystem 주간 업데이트 PR 자동 생성 |

### 규칙 파일 (에이전트가 자동 참조)

| 규칙 파일 | Phase A | Phase B | 검증 시점 |
|---|---|---|---|
| `architecture-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh |
| `coding-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + lint |
| `testing-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 |
| `security-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh 보안 체크 |
| `performance-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh 성능 체크 |
| `deploy-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + validate.sh Docker 체크 |
| `feedback-rules.md` | AGENTS.md에 명시적 읽기 지시 | @import 자동 로드 | Phase A 시작 시 + Phase C에서 재작성 |
| `workflow-rules.md` | docs/agents/로 참조 | @import 자동 로드 | — |
| `REVIEW.md` | — | @import 자동 로드 | Phase B 리뷰 시 APPROVED/REJECTED 판정 기준 |
| `backup-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + 배포 전 체크리스트 |
| `seo-rules.md` | docs/agents/로 참조 | @import 자동 로드 | 리뷰 시 + 페이지 수정 후 체크리스트 |

---

## 다른 AI 도구 사용 시 (Kiro, Antigravity 등)

이 Harness의 핵심 자산은 **도구 독립적**입니다:
- `docs/agents/*.md` (규칙 10개) — 어떤 AI 도구든 동일하게 적용
- bash/WSL/macOS/Linux는 `scripts/*.sh`, Windows PowerShell은 `scripts/*.ps1` 진입점 사용
- `REVIEW.md` — 리뷰 기준은 도구와 무관

BMAD 스킬이 없는 도구를 사용할 때는 아래 프롬프트에 규칙 파일을 직접 참조시키세요.

### 구현 프롬프트 (Phase A 대체)

```
아래 작업을 구현해줘.

작업 내용: [설명]

반드시 아래 규칙 파일을 읽고 따를 것:
- docs/agents/architecture-rules.md (레이어 경계, API 규칙, health check)
- docs/agents/coding-rules.md (파일 구조, 로깅, 에러 처리)
- docs/agents/security-rules.md (시크릿, 인증, 입력 검증)
- docs/agents/performance-rules.md (N+1, LIMIT, 이벤트 cleanup)
- docs/agents/deploy-rules.md (Docker, 포트, DB 보호)
- docs/agents/testing-rules.md (테스트 대상, 작성 원칙)
- docs/agents/backup-rules.md (DB 백업 — 해당 시)
- docs/agents/seo-rules.md (SEO/AEO/GEO — 웹 프로젝트 시)

완료 전 반드시:
- 현재 OS/셸에 맞는 validate-quick 진입점 실행하여 빠른 검증 통과
- 검증 통과 후 commit + push: git add -A && git commit -m "feat(<scope>): <설명>" && git push
```

### 리뷰 프롬프트 (Phase B 대체)

```
현재 브랜치의 변경 사항을 리뷰하고 수정해줘.

리뷰 기준: REVIEW.md 파일을 읽고 그대로 따를 것.
추가 참조: docs/agents/ 아래 모든 규칙 파일.

REJECTED 항목은 직접 수정하고,
현재 OS/셸에 맞는 validate + smoke 진입점으로 최종 검증 후
develop에 merge (CI 통과 후 main 승격).
```

> 이 프롬프트들은 BMAD 스킬 없이도 **규칙 파일 + 검증 스크립트**만으로
> Harness의 핵심 가치(문맥, 테스트 계약, 리뷰 루프)를 유지합니다.

---

## 운영 체크리스트

자동화할 수 없는 항목(콘텐츠-메타데이터 일관성, 배포 전 수동 확인 등)은 체크리스트로 관리합니다.
각 체크리스트에는 LLM에게 전달할 프롬프트도 포함되어 있습니다.

| 시점 | 체크리스트 | 설명 |
|---|---|---|
| 페이지 수정 후 | [docs/checklists/page-update.md](docs/checklists/page-update.md) | SEO 메타데이터, JSON-LD, GEO 인용 문장, OG 이미지 일관성 |
| 배포 전 | [docs/checklists/pre-deploy.md](docs/checklists/pre-deploy.md) | DB 백업, 환경변수, 마이그레이션, 인프라 확인 |

---
