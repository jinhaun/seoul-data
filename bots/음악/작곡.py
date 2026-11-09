"""저작권 걱정 없는 배경음악을 코드로 직접 작곡해 wav로 저장한다 (외부 음원 사용 없음).
사용: python -X utf8 작곡.py      → 경쾌.wav (테크·게임), 잔잔.wav (서울·여행)
"""
import wave
from pathlib import Path

import numpy as np

SR = 44100
HERE = Path(__file__).resolve().parent
rng = np.random.default_rng(7)


def note(freq, dur, kind="keys", vol=0.2):
    t = np.arange(int(SR * dur)) / SR
    if kind == "keys":      # 부드러운 전자 피아노: 기음 + 배음, 빠른 어택·완만한 감쇠
        w = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(4 * np.pi * freq * t) + 0.12 * np.sin(6 * np.pi * freq * t)
        env = np.minimum(1, t / 0.01) * np.exp(-t * 2.2)
    elif kind == "pad":     # 잔잔한 패드: 살짝 어긋난 두 음으로 넓게
        w = np.sin(2 * np.pi * freq * t) + np.sin(2 * np.pi * freq * 1.003 * t)
        env = np.minimum(1, t / 0.4) * np.minimum(1, (dur - t) / 0.4)
    elif kind == "bass":
        w = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(4 * np.pi * freq * t)
        env = np.minimum(1, t / 0.005) * np.exp(-t * 3)
    elif kind == "pluck":   # 멜로디용 짧은 소리
        w = np.sign(np.sin(2 * np.pi * freq * t)) * 0.3 + np.sin(2 * np.pi * freq * t)
        env = np.minimum(1, t / 0.003) * np.exp(-t * 9)
    return (w * env * vol).astype(np.float32)


def kick(dur=0.35):
    t = np.arange(int(SR * dur)) / SR
    f = 110 * np.exp(-t * 18) + 45
    return (np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * 0.9).astype(np.float32)


def snare(dur=0.2):
    t = np.arange(int(SR * dur)) / SR
    return ((rng.standard_normal(len(t)) * 0.5 + np.sin(2 * np.pi * 190 * t) * 0.3) * np.exp(-t * 20) * 0.45).astype(np.float32)


def hat(dur=0.05):
    t = np.arange(int(SR * dur)) / SR
    n = rng.standard_normal(len(t))
    n = np.diff(n, prepend=0)  # 고음만 남기기
    return (n * np.exp(-t * 70) * 0.12).astype(np.float32)


def put(buf, sig, at):
    i = int(at * SR)
    j = min(len(buf), i + len(sig))
    if i < len(buf):
        buf[i:j] += sig[: j - i]


def hz(m):  # MIDI 번호 → 주파수
    return 440 * 2 ** ((m - 69) / 12)


def song(bpm, chords, bars_per_chord, melody, drums, kind, out, loops=4):
    beat = 60 / bpm
    bar = beat * 4
    total = bar * bars_per_chord * len(chords) * loops
    buf = np.zeros(int(SR * (total + 2)), dtype=np.float32)
    t = 0.0
    for _ in range(loops):
        for ci, ch in enumerate(chords):
            for b in range(bars_per_chord):
                start = t + b * bar
                if kind == "keys":   # 8분음표 리듬 코드
                    for k in range(8):
                        if k in (0, 3, 6):
                            for m in ch:
                                put(buf, note(hz(m + 12), beat * 1.4, "keys", 0.07), start + k * beat / 2)
                else:                # 길게 깔리는 패드
                    for m in ch:
                        put(buf, note(hz(m + 12), bar, "pad", 0.05), start)
                put(buf, note(hz(ch[0] - 12), beat * 1.8, "bass", 0.28), start)
                put(buf, note(hz(ch[0] - 12), beat * 0.9, "bass", 0.2), start + beat * 2.5)
                if drums:
                    for k in range(4):
                        if k in (0, 2):
                            put(buf, kick(), start + k * beat)
                        if k in (1, 3):
                            put(buf, snare(), start + k * beat)
                        put(buf, hat(), start + k * beat + beat / 2)
                        put(buf, hat(), start + k * beat)
                else:
                    put(buf, kick() * 0.5, start)
                    put(buf, hat() * 0.6, start + beat * 2)
                mel = melody[(ci * bars_per_chord + b) % len(melody)]
                for k, m in enumerate(mel):
                    if m:
                        put(buf, note(hz(m + 12), beat * 0.9, "pluck", 0.06), start + k * beat)
            t += bar * bars_per_chord
    buf = buf[: int(SR * total)]
    # 앞뒤 페이드, 가벼운 리버브(에코), 정규화
    echo = np.zeros_like(buf); d = int(SR * beat * 0.75)
    echo[d:] = buf[:-d] * 0.25
    buf = buf + echo
    fade = int(SR * 1.0)
    buf[:fade] *= np.linspace(0, 1, fade); buf[-fade:] *= np.linspace(1, 0, fade)
    buf = buf / np.max(np.abs(buf)) * 0.8
    stereo = np.stack([buf, np.roll(buf, int(SR * 0.012))], axis=1)
    with wave.open(str(out), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((stereo * 32767).astype("<i2").tobytes())
    print(f"{out.name}: {total:.1f}초, {bpm}bpm")


# C장조 I–V–vi–IV (C G Am F), 경쾌: 드럼 + 리듬 코드
C, G, Am, F = [48, 52, 55], [43, 47, 50], [45, 48, 52], [41, 45, 48]
song(112, [C, G, Am, F], 1,
     [[67, 0, 64, 67], [71, 0, 67, 0], [69, 72, 0, 69], [65, 0, 69, 0]],
     True, "keys", HERE / "경쾌.wav", loops=6)
# 잔잔: 느린 패드 Fmaj7–Em7–Dm7–Cmaj7 느낌
F7, Em7, Dm7, C7 = [41, 45, 48, 52], [40, 43, 47, 50], [38, 41, 45, 48], [36, 40, 43, 47]
song(84, [F7, Em7, Dm7, C7], 1,
     [[72, 0, 0, 69], [71, 0, 67, 0], [69, 0, 0, 65], [64, 0, 67, 0]],
     False, "pad", HERE / "잔잔.wav", loops=6)
