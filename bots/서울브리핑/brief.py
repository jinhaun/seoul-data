"""서울 외국인 데일리: 외국인 추이·자치구 순위·환율·서울 숙박업소 변화.
사용: python -X utf8 brief.py [기준일 YYYY-MM-DD]
외국인은 기준일 전날까지의 최신 공개 자료로 최근 14일과 두 7일 평균을 확인한다.
숙박은 발송일의 성공 수집 기록과 변경 원문을 대조한다.
쇼츠 주제 추천·번호 답글 제작 안내는 종료했으며 프롬프트는 보관 폴더에 남긴다.
출력: 리포트/YYMMDD_서울브리핑.md, _slack.json, _지표.json
"""
import os
import json
import sys
from datetime import date, timedelta
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
DATA = Path(os.environ.get("SEOUL_DATA_DIR") or Path(__file__).resolve().parents[2] / "data")  # 저장소의 data 폴더
OUT = HERE / "리포트"

FOCUS = ["일본", "미국", "중국", "프랑스", "태국"]
FLAG = {"일본": "🇯🇵", "미국": "🇺🇸", "중국": "🇨🇳", "프랑스": "🇫🇷", "태국": "🇹🇭"}
FX = {"일본": ("원_100엔", "100엔"), "미국": ("원_달러", "달러"), "중국": ("원_위안", "위안"), "프랑스": ("원_유로", "유로"), "태국": ("원_바트", "바트")}
SPARK = "▁▂▃▄▅▆▇█"


def pct(a, b):
    return None if not b else (a - b) / b * 100


def arr(v):
    return "비교 불가" if v is None else f"{'🔺' if v >= 0 else '🔻'}{abs(v):.1f}%"


def md_(d):
    return f"{int(d[5:7])}/{int(d[8:10])}"



def spark(vals):
    lo, hi = min(vals), max(vals)
    return "".join(SPARK[0 if hi == lo else int((v - lo) / (hi - lo) * 7)] for v in vals)


# ── 데이터 읽기 ──
def lodging(ref: date):
    """발송일의 성공 수집 기록과 변경 원문을 함께 확인한다. 지난 자료로 대신하지 않는다."""
    kinds = ("호텔", "외국인민박", "숙박업")
    log_path = DATA / "status" / "숙박기록.csv"
    log = pd.read_csv(log_path, dtype=str, keep_default_na=False) if log_path.exists() else None
    result = {"기준일": str(ref), "종류": []}
    for kind in kinds:
        item = {"종류": kind, "상태": "오늘 자료 없음", "건수": None, "신규업소": []}
        entries = log[(log["날짜"] == str(ref)) & (log["종류"] == kind)] if log is not None else None
        if entries is None or entries.empty:
            result["종류"].append(item)
            continue
        logged = {k: int(entries.iloc[-1][k]) for k in ("신규", "변경", "삭제")}
        if any(v < 0 for v in logged.values()):
            raise ValueError(f"숙박 {kind}: 음수 건수")
        path = DATA / "lodging" / "changes" / f"{ref:%Y-%m}" / f"{ref}_{kind}.csv"
        counts = dict.fromkeys(logged, 0)
        if path.exists():
            changes = pd.read_csv(path, dtype=str, keep_default_na=False)
            if not {"구분", "업소명", "자치구"}.issubset(changes.columns):
                raise ValueError(f"숙박 {kind}: 변경 원문의 필수 열 없음")
            if not changes["구분"].isin(counts).all():
                raise ValueError(f"숙박 {kind}: 알 수 없는 변경 구분")
            grouped = changes["구분"].value_counts()
            counts = {k: int(grouped.get(k, 0)) for k in counts}
            item["신규업소"] = changes.loc[changes["구분"] == "신규", ["업소명", "자치구"]].head(2).to_dict("records")
        if counts != logged:
            raise ValueError(f"숙박 {kind}: 수집 기록과 변경 원문 불일치")
        item.update({"상태": "변경 있음" if sum(counts.values()) else "변화 없음", "건수": counts})
        result["종류"].append(item)
    return result


def lodging_text(report):
    def clean(value):
        return " ".join(str(value).split()).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    lines = []
    for item in report["종류"]:
        kind, counts = item["종류"], item["건수"]
        if counts is None:
            lines.append(f"• {kind}: 오늘 자료 없음")
        elif not sum(counts.values()):
            lines.append(f"• {kind}: 변화 없음")
        else:
            lines.append(f"• {kind}: 신규 {counts['신규']:,} · 변경 {counts['변경']:,} · 삭제 {counts['삭제']:,}건")
            examples = [f"{clean(x['업소명']) or '업소명 미상'}({clean(x['자치구']) or '자치구 미상'})" for x in item["신규업소"]]
            if examples:
                lines.append("  신규 예시: " + ", ".join(examples))
    lines.append("※ 직전 수집 목록 대비 변화이며, 신규·삭제가 실제 개업·폐업일을 뜻하지는 않습니다.")
    return "\n".join(lines)


