# テスト設計書

---

## 1. テスト方針

| 目標                         | 手法                                      |
|-----------------------------|------------------------------------------|
| ロジックの正確性の保証        | GUT (Godot Unit Test) による単体テスト    |
| 外部APIの実行可能性の検証     | Python unittest + requests モック         |
| パラメータ異常系の防御        | 境界値分析・同値分割                       |
| 長時間プレイの安定性の確認    | 耐久テスト（シミュレーション）             |
| ゲームループ一気通貫の確認    | ヘッドレス・スモークテスト（実シーン実行） |

---

## 2. テストスコープ

```
tests/
├── unit/
│   ├── test_player_stats.gd       # PlayerStats 単体テスト (GUT)
│   └── test_terrain_generator.gd  # TerrainGenerator パース単体テスト (GUT)
├── smoke/
│   └── smoke_main.gd              # メインシーンのヘッドレス・スモークテスト
└── tools/
    └── test_fetch_elevation.py    # 標高APIテスト (Python unittest)
```

---

## 3. PlayerStats テスト設計

### 3-1. 機能テスト

| ID    | テストケース                               | 期待結果                             |
|-------|------------------------------------------|--------------------------------------|
| ST-01 | 初期化後の stamina が 100.0 であること      | stamina == 100.0                     |
| ST-02 | 初期化後の hydration が 100.0 であること   | hydration == 100.0                   |
| ST-03 | apply_drain を呼ぶと stamina が減少する    | stamina < 100.0                      |
| ST-04 | apply_drain を呼ぶと hydration が減少する  | hydration < 100.0                    |
| ST-05 | restore_hydration(50) で水分が回復する     | hydration が増加する                 |
| ST-06 | restore_stamina(50) で体力が回復する       | stamina が増加する                   |
| ST-07 | apply_drain 後に stats_changed が発火する  | シグナルが1回発火                    |
| ST-08 | is_downed=true のとき apply_drain は無効   | 値が変化しない                       |
| ST-09 | 水分不足時に体力消耗が増加する              | 水分100時より消耗が大きい            |
| ST-10 | 傾斜が大きいほど体力消耗が増加する          | 20° > 10° の消耗                     |
| ST-11 | ザックが重いほど体力消耗が増加する          | 15kg > 5kg の消耗                    |
| ST-12 | drink で水分回復・手持ちの水が減る          | hydration 増・water_ml 減            |
| ST-13 | 水切れ時の drink は失敗する                | false を返し hydration 不変          |
| ST-14 | 立ち止まり中は体力が回復する                | apply_drain(…, false) で stamina 増  |
| ST-15 | 立ち止まり中も水分は消耗する                | hydration 減                         |
| ST-16 | 天候倍率で体力消耗が増加する                | weather_mult=1.3 > 1.0 の消耗        |

### 3-2. 境界値テスト

| ID    | テストケース                              | 期待結果                              |
|-------|------------------------------------------|---------------------------------------|
| BV-01 | stamina が 0 のとき player_downed 発火    | シグナル発火、reason に "体力" を含む |
| BV-02 | hydration が 0 のとき player_downed 発火  | シグナル発火、reason に "脱水" を含む |
| BV-03 | restore_hydration で100を超えない         | hydration == 100.0 (クランプ)         |
| BV-04 | restore_stamina で100を超えない           | stamina == 100.0 (クランプ)           |
| BV-05 | stamina/hydration が負数にならない        | 最小値 0.0                            |
| BV-06 | pack_weight_kg = 5.0 (境界値) の倍率     | multiplier == 1.0                     |
| BV-07 | pack_weight_kg = 5.001 (境界値+ε) の倍率 | multiplier == 1.2                     |
| BV-08 | slope_degrees = 10.0 の倍率             | multiplier == 1.0                     |
| BV-09 | slope_degrees = 10.001 の倍率           | multiplier == 1.3                     |
| BV-10 | slope_degrees = 90.0 (崖) の倍率        | multiplier == 2.2                     |
| BV-11 | player_downed が2回目以降は発火しない     | シグナルは合計1回のみ                 |
| BV-12 | 休憩回復でも体力が100を超えない            | stamina ≤ 100.0 (クランプ)           |

### 3-3. 耐久テスト (シミュレーション)

| ID    | テストケース                                  | 期待結果                          |
|-------|----------------------------------------------|----------------------------------|
| DU-01 | 8時間ゲーム内時間 (delta=1.0 × 28800回) の連続消耗 | stamina, hydration が [0, 100] 内 |
| DU-02 | 補給なしで歩き続ける                           | 最終的に is_downed / stamina == 0  |
| DU-03 | 極小 delta (0.001) で10000回 apply_drain       | 値が負にならない                  |
| DU-04 | 極大 delta (10.0) を1回 apply_drain            | 値が負にならない（クランプ保証）   |
| DU-05 | restore_hydration を 10000回繰り返す           | hydration が 100.0 を超えない     |

