extends RefCounted
class_name PlantGrowth

## Universal 6-stage growth model for plant visuals and maturity timing.

const STAGE_NAMES: Array[String] = [
	"Sown", "Seedling", "Vegetative", "Flowering", "Mature", "Senescence",
]
const FLORA_BASE := "res://assets/base/sprites/flora"
const USER_STAGE_DIR := "user://databases/sprites/stages/"
const FLORA_ATLAS_MAP_PATH := "res://data/flora_atlas_map.json"

const DEFAULT_DAYS_TO_MATURE := 10
const DEFAULT_DAYS_TO_SENESCENCE := 15

static var _atlas_map: Dictionary = {}
static var _atlas_map_loaded := false


static func days_to_mature(plant_data: Dictionary) -> int:
	return maxi(1, int(plant_data.get("days_to_mature", plant_data.get("mature_turn", DEFAULT_DAYS_TO_MATURE))))


static func days_to_senescence(plant_data: Dictionary) -> int:
	var mature := days_to_mature(plant_data)
	var fallback := maxi(mature + 1, DEFAULT_DAYS_TO_SENESCENCE)
	return maxi(mature + 1, int(plant_data.get("days_to_senescence", fallback)))


static func growth_stage(plant_id: String, current_age: float) -> int:
	var row: Dictionary = preload("res://data/data_plants.gd").get_plant_data(plant_id)
	if row.is_empty():
		return 0
	return growth_stage_from_data(row, current_age)


static func growth_stage_from_data(plant_data: Dictionary, current_age: float) -> int:
	var mature := days_to_mature(plant_data)
	var senesce := days_to_senescence(plant_data)
	if current_age <= 0.0:
		return 0
	if current_age < float(mature) * 0.33:
		return 1
	if current_age < float(mature) * 0.66:
		return 2
	if current_age < float(mature):
		return 3
	if current_age < float(senesce):
		return 4
	return 5


## Pre-baked flora grid coordinate from data/flora_atlas_map.json (offline baker).
static func flora_atlas_coord(plant_id: String, stage: int) -> Vector2i:
	_ensure_atlas_map()
	var stage_idx := clampi(stage, 0, 5)
	var tiles: Dictionary = _atlas_map.get("tiles", {})
	var per_plant: Variant = tiles.get(plant_id, {})
	if per_plant is Dictionary:
		var stages: Dictionary = per_plant
		if stages.has(str(stage_idx)):
			var arr: Array = stages[str(stage_idx)]
			return Vector2i(int(arr[0]), int(arr[1]))
		var best_key := ""
		var best_dist := 999
		for key in stages.keys():
			var dist := absi(int(key) - stage_idx)
			if dist < best_dist:
				best_dist = dist
				best_key = str(key)
		if best_key != "":
			var fallback: Array = stages[best_key]
			return Vector2i(int(fallback[0]), int(fallback[1]))
	return Vector2i(-1, -1)


static func flora_atlas_meta() -> Dictionary:
	_ensure_atlas_map()
	return _atlas_map


const FLORA_LOD_MAP_PATH := "res://data/flora_lod_map.json"
static var _lod_map: Dictionary = {}
static var _lod_map_loaded := false


static func flora_lod_meta() -> Dictionary:
	_ensure_lod_map()
	return _lod_map


static func flora_full_zoom_min() -> float:
	_ensure_lod_map()
	if _lod_map.is_empty():
		return 0.38
	return float(_lod_map.get("full_zoom_min", 0.38))


## Returns "" (use full atlas), "mid", or "far" for the active LOD tile set.
static func flora_lod_tier_for_zoom(zoom: float) -> String:
	_ensure_lod_map()
	if _lod_map.is_empty():
		return ""
	var full_min := flora_full_zoom_min()
	if zoom >= full_min:
		return ""
	for tier_v in _lod_map.get("tiers", []):
		if not tier_v is Dictionary:
			continue
		var tier: Dictionary = tier_v
		var zmin := float(tier.get("zoom_min", 0.0))
		var zmax := float(tier.get("zoom_max", full_min))
		if zoom >= zmin and zoom < zmax:
			return str(tier.get("id", ""))
	var tiers: Array = _lod_map.get("tiers", [])
	if tiers.is_empty():
		return ""
	return str((tiers[tiers.size() - 1] as Dictionary).get("id", ""))


static func flora_lod_atlas_path(tier_id: String) -> String:
	_ensure_lod_map()
	for tier_v in _lod_map.get("tiers", []):
		if not tier_v is Dictionary:
			continue
		var tier: Dictionary = tier_v
		if str(tier.get("id", "")) == tier_id:
			return str(tier.get("atlas_path", ""))
	return ""


