"""서울 외국인 국가대항전 — 주간 집계 + 쇼츠 대본 + Slack 카드 생성.
최근 공개된 7일 vs 그 전 7일, 국적별 하루 평균 단기체류 생활인구 TOP5.
사용: python -X utf8 집계.py [발송일]      출력: 리포트/<yymmdd>_지표.json, _slack.json
종료코드 0 정상 / 2 데이터 부족
"""
import json
import random
import sys
from datetime import date, timedelta
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
CFG = json.loads((HERE / "설정.json").read_text(encoding="utf-8"))
SRC = (HERE / CFG["데이터저장소"]).resolve() / CFG["데이터파일"]  # 절대 경로면 그대로
OUT = HERE / "리포트"
LAG = CFG["공개지연일"]  # 데이터 공개 지연(일). 검증.py도 같은 설정을 읽음
WEEK = "월화수목금토일"
FLAG = {"중국": "🇨🇳", "태국": "🇹🇭", "미국": "🇺🇸", "일본": "🇯🇵", "베트남": "🇻🇳", "몽골": "🇲🇳", "캐나다": "🇨🇦",
        "러시아": "🇷🇺", "프랑스": "🇫🇷", "필리핀": "🇵🇭", "카자흐스탄": "🇰🇿", "인도네시아": "🇮🇩", "인도": "🇮🇳"}


def md_(d):
    return f"{d.month}/{d.day}"


def j(word, pair):  # 받침에 맞는 조사: j("태국", "이가") → 태국이
    last = word[-1]
    has = "가" <= last <= "힣" and (ord(last) - 0xAC00) % 28 > 0
    return word + (pair[0] if has else pair[1])


def yo(word):  # 몽골 → 몽골이에요, 태국 → 태국이에요, 미국 → 미국이에요, 캐나다 → 캐나다예요
    last = word[-1]
    has = "가" <= last <= "힣" and (ord(last) - 0xAC00) % 28 > 0
    return word + ("이에요" if has else "예요")


