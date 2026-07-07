# PlayerStats モジュール 設計書

**対象ファイル**: `scripts/player/player_stats.gd`

---

## 1. 概要

プレイヤーの生理的状態（体力・水分）を管理し、
消耗計算・休憩回復・飲水・状態異常検知を担う単一責任クラス。

---

## 2. 責務と非責務

| 責務（このクラスがやること）           | 非責務（やらないこと）              |
|--------------------------------------|-----------------------------------|
| パラメータ値の保持・更新              | UI への描画                       |
| 消耗量の計算（重量・傾斜・天候・脱水考慮）| 入力イベントの処理             |
| 上限(100) / 下限(0) クランプ         | 地形データの取得                  |
| 行動不能判定とシグナル発火            | セーブ/ロード処理（将来フェーズ）  |
| 回復処理（飲水・休憩回復）            | 天候の判定（GameManagerが倍率を設定）|

---

## 3. パラメータ定義

| パラメータ    | 型    | 範囲     | 初期値 | 単位  |
|--------------|-------|----------|--------|-------|
| stamina      | float | [0, 100] | 100.0  | 無次元 |
| hydration    | float | [0, 100] | 100.0  | 無次元 |
| water_ml     | float | [0, ∞)   | 1500.0 | ml（手持ちの水）|
| weather_mult | float | ≥ 1.0    | 1.0    | 天候消耗倍率 |

---

## 4. 消耗計算式

### 4-0. 歩行中（is_moving = true）

```
stamina_drain/sec =
    (BASE_STAMINA_DRAIN × weight_multiplier(kg) × slope_multiplier(deg) × weather_mult
     + dehydration_penalty × (1 - hydration / MAX_HYDRATION))
    × delta

hydration_drain/sec = BASE_HYDRATION_DRAIN × weather_mult × delta
```

### 4-0b. 立ち止まり中（is_moving = false）— 「息を整える」

```
stamina_regen/sec = REST_STAMINA_REGEN (2.0) × (0.3 + 0.7 × hydration/100) × delta
hydration_drain/sec = BASE_HYDRATION_DRAIN × 0.3 × delta   # 基礎代謝分
```

脱水気味だと回復が鈍る。休憩しても水分は減り続けるため、
「休めば無限に粘れる」状態にはならない。

### 4-0c. 飲水（drink）

1回 150ml 消費して水分 +15。手持ちの水（water_ml）が尽きると失敗する。
持水量は計画フェーズの装備（MVP: 1500ml 固定）が上限。

### 4-1. 重量倍率テーブル

| ザック重量 (kg) | 倍率 |
|---------------|------|
| ≤ 5.0         | 1.0  |
| ≤ 10.0        | 1.2  |
| ≤ 15.0        | 1.5  |
| > 15.0        | 2.0  |

### 4-2. 傾斜倍率テーブル

| 傾斜角度 (°) | 倍率 |
|------------|------|
| ≤ 10       | 1.0  |
| ≤ 20       | 1.3  |
| ≤ 30       | 1.7  |
| > 30       | 2.2  |

### 4-3. 脱水ペナルティ

水分が0のとき、体力消耗に `DEHYDRATION_STAMINA_PENALTY (0.3/sec)` が追加される。
水分50%のときペナルティは半分 (`0.15/sec`)。

### 4-4. 天候倍率

`weather_mult` は GameManager（天候イベント）が設定する。雨天時 1.3。
体力・水分の両方の消耗に乗算される。デフォルト 1.0（晴れ）。

---

## 5. 状態遷移

```
[Normal]
  ├─ stamina → 0  →  player_downed("体力が尽きた。動けない。")
  └─ hydration → 0 →  player_downed("重度の脱水状態。意識が遠のく。")

[Downed]
  ├─ is_downed = true
  └─ apply_drain() は処理をスキップ（追加消耗なし）
```

---

## 6. 公開シグナル

| シグナル名       | 引数             | 発火タイミング                  |
|----------------|------------------|---------------------------------|
| stats_changed  | なし             | apply_drain / restore 呼び出し後 |
| player_downed  | reason: String   | stamina または hydration が 0以下 |

---

## 7. 公開メソッド

| メソッド                                        | 説明                                        |
|------------------------------------------------|---------------------------------------------|
| `apply_drain(delta, slope_deg, is_moving=true)`| 毎フレーム消耗を適用。is_moving=false で休憩回復 |
| `drink() → bool`                               | 水を一口飲む（150ml → 水分+15）。水切れで false |
| `restore_hydration(amount)`                    | 水分を amount 回復（上限100）               |
| `restore_stamina(amount)`                      | 体力を amount 回復（上限100）               |
| `get_stamina_ratio() → float`                  | stamina / MAX_STAMINA を返す                |
| `get_hydration_ratio() → float`                | hydration / MAX_HYDRATION を返す            |

---

## 8. 既知の制約・将来拡張

| 項目          | 現在の制約                    | 将来の拡張（フェーズ2以降）         |
|-------------|------------------------------|------------------------------------|
| パラメータ種別 | 体力・水分のみ                | 空腹・体温・バッテリー残量を追加    |
| 行動種別      | 歩行・立ち止まり休憩のみ      | 走行・クライミングの消耗差分        |
| 天候効果      | 消耗倍率のみ（雨 ×1.3）       | 気温・風・視界への影響              |
| is_downed 解除 | 解除不可（GameOverのみ）      | 救助イベントでの復活               |
