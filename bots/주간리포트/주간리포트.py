"""주간 데이터 보고: 지난주 수집 현황 + 외국인 핵심 숫자 + 환율 → Slack #data-매주추가데이터
사용: python -X utf8 주간리포트.py [발송일 YYYY-MM-DD] [data|test]   (기본: 오늘, data)
 - 수집 현황: 발송일 기준 지난주 월~일 (실시간 시간대 수, 매일 작업, 숙박 변화)
 - 외국인: 공개가 4~5일 늦으므로 '최근 공개된 7일 vs 그 전 7일'
 - 숫자 검증: 서울 전체 하루 평균을 요약 파일과 자치구별 파일 두 가지로 따로 계산해 맞는지 확인. 안 맞으면 #test에 보류
예전에는 Claude 예약 작업이 하던 일을 프로그램으로 바꾼 것 (Claude 없이 돌아감)
결과: 리포트/YYMMDD_주간.json, 게시 기록은 bots/게시기록.csv
"""
import csv
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = Path(os.environ.get("SEOUL_DATA_DIR") or HERE.parents[1] / "data")
OUT = HERE / "리포트"
POST = HERE.parent / "post_slack.py"
PY = [sys.executable, "-X", "utf8", "-W", "ignore"]
DRY = os.environ.get("SLACK_DRY_RUN") == "1"
BOT = "주간리포트"
sys.path.insert(0, str(HERE.parent))
from 게시기록 import record as _record  # noqa: E402

WD = "월화수목금토일"


def record(result):
    if not DRY:
        _record(BOT, result)


