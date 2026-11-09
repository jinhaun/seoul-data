#!/usr/bin/env bash
# 봇 실행 뒤 게시 기록·쇼츠 주제 기록만 저장소에 올림 (다른 수집 작업과 부딪히면 3번까지 다시 시도)
# 사용: bash bots/올리기.sh "커밋 메시지"
set -u
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add bots/게시기록.csv bots/서울브리핑/리포트/쇼츠주제_기록.csv 2>/dev/null
if git diff --cached --quiet; then echo "올릴 기록 없음"; exit 0; fi
git commit -q -m "$1"
for i in 1 2 3; do
  if git pull --rebase -q && git push -q; then echo "저장소에 올림"; exit 0; fi
  git rebase --abort 2>/dev/null
  sleep 10
done
echo "::warning::게시 기록을 저장소에 올리지 못함 (다음 실행 때 같은 날 다시 올릴 수 있음)"
