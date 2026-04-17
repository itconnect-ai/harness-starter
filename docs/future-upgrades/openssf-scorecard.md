# OpenSSF Scorecard — 오픈소스 보안 표준 점수

## 도입 조건

- 프로젝트를 **오픈소스로 외부 공개** (GitHub public repo)
- 사내 전용 프로젝트는 도입 가치 낮음

## 문제 (왜 필요한가)

Linux Foundation의 OpenSSF가 정의한 "보안 Best Practice 18개"를 자동 점검해 0~10점 점수로 보여줍니다:

- Branch Protection 있는가
- Signed Commits 있는가
- Dependency Update Tool(Dependabot) 있는가
- CI Tests 있는가
- Fuzzing 있는가
- SAST 있는가
- Token Permissions(workflow 권한 최소화) 있는가
- Pinned Dependencies(GitHub Actions 버전 고정) 있는가
- ...

이미 현재 하네스가 대부분을 커버하므로 Scorecard 도입 시 고득점 기대. 점수는 외부 사용자/기여자에게 "이 프로젝트는 신뢰할 수 있다"는 신호.

## 구현 개요

### 1. workflow 추가

`.github/workflows/security.yml`에 job 추가 (별도 파일도 가능):

```yaml
  scorecard:
    name: scorecard
    runs-on: ubuntu-latest
    if: github.event_name == 'push' || github.event_name == 'schedule'
    # PR에서는 돌리지 않음 — 원격 리소스 조회 필요
    permissions:
      security-events: write
      id-token: write
      contents: read
      actions: read
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false

      - name: Run analysis
        uses: ossf/scorecard-action@v2.4.0
        with:
          results_file: scorecard-results.sarif
          results_format: sarif
          publish_results: true

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: scorecard-results.sarif
          category: openssf-scorecard
```

### 2. README 배지 추가

```markdown
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/<OWNER>/<REPO>/badge)](https://scorecard.dev/viewer/?uri=github.com/<OWNER>/<REPO>)
```

공개 저장소는 자동으로 Scorecard 서비스에서 점수가 산정되어 배지 URL이 작동.

### 3. 점수 향상 체크리스트

Scorecard가 감점하는 흔한 항목:

- [ ] **Pinned-Dependencies**: GitHub Actions 버전을 `@v4` 대신 `@abc123...` SHA로 고정
- [ ] **Signed-Commits**: 주요 커밋에 GPG/SSH 서명 (`git commit -S`)
- [ ] **Token-Permissions**: workflow마다 최소 permissions 블록 명시
- [ ] **Code-Review**: Branch protection + required review (이미 setup-repo.sh가 설정)
- [ ] **Fuzzing**: 해당 시 OSS-Fuzz 등록

## 하네스 통합 지점

- 현재 Phase 1+2 구현이 Scorecard 항목의 ~70% 커버 예상
  - Branch Protection ✓ (setup-repo.sh)
  - Dependency Update Tool ✓ (Dependabot)
  - CI-Tests ✓ (ci.yml)
  - SAST ✓ (CodeQL)
  - Dangerous-Workflow / Token-Permissions: workflow 권한 block 점검 필요
- 미충족 항목은 도입 시점에 추가로 보강

## 사내 전용 프로젝트에서의 가치

- **점수 배지**: 외부 공개 가치 없음
- **체크리스트 가치**: 있음. Scorecard가 보는 18개 항목은 **일반 보안 baseline**. private repo에서도 `scorecard CLI`를 로컬 실행해 진단 가능

```bash
# 로컬 실행 (public repo만 지원)
docker run -e GITHUB_AUTH_TOKEN=xxx gcr.io/openssf/scorecard:stable \
  --repo=github.com/owner/repo
```

## 참고

- 공식: https://github.com/ossf/scorecard
- Scorecard-action: https://github.com/ossf/scorecard-action
- Scorecard viewer: https://scorecard.dev/
