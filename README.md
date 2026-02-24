# ハイキングシミュレーター

実際の登山で必要な思考・判断・計画をゲームを通じて体験・学習できる、リアル系登山シミュレーターゲーム。

> **コンセプト**: 「登山は山頂に立つことではなく、安全に帰ってくること」

---

## 必要な環境

| ツール | バージョン | 用途 |
|--------|-----------|------|
| [Godot 4](https://godotengine.org/download/) | 4.3 以上 | ゲーム本体の起動・編集 |
| [GUT プラグイン](https://github.com/bitwes/Gut) | 9.x (Godot 4対応) | GDScript の単体テスト |
| Python | 3.11 以上 | 標高APIツール・Pythonテスト |
| pip パッケージ: `requests`, `pytest` | 最新 | APIアクセス・テスト実行 |

---

## セットアップ

### 1. リポジトリをクローン

```bash
git clone <リポジトリURL>
cd hiking_simulator
```

### 2. Python 依存パッケージをインストール

```bash
pip install requests pytest
```

### 3. Godot でプロジェクトを開く

1. Godot 4 を起動
2. 「インポート」→ このリポジトリの `project.godot` を選択
3. プロジェクトが開く

### 4. GUT プラグインを導入（GDScript テスト用）

1. Godot エディタ上で **AssetLib** を開く
2. 「GUT」で検索してインストール
3. **Project → Project Settings → Plugins** で GUT を **Enable** にする

または、GitHubから直接取得する場合:

```bash
# addons/ ディレクトリに GUT を配置
mkdir -p addons
cd addons
git clone https://github.com/bitwes/Gut.git gut
```

---

## ゲームの起動

Godot エディタで `F5`（または再生ボタン）を押すと起動します。

メインシーンは `scenes/main.tscn` です（シーンファイルは今後作成予定）。

---

## テストの実行

### Python テスト（標高API・ユーティリティ）

**オフライン（CI推奨・ネット不要）:**

```bash
python3 -m pytest tests/tools/ -v -m "not online"
```

**オンライン（実際のAPIを叩く結合テスト）:**

```bash
python3 -m pytest tests/tools/ -v
```

**実行例:**

```
tests/tools/test_fetch_elevation.py::TestLatLonToTile::test_PY15_takao_zoom14  PASSED
tests/tools/test_fetch_elevation.py::TestParseCsv::test_PY10_normal_csv        PASSED
tests/tools/test_fetch_elevation.py::TestFetchElevationMock::test_PY12_404_...  PASSED
...
14 passed, 4 deselected in 0.59s
```

### GDScript テスト（Godot / GUT）

**Godot エディタ上で実行:**

1. **Project → Tools → GUT** を開く
2. 「Run All」をクリック

**コマンドラインで実行（ヘッドレス）:**

```bash
godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=tests/ \
  -gprefix=test_ \
  -gsuffix=.gd \
  -gexit
```

テスト対象:

| ファイル | ケース数 | 内容 |
|----------|---------|------|
| `tests/unit/test_player_stats.gd` | 27 | 体力・水分パラメータ管理 |
| `tests/unit/test_terrain_generator.gd` | 9 | 座標変換・CSVパース |

---

## 標高データ確認ツール

国土地理院APIから標高データを取得して表示するデバッグツールです。

```bash
# 高尾山付近（デフォルト）
python3 tools/fetch_elevation.py

# 任意の座標を指定
python3 tools/fetch_elevation.py --lat 35.3606 --lon 138.7274 --zoom 14
```

**出力例:**

```
=== 国土地理院 標高タイルAPI 検証 ===
  緯度: 35.6252, 経度: 139.2437, ズーム: 14

  取得中: https://cyberjapandata.gsi.go.jp/xyz/dem5a/14/14529/6454.txt

[OK] データ取得成功
  行数: 256, 列数: 256
  標高 最小: 120.3m  最大: 599.2m  平均: 312.1m
  欠損値: 0 / 65536 (0.0%)

  [標高グリッド サンプル表示]
  (低) .:-=+*#@ (高)

  .....---==++*
  ...----==+**#
  ...
```

---

## プロジェクト構成

```
hiking_simulator/
├── project.godot                      # Godot 4 プロジェクト設定
├── scenes/                            # シーンファイル (.tscn) ※作成予定
│   ├── player/
│   ├── terrain/
│   └── ui/
├── scripts/                           # GDScript
│   ├── main.gd                        # GameManager（フェーズ管理）
│   ├── player/
│   │   ├── player.gd                  # 移動・勾配検出
│   │   └── player_stats.gd            # 体力・水分パラメータ管理
│   ├── terrain/
│   │   └── terrain_generator.gd       # 国土地理院API → 3Dメッシュ生成
│   └── ui/
│       └── hud.gd                     # HUD（バー・時刻・警告表示）
├── docs/
│   ├── design/                        # モジュール設計書
│   └── test/                          # テスト設計書
├── tests/
│   ├── unit/                          # GUT 単体テスト (.gd)
│   └── tools/                         # Python テスト
├── tools/
│   └── fetch_elevation.py             # 標高API検証ツール
├── GAME_DESIGN.md                     # ゲームデザインドキュメント
└── pytest.ini                         # pytest 設定
```

---

## ドキュメント

- [ゲームデザインドキュメント（GDD）](./GAME_DESIGN.md)
- [テスト設計書](./docs/test/test_design.md)
- 設計書: [PlayerStats](./docs/design/player_stats_design.md) / [TerrainGenerator](./docs/design/terrain_generator_design.md) / [GameManager](./docs/design/game_manager_design.md)
