extends Node

## Plant database loaded from `res://data/plants_v3.csv` (V3.3 ecological schema).
## See `obsidian/P4S Obsidian Design Docs/06_Plant_Data_Schema.md`.

const PLANTS_CSV_PATH := "res://data/plants_v3.csv"
const CUSTOM_PLANTS_PATH := "user://databases/custom_plants.csv"
const CUSTOM_SPRITE_DIR := "user://databases/sprites/"

## Parsed rows keyed by `id`. Empty cells fall back to `_field_defaults()`.
static var DATA: Dictionary = {}
static var _csv_headers: PackedStringArray = PackedStringArray()

static func _static_init() -> void:
	_load_plants_from_csv(PLANTS_CSV_PATH)


static func _field_defaults() -> Dictionary:
	# Empty CSV cells use these only for keys present in `_field_defaults` / known gameplay columns.
	# Policy: min_* gatekeepers default 0; max_moisture/max_nitrogen/max_minerals default 10; max_temp default 40 (°C);
	# all *_delta default 0; soil-web affinities default 0; pH 5.5–7.5.
	return {
		"id": "",
		"name": "",
		"latin_name": "",
		"cost": 1,
		"atlas_x": 0,
		"custom_sprite_path": "",
		"layer": "ground",
		"mature_turn": 1,
		"days_to_mature": 10,
		"days_to_senescence": 15,
		"lifecycle": "annual",
		"yield_val": -1,
		"energy_yield": -1,
		"soil_reqs": [],
		"soil_yields": [],
		"desc": "",
		"frost_hardiness": 0,
		"shade_tolerance": "Medium",
		"drought_resist": "Medium",
		"root_type": "Fibrous",
		"attracts_wildlife": [],
		"repels_pests": [],
		"coppice_yield": 0,
		"windbreak_rating": 0,
		"dynamic_accumulator": false,
		"nitrogen_fixer": false,
		"mycorrhizal_affinity": "Medium",
		"harvest_season": "",
		"edible_parts": "",
		"toxicity": "None",
		"spread_rate": 1,
		"n_delta": 0.0,
		"m_delta": 0.0,
		"min_moisture": 0,
		"max_moisture": 10,
		"min_nitrogen": 0,
		"min_minerals": 0,
		"max_nitrogen": 10,
		"max_minerals": 10,
		"ideal_ph_min": 5.5,
		"ideal_ph_max": 7.5,
		"min_depth": 0,
		"max_toxicity": 10,
		"min_germination_temp": 0,
		"max_temp": 40,
		"moisture_delta": 0,
		"nitrogen_delta": 0,
		"mineral_delta": 0,
		"toxicity_delta": 0,
		"structure_delta": 0,
		"fungal_affinity": 0,
		"bacterial_affinity": 0,
		"macro_life_affinity": 0,
		"flowering_seasons": [],
		"pollination_bonus": 1,
	}


static func load_custom_database(filepath: String) -> void:
	_load_plants_from_csv(filepath)


static func reload_default_database() -> void:
	_load_plants_from_csv(PLANTS_CSV_PATH)


static func apply_custom_sprite(plant_id: String, sprite_path: String) -> void:
	if not DATA.has(plant_id):
		return
	DATA[plant_id]["custom_sprite_path"] = sprite_path
	DATA[plant_id].erase("custom_atlas_x")


