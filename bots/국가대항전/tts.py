"""대본 문장 → 자연스러운 음성 파일 (edge-tts, Microsoft 신경망 음성).
사용: python -X utf8 tts.py <문장목록.json> <출력폴더> [목소리] [속도]
출력: v00.mp3, v01.mp3 ... (문장 순서대로)
※ edge-tts는 비공식 경로라 수익 채널에 오래 쓸 거면 정식 음성 서비스나 직접 녹음으로 바꾸는 게 안전하다.
"""
import asyncio
import json
import sys
from pathlib import Path

import edge_tts


async def main():
    lines = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
    out = Path(sys.argv[2])
    voice = sys.argv[3] if len(sys.argv) > 3 else "ko-KR-SunHiNeural"
    rate = sys.argv[4] if len(sys.argv) > 4 else "+12%"
    for i, text in enumerate(lines):
        for attempt in range(3):
            try:
                await edge_tts.Communicate(text, voice, rate=rate).save(str(out / f"v{i:02d}.mp3"))
                break
            except Exception:
                if attempt == 2:
                    raise
                await asyncio.sleep(2)
    print(f"음성 {len(lines)}개")


asyncio.run(main())
