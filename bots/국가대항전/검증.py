"""국가대항전 숫자 검증 (number-checker): 집계.py(pandas)와 다른 방법(csv 모듈로 한 줄씩)으로 다시 계산해 대조.
쇼츠 대본에 들어간 숫자까지 확인한다 (영상으로 틀린 숫자가 나가지 않게).
사용: python -X utf8 검증.py <발송일>     마지막 줄: "통과" 또는 "보류: 이유" (종료코드 0/1)
"""
import csv
import json
import sys
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
CFG = json.loads((HERE / "설정.json").read_text(encoding="utf-8"))
SRC = (HERE / CFG["데이터저장소"]).resolve() / CFG["데이터파일"]  # 절대 경로면 그대로


def num(x):
    return float(x) if x not in ("", None) else 0.0


def main():
    ref = date.fromisoformat(sys.argv[1])
    tag = ref.strftime("%y%m%d")
    try:
        J = json.loads((HERE / "리포트" / f"{tag}_지표.json").read_text(encoding="utf-8"))
        S = (HERE / "리포트" / f"{tag}_slack.json").read_text(encoding="utf-8")
    except FileNotFoundError as e:
        print(f"보류: 결과 파일 없음 ({Path(e.filename).name})"); sys.exit(1)
    P = []
    with open(SRC, encoding="utf-8-sig", newline="") as f:
        rows = sorted((r for r in csv.DictReader(f) if r["날짜"] <= str(ref - timedelta(days=CFG["공개지연일"]))), key=lambda r: r["날짜"])
    last14 = rows[-14:]
    cw, pw = last14[7:], last14[:7]
    nat = [k for k in rows[0] if k not in ("날짜", "합계", "기타")]
    cur = {k: sum(num(r[k]) for r in cw) / 7 for k in nat}
    prv = {k: sum(num(r[k]) for r in pw) / 7 for k in nat}
    if J["최신일"] != cw[-1]["날짜"] or J["이번주"][0] != cw[0]["날짜"]:
        P.append(f"기간 {J['이번주']} vs {cw[0]['날짜']}~{cw[-1]['날짜']}")

    order = sorted(nat, key=lambda k: -cur[k])
    order_p = sorted(nat, key=lambda k: -prv[k])
    if [r["국적"] for r in J["TOP5"]] != order[:5]:
        P.append(f"TOP5 순서 {[r['국적'] for r in J['TOP5']]} vs {order[:5]}")
    wins = {}
    for r in cw:
        w = max(nat, key=lambda k: num(r[k])); wins[w] = wins.get(w, 0) + 1
    for r in J["TOP5"]:
        k = r["국적"]
        ch = (cur[k] - prv[k]) / prv[k] * 100
        if (r["이번주"], r["지난주"]) != (round(cur[k]), round(prv[k])) or abs(ch - r["변화"]) > 0.01 \
                or r["지난주순위"] != order_p.index(k) + 1 or r["1위일수"] != wins.get(k, 0):
            P.append(f"{k} {r['이번주']}/{r['지난주']}/{r['변화']}/{r['1위일수']}일 vs {round(cur[k])}/{round(prv[k])}/{ch:.2f}/{wins.get(k, 0)}일")
    gap = cur[order[0]] - cur[order[1]]
    if J["격차"] != round(gap):
        P.append(f"격차 {J['격차']} vs {round(gap)}")
    if (J["1위"] != order_p[0]) != J["뒤집힘"]:
        P.append("뒤집힘 판정 오류")

    # 대본·화면 글자에 들어간 숫자가 재계산과 같은지
    sh = J["쇼츠"]
    script = " ".join(" ".join(v) for v in sh["대본"].values())
    must = [f"{abs(gap):,.0f}명", f"{round(cur[order[4]]):,}명", f"{round(cur[order[2]]):,}명"]
    for m in must:
        if m not in script:
            P.append(f"대본에 '{m}' 없음")
    if sh["표지큰글씨"] != f"{abs(gap):,.0f}명":
        P.append("표지 숫자 불일치")
    for b, k in zip(sh["배지"], order[:5]):
        if b != f"{(cur[k] - prv[k]) / prv[k] * 100:+.1f}%":
            P.append(f"{k} 배지 {b}")
    for k in order[:5]:
        if k not in script:
            P.append(f"대본에 {k} 없음")
    if "{" in script or "(가)" in script or "(이)" in script:
        P.append("자리표시자/조사 미처리")
    try:
        json.loads(S)
    except ValueError:
        P.append("slack json 형식 오류")
    if "출처" not in S or str(ref) not in S:
        P.append("출처·발송일 없음")

    print("통과" if not P else "보류: " + " / ".join(P))
    sys.exit(0 if not P else 1)


if __name__ == "__main__":
    main()
