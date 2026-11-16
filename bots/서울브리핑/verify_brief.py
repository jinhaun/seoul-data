"""서울 외국인 데일리 숫자 검증 (number-checker): brief.py(pandas)와 다른 방법(csv 모듈로 한 줄씩)으로 다시 계산해 대조한다.
대상: 5개국 추이·자치구 순위·환율·숙박 신규·변경·삭제·업소 예시 + 출력 형식
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
from brief import FX  # 코드 목록·열 이름만 공유 (계산은 따로)


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
    lodging_sections = [text for text in sections if text.startswith("*🏨 ④ 서울 숙박업소 변화*")]
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
