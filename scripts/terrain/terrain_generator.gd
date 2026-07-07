extends Node3D
## TerrainGenerator: 国土地理院の標高タイルデータからメッシュを生成する
##
## 標高タイルAPI仕様:
##   URL: https://cyberjapandata.gsi.go.jp/xyz/dem5a/{z}/{x}/{y}.txt
##   フォーマット: CSV（256行×256列, カンマ区切り, 単位:メートル）
##   ズームレベル: 15 が最高解像度（約1m/pixel相当）
##
## 生成完了時に terrain_ready を発火する。標高はタイル内最小標高を y=0 に
## 正規化してメッシュ化する（実標高は base_elevation で復元可能）。

## 地形生成完了。info = {
##   "spawn_position": Vector3,   # 最低標高点（登山口）のワールド座標
##   "summit_position": Vector3,  # 最高標高点（山頂）のワールド座標
##   "base_elevation": float,     # y=0 に対応する実標高（m）
##   "max_elevation": float,      # 実標高の最大値（m）
##   "is_fallback": bool,         # 通信失敗で代替地形を使ったか
## }
signal terrain_ready(info: Dictionary)

const GSI_ELEVATION_URL := "https://cyberjapandata.gsi.go.jp/xyz/dem5a/{z}/{x}/{y}.txt"
const TILE_RESOLUTION   := 256  # タイル1枚あたりのサンプル数
# zoom15 タイルの一辺は緯度35.6°付近で約1000m → 1000/256 ≈ 3.9m/サンプル。
# 実寸に合わせないと傾斜角が誇張され、勾配倍率テーブルの前提が崩れる。
const MESH_SCALE        := 3.9
const HEIGHT_SCALE      := 1.0  # 標高をそのままメートルで使用

var _http_request : HTTPRequest


func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	# タイムアウト無指定だと通信不能時に「地形データを取得中…」のまま無限に
	# 待ち続けてしまう。RESULT_TIMEOUTとして_on_request_completedに届かせ、
	# 既存のフォールバック経路へ合流させる
	_http_request.timeout = 10.0
	_http_request.request_completed.connect(_on_request_completed)


# ---------------------------------------------------------------------------
# 公開API
# ---------------------------------------------------------------------------

func generate_from_tile(zoom: int, tile_x: int, tile_y: int) -> void:
	"""指定タイルの標高データを取得してメッシュを生成する"""
	var url := GSI_ELEVATION_URL.format({"z": zoom, "x": tile_x, "y": tile_y})
	var err := _http_request.request(url)
	if err != OK:
		push_warning("標高タイルのリクエスト発行に失敗（オフライン？）。代替地形を生成します: err=%d" % err)
		_generate_fallback_terrain()


func latlon_to_tile(lat: float, lon: float, zoom: int) -> Vector2i:
	"""緯度経度をタイル座標に変換する（Webメルカトル）"""
	var n   := pow(2, zoom)
	var x   := int((lon + 180.0) / 360.0 * n)
	var lat_rad := deg_to_rad(lat)
	var y   := int((1.0 - log(tan(lat_rad) + 1.0 / cos(lat_rad)) / PI) / 2.0 * n)
	return Vector2i(x, y)


# ---------------------------------------------------------------------------
# メッシュ生成
# ---------------------------------------------------------------------------

