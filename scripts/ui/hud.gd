extends CanvasLayer
## HUD: プレイヤーのステータスを常時表示するUI

@onready var stamina_bar     : ProgressBar = $StatsBox/StaminaRow/StaminaBar
@onready var hydration_bar   : ProgressBar = $StatsBox/HydrationRow/HydrationBar
@onready var water_label     : Label = $StatsBox/WaterLabel
@onready var warning_label   : Label = $WarningLabel
@onready var message_label   : Label = $MessageLabel
@onready var status_label    : Label = $StatusLabel
@onready var time_label      : Label = $InfoBox/TimeLabel
@onready var elevation_label : Label = $InfoBox/ElevationLabel
@onready var weather_label   : Label = $InfoBox/WeatherLabel
@onready var goal_label      : Label = $InfoBox/GoalLabel
@onready var help_panel      : PanelContainer = $HelpPanel

var _player_stats : Node = null
var _player : Node3D = null
var _summit_position := Vector3.ZERO
var _base_elevation : float = 0.0
var _max_elevation : float = 0.0
var _clock_running := false
var _message_tween : Tween = null

var _game_time_sec : float = 6.0 * 3600.0  # ゲーム内時刻。朝6時出発
const GAME_TIME_SCALE := 60.0              # 現実1秒 = ゲーム内60秒（1分）


func _ready() -> void:
	warning_label.visible = false
	message_label.visible = false
	status_label.visible = false
	_update_time_label()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		help_panel.visible = not help_panel.visible


func _process(delta: float) -> void:
	if _clock_running:
		_game_time_sec += delta * GAME_TIME_SCALE
		_update_time_label()
	_update_warning()
	_update_location_info()


# ---------------------------------------------------------------------------
# GameManagerから呼ばれる公開API
# ---------------------------------------------------------------------------

func bind_player_stats(stats: Node) -> void:
	"""PlayerStatsノードをバインドしてシグナルを接続"""
	_player_stats = stats
	stats.stats_changed.connect(_on_stats_changed)
	_refresh_bars()


func set_status(msg: String) -> void:
	"""画面中央のステータス表示（ローディング等）。空文字で消える"""
	status_label.text = msg
	status_label.visible = msg != ""


func show_message(msg: String, duration_sec: float = 4.0) -> void:
	"""一定時間で消えるイベントメッセージ"""
	# 前のメッセージのhideコールバックが新しいメッセージを消してしまわないよう、
	# 古いtweenは先に破棄する
	if _message_tween and _message_tween.is_valid():
		_message_tween.kill()
	message_label.text = msg
	message_label.visible = true
	_message_tween = create_tween()
	_message_tween.tween_interval(duration_sec)
	_message_tween.tween_callback(func() -> void: message_label.visible = false)


func set_clock_running(running: bool) -> void:
	_clock_running = running


func set_base_elevation(elevation_m: float) -> void:
	_base_elevation = elevation_m


func set_target(player: Node3D, summit_position: Vector3, max_elevation_m: float) -> void:
	_player = player
	_summit_position = summit_position
	_max_elevation = max_elevation_m


func set_weather(weather_name: String) -> void:
	weather_label.text = "天候: %s" % weather_name


# ---------------------------------------------------------------------------
# 表示更新
# ---------------------------------------------------------------------------

func _on_stats_changed() -> void:
	_refresh_bars()


func _refresh_bars() -> void:
	if _player_stats == null:
		return

	var st: float = _player_stats.get_stamina_ratio()
	var hy: float = _player_stats.get_hydration_ratio()

	stamina_bar.value   = st * 100.0
	hydration_bar.value = hy * 100.0

	# 値が低いときにバーの色を変える
	stamina_bar.modulate   = _status_color(st)
	hydration_bar.modulate = _status_color(hy)

	water_label.text = "残りの水: %dml (Eで飲む)" % int(_player_stats.water_ml)


func _update_time_label() -> void:
	var hours   := int(_game_time_sec / 3600) % 24
	var minutes := int(_game_time_sec / 60) % 60
	time_label.text = "%02d:%02d" % [hours, minutes]


func _update_location_info() -> void:
	if _player == null:
		return
	var elevation := _base_elevation + _player.global_position.y
	elevation_label.text = "標高 %dm / 山頂 %dm" % [int(elevation), int(_max_elevation)]

	var to_summit := _summit_position - _player.global_position
	to_summit.y = 0.0
	goal_label.text = "山頂まで %dm" % int(to_summit.length())


func _update_warning() -> void:
	if _player_stats == null:
		return
	var msg := ""
	if _player_stats.hydration < 20.0:
		msg = "⚠ 水分が危険なレベルです。水を飲んでください (E)"
	elif _player_stats.stamina < 20.0:
		msg = "⚠ 体力が限界に近づいています。立ち止まって休憩を"

	warning_label.text    = msg
	warning_label.visible = msg != ""


func _status_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Color.WHITE
	elif ratio > 0.25:
		return Color.YELLOW
	else:
		return Color.RED
