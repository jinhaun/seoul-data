"""Slack 게시: python -X utf8 post_slack.py <json 파일> <test|alert|data> [--files 파일1 파일2 ...]
json 파일 대신 "--text 메시지"를 주면 단순 텍스트로 게시한다 (보류·데이터 없음 알림용).

주소(Webhook)는 환경변수에서 읽고 화면에 출력하지 않는다.
 - GitHub: 저장소 설정 → Secrets 의 SLACK_WEBHOOK_ALERT / SLACK_WEBHOOK_TEST / SLACK_WEBHOOK_DATA
 - 내 컴퓨터에서 시험할 때: 이 폴더의 .env 파일 (저장소에 올라가지 않음)
SLACK_DRY_RUN=1 이면 실제로 보내지 않고 "보낼 내용 확인"만 한다.
SLACK_WEBHOOK_DATA 가 없으면 data 채널 글은 test 채널로 보낸다.
--files: 영상·이미지 업로드. Webhook은 파일을 못 올리므로 SLACK_BOT_TOKEN(files:write 권한)과
         SLACK_CHANNEL_TEST / SLACK_CHANNEL_ALERT(채널 ID)가 있을 때만 올리고, 없으면 건너뛴다고 알린다.
"""
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

BASE = Path(__file__).resolve().parent
KEYS = {"test": "SLACK_WEBHOOK_TEST", "alert": "SLACK_WEBHOOK_ALERT", "data": "SLACK_WEBHOOK_DATA"}


def env(key, required=True):
    v = os.environ.get(key, "").strip()
    if v:
        return v
    f = BASE / ".env"
    if f.exists():
        for line in f.read_text(encoding="utf-8-sig").splitlines():
            if line.startswith(key + "="):
                return line.split("=", 1)[1].strip()
    if required:
        sys.exit(f"{key} 없음 (GitHub 비밀 설정 또는 .env)")
    return None


def webhook(channel: str) -> str:
    if channel not in KEYS:
        sys.exit("채널은 test, alert, data 중 하나")
    if channel == "data" and not env(KEYS["data"], False):
        return env(KEYS["test"])
    return env(KEYS[channel])


def api(method, token, data=None, form=True):
    body = urllib.parse.urlencode(data).encode() if form else data
    req = urllib.request.Request(f"https://slack.com/api/{method}", data=body,
                                 headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode())


def upload(files, channel):
    token, cid = env("SLACK_BOT_TOKEN", False), env(f"SLACK_CHANNEL_{channel.upper()}", False)
    if not token or not cid:
        return "파일 업로드 건너뜀 (봇 토큰·채널 ID 없음)"
    done = []
    try:
        for p in map(Path, files):
            data = p.read_bytes()
            u = api("files.getUploadURLExternal", token, {"filename": p.name, "length": len(data)})
            if not u.get("ok"):
                return f"업로드 실패: {u.get('error')}"
            urllib.request.urlopen(urllib.request.Request(u["upload_url"], data=data), timeout=300).read()
            done.append({"id": u["file_id"], "title": p.name})
        c = api("files.completeUploadExternal", token, {"files": json.dumps(done), "channel_id": cid,
                                                       "initial_comment": "🎬 이번 주 쇼츠 영상·썸네일 (자동 생성)"})
        return f"파일 {len(done)}개 업로드: " + ("ok" if c.get("ok") else c.get("error"))
    except Exception as e:  # 토큰이 섞여 나오지 않게 종류만
        return f"업로드 실패: {type(e).__name__}"


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    args = sys.argv[1:]
    files = []
    if "--files" in args:
        i = args.index("--files"); files = args[i + 1:]; args = args[:i]
    if args[0] == "--text":
        text, channel = args[1], args[2]
        body = json.dumps({"text": text}, ensure_ascii=False)
    else:
        body = Path(args[0]).read_text(encoding="utf-8")
        json.loads(body)  # 형식 확인
        channel = args[1]
    if os.environ.get("SLACK_DRY_RUN") == "1":
        print(f"게시 결과 ({channel}): 시험 실행이라 보내지 않음 ({len(body)}자)")
        sys.exit(0)
    req = urllib.request.Request(webhook(channel), data=body.encode("utf-8"), headers={"Content-Type": "application/json; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            res = r.read().decode()
    except Exception as e:  # 주소가 섞여 나오지 않게 메시지만
        sys.exit(f"게시 실패 ({channel}): {type(e).__name__}")
    print(f"게시 결과 ({channel}): {res}")
    if files:
        print(upload(files, channel))
    sys.exit(0 if res == "ok" else 1)


if __name__ == "__main__":
    main()