func _build_terrain(elevation_data: Array, is_fallback: bool) -> void:
	"""標高データからメッシュ・コリジョンを生成し、terrain_ready を発火する"""
	var rows : int = elevation_data.size()
	var cols : int = elevation_data[0].size() if rows > 0 else 0
	if rows < 2 or cols < 2:
		push_error("標高データが不正です: rows=%d cols=%d" % [rows, cols])
		return

	# 最小・最大標高を求める（メッシュ正規化用は全域から）
	var min_h : float = elevation_data[0][0]
	var max_h : float = elevation_data[0][0]
	for row in range(rows):
		for col in range(cols):
			min_h = minf(min_h, elevation_data[row][col])
			max_h = maxf(max_h, elevation_data[row][col])

	# 登山口と山頂はタイル縁を避けて内側から選ぶ（縁だとメッシュ外へこぼれ落ちる）。
	# 登山口は「低くて、かつ足場が平らな」場所。最低点そのものは渓谷の
	# 急斜面であることが多く、スポーン地点に適さない。
	var margin := 8
	const SPAWN_MAX_SLOPE_DEG := 15.0
	var min_cell := Vector2i(margin, margin)
	var max_cell := Vector2i(margin, margin)
	var found_flat := false
	for row in range(margin, rows - margin):
		for col in range(margin, cols - margin):
			var h : float = elevation_data[row][col]
			if h > elevation_data[max_cell.y][max_cell.x]:
				max_cell = Vector2i(col, row)
			var is_lower : bool = (not found_flat) or h < elevation_data[min_cell.y][min_cell.x]
			if is_lower and _cell_slope_deg(elevation_data, col, row) <= SPAWN_MAX_SLOPE_DEG:
				min_cell = Vector2i(col, row)
				found_flat = true
	if not found_flat:
		# 平坦なセルが見つからず急斜面セルをそのまま使う（slope制約なしのフォールバック）。
		# ゲーム続行は可能だが、スポーン地点が急斜面になり得るため警告で可視化する
		push_warning("平坦な登山口が見つからないため急斜面セルを使用: slope制約なし")

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 頂点を打つ（y は最小標高基準に正規化。標高比で頂点カラーを付ける）
	var height_range := maxf(max_h - min_h, 1.0)
	for row in range(rows):
		for col in range(cols):
			var h : float = elevation_data[row][col]
			var t := (h - min_h) / height_range
			surface_tool.set_color(_elevation_color(t))
			surface_tool.set_uv(Vector2(float(col) / cols, float(row) / rows))
			surface_tool.add_vertex(Vector3(col * MESH_SCALE, (h - min_h) * HEIGHT_SCALE, row * MESH_SCALE))

	# インデックスを組む（2三角形 = 1クアッド）
	# 巻き順に注意: この順で法線が+y（上向き）になる。逆順だと面が裏返り、
	# 描画もコリジョンも下向き（上からのレイ・落下物が素通り）になる。
	for row in range(rows - 1):
		for col in range(cols - 1):
			var i := row * cols + col
			# 三角形1
			surface_tool.add_index(i)
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + cols)
			# 三角形2
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + cols + 1)
			surface_tool.add_index(i + cols)

	surface_tool.generate_normals()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface_tool.commit()

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true  # sRGB指定しないと色が明るく飛ぶ
	material.roughness = 1.0
	mesh_instance.material_override = material

	# コリジョン付与（プレイヤーが乗れるように）
	mesh_instance.create_trimesh_collision()
	add_child(mesh_instance)

	_scatter_props(elevation_data, min_h, max_h)

	terrain_ready.emit({
		"spawn_position": _cell_to_world(min_cell, elevation_data, min_h),
		"summit_position": _cell_to_world(max_cell, elevation_data, min_h),
		"base_elevation": min_h,
		"max_elevation": max_h,
		"is_fallback": is_fallback,
	})


func _cell_slope_deg(elevation_data: Array, col: int, row: int) -> float:
	"""4近傍との高低差から局所勾配（度）を概算する"""
	var h : float = elevation_data[row][col]
	var max_diff := 0.0
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n : float = elevation_data[row + offset.y][col + offset.x]
		max_diff = maxf(max_diff, absf(n - h))
	return rad_to_deg(atan(max_diff / MESH_SCALE))


func _cell_to_world(cell: Vector2i, elevation_data: Array, min_h: float) -> Vector3:
	var h : float = elevation_data[cell.y][cell.x]
	return Vector3(cell.x * MESH_SCALE, (h - min_h) * HEIGHT_SCALE, cell.y * MESH_SCALE)


func _elevation_color(t: float) -> Color:
	"""標高比 t (0=谷, 1=頂) に応じた地形カラー: 緑→茶→灰"""
	var forest := Color(0.13, 0.3, 0.1)
	var rock   := Color(0.32, 0.25, 0.16)
	var peak   := Color(0.42, 0.4, 0.38)
	if t < 0.7:
		return forest.lerp(rock, t / 0.7)
	return rock.lerp(peak, (t - 0.7) / 0.3)


# ---------------------------------------------------------------------------
# 植生・岩の散布（プロシージャル素材）
# ---------------------------------------------------------------------------

const TREE_COUNT      := 1200
const ROCK_COUNT      := 250
const TREELINE_RATIO  := 0.75  # 標高比がこれ以上の場所には木が生えない（森林限界）
const TREE_MAX_SLOPE  := 32.0
const PROP_SEED       := 4649  # 固定ルート(MVP): 配置を再現可能にする

