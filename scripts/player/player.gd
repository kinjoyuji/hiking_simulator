extends CharacterBody3D
## Player: プレイヤーの移動・入力・地形追従を管理する

const WALK_SPEED    := 3.0   # 平地歩行速度 (m/s)
const GRAVITY       := 9.8
const MOUSE_SENSITIVITY := 0.002

@onready var stats        : Node      = $PlayerStats
@onready var camera_pivot : Node3D    = $CameraPivot
@onready var camera       : Camera3D  = $CameraPivot/Camera3D
@onready var ray_cast     : RayCast3D = $SlopeCast

var _current_slope_deg : float = 0.0


func _ready() -> void:
	# 登山道は45°超の斜面もあるため、床判定の許容角度を広げる
	floor_max_angle = deg_to_rad(60.0)
	stats.player_downed.connect(_on_player_downed)


func _physics_process(delta: float) -> void:
	if stats.is_downed:
		return

	_apply_gravity(delta)
	var is_moving := _handle_movement()
	_update_slope()

	if Input.is_action_just_pressed("drink"):
		stats.drink()

	stats.apply_drain(delta, _current_slope_deg, is_moving)
	move_and_slide()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -PI / 3, PI / 3)


func _handle_movement() -> bool:
	"""入力に応じて水平速度を更新し、歩行中かどうかを返す"""
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * WALK_SPEED
		velocity.z = direction.z * WALK_SPEED
		return true

	velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
	velocity.z = move_toward(velocity.z, 0, WALK_SPEED)
	return false


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta


func _update_slope() -> void:
	"""レイキャストで足元の傾斜角度を取得"""
	if ray_cast.is_colliding():
		var normal := ray_cast.get_collision_normal()
		_current_slope_deg = rad_to_deg(normal.angle_to(Vector3.UP))
	else:
		_current_slope_deg = 0.0


func _on_player_downed(reason: String) -> void:
	velocity = Vector3.ZERO
	# GameManagerへ通知（シグナルで疎結合に保つ）
	get_tree().call_group("game_manager", "on_player_downed", reason)
