# docs/agents/feedback-rules.md
#
# 과거 Epic에서 반복된 실수 패턴을 정리한 활성 교훈 파일입니다.
# 이 파일은 Phase C 회고에서 재작성됩니다 (쌓는 파일이 아님).
#
# 운영 규칙:
#   - 최대 10개 active rule만 유지 (초과 시 가장 오래된 것 retire)
#   - 각 규칙은 source incident id를 가짐
#   - 최근 2 Epic 동안 재발 없으면 retired로 이동
#   - 기계적으로 판별 가능한 패턴은 validate.sh로 승격 후 여기서 제거

## Active Rules

### 1. Windows PowerShell entrypoint must be native (codex-windows-native-pwsh)
- source: 2026-04-17-codex-windows-sandbox
- 발견: Codex Desktop Windows에서 `.ps1`가 Git Bash 래퍼로 동작하면서 validate/git/node 단계가 연쇄 실패
- 규칙: Windows용 `validate.ps1`, `validate-quick.ps1`, `smoke.ps1`는 Bash를 숨겨 호출하지 말고 native PowerShell로 구현한다. Git Bash/WSL은 선택 호환 계층이지 필수 실행 경로가 아니다.
- 승격 상태: `.github/workflows/harness-self-test.yml`에서 핵심 `.ps1` entrypoint의 `Invoke-HarnessBashScript` 의존을 차단

### 2. Codex Windows git must use harness wrapper first (codex-windows-git-wrapper)
- source: 2026-04-17-codex-windows-sandbox
- 발견: Codex Desktop Windows에서 `git fetch/push`가 schannel, credential helper, 기본 Windows env 누락으로 실패
- 규칙: Phase A 자동화와 문서화된 workflow는 raw `git fetch/push`보다 `scripts/lib/git-utils.ps1` 기반 wrapper를 우선 사용한다. wrapper는 Windows 기본 env 복구, OpenSSL fallback, credential-store fallback, secret redaction을 제공해야 한다.
- 승격 상태: active

### 3. Hook fallback requires native validation first (codex-windows-hook-fallback)
- source: 2026-04-17-codex-windows-sandbox
- 발견: Bash 기반 git hook은 Codex Windows sandbox에서 실행되지 않을 수 있음
- 규칙: Windows/Codex에서 `git commit --no-verify` fallback은 native validate/check가 이미 통과한 경우에만 허용한다. hook 실패를 검증 생략으로 해석하지 않는다.
- 승격 상태: active

<!-- 예시 형식:
### 1. 테스트 누락 (missing-tests)
- source: epic-1-story-3
- 발견: Phase B 리뷰에서 2회 반복
- 규칙: 비즈니스 로직 변경 시 반드시 관련 테스트 추가
- 승격 상태: active (validate.sh 승격 검토 중)

### 2. N+1 쿼리 (n-plus-one-query)
- source: epic-1-story-5
- 발견: Phase B 리뷰에서 3회 반복
- 규칙: ORM 사용 시 include/eager loading 필수
- 승격 상태: validate.sh에 자동 감지 추가됨 → retired
-->

## Retired Rules

없음
