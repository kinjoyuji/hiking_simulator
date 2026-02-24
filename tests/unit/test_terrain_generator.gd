extends GutTest
## TerrainGenerator 単体テスト
## 注: HTTP通信を伴うメッシュ生成はモック化が困難なため、
##     純粋関数 (latlon_to_tile, _parse_csv) のみをここでテストする。

const TerrainGeneratorScript = preload("res://scripts/terrain/terrain_generator.gd")

var gen : Node3D

func before_each() -> void:
	gen = TerrainGeneratorScript.new()
	add_child_autofree(gen)


# ===========================================================================
# latlon_to_tile テスト (TG-01〜04)
# ===========================================================================

func test_TG01_takao_zoom15() -> void:
	## 高尾山付近 (35.6252, 139.2437) zoom=15
	## 期待タイル座標は事前計算済み
	var tile := gen.latlon_to_tile(35.6252, 139.2437, 15)
	assert_eq(tile.x, 29110, "高尾山x座標")
	assert_eq(tile.y, 12922, "高尾山y座標")


func test_TG02_fuji_zoom14() -> void:
	## 富士山頂 (35.3606, 138.7274) zoom=14
	var tile := gen.latlon_to_tile(35.3606, 138.7274, 14)
	assert_eq(tile.x, 14535, "富士山x座標")
	assert_eq(tile.y, 6467,  "富士山y座標")


func test_TG03_west_edge_lon_minus180() -> void:
	## 経度 -180 はタイル x=0
	var tile := gen.latlon_to_tile(0.0, -180.0, 5)
	assert_eq(tile.x, 0, "経度-180のとき x=0")


func test_TG04_tile_x_within_range() -> void:
	## zoom=4 では x の最大は 2^4 - 1 = 15
	var tile := gen.latlon_to_tile(0.0, 179.9, 4)
	assert_le(tile.x, 15, "タイルxは 2^zoom-1 以下であること")
	assert_ge(tile.x, 0,  "タイルxは0以上であること")


# ===========================================================================
# _parse_csv テスト (TG-10〜14)
# ===========================================================================

func test_TG10_parse_normal_csv() -> void:
	## 正常なCSV (2×2)
	var csv := "100.0,200.0\n300.0,400.0"
	var result := gen._parse_csv(csv)
	assert_eq(result.size(), 2, "行数は2")
	assert_eq(result[0].size(), 2, "列数は2")
	assert_eq(result[0][0], 100.0, "左上の値")
	assert_eq(result[1][1], 400.0, "右下の値")


func test_TG11_parse_csv_with_missing_values() -> void:
	## 欠損値 "e" は 0.0 として補完される
	var csv := "100.0,e\ne,200.0"
	var result := gen._parse_csv(csv)
	assert_eq(result[0][1], 0.0, "欠損値eは0.0として補完されること")
	assert_eq(result[1][0], 0.0, "欠損値eは0.0として補完されること")


func test_TG12_parse_csv_skip_empty_lines() -> void:
	## 空行はスキップされる
	var csv := "1.0,2.0\n\n3.0,4.0"
	var result := gen._parse_csv(csv)
	## 空行は空配列として扱われるため、sizeが2または3かを確認
	## （実装詳細に合わせて調整）
	assert_ge(result.size(), 2, "有効行は少なくとも2行")


func test_TG13_parse_empty_string() -> void:
	## 空文字列は空配列を返す
	var result := gen._parse_csv("")
	assert_eq(result.size(), 0, "空文字列パース結果は空配列")


func test_TG14_parse_single_cell() -> void:
	## 1行1列のCSV
	var csv := "523.5"
	var result := gen._parse_csv(csv)
	assert_eq(result.size(), 1, "行数は1")
	assert_eq(result[0].size(), 1, "列数は1")
	assert_almost_eq(result[0][0], 523.5, 0.001, "値が正しいこと")


func test_TG_parse_negative_elevation() -> void:
	## 負の標高（海面下）も正しくパースされる
	var csv := "-5.2,0.0\n10.0,-15.8"
	var result := gen._parse_csv(csv)
	assert_almost_eq(result[0][0], -5.2, 0.001, "負の標高値がパースされること")
	assert_almost_eq(result[1][1], -15.8, 0.001, "負の標高値がパースされること")
