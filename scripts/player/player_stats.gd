extends Node
## PlayerStats: プレイヤーの全パラメータを管理するクラス
## MVPスコープ: 体力・水分のみ。後のフェーズで空腹・バッテリー・体温を追加する。

signal stats_changed
signal player_downed(reason: String)

# --- パラメータ定義 ---
const MAX_STAMINA    := 100.0
const MAX_HYDRATION  := 100.0

var stamina   : float = MAX_STAMINA
var hydration : float = MAX_HYDRATION

# --- 消耗レート（1秒あたり）---
# ゲーム内1秒 = 現実の数分に相当するよう、後でTimeManagerで調整する
const BASE_STAMINA_DRAIN_PER_SEC   := 0.5   # 平地歩行時の基本消耗
const BASE_HYDRATION_DRAIN_PER_SEC := 0.3   # 基本水分消耗

# 重量倍率テーブル（ザック重量 kg → 消耗倍率）
const WEIGHT_MULTIPLIERS := [
	{"max_kg": 5.0,  "multiplier": 1.0},
	{"max_kg": 10.0, "multiplier": 1.2},
	{"max_kg": 15.0, "multiplier": 1.5},
	{"max_kg": 999.0,"multiplier": 2.0},
]

# 勾配による消耗倍率（傾斜角度 degrees → 倍率）
const SLOPE_MULTIPLIERS := [
	{"max_deg": 10.0, "multiplier": 1.0},
	{"max_deg": 20.0, "multiplier": 1.3},
	{"max_deg": 30.0, "multiplier": 1.7},
	{"max_deg": 999.0,"multiplier": 2.2},
]

# 水分不足時の追加体力消耗（水分が低いほど体力消耗が増える）
const DEHYDRATION_STAMINA_PENALTY := 0.3  # 水分0時に加算される追加消耗/sec

# 立ち止まり中の回復・消耗（「歩みを止めて息を整える」を再現）
const REST_STAMINA_REGEN_PER_SEC   := 2.0  # 停止中の体力回復
const REST_HYDRATION_DRAIN_FACTOR  := 0.3  # 停止中も水分は基礎代謝分消耗する

# 飲水1回あたりの量（手持ちの水は有限。計画フェーズの持水量が上限）
const DRINK_AMOUNT_ML       := 150.0
const HYDRATION_PER_100ML   := 10.0

var pack_weight_kg : float = 8.0    # 初期ザック重量
var water_ml       : float = 1500.0 # 手持ちの水（ml）
var weather_mult   : float = 1.0    # 天候による消耗倍率（雨・強風で上昇）
var is_downed      : bool  = false


func _ready() -> void:
	stamina   = MAX_STAMINA
	hydration = MAX_HYDRATION


func apply_drain(delta: float, slope_degrees: float = 0.0, is_moving: bool = true) -> void:
	"""毎フレーム呼ばれる消耗処理。is_moving=false（立ち止まり）中は体力が回復する"""
	if is_downed:
		return

	if is_moving:
		var weight_mult := _get_weight_multiplier(pack_weight_kg)
		var slope_mult  := _get_slope_multiplier(abs(slope_degrees))

		# 水分消耗
		var hydration_drain := BASE_HYDRATION_DRAIN_PER_SEC * weather_mult * delta
		hydration = maxf(hydration - hydration_drain, 0.0)

		# 体力消耗（重量・勾配・天候・水分不足を考慮）
		var dehydration_penalty := DEHYDRATION_STAMINA_PENALTY * (1.0 - hydration / MAX_HYDRATION)
		var stamina_drain := (BASE_STAMINA_DRAIN_PER_SEC * weight_mult * slope_mult * weather_mult + dehydration_penalty) * delta
		stamina = maxf(stamina - stamina_drain, 0.0)
	else:
		# 立ち止まり: 息を整えて体力回復。水分は基礎代謝分だけ消耗
		hydration = maxf(hydration - BASE_HYDRATION_DRAIN_PER_SEC * REST_HYDRATION_DRAIN_FACTOR * delta, 0.0)
		var regen_scale := 0.3 + 0.7 * (hydration / MAX_HYDRATION)  # 脱水気味だと回復が鈍る
		stamina = minf(stamina + REST_STAMINA_REGEN_PER_SEC * regen_scale * delta, MAX_STAMINA)

	stats_changed.emit()
	_check_downed()


func drink() -> bool:
	"""手持ちの水を一口飲む。水が尽きていれば false"""
	if is_downed or water_ml <= 0.0:
		return false
	var amount := minf(DRINK_AMOUNT_ML, water_ml)
	water_ml -= amount
	restore_hydration(amount / 100.0 * HYDRATION_PER_100ML)
	return true


func restore_hydration(amount: float) -> void:
	"""水分補給"""
	hydration = minf(hydration + amount, MAX_HYDRATION)
	stats_changed.emit()


func restore_stamina(amount: float) -> void:
	"""体力回復（休憩など）"""
	stamina = minf(stamina + amount, MAX_STAMINA)
	stats_changed.emit()


func get_stamina_ratio() -> float:
	return stamina / MAX_STAMINA


func get_hydration_ratio() -> float:
	return hydration / MAX_HYDRATION


# --- private ---

func _check_downed() -> void:
	# 同一フレームで両方0になった場合、脱水は医学的に体力消耗より優先度の高い
	# 原因のため、脱水の教育的アドバイスを優先して表示する
	if hydration <= 0.0:
		_trigger_downed("重度の脱水状態。意識が遠のく。")
	elif stamina <= 0.0:
		_trigger_downed("体力が尽きた。動けない。")


func _trigger_downed(reason: String) -> void:
	if is_downed:
		return
	is_downed = true
	player_downed.emit(reason)


func _get_weight_multiplier(kg: float) -> float:
	for entry in WEIGHT_MULTIPLIERS:
		if kg <= entry["max_kg"]:
			return entry["multiplier"]
	return 2.0


func _get_slope_multiplier(deg: float) -> float:
	for entry in SLOPE_MULTIPLIERS:
		if deg <= entry["max_deg"]:
			return entry["multiplier"]
	return 2.2
