# docs/agents/testing-rules.md
#
# 테스트 작성과 실행에 대한 규칙입니다.
# ⚠️ 프로젝트의 테스트 프레임워크에 맞게 수정하세요.

## 테스트 필수 대상

- 새로 추가된 비즈니스 로직
- 변경된 기존 동작
- 버그 수정 (재발 방지 테스트)
- API 엔드포인트
- 사용자 입력 검증 로직

## 테스트 불필요 대상

- 순수 UI 스타일링 변경
- 타입 정의만 변경
- 설정 파일만 변경
- 문서만 변경

## 테스트 작성 원칙

- 테스트 이름은 "무엇을 했을 때 무엇이 되어야 한다" 형식
- 하나의 테스트에 하나의 검증
- 외부 의존성은 mock 처리
- 테스트 데이터는 테스트 파일 내에 명시

## 테스트 격리 규칙 (병렬 충돌 방지)

테스트 간 공유 자원 충돌을 방지하기 위해 다음 규칙을 따릅니다:

- DB: 테스트별 트랜잭션 롤백 또는 테스트 전용 DB 사용. 공유 DB에 직접 쓰기 금지
- 포트: 테스트에서 서버를 띄울 때 `port: 0` 사용 (OS가 빈 포트 자동 할당)
- 파일 시스템: 임시 파일은 테스트별 고유 `tmp` 디렉토리 사용 (`mkdtemp` 패턴)
- 전역 상태: `beforeEach`에서 초기화, `afterEach`에서 정리. 테스트 간 상태 공유 금지
- 환경변수: 테스트에서 `process.env`를 직접 수정하지 않음. mock 또는 설정 주입 사용
- 타이머/시간: `vi.useFakeTimers()` 또는 `jest.useFakeTimers()` 사용 시 `afterEach`에서 반드시 복원

validate.sh는 `--no-threads` (Vitest) 또는 `--runInBand` (Jest)로 순차 실행합니다.
격리 규칙이 충분히 정착되면 병렬 실행으로 전환할 수 있습니다.

## 2단계 검증 체계

| 시점 | 스크립트 | 범위 | 목적 |
|---|---|---|---|
| Story 완료 시 | `validate-quick.sh` | lint + typecheck + 변경 파일 관련 테스트 | 빠른 피드백 (30초 이내) |
| Epic 완료 시 | `validate.sh` | 전체 (의존성 + 타입 + 린트 + 전체 테스트 + 빌드 + 보안 + 성능) | 통합 검증 |

- Story 단위에서는 전체 테스트를 돌리지 않음 (아직 구현 안 된 Story의 테스트 실패 방지)
- Epic 단위에서 전체 테스트를 순차 실행하여 병렬 충돌 없이 통합 검증
- validate.sh 실패 시 `--from=실패단계`로 해당 단계부터 재개 가능

## 검증 출력과 로그

- 기본 출력은 summary 모드: 단계별 성공/실패 + 소요시간만 표시
- 전체 출력: `VALIDATE_OUTPUT_MODE=verbose`로 설정
- 모든 실행의 원본 로그는 `state/validate/latest/*.log`에 단계별로 저장
- 실패 시 summary에 로그 경로 + 실패 테스트명 + 마지막 50줄이 포함됨
- 실패 디버깅: summary 출력의 로그 경로를 읽어서 원인 파악 (전체 로그를 콘솔에 쏟지 않음)

## 실행 명령

- Story 빠른 검증: `./scripts/validate-quick.sh`
- Epic 전체 검증: `./scripts/validate.sh`
- 실패 단계부터 재개: `./scripts/validate.sh --from=test`
- 전체 출력 모드: `VALIDATE_OUTPUT_MODE=verbose ./scripts/validate.sh`
- 특정 파일: `npm run test -- --grep "파일명"`
- 커버리지: `npm run test:coverage`

## 검증 순서

1. 타입 체크 통과
2. lint 통과
3. 단위 테스트 통과 (순차 실행)
4. 회귀 테스트 통과
5. 빌드 성공
6. (해당 시) 통합 테스트 통과
