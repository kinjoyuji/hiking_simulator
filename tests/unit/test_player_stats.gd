extends GutTest
## PlayerStats 単体テスト
##
## 実行方法:
##   Godot エディタ上で GUT プラグインを使用して実行
##   または: godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/

const PlayerStatsScript = preload("res://scripts/player/player_stats.gd")

var stats : Node

func before_each() -> void:
	stats = PlayerStatsScript.new()
	add_child_autofree(stats)


# ===========================================================================
# 機能テスト (ST)
# ===========================================================================

func test_ST01_initial_stamina_is_100() -> void:
	assert_eq(stats.stamina, 100.0, "初期体力は100.0であること")


func test_ST02_initial_hydration_is_100() -> void:
	assert_eq(stats.hydration, 100.0, "初期水分は100.0であること")


func test_ST03_apply_drain_decreases_stamina() -> void:
	stats.apply_drain(1.0, 0.0)
	assert_lt(stats.stamina, 100.0, "apply_drain後にstaminaが減少すること")


func test_ST04_apply_drain_decreases_hydration() -> void:
	stats.apply_drain(1.0, 0.0)
	assert_lt(stats.hydration, 100.0, "apply_drain後にhydrationが減少すること")


func test_ST05_restore_hydration_increases_value() -> void:
	stats.hydration = 30.0
	stats.restore_hydration(20.0)
	assert_eq(stats.hydration, 50.0, "restore_hydration後に水分が回復すること")


func test_ST06_restore_stamina_increases_value() -> void:
	stats.stamina = 40.0
	stats.restore_stamina(30.0)
	assert_eq(stats.stamina, 70.0, "restore_stamina後に体力が回復すること")


func test_ST07_apply_drain_emits_stats_changed() -> void:
	watch_signals(stats)
	stats.apply_drain(1.0, 0.0)
	assert_signal_emitted(stats, "stats_changed", "apply_drain後にstats_changedが発火すること")


func test_ST08_apply_drain_skipped_when_downed() -> void:
	stats.is_downed = true
	var prev_stamina: float = stats.stamina
	var prev_hydration: float = stats.hydration
	stats.apply_drain(100.0, 0.0)
	assert_eq(stats.stamina, prev_stamina, "ダウン中はstaminaが変化しないこと")
	assert_eq(stats.hydration, prev_hydration, "ダウン中はhydrationが変化しないこと")


func test_ST09_dehydration_increases_stamina_drain() -> void:
	# 水分十分な状態
	stats.stamina = 100.0
	stats.hydration = 100.0
	stats.apply_drain(1.0, 0.0)
	var stamina_after_hydrated: float = stats.stamina

	# 水分枯渇状態でリセット
	var stats2 = PlayerStatsScript.new()
	add_child_autofree(stats2)
	stats2.stamina = 100.0
	stats2.hydration = 0.0
	stats2.apply_drain(1.0, 0.0)
	var stamina_after_dehydrated: float = stats2.stamina

	assert_lt(stamina_after_dehydrated, stamina_after_hydrated,
		"水分枯渇時は体力消耗が大きいこと")


func test_ST10_steeper_slope_increases_stamina_drain() -> void:
	# 10度
	var s1 = PlayerStatsScript.new()
	add_child_autofree(s1)
	s1.apply_drain(1.0, 10.0)
	var drain_10deg: float = 100.0 - s1.stamina

	# 20度
	var s2 = PlayerStatsScript.new()
	add_child_autofree(s2)
	s2.apply_drain(1.0, 20.0)
	var drain_20deg: float = 100.0 - s2.stamina

	assert_gt(drain_20deg, drain_10deg, "傾斜が大きいほど体力消耗が大きいこと")


