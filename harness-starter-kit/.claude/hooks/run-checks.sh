#!/usr/bin/env bash
# ============================================================================
# .claude/hooks/run-checks.sh
#
# PostToolUse Hook: 파일 편집 후 자동으로 lint + typecheck 실행
# HumanLayer 패턴: 성공 시 침묵, 실패 시에만 에러 노출
#
# 대상: .ts, .tsx, .js, .jsx 파일 편집 시
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

# package.json 존재 확인
project_dir="${CLAUDE_PROJECT_DIR:-.}"
if [ ! -f "$project_dir/package.json" ]; then
  exit 0
fi

cd "$project_dir" || exit 0

# lint 실행 (실패 시에만 출력)
lint_output=$(npm run lint --silent 2>&1)
lint_exit=$?

if [ $lint_exit -ne 0 ]; then
  echo "Lint failed:" >&2
  echo "$lint_output" >&2
  exit 2
fi

# typecheck 실행 (실패 시에만 출력)
typecheck_output=$(npm run typecheck --silent 2>&1)
typecheck_exit=$?

if [ $typecheck_exit -ne 0 ]; then
  echo "Type check failed:" >&2
  echo "$typecheck_output" >&2
  exit 2
fi

# 성공 시 침묵 (exit 0)
exit 0
