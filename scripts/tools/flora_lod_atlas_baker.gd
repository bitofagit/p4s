extends RefCounted
class_name FloraLodAtlasBaker

## Downscales the full flora atlas into low-res PNG tiers for far-zoom rendering.
## Output: res://assets/base/sprites/atlas/lod/
##   flora_atlas_lod_mid.png  — 50% detail centred in each 200 px cell
##   flora_atlas_lod_far.png  — 25% detail centred in each 200 px cell
##   flora_lod_map.json       — tier paths + zoom thresholds (shared tile coords)

const FULL_ATLAS_PATH := "res://assets/base/sprites/atlas/flora_atlas.png"
const FULL_MAP_PATH := "res://data/flora_atlas_map.json"
const LOD_DIR := "res://assets/base/sprites/atlas/lod"
const LOD_MAP_PATH := "res://data/flora_lod_map.json"

const TIERS: Array[Dictionary] = [
	{
		"id": "mid",
		"filename": "flora_atlas_lod_mid.png",
		"inner_scale": 0.5,
		"full_zoom_min": 0.20,
	},
	{
		"id": "far",
		"filename": "flora_atlas_lod_far.png",
		"inner_scale": 0.25,
		"full_zoom_min": 0.0,
	},
]


static func bake() -> Dictionary:
	if not FileAccess.file_exists(FULL_ATLAS_PATH):
		push_error("FloraLodAtlasBaker: run bake_flora_atlas.gd first — missing %s" % FULL_ATLAS_PATH)
		return {"ok": false}

	var full_img := Image.load_from_file(ProjectSettings.globalize_path(FULL_ATLAS_PATH))
	if full_img == null or full_img.is_empty():
		push_error("FloraLodAtlasBaker: could not load %s" % FULL_ATLAS_PATH)
		return {"ok": false}

	var meta: Dictionary = {}
	if FileAccess.file_exists(FULL_MAP_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FULL_MAP_PATH))
		if parsed is Dictionary:
			meta = parsed

	var tile_sz := int(meta.get("tile_size", 200))
	var cols := int(meta.get("columns", full_img.get_width() / tile_sz))
	var rows := int(meta.get("rows", full_img.get_height() / tile_sz))
	_ensure_dir(LOD_DIR)

	var tier_reports: Array[Dictionary] = []
	for tier in TIERS:
		var inner_scale: float = float(tier["inner_scale"])
		var inner_sz := maxi(int(round(float(tile_sz) * inner_scale)), 8)
		var out := Image.create(cols * tile_sz, rows * tile_sz, false, Image.FORMAT_RGBA8)
		out.fill(Color(0, 0, 0, 0))

		for row in range(rows):
			for col in range(cols):
				var src_rect := Rect2i(col * tile_sz, row * tile_sz, tile_sz, tile_sz)
				var cell := full_img.get_region(src_rect)
				cell.resize(inner_sz, inner_sz, Image.INTERPOLATE_LANCZOS)
				var dest := Vector2i(col * tile_sz, row * tile_sz)
				var offset := Vector2i((tile_sz - inner_sz) / 2, (tile_sz - inner_sz) / 2)
				out.blit_rect(cell, Rect2i(0, 0, inner_sz, inner_sz), dest + offset)

		var out_path: String = LOD_DIR.path_join(str(tier["filename"]))
		var err := out.save_png(ProjectSettings.globalize_path(out_path))
		if err != OK:
			push_error("FloraLodAtlasBaker: failed to save %s (%s)" % [out_path, err])
			return {"ok": false}
		tier_reports.append({
			"id": tier["id"],
			"path": out_path,
			"inner_scale": inner_scale,
		})
		print("FloraLodAtlasBaker: wrote %s (%dx%d cells, inner %d px)" % [
			out_path, cols, rows, inner_sz,
		])

	var full_zoom := 0.38
	var manifest := {
		"version": 1,
		"source_atlas": FULL_ATLAS_PATH,
		"tile_size": tile_sz,
		"columns": cols,
		"rows": rows,
		"full_zoom_min": full_zoom,
		"tiers": [],
		"baked_at": Time.get_datetime_string_from_system(),
	}
	for i in range(TIERS.size()):
		var tier_def: Dictionary = TIERS[i]
		var next_min := 0.0
		if i + 1 < TIERS.size():
			next_min = float(TIERS[i + 1]["full_zoom_min"])
		manifest["tiers"].append({
			"id": tier_def["id"],
			"atlas_path": LOD_DIR.path_join(str(tier_def["filename"])),
			"inner_scale": tier_def["inner_scale"],
			"zoom_min": float(tier_def["full_zoom_min"]),
			"zoom_max": full_zoom if i == 0 else float(TIERS[i - 1]["full_zoom_min"]),
		})

	var map_err := FileAccess.open(
		ProjectSettings.globalize_path(LOD_MAP_PATH), FileAccess.WRITE
	)
	if map_err:
		map_err.store_string(JSON.stringify(manifest, "\t") + "\n")
		map_err.close()

	print("FloraLodAtlasBaker: wrote %s (%d tiers)" % [LOD_MAP_PATH, manifest["tiers"].size()])
	print("FloraLodAtlasBaker: run `godot --headless --path . --import` so Godot registers the new PNGs.")
	return {"ok": true, "tiers": tier_reports, "map": LOD_MAP_PATH}


static func _ensure_dir(res_path: String) -> void:
	var abs := ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(abs)