## Applies every `{plant_id}.png` in a folder (or a single PNG) onto matching DATA rows.
static func apply_sprite_pack_from_path(pack_path: String) -> void:
	if pack_path == "":
		return
	if FileAccess.file_exists(pack_path) and not DirAccess.dir_exists_absolute(pack_path):
		var single_id := pack_path.get_file().get_basename()
		if DATA.has(single_id):
			apply_custom_sprite(single_id, pack_path)
		return
	var dir := DirAccess.open(pack_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.to_lower().ends_with(".png"):
			var plant_id := entry.get_basename()
			if DATA.has(plant_id):
				apply_custom_sprite(plant_id, pack_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


static func get_plant_atlas_x(plant_id: String) -> int:
	var row: Dictionary = get_plant_data(plant_id)
	if row.is_empty():
		return 0
	if row.has("custom_atlas_x"):
		return int(row["custom_atlas_x"])
	return int(row.get("atlas_x", 0))


static func coerce_field(column: String, raw: String) -> Variant:
	return _parse_cell(column, raw)


static func get_csv_headers() -> PackedStringArray:
	if _csv_headers.is_empty():
		_cache_csv_headers_from(PLANTS_CSV_PATH)
	return _csv_headers


static func _cache_csv_headers_from(csv_path: String) -> void:
	_csv_headers = PackedStringArray()
	if not FileAccess.file_exists(csv_path):
		return
	var text := FileAccess.get_file_as_string(csv_path)
	text = text.replace("\r\n", "\n").replace("\r", "\n")
	var lines := text.split("\n", false)
	if lines.is_empty():
		return
	var headers := _split_csv_line(lines[0])
	if headers.size() > 0:
		var h0 := str(headers[0])
		if h0.unicode_at(0) == 0xFEFF:
			headers[0] = h0.substr(1)
	_csv_headers = headers


static func export_to_csv(filepath: String, data_dict: Dictionary) -> bool:
	var headers := get_csv_headers()
	if headers.is_empty():
		push_error("data_plants: no CSV headers available for export")
		return false
	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		push_error("data_plants: cannot write %s (err %s)" % [filepath, FileAccess.get_open_error()])
		return false
	file.store_line(",".join(headers))
	var ids: Array = data_dict.keys()
	ids.sort()
	for plant_id in ids:
		var row: Dictionary = data_dict[plant_id]
		var fields := PackedStringArray()
		for h in headers:
			var key := str(h).strip_edges()
			fields.append(_serialize_cell(key, row.get(key, "")))
		file.store_line(",".join(fields))
	file.close()
	print("data_plants: exported ", ids.size(), " plants to ", filepath)
	return true


static func _serialize_cell(column: String, value: Variant) -> String:
	if value == null:
		return ""
	const ARRAY_KEYS: Array[String] = ["soil_reqs", "soil_yields", "attracts_wildlife", "repels_pests"]
	const BOOL_KEYS: Array[String] = ["dynamic_accumulator", "nitrogen_fixer"]
	if column == "flowering_seasons":
		if value is Array:
			if value.is_empty():
				return ""
			var season_parts: PackedStringArray = PackedStringArray()
			for el in value:
				season_parts.append(str(el).strip_edges().to_lower())
			return _escape_csv_field(",".join(season_parts))
		return _escape_csv_field(str(value))
	if ARRAY_KEYS.has(column):
		if value is Array:
			if value.is_empty():
				return ""
			var parts: PackedStringArray = PackedStringArray()
			for el in value:
				parts.append(str(el).strip_edges())
			return _escape_csv_field("|".join(parts))
		return _escape_csv_field(str(value))
	if BOOL_KEYS.has(column):
		return "true" if bool(value) else "false"
	if value is float:
		var s := str(value)
		if s.ends_with(".0"):
			return s.substr(0, s.length() - 2)
		return s
	if value is int:
		return str(value)
	if value is bool:
		return "true" if value else "false"
	return _escape_csv_field(str(value))


static func _escape_csv_field(raw: String) -> String:
	if raw.find(",") >= 0 or raw.find("\"") >= 0 or raw.find("\n") >= 0:
		return "\"" + raw.replace("\"", "\"\"") + "\""
	return raw


static func _load_plants_from_csv(csv_path: String = PLANTS_CSV_PATH) -> void:
	DATA.clear()
	if not FileAccess.file_exists(csv_path):
		push_error("data_plants: missing %s" % csv_path)
		return
	var text := FileAccess.get_file_as_string(csv_path)
	text = text.replace("\r\n", "\n").replace("\r", "\n")
	var lines := text.split("\n", false)
	if lines.is_empty():
		push_error("data_plants: empty CSV")
		return
	var headers := _split_csv_line(lines[0])
	if headers.size() > 0:
		var h0 := str(headers[0])
		if h0.unicode_at(0) == 0xFEFF:
			headers[0] = h0.substr(1)
	if headers.is_empty() or str(headers[0]).strip_edges().begins_with("#"):
		push_error("data_plants: invalid header row")
		return
	_csv_headers = headers
	for li in range(1, lines.size()):
		var line := lines[li].strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var fields := _split_csv_line(lines[li])
		if fields.is_empty():
			continue
		var row := _field_defaults().duplicate(true)
		for fi in range(mini(headers.size(), fields.size())):
			var key := str(headers[fi]).strip_edges()
			if key == "":
				continue
			var raw := str(fields[fi]).strip_edges()
			if raw == "":
				continue
			row[key] = _parse_cell(key, raw)
		var sid := str(row.get("id", "")).strip_edges()
		if sid == "":
			push_warning("data_plants: skipping row %d (no id)" % li)
			continue
		row["id"] = sid
		# Produce economy: explicit ints; blank/missing CSV cells keep sentinel -1 → default 5
		var yv := int(row.get("yield_val", -1))
		row["yield_val"] = 5 if yv < 0 else yv
		var ey := int(row.get("energy_yield", -1))
		row["energy_yield"] = 5 if ey < 0 else ey
		if not row.has("pollination_bonus"):
			row["pollination_bonus"] = 1
		else:
			row["pollination_bonus"] = maxi(0, int(row.get("pollination_bonus", 1)))
		if not row.has("flowering_seasons") or row["flowering_seasons"] == null:
			row["flowering_seasons"] = []
		var mature_days := int(row.get("days_to_mature", -1))
		if mature_days < 1:
			mature_days = maxi(1, int(row.get("mature_turn", 10)))
		row["days_to_mature"] = mature_days
		var senesce_days := int(row.get("days_to_senescence", -1))
		if senesce_days <= mature_days:
			senesce_days = maxi(mature_days + 1, 15)
		row["days_to_senescence"] = senesce_days
		DATA[sid] = row
	print("Successfully loaded ", DATA.size(), " plants from ", csv_path.get_file(), " (V3.3).")


## Split one CSV line into fields (RFC4180-style quotes; "" → literal ").
static func _split_csv_line(line: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur := ""
	var in_quotes := false
	var i := 0
	while i < line.length():
		var ch: String = line[i]
		if ch == "\"":
			if in_quotes and i + 1 < line.length() and line[i + 1] == "\"":
				cur += "\""
				i += 2
				continue
			in_quotes = not in_quotes
			i += 1
			continue
		if not in_quotes and ch == ",":
			out.append(cur)
			cur = ""
			i += 1
			continue
		cur += ch
		i += 1
	out.append(cur)
	return out


static func _parse_cell(column: String, raw: String) -> Variant:
	const STRING_KEYS: Array[String] = [
		"id", "name", "latin_name", "lifecycle", "layer", "shade_tolerance", "drought_resist", "root_type",
		"mycorrhizal_affinity", "harvest_season", "edible_parts", "toxicity", "desc", "custom_sprite_path",
	]
	const FLOAT_KEYS: Array[String] = ["ideal_ph_min", "ideal_ph_max", "n_delta", "m_delta"]
	const BOOL_KEYS: Array[String] = ["dynamic_accumulator", "nitrogen_fixer"]
	const ARRAY_KEYS: Array[String] = ["soil_reqs", "soil_yields", "attracts_wildlife", "repels_pests"]

	if column == "flowering_seasons":
		if raw == "":
			return []
		var sep := "|" if "|" in raw else ","
		var season_parts := raw.split(sep, false)
		var seasons: Array = []
		for p in season_parts:
			var s := str(p).strip_edges().to_lower()
			if s != "":
				seasons.append(s)
		return seasons

	if column == "pollination_bonus":
		if raw == "":
			return 1
		return maxi(0, int(raw))

	if ARRAY_KEYS.has(column):
		if raw == "":
			return []
		var parts := raw.split("|", false)
		var arr: Array = []
		for p in parts:
			var s := str(p).strip_edges()
			if s != "":
				arr.append(s)
		return arr

	if BOOL_KEYS.has(column):
		var lo := raw.to_lower()
		return lo == "true" or lo == "1" or lo == "yes"

	if FLOAT_KEYS.has(column):
		var f := raw.to_float()
		return f

	if STRING_KEYS.has(column):
		return raw

	# Int stats & counters
	if raw.is_valid_int():
		return int(raw)
	if raw.is_valid_float():
		return int(round(raw.to_float()))
	return 0


## Coerce CSV/custom plant fields for `%d` / `%+d` string formatting (Godot 4.6 rejects non-numbers).
static func as_int(value: Variant, default: int = 0) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(round(value))
		TYPE_STRING:
			var s := str(value).strip_edges()
			if s.is_valid_int():
				return int(s)
			if s.is_valid_float():
				return int(round(s.to_float()))
	return default


static func get_plant_data(id: String) -> Dictionary:
	if DATA.is_empty():
		_load_plants_from_csv(PLANTS_CSV_PATH)
	return DATA.get(id, {})


## Back-compat alias used across the project.
static func get_plant(id: String) -> Dictionary:
	return get_plant_data(id)


static func get_all_codex_data() -> Dictionary:
	if DATA.is_empty():
		_load_plants_from_csv(PLANTS_CSV_PATH)

	var codex := {}
	for key in DATA.keys():
		var p: Dictionary = DATA[key]
		var plant_name: String = str(p.get("name", key.capitalize()))
		var text := "[b]Layer:[/b] %s\n" % str(p.get("layer", "")).capitalize()
		text += "[b]Lifecycle:[/b] %s\n" % str(p.get("lifecycle", "")).capitalize()
		text += "[b]Cost:[/b] £%s\n" % str(p.get("cost", "0"))
		text += "[b]Needs:[/b] moisture %s–%s · N %s–%s · minerals %s–%s · toxicity ≤%s · germ ≥%s°C · heat ≤%s°C\n" % [
			str(p.get("min_moisture", "?")),
			str(p.get("max_moisture", "?")),
			str(p.get("min_nitrogen", "?")),
			str(p.get("max_nitrogen", "?")),
			str(p.get("min_minerals", "?")),
			str(p.get("max_minerals", "?")),
			str(p.get("max_toxicity", "?")),
			str(p.get("min_germination_temp", "?")),
			str(p.get("max_temp", "?")),
		]
		text += "[b]Δ per exchange:[/b] moisture %s · nitrogen %s · minerals %s · toxicity %s · structure %s\n" % [
			str(p.get("moisture_delta", "0")),
			str(p.get("nitrogen_delta", "0")),
			str(p.get("mineral_delta", "0")),
			str(p.get("toxicity_delta", "0")),
			str(p.get("structure_delta", "0")),
		]
		text += "[b]Soil web:[/b] fungi %s · bacteria %s · macro-life %s\n" % [
			str(p.get("fungal_affinity", "0")),
			str(p.get("bacterial_affinity", "0")),
			str(p.get("macro_life_affinity", "0")),
		]
		text += "[b]Yield / Energy:[/b] %s (%s)\n" % [str(p.get("yield_val", "0")), str(p.get("energy_yield", "0"))]
		var roles = p.get("repels_pests", [])
		var roles_str := "None"
		if roles is Array and roles.size() > 0:
			roles_str = ", ".join(PackedStringArray(roles))
		elif roles is String and str(roles) != "":
			roles_str = str(roles)
		text += "[b]Roles/Traits:[/b] [color=#ffb74d]%s[/color]\n\n" % roles_str
		text += "[color=#aaaaaa]%s[/color]" % str(p.get("desc", ""))
		codex[plant_name] = text
	return codex


## Back-compat for UI that forced a reload before iterating.
static func _load_csv() -> void:
	_load_plants_from_csv(PLANTS_CSV_PATH)