func test_ST11_heavier_pack_increases_stamina_drain() -> void:
	# 5kg
	var s1 = PlayerStatsScript.new()
	add_child_autofree(s1)
	s1.pack_weight_kg = 5.0
	s1.apply_drain(1.0, 0.0)
	var drain_5kg: float = 100.0 - s1.stamina

	# 15kg
	var s2 = PlayerStatsScript.new()
	add_child_autofree(s2)
	s2.pack_weight_kg = 15.0
	s2.apply_drain(1.0, 0.0)
	var drain_15kg: float = 100.0 - s2.stamina

	assert_gt(drain_15kg, drain_5kg, "重いザックほど体力消耗が大きいこと")


# ===========================================================================
# 境界値テスト (BV)
# ===========================================================================

func test_BV01_stamina_zero_triggers_player_downed() -> void:
	watch_signals(stats)
	stats.stamina = 0.0
	stats.apply_drain(0.001, 0.0)  # 微小消耗でちょうど0に到達させる
	# 直接0にしてチェック
	stats.stamina = 0.0
	stats._check_downed()
	assert_signal_emitted(stats, "player_downed", "stamina=0でplayer_downedが発火すること")


func test_BV02_hydration_zero_triggers_player_downed() -> void:
	watch_signals(stats)
	stats.hydration = 0.0
	stats._check_downed()
	assert_signal_emitted(stats, "player_downed", "hydration=0でplayer_downedが発火すること")


func test_BV03_restore_hydration_cannot_exceed_max() -> void:
	stats.hydration = 90.0
	stats.restore_hydration(50.0)  # 140になるはずだがクランプされる
	assert_eq(stats.hydration, 100.0, "水分は100を超えないこと")


func test_BV04_restore_stamina_cannot_exceed_max() -> void:
	stats.stamina = 90.0
	stats.restore_stamina(50.0)
	assert_eq(stats.stamina, 100.0, "体力は100を超えないこと")


func test_BV05_stamina_cannot_go_below_zero() -> void:
	stats.apply_drain(99999.0, 0.0)
	assert_gte(stats.stamina, 0.0, "体力は0未満にならないこと")


func test_BV05b_hydration_cannot_go_below_zero() -> void:
	stats.apply_drain(99999.0, 0.0)
	assert_gte(stats.hydration, 0.0, "水分は0未満にならないこと")


func test_BV06_weight_at_boundary_5kg() -> void:
	var mult: float = stats._get_weight_multiplier(5.0)
	assert_eq(mult, 1.0, "5.0kg のとき倍率は1.0")


func test_BV07_weight_just_over_5kg() -> void:
	var mult: float = stats._get_weight_multiplier(5.001)
	assert_eq(mult, 1.2, "5.001kg のとき倍率は1.2")


func test_BV08_slope_at_boundary_10deg() -> void:
	var mult: float = stats._get_slope_multiplier(10.0)
	assert_eq(mult, 1.0, "10.0度のとき倍率は1.0")


func test_BV09_slope_just_over_10deg() -> void:
	var mult: float = stats._get_slope_multiplier(10.001)
	assert_eq(mult, 1.3, "10.001度のとき倍率は1.3")


func test_BV10_slope_90deg() -> void:
	var mult: float = stats._get_slope_multiplier(90.0)
	assert_eq(mult, 2.2, "90度(崖)のとき倍率は2.2")


func test_BV11_player_downed_fires_only_once() -> void:
	watch_signals(stats)
	stats.stamina = 0.0
	stats._check_downed()
	stats._check_downed()  # 2回目は発火しないはず
	stats._check_downed()  # 3回目も発火しないはず
	assert_signal_emit_count(stats, "player_downed", 1, "player_downedは1回のみ発火すること")


# ===========================================================================
# 耐久テスト (DU)
# ===========================================================================

func test_DU01_8hours_game_time_stays_in_range() -> void:
	## ゲーム内8時間 = delta=1.0 を 28800回 適用
	## すべての値が [0, 100] に収まることを確認
	for _i in range(28800):
		if stats.is_downed:
			break
		stats.apply_drain(1.0, 0.0)
	assert_gte(stats.stamina, 0.0,   "8時間後もstaminaは0以上")
	assert_lte(stats.stamina, 100.0, "8時間後もstaminaは100以下")
	assert_gte(stats.hydration, 0.0,   "8時間後もhydrationは0以上")
	assert_lte(stats.hydration, 100.0, "8時間後もhydrationは100以下")