def main():
    ref = date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else date.today()
    tag = ref.strftime("%y%m%d")
    df = pd.read_csv(SRC, encoding="utf-8-sig", parse_dates=["날짜"])
    # 서울시 공개가 4~5일 늦으므로 "발송일 5일 전까지"로 고정 → 나중에 다시 돌려도 같은 결과
    cutoff = ref - timedelta(days=LAG)
    df = df[df["날짜"].dt.date <= cutoff].sort_values("날짜")
    nat = [c for c in df.columns if c not in ("날짜", "합계", "기타")]
    df[nat] = df[nat].apply(pd.to_numeric, errors="coerce").fillna(0)
    if len(df) < 14:
        print("데이터 부족: 14일 미만"); sys.exit(2)
    last14 = df.tail(14)
    L = last14["날짜"].iloc[-1].date()
    if (L - last14["날짜"].iloc[0].date()).days != 13:
        print("데이터 부족: 최근 14일 중 빠진 날이 있어요"); sys.exit(2)
    cw, pw = last14.tail(7), last14.head(7)
    cur, prv = cw[nat].mean(), pw[nat].mean()
    rank_c = cur.rank(ascending=False, method="first").astype(int)
    rank_p = prv.rank(ascending=False, method="first").astype(int)
    top = cur.sort_values(ascending=False).head(5).index.tolist()
    wins = cw[nat].idxmax(axis=1).value_counts().to_dict()     # 이번 주 날짜별 1위 횟수
    champ, prev_champ = top[0], prv.idxmax()
    flipped = champ != prev_champ
    gap = cur[top[0]] - cur[top[1]]
    riser = max(nat, key=lambda k: (cur[k] - prv[k]) / prv[k] if prv[k] >= 1000 else -9)

    rows = []
    for k in top:
        ch = (cur[k] - prv[k]) / prv[k] * 100
        mv = int(rank_p[k] - rank_c[k])
        rows.append({"국적": k, "이번주": round(cur[k]), "지난주": round(prv[k]), "변화": round(ch, 4),
                     "순위": int(rank_c[k]), "지난주순위": int(rank_p[k]), "순위변동": mv, "1위일수": int(wins.get(k, 0))})

    def badge(r):  # 반올림은 원래 값에서 한 번만 (-6.4475 → -6.45 → -6.5 같은 이중 반올림 방지)
        k = r["국적"]
        return f"{(cur[k] - prv[k]) / prv[k] * 100:+.1f}%"

    def sub(r):
        if r["순위변동"] > 0:
            return f"지난주 {r['지난주순위']}위 → {r['순위']}위로 상승"
        if r["순위변동"] < 0:
            return f"지난주 {r['지난주순위']}위 → {r['순위']}위로 하락"
        return f"지난주에 이어 {r['순위']}위 유지"

    R = {r["국적"]: r for r in rows}
    c1, c2 = top[0], top[1]
    if flipped:
        hook = f"서울을 점령한 외국인 1위, 이번 주 뒤집혔습니다"
        cover = ["서울 외국인", "국가대항전", "1위가 뒤집혔다"]
        hi = "뒤집혔다"
        verdict = f"지난주 1위 {j(prev_champ, '을를')} 꺾고 {j(c1, '이가')} 1위"
    else:
        hook = f"서울을 점령한 외국인 1위, 이번 주도 {j(c1, '이가')} 지켜냈을까요?"
        cover = ["서울 외국인", "국가대항전", "이번 주 1위는?"]
        hi = "1위"
        verdict = f"{j(c1, '이가')} 1위를 지켰어요"
    # 말하듯 쓰는 대본: 표현 후보 중 하나를 고른다 (같은 발송일이면 항상 같은 선택 → 다시 돌려도 같음)
    rnd = random.Random(tag)
    pick = rnd.choice
    n5, n4, n3 = top[4], top[3], top[2]
    v5, v3 = f"{R[n5]['이번주']:,}명", f"{R[n3]['이번주']:,}명"
    g = f"{abs(gap):,.0f}명"
    ch4 = R[n4]["변화"]
    move4 = f"지난주보다 {abs(ch4):.1f}% {'늘었어요' if ch4 > 0 else '줄었어요'}" if abs(ch4) >= 0.5 else "지난주랑 거의 똑같아요"
    close_race = abs(gap) < 1000
    lines = {
        "cover": [hook if flipped else pick([f"지금 서울에 제일 많이 와 있는 외국인, 어느 나라일까요?",
                                             f"서울에 머무는 외국인 1등 나라, 맞혀 보실래요?"]),
                  (f"이번 주는 1등이랑 2등 차이가 고작 {g}이에요." if close_race else "이번 주 순위, 5위부터 바로 갈게요.")],
        "r5": [pick([f"5위는 의외로 {yo(n5)}.", f"5위부터 갈게요. {n5}!"]),
               pick([f"하루에 {v5} 정도 서울에 있었어요.", f"하루 평균 {v5}이 서울에 있었어요."])],
        "r4": [pick([f"4위는 {yo(n4)}.", f"그다음 4위, {n4}."]), move4 + "."],
        "r3": [pick([f"3위는 {n3}!", f"동메달은 {n3}!"]), pick([f"하루 평균 {v3}이에요.", f"하루에 {v3}이나 있었어요."])],
        "r2": [f"2위는 {yo(c2)}.",
               (pick([f"근데 1위랑 차이가 진짜 {g}밖에 안 나요.", f"1위랑 딱 {g} 차이예요. 거의 동점이죠."])
                if close_race else f"1위와는 {g} 차이예요.")],
        "r1": [pick([f"그리고 1위는... {c1}!", f"대망의 1위, {c1}!"]),
               (f"날짜로 따지면 {j(c2, '이가')} {R[c2]['1위일수']}일이나 이겼는데, 평균으로는 {j(c1, '이가')} 살짝 앞섰어요."
                if R[c2]["1위일수"] > R[c1]["1위일수"] else f"이번 주 7일 중 {R[c1]['1위일수']}일을 1위로 버텼어요.")],
        "summary": [f"다음 주엔 {j(c2, '이가')} 뒤집을 수 있을까요?", pick(["댓글로 예상 남겨 주세요!", "여러분 예상은요? 댓글로 알려 주세요!"])],
    }
    period = f"{md_(cw['날짜'].iloc[0].date())}~{md_(L)}"
    J = {
        "발송일": str(ref), "최신일": str(L), "이번주": [str(cw['날짜'].iloc[0].date()), str(L)],
        "지난주": [str(pw['날짜'].iloc[0].date()), str(pw['날짜'].iloc[-1].date())],
        "TOP5": rows, "1위": c1, "지난주1위": prev_champ, "뒤집힘": bool(flipped), "격차": round(gap),
        "급상승": {"국적": riser, "변화": round((cur[riser] - prv[riser]) / prv[riser] * 100, 4)},
        "쇼츠": {"표지": cover, "표지강조": hi, "표지윗줄": "1·2위 격차", "표지큰글씨": f"{abs(gap):,.0f}명",
                 "배지": [badge(r) for r in rows], "카드설명": [sub(r) for r in rows],
                 "대본": lines, "요약제목": "이번 주 TOP5",
                 "출처": f"자료: 서울시 단기체류 외국인 생활인구 · {period} 하루 평균"},
        "결론": verdict, "기간": period,
    }

    # Slack 카드
    top_txt = "\n".join(
        f"{r['순위']}위 {FLAG.get(r['국적'], '')} {r['국적']} {r['이번주']:,}명 ({r['변화']:+.1f}%)"
        + (f" ⬆{r['순위변동']}" if r["순위변동"] > 0 else (f" ⬇{-r['순위변동']}" if r["순위변동"] < 0 else ""))
        for r in rows)
    blocks = [
        {"type": "header", "text": {"type": "plain_text", "text": f"🏆 서울 외국인 국가대항전 ({period})"}},
        {"type": "section", "text": {"type": "mrkdwn", "text":
            f"*{verdict}* · 1·2위 격차 *{abs(gap):,.0f}명*\n이번 주 날짜별 1위: "
            + ", ".join(f"{k} {v}일" for k, v in sorted(wins.items(), key=lambda x: -x[1]))
            + f"\n급상승: {riser} {J['급상승']['변화']:+.1f}%"}},
        {"type": "section", "text": {"type": "mrkdwn", "text": f"```{top_txt}```"}},
        {"type": "section", "text": {"type": "mrkdwn", "text": "*🎬 쇼츠 대본 (자동 생성)*\n" + "\n".join(f"• {' '.join(v)}" for v in lines.values())}},
        {"type": "context", "elements": [{"type": "mrkdwn", "text":
            f"비교: 최근 공개된 7일 vs 그 전 7일 (하루 평균, 서울시 공개 4~5일 지연) · 생활인구 = 그 시각 서울에 머무는 인원 · "
            f"숫자 검증 통과 후 게시 · 출처: 서울시 단기체류 외국인 생활인구 · 발송 {ref}"}]},
    ]
    OUT.mkdir(exist_ok=True)
    (OUT / f"{tag}_지표.json").write_text(json.dumps(J, ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT / f"{tag}_slack.json").write_text(json.dumps({"blocks": blocks}, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"완료: {verdict} ({period})")


if __name__ == "__main__":
    main()