---

## 4. TerrainGenerator テスト設計

### 4-1. latlon_to_tile（純粋関数）

| ID    | テストケース                                  | 期待結果                   |
|-------|----------------------------------------------|--------------------------|
| TG-01 | 高尾山 (35.6252, 139.2437) zoom=15           | 特定のタイル座標           |
| TG-02 | 富士山頂 (35.3606, 138.7274) zoom=14         | 特定のタイル座標           |
| TG-03 | 経度 -180 (西端)                              | tile_x == 0              |
| TG-04 | 経度 +180 (東端)                              | tile_x == 2^zoom - 1 付近 |

### 4-2. CSVパース（_parse_csv）

| ID    | テストケース                                  | 期待結果                   |
|-------|----------------------------------------------|--------------------------|
| TG-10 | 正常なCSVデータ (数値のみ)                    | 正しい二次元配列           |
| TG-11 | 欠損値 "e" を含むCSV                          | 0.0 として補完             |
| TG-12 | 空行を含むCSV                                 | 空行はスキップ             |
| TG-13 | 空文字列を渡した場合                          | 空配列を返す               |
| TG-14 | 1行1列のCSV                                   | [[値]] を返す              |

---

## 5. Python 標高APIテスト設計

### 5-1. 機能テスト（オンライン）

| ID    | テストケース                                  | 期待結果                            |
|-------|----------------------------------------------|-------------------------------------|
| PY-01 | 高尾山付近のタイル取得 (zoom=14)             | HTTP 200、256行のデータ             |
| PY-02 | 返されるデータの行数が256であること           | len(data) == 256                    |
| PY-03 | 各行の列数が256であること                    | all(len(row)==256 for row in data)  |
| PY-04 | 標高値が現実的な範囲内であること             | -100 ≤ value ≤ 4000 (日本の高低差) |

### 5-2. 機能テスト（オフライン・モック）

| ID    | テストケース                                  | 期待結果                            |
|-------|----------------------------------------------|-------------------------------------|
| PY-10 | 正常CSVのパース                               | 正しい数値配列                      |
| PY-11 | "e" を含むCSVのパース                         | None または 0.0 として処理           |
| PY-12 | HTTP 404 のとき低解像度にフォールバック       | フォールバックURLに再リクエスト      |
| PY-13 | HTTP 500 のとき None を返す                   | 戻り値が None                       |
| PY-14 | タイムアウト例外のとき None を返す            | 戻り値が None                       |
| PY-15 | latlon_to_tile の精度検証                    | 既知のタイル座標と一致              |

---

## 6. スモークテスト設計（tests/smoke/smoke_main.gd）

メインシーンをヘッドレスのゲームループごと実行し、一気通貫で検証する。
GSI API に到達できない環境では代替地形で自動続行する。

| 検証項目                                   |
|--------------------------------------------|
| メインシーンがエラーなくロードできる        |
| start_hiking → terrain_ready が発火する    |
| プレイヤーが地形上に着地する（すり抜けない）|
| 歩行入力で体力・水分が消耗する              |
| 飲水で水分が回復する                        |
| 山頂ゴール進入で RESULT に遷移する          |

---

## 7. テスト実行方法

### GUT (Godot 単体テスト)
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gprefix=test_ -gsuffix=.gd -gexit
```

### スモークテスト
```bash
godot --headless -s tests/smoke/smoke_main.gd
```

### Python
```bash
python3 -m pytest tests/tools/ -v -m "not online"   # オフライン（通常開発）
python3 -m pytest tests/tools/ -v                    # オンライン込み
```

### 注意: GDScript テストの書き方

- GUT 9.5 の比較アサートは `assert_gte` / `assert_lte`（`assert_ge/le` は存在しない）
- 動的型の戻り値を `:=` で受けると Godot 4 ではパースエラーになる。
  `var x: float = stats.stamina` のように明示型で受けること
- `latlon_to_tile` 系の期待値は `tools/fetch_elevation.py` と同一式で算出した値を使う

---

## 7. カバレッジ目標

| モジュール              | ライン カバレッジ目標 | ブランチ カバレッジ目標 |
|-----------------------|---------------------|----------------------|
| PlayerStats           | ≥ 95%               | ≥ 90%                |
| TerrainGenerator パース | ≥ 90%             | ≥ 85%                |
| 標高APIツール (Python) | ≥ 90%               | ≥ 85%                |

---

## 8. テスト環境

| 項目              | 内容                                |
|-----------------|-------------------------------------|
| GUT バージョン    | 9.x (Godot 4 対応)                 |
| Python バージョン | 3.11+                              |
| 依存パッケージ    | requests, unittest, unittest.mock  |
| CI 実行条件       | push / PR 時に Python テストを実行  |
