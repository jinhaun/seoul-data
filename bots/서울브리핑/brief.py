"""서울 외국인 데일리: ① 5개국 방문자 추이 ② 환율 ③ 오늘의 쇼츠 주제 3개

사용: python -X utf8 brief.py [기준일 YYYY-MM-DD]   (생략 시 오늘)
 - 방문자(단기체류 외국인 생활인구 = 그 순간 서울에 머무는 인원): 어제 이전 최신 공개일 L 기준 최근 14일, 7일 평균 vs 이전 7일
 - 환율: 기준일 이전 마지막 고시 vs 1주 전·1개월 전 고시
 - 쇼츠 주제: 외국인(국적·자치구)·실시간 유동인구(어제 vs 1주 전 같은 요일)·환율·항공에서 규칙으로 후보를 만들고 점수 상위 3개
   (최근 3일 동안 나온 주제 유형은 건너뜀 → 리포트/쇼츠주제_기록.csv)
출력: 리포트/YYMMDD_서울브리핑.md, _slack.json, _지표.json   종료코드: 0 정상 / 2 데이터 없음
"""
import os
import csv
import json
import sys
from datetime import date, timedelta
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
DATA = Path(os.environ.get("SEOUL_DATA_DIR") or Path(__file__).resolve().parents[2] / "data")  # 저장소의 data 폴더
OUT = HERE / "리포트"
HISTORY = OUT / "쇼츠주제_기록.csv"

FOCUS = ["일본", "미국", "중국", "프랑스", "태국"]
FLAG = {"일본": "🇯🇵", "미국": "🇺🇸", "중국": "🇨🇳", "프랑스": "🇫🇷", "태국": "🇹🇭"}
FX = {"일본": ("원_100엔", "100엔"), "미국": ("원_달러", "달러"), "중국": ("원_위안", "위안"), "프랑스": ("원_유로", "유로"), "태국": ("원_바트", "바트")}
AIRPORTS = {
    "일본": {"NRT", "HND", "KIX", "ITM", "UKB", "FUK", "CTS", "NGO", "OKA", "KOJ", "KMJ", "OIT", "FSZ", "HIJ", "KKJ", "TAK", "MYJ",
             "OKJ", "SDJ", "KIJ", "AOJ", "UBJ", "TOY", "NGS", "KMQ", "YGJ", "ISG", "MMY", "ASJ", "AXT", "IBR", "HKD", "KMI", "OKD"},
    "중국": {"PEK", "PKX", "PVG", "SHA", "CAN", "SZX", "TAO", "SHE", "DLC", "YNT", "WEH", "CGO", "HGH", "NKG", "XMN", "CTU", "TFU",
             "CKG", "XIY", "KMG", "HRB", "YNJ", "TSN", "WUH", "CSX", "NNG", "HAK", "SYX", "CGQ", "SJW", "TNA", "KWE", "LHW", "DYG"},
    "미국": {"JFK", "LAX", "SFO", "SEA", "ORD", "ATL", "DFW", "IAD", "BOS", "LAS", "HNL", "ANC", "DTW", "MSP", "IAH", "EWR", "SLC"},
    "프랑스": {"CDG", "ORY", "NCE"},
    "태국": {"BKK", "DMK", "CNX", "HKT", "USM", "KBV", "UTP"},
}
SPARK = "▁▂▃▄▅▆▇█"


def pct(a, b):
    return None if not b else (a - b) / b * 100


def arr(v):
    return "비교 불가" if v is None else f"{'🔺' if v >= 0 else '🔻'}{abs(v):.1f}%"


def md_(d):
    return f"{int(d[5:7])}/{int(d[8:10])}"


def j(word, pair):
    """받침에 맞는 조사: j('태국','이가') → '태국이'"""
    c = word[-1]
    has = "가" <= c <= "힣" and (ord(c) - 0xAC00) % 28 != 0
    first = pair in ("이가", "은는", "을를")
    return word + (pair[0] if has == first else pair[1]) if first else word + (pair[1] if has else pair[0])


def spark(vals):
    lo, hi = min(vals), max(vals)
    return "".join(SPARK[0 if hi == lo else int((v - lo) / (hi - lo) * 7)] for v in vals)


# ── 데이터 읽기 ──
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


def realtime(day: date):
    p = DATA / "realtime" / f"{day:%Y-%m}" / f"{day}.csv"
    if not p.exists():
        return None
    r = pd.read_csv(p)
    r = r[r["인구기준시각"].str.startswith(str(day))].drop_duplicates(["인구기준시각", "장소"])
    r = r.dropna(subset=["인구_최소", "인구_최대"])
    r["인구"] = (r["인구_최소"] + r["인구_최대"]) / 2
    r["시"] = r["인구기준시각"].str[11:13].astype(int)
    return r


