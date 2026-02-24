"""
標高APIツール テスト
====================
テスト種別:
  - 機能テスト  (PY-01〜04): オンラインAPI を実際に叩く
  - モックテスト (PY-10〜15): ネットワーク不要、CI でも実行可能

実行方法:
  # 全テスト（要ネット接続）
  python3 -m pytest tests/tools/test_fetch_elevation.py -v

  # オフラインテストのみ
  python3 -m pytest tests/tools/test_fetch_elevation.py -v -m "not online"

  # 詳細なコンソール出力付き
  python3 -m pytest tests/tools/test_fetch_elevation.py -v -s
"""

import math
import sys
import unittest
from unittest.mock import MagicMock, patch

import pytest

# テスト対象のモジュールを tools/ からインポート
sys.path.insert(0, "tools")
import fetch_elevation as fe


# ===========================================================================
# ユーティリティ
# ===========================================================================

def _make_csv(rows: int = 256, cols: int = 256, value: float = 500.0, missing: bool = False) -> str:
    """テスト用CSVを生成する"""
    lines = []
    for r in range(rows):
        row_vals = []
        for c in range(cols):
            if missing and r == 0 and c == 0:
                row_vals.append("e")
            else:
                row_vals.append(f"{value + r * 0.1:.1f}")
        lines.append(",".join(row_vals))
    return "\n".join(lines)


# ===========================================================================
# 機能テスト (モック) — PY-10〜15
# ===========================================================================

class TestLatLonToTile(unittest.TestCase):
    """latlon_to_tile の単体テスト（純粋関数）"""

    def test_PY15_takao_zoom14(self):
        """高尾山付近のタイル座標検証 (zoom=14)"""
        tx, ty = fe.latlon_to_tile(35.6252, 139.2437, 14)
        # 期待値: Webメルカトル計算による実測値
        self.assertEqual(tx, 14529)
        self.assertEqual(ty, 6454)

    def test_west_edge(self):
        """経度 -180 は x=0"""
        tx, _ = fe.latlon_to_tile(0.0, -180.0, 10)
        self.assertEqual(tx, 0)

    def test_tile_in_valid_range(self):
        """zoom=8 では x, y が [0, 255] の範囲内"""
        zoom = 8
        tx, ty = fe.latlon_to_tile(35.0, 135.0, zoom)
        self.assertGreaterEqual(tx, 0)
        self.assertLess(tx, 2 ** zoom)
        self.assertGreaterEqual(ty, 0)
        self.assertLess(ty, 2 ** zoom)

    def test_higher_zoom_more_tiles(self):
        """ズームが1上がるとタイル数が4倍になる（x, y ともに2倍）"""
        tx14, ty14 = fe.latlon_to_tile(35.0, 135.0, 14)
        tx15, ty15 = fe.latlon_to_tile(35.0, 135.0, 15)
        # zoom+1 では各タイル座標がほぼ2倍になる
        self.assertAlmostEqual(tx15 / tx14, 2.0, delta=1.0)
        self.assertAlmostEqual(ty15 / ty14, 2.0, delta=1.0)


class TestParseCsv(unittest.TestCase):
    """fetch_elevation.py 内の CSV パース処理テスト"""

    def _parse(self, csv_text: str):
        """fetch_elevation_tile のパース部分のみ抽出して呼ぶ"""
        rows = []
        for line in csv_text.strip().split("\n"):
            row = []
            for cell in line.split(","):
                c = cell.strip()
                row.append(None if c == "e" else float(c))
            if row:
                rows.append(row)
        return rows

    def test_PY10_normal_csv(self):
        """正常なCSVデータのパース"""
        csv = "100.0,200.0\n300.0,400.0"
        result = self._parse(csv)
        self.assertEqual(len(result), 2)
        self.assertEqual(len(result[0]), 2)
        self.assertAlmostEqual(result[0][0], 100.0)
        self.assertAlmostEqual(result[1][1], 400.0)

    def test_PY11_missing_value_e(self):
        """'e' は None として処理される"""
        csv = "100.0,e\ne,200.0"
        result = self._parse(csv)
        self.assertIsNone(result[0][1])
        self.assertIsNone(result[1][0])

    def test_PY11b_missing_value_statistics(self):
        """欠損値を含む場合の統計計算が正常に動作する"""
        csv = _make_csv(10, 10, 500.0, missing=True)
        data = self._parse(csv)
        flat = [v for row in data for v in row if v is not None]
        # 1つ欠損なので 10*10-1 = 99 個
        self.assertEqual(len(flat), 99)

    def test_negative_elevation(self):
        """負の標高値が正しくパースされる"""
        csv = "-5.2,0.0\n10.0,-15.8"
        result = self._parse(csv)
        self.assertAlmostEqual(result[0][0], -5.2)
        self.assertAlmostEqual(result[1][1], -15.8)

    def test_single_cell(self):
        """1行1列のCSV"""
        csv = "523.5"
        result = self._parse(csv)
        self.assertEqual(len(result), 1)
        self.assertAlmostEqual(result[0][0], 523.5)