def foreigner(upto: date):
    s = pd.read_csv(DATA / "foreigner" / "일별요약_단기.csv", dtype={"날짜": str}).sort_values("날짜")
    s = s[s["날짜"] <= str(upto)].reset_index(drop=True)
    return s if len(s) >= 14 else None


def district_avg(day: str):
    p = DATA / "foreigner" / "단기" / day[:7] / f"{day}.csv"
    if not p.exists():
        return None
    d = pd.read_csv(p).fillna(0)
    nat = [c for c in d.columns if c not in ("날짜", "시간", "자치구코드", "자치구")]
    return d.groupby("자치구")[nat].sum() / 24, int(d["시간"].nunique()), int(d["자치구"].nunique())


def district_trend(days):
    """자치구별 일별 외국인(단기) 하루 평균 인원: 행=날짜, 열=자치구. 파일 없는 날은 빠짐"""
    out = {}
    for d in days:
        p = DATA / "foreigner" / "단기" / d[:7] / f"{d}.csv"
        if p.exists():
            x = pd.read_csv(p)
            out[d] = x.groupby("자치구")["생활인구합계"].sum() / 24
    return pd.DataFrame(out).T.sort_index() if out else None


def district_rank(t):
    """7일 평균 순위 + 이전 7일 대비 변화·순위 변동 + 14일 흐름"""
    cur, prv = t.iloc[-7:].mean(), t.iloc[-14:-7].mean()
    rank_c = cur.rank(ascending=False, method="first").astype(int)
    rank_p = prv.rank(ascending=False, method="first").astype(int)
    rows = []
    for gu in cur.sort_values(ascending=False).index:
        rows.append({"자치구": gu, "순위": int(rank_c[gu]), "순위변동": int(rank_p[gu] - rank_c[gu]),
                     "7일평균": round(float(cur[gu])), "변화": pct(cur[gu], prv[gu]), "흐름": spark(t[gu].tolist())})
    return rows





def exchange(upto: date):
    e = pd.read_csv(DATA / "exchange" / "환율_일별.csv", dtype={"날짜": str})
    g = e[(e["고시여부"] == "Y") & (e["날짜"] <= str(upto))].sort_values("날짜")
    if g.empty:
        return None
    c = g.iloc[-1]
    cd = date.fromisoformat(c["날짜"])
    w = g[g["날짜"] <= str(cd - timedelta(days=7))].iloc[-1]
    m = g[g["날짜"] <= str(cd - timedelta(days=30))].iloc[-1]
    return {"고시일": c["날짜"], "1주전": w["날짜"], "1개월전": m["날짜"],
            "값": {n: {"현재": float(c[col]), "1주": pct(float(c[col]), float(w[col])), "1개월": pct(float(c[col]), float(m[col]))}
                  for n, (col, _) in FX.items()}}


# ── 쇼츠 주제 후보 ──


