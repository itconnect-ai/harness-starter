docs/agents/ 아래에 seo-rules.md 파일을 새로 만들어줘.
이 프로젝트의 다른 규칙 파일(coding-rules.md, security-rules.md 등)과 동일한 톤/형식을 따라야 해.

아래 내용을 기반으로, 웹 프로젝트에서 에이전트가 SEO·AEO·GEO를 구현할 때 따라야 하는 규칙을 작성해줘.

---

## 규칙에 포함할 내용

### 1. 페이지 메타데이터 규칙

- 모든 page.tsx는 metadata export 또는 generateMetadata 필수
- 'use client' 페이지는 같은 디렉토리에 layout.tsx를 만들어 metadata export
- 필수 필드: title, description, canonical, openGraph (title, description, url)
- title 형식: "{페이지명} | {사이트명} — {핵심 가치}"
- description: 120자 내외, 행동 유도 포함

### 2. 구조화 데이터 (JSON-LD) 규칙 — AEO

- 홈페이지 필수 스키마: Organization, WebSite(+SearchAction), WebPage, FAQPage, Service
- 서비스/제품 페이지: Service 또는 Product 스키마
- 프로세스 설명 페이지: HowTo 스키마
- FAQ 섹션이 있으면: FAQPage 스키마 필수
- 비즈니스 페이지: LocalBusiness 또는 ProfessionalService
- 모든 페이지: BreadcrumbList
- Organization 스키마에 founder, foundingDate, contactPoint 등 상세 정보 포함
- Service 스키마에 구체적 서비스 카탈로그(OfferCatalog) 포함
- sameAs에는 실제 공식 소셜 링크만 (스텁 URL 금지)

### 3. SEO 인프라 규칙

- sitemap.ts: src/app/sitemap.ts에 동적 생성, 모든 공개 페이지 포함, priority/changeFrequency 설정
- robots.ts: src/app/robots.ts에 생성, /admin/, /api/, 비공개 경로 disallow, sitemap URL 포함
- manifest.ts: PWA 메타데이터 (브랜드명, 설명, 아이콘, 테마 컬러)
- googleBot: max-image-preview: large, max-snippet: -1, max-video-preview: -1 포함

### 4. OG 이미지 규칙

- 루트 OG 이미지: src/app/opengraph-image.tsx (1200x630, 브랜드 컬러/로고)
- 페이지별 OG 이미지: 각 라우트 디렉토리에 opengraph-image.tsx 생성 (소셜 공유 빈도 순으로 우선순위)
  - 1순위 — 견적/서비스 페이지: 서비스명 + 핵심 가치 (견적 결과 공유 시나리오)
  - 2순위 — 포트폴리오: 실적 키워드 (레퍼런스 공유)
  - 3순위 — 회사 소개 등 정적 페이지 (공유 빈도 낮음, 후순위 가능)
  - 블로그(향후): 포스트 제목 + 카테고리 (동적 생성 필수)
- Next.js ImageResponse(edge runtime) 사용, 정적 이미지 파일 금지

### 5. AEO (답변엔진 최적화) 규칙

- FAQ 콘텐츠는 질문-답변 구조로 작성 (FAQPage 스키마 매핑)
- 핵심 프로세스는 단계별로 구조화 (HowTo 스키마 매핑)
- 답변은 구체적 수치/사실 포함 (AI가 인용하기 좋은 형태)
- 모든 스키마는 Google Rich Results Test 통과 필수

### 6. GEO (생성형 AI 최적화) 규칙 — 콘텐츠 레이어

GEO는 스키마가 아닌 콘텐츠 레벨에서 작동한다. 핵심은 AI가 답변 생성 시 인용할 수 있는 콘텐츠를 만드는 것이다.

#### 6-1. 페이지별 "인용 유도 핵심 문장" 작성

- 각 주요 페이지에 AI가 인용할 수 있는 **팩트 기반 단문**을 배치
- 추상적 표현 금지 → 구체적 수치/통계 사용
- 예시:
  - ❌ "저렴한 비용으로 빠르게 개발합니다"
  - ✅ "homepage.works는 기존 외주 대비 40~60% 저렴하게, 평균 4~6주 안에 MVP를 완성합니다"
- HTML 시맨틱 마크업(`<strong>` 등)보다 **텍스트 자체의 명확성**이 중요 — LLM 크롤러는 마크업보다 텍스트 밀도를 봄
- GEO 작업은 곧 카피라이팅 수정: 기존 추상적 문구를 팩트 단문으로 교체하는 것이 핵심

#### 6-2. 수치/통계 기반 콘텐츠

- 가격, 기간, 보증 조건, 실적 등 고유 데이터 포인트를 명시
- "N개 서비스 운영", "N건 프로젝트 완료" 등 검증 가능한 수치 포함
- 비교 데이터: "기존 외주 대비 N% 절감" 형태의 비교 문장 포함

#### 6-3. 블로그/아티클 콘텐츠 (장기 전략)

- GEO의 핵심 무기는 장기적으로 블로그/아티클 콘텐츠
- 주제 예시: 외주 개발 가이드, 비용 비교, 기술 선택 가이드, 사례 분석
- 각 아티클에 인용 가능한 팩트 문장 최소 3개 이상 포함
- 블로그 포스트별 동적 OG 이미지 + generateMetadata 필수

### 7. 도메인 규칙

- SITE_URL 상수를 한 곳에서 정의하고 전체에서 참조 (하드코딩 금지)
- 프로젝트 내 도메인 참조는 반드시 통일
- hreflang: 다국어 확장 계획이 있으면 URL 설계 단계에서 결정 (초기부터 /ko/, /en/ 등 구조 확보)

### 8. 적용 시점

```
기획 ──── 설계 ──── 개발 ──── 테스트 ──── 배포
 ▲         ▲                    ▲          ▲
 │         │                    │          │
 GEO       SEO/AEO             검증       SEO
 콘텐츠    메타데이터            스키마     사이트맵
 전략수립   구조설계             유효성     로봇
```

- **기획 단계**: GEO 콘텐츠 전략 수립 (타깃 키워드, 인용 유도 문장 방향, 블로그 주제)
- **설계 단계**: URL 구조, 메타데이터 구조, 스키마 설계, OG 이미지 설계
- **개발 중**: 페이지 생성 시 metadata + JSON-LD + 인용 유도 문장 함께 작성
- **테스트 단계**: 아래 검증 도구 전부 통과 필수
  - Google Rich Results Test (구조화 데이터 유효성)
  - Meta OG 디버거 / 카카오 OG 디버거 (소셜 미리보기)
  - Lighthouse SEO 점수 (90점 이상 목표)
  - 모바일 친화성 테스트
- **배포 직전**: sitemap.ts, robots.ts, OG 이미지, manifest.ts 최종 생성/검증
- **배포 후**: Google Search Console 등록, 네이버 서치어드바이저 등록, 크롤링 확인, 블로그 아티클 발행 시작

---

작성 후 AGENTS.md의 "Repo map" 테이블과 "참조 파일" 부분에 seo-rules.md를 추가해줘.
CLAUDE.md의 "참조 파일" 목록에도 @docs/agents/seo-rules.md를 추가해줘.
