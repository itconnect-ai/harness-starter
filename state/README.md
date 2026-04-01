# state/README.md
#
# 이 폴더는 에이전트의 작업 상태를 추적합니다.
# run-epic.sh가 자동으로 상태 파일을 생성하고 관리합니다.
#
# 파일 설명:
#
# epic-{N}-progress.json
#   - run-epic.sh가 생성
#   - 각 epic의 story 처리 상태 (completed, failed, skipped)
#   - 스크립트를 재실행하면 이 파일을 읽어서 이어서 처리
#   - 초기화하려면 이 파일을 삭제하고 다시 실행
#
# progress-template.json
#   - 상태 파일의 템플릿 (참고용)
#
# 사용 예:
#   # Epic 1 상태 확인
#   cat state/epic-1-progress.json | jq .
#
#   # 완료된 story 목록
#   jq '.completed' state/epic-1-progress.json
#
#   # 실패한 story 목록
#   jq '.failed' state/epic-1-progress.json
#
#   # 상태 초기화 (처음부터 다시)
#   rm state/epic-1-progress.json
