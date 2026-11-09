"""봇이 오늘 이미 게시했는지 기록·확인 (같은 날 두 번 올리지 않게)
사용: python -X utf8 게시기록.py 확인 <봇이름>        → 오늘 '게시' 또는 '보류' 기록이 있으면 종료코드 0, 없으면 1
      python -X utf8 게시기록.py 남기기 <봇이름> <결과>
기록 파일: bots/게시기록.csv (날짜·봇·결과·시각, 한국 시간)
"""
import csv
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

LOG = Path(__file__).resolve().parent / "게시기록.csv"
KST = timezone(timedelta(hours=9))
FINISHED = ("게시", "보류")  # 이 결과면 그날은 끝. '데이터없음'·'실패'는 다음에 다시 시도


def today():
    return datetime.now(KST).strftime("%Y-%m-%d")


def done(bot):
    if not LOG.exists():
        return False
    with open(LOG, encoding="utf-8-sig") as f:
        return any(r["날짜"] == today() and r["봇"] == bot and r["결과"] in FINISHED for r in csv.DictReader(f))


def record(bot, result):
    new = not LOG.exists()
    with open(LOG, "a", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, quoting=csv.QUOTE_ALL)
        if new:
            w.writerow(["날짜", "봇", "결과", "시각"])
        w.writerow([today(), bot, result, datetime.now(KST).strftime("%Y-%m-%d %H:%M")])


if __name__ == "__main__":
    cmd, bot = sys.argv[1], sys.argv[2]
    if cmd == "확인":
        sys.exit(0 if done(bot) else 1)
    record(bot, sys.argv[3])