func _scatter_props(elevation_data: Array, min_h: float, max_h: float) -> void:
	"""低ポリの木と岩をMultiMeshで地形上に散布する（コリジョンなし）"""
	var rows : int = elevation_data.size()
	var cols : int = elevation_data[0].size()
	var height_range := maxf(max_h - min_h, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = PROP_SEED

	var trunks   : Array[Transform3D] = []
	var canopies : Array[Transform3D] = []
	var rocks    : Array[Transform3D] = []

	var attempts := (TREE_COUNT + ROCK_COUNT) * 4
	for _i in range(attempts):
		if trunks.size() >= TREE_COUNT and rocks.size() >= ROCK_COUNT:
			break
		var col := rng.randi_range(2, cols - 3)
		var row := rng.randi_range(2, rows - 3)
		var h : float = elevation_data[row][col]
		var t := (h - min_h) / height_range
		var slope := _cell_slope_deg(elevation_data, col, row)
		var pos := Vector3(col * MESH_SCALE, (h - min_h) * HEIGHT_SCALE, row * MESH_SCALE)

		if t < TREELINE_RATIO and slope < TREE_MAX_SLOPE and trunks.size() < TREE_COUNT:
			var s := rng.randf_range(0.8, 1.6)
			var rot := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s))
			# 幹をやや沈めて、斜面でも根本が浮かないようにする
			trunks.append(Transform3D(rot, pos + Vector3(0, 0.8 * s, 0)))
			canopies.append(Transform3D(rot, pos + Vector3(0, 3.2 * s, 0)))
		elif (t >= 0.5 or slope >= 25.0) and rocks.size() < ROCK_COUNT:
			var rs := rng.randf_range(0.4, 1.5)
			var rb := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(rs, rs * 0.6, rs))
			rocks.append(Transform3D(rb, pos + Vector3(0, 0.2 * rs, 0)))

	# 幹: 茶色の円柱
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.18
	trunk_mesh.height = 2.2
	trunk_mesh.radial_segments = 5
	trunk_mesh.rings = 1
	trunk_mesh.material = _flat_material(Color(0.35, 0.24, 0.15))
	_add_multimesh(trunk_mesh, trunks)

	# 樹冠: 緑の円錐
	var canopy_mesh := CylinderMesh.new()
	canopy_mesh.top_radius = 0.01
	canopy_mesh.bottom_radius = 1.3
	canopy_mesh.height = 3.4
	canopy_mesh.radial_segments = 6
	canopy_mesh.rings = 1
	canopy_mesh.material = _flat_material(Color(0.13, 0.35, 0.16))
	_add_multimesh(canopy_mesh, canopies)

	# 岩: つぶれた低ポリ球
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.8
	rock_mesh.height = 1.2
	rock_mesh.radial_segments = 6
	rock_mesh.rings = 4
	rock_mesh.material = _flat_material(Color(0.5, 0.48, 0.46))
	_add_multimesh(rock_mesh, rocks)


func _add_multimesh(mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


# ---------------------------------------------------------------------------
# 代替地形（通信不可でもゲームを成立させる）
# ---------------------------------------------------------------------------

func _generate_fallback_terrain() -> void:
	"""ノイズベースの仮想の山を生成する"""
	var noise := FastNoiseLite.new()
	noise.seed = 351  # 固定ルート（MVP）: 毎回同じ山になるよう固定
	noise.frequency = 0.012

	var data : Array = []
	var center := TILE_RESOLUTION / 2.0
	for row in range(TILE_RESOLUTION):
		var line : Array = []
		for col in range(TILE_RESOLUTION):
			# 中央が高い山型 + ノイズで尾根・谷を作る
			var dist := Vector2(col - center, row - center).length() / center
			var base := maxf(1.0 - dist, 0.0) * 220.0
			var detail := (noise.get_noise_2d(col, row) + 1.0) * 40.0
			line.append(300.0 + base + detail)
		data.append(line)
	_build_terrain(data, true)


# ---------------------------------------------------------------------------
# HTTPレスポンス処理
# ---------------------------------------------------------------------------

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("標高タイルの取得に失敗。代替地形を生成します: result=%d code=%d" % [result, response_code])
		_generate_fallback_terrain()
		return

	var csv_text := body.get_string_from_utf8()
	var elevation_data := _parse_csv(csv_text)
	if elevation_data.size() < 2 or elevation_data[0].size() < 2:
		# 不正な200レスポンス（データ不足）をそのまま_build_terrainへ渡すと
		# push_errorのみでterrain_readyが発火せず、ロード画面で詰む
		push_warning("標高データの形式が不正なため代替地形を生成します: rows=%d" % elevation_data.size())
		_generate_fallback_terrain()
		return
	_build_terrain(elevation_data, false)


func _parse_csv(csv_text: String) -> Array:
	"""GSI標高CSVをパースして二次元配列で返す。欠損値('e')は0.0で補完。"""
	var result : Array = []
	for line in csv_text.strip_edges().split("\n"):
		if line.strip_edges() == "":
			continue
		var row : Array = []
		for cell in line.split(","):
			var trimmed := cell.strip_edges()
			row.append(0.0 if trimmed == "e" else float(trimmed))
		if row.size() > 0:
			result.append(row)
	return result
