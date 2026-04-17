# DAST — OWASP ZAP 동적 보안 스캔

## 도입 조건

- 웹 앱이 **외부에 공개**됨 (회원가입/로그인/결제 등 사용자 상호작용 페이지 존재)
- 현재 Phase 1의 CodeQL(SAST)은 소스 코드만 분석. 외부에서 접근 가능한 앱의 **실행 시 취약점**(auth bypass, session fixation, CSRF 등)은 DAST로만 잡힘.

## 문제 (왜 필요한가)

SAST와 DAST의 차이:

| 분석 방식 | 대상 | 강점 | 약점 |
|---|---|---|---|
| SAST (CodeQL) | 소스 코드 | 빠름, 조기 감지, 정확한 위치 | 런타임 컨텍스트 모름 (auth 우회 등) |
| DAST (ZAP) | 실행 중인 앱 | 실제 공격 시나리오 반영 | 느림, 특정 페이지만 스캔, false positive 많음 |

외부 공개 웹 앱은 둘 다 있어야 완성. 내부 API 서비스나 SSR 없는 정적 사이트는 SAST만으로도 충분할 수 있음.

## 구현 개요

### 1. 별도 workflow로 분리

`.github/workflows/security-dast.yml`:

```yaml
name: Security DAST

on:
  workflow_dispatch:
    inputs:
      target_url:
        description: '스캔 대상 URL (예: https://staging.example.com)'
        required: true
        type: string
  schedule:
    - cron: '0 20 * * 0'  # 매주 일요일 20:00 UTC (월요일 05:00 KST)

permissions:
  contents: read
  issues: write

jobs:
  zap-baseline:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: ZAP Baseline Scan
        uses: zaproxy/action-baseline@v0.13.0
        with:
          target: ${{ inputs.target_url || 'https://staging.example.com' }}
          rules_file_name: '.zap/rules.tsv'
          cmd_options: '-a'   # alpha 규칙 포함
          fail_action: true
          allow_issue_writing: true
```

**왜 별도 workflow인가**:
- DAST는 수 분 ~ 수십 분 소요. 모든 PR에 돌리면 CI 느려짐
- 실행 중인 배포 서버를 대상으로 하므로 "배포 후 ~ 프로덕션 승격 전" 타이밍이 맞음
- `workflow_dispatch`로 수동 실행 가능 + 주간 스케줄

### 2. 규칙 파일 `.zap/rules.tsv`

ZAP baseline scan이 기본으로 잡는 것 중 false positive 비율이 높은 규칙을 무시:

```
10015	IGNORE	(Incomplete or No Cache-control Header Set)
10023	IGNORE	(Information Disclosure - Debug Error Messages)
10063	IGNORE	(Permissions Policy Header Not Set)
10098	IGNORE	(Cross-Domain Misconfiguration)
10202	IGNORE	(Absence of Anti-CSRF Tokens) - SPA라면 무시, MPA라면 유지
90004	IGNORE	(Insufficient Site Isolation Against Spectre)
```

프로젝트 특성에 맞게 조정 (SPA인지 MPA인지, auth 방식이 session인지 JWT인지 등).

### 3. 결과 처리

- `fail_action: true` → CRITICAL 발견 시 workflow 실패
- 결과를 자동으로 GitHub Issue로 생성 (`allow_issue_writing: true`)
- 기존 issue가 있으면 업데이트하여 소음 방지

### 4. 스캔 대상 URL 결정

- **스테이징 환경** 우선 — 프로덕션은 응답 저하 가능
- 공개 URL이 없는 경우: workflow에서 docker compose up → 테스트 컨테이너 대상 스캔
- 인증이 필요한 페이지는 ZAP context 파일로 자동 로그인 설정

## 하네스 통합 지점

- 기존 `.github/workflows/security.yml`은 SAST/의존성 스캔 (빠른 체크)
- 새 `.github/workflows/security-dast.yml`은 DAST (느린, 주간/수동)
- `deploy.yml`의 production 배포 직전에 `security-dast.yml` 호출 옵션 추가 (수동 gate)
- `docs/agents/security-rules.md`에 "외부 공개 페이지는 DAST 통과 필수" 추가

## 참고

- OWASP ZAP: https://www.zaproxy.org/
- ZAP GitHub Action: https://github.com/zaproxy/action-baseline
- Rules file format: https://www.zaproxy.org/docs/desktop/addons/active-scan-rules/