def main():
    ref = date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else date.today()
    yday = ref - timedelta(days=1)
    tag = ref.strftime("%y%m%d")

    s = foreigner(yday)
    if s is None:
        print(f"데이터 없음: {yday} 이전 외국인 데이터 14일 미만"); sys.exit(2)
    L = s.iloc[-1]["날짜"]
    dist = district_avg(L)
    X = exchange(ref)
    lodging_report = lodging(ref)
    lodging_txt = lodging_text(lodging_report)

    # ① 5개국 추이
    last14 = s.iloc[-14:]
    trend = []
    for c in FOCUS:
        a, b = s[c].iloc[-7:].mean(), s[c].iloc[-14:-7].mean()
        trend.append({"국적": c, "최신일": int(s[c].iloc[-1]), "7일평균": round(a), "변화": pct(a, b), "흐름": spark(last14[c].tolist())})

    # ④ 자치구별 방문자 추이 랭킹 (최근 14일)
    dt = district_trend(s["날짜"].iloc[-14:].tolist())
    gu_rank = district_rank(dt) if dt is not None and len(dt) == 14 else None

    # 품질
    issues = []
    if s["날짜"].iloc[-14:].tolist() != [str(date.fromisoformat(L) - timedelta(days=13 - i)) for i in range(14)]:
        issues.append("외국인 최근 14일 중 빠진 날 있음")
    lag = (yday - date.fromisoformat(L)).days
    if lag > 6:
        issues.append(f"외국인 데이터 {lag}일 지연")
    if dist is None:
        issues.append("자치구 파일 없음")
    elif dist[1:] != (24, 25):
        issues.append(f"자치구 {dist[1]}시간·{dist[2]}구")
    if gu_rank is None:
        issues.append(f"자치구 14일 파일 중 빠진 날 ({0 if dt is None else len(dt)}/14)")
    if X is None:
        issues.append("환율 없음")
    missing_lodging = [r["종류"] for r in lodging_report["종류"] if r["건수"] is None]
    if missing_lodging:
        issues.append("숙박 오늘 자료 없음 (" + "·".join(missing_lodging) + ")")
    status = "✅ 이상 없음" if not issues else "⚠️ " + " / ".join(issues)

    # ── 출력 ──
    title = f"서울 외국인 데일리 ({md_(L)} 기준)"
    src = "서울시 단기체류 외국인 생활인구 · 유럽중앙은행 기준환율 · 서울시 숙박업소 인허가 목록"
    footer = f"출처: {src} · 발송 기준일 {ref} · 외국인 {s['날짜'].iloc[-14]}~{L} · 환율 {X['고시일'] if X else '-'} · 숙박 수집 확인일 {ref}"
    trend_txt = "\n".join(f"{FLAG[t['국적']]} {t['국적']:<3} {t['흐름']}  {t['최신일']:>6,}명  7일평균 {arr(t['변화'])}" for t in trend)
    fx_txt = "\n".join(f"{FLAG[n]} {FX[n][1]:<4} {v['현재']:>9,.2f}원  1주 {arr(v['1주'])}  1개월 {arr(v['1개월'])}" for n, v in X["값"].items()) if X else "환율 없음"
    def mv(n):
        return "  -" if n == 0 else (f"▲{n}" if n > 0 else f"▼{-n}")
    gu_txt, gu_up = "자치구 데이터 부족", ""
    if gu_rank:
        gu_txt = "\n".join(f"{r['순위']:>2}. {r['자치구']:<4} {mv(r['순위변동']):>3}  {r['7일평균']:>6,}명  {arr(r['변화']):>7}  {r['흐름']}"
                           for r in gu_rank[:10])
        ups = sorted([r for r in gu_rank if r["7일평균"] >= 1000 and r["변화"] is not None], key=lambda r: -r["변화"])
        gu_up = (f"가장 많이 늘어난 구: {ups[0]['자치구']} {arr(ups[0]['변화'])} · 가장 많이 줄어든 구: {ups[-1]['자치구']} {arr(ups[-1]['변화'])}"
                 if ups else "")

    md = [f"# {title}", "", f"## ① 외국인 추이 (최근 14일 · {md_(s['날짜'].iloc[-14])}~{md_(L)})", "```", trend_txt, "```",
          "", f"## ② 자치구별 외국인 순위 상위 10개 구 (7일 평균, 이전 7일 대비 · 순위 변동 · 14일 흐름)", "```", gu_txt, "```", gu_up,
          "", f"## ③ 환율 ({X['고시일'] if X else '-'} 고시)", "```", fx_txt, "```",
          "", f"## ④ 서울 숙박업소 변화 ({ref} 수집)", lodging_txt,
          "", f"데이터 품질: {status}", "", footer, ""]
    OUT.mkdir(exist_ok=True)
    (OUT / f"{tag}_서울브리핑.md").write_text("\n".join(md), encoding="utf-8")
    blocks = [
        {"type": "header", "text": {"type": "plain_text", "text": f"🌏 {title}"}},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*① 외국인 추이* (최근 14일, 서울에 머무는 인원)\n```{trend_txt}```"}},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*② 자치구별 외국인 순위 상위 10개 구* (7일 평균 · 이전 7일 대비 · 순위 변동 · 14일 흐름)\n```{gu_txt}```\n{gu_up}"}},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*③ 환율* ({X['고시일'] if X else '-'} 고시, 원화 기준)\n```{fx_txt}```"}},
        {"type": "divider"},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*🏨 ④ 서울 숙박업소 변화* ({ref} 수집)\n{lodging_txt}"}},
        {"type": "context", "elements": [{"type": "mrkdwn", "text": f"데이터 품질 {status}\n{footer}"}]},
    ]
    (OUT / f"{tag}_slack.json").write_text(json.dumps({"blocks": blocks}, ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT / f"{tag}_지표.json").write_text(json.dumps({"기준일": str(ref), "최신일": L, "추이": trend, "자치구랭킹": gu_rank, "환율": X,
                                                      "숙박": lodging_report, "품질": issues}, ensure_ascii=False, indent=1, default=float), encoding="utf-8")
    print("\n".join(md))



if __name__ == "__main__":
    main()