func test_DU02_long_walk_eventually_downs_player() -> void:
	## 補給なしで歩き続けると最終的に体力が尽きてダウンする
	for _i in range(10000):
		if stats.is_downed:
			break
		stats.apply_drain(1.0, 0.0)
	assert_true(stats.is_downed, "補給なしの長時間歩行で最終的にダウンすること")
	assert_eq(stats.stamina, 0.0, "ダウン時にstaminaが0であること")


func test_DU03_tiny_delta_no_underflow() -> void:
	## 極小 delta で10000回 → 負数にならない
	for _i in range(10000):
		stats.apply_drain(0.001, 0.0)
	assert_gte(stats.stamina, 0.0, "極小delta連続適用後もstaminaは0以上")
	assert_gte(stats.hydration, 0.0, "極小delta連続適用後もhydrationは0以上")


func test_DU04_huge_delta_no_underflow() -> void:
	## 極大 delta 1回 → 負数にならない（クランプ保証）
	stats.apply_drain(10.0, 90.0)
	assert_gte(stats.stamina, 0.0, "極大deltaでもstaminaは0以上")
	assert_gte(stats.hydration, 0.0, "極大deltaでもhydrationは0以上")


func test_DU05_repeated_restore_no_overflow() -> void:
	## restore_hydration を10000回繰り返しても100を超えない
	stats.hydration = 0.0
	for _i in range(10000):
		stats.restore_hydration(10.0)
	assert_eq(stats.hydration, 100.0, "繰り返しrestoreでもhydrationは100を超えない")


# ===========================================================================
# 飲水・休憩・天候テスト (ST12〜 / BV12)
# ===========================================================================

func test_ST12_drink_restores_hydration_and_consumes_water() -> void:
	stats.hydration = 50.0
	var prev_water: float = stats.water_ml
	var ok: bool = stats.drink()
	assert_true(ok, "水が残っていればdrinkは成功する")
	assert_gt(stats.hydration, 50.0, "drink後に水分が回復すること")
	assert_lt(stats.water_ml, prev_water, "drink後に手持ちの水が減ること")


func test_ST13_drink_fails_when_water_empty() -> void:
	stats.water_ml = 0.0
	stats.hydration = 50.0
	var ok: bool = stats.drink()
	assert_false(ok, "水が尽きていればdrinkは失敗する")
	assert_eq(stats.hydration, 50.0, "水分は変化しないこと")


func test_ST14_resting_recovers_stamina() -> void:
	stats.stamina = 50.0
	stats.apply_drain(1.0, 0.0, false)  # 立ち止まり
	assert_gt(stats.stamina, 50.0, "立ち止まり中は体力が回復すること")


func test_ST15_resting_still_drains_hydration() -> void:
	stats.apply_drain(1.0, 0.0, false)
	assert_lt(stats.hydration, 100.0, "立ち止まり中も水分は消耗すること")


func test_ST16_weather_multiplier_increases_drain() -> void:
	var s1 = PlayerStatsScript.new()
	add_child_autofree(s1)
	s1.apply_drain(1.0, 0.0)
	var drain_sunny: float = 100.0 - s1.stamina

	var s2 = PlayerStatsScript.new()
	add_child_autofree(s2)
	s2.weather_mult = 1.3
	s2.apply_drain(1.0, 0.0)
	var drain_rainy: float = 100.0 - s2.stamina

	assert_gt(drain_rainy, drain_sunny, "雨天時は体力消耗が大きいこと")


func test_BV12_rest_regen_cannot_exceed_max() -> void:
	stats.stamina = 99.9
	for _i in range(100):
		stats.apply_drain(1.0, 0.0, false)
	assert_lte(stats.stamina, 100.0, "休憩回復でも体力は100を超えないこと")
