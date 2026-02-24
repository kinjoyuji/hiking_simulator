# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 開発ブランチ

作業ブランチ: `claude/hiking-simulator-concept-mz6rO`
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
# ヘッドレス実行（Godot インストール済みの場合）
godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/ -gprefix=test_ -gsuffix=.gd -gexit
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

体力消耗は `BASE_STAMINA_DRAIN × weight_mult × slope_mult + dehydration_penalty` で計算される。倍率テーブルは定数として `player_stats.gd` に定義されており、変更時はテスト `tests/unit/test_player_stats.gd` の境界値テスト (BV-06〜10) も合わせて更新が必要。

### TerrainGenerator の地形生成パイプライン

`generate_from_tile(zoom, x, y)` → 非同期 HTTP → CSV パース → `SurfaceTool` でメッシュ生成 → `create_trimesh_collision()` でコリジョン付与。

国土地理院 dem5a タイル (zoom≤15) を優先し、404 の場合は dem (zoom≤14) にフォールバックする。CSV の欠損値 `"e"` は `0.0` で補完（将来的に近傍補間へ改善予定）。

## テスト設計の方針

テストは3種類で構成される。新機能追加時はこの分類に従うこと:

- **機能テスト (ST/PY-01〜)**: 正常系の入出力検証
- **境界値テスト (BV/TG-)**: 倍率テーブルの閾値・クランプ上下限での挙動確認
- **耐久テスト (DU-)**: 長時間シミュレーション（28800フレーム = ゲーム内8時間相当）で値が `[0, 100]` を外れないことを確認

詳細は `docs/test/test_design.md` を参照。

## 将来フェーズで追加予定の機能

MVP（現在）は体力・水分の2パラメータのみ。以下はフェーズ2以降の予定であり、現時点では実装しないこと:

- パラメータ: 空腹・体温・バッテリー残量
- 行動種別: 走行・クライミング・休憩
- 地形: テクスチャ・LOD・ストリーミング隣接タイル
- イベント: 天候急変・道迷い・転倒・救助要請
- `is_downed` の解除（現在は不可）
