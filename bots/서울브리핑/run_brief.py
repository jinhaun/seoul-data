"""서울 일일 브리핑 한 줄 실행: 집계·품질점검(brief) → 숫자 검증(verify_brief) → Slack 게시
사용: python -X utf8 run_brief.py [기준일] [alert|test]   (기본: 오늘, alert)
GitHub에서는 저장소를 받아 온 상태로 실행하므로 데이터 최신화(git pull)는 워크플로가 한다.
- 검증 통과 → 지정 채널(기본 #alert)에 브리핑 카드
- 데이터 품질 경고가 있으면 → 브리핑에 ⚠️로 표시 + #test에 품질 알림
- 검증 보류 → 브리핑은 올리지 않고 #test에 "보류: 이유"
- 데이터 없음 → #test에 알림
결과는 bots/게시기록.csv 에 남긴다 (게시 / 보류 / 데이터없음 / 실패)
"""
import json
import os
import subprocess
import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
POST = HERE.parent / "post_slack.py"
sys.path.insert(0, str(HERE.parent))
from 게시기록 import record as _record  # noqa: E402

PY = [sys.executable, "-X", "utf8", "-W", "ignore"]
BOT = "서울브리핑"
DRY = os.environ.get("SLACK_DRY_RUN") == "1"  # 시험 실행: 기록을 남기지 않음


def run(script, *args):
    r = subprocess.run(PY + [str(script), *args], capture_output=True, text=True, encoding="utf-8", cwd=HERE)
    return r.returncode, (r.stdout.strip().splitlines() or [r.stderr.strip()[-200:]])[-1]


def record(bot, result):
    if not DRY:
        _record(bot, result)


def notify(msg):
    print(msg)
    print(run(POST, "--text", msg, "test")[1])


def main():
    ref = sys.argv[1] if len(sys.argv) > 1 else str(date.today())
    channel = sys.argv[2] if len(sys.argv) > 2 else "alert"
    tag = date.fromisoformat(ref).strftime("%y%m%d")

    code, last = run(HERE / "brief.py", ref)
    if code != 0:
        record(BOT, "데이터없음" if code == 2 else "실패")
        notify(f"⚠️ 서울 브리핑 중단 (기준일 {ref}): {last}"); sys.exit(code)
    print(f"1/3 집계·품질점검 완료: 리포트/{tag}_서울브리핑.md")

    code, verdict = run(HERE / "verify_brief.py", ref)
    print(f"2/3 숫자 검증: {verdict}")
    if code != 0:
        record(BOT, "보류")
        notify(f"⏸️ 서울 브리핑 보류 (기준일 {ref}) — {verdict}"); sys.exit(1)

    code, last = run(POST, str(HERE / "리포트" / f"{tag}_slack.json"), channel)
    print(f"3/3 {last}")
    if code != 0:
        record(BOT, "실패"); sys.exit(code)
    if channel != "test" and not DRY:
        record(BOT, "게시")
        from brief import record_topics
        record_topics(ref)  # 다음 3일 동안 같은 유형 주제 반복 방지
    issues = json.loads((HERE / "리포트" / f"{tag}_지표.json").read_text(encoding="utf-8"))["품질"]
    if issues and channel != "test":
        notify(f"🔎 서울 브리핑 데이터 품질 경고 (기준일 {ref}): " + " / ".join(issues))


if __name__ == "__main__":
    main()
