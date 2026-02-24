extends Node
## GameManager: ゲーム全体の進行・状態を管理する
## グループ名 "game_manager" でどこからでも参照可能

enum GameState {
	PLANNING,   # 計画フェーズ（出発前）
	HIKING,     # 行動フェーズ（山行中）
	EMERGENCY,  # 緊急フェーズ（トラブル発生）
	RESULT,     # リザルト（完了/ゲームオーバー）
}

var current_state : GameState = GameState.PLANNING

@onready var hud               : CanvasLayer = $HUD
@onready var player            : CharacterBody3D = $Player
@onready var terrain_generator : Node3D = $TerrainGenerator
@onready var result_panel      : Control = $ResultPanel
@onready var planning_panel    : Control = $PlanningPanel


func _ready() -> void:
	add_to_group("game_manager")
	hud.bind_player_stats(player.get_node("PlayerStats"))
	_start_planning_phase()


# ---------------------------------------------------------------------------
# フェーズ遷移
# ---------------------------------------------------------------------------

func _start_planning_phase() -> void:
	current_state = GameState.PLANNING
	planning_panel.visible = true
	player.set_physics_process(false)


func start_hiking() -> void:
	"""計画フェーズ完了 → 行動フェーズ開始"""
	current_state = GameState.HIKING
	planning_panel.visible = false
	player.set_physics_process(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# MVP: 入門コースのタイル（高尾山付近）を読み込む
	# ズーム15, 緯度35.6252, 経度139.2437
	var tile: Vector2i = terrain_generator.latlon_to_tile(35.6252, 139.2437, 15)
	terrain_generator.generate_from_tile(15, tile.x, tile.y)


func on_player_downed(reason: String) -> void:
	"""PlayerからGameOverを受け取る"""
	current_state = GameState.RESULT
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	result_panel.visible = true
	result_panel.get_node("TitleLabel").text = "行動不能"
	result_panel.get_node("ReasonLabel").text = reason
	result_panel.get_node("AdviceLabel").text = _get_advice(reason)


func on_goal_reached() -> void:
	"""ゴール到達"""
	current_state = GameState.RESULT
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	result_panel.visible = true
	result_panel.get_node("TitleLabel").text = "下山完了！"
	result_panel.get_node("ReasonLabel").text = "無事に登山を終えました。"
	result_panel.get_node("AdviceLabel").text = "お疲れ様でした。計画通りに行動できたことが成功の鍵です。"


# ---------------------------------------------------------------------------
# 教育的フィードバック
# ---------------------------------------------------------------------------

func _get_advice(reason: String) -> String:
	if "脱水" in reason:
		return "【振り返り】水分は30分に一口以上補給しましょう。のどが渇いたと感じた時点で既に脱水が始まっています。"
	elif "体力" in reason:
		return "【振り返り】体力配分は重要です。登りに体力を使いすぎると下山できなくなります。\n「引き返し点」を事前に決め、それ以上消耗した場合は必ず下山しましょう。"
	return "【振り返り】山では無理をせず、余裕を持った計画を立てることが大切です。"
