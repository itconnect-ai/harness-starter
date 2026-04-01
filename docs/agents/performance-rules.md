# docs/agents/performance-rules.md
#
# 성능 규칙입니다. AI 에이전트가 자주 만드는 성능 안티패턴을 방지합니다.
# ⚠️ 프로젝트의 기술 스택에 맞게 수정하세요.

## 데이터베이스 쿼리

- 루프 안에서 DB 쿼리 호출 금지 (N+1 문제)
  - BAD: `users.forEach(u => db.query('SELECT * FROM orders WHERE user_id = ?', u.id))`
  - GOOD: `db.query('SELECT * FROM orders WHERE user_id IN (?)', userIds)`
- ORM 사용 시 관련 데이터를 eager loading으로 가져옴
  - BAD: `prisma.user.findMany()` 후 루프로 orders 조회
  - GOOD: `prisma.user.findMany({ include: { orders: true } })`
- 리스트 쿼리에 반드시 LIMIT 지정 (기본: 100, 최대: 1000)
- `SELECT *` 금지, 필요한 컬럼만 선택
- WHERE, JOIN, ORDER BY에 사용되는 컬럼에 인덱스 필수
- 인덱스 추가 시 마이그레이션 파일에 이유 주석 기록

## 프론트엔드

- `<img>` 대신 최적화된 이미지 컴포넌트 사용 (next/image 등)
- below-the-fold 이미지와 컴포넌트는 lazy-load
- 전체 라이브러리 import 금지 (tree-shake 가능한 개별 import 사용)
  - BAD: `import _ from 'lodash'`
  - GOOD: `import debounce from 'lodash/debounce'`
- JS 번들 사이즈 예산: 경로당 250KB gzipped 이하

## 메모리/이벤트 리스너

- useEffect에서 addEventListener 사용 시 반드시 cleanup 반환
  - BAD: `useEffect(() => { window.addEventListener('resize', handler) }, [])`
  - GOOD: `useEffect(() => { window.addEventListener('resize', handler); return () => window.removeEventListener('resize', handler) }, [])`
- setInterval, setTimeout은 unmount 시 반드시 clear
- Observable/subscription은 unmount 시 반드시 unsubscribe

## API 설계

- 리스트 엔드포인트는 반드시 페이지네이션 (offset+limit 또는 cursor)
- 외부 API 호출에 반드시 timeout 설정
- API 응답에 바운드 없는 배열 반환 금지
