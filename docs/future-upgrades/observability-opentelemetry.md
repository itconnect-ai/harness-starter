# 관측성(Observability) — OpenTelemetry + Jaeger + Prometheus + Grafana

## 도입 조건

아래 중 **하나 이상** 해당하면 추가 검토:

- 운영 중 "어느 API가 느린지" 질문이 반복되는데 로그로는 답이 안 나옴
- p95 응답 시간 또는 에러율이 SLA 지표가 됨 (고객과 약속)
- 서비스가 여러 개(2+)로 분리되어 요청이 어느 서비스에서 실패했는지 추적 필요
- 운영 중 on-call 당직자가 대시보드를 봐야 함

예측적 도입 금지. 위 조건이 **실제** 발생한 뒤 도입.

## 문제 (왜 필요한가)

로그만으로는 "느린 요청"을 찾을 수 없습니다. 예:
- 요청 A: DB 쿼리 3초 → 원인이 쿼리
- 요청 B: 외부 API 3초 → 원인이 외부
- 로그는 둘 다 "3초" 라고만 기록

Tracing이 필요한 이유: **한 요청의 모든 단계(span)를 나무 구조로** 시각화. 어느 단계가 느렸는지 즉시 확인.

Metrics가 필요한 이유: "p95 응답 시간이 500ms 넘으면 알림" 같은 SLA 자동 모니터링.

## 구현 개요

### 1. 로컬 관측성 스택 (`docker-compose.observability.yml`)

3개 컨테이너:

- **otel-collector** (포트 4317 gRPC / 4318 HTTP): 앱에서 OTLP로 데이터 수신
- **jaeger** (포트 16686): 트레이스 시각화 UI
- **prometheus** (포트 9090): 메트릭 수집

```yaml
# docker-compose.observability.yml (예시)
name: <접두사>-obs
x-environment: development

services:
  otel-collector:
    container_name: <접두사>-otel
    image: otel/opentelemetry-collector-contrib:latest
    command: ["--config=/etc/otel-collector-config.yaml"]
    volumes:
      - ./observability/otel-collector-config.yaml:/etc/otel-collector-config.yaml
    ports:
      - "4317:4317"
      - "4318:4318"

  jaeger:
    container_name: <접두사>-jaeger
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"

  prometheus:
    container_name: <접두사>-prometheus
    image: prom/prometheus:latest
    volumes:
      - ./observability/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
```

(`docker-rules.md` 네이밍 규칙을 따라 `-obs` 접미사 사용. compose name도 `-obs`로 분리하여 앱 환경과 섞이지 않게.)

### 2. 앱 SDK 연동

**기술 스택별로 다름**. 예시는 Node.js (Express/Next.js 공통):

```typescript
// instrumentation.ts
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT ?? 'http://localhost:4318/v1/traces',
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();
```

기본으로 HTTP, DB 쿼리, 외부 API 호출이 자동 추적됨.

### 3. 커스텀 Span / 메트릭

비즈니스 중요 지점에 추가:

```typescript
const tracer = trace.getTracer('my-app');

await tracer.startActiveSpan('checkout.process-payment', async (span) => {
  span.setAttribute('order.id', orderId);
  span.setAttribute('order.amount', amount);
  try {
    const result = await processPayment(orderId);
    return result;
  } catch (err) {
    span.recordException(err);
    span.setStatus({ code: SpanStatusCode.ERROR });
    throw err;
  } finally {
    span.end();
  }
});
```

### 4. 대시보드 + 알림

Grafana 대시보드 템플릿:
- p50/p95/p99 응답 시간 (per route)
- 에러율 (per route)
- throughput (요청/초)
- DB 쿼리 시간
- 외부 API 호출 시간

Grafana Alert 규칙:
- p95 응답 > 1초 (5분 지속) → Slack 알림
- 에러율 > 1% (5분 지속) → 즉시 알림
- CPU 사용률 > 80% (10분 지속) → 경고

## 하네스 통합 지점

- 새 문서 `docs/agents/observability-rules.md` 생성
- `coding-rules.md`에 "비즈니스 이벤트는 반드시 span으로 감싸기" 규칙 추가
- `deploy-rules.md`에 "운영 서비스는 Prometheus `/metrics` 엔드포인트 제공 필수" 추가
- Docker 네이밍: `<접두사>-otel`, `<접두사>-jaeger`, `<접두사>-prometheus` (docker-rules §1-2 허용 목록 확장)
- `validate.sh`에 OTEL 환경변수 설정 존재 확인 단계 추가

## 유지 비용 경고

- 3개 컨테이너 추가 운영 → 메모리 2GB+ 추가
- Prometheus 디스크 증가 속도 관리 필요 (기본 15일 보존)
- Grafana 대시보드 관리 (팀원 1명 주당 2시간+)
- **소규모 프로젝트에는 과잉**. 단일 서비스 + 트래픽 적으면 도입 금지.

## 참고

- OpenTelemetry: https://opentelemetry.io/docs/
- Node SDK: https://opentelemetry.io/docs/languages/js/
- Jaeger: https://www.jaegertracing.io/
- Grafana dashboards for OTel: https://grafana.com/grafana/dashboards/
