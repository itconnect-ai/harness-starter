# docs/future-upgrades/

현재 하네스에 **아직 포함되지 않은** 보안/운영 기능의 도입 가이드입니다. 프로젝트가 특정 조건에 도달하면 해당 문서를 참고해 추가하세요.

## 문서 목록

| 파일 | 도입 조건(trigger) | 핵심 값 |
|---|---|---|
| [oidc-cloud-auth.md](oidc-cloud-auth.md) | 클라우드(AWS/GCP/Azure) 배포 시작 | 장기 access key 없는 배포 인증 |
| [observability-opentelemetry.md](observability-opentelemetry.md) | 서비스 응답 시간 문제 발생 / 운영 대시보드 필요 | 분산 추적·메트릭·알림 |
| [dast-owasp-zap.md](dast-owasp-zap.md) | 외부 공개 웹 앱 배포 | 실행 중 앱에 대한 취약점 스캔 |
| [openssf-scorecard.md](openssf-scorecard.md) | 오픈소스로 외부 공개 | 보안 표준 점수 + 배지 |

## 추가 시점 판단 기준

- **비용 대비 가치**: 지금 하네스에 넣지 않은 이유는 "유지보수 비용 > 현재 가치"라서입니다. 상황이 바뀌면 이 비율이 역전됩니다.
- **트리거 이벤트**: 각 문서의 "도입 조건" 항목이 충족되면 추가 검토. 예측적 도입(만약을 위해) 금지.
- **Phase C 회고에서 검토**: Epic 회고 시 "이번 Epic에서 이 기능이 있었으면 사고를 막을 수 있었나?"를 체크. YES면 다음 Epic에 도입.

## 도입 시 공통 절차

1. 해당 future-upgrades 문서를 처음부터 끝까지 읽기
2. `docs/agents/*.md` 기존 규칙과의 통합 지점 확인
3. 구현 후 이 디렉토리의 해당 파일 삭제 + 대신 `docs/agents/` 또는 `docs/changelog/`로 이관
4. `feedback/incidents/`에 "이 기능 도입의 배경 incident" 기록 (미래 판단에 참고)
