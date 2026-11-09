"""명령 한 줄로 전부: 집계 → 숫자 검증 → 쇼츠 영상·썸네일 생성 → Slack 게시.
사용: python -X utf8 실행.py [test|alert] [발송일]      (기본: test, 오늘)
GitHub에서는 저장소를 받아 온 상태로 실행하므로 데이터 최신화(git pull)는 워크플로가 한다.
검증에서 걸리면 영상을 만들지 않고 #test에 경고만 보낸다.
영상 만들기는 Windows(그림 그리기·글꼴)에서만 된다. 영상 없이 카드만 올리려면 NO_VIDEO=1.
결과는 bots/게시기록.csv 에 남긴다 (게시 / 보류 / 실패)
"""
import json
import os
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
PY = [sys.executable, "-X", "utf8", "-W", "ignore"]
POST = HERE.parent / "post_slack.py"
CFG = json.loads((HERE / "설정.json").read_text(encoding="utf-8"))
DRY = os.environ.get("SLACK_DRY_RUN") == "1"
NO_VIDEO = os.environ.get("NO_VIDEO") == "1" or os.name != "nt"
BOT = "국가대항전"
sys.path.insert(0, str(HERE.parent))
from 게시기록 import record as _record  # noqa: E402


def record(result):
    if not DRY:
        _record(BOT, result)


def run(args, enc="utf-8"):
    r = subprocess.run(args, capture_output=True, text=True, encoding=enc, errors="replace")
    return r.returncode, (r.stdout + r.stderr).strip()


def step(n, msg):
    print(f"[{n}/4] {msg}", flush=True)


def main():
    ch = sys.argv[1] if len(sys.argv) > 1 else "test"
    ref = sys.argv[2] if len(sys.argv) > 2 else str(date.today())
    tag = date.fromisoformat(ref).strftime("%y%m%d")
    t0 = time.time()
    print(f"🏆 서울 외국인 국가대항전 자동 제작 — 발송일 {ref}\n")

    code, out = run(PY + [str(HERE / "집계.py"), ref])
    step(1, "주간 순위 계산: " + (out.splitlines()[-1] if out else str(code)))
    if code != 0:
        record("실패")
        run(PY + [str(POST), "--text", f"⚠️ 국가대항전 보류 ({ref}): {out[-200:]}", "test"]); sys.exit(code)

    code, out = run(PY + [str(HERE / "검증.py"), ref])
    verdict = out.splitlines()[-1] if out else "보류: 출력 없음"
    step(2, "숫자 검증 (다른 방법으로 재계산): " + verdict)
    if code != 0:
        record("보류")
        run(PY + [str(POST), "--text", f"⚠️ 국가대항전 검증 {verdict} ({ref}) — 영상을 만들지 않았어요", "test"]); sys.exit(3)

    files = []
    if NO_VIDEO:
        step(3, "영상 만들기 건너뜀 (Windows가 아님 또는 NO_VIDEO=1)")
    else:
        step(3, "쇼츠 영상·썸네일·배경음악 만드는 중 (약 1~3분)...")
        code, out = run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(HERE / "영상만들기.ps1"), "-Tag", tag])
        print("      " + "\n      ".join(out.splitlines()[-3:]))
        if code != 0:
            run(PY + [str(POST), "--text", f"⚠️ 국가대항전 영상 생성 실패 ({ref}) — 카드만 올려요", "test"])
        else:
            # 배경음악(직접 작곡한 곡, 목소리 나올 때 자동으로 작아짐). 실패해도 음악 없는 영상으로 계속 진행
            video = HERE / "리포트" / f"{tag}_쇼츠.mp4"
            code, out = run(PY + [str(HERE.parent / "음악" / "음악넣기.py"), str(video), CFG["배경음악"]])
            if code == 0:
                video = HERE / "리포트" / f"{tag}_쇼츠_음악.mp4"
            print("      배경음악: " + ((out.splitlines() or [""])[-1] if code == 0 else "실패 → 음악 없이 진행"))
            files = [str(video), str(HERE / "리포트" / f"{tag}_썸네일.png")]

    args = PY + [str(POST), str(HERE / "리포트" / f"{tag}_slack.json"), ch]
    code, out = run(args + (["--files"] + files if files else []))
    step(4, "Slack 게시: " + out.replace("\n", " / "))
    record("게시" if code == 0 and ch != "test" else "실패" if code != 0 else "시험")
    print(f"\n완료 · 총 {time.time() - t0:.0f}초")
    sys.exit(code)


if __name__ == "__main__":
    main()
