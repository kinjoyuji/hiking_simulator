# ハイキングシミュレーター

実際の登山で必要な思考・判断・計画をゲームを通じて体験・学習できる、リアル系登山シミュレーターゲーム。

> **コンセプト**: 「登山は山頂に立つことではなく、安全に帰ってくること」

---

## 必要な環境

| ツール | バージョン | 用途 |
|--------|-----------|------|
| [Godot 4](https://godotengine.org/download/) | 4.6 以上 | ゲーム本体の起動・編集 |
| Python | 3.11 以上 | 標高APIツール・環境音生成・Pythonテスト |
| pip パッケージ: `requests`, `pytest` | 最新 | APIアクセス・テスト実行 |

GUT プラグイン（GDScriptテスト）と Noto Sans JP フォントはリポジトリに同梱済み。

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

CLI の場合（Linux/WSL）:

```bash
# Godot 4.6 バイナリを取得して ~/.local/bin/godot に配置した想定
godot --headless --import   # 初回インポート
godot                        # エディタ起動
```

---

## ゲームの起動

Godot エディタで `F5`（または再生ボタン）を押すと起動します。メインシーンは `scenes/main.tscn` です。

### 遊び方（MVP: 入門・高尾山コース）

1. 「登山計画」画面で内容を確認して **出発する**
2. 国土地理院の実標高データから山が生成され、登山口にスポーンする
   （オフライン時は自動的に仮想の山になる）
3. 山頂に立つ**赤い標柱**を目指して歩く
4. 体力・水分に注意。山行中に**雨が降ると消耗が加速**する
5. 山頂到達で登頂成功。体力か水分が尽きると行動不能（教育的フィードバック表示）

| 操作 | 内容 |
|------|------|
| WASD | 移動 |
| マウス | 視点 |
| 矢印キー | 視点を回す（マウスキャプチャが効かない環境でも360°見渡せる） |
| E | 水を飲む（手持ち1500ml） |
| H | 操作ヘルプの表示/非表示 |
| 立ち止まる | 呼吸を整えて体力回復 |
| ESC / クリック | マウス解放 / 再キャプチャ |

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
  -gdir=tests/unit \
  -gprefix=test_ \
  -gsuffix=.gd \
  -gexit
```

テスト対象:

| ファイル | ケース数 | 内容 |
|----------|---------|------|
| `tests/unit/test_player_stats.gd` | 34 | 体力・水分・飲水・休憩・天候 |
| `tests/unit/test_terrain_generator.gd` | 10 | 座標変換・CSVパース |

### スモークテスト（ゲームループ一気通貫）

メインシーンを実際に起動し、地形生成 → スポーン → 消耗 → 飲水 → 登頂までを自動検証します。

```bash
godot --headless -s tests/smoke/smoke_main.gd
```

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
├── scenes/
│   └── main.tscn                      # メインシーン（HUD/Player/地形/パネル）
├── scripts/                           # GDScript
│   ├── main.gd                        # GameManager（フェーズ管理・ゴール・天候）
│   ├── player/
│   │   ├── player.gd                  # 移動・勾配検出・飲水入力
│   │   └── player_stats.gd            # 体力・水分・飲水・休憩回復
│   ├── terrain/
│   │   └── terrain_generator.gd       # 国土地理院API → 3Dメッシュ + 木/岩散布
│   └── ui/
│       └── hud.gd                     # HUD（バー・時刻・標高・警告・メッセージ）
├── assets/
│   ├── audio/wind_loop.wav            # 風の環境音（tools/generate_ambient.py で生成）
│   └── fonts/NotoSansJP.ttf           # 日本語フォント（OFL）
├── docs/
│   ├── design/                        # モジュール設計書
│   └── test/                          # テスト設計書
├── tests/
│   ├── unit/                          # GUT 単体テスト (.gd)
│   ├── smoke/                         # ヘッドレス・スモークテスト
│   └── tools/                         # Python テスト
├── tools/
│   ├── fetch_elevation.py             # 標高API検証ツール
│   └── generate_ambient.py            # 環境音（風）合成ツール
├── GAME_DESIGN.md                     # ゲームデザインドキュメント
└── pytest.ini                         # pytest 設定
```

---

## ドキュメント

- [ゲームデザインドキュメント（GDD）](./GAME_DESIGN.md)
- [テスト設計書](./docs/test/test_design.md)
- 設計書: [PlayerStats](./docs/design/player_stats_design.md) / [TerrainGenerator](./docs/design/terrain_generator_design.md) / [GameManager](./docs/design/game_manager_design.md)
