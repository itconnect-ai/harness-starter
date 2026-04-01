#!/usr/bin/env bash
# ============================================================================
# .claude/hooks/block-rm.sh
#
# PreToolUse Hook: 위험한 Bash 명령을 차단합니다.
# 매치 시 exit 2로 도구 실행을 블로킹합니다.
#
# 차단 대상:
#   rm -rf, rm -fr, sudo rm, sudo dd, chmod 777, truncate /
#   /etc/ 또는 /usr/ 로의 리다이렉트
# ============================================================================

# stdin에서 JSON 읽기
input=$(cat)

# jq로 명령 추출
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$command" ]; then
  exit 0
fi

# 위험 패턴 목록
dangerous_patterns=(
  "rm -rf"
  "rm -fr"
  "sudo rm"
  "sudo dd"
  "> /etc/"
  "> /usr/"
  "chmod 777"
  "chmod -R 777"
  "truncate /"
  "mkfs\."
  ":(){:|:&};:"
)

for pattern in "${dangerous_patterns[@]}"; do
  if echo "$command" | grep -qF "$pattern"; then
    echo "{\"decision\": \"block\", \"reason\": \"Dangerous command blocked: $pattern\"}" >&2
    exit 2
  fi
done

exit 0