def flights(day: date):
    p = DATA / "flights" / f"{day:%Y-%m}" / f"{day}.csv"
    if not p.exists():
        return None
    f = pd.read_csv(p)
    f = f[(f["국내국제"] == "국제") & (f["마스터편명"].isna())].drop_duplicates(["공항", "구분", "편명", "예정시각"])
    return {k: int(f["상대공항코드"].isin(v).sum()) for k, v in AIRPORTS.items()}


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
def topics(s, dist, rt_y, rt_w, fl, X, nat_all):
    T = []
    last = s.iloc[-1]
    L = last["날짜"]

    # 1) 1위 다툼 / 평소와 다른 1위
    leaders = s[nat_all].idxmax(axis=1).tolist()
    usual = max(set(leaders), key=leaders.count)
    last7 = leaders[-7:]
    rank = sorted(nat_all, key=lambda c: -last[c])
    if len(set(last7)) >= 2 or rank[0] != usual:
        cnt = {x: last7.count(x) for x in dict.fromkeys(last7)}
        other = rank[0] if rank[0] != usual else rank[1]
        T.append({"유형": "1위다툼", "점수": 90,
                  "제목": f"서울 외국인 1위가 {j(usual, '이가')} 아닌 날? {j(other, '와과')} 벌이는 1위 다툼",
                  "근거": f"최근 7일 1위: " + ", ".join(f"{k} {v}일" for k, v in cnt.items()) + f" · {md_(L)} {rank[0]} {int(last[rank[0]]):,} vs {rank[1]} {int(last[rank[1]]):,} (올해 {usual} 1위 {leaders.count(usual)}/{len(leaders)}일)",
                  "값": {"최근7일": cnt, "1위": rank[0], "2위": rank[1]}})

    # 2) 7일 평균 급증 국적 (기준 1,000명 이상)
    c7, p7 = s.iloc[-7:], s.iloc[-14:-7]
    ch = [(c, c7[c].mean(), p7[c].mean()) for c in nat_all if p7[c].mean() >= 1000]
    c, a, b = max(ch, key=lambda x: (x[1] - x[2]) / x[2])
    g = (a - b) / b * 100
    if g > 5:
        T.append({"유형": "급증국적", "점수": min(85, 30 + g * 3),
                  "제목": f"요즘 서울에 갑자기 늘어난 외국인 1위는 {c}",
                  "근거": f"{c} 7일 평균 {round(a):,}명, 이전 7일보다 {g:+.1f}%", "값": {"국적": c, "변화": round(g, 2)}})

    # 3) 자치구별 특이 국적 (서울 평균 대비 비율이 가장 높은 구·국적)
    if dist is not None:
        D = dist[0]
        tot = D["생활인구합계"]
        best = None
        for n in nat_all:
            city_share = D[n].sum() / tot.sum()
            if D[n].sum() < 500:
                continue
            for gu in D.index:
                if D.at[gu, n] < 300:
                    continue
                ratio = (D.at[gu, n] / tot[gu]) / city_share
                if best is None or ratio > best[0]:
                    best = (ratio, n, gu, D.at[gu, n] / tot[gu] * 100, city_share * 100, D.at[gu, n])
        if best:
            ratio, n, gu, sh, cs = best[:5]
            T.append({"유형": "자치구특이", "점수": min(80, 20 + ratio * 12),
                      "제목": f"서울에서 {n}인 비율이 가장 높은 동네는 {gu}",
                      "근거": f"{md_(L)} {gu} 외국인 중 {n} {sh:.1f}% (서울 전체 {cs:.1f}%의 {ratio:.1f}배, 약 {round(best[5]):,}명)",
                      "값": {"국적": n, "자치구": gu, "배율": round(ratio, 2)}})

    # 4) 실시간: 어제 평소(1주 전 같은 요일)보다 사람이 몰린 곳 (두 날 모두 있는 시간만 비교)
    if rt_y is not None and rt_w is not None:
        hrs = sorted(set(rt_y["시"]) & set(rt_w["시"]))
        if len(hrs) >= 12:
            ya = rt_y[rt_y["시"].isin(hrs)].groupby("장소")["인구"].mean()
            wa = rt_w[rt_w["시"].isin(hrs)].groupby("장소")["인구"].mean()
            both = pd.concat([ya, wa], axis=1, keys=["어제", "전주"]).dropna()
            both = both[both["전주"] >= 2000]
            both["배"] = both["어제"] / both["전주"]
            top = both.sort_values("배", ascending=False).iloc[0]
            if top["배"] >= 1.2:
                T.append({"유형": "장소급증", "점수": min(85, (top["배"] - 1) * 120),
                          "제목": f"어제 평소보다 사람이 {top['배']:.1f}배 몰린 서울 장소는 {top.name}",
                          "근거": f"{top.name} 하루 평균 {round(top['어제']):,}명 (1주 전 같은 요일 {round(top['전주']):,}명, 공통 {len(hrs)}시간 비교)",
                          "값": {"장소": top.name, "배율": round(float(top["배"]), 3), "시간수": len(hrs)}})
        # 5) 실시간: 어제 20대 비율 1위 장소 (사람 3,000명 이상)
        big = rt_y.groupby("장소").agg(인구=("인구", "mean"), 이십대=("20대", "mean"))
        big = big[big["인구"] >= 3000].sort_values("이십대", ascending=False)
        if len(big):
            T.append({"유형": "20대장소", "점수": 35, "제목": f"어제 20대 비율이 가장 높았던 서울 장소는 {big.index[0]}",
                      "근거": f"{big.index[0]} 20대 {big.iloc[0]['이십대']:.1f}% (2위 {big.index[1]} {big.iloc[1]['이십대']:.1f}%)",
                      "값": {"장소": big.index[0], "비율": round(float(big.iloc[0]["이십대"]), 2)}})

    # 6) 환율: 1개월 변화가 가장 큰 통화
    if X:
        n, v = max(X["값"].items(), key=lambda kv: abs(kv[1]["1개월"]))
        mv = v["1개월"]
        if abs(mv) >= 1:
            T.append({"유형": "환율", "점수": min(75, abs(mv) * 20),
                      "제목": f"{FX[n][1]} 한 달 새 {abs(mv):.1f}% {'상승' if mv > 0 else '하락'}, {n} 여행 {'비싸졌다' if mv > 0 else '싸졌다'}?",
                      "근거": f"원/{FX[n][1]} {v['현재']:,.2f} ({X['1개월전']} 대비 {mv:+.1f}%)", "값": {"나라": n, "1개월": round(mv, 3)}})

    # 7) 하늘길 vs 머무는 인원 (숫자의 함정)
    if fl:
        topf = max(fl, key=fl.get)
        r7 = {c: c7[c].mean() for c in FOCUS}
        vr = sorted(FOCUS, key=lambda c: -r7[c]).index(topf) + 1
        if vr >= 3:
            T.append({"유형": "하늘길함정", "점수": 60,
                      "제목": f"비행기는 {j(topf, '이가')} 1위인데 서울에 머무는 {topf}인은 {vr}위? 숫자의 함정",
                      "근거": f"어제 {topf} 노선 {fl[topf]}편(5개국 중 1위) · {topf}인 7일 평균 {round(r7[topf]):,}명({vr}위). ※ 생활인구는 '머무는 인원'이라 짧게 머물면 적게 잡힘",
                      "값": {"나라": topf, "편수": fl[topf], "순위": vr}})
    return T


