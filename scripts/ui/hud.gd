extends CanvasLayer
## HUD: プレイヤーのステータスを常時表示するUI

@onready var stamina_bar   : ProgressBar = $VBoxContainer/StaminaRow/StaminaBar
@onready var hydration_bar : ProgressBar = $VBoxContainer/HydrationRow/HydrationBar
@onready var stamina_label : Label       = $VBoxContainer/StaminaRow/Label
@onready var hydration_label: Label      = $VBoxContainer/HydrationRow/Label
@onready var warning_label : Label       = $WarningLabel
@onready var time_label    : Label       = $TimeLabel

var _player_stats : Node = null
var _game_time_sec : float = 0.0  # ゲーム内時刻（秒）
const GAME_TIME_SCALE := 60.0     # 現実1秒 = ゲーム内60秒（1分）


func _ready() -> void:
	warning_label.visible = false


func _process(delta: float) -> void:
	_game_time_sec += delta * GAME_TIME_SCALE
	_update_time_label()
	_update_warning()


func bind_player_stats(stats: Node) -> void:
	"""PlayerStatsノードをバインドしてシグナルを接続"""
	_player_stats = stats
	stats.stats_changed.connect(_on_stats_changed)
	_refresh_bars()


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


func _update_time_label() -> void:
	var hours   := int(_game_time_sec / 3600) % 24
	var minutes := int(_game_time_sec / 60) % 60
	time_label.text = "%02d:%02d" % [hours, minutes]


func _update_warning() -> void:
	if _player_stats == null:
		return
	var msg := ""
	if _player_stats.hydration < 20.0:
		msg = "⚠ 水分が危険なレベルです。水場を探してください。"
	elif _player_stats.stamina < 20.0:
		msg = "⚠ 体力が限界に近づいています。休憩を検討してください。"

	warning_label.text    = msg
	warning_label.visible = msg != ""


func _status_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Color.WHITE
	elif ratio > 0.25:
		return Color.YELLOW
	else:
		return Color.RED