def rows(p):
    with open(p, encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def md(d):
    return f"{d.month}/{d.day}({WD[d.weekday()]})"


def pct(a, b):
    return None if not b else (a - b) / b * 100


def arr(v):
    return "비교 불가" if v is None else f"{'🔺' if v >= 0 else '🔻'}{abs(v):.1f}%"


def post(args):
    r = subprocess.run(PY + [str(POST), *args], capture_output=True, text=True, encoding="utf-8")
    return r.returncode, (r.stdout + r.stderr).strip()


# ── ① 수집 현황 (지난주 월~일) ──
def collection(days):
    hours = defaultdict(set)
    for r in rows(DATA / "status" / "수집기록.csv"):
        t = r["인구기준시각"]
        if num(r["성공"]) > 0 and len(t) >= 13:
            hours[t[:10]].add(int(t[11:13]))
    daily = defaultdict(list)
    for r in rows(DATA / "status" / "매일작업기록.csv"):
        daily[r["날짜"]].append(r["결과"])
    lodging = defaultdict(lambda: [0, 0, 0])
    lines, short = [], 0
    for d in days:
        k = str(d)
        h = hours.get(k, set())
        miss = [x for x in range(24) if x not in h]
        if miss:
            short += 1
        miss_s = "" if not miss else " · 빠짐 " + (",".join(f"{x}시" for x in miss) if len(miss) <= 6 else f"{len(miss)}개 시간대")
        res = " | ".join(daily.get(k, []))
        ok = "✅" if res and "ERROR" not in res and "실패" not in res else ("⚠️" if res else "❌")
        for kind, a, b, c in re.findall(r"숙박-(\S+): 신규 (\d+), 변경 (\d+), 삭제 (\d+)", res):
            v = lodging[kind]; v[0] += int(a); v[1] += int(b); v[2] += int(c)
        lines.append(f"{md(d):9} 실시간 {len(h):2}/24{miss_s}  매일작업 {ok}")
    lod = " · ".join(f"{k} 신규 {v[0]}·변경 {v[1]}·삭제 {v[2]}" for k, v in lodging.items()) or "변화 기록 없음"
    return lines, short, lod


# ── ② 외국인 (최근 공개 7일 vs 그 전 7일) ──
def foreigner(ref):
    s = sorted((r for r in rows(DATA / "foreigner" / "일별요약_단기.csv") if r["날짜"] < str(ref)), key=lambda r: r["날짜"])
    if len(s) < 14:
        return None
    now, prev = s[-7:], s[-14:-7]
    avg = lambda rs, col: sum(num(r[col]) for r in rs) / len(rs)  # noqa: E731
    nats = [c for c in s[0].keys() if c not in ("날짜", "합계", "기타")]
    top = sorted(nats, key=lambda c: -avg(now, c))[:6]
    wk = [r for r in now if date.fromisoformat(r["날짜"]).weekday() < 5]
    we = [r for r in now if date.fromisoformat(r["날짜"]).weekday() >= 5]
    # 자치구: 하루 평균 = 그날 24개 시간의 평균, 여러 날은 평균
    gu = defaultdict(list)
    check = {}
    for r in now:
        d = r["날짜"]
        p = DATA / "foreigner" / "단기" / d[:7] / f"{d}.csv"
        if not p.exists():
            continue
        per = defaultdict(list)
        for x in rows(p):
            per[x["자치구"]].append(num(x["생활인구합계"]))
        day = {g: sum(v) / len(v) for g, v in per.items()}
        for g, v in day.items():
            gu[g].append(v)
        check[d] = sum(day.values())
    gu_avg = sorted(((g, sum(v) / len(v)) for g, v in gu.items()), key=lambda t: -t[1])[:5]
    return {
        "기간": (now[0]["날짜"], now[-1]["날짜"]), "이전": (prev[0]["날짜"], prev[-1]["날짜"]),
        "합계": (avg(now, "합계"), avg(prev, "합계")),
        "국적": [(c, avg(now, c), avg(prev, c)) for c in top],
        "평일": avg(wk, "합계") if wk else None, "주말": avg(we, "합계") if we else None,
        "자치구": gu_avg, "검증": {r["날짜"]: (num(r["합계"]), check.get(r["날짜"])) for r in now},
    }


# ── ③ 환율 ──
def exchange(ref):
    g = [r for r in rows(DATA / "exchange" / "환율_일별.csv") if r["고시여부"] == "Y" and r["날짜"] <= str(ref)]
    if not g:
        return None
    last = g[-1]
    week = [r for r in g if r["날짜"] <= str(date.fromisoformat(last["날짜"]) - timedelta(days=7))]
    w = week[-1] if week else None
    out = []
    for col, name in (("원_달러", "1달러"), ("원_100엔", "100엔"), ("원_위안", "1위안")):
        out.append((name, num(last[col]), pct(num(last[col]), num(w[col])) if w else None))
    return last["날짜"], out


def main():
    ref = date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else date.today()
    ch = sys.argv[2] if len(sys.argv) > 2 else "data"
    tag = ref.strftime("%y%m%d")
    mon = ref - timedelta(days=ref.weekday() + 7)
    days = [mon + timedelta(days=i) for i in range(7)]

    col, short, lod = collection(days)
    F = foreigner(ref)
    X = exchange(ref)
    if F is None:
        record("데이터없음")
        print(post(["--text", f"⚠️ 주간 데이터 보고 중단 ({ref}): 외국인 자료가 14일치 안 됨", "test"])[1]); sys.exit(2)

    # 숫자 검증: 요약 파일 합계 vs 자치구별 파일로 다시 계산한 합계 (0.5% 안)
    bad = [d for d, (a, b) in F["검증"].items() if b is None or abs(a - b) > a * 0.005]
    if bad:
        record("보류")
        msg = f"⏸️ 주간 데이터 보고 보류 ({ref}) — 서울 전체 하루 평균이 두 계산에서 다름: " + ", ".join(bad)
        print(post(["--text", msg, "test"])[1]); sys.exit(1)

    a, b = F["합계"]
    f1, f2 = (date.fromisoformat(x) for x in F["기간"])
    nat = "\n".join(f"{i}. {c:6} {v:>8,.0f}명  {arr(pct(v, p))}" for i, (c, v, p) in enumerate(F["국적"], 1))
    gus = "\n".join(f"{i}. {g:5} {v:>8,.0f}명" for i, (g, v) in enumerate(F["자치구"], 1))
    wkwe = (f"평일 {F['평일']:,.0f}명 · 주말 {F['주말']:,.0f}명 ({arr(pct(F['주말'], F['평일']))})"
            if F["평일"] and F["주말"] else "평일·주말 비교 불가")
    fx = ("\n".join(f"{n:5} {v:>9,.2f}원  1주 {arr(c)}" for n, v, c in X[1]) if X else "환율 자료 없음")
    blocks = [
        {"type": "header", "text": {"type": "plain_text", "text": f"📊 주간 데이터 보고 ({md(days[0])}~{md(days[-1])})"}},
        {"type": "section", "text": {"type": "mrkdwn", "text":
            "*① 수집 현황* (실시간 = 1시간마다 121곳, 하루 24개가 정상)\n```" + "\n".join(col) + "```\n"
            + ("모든 날 24개 시간대가 다 모였어요." if not short else f"시간대가 빠진 날 {short}일") + f"\n숙박 변화: {lod}"}},
        {"type": "section", "text": {"type": "mrkdwn", "text":
            f"*② 서울 단기체류 외국인* (최근 공개 {f1.month}/{f1.day}~{f2.month}/{f2.day}, 그 전 7일 대비)\n"
            f"하루 평균 *{a:,.0f}명* {arr(pct(a, b))}  ·  {wkwe}\n"
            f"*국적 상위 6*\n```{nat}```\n*자치구 상위 5*\n```{gus}```"}},
        {"type": "section", "text": {"type": "mrkdwn", "text":
            f"*③ 환율* ({X[0] if X else '-'} 고시, 원화 기준)\n```{fx}```"}},
        {"type": "context", "elements": [{"type": "mrkdwn", "text":
            "숫자 검증 ✅ (서울 전체 하루 평균을 두 가지 방법으로 계산해 일치 확인)\n"
            "※ 생활인구는 '그 시간에 서울에 있던 사람 수'의 평균이라 중복 없는 방문객 수가 아니에요.\n"
            "출처: 서울시 단기체류 외국인 생활인구 · 서울시 실시간 도시데이터 · 한국수출입은행 환율 · 자동 생성(깃허브)"}]},
    ]
    OUT.mkdir(exist_ok=True)
    p = OUT / f"{tag}_주간.json"
    p.write_text(json.dumps({"blocks": blocks}, ensure_ascii=False, indent=1), encoding="utf-8")
    code, out = post([str(p), ch])
    print(out)
    record("게시" if code == 0 and ch != "test" else "실패" if code != 0 else "시험")
    sys.exit(code)


if __name__ == "__main__":
    main()
