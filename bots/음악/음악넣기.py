"""영상에 배경음악 넣기: 목소리가 나올 때 음악이 자동으로 작아지고(덕킹), 끝에서 페이드아웃.
사용: python -X utf8 음악넣기.py <영상.mp4> <경쾌|잔잔|음악파일> [출력.mp4]
출력 기본값: <영상>_음악.mp4 (원본은 그대로 둠). 영상은 다시 인코딩하지 않아 화질이 그대로다.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
# 예약 실행·다른 터미널에서도 ffmpeg를 찾도록 winget 설치 위치를 PATH에 추가
_WINGET = Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft" / "WinGet" / "Links"
if not shutil.which("ffmpeg") and _WINGET.exists():
    os.environ["PATH"] = str(_WINGET) + os.pathsep + os.environ.get("PATH", "")
VOL = 0.30  # 음악 기본 크기 (덕킹 전)


def main():
    src = Path(sys.argv[1])
    track = sys.argv[2]
    music = HERE / f"{track}.wav" if track in ("경쾌", "잔잔") else Path(track)
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else src.with_name(src.stem + "_음악.mp4")
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(src)],
                               capture_output=True, text=True).stdout)
    fc = (f"[1:a]aresample=48000,volume={VOL},afade=t=in:d=0.8,afade=t=out:st={max(0, dur - 2.5):.2f}:d=2.5[m];"
          "[0:a]aresample=48000,pan=stereo|c0=c0|c1=c0,asplit=2[v][sc];"  # 모노 목소리를 양쪽에 그대로 (크기 유지)
          "[m][sc]sidechaincompress=threshold=0.02:ratio=10:attack=15:release=350[md];"
          "[v][md]amix=inputs=2:normalize=0:duration=first[a]")
    r = subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-stream_loop", "-1", "-i", str(music),
                        "-filter_complex", fc, "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                        "-t", f"{dur:.3f}", "-movflags", "+faststart", str(out)], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("음악 넣기 실패: " + r.stderr[-300:])
    print(f"완료: {out.name} ({dur:.1f}초, {music.stem})")


if __name__ == "__main__":
    main()
