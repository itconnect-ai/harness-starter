# 기존 프로젝트에 Harness 입히기 (Brownfield)

**2단계로 끝납니다**: install.sh 실행 → Claude Code에 아래 프롬프트 붙여넣기. AI가 기존 프로젝트를 분석하고 충돌 지점을 자동 병합합니다. 수동 편집 거의 없음.

신규 프로젝트 셋업은 [README.md](README.md)를 참고하세요.

---

## 1단계: 필수 파일 설치

기존 프로젝트 루트에서:

```bash
curl -fsSL https://raw.githubusercontent.com/itconnect-ai/harness-test/main/scripts/install.sh | bash
```

기본 모드는 **기존 파일 skip** — 충돌 없이 안전. 이 시점에는 harness 파일이 단순 추가만 된 상태이고, 기존 워크플로는 영향을 받지 않습니다.

---

## 2단계: Claude Code에 통합 프롬프트 붙여넣기

Claude Code를 열고 **아래 프롬프트 전체를 복사해서 실행**하세요.

````markdown
# Harness Brownfield 통합

이 프로젝트는 기존 코드베이스입니다. 방금 `scripts/install.sh`로 harness
필수 파일들이 추가됐습니다. 이제 기존 프로젝트 구성과 **충돌 없이 통합**
해 주세요. 절대 기존 내용을 덮어쓰지 말고, 항상 읽은 뒤 병합하세요.

## 작업 순서

### 1. 현황 분석 (읽기만, 수정 금지)

#### 1-a. 프로젝트 구성 파악

다음을 병렬로 읽고 요약하세요:
- `ls -la` 루트
- `package.json`의 scripts 섹션 + 주요 dependencies
- `.github/workflows/` 안의 모든 yml
- 기존 `.gitignore`, `.gitattributes`
- 기존 `CLAUDE.md`, `AGENTS.md`, `README.md` (있으면)
- `.husky/` 디렉토리 존재 여부
- 기존 `docker-compose*.yml`, `Dockerfile`
- 주 언어 감지 (package.json 또는 파일 확장자 비율)
- 테스트 러너 감지 (vitest/jest/mocha/pytest 등)
- 패키지 매니저 감지 (package-lock/yarn.lock/pnpm-lock)

#### 1-b. Harness 규칙과 모순되는 기존 내용 감지

기존 `CLAUDE.md`, `AGENTS.md`, `README.md` 내용을 읽고 harness 규칙과
**모순되는 문구**를 찾으세요. 아래는 대표 체크리스트 (감지되면 교체 대상):

