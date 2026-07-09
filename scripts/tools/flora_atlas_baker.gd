extends RefCounted
class_name FloraAtlasBaker

## Offline 2D grid atlas baker for flora stage sprites (200 px cells).

const FLORA_BASE := "res://assets/base/sprites/flora"
const USER_STAGE_DIR := "user://databases/sprites/stages/"
const ATLAS_OUT_PATH := "res://assets/base/sprites/atlas/flora_atlas.png"
const MAP_OUT_PATH := "res://data/flora_atlas_map.json"

const COLUMNS := 14
const ROWS := 15
const TILE_SIZE := 200
const CANOPY_COMPOSE_SIZE := int(TILE_SIZE * 1.2)
const UNDERSTORY_COMPOSE_SIZE := int(150 * 0.9)


static func bake() -> Dictionary:
	var pd := preload("res://data/data_plants.gd")
	pd.get_plant_data("")

	var plant_ids: Array[String] = []
	for key in pd.DATA.keys():
		plant_ids.append(str(key))
	plant_ids.sort()

	var atlas := Image.create(COLUMNS * TILE_SIZE, ROWS * TILE_SIZE, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))

	var tiles: Dictionary = {}
	var slot := 0
	var png_count := 0
	var placeholder_count := 0

	for plant_id in plant_ids:
		var row_data: Dictionary = pd.get_plant_data(plant_id)
		# Layer from plants_v3.csv (ground / understory / canopy) drives cluster composition.
		var layer := str(row_data.get("layer", "ground")).to_lower()
		tiles[plant_id] = {}

		for stage in range(6):
			var col := slot % COLUMNS
			var row := slot / COLUMNS
			var dest := Vector2i(col * TILE_SIZE, row * TILE_SIZE)
			var cell := _resolve_cell_image(plant_id, stage, layer)

			if cell["source"] == "png":
				png_count += 1
			else:
				placeholder_count += 1

			atlas.blit_rect(cell["image"], Rect2i(0, 0, TILE_SIZE, TILE_SIZE), dest)
			tiles[plant_id][str(stage)] = [col, row]
			slot += 1

	_ensure_dir("res://assets/base/sprites/atlas")
	var atlas_err := atlas.save_png(ProjectSettings.globalize_path(ATLAS_OUT_PATH))
	if atlas_err != OK:
		push_error("FloraAtlasBaker: failed to save atlas (%s)" % atlas_err)

	var manifest := {
		"version": 1,
		"columns": COLUMNS,
		"rows": ROWS,
		"tile_size": TILE_SIZE,
		"atlas_path": ATLAS_OUT_PATH,
		"baked_at": Time.get_datetime_string_from_system(),
		"species_count": plant_ids.size(),
		"png_cells": png_count,
		"placeholder_cells": placeholder_count,
		"tiles": tiles,
	}
	var map_json := JSON.stringify(manifest, "\t")
	var map_file := FileAccess.open(MAP_OUT_PATH, FileAccess.WRITE)
	if map_file == null:
		push_error("FloraAtlasBaker: cannot write %s" % MAP_OUT_PATH)
	else:
		map_file.store_string(map_json)

	print(
		"FloraAtlasBaker: %dx%d atlas, %d species, %d PNG + %d placeholder cells -> %s"
		% [COLUMNS, ROWS, plant_ids.size(), png_count, placeholder_count, ATLAS_OUT_PATH]
	)
	return manifest


static func _resolve_cell_image(plant_id: String, stage: int, layer: String) -> Dictionary:
	var layer_key := layer.to_lower()
	var png_path := PlantGrowth.stage_sprite_path(plant_id, stage)
	var src: Image = null
	var source_kind := "placeholder"
	if png_path != "":
		src = _load_source_png(png_path)
		if src != null:
			source_kind = "png"
	if src == null:
		src = _make_placeholder_source(layer_key)
	return {
		"image": _compose_cell_from_source(src, layer_key),
		"source": source_kind,
		"path": png_path,
	}


static func _load_source_png(path: String) -> Image:
	var img: Image = null
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex:
				img = tex.get_image()
		if img == null:
			var fs_path := ProjectSettings.globalize_path(path)
			if FileAccess.file_exists(fs_path):
				img = Image.load_from_file(fs_path)
	else:
		if FileAccess.file_exists(path):
			img = Image.load_from_file(path)
	if img == null:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func _compose_cell_from_source(source: Image, layer: String) -> Image:
	var cell := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	cell.fill(Color(0, 0, 0, 0))
	match layer:
		"ground":
			var cluster := source.duplicate()
			cluster.resize(65, 65, Image.INTERPOLATE_NEAREST)
			var placements: Array[Vector2i] = [
				Vector2i(0, 130), Vector2i(30, 135), Vector2i(60, 125),
				Vector2i(90, 135), Vector2i(115, 130), Vector2i(135, 135),
			]
			for dest in placements:
				cell.blend_rect(cluster, Rect2i(0, 0, 65, 65), dest)
		"understory":
			var cluster := source.duplicate()
			cluster.resize(UNDERSTORY_COMPOSE_SIZE, UNDERSTORY_COMPOSE_SIZE, Image.INTERPOLATE_NEAREST)
			for dest: Vector2i in [Vector2i(30, 20), Vector2i(50, 45)]:
				cell.blend_rect(cluster, Rect2i(0, 0, UNDERSTORY_COMPOSE_SIZE, UNDERSTORY_COMPOSE_SIZE), dest)
		_:
			var full := source.duplicate()
			if full.get_size() != Vector2i(CANOPY_COMPOSE_SIZE, CANOPY_COMPOSE_SIZE):
				full.resize(CANOPY_COMPOSE_SIZE, CANOPY_COMPOSE_SIZE, Image.INTERPOLATE_NEAREST)
			var canopy_dest := Vector2i(
				(TILE_SIZE - CANOPY_COMPOSE_SIZE) / 2,
				(TILE_SIZE - CANOPY_COMPOSE_SIZE) / 2,
			)
			cell.blend_rect(full, Rect2i(0, 0, CANOPY_COMPOSE_SIZE, CANOPY_COMPOSE_SIZE), canopy_dest)
	return cell


## Small coloured patch used when no PNG exists — composed into clusters like real sprites.
static func _make_placeholder_source(layer: String) -> Image:
	match layer:
		"canopy":
			var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			img.fill_rect(Rect2i(25, 13, 150, 94), Color("2e7d32", 0.5))
			img.fill_rect(Rect2i(88, 106, 25, 94), Color("5d4037", 0.8))
			return img
		"understory":
			var u := Image.create(UNDERSTORY_COMPOSE_SIZE, UNDERSTORY_COMPOSE_SIZE, false, Image.FORMAT_RGBA8)
			u.fill(Color(0, 0, 0, 0))
			u.fill_rect(Rect2i(18, 36, 99, 81), Color("f9a825", 1.0))
			return u
		_:
			var g := Image.create(65, 65, false, Image.FORMAT_RGBA8)
			g.fill(Color(0, 0, 0, 0))
			g.fill_rect(Rect2i(8, 45, 50, 18), Color("00e5ff", 1.0))
			return g


static func _make_placeholder(layer: String) -> Image:
	return _compose_cell_from_source(_make_placeholder_source(layer.to_lower()), layer.to_lower())


static func _ensure_dir(res_path: String) -> void:
	var abs := ProjectSettings.globalize_path(res_path)
	if not DirAccess.dir_exists_absolute(abs):
		DirAccess.make_dir_recursive_absolute(abs)
