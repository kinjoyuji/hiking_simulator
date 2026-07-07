extends SceneTree
## ヘッドレス・スモークテスト: メインシーンをゲームループごと実行して検証する
##
## 実行方法:
##   godot --headless -s tests/smoke/smoke_main.gd
##
## 検証項目:
##   1. メインシーンがエラーなくロードできる
##   2. start_hiking → terrain_ready が発火する（オフライン時は代替地形）
##   3. プレイヤーが地形の上に立つ（すり抜け落下しない）
##   4. 歩行で体力・水分が消耗する
##   5. 山頂ゴールに入ると登頂リザルトが表示される

var _failures := 0


func _init() -> void:
	await process_frame
	_run()


func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_check(scene.current_state == scene.GameState.PLANNING, "初期状態はPLANNING")

	var terrain: Node3D = scene.get_node("TerrainGenerator")
	var player: CharacterBody3D = scene.get_node("Player")
	var stats: Node = player.get_node("PlayerStats")

	scene.start_hiking()
	var info: Dictionary = await terrain.terrain_ready
	print("  terrain_ready: fallback=%s base=%.1fm max=%.1fm" %
		[info["is_fallback"], info["base_elevation"], info["max_elevation"]])
	await process_frame
	_check(scene.current_state == scene.GameState.HIKING, "地形生成後はHIKING")

	# 物理を安定させ、プレイヤーが地形上に着地することを確認
	for _i in range(120):
		await physics_frame
	var spawn: Vector3 = info["spawn_position"]
	_check(player.global_position.y > spawn.y - 5.0,
		"プレイヤーが地形をすり抜けていない (y=%.2f, spawn.y=%.2f)" % [player.global_position.y, spawn.y])
	_check(player.is_on_floor(), "プレイヤーが接地している")

	# 前進入力をシミュレートして消耗を確認
	Input.action_press("move_forward")
	for _i in range(60):
		await physics_frame
	Input.action_release("move_forward")
	_check(stats.stamina < 100.0, "歩行で体力が消耗する (stamina=%.2f)" % stats.stamina)
	_check(stats.hydration < 100.0, "歩行で水分が消耗する (hydration=%.2f)" % stats.hydration)

	# 飲水
	var hy_before: float = stats.hydration
	stats.drink()
	_check(stats.hydration > hy_before, "飲水で水分が回復する")

	# 山頂へテレポートしてゴール判定を確認
	var summit: Vector3 = info["summit_position"]
	player.global_position = summit + Vector3.UP * 1.0
	for _i in range(30):
		await physics_frame
	_check(scene.current_state == scene.GameState.RESULT, "山頂到達でRESULTになる")
	_check(scene.get_node("ResultPanel").visible, "リザルトパネルが表示される")

	if _failures == 0:
		print("SMOKE TEST: ALL PASSED")
	else:
		print("SMOKE TEST: %d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] " + label)
	else:
		print("  [FAIL] " + label)
		_failures += 1
