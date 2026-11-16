"""서울 외국인 데일리 숫자 검증 (number-checker): brief.py(pandas)와 다른 방법(csv 모듈로 한 줄씩)으로 다시 계산해 대조한다.
대상: ① 5개국 추이 ② 환율 ③ 쇼츠 주제 근거 숫자(유형별 재계산) ④ 숙박 신규·변경·삭제·업소 예시 + 출력 형식
사용: python -X utf8 verify_brief.py <기준일>      마지막 줄: "통과" 또는 "보류: 이유" (종료코드 0/1)
"""
import os
import csv
import json
import re
import sys
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = Path(os.environ.get("SEOUL_DATA_DIR") or Path(__file__).resolve().parents[2] / "data")  # 저장소의 data 폴더
sys.path.insert(0, str(HERE))
from brief import AIRPORTS, FX  # 코드 목록·열 이름만 공유 (계산은 따로)


def rows(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        yield from csv.DictReader(f)


def num(x):
    return float(x) if x not in ("", None) else 0.0


def close(a, b, tol=0.05):
    return a is not None and b is not None and abs(a - b) <= tol


def verify_lodging(ref, report, md, slack_json):
    """변경 원문을 csv 행별로 다시 세고, 수집 기록·지표·표시 문구를 독립 대조한다."""
    problems = []
    source = DATA / "status" / "숙박기록.csv"
    logs = list(rows(source)) if source.exists() else []
    expected = {"기준일": str(ref), "종류": []}
    required_lines = []
    for kind in ("호텔", "외국인민박", "숙박업"):
        entry = None
        for row in logs:
            if row["날짜"] == str(ref) and row["종류"] == kind:
                entry = row
        item = {"종류": kind, "상태": "오늘 자료 없음", "건수": None, "신규업소": []}
        if entry is None:
            required_lines.append(f"• {kind}: 오늘 자료 없음")
        else:
            counts = {"신규": 0, "변경": 0, "삭제": 0}
            path = DATA / "lodging" / "changes" / str(ref)[:7] / f"{ref}_{kind}.csv"
            if path.exists():
                for row in rows(path):
                    category = row["구분"]
                    if category not in counts:
                        problems.append(f"숙박 {kind}: 원문 구분 오류")
                        continue
                    counts[category] += 1
                    if category == "신규" and len(item["신규업소"]) < 2:
                        item["신규업소"].append({"업소명": row["업소명"], "자치구": row["자치구"]})
            if any(counts[k] != int(entry[k]) for k in counts):
                problems.append(f"숙박 {kind}: 수집 기록·원문 건수 불일치")
            item["건수"] = counts
            item["상태"] = "변경 있음" if sum(counts.values()) else "변화 없음"
            if sum(counts.values()):
                required_lines.append(f"• {kind}: 신규 {counts['신규']:,} · 변경 {counts['변경']:,} · 삭제 {counts['삭제']:,}건")
            else:
                required_lines.append(f"• {kind}: 변화 없음")
            for example in item["신규업소"]:
                # 표시 문자열만 정규화한다. 숫자·업소 선택은 위 원문에서 따로 확인했다.
                name = " ".join(example["업소명"].split()).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;") or "업소명 미상"
                gu = " ".join(example["자치구"].split()).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;") or "자치구 미상"
                required_lines.append(f"{name}({gu})")
        expected["종류"].append(item)
    if report != expected:
        problems.append("숙박 지표·신규 업소가 원문과 다름")
    payload = json.loads(slack_json)
    sections = [b.get("text", {}).get("text", "") for b in payload.get("blocks", []) if b.get("type") == "section"]
    lodging_sections = [text for text in sections if text.startswith("*🏨 ⑤ 서울 숙박업소 변화*")]
    if len(lodging_sections) != 1:
        problems.append("슬랙 숙박 항목 없음 또는 중복")
    else:
        for text in required_lines:
            if text not in lodging_sections[0] or text not in md:
                problems.append("숙박 표시 누락·불일치: " + text)
        if f"({ref} 수집)" not in lodging_sections[0] or "직전 수집 목록 대비" not in lodging_sections[0]:
            problems.append("숙박 기준일·목록 비교 안내 없음")
    return problems


def main():
    ref = date.fromisoformat(sys.argv[1])
    yday = ref - timedelta(days=1)
    tag = ref.strftime("%y%m%d")
    P = []
    try:
        J = json.loads((HERE / "리포트" / f"{tag}_지표.json").read_text(encoding="utf-8"))
        S = (HERE / "리포트" / f"{tag}_slack.json").read_text(encoding="utf-8")
        md = (HERE / "리포트" / f"{tag}_서울브리핑.md").read_text(encoding="utf-8")
    except FileNotFoundError as e:
        print(f"보류: 결과 파일 없음 ({Path(e.filename).name})"); sys.exit(1)

    # ① 방문자 추이
    allr = sorted((r for r in rows(DATA / "foreigner" / "일별요약_단기.csv") if r["날짜"] <= str(yday)), key=lambda r: r["날짜"])
    L = allr[-1]["날짜"]
    if L != J["최신일"]:
        P.append(f"최신일 {J['최신일']} vs {L}")
    c7, p7 = allr[-7:], allr[-14:-7]
    for t in J["추이"]:
        k = t["국적"]
        a = sum(num(r[k]) for r in c7) / 7
        b = sum(num(r[k]) for r in p7) / 7
        if int(num(allr[-1][k])) != t["최신일"] or round(a) != t["7일평균"] or not close((a - b) / b * 100, t["변화"]):
            P.append(f"{k} 추이 {t['최신일']}/{t['7일평균']}/{t['변화']:+.1f}% vs {int(num(allr[-1][k]))}/{round(a)}/{(a - b) / b * 100:+.1f}%")

    # ①-2 자치구별 방문자 랭킹 (14일 파일을 한 줄씩 합산)
    G = J.get("자치구랭킹")
    if G:
        days = [r["날짜"] for r in allr[-14:]]
        daily = []
        for d in days:
            s = defaultdict(float)
            for r in rows(DATA / "foreigner" / "단기" / d[:7] / f"{d}.csv"):
                s[r["자치구"]] += num(r["생활인구합계"])
            daily.append({k: v / 24 for k, v in s.items()})
        gus = daily[0].keys()
        cur = {g: sum(x[g] for x in daily[-7:]) / 7 for g in gus}
        prv = {g: sum(x[g] for x in daily[:7]) / 7 for g in gus}
        order_c = sorted(gus, key=lambda g: -cur[g])
        order_p = sorted(gus, key=lambda g: -prv[g])
        if [r["자치구"] for r in G] != order_c:
            P.append("자치구 순위 불일치")
        for r in G:
            g = r["자치구"]
            mv = (order_p.index(g) + 1) - (order_c.index(g) + 1)
            if round(cur[g]) != r["7일평균"] or not close((cur[g] - prv[g]) / prv[g] * 100, r["변화"]) or mv != r["순위변동"]:
                P.append(f"자치구 {g} {r['7일평균']}/{r['변화']:+.1f}%/{r['순위변동']} vs {round(cur[g])}/{(cur[g] - prv[g]) / prv[g] * 100:+.1f}%/{mv}")
        for r in G[:10]:
            if f"{r['7일평균']:,}명" not in md:
                P.append(f"md에 {r['자치구']} 숫자 없음")

    # ② 환율
    X = J["환율"]
    if X:
        g = [r for r in rows(DATA / "exchange" / "환율_일별.csv") if r["고시여부"] == "Y" and r["날짜"] <= str(ref)]
        cur = g[-1]
        cd = date.fromisoformat(cur["날짜"])
        w = [r for r in g if r["날짜"] <= str(cd - timedelta(days=7))][-1]
        m = [r for r in g if r["날짜"] <= str(cd - timedelta(days=30))][-1]
        for n, v in X["값"].items():
            col = FX[n][0]
            c0, w0, m0 = num(cur[col]), num(w[col]), num(m[col])
            if c0 != v["현재"] or not close((c0 - w0) / w0 * 100, v["1주"], 0.01) or not close((c0 - m0) / m0 * 100, v["1개월"], 0.01):
                P.append(f"환율 {n} 불일치")

    # ③ 쇼츠 주제 근거 재계산
    nat = [k for k in allr[0] if k not in ("날짜", "합계", "기타")]
    for t in J["쇼츠주제"]:
        v, ty = t["값"], t["유형"]
        if ty == "1위다툼":
            lead = [max(nat, key=lambda k: num(r[k])) for r in allr]
            cnt = defaultdict(int)
            for x in lead[-7:]:
                cnt[x] += 1
            rank = sorted(nat, key=lambda k: -num(allr[-1][k]))
            if dict(cnt) != v["최근7일"] or rank[:2] != [v["1위"], v["2위"]]:
                P.append(f"[1위다툼] {v} vs 7일 {dict(cnt)} 순위 {rank[:2]}")
        elif ty == "급증국적":
            k = v["국적"]
            a = sum(num(r[k]) for r in c7) / 7; b = sum(num(r[k]) for r in p7) / 7
            best = max((x for x in nat if sum(num(r[x]) for r in p7) / 7 >= 1000),
                       key=lambda x: (sum(num(r[x]) for r in c7) - sum(num(r[x]) for r in p7)) / sum(num(r[x]) for r in p7))
            if best != k or not close((a - b) / b * 100, v["변화"], 0.01):
                P.append(f"[급증국적] {k} {v['변화']} vs {best} {(a - b) / b * 100:.2f}")
        elif ty == "자치구특이":
            tot, by = defaultdict(float), defaultdict(lambda: defaultdict(float))
            for r in rows(DATA / "foreigner" / "단기" / L[:7] / f"{L}.csv"):
                tot[r["자치구"]] += num(r["생활인구합계"]); by[r["자치구"]][v["국적"]] += num(r[v["국적"]])
            city = sum(by[g][v["국적"]] for g in by) / sum(tot.values())
            gu = v["자치구"]
            ratio = (by[gu][v["국적"]] / tot[gu]) / city
            if not close(ratio, v["배율"], 0.01):
                P.append(f"[자치구특이] {gu} {v['국적']} 배율 {v['배율']} vs {ratio:.2f}")
        elif ty == "장소급증":
            def day_avg(d, hrs=None):
                s, n = defaultdict(float), defaultdict(int)
                seen = set()
                for r in rows(DATA / "realtime" / f"{d:%Y-%m}" / f"{d}.csv"):
                    tm = r["인구기준시각"]
                    if not tm.startswith(str(d)) or (tm, r["장소"]) in seen or not r["인구_최소"] or not r["인구_최대"]:
                        continue
                    seen.add((tm, r["장소"]))
                    if hrs is not None and int(tm[11:13]) not in hrs:
                        continue
                    s[(r["장소"], int(tm[11:13]))] += 0
                    s[r["장소"]] += (num(r["인구_최소"]) + num(r["인구_최대"])) / 2; n[r["장소"]] += 1
                return s, n
            hy = {int(r["인구기준시각"][11:13]) for r in rows(DATA / "realtime" / f"{yday:%Y-%m}" / f"{yday}.csv") if r["인구기준시각"].startswith(str(yday))}
            w_ = yday - timedelta(days=7)
            hw = {int(r["인구기준시각"][11:13]) for r in rows(DATA / "realtime" / f"{w_:%Y-%m}" / f"{w_}.csv") if r["인구기준시각"].startswith(str(w_))}
            hrs = hy & hw
            sy, ny = day_avg(yday, hrs); sw, nw = day_avg(w_, hrs)
            pl = v["장소"]
            ratio = (sy[pl] / ny[pl]) / (sw[pl] / nw[pl])
            if not close(ratio, v["배율"], 0.001) or len(hrs) != v["시간수"]:
                P.append(f"[장소급증] {pl} {v['배율']} vs {ratio:.3f}")
        elif ty == "환율" and X:
            if not close(X["값"][v["나라"]]["1개월"], v["1개월"], 0.01):
                P.append("[환율] 주제 숫자 불일치")
            want = "상승" if v["1개월"] > 0 else "하락"
            if want not in t["제목"]:
                P.append("[환율] 상승/하락 표현 오류")
        elif ty == "하늘길함정":
            seen, cnt = set(), 0
            for r in rows(DATA / "flights" / f"{yday:%Y-%m}" / f"{yday}.csv"):
                k = (r["공항"], r["구분"], r["편명"], r["예정시각"])
                if r["국내국제"] == "국제" and not r["마스터편명"] and k not in seen and r["상대공항코드"] in AIRPORTS[v["나라"]]:
                    seen.add(k); cnt += 1
            if cnt != v["편수"]:
                P.append(f"[하늘길함정] {v['나라']} {v['편수']}편 vs {cnt}편")
        # 근거 문장에 쓴 숫자가 제목·근거에 그대로 있는지 (지어낸 숫자 방지는 위 재계산으로)
    if len(J["쇼츠주제"]) != 3:
        P.append(f"쇼츠 주제 {len(J['쇼츠주제'])}개 (3개 아님)")

    # ④ 숙박 원문과 표시를 별도 재계산
    try:
        P.extend(verify_lodging(ref, J.get("숙박"), md, S))
    except (ValueError, KeyError, OSError) as e:
        P.append(f"숙박 검증 실패: {e}")

    # 출력 형식
    try:
        json.loads(S)
    except ValueError:
        P.append("slack json 형식 오류")
    if re.search(r"\{[가-힣]+\}", S) or "(가)" in S or "(과)" in S:
        P.append("자리표시자/조사 미처리")
    if "출처" not in S or str(ref) not in S:
        P.append("출처·기준일 없음")
    for t in J["추이"]:
        if f"{t['최신일']:,}명" not in md:
            P.append(f"md에 {t['국적']} 숫자 없음")

    print("통과" if not P else "보류: " + " / ".join(P))
    sys.exit(0 if not P else 1)


if __name__ == "__main__":
    main()