def main():
    ref = date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else date.today()
    yday = ref - timedelta(days=1)
    tag = ref.strftime("%y%m%d")

    s = foreigner(yday)
    if s is None:
        print(f"데이터 없음: {yday} 이전 외국인 데이터 14일 미만"); sys.exit(2)
    L = s.iloc[-1]["날짜"]
    nat_all = [c for c in s.columns if c not in ("날짜", "합계", "기타")]
    dist = district_avg(L)
    rt_y, rt_w = realtime(yday), realtime(yday - timedelta(days=7))
    fl, X = flights(yday), exchange(ref)

    # ① 5개국 추이
    last14 = s.iloc[-14:]
    trend = []
    for c in FOCUS:
        a, b = s[c].iloc[-7:].mean(), s[c].iloc[-14:-7].mean()
        trend.append({"국적": c, "최신일": int(s[c].iloc[-1]), "7일평균": round(a), "변화": pct(a, b), "흐름": spark(last14[c].tolist())})

    # ④ 자치구별 방문자 추이 랭킹 (최근 14일)
    dt = district_trend(s["날짜"].iloc[-14:].tolist())
    gu_rank = district_rank(dt) if dt is not None and len(dt) == 14 else None

    # ③ 쇼츠 주제 (최근 3일 유형 제외)
    recent = set()
    if HISTORY.exists():
        for r in csv.DictReader(open(HISTORY, encoding="utf-8-sig")):
            if str(ref - timedelta(days=3)) <= r["기준일"] < str(ref):
                recent.add(r["유형"])
    cands = sorted(topics(s, dist, rt_y, rt_w, fl, X, nat_all), key=lambda t: -t["점수"])
    pick = [t for t in cands if t["유형"] not in recent][:3]
    if len(pick) < 3:
        pick += [t for t in cands if t not in pick][: 3 - len(pick)]

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
    if rt_y is None:
        issues.append(f"실시간 {yday} 없음")
    else:
        miss = 24 - rt_y["시"].nunique()
        if miss:
            issues.append(f"실시간 {md_(str(yday))} {miss}시간 수집 누락")
    if fl is None:
        issues.append(f"항공 {yday} 없음")
    if X is None:
        issues.append("환율 없음")
    status = "✅ 이상 없음" if not issues else "⚠️ " + " / ".join(issues)

    # ── 출력 ──
    title = f"서울 외국인 데일리 ({md_(L)} 기준)"
    src = "서울시 단기체류 외국인 생활인구 · 서울시 실시간 도시데이터 · 한국수출입은행 환율 · 인천/한국공항공사 운항정보"
    footer = f"출처: {src} · 발송 기준일 {ref} · 방문자 {s['날짜'].iloc[-14]}~{L} · 환율 {X['고시일'] if X else '-'} · 실시간·항공 {yday}"
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
    topic_txt = "\n\n".join(f"*{i}. {t['제목']}*\n└ {t['근거']}" for i, t in enumerate(pick, 1))

    md = [f"# {title}", "", f"## ① 방문자 추이 (최근 14일 · {md_(s['날짜'].iloc[-14])}~{md_(L)})", "```", trend_txt, "```",
          "", f"## ② 자치구별 방문자 랭킹 TOP10 (7일 평균, 이전 7일 대비 · 순위 변동 · 14일 흐름)", "```", gu_txt, "```", gu_up,
          "", f"## ③ 환율 ({X['고시일'] if X else '-'} 고시)", "```", fx_txt, "```", "", "## ④ 오늘의 쇼츠 주제", topic_txt.replace("*", "**"),
          "", f"데이터 품질: {status}", "", footer, ""]
    OUT.mkdir(exist_ok=True)
    (OUT / f"{tag}_서울브리핑.md").write_text("\n".join(md), encoding="utf-8")
    blocks = [
        {"type": "header", "text": {"type": "plain_text", "text": f"🌏 {title}"}},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*① 방문자 추이* (최근 14일, 서울에 머무는 인원)\n```{trend_txt}```"}},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*② 자치구별 방문자 랭킹 TOP10* (7일 평균 · 이전 7일 대비 · 순위 변동 · 14일 흐름)\n```{gu_txt}```\n{gu_up}"}},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*③ 환율* ({X['고시일'] if X else '-'} 고시, 원화 기준)\n```{fx_txt}```"}},
        {"type": "divider"},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*🎬 ④ 오늘의 쇼츠 주제*\n\n{topic_txt}\n\n👉 만들 주제를 *이 메시지 스레드에 번호로 답글*(예: `2`)로 남기면, 5분 안에 Claude가 제작을 시작해서 숫자 검증을 통과하면 DM으로 보내요."}},
        {"type": "context", "elements": [{"type": "mrkdwn", "text": f"데이터 품질 {status}\n{footer}"}]},
    ]
    (OUT / f"{tag}_slack.json").write_text(json.dumps({"blocks": blocks}, ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT / f"{tag}_지표.json").write_text(json.dumps({"기준일": str(ref), "최신일": L, "추이": trend, "자치구랭킹": gu_rank, "환율": X, "항공": fl,
                                                      "쇼츠주제": pick, "후보수": len(cands), "품질": issues}, ensure_ascii=False, indent=1, default=float), encoding="utf-8")
    print("\n".join(md))


def record_topics(ref: str):
    """게시에 성공한 날만 주제 기록 (run_brief.py가 호출)"""
    J = json.loads((OUT / f"{date.fromisoformat(ref):%y%m%d}_지표.json").read_text(encoding="utf-8"))
    new = not HISTORY.exists()
    if not new and any(r["기준일"] == ref for r in csv.DictReader(open(HISTORY, encoding="utf-8-sig"))):
        return  # 같은 날 다시 보낸 경우 중복 기록 안 함
    with open(HISTORY, "a", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["기준일", "유형", "제목"])
        for t in J["쇼츠주제"]:
            w.writerow([ref, t["유형"], t["제목"]])


if __name__ == "__main__":
    main()
