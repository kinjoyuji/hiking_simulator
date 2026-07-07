#!/usr/bin/env python3
"""
国土地理院 標高タイルAPI 検証スクリプト
=========================================
用途:
  Godot組み込み前に、APIからの標高データ取得・パースが
  正しく動作するかをPythonで検証する。

使い方:
  python3 tools/fetch_elevation.py
  python3 tools/fetch_elevation.py --lat 35.6252 --lon 139.2437 --zoom 15

出力:
  - タイル座標
  - 標高データの統計（最小・最大・平均）
  - サンプルグリッド（10×10）のASCII表示
"""

import argparse
import math
import sys
import requests


GSI_URL = "https://cyberjapandata.gsi.go.jp/xyz/dem5a/{z}/{x}/{y}.txt"
FALLBACK_URL = "https://cyberjapandata.gsi.go.jp/xyz/dem/{z}/{x}/{y}.txt"  # 低解像度フォールバック


def latlon_to_tile(lat: float, lon: float, zoom: int) -> tuple[int, int]:
    """緯度経度 → Webメルカトル タイル座標 (x, y)"""
    n = 2 ** zoom
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.log(math.tan(lat_rad) + 1.0 / math.cos(lat_rad)) / math.pi) / 2.0 * n)
    return x, y


def fetch_elevation_tile(zoom: int, x: int, y: int) -> list[list[float]] | None:
    """標高タイルCSVを取得してパースする。欠損値('e')は None で返す。"""
    url = GSI_URL.format(z=zoom, x=x, y=y)
    print(f"  取得中: {url}")
    try:
        resp = requests.get(url, timeout=10)
    except requests.exceptions.RequestException as e:
        print(f"  [ERROR] リクエスト失敗: {e}", file=sys.stderr)
        return None

    if resp.status_code == 404:
        # dem5a がない場合は低解像度 dem にフォールバック
        url = FALLBACK_URL.format(z=zoom, x=x, y=y)
        print(f"  フォールバック: {url}")
        try:
            resp = requests.get(url, timeout=10)
        except requests.exceptions.RequestException as e:
            print(f"  [ERROR] フォールバックリクエスト失敗: {e}", file=sys.stderr)
            return None

    if resp.status_code != 200:
        print(f"  [ERROR] HTTP {resp.status_code}", file=sys.stderr)
        return None

    rows = []
    for line in resp.text.strip().split("\n"):
        row = []
        for cell in line.split(","):
            c = cell.strip()
            row.append(None if c == "e" else float(c))
        if row:
            rows.append(row)
    return rows


def print_stats(data: list[list[float]]) -> None:
    flat = [v for row in data for v in row if v is not None]
    if not flat:
        print("  有効な標高データがありません（全て欠損値）")
        return
    print(f"  行数: {len(data)}, 列数: {len(data[0])}")
    print(f"  標高 最小: {min(flat):.1f}m  最大: {max(flat):.1f}m  平均: {sum(flat)/len(flat):.1f}m")
    missing = sum(1 for row in data for v in row if v is None)
    print(f"  欠損値: {missing} / {len(flat) + missing} ({missing/(len(flat)+missing)*100:.1f}%)")


def print_ascii_grid(data: list[list[float]], sample: int = 10) -> None:
    """粗くサンプリングしてASCIIで標高を可視化する"""
    rows = len(data)
    cols = len(data[0]) if rows > 0 else 0
    if rows == 0 or cols == 0:
        return

    flat = [v for row in data for v in row if v is not None]
    if not flat:
        return
    lo, hi = min(flat), max(flat)
    chars = " .:-=+*#@"

    row_step = max(1, rows // sample)
    col_step = max(1, cols // sample)

    print("\n  [標高グリッド サンプル表示]")
    print("  (低) " + "".join(chars) + " (高)\n")
    for r in range(0, rows, row_step):
        line = "  "
        for c in range(0, cols, col_step):
            v = data[r][c]
            if v is None:
                line += "?"
            else:
                idx = int((v - lo) / (hi - lo + 1e-9) * (len(chars) - 1))
                line += chars[idx]
        print(line)


def main() -> None:
    parser = argparse.ArgumentParser(description="国土地理院 標高タイルAPI 検証ツール")
    parser.add_argument("--lat",  type=float, default=35.6252, help="緯度 (default: 高尾山付近)")
    parser.add_argument("--lon",  type=float, default=139.2437, help="経度")
    parser.add_argument("--zoom", type=int,   default=14,      help="ズームレベル (推奨: 14〜15)")
    args = parser.parse_args()

    print(f"\n=== 国土地理院 標高タイルAPI 検証 ===")
    print(f"  緯度: {args.lat}, 経度: {args.lon}, ズーム: {args.zoom}")

    tx, ty = latlon_to_tile(args.lat, args.lon, args.zoom)
    print(f"  タイル座標: x={tx}, y={ty}\n")

    data = fetch_elevation_tile(args.zoom, tx, ty)
    if data is None:
        print("[FAIL] データ取得に失敗しました。")
        sys.exit(1)

    print("\n[OK] データ取得成功")
    print_stats(data)
    print_ascii_grid(data)
    print("\n[完了] Godotのterrain_generator.gdに同じロジックを実装できます。")


if __name__ == "__main__":
    main()
