#!/usr/bin/env python3
"""環境音（山の風）を合成して WAV に書き出すツール。

外部素材・外部ライブラリに依存せず、ローパスフィルタ済みノイズ +
ゆっくりした振幅の揺らぎで風の環境音ループを生成する。

使い方:
    python3 tools/generate_ambient.py            # assets/audio/wind_loop.wav を生成
    python3 tools/generate_ambient.py --seconds 20
"""

import argparse
import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 22050


def synth_wind(seconds: float, seed: int = 4649) -> list[float]:
    """風のループ音を [-1, 1] の float 列で返す。

    - 白色ノイズを1次IIRローパスに2段通して「ゴォー」という帯域にする
    - 2つの低周波LFOで強弱の揺らぎ（突風感）を付ける
    - 末尾と先頭をクロスフェードしてシームレスループにする
    """
    rng = random.Random(seed)
    n = int(seconds * SAMPLE_RATE)

    # 2段ローパス（カットオフ ~400Hz 相当）
    alpha = 0.10
    lp1 = lp2 = 0.0
    samples = []
    for i in range(n):
        white = rng.uniform(-1.0, 1.0)
        lp1 += alpha * (white - lp1)
        lp2 += alpha * (lp1 - lp2)

        t = i / SAMPLE_RATE
        # 風の強弱: 周期の異なるLFOを重ねて自然な揺らぎに
        gust = 0.55 + 0.3 * math.sin(2 * math.pi * 0.07 * t) \
                    + 0.15 * math.sin(2 * math.pi * 0.19 * t + 1.3)
        samples.append(lp2 * gust * 3.0)  # ローパスで下がった振幅を補償

    # シームレスループ: 末尾1秒を先頭にクロスフェード
    fade = SAMPLE_RATE
    for i in range(fade):
        w = i / fade
        samples[i] = samples[i] * w + samples[n - fade + i] * (1.0 - w)
    samples = samples[: n - fade]

    peak = max(abs(s) for s in samples)
    return [s / peak * 0.8 for s in samples]


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
        )
        wf.writeframes(frames)


def main() -> None:
    parser = argparse.ArgumentParser(description="山の風の環境音ループを生成する")
    parser.add_argument("--seconds", type=float, default=14.0, help="生成する長さ（秒）")
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "assets" / "audio" / "wind_loop.wav",
    )
    args = parser.parse_args()

    samples = synth_wind(args.seconds)
    write_wav(args.out, samples)
    print(f"[OK] {args.out} ({len(samples) / SAMPLE_RATE:.1f}s, {SAMPLE_RATE}Hz mono)")


if __name__ == "__main__":
    main()
