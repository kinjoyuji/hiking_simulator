# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 開発ブランチ

作業ブランチ: `claude/mountain-experience-design-d4a9w3`
変更は必ずこのブランチにコミット・プッシュすること。

## よく使うコマンド

### Python テスト

```bash
# オフラインテストのみ（CI・通常開発はこちら）
python3 -m pytest tests/tools/ -v -m "not online"

# 単一テストの実行
python3 -m pytest tests/tools/test_fetch_elevation.py::TestParseCsv::test_PY10_normal_csv -v

# オンラインテスト含む全テスト（国土地理院APIへの実アクセスあり）
python3 -m pytest tests/tools/ -v
```

### GDScript テスト (GUT)

```bash
# ヘッドレス実行（godot = Godot 4.6 バイナリ。WSLでは ~/.local/bin/godot に配置）
godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gprefix=test_ -gsuffix=.gd -gexit

# スモークテスト（メインシーンを実行して地形生成〜登頂まで一気通貫検証）
godot --headless -s tests/smoke/smoke_main.gd

# シーン/スクリプト変更後の再インポート
godot --headless --import
```

### 標高データ確認ツール

```bash
python3 tools/fetch_elevation.py --lat 35.6252 --lon 139.2437 --zoom 14
```

## アーキテクチャ概要

### ゲームのフェーズ遷移

```
[PLANNING] → [HIKING] → [RESULT]
                ↓
          [EMERGENCY] → [RESULT]
```

`scripts/main.gd` の `GameManager` がフェーズ全体を管理する。グループ名 `"game_manager"` で登録されており、他ノードからは `get_tree().call_group("game_manager", "メソッド名", ...)` で呼び出す。

### ノード間の依存関係

```
GameManager (scripts/main.gd)
  ├── Player (scripts/player/player.gd)
  │     └── PlayerStats (scripts/player/player_stats.gd)  ← シグナルで疎結合
  ├── TerrainGenerator (scripts/terrain/terrain_generator.gd)
  └── HUD (scripts/ui/hud.gd)  ← PlayerStats.stats_changed シグナルを購読
```

ノード間の直接参照は GameManager を経由させる（仲介パターン）。PlayerStats から HUD への依存はなく、シグナル `stats_changed` / `player_downed` 経由でのみ通信する。

### PlayerStats の消耗計算

歩行中の体力消耗は `BASE_STAMINA_DRAIN_PER_SEC × weight_mult × slope_mult × weather_mult + dehydration_penalty`。立ち止まり中（`apply_drain(..., is_moving=false)`）は体力が回復し、水分のみ基礎代謝分消耗する。倍率テーブルは定数として `player_stats.gd` に定義されており、変更時はテスト `tests/unit/test_player_stats.gd` の境界値テスト (BV-06〜10) も合わせて更新が必要。

### TerrainGenerator の地形生成パイプライン

`generate_from_tile(zoom, x, y)` → 非同期 HTTP → CSV パース → 最低標高で正規化（最低点が y=0）→ `SurfaceTool` でメッシュ生成（頂点カラー: 標高比で緑→茶→灰）→ `create_trimesh_collision()` → 木・岩を MultiMesh 散布 → `terrain_ready` シグナル発火（登山口・山頂座標・基準標高を渡す）。

取得失敗時は `FastNoiseLite` の仮想の山にフォールバックする（オフラインでもプレイ・テスト可能）。CSV の欠損値 `"e"` は `0.0` で補完（将来的に近傍補間へ改善予定）。

**落とし穴**: メッシュのインデックス巻き順は法線が +y になる順で固定すること。逆にすると描画・コリジョンとも裏返り、プレイヤーが地形をすり抜ける。頂点カラーには `vertex_color_is_srgb = true` が必要（ないと色が明るく飛ぶ）。

### GDScript の記法制約（Godot 4）

- 動的型の戻り値を `:=` で受けるとパースエラー。`var x: float = stats.stamina` と明示型で受ける
- GUT 9.5 の比較アサートは `assert_gte` / `assert_lte`（`assert_ge/le` は無い）

## テスト設計の方針

テストは3種類で構成される。新機能追加時はこの分類に従うこと:

- **機能テスト (ST/PY-01〜)**: 正常系の入出力検証
- **境界値テスト (BV/TG-)**: 倍率テーブルの閾値・クランプ上下限での挙動確認
- **耐久テスト (DU-)**: 長時間シミュレーション（28800フレーム = ゲーム内8時間相当）で値が `[0, 100]` を外れないことを確認

詳細は `docs/test/test_design.md` を参照。

## フェーズ2: クオリティアップ（計画済み）

体験品質向上（遠景の稜線・樹林帯の質感・環境音の重層化）の計画は以下の資料に従うこと:

- ロードマップ: `docs/roadmap/quality_up_roadmap.md`（マイルストーン M1〜M5・技術スタック方針・性能予算）
- 設計書: `docs/design/vista_and_atmosphere_design.md`（フォグ・空・マルチタイル遠景）
- 設計書: `docs/design/forest_experience_design.md`（植生帯・樹木LOD・登山道・地面シェーダー）
- 設計書: `docs/design/ambient_audio_design.md`（バス構成・音レイヤー・素材合成パイプライン）

実装時はまず該当設計書を読み、設計変更が必要なら設計書を先に更新する。

## 将来フェーズで追加予定の機能（フェーズ3以降・現時点では実装しないこと）

- パラメータ: 空腹・体温・バッテリー残量
- 行動種別: 走行・クライミング
- イベント: 雷・ホワイトアウト・道迷い・転倒・救助要請
- `is_downed` の解除（現在は不可）
- 川・湖の水面メッシュ、雪山（マルチシーズン）
