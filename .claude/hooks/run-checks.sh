#!/usr/bin/env bash
# ============================================================================
# .claude/hooks/run-checks.sh
#
# PostToolUse Hook: 파일 편집 후 "변경 파일에 대해서만" 빠른 검증
# HumanLayer 패턴: 성공 시 침묵, 실패 시에만 에러 노출
#
# 대상: .ts, .tsx, .js, .jsx 파일 편집 시
#
# 설계 원칙:
#   - 프로젝트 전체 lint/typecheck를 매 편집마다 돌리지 않음 (10~60초 오버헤드 × 편집 수)
#   - 변경된 그 파일만 eslint 실행 (수 초 이내)
#   - typecheck는 여기서 하지 않음 — tsc는 프로젝트 단위라 부분 실행 불가,
#     validate-quick.sh에서 1번만 실행하면 충분 (tsc --incremental 캐시로 빠름)
#   - 편집할 때마다 풀 typecheck를 돌리면 inner-loop가 outer-loop 시간이 됨
# ============================================================================

# stdin에서 JSON 읽기
input=$(cat)

# 편집된 파일 경로 추출
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)

if [ -z "$file_path" ]; then
  exit 0
fi

# 대상 확장자 확인
case "$file_path" in
  *.ts|*.tsx|*.js|*.jsx)
    ;;
  *)
    exit 0
    ;;
esac

# 프로젝트 루트로 이동
project_dir="${CLAUDE_PROJECT_DIR:-.}"
cd "$project_dir" || exit 0

# package.json 존재 확인 (템플릿 상태에서는 skip)
if [ ! -f package.json ]; then
  exit 0
fi

# eslint binary 감지
if [ ! -x node_modules/.bin/eslint ]; then
  # eslint 미설치 — 조용히 skip (설정 전 상태일 수 있음)
  exit 0
fi

# 상대 경로로 변환 (CLAUDE_PROJECT_DIR 기준)
relative_path="${file_path#$project_dir/}"
relative_path="${relative_path#./}"

# 파일이 실제로 존재하는지 확인 (삭제된 파일 등)
if [ ! -f "$relative_path" ]; then
  exit 0
fi

# 변경된 파일만 lint (전체 프로젝트 lint보다 훨씬 빠름)
lint_output=$(npx eslint "$relative_path" 2>&1)
lint_exit=$?

if [ $lint_exit -ne 0 ]; then
  echo "Lint failed on $relative_path:" >&2
  echo "$lint_output" >&2
  exit 2
fi

# 성공 시 침묵 (exit 0)
# 프로젝트 전체 typecheck는 story 종료 시 validate-quick이 담당
exit 0