| 모순 패턴 | Harness 기준 |
|---|---|
| "main에 직접 push" / "main에 바로 merge" | develop → main 흐름 |
| "console.log 사용 가능" / 로거 미정의 | 구조화 로거(winston/pino) 강제 |
| "docker compose down -v 사용" | 절대 금지 |
| "prisma migrate deploy 직접 호출" | `./scripts/db-migrate.sh` 래퍼 필수 |
| husky 기반 pre-commit 설명 | `.githooks/` 또는 선택된 옵션에 맞게 통일 |
| "validate 없이 commit 가능" | validate-quick 통과 후 commit 필수 |
| "feature/ 브랜치 사용" (develop 없이 main 직결) | story/* → develop → main |
| "SSH 키를 저장소에 커밋" 등 보안 금지 사항 | security-rules와 정면 충돌 — 교체 |

추가로 AI 판단: 읽은 문서 중 harness의 `docs/agents/*-rules.md`와 내용이
**상반되는 모든 구문**을 목록화.

#### 1-c. 통합 계획 출력

분석 결과를 아래 형식으로 출력하세요:

```
## 통합 계획

### A. 신규 설치 (충돌 없음, 그대로 유지)
- [파일 목록]

### B. 병합 — 누락 섹션 append (기존 내용 보존)
- .gitignore: [어떤 라인 추가할지]
- .gitattributes: [추가할 규칙]
- .github/workflows/ci.yml: [누락 step 추가]
- .claude/settings.json: [hooks 병합]
- (기타)

### C. 모순 교체 — 기존 내용이 harness와 충돌 (원본은 docs/legacy/에 백업)
- CLAUDE.md:
  - [섹션 이름]: "[기존 문구 요약]" → "[harness 기준]"
  - [섹션 이름]: ...
- AGENTS.md:
  - [섹션 이름]: "[기존 문구 요약]" → "[harness 기준]"
- README.md:
  - [섹션 이름]: ...
- (기타)

### D. 사용자 선택 필요 (자동 결정 불가)
- husky 감지됨: 옵션 A(harness 통일) vs B(husky 유지) — 어느 쪽?
- CI job 이름: 기존 'build' → 'quality-gate'로 rename? (branch
  protection 호환)

### E. 스택별 커스터마이징 (감지 결과 기반 자동 수정)
- scripts/validate.sh: `npm run lint` → `[감지된 명령]`
- .claude/hooks/run-checks.sh: 확장자 [.ts/.tsx → 실제]
- docs/agents/coding-rules.md: 로거 [winston/pino/console 감지 결과]
- docs/agents/testing-rules.md: 러너 [감지 결과]
- (기타)
```

### 2. 사용자 승인 (일괄 게이트 — 단 1회)

**중요**: 분석 출력(섹션 A~E)을 보여준 뒤 반드시 멈추고, 다음과 같이
**한 번에 묻고** 대답을 기다리세요:

```
위 계획 전체로 진행할까요?
  - yes: 계획대로 실행 (C의 모순 교체 + E의 커스터마이징 모두 자동 적용)
  - no:  중단
  - 항목 제외: "C의 CLAUDE.md 3번째 항목은 제외" 같은 형식으로 지정
  - D의 사용자 선택은 아래 답변에 포함해주세요:
      husky: A 또는 B
      CI rename: yes 또는 no
```

기본 원칙:
- **C(모순 교체)는 기본 실행**. 원본은 `docs/legacy/<원본-파일명>.<timestamp>.bak`
  으로 백업되므로 복구 가능.
- **D(사용자 선택)만 대답 필수** — husky/CI rename 2개.
- 사용자가 "yes"만 답하면 → D는 기본값 사용: `husky: A`, `CI rename: yes`.

사용자 응답을 받기 전에는 어떤 파일도 수정하지 마세요.

### 3. 단계별 자동 병합 (각각 독립 commit)

각 단계 끝에 commit을 만들어 특정 단계만 rollback 가능하도록.

**3-1. .gitignore 병합** (`chore(harness): merge .gitignore rules`)
기존 파일 끝에 아래 헤더로 구분하여 append (중복 라인 제외):
```
# ── Harness Engineering rules ──────────────────────
state/validate/
state/db-backups/
private/*
!private/README.md
docs/org/docker-port-registry.md
docs/org/*.local.md
```

**3-2. .gitattributes 병합** (`chore(harness): merge .gitattributes`)
이미 `*.sh eol=lf` 없으면 추가. `.githooks/* eol=lf` 추가.

**3-3. CLAUDE.md 병합 + 모순 교체** (`chore(harness): align CLAUDE.md with harness`)

`docs/legacy/` 디렉토리가 없으면 먼저 생성.

3-a. 기존 CLAUDE.md가 있고 **1-b에서 감지한 모순 구문**이 있으면:
  - 원본을 `docs/legacy/CLAUDE.md.<YYYYMMDD_HHMMSS>.bak`으로 복사 (백업)
  - 모순되는 섹션을 **harness 기준 문구로 치환** (통합 계획 C 항목 그대로)
  - 섹션 단위로 교체 (heading 기준). 한 섹션 안에서 일부만 모순이면 그
    부분만 치환하되 주변 맥락 보존.

3-b. `@import` 지시 섹션이 없으면 파일 끝에 추가:
```
@AGENTS.md
@REVIEW.md
@docs/agents/architecture-rules.md
@docs/agents/coding-rules.md
@docs/agents/testing-rules.md
@docs/agents/workflow-rules.md
@docs/agents/security-rules.md
@docs/agents/performance-rules.md
@docs/agents/deploy-rules.md
@docs/agents/docker-rules.md
@docs/agents/migration-rules.md
@docs/agents/backup-rules.md
@docs/agents/feedback-rules.md
@docs/agents/seo-rules.md
```

3-c. "Build, Test & Quality" 섹션을 **package.json의 실제 scripts로 생성**
(기존 섹션이 있으면 실제 명령으로 업데이트). 예:
- `npm run lint`가 scripts에 있으면 그대로 사용
- 없고 eslint dependency만 있으면 `npx eslint .`
- pnpm이면 `pnpm lint`로 자동 교체

기존 CLAUDE.md가 없으면 harness의 CLAUDE.md가 이미 설치된 상태이므로
3-c만 수행.

**3-4. AGENTS.md 병합 + 모순 교체** (`chore(harness): align AGENTS.md with harness`)

4-a. 기존 AGENTS.md에 **1-b 모순**이 있으면:
  - 원본 `docs/legacy/AGENTS.md.<timestamp>.bak` 백업
  - 모순 섹션 harness 기준으로 치환

4-b. "Docker & DB 작업 의무 규칙" 섹션이 없으면 추가.
4-c. "참조 파일" 목록이 없거나 불완전하면 harness 기준 12개 규칙 파일로
     교체/추가.
4-d. "Repo map" 섹션이 있으면 실제 디렉토리 구조(`ls src/`, `ls apps/`
     등)로 업데이트.

**3-4b. README.md 모순 교체** (`chore(harness): align README.md with harness`)

기존 README.md에 **1-b 모순**이 있으면 동일하게:
- `docs/legacy/README.md.<timestamp>.bak` 백업
- 모순 섹션만 harness 기준으로 치환 (전체 덮어쓰기 금지 — 프로젝트 고유
  소개/설치 안내 등 harness와 무관한 내용은 보존)

모순이 없으면 이 단계 skip.

**3-5. husky 충돌 해결** (`chore(harness): resolve husky conflict`)
`.husky/` 디렉토리가 있으면 사용자에게 선택지 제시:
- **옵션 A (권장)**: harness로 통일. `npm uninstall husky` + 기존 husky
  훅 내용을 `.githooks/pre-commit`에 병합 + `.husky/` 제거
- **옵션 B**: husky 유지. `.githooks/*` 내용을 `.husky/`로 이동 +
  `.githooks/` 제거. `core.hooksPath` 설정 안 함.
사용자 선택 후 실행.

**3-6. CI workflow 병합** (`chore(harness): merge CI workflow`)
`.github/workflows/ci.yml` 기존 파일이 있으면:
- harness의 ci.yml과 diff해서 **누락된 step만 추가** (coverage, audit
  upload, docker-build job 등)
- 기존 job 이름이 `quality-gate`가 아니면 사용자에게 "branch protection
  과 호환되도록 `quality-gate`로 rename할까요?" 질문
- 기존 trigger(main/develop) 유지
없으면 harness의 ci.yml 그대로 유지.

**3-7. Dependabot 병합** (`chore(harness): merge dependabot`)
`.github/dependabot.yml` 있으면 updates 배열에 없는 ecosystem만 추가.
없으면 harness의 것 유지.

**3-8. Claude Code hooks 병합** (`chore(harness): merge .claude/settings.json`)
`.claude/settings.json` 있으면 hooks 객체의 각 배열(PreToolUse,
PostToolUse, SessionStart, Stop)을 **명령 중복 없이** 병합.
없으면 harness의 것 유지.

**3-9. package.json scripts 검증** (필요 시 `chore(harness): add script aliases`)
lint/typecheck/test/build 이름이 harness 가정과 일치하는지 확인.
다른 이름이면 사용자에게 alias 추가 제안 후 동의 시 scripts에 추가.
예: `"check": "tsc --noEmit"` 있으면 `"typecheck": "npm run check"` 제안.

### 4. 스택별 커스터마이징 (통합 계획 E 섹션 실행) (`chore(harness): customize for {stack}`)

1-a에서 감지된 스택 정보를 바탕으로 아래를 자동 수정:

- `scripts/validate.sh`, `validate-quick.sh`의 npm 명령 → 감지된 패키지
  매니저 명령으로 교체 (pnpm/yarn 사용 시)
- `.claude/hooks/run-checks.sh`의 case 문 확장자를 실제 언어로 조정
- `docs/agents/architecture-rules.md`에 실제 src 구조(api/components/
  lib 등)를 "프로젝트 실제 구조" 섹션으로 추가
- `docs/agents/coding-rules.md`에 감지된 로거 라이브러리 명시
- `docs/agents/testing-rules.md`에 감지된 테스트 러너 + 현재 커버리지
  수치(가능하면) 명시
- `docs/agents/deploy-rules.md`에 감지된 배포 타겟(Dockerfile /
  vercel.json / fly.toml / netlify.toml 등) 반영

### 5. 검증 (`chore(harness): verify integration`)

실행:
```
./scripts/validate.sh
```
실패하면 원인 로그 분석 후 수정. 예를 들어 npm 명령 alias가 누락됐으면
3-9단계로 돌아가 추가. 성공할 때까지 반복.

### 6. git hooks 활성화

```
./scripts/setup/install-git-hooks.sh
```
성공 확인 후 다음으로.

### 7. GitHub 보안 설정 (조건부)

`gh auth status`로 인증 확인:
- 인증됨 + origin 있음: `./scripts/setup/setup-repo.sh` 실행
- 아니면: skip하고 사용자에게 "나중에 gh auth login 후 수동 실행 필요"
  안내.

### 8. 최종 푸시

```
git push
```
이전 단계들에서 만든 commit들이 순서대로 원격에 반영됨.

### 9. 완료 보고

다음을 짧게 요약해서 보여주기:
- 추가된 파일 수 / 병합된 파일 수
- husky 처리 결과
- 주요 커스터마이징 (스택/로거/러너/배포 타겟)
- validate 통과 여부
- 다음 단계 안내:
  - 팀에 "harness 도입됨" 공지
  - `docs/agents/` 규칙 파일들을 팀이 읽고 피드백
  - 첫 Epic을 Phase A/B/C 흐름으로 시험 적용

## 강제 규칙 (절대 위반 금지)

- **읽고 수정**: 모든 기존 파일은 반드시 먼저 읽은 뒤 수정.
- **백업 후 교체**: 모순 내용을 교체할 때는 **반드시** 원본을
  `docs/legacy/<파일명>.<timestamp>.bak`으로 백업한 뒤 수정. 백업 없이
  수정 금지.
- **섹션 단위 교체**: 전체 파일 덮어쓰기 금지. markdown heading 또는
  명확한 블록 단위로만 치환. harness와 무관한 내용(프로젝트 고유 소개,
  라이선스, 기여 가이드 등)은 건드리지 않음.
- **단계별 commit**: 각 단계를 독립 commit으로 만들어 특정 단계만
  rollback 가능하게. commit 메시지는 위 예시 그대로.
- **실패 시 중단**: 어느 단계든 실패하면 stop하고 사용자에게 보고.
  그때까지의 commit은 rollback 가능한 상태로 남아있음.
- **승인 게이트 단 1회**: 2단계 일괄 승인 + D 항목의 husky/CI rename
  답변만 필요. 그 외 각 모순 항목별 개별 승인 받지 않음 (C 섹션은
  통합 계획에 포함되어 일괄 승인됨).
````

---

## AI가 자동 처리하는 것 (요약)

| 영역 | 처리 방법 |
|---|---|
| 신규 파일 설치 | install.sh가 skip-safe로 이미 처리 |
| .gitignore / .gitattributes | 헤더 구분 후 append (중복 제외) |
| CLAUDE.md / AGENTS.md / README.md — **누락 섹션** | append (기존 내용 보존) |
| CLAUDE.md / AGENTS.md / README.md — **모순 섹션** | **자동 교체** + 원본 `docs/legacy/<파일>.<timestamp>.bak` 백업 |
| husky 충돌 | 사용자 선택 후 A(harness 통일) 또는 B(husky 유지) 자동 실행 |
| CI workflow | 기존 구조 유지 + 누락 step만 추가. job 이름 rename은 사용자 선택 |
| Dependabot | updates 배열에 누락 ecosystem 추가 |
| Claude settings | hooks 객체 배열 병합 (중복 제거) |
| package.json scripts | alias 제안 후 추가 |
| 스택별 커스터마이징 | 감지된 정보로 규칙 파일·스크립트 자동 수정 |
| 검증 | validate.sh 실패 시 자동 수정 후 재시도 |

**원본 복구**: 모순 교체로 변경된 모든 파일은 `docs/legacy/<파일>.<YYYYMMDD_HHMMSS>.bak`에 저장됩니다. 일부 항목만 되돌리고 싶으면 해당 백업을 수동으로 참조하여 복원 가능.
| 배포 | GitHub 인증 조건부 자동 실행 |

**사용자가 직접 하는 일**:
1. `curl | bash` 한 번
2. Claude Code에 프롬프트 붙여넣기
3. 2번 (husky 처리, CI rename) 승인 또는 선택
4. 끝

---

## 롤백

각 단계가 독립 commit이므로 특정 단계만 되돌리기 쉽습니다:

```bash
# 가장 최근 병합 되돌리기
git reset --soft HEAD~1

# 특정 commit만 되돌리기 (예: husky 병합만 되돌림, 나머지 유지)
git log --oneline | grep "harness"
git revert <해당 commit SHA>
```

harness 전체를 제거하려면:

```bash
# harness가 추가한 commit들을 한 번에 되돌리기 (날짜 기준)
git log --since="2 hours ago" --format=%H --author="$(git config user.name)" | \
  head -n $(git log --since="2 hours ago" --oneline | wc -l) | \
  xargs -I {} git revert --no-edit {}
```

단, `install.sh`가 단순 복사한 파일들(docs/agents/, scripts/ 등)은 git
에 commit되어 있지 않을 수 있으므로 `git clean -n`으로 확인 후 제거.

---

## 문제 해결

| 증상 | 해결 |
|---|---|
| AI가 승인 없이 파일 수정함 | 중단 + `git reset --hard HEAD~N`으로 되돌리고 프롬프트 다시 실행 |
| validate.sh가 계속 실패 | AI가 7회 이상 수정 시도 중이면 중단 + 수동으로 `./scripts/validate.sh`를 실행해 에러 확인 |
| husky 제거 후 기존 훅이 필요 | `.husky/` 삭제 전에 `.husky.backup/`으로 이동해 두고, 필요한 훅만 `.githooks/`로 옮김 |
| CI가 기존 PR에서 실패 | `quality-gate` job 이름 rename이 기존 branch protection의 required checks와 불일치. GitHub UI에서 required checks 업데이트 |
| Windows에서 install.sh 실행 안 됨 | Git Bash에서 실행. PowerShell은 지원 안 함 |

---

## 추가 자료

- 전체 하네스 구조: [README.md](README.md)
- 규칙 상세: [docs/agents/](docs/agents/)
- 향후 확장 가이드: [docs/future-upgrades/](docs/future-upgrades/)
