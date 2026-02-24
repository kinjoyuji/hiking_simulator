extends Node3D
## TerrainGenerator: 国土地理院の標高タイルデータからメッシュを生成する
##
## 標高タイルAPI仕様:
##   URL: https://cyberjapandata.gsi.go.jp/xyz/dem5a/{z}/{x}/{y}.txt
##   フォーマット: CSV（256行×256列, カンマ区切り, 単位:メートル）
##   ズームレベル: 15 が最高解像度（約1m/pixel相当）

const GSI_ELEVATION_URL := "https://cyberjapandata.gsi.go.jp/xyz/dem5a/{z}/{x}/{y}.txt"
const TILE_RESOLUTION   := 256  # タイル1枚あたりのサンプル数
const MESH_SCALE        := 2.0  # 1サンプル = 2m（水平）
const HEIGHT_SCALE      := 1.0  # 標高をそのままメートルで使用

var _http_request : HTTPRequest
var _pending_tiles : Dictionary = {}  # {tile_key: callback}


func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


# ---------------------------------------------------------------------------
# 公開API
# ---------------------------------------------------------------------------

func generate_from_tile(zoom: int, tile_x: int, tile_y: int) -> void:
	"""指定タイルの標高データを取得してメッシュを生成する"""
	var url := GSI_ELEVATION_URL.format({"z": zoom, "x": tile_x, "y": tile_y})
	var tile_key := "%d_%d_%d" % [zoom, tile_x, tile_y]
	_pending_tiles[url] = tile_key
	_http_request.request(url)


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

func _build_terrain_mesh(elevation_data: Array) -> MeshInstance3D:
	"""標高データ（256×256の二次元配列）からMeshを生成する"""
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rows : int = elevation_data.size()
	var cols : int = elevation_data[0].size() if rows > 0 else 0

	# 頂点を打つ
	for row in range(rows):
		for col in range(cols):
			var h : float = elevation_data[row][col]
			var vx := col * MESH_SCALE
			var vz := row * MESH_SCALE
			surface_tool.set_uv(Vector2(float(col) / cols, float(row) / rows))
			surface_tool.add_vertex(Vector3(vx, h * HEIGHT_SCALE, vz))

	# インデックスを組む（2三角形 = 1クアッド）
	for row in range(rows - 1):
		for col in range(cols - 1):
			var i := row * cols + col
			# 三角形1
			surface_tool.add_index(i)
			surface_tool.add_index(i + cols)
			surface_tool.add_index(i + 1)
			# 三角形2
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + cols)
			surface_tool.add_index(i + cols + 1)

	surface_tool.generate_normals()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface_tool.commit()

	# コリジョン付与（プレイヤーが乗れるように）
	mesh_instance.create_trimesh_collision()

	return mesh_instance


# ---------------------------------------------------------------------------
# HTTPレスポンス処理
# ---------------------------------------------------------------------------

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("標高タイルの取得に失敗しました: result=%d code=%d" % [result, response_code])
		return

	var csv_text := body.get_string_from_utf8()
	var elevation_data := _parse_csv(csv_text)
	var mesh_instance  := _build_terrain_mesh(elevation_data)
	add_child(mesh_instance)


func _parse_csv(csv_text: String) -> Array:
	"""GSI標高CSVをパースして二次元配列で返す。欠損値('e')は0.0で補完。"""
	var result : Array = []
	for line in csv_text.strip_edges().split("\n"):
		var row : Array = []
		for cell in line.split(","):
			var trimmed := cell.strip_edges()
			row.append(0.0 if trimmed == "e" else float(trimmed))
		if row.size() > 0:
			result.append(row)
	return result
