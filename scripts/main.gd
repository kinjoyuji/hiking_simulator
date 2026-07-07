extends Node
## GameManager: ゲーム全体の進行・状態を管理する
## グループ名 "game_manager" でどこからでも参照可能

enum GameState {
	PLANNING,   # 計画フェーズ（出発前）
	HIKING,     # 行動フェーズ（山行中）
	EMERGENCY,  # 緊急フェーズ（トラブル発生）
	RESULT,     # リザルト（完了/ゲームオーバー）
}

# MVP: 入門コース（高尾山付近）の固定タイル
const COURSE_LAT  := 35.6252
const COURSE_LON  := 139.2437
const COURSE_ZOOM := 15

const GOAL_RADIUS := 8.0  # 山頂到達と見なす半径 (m)

# 天候急変イベント: この時間帯（現実秒）のどこかで雨が降り出す
const WEATHER_EVENT_MIN_SEC := 60.0
const WEATHER_EVENT_MAX_SEC := 150.0
const RAIN_DRAIN_MULT       := 1.3

var current_state : GameState = GameState.PLANNING

@onready var hud               : CanvasLayer = $HUD
@onready var player            : CharacterBody3D = $Player
@onready var terrain_generator : Node3D = $TerrainGenerator
@onready var result_panel      : Control = $ResultPanel
@onready var planning_panel    : Control = $PlanningPanel


func _ready() -> void:
	add_to_group("game_manager")
	hud.bind_player_stats(player.get_node("PlayerStats"))
	terrain_generator.terrain_ready.connect(_on_terrain_ready)
	_start_planning_phase()


func _input(event: InputEvent) -> void:
	# ESCでマウス解放、クリックで再キャプチャ（山行中のみ）
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed \
			and current_state == GameState.HIKING \
			and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ---------------------------------------------------------------------------
# フェーズ遷移
# ---------------------------------------------------------------------------

func _start_planning_phase() -> void:
	current_state = GameState.PLANNING
	planning_panel.visible = true
	player.set_physics_process(false)


func start_hiking() -> void:
	"""計画フェーズ完了 → 地形取得 → 行動フェーズ開始"""
	planning_panel.visible = false
	hud.set_status("地形データを取得中…")

	var tile: Vector2i = terrain_generator.latlon_to_tile(COURSE_LAT, COURSE_LON, COURSE_ZOOM)
	terrain_generator.generate_from_tile(COURSE_ZOOM, tile.x, tile.y)


func _on_terrain_ready(info: Dictionary) -> void:
	hud.set_status("")
	if info["is_fallback"]:
		hud.show_message("通信できないため仮想の山でプレイします", 5.0)

	# 登山口（最低標高点）にスポーン。山頂にゴールを設置
	player.global_position = info["spawn_position"] + Vector3.UP * 2.0
	_spawn_goal(info["summit_position"])
	hud.set_base_elevation(info["base_elevation"])
	hud.set_target(player, info["summit_position"], info["max_elevation"])

	current_state = GameState.HIKING
	player.set_physics_process(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	hud.set_clock_running(true)
	_start_wind_ambience()
	_schedule_weather_event()


func on_player_downed(reason: String) -> void:
	"""PlayerからGameOverを受け取る"""
	_show_result("行動不能", reason, _get_advice(reason))


func on_goal_reached() -> void:
	"""ゴール到達"""
	if current_state != GameState.HIKING:
		return
	_show_result(
		"登頂成功！",
		"山頂に到達しました。",
		"お疲れ様でした。本来は「安全に下山するまでが登山」です。\n体力の半分は下山のために残しておきましょう。"
	)


func _show_result(title: String, reason: String, advice: String) -> void:
	current_state = GameState.RESULT
	hud.set_clock_running(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	result_panel.visible = true
	result_panel.get_node("%TitleLabel").text = title
	result_panel.get_node("%ReasonLabel").text = reason
	result_panel.get_node("%AdviceLabel").text = advice


# ---------------------------------------------------------------------------
# ゴール判定
# ---------------------------------------------------------------------------

func _spawn_goal(summit: Vector3) -> void:
	"""山頂にゴールエリアと目印の標柱を設置する"""
	var goal_area := Area3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = GOAL_RADIUS
	cylinder.height = 20.0
	shape.shape = cylinder
	goal_area.add_child(shape)

	# 目印: 遠くからでも見える赤い標柱
	var marker := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.5
	pole.bottom_radius = 0.5
	pole.height = 30.0
	marker.mesh = pole
	marker.position.y = 15.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.15, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.15, 0.1)
	mat.emission_energy_multiplier = 0.6
	marker.material_override = mat
	goal_area.add_child(marker)

	goal_area.position = summit
	goal_area.body_entered.connect(_on_goal_body_entered)
	add_child(goal_area)


func _on_goal_body_entered(body: Node3D) -> void:
	if body == player:
		on_goal_reached()


func _start_wind_ambience() -> void:
	var wind_player: AudioStreamPlayer = $WindPlayer
	var stream := wind_player.stream as AudioStreamWAV
	if stream:
		# WAV自体にループチャンクを持たせていないため、ここでループ指定する
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = stream.data.size() / 2  # 16bitモノラル: 2バイト=1フレーム
	wind_player.play()


# ---------------------------------------------------------------------------
# 天候急変イベント（MVP: 雨で消耗増加のみ）
# ---------------------------------------------------------------------------

func _schedule_weather_event() -> void:
	var delay := randf_range(WEATHER_EVENT_MIN_SEC, WEATHER_EVENT_MAX_SEC)
	get_tree().create_timer(delay).timeout.connect(_on_weather_changed)


func _on_weather_changed() -> void:
	if current_state != GameState.HIKING:
		return
	player.get_node("PlayerStats").weather_mult = RAIN_DRAIN_MULT
	hud.show_message("雨が降り出した… 体力の消耗が早くなる。", 6.0)
	hud.set_weather("雨")


# ---------------------------------------------------------------------------
# 教育的フィードバック
# ---------------------------------------------------------------------------

func _get_advice(reason: String) -> String:
	if "脱水" in reason:
		return "【振り返り】水分は30分に一口以上補給しましょう。のどが渇いたと感じた時点で既に脱水が始まっています。"
	elif "体力" in reason:
		return "【振り返り】体力配分は重要です。登りに体力を使いすぎると下山できなくなります。\n「引き返し点」を事前に決め、それ以上消耗した場合は必ず下山しましょう。\n立ち止まって休憩すれば体力は回復します。"
	return "【振り返り】山では無理をせず、余裕を持った計画を立てることが大切です。"


func _on_start_button_pressed() -> void:
	start_hiking()


func _on_retry_button_pressed() -> void:
	get_tree().reload_current_scene()