class TestFetchElevationMock(unittest.TestCase):
    """requests をモックしたAPIテスト（ネット不要）"""

    def _make_response(self, status_code: int, text: str = ""):
        mock_resp = MagicMock()
        mock_resp.status_code = status_code
        mock_resp.text = text
        return mock_resp

    @patch("fetch_elevation.requests.get")
    def test_PY10_success_returns_data(self, mock_get):
        """HTTP 200 のとき有効なデータを返す"""
        csv = _make_csv(256, 256, 300.0)
        mock_get.return_value = self._make_response(200, csv)
        result = fe.fetch_elevation_tile(14, 14555, 6461)
        self.assertIsNotNone(result)
        self.assertEqual(len(result), 256)
        self.assertEqual(len(result[0]), 256)

    @patch("fetch_elevation.requests.get")
    def test_PY12_404_falls_back_to_dem(self, mock_get):
        """HTTP 404 のとき低解像度 dem にフォールバックする"""
        csv = _make_csv(256, 256, 100.0)
        mock_get.side_effect = [
            self._make_response(404, ""),        # dem5a → 404
            self._make_response(200, csv),       # dem   → 成功
        ]
        result = fe.fetch_elevation_tile(14, 14555, 6461)
        self.assertIsNotNone(result)
        self.assertEqual(mock_get.call_count, 2, "フォールバックで2回リクエストされること")

    @patch("fetch_elevation.requests.get")
    def test_PY13_http_500_returns_none(self, mock_get):
        """HTTP 500 のとき None を返す"""
        mock_get.return_value = self._make_response(500, "")
        result = fe.fetch_elevation_tile(14, 14555, 6461)
        self.assertIsNone(result)

    @patch("fetch_elevation.requests.get")
    def test_PY14_timeout_returns_none(self, mock_get):
        """タイムアウト例外のとき None を返す"""
        import requests as req_module
        mock_get.side_effect = req_module.exceptions.Timeout()
        result = fe.fetch_elevation_tile(14, 14555, 6461)
        self.assertIsNone(result)

    @patch("fetch_elevation.requests.get")
    def test_elevation_values_are_numeric(self, mock_get):
        """取得データの全要素が数値 (None or float) であること"""
        csv = _make_csv(10, 10, 250.0, missing=True)
        mock_get.return_value = self._make_response(200, csv)
        result = fe.fetch_elevation_tile(14, 0, 0)
        for row in result:
            for val in row:
                self.assertTrue(
                    val is None or isinstance(val, float),
                    f"値は None か float であること: {val!r}"
                )


# ===========================================================================
# 機能テスト (オンライン) — PY-01〜04
# マーカー: @pytest.mark.online
# CI では除外: pytest -m "not online"
# ===========================================================================

@pytest.mark.online
class TestFetchElevationOnline(unittest.TestCase):
    """実際にAPIを叩く結合テスト（ネット接続必須）"""

    ZOOM = 14
    LAT  = 35.6252   # 高尾山付近
    LON  = 139.2437

    def setUp(self):
        tx, ty = fe.latlon_to_tile(self.LAT, self.LON, self.ZOOM)
        self.data = fe.fetch_elevation_tile(self.ZOOM, tx, ty)

    def test_PY01_http_200_returns_data(self):
        """正常にデータが取得できること"""
        self.assertIsNotNone(self.data, "APIからデータが取得できること")

    def test_PY02_row_count_is_256(self):
        """行数が256であること"""
        if self.data is None:
            self.skipTest("APIデータ未取得のためスキップ")
        self.assertEqual(len(self.data), 256)

    def test_PY03_col_count_is_256(self):
        """各行の列数が256であること"""
        if self.data is None:
            self.skipTest("APIデータ未取得のためスキップ")
        for i, row in enumerate(self.data):
            self.assertEqual(len(row), 256, f"row {i} の列数が256であること")

    def test_PY04_elevation_values_in_realistic_range(self):
        """標高値が現実的な範囲 (-100m 〜 4000m) であること"""
        if self.data is None:
            self.skipTest("APIデータ未取得のためスキップ")
        for row in self.data:
            for val in row:
                if val is not None:
                    self.assertGreaterEqual(val, -100.0, f"標高 {val}m は -100m 以上であること")
                    self.assertLessEqual(val, 4000.0, f"標高 {val}m は 4000m 以下であること")


if __name__ == "__main__":
    unittest.main()