## Stable per-plant colour for far-zoom vector LOD shapes.
static func flora_lod_vector_colour(plant_id: String, layer_key: String) -> Color:
	var hue := float(plant_id.hash() % 360) / 360.0
	var base := Color.from_hsv(hue, 0.45, 0.72, 0.88)
	match layer_key:
		"canopy":
			return base.darkened(0.15)
		"understory":
			return base
		"ground":
			return base.lightened(0.12)
		_:
			return base


static func _ensure_lod_map() -> void:
	if _lod_map_loaded:
		return
	_lod_map_loaded = true
	if not FileAccess.file_exists(FLORA_LOD_MAP_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FLORA_LOD_MAP_PATH))
	if parsed is Dictionary:
		_lod_map = parsed


static func _ensure_atlas_map() -> void:
	if _atlas_map_loaded:
		return
	_atlas_map_loaded = true
	if not FileAccess.file_exists(FLORA_ATLAS_MAP_PATH):
		push_warning("PlantGrowth: missing %s — run scripts/tools/bake_flora_atlas.gd" % FLORA_ATLAS_MAP_PATH)
		return
	var file := FileAccess.open(FLORA_ATLAS_MAP_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_atlas_map = parsed


## Used by the offline atlas baker only — not at runtime paint time.
static func stage_sprite_path(plant_id: String, stage: int) -> String:
	var stage_idx := clampi(stage, 0, 5)
	var exact := _stage_sprite_path_for_index(plant_id, stage_idx)
	if exact != "":
		return exact
	var available := _discover_available_stage_indices(plant_id)
	if available.is_empty():
		return ""
	var best_stage := available[0]
	var best_dist := absi(best_stage - stage_idx)
	for s in available:
		var dist := absi(s - stage_idx)
		if dist < best_dist:
			best_dist = dist
			best_stage = s
	return _stage_sprite_path_for_index(plant_id, best_stage)


static func _stage_sprite_path_for_index(plant_id: String, stage_idx: int) -> String:
	var row: Dictionary = preload("res://data/data_plants.gd").get_plant_data(plant_id)
	var fruit_variants := str(row.get("layer", "")).to_lower() == "canopy"
	for path in _stage_sprite_path_candidates(plant_id, stage_idx, FLORA_BASE, fruit_variants):
		if _sprite_file_exists(path):
			return path
	for path in _stage_sprite_path_candidates(plant_id, stage_idx, USER_STAGE_DIR, fruit_variants):
		if _sprite_file_exists(path):
			return path
	return ""


static func _sprite_file_exists(path: String) -> bool:
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			return true
		return FileAccess.file_exists(ProjectSettings.globalize_path(path))
	return FileAccess.file_exists(path)


static func _discover_available_stage_indices(plant_id: String) -> Array[int]:
	var found: Dictionary = {}
	var folder := "%s/%s" % [FLORA_BASE, plant_id]
	var dir := DirAccess.open(folder)
	if dir:
		for entry in dir.get_files():
			if entry.to_lower().ends_with(".png"):
				var stage := _parse_stage_from_filename(entry.get_basename(), plant_id)
				if stage >= 0:
					found[stage] = true
	var user_folder := "%s/%s" % [USER_STAGE_DIR, plant_id]
	var udir := DirAccess.open(user_folder)
	if udir:
		for entry in udir.get_files():
			if entry.to_lower().ends_with(".png"):
				var stage := _parse_stage_from_filename(entry.get_basename(), plant_id)
				if stage >= 0:
					found[stage] = true
	var stages: Array[int] = []
	for key in found.keys():
		stages.append(int(key))
	stages.sort()
	return stages


static func _parse_stage_from_filename(stem: String, plant_id: String = "") -> int:
	var cleaned := stem.replace("_nanoalpha", "")
	var regex := RegEx.new()
	regex.compile("^stage_?(\\d+)(?:nofruit|withfruit)?$")
	var m := regex.search(cleaned)
	if m:
		return clampi(int(m.get_string(1)), 0, 5)
	var digit_re := RegEx.new()
	digit_re.compile("^(?:.+?)(\\d+)$")
	var m2 := digit_re.search(cleaned)
	if m2:
		var num := int(m2.get_string(1))
		if plant_id != "":
			return _legacy_file_number_to_stage(plant_id, num)
		return clampi(num, 0, 5)
	return -1


static func _legacy_file_number_to_stage(plant_id: String, file_num: int) -> int:
	if _folder_prefers_zero_indexed_stages(plant_id):
		return clampi(file_num, 0, 5)
	return clampi(file_num - 1, 0, 5)


static func _folder_prefers_zero_indexed_stages(plant_id: String) -> bool:
	var folder := "%s/%s" % [FLORA_BASE, plant_id]
	var dir := DirAccess.open(folder)
	if dir == null:
		return false
	for entry in dir.get_files():
		if not entry.to_lower().ends_with(".png"):
			continue
		var stem := entry.get_basename().replace("_nanoalpha", "")
		var digit_re := RegEx.new()
		digit_re.compile("^(?:.+?)(\\d+)$")
		var m := digit_re.search(stem)
		if m and int(m.get_string(1)) == 0:
			return true
	return false


static func _legacy_stems_for_plant(plant_id: String) -> PackedStringArray:
	match plant_id:
		"climbing_bean":
			return PackedStringArray(["climbingbean"])
		"yorkshire_rhubarb":
			return PackedStringArray(["rhubarb"])
		"reed":
			return PackedStringArray(["reeds", "reed"])
		_:
			return PackedStringArray([plant_id])


static func _nanoalpha_variant(filename: String) -> String:
	return filename.replace(".png", "_nanoalpha.png")


## Canopy trees: try stage{N}nofruit / stage{N}withfruit before plain stage names.
## NanoAlpha copies (*_nanoalpha.png) are preferred when present.
static func _stage_sprite_file_names(stage_idx: int, fruit_variants: bool) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var base: PackedStringArray = PackedStringArray()
	if fruit_variants:
		var suffixes: Array[String]
		if stage_idx == 4:
			suffixes = ["withfruit", "nofruit"]
		else:
			suffixes = ["nofruit", "withfruit"]
		for suffix in suffixes:
			base.append("stage%d%s.png" % [stage_idx, suffix])
			base.append("stage_%d_%s.png" % [stage_idx, suffix])
			base.append("stage_%d%s.png" % [stage_idx, suffix])
	base.append("stage_%d.png" % stage_idx)
	base.append("stage%d.png" % stage_idx)
	for name in base:
		names.append(_nanoalpha_variant(name))
		names.append(name)
	return names


static func _legacy_stage_file_names(plant_id: String, stage_idx: int) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var zero_idx := _folder_prefers_zero_indexed_stages(plant_id)
	var file_num := stage_idx if zero_idx else stage_idx + 1
	for stem in _legacy_stems_for_plant(plant_id):
		var plain := "%s%d.png" % [stem, file_num]
		names.append(_nanoalpha_variant(plain))
		names.append(plain)
	return names


static func _stage_sprite_path_candidates(plant_id: String, stage_idx: int, base: String, fruit_variants: bool) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for name in _stage_sprite_file_names(stage_idx, fruit_variants):
		out.append("%s/%s/%s" % [base, plant_id, name])
	for name in _legacy_stage_file_names(plant_id, stage_idx):
		out.append("%s/%s/%s" % [base, plant_id, name])
	for name in _stage_sprite_file_names(stage_idx, fruit_variants):
		out.append("%s/%s_%s" % [base, plant_id, name])
	for name in _legacy_stage_file_names(plant_id, stage_idx):
		out.append("%s/%s_%s" % [base, plant_id, name])
	return out


static func stage_label(stage: int) -> String:
	var idx := clampi(stage, 0, STAGE_NAMES.size() - 1)
	return STAGE_NAMES[idx]


## Permaculture life-cycle scaling for daily soil exchange (n / minerals / moisture).
static func stage_multipliers(stage: int) -> Dictionary:
	match clampi(stage, 0, 5):
		0:
			return {"n": 0.0, "min": 0.0, "m": 0.1}
		1:
			return {"n": 0.25, "min": 0.1, "m": 0.5}
		2:
			return {"n": 1.0, "min": 0.5, "m": 1.0}
		3:
			return {"n": 0.5, "min": 1.0, "m": 1.0}
		4:
			return {"n": 0.2, "min": 1.0, "m": 1.0}
		5:
			return {"n": 0.0, "min": 0.0, "m": 0.0}
		_:
			return {"n": 1.0, "min": 1.0, "m": 1.0}


## Base CSV exchange deltas scaled by growth stage (structure/toxicity unscaled).
static func scaled_exchange_deltas(plant_data: Dictionary, stage: int) -> Dictionary:
	var mults: Dictionary = stage_multipliers(stage)
	return {
		"moisture": float(plant_data.get("moisture_delta", 0)) * float(mults.m),
		"nitrogen": float(plant_data.get("nitrogen_delta", 0)) * float(mults.n),
		"minerals": float(plant_data.get("mineral_delta", 0)) * float(mults.min),
		"structure": float(plant_data.get("structure_delta", 0)),
		"toxicity": float(plant_data.get("toxicity_delta", 0)),
	}
