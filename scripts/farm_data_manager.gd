extends Node

## FarmDataManager (autoload): single source of truth for the **current farm run** —
## grid, turn, money, workers, energy, inventory, seasons, queues.
## UI and map code read/write here; SaveManager serializes this for `user://` saves.
## Meta-progression (Insight, unlocks) lives in MetaManager, not here.
## Broader orientation: docs/CODEBASE_GUIDE.md

signal data_reset
signal energy_changed(new_val, max_val)
@warning_ignore("unused_signal")
signal money_changed(new_val)
@warning_ignore("unused_signal")
signal turn_advanced(new_turn)

var grid_data: Array[Array] = []
var current_turn: int = 1
var action_queue: Array[Dictionary] = []
var redo_queue: Array[Array] = []
var blueprints: Array[Dictionary] = []
var current_money: int = 500
var current_season: String = "Spring"
const DAYS_PER_MONTH := 28
const DAYS_PER_YEAR := 336
## Turn 1 = Dawnseed 1, Year 1. Each gameplay season spans three months (see MONTH_SEASONS).
## Month display names from obsidian/24_Months.md
const MONTHS: Array[String] = [
	"Dawnseed", "Glimmernow", "Bloomtide",
	"Sungrain", "Solstace", "Meadowlark",
	"Leafturn", "Grainrest", "Windfall",
	"Frostmoon", "Yulebrink", "Landsleep",
]
## Hover / lore label for each month (Early Spring, Mid Spring, …).
const MONTH_SEASONS: Array[String] = [
	"Early Spring", "Mid Spring", "Late Spring",
	"Early Summer", "Mid Summer", "Late Summer",
	"Early Autumn", "Mid Autumn", "Late Autumn",
	"Early Winter", "Mid Winter", "Late Winter",
]
const WEEKDAYS: Array[String] = ["M", "Tu", "W", "Th", "F", "Sa", "Su"]
const COARSE_SEASONS: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]
const COMMUNITY_EVENTS_DEFAULT: Dictionary = {
	14: "Seed Swap",
	28: "Spring Festival",
	56: "Midsummer Fair",
	84: "Harvest Moon Feast",
}
var community_events: Dictionary = COMMUNITY_EVENTS_DEFAULT.duplicate()
var inventory: Dictionary = {}
var workers: Array[Dictionary] = []

var difficulty: String = "Normal"
var is_creative_mode: bool = false
var creative_zen_mode: bool = false
var creative_weatherproof: bool = false
var creative_infinite_water: bool = false
var creative_time_lapse: float = 1.0

var auto_harvest: bool = true
var auto_sell: bool = true
var manual_energy_bonus: int = 10
var base_max_energy: int = 30

var active_worker_id: String = "player"
var cell_notes: Dictionary = {}
var scribbles: Array[Dictionary] = []

var map_width: int = 128
var map_height: int = 128
var current_power: int = 0
var current_water: int = 0
var player_bounds_left: int = 6
var player_bounds_right: int = 93
var active_campaign_id: String = "tutorial"
## Political campaign metrics (Oakhaven Defence); money uses `current_money`.
var metric_education: int = 50
var metric_ecology: int = 80
var metric_sanity: int = 50
var custom_starting_grid_loaded: bool = false
var custom_farmhouse_pos: Vector2i = Vector2i(-1, -1)

const MAX_HISTORY := 50
var history_buffer: Array[Dictionary] = []
## Index into `history_buffer` while scrubbing; -1 = live at newest frame.
var history_playhead: int = -1
## Edits while scrubbed back — futures stay until sleep; cleared when state matches anchor again.
var timeline_draft_pending: bool = false
var timeline_draft_anchor: int = -1

func _merge_campaign_defaults(overrides: Dictionary) -> Dictionary:
	var campaigns := DataScenario.get_campaigns()
	var cid := DataScenario.normalize_campaign_id(
		str(overrides.get("id", overrides.get("active_campaign_id", overrides.get("campaign_id", ""))))
	)
	var def: Dictionary = campaigns.get(cid, campaigns[DataScenario.DEFAULT_CAMPAIGN_ID])
	var out := overrides.duplicate(true)
	out["id"] = cid
	out["active_campaign_id"] = cid
	out["campaign_id"] = cid
	if not out.has("width") and not out.has("map_width"):
		out["width"] = int(def.get("map_width", 100))
	if not out.has("height") and not out.has("map_height"):
		out["height"] = int(def.get("map_height", 100))
	if not out.has("money"):
		out["money"] = int(def.get("starting_money", 200))
	if not out.has("bounds"):
		out["bounds"] = [int(def.get("bounds_left", 6)), int(def.get("bounds_right", 93))]
	return out


# Critical for reincarnation/reloads
func reset_data(overrides: Dictionary = {}) -> void:
	overrides = _merge_campaign_defaults(overrides)
	# Campaign / creative overrides use `width`/`height` in data; legacy paths used `map_width`/`map_height`.
	active_campaign_id = DataScenario.normalize_campaign_id(
		str(overrides.get("id", overrides.get("active_campaign_id", overrides.get("campaign_id", DataScenario.DEFAULT_CAMPAIGN_ID))))
	)

	if overrides.has("width"):
		map_width = int(overrides["width"])
	elif overrides.has("map_width"):
		map_width = int(overrides["map_width"])
	else:
		map_width = 128

	if overrides.has("height"):
		map_height = int(overrides["height"])
	elif overrides.has("map_height"):
		map_height = int(overrides["map_height"])
	else:
		map_height = 128

	if overrides.has("bounds"):
		var bounds: Array = overrides["bounds"]
		if bounds.size() > 0:
			player_bounds_left = int(bounds[0])
		if bounds.size() > 1:
			player_bounds_right = int(bounds[1])
	elif overrides.has("player_bounds_left") or overrides.has("player_bounds_right"):
		if overrides.has("player_bounds_left"):
			player_bounds_left = int(overrides["player_bounds_left"])
		if overrides.has("player_bounds_right"):
			player_bounds_right = int(overrides["player_bounds_right"])
	elif overrides.has("player_bounds_min_x") or overrides.has("player_bounds_max_x"):
		if overrides.has("player_bounds_min_x"):
			player_bounds_left = int(overrides["player_bounds_min_x"])
		if overrides.has("player_bounds_max_x"):
			player_bounds_right = int(overrides["player_bounds_max_x"])
	else:
		player_bounds_left = 6
		player_bounds_right = 93

	_apply_creative_plant_mods(overrides)

	NarrativeData.load_data(active_campaign_id)
	DataScenario.load_data(active_campaign_id)

	grid_data.clear()
	history_buffer.clear()
	history_playhead = -1
	timeline_draft_pending = false
	timeline_draft_anchor = -1
	custom_starting_grid_loaded = false
	custom_farmhouse_pos = Vector2i(-1, -1)
	current_turn = 1
	action_queue.clear()
	blueprints.clear()
	current_money = int(overrides.get("money", 500))
	inventory.clear()
	current_season = "Spring"
	community_events = COMMUNITY_EVENTS_DEFAULT.duplicate()
	sync_calendar_state()
	difficulty = "Normal"
	is_creative_mode = false
	creative_zen_mode = false
	creative_weatherproof = false
	creative_infinite_water = false
	creative_time_lapse = 1.0
	auto_harvest = true
	auto_sell = true
	manual_energy_bonus = 10
	base_max_energy = 30
	current_power = 0
	current_water = 0
	active_worker_id = "player"
	workers = [{
		"id": "player", "name": "Farmer", "color": "fbc02d",
		"role": "active", "skills": {"dig": 1.0, "maintain": 1.0}, "action_queue": [],
		"energy": base_max_energy, "max_energy": base_max_energy,
		"sprite": "res://assets/base/sprites/characters/farmers/farmer.png",
		"character_anim": "inbox_farmer",
	}]
	cell_notes.clear()
	scribbles.clear()
	redo_queue.clear()

	is_creative_mode = not overrides.is_empty() and overrides.get("campaign_id", "") == ""
	if is_creative_mode:
		if overrides.has("money"):
			current_money = int(overrides.get("money", current_money))
		creative_zen_mode = bool(overrides.get("zen_mode", false))
		creative_weatherproof = bool(overrides.get("weatherproof", false))
		creative_infinite_water = bool(overrides.get("infinite_water", false))
		creative_time_lapse = float(overrides.get("time_lapse", 1.0))

		var custom_energy: int = int(overrides.get("energy", base_max_energy))
		base_max_energy = custom_energy
		for w in workers:
			if w.get("id", "") == "player":
				w["max_energy"] = custom_energy
				w["energy"] = custom_energy

		if overrides.has("auto_harvest"):
			auto_harvest = bool(overrides.get("auto_harvest", true))
		if overrides.has("auto_sell"):
			auto_sell = bool(overrides.get("auto_sell", true))
		if overrides.has("manual_energy_bonus"):
			manual_energy_bonus = int(overrides.get("manual_energy_bonus", 10))

		var pre_staffed: int = int(overrides.get("pre_staffed", 0))
		if pre_staffed > 0:
			workers.append({
				"id": "digger", "name": "Digger", "role": "cultivate",
				"skills": {"dig": 1.5, "maintain": 1.0}, "action_queue": [],
				"energy": 25, "max_energy": 25,
				"sprite": "res://assets/base/dummy.png", "color": "81c784",
			})
		if pre_staffed > 1:
			workers.append({
				"id": "tender", "name": "Tender", "role": "water",
				"skills": {"dig": 0.8, "maintain": 1.5}, "action_queue": [],
				"energy": 15, "max_energy": 15,
				"sprite": "res://assets/base/dummy.png", "color": "64b5f6",
			})

		if overrides.has("season"):
			current_season = str(overrides.get("season", current_season))
	else:
		var save_mgr := get_node_or_null("/root/SaveManager")
		if save_mgr and save_mgr.has_method("apply_gameplay_settings_to_farm"):
			save_mgr.apply_gameplay_settings_to_farm()
		else:
			for w in workers:
				if w.get("id", "") == "player":
					base_max_energy = int(w.get("max_energy", base_max_energy))
					break

	# Custom starting_grid.json is optional — missing file → procedural generation in starting_map.
	if not try_load_custom_starting_grid():
		custom_starting_grid_loaded = false

	if active_campaign_id == "heritage_garden":
		auto_harvest = true
		auto_sell = true

	if active_campaign_id == "oakhaven_defence":
		metric_education = 50
		metric_ecology = 80
		metric_sanity = 50

	recalculate_energy_bonus()
	data_reset.emit()


func _resolve_custom_starting_grid_path() -> String:
	# Only a grid saved for THIS campaign id boots here. The Map Editor's scratch grid
	# (user://campaigns/custom/) must never hijack tutorial / standard campaigns —
	# those fall through to procedural biome generation in starting_map.
	var campaign_path := "user://campaigns/%s/starting_grid.json" % active_campaign_id
	if FileAccess.file_exists(campaign_path):
		return campaign_path
	return ""


func try_load_custom_starting_grid() -> bool:
	custom_starting_grid_loaded = false
	var grid_path := _resolve_custom_starting_grid_path()
	if grid_path == "" or not FileAccess.file_exists(grid_path):
		return false

	var file := FileAccess.open(grid_path, FileAccess.READ)
	if file == null:
		push_warning("FarmDataManager: could not read %s" % grid_path)
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("FarmDataManager: invalid starting grid JSON at %s" % grid_path)
		return false

	var data: Dictionary = parsed
	var w := clampi(int(data.get("width", map_width)), 10, 256)
	var h := clampi(int(data.get("height", map_height)), 10, 256)

	var raw_grid: Variant = data.get("grid_data", [])
	if typeof(raw_grid) != TYPE_ARRAY:
		push_warning("FarmDataManager: starting grid missing grid_data array")
		return false

	var new_grid: Array[Array] = []
	for x in range(w):
		var src_col: Variant = raw_grid[x] if x < raw_grid.size() else []
		var column: Array = []
		for y in range(h):
			if typeof(src_col) == TYPE_ARRAY and y < src_col.size() and typeof(src_col[y]) == TYPE_DICTIONARY:
				column.append((src_col[y] as Dictionary).duplicate(true))
			else:
				column.append({
					"land": "land",
					"moisture": 5.0,
					"nitrogen": 5.0,
					"minerals": 5.0,
					"toxicity": 0.0,
					"structure": 5.0,
					"biodiversity": 10,
					"aeration": 20,
					"soil_tags": [],
					"has_path": false,
				})
		new_grid.append(column)

	map_width = w
	map_height = h
	grid_data = new_grid

	var fp: Variant = data.get("farmhouse_pos", {})
	if typeof(fp) == TYPE_DICTIONARY:
		custom_farmhouse_pos = Vector2i(int(fp.get("x", -1)), int(fp.get("y", -1)))
	else:
		custom_farmhouse_pos = Vector2i(-1, -1)

	custom_starting_grid_loaded = true
	print("FarmDataManager: loaded custom starting grid (%dx%d) from %s" % [map_width, map_height, grid_path])
	return true


func is_time_machine_enabled() -> bool:
	var meta := get_node_or_null("/root/MetaManager")
	var dev_mode := meta != null and bool(meta.get("dev_mode"))
	return is_creative_mode or dev_mode


func get_current_date_info(turn: int = -1) -> Dictionary:
	var t := turn if turn >= 0 else current_turn
	var zero := t - 1
	var year := int(zero / DAYS_PER_YEAR) + 1
	var month_index := int((zero % DAYS_PER_YEAR) / DAYS_PER_MONTH)
	var day_of_month := (zero % DAYS_PER_MONTH) + 1
	var weekday: String = WEEKDAYS[zero % WEEKDAYS.size()]
	return {
		"year": year,
		"month_index": month_index,
		"month_name": MONTHS[month_index],
		"season_name": MONTH_SEASONS[month_index],
		"day_of_month": day_of_month,
		"weekday": weekday,
	}


func get_month_season_name(month_index: int) -> String:
	var idx := posmod(month_index, MONTH_SEASONS.size())
	return MONTH_SEASONS[idx]


func get_coarse_season(turn: int = -1) -> String:
	var month_index: int = int(get_current_date_info(turn)["month_index"])
	return COARSE_SEASONS[month_index / 3]


func format_year(year: int) -> String:
	return "Year %d" % year


func _ordinal_day(day: int) -> String:
	var mod100 := day % 100
	if mod100 >= 11 and mod100 <= 13:
		return "%dth" % day
	match day % 10:
		1:
			return "%dst" % day
		2:
			return "%dnd" % day
		3:
			return "%drd" % day
		_:
			return "%dth" % day


func format_calendar_date(turn: int = -1, use_ordinal: bool = true) -> String:
	var info := get_current_date_info(turn)
	var day_part: String = _ordinal_day(int(info["day_of_month"])) if use_ordinal else str(info["day_of_month"])
	return "%s %s, %s" % [info["month_name"], day_part, format_year(int(info["year"]))]


func format_month_year(year: int, month_index: int) -> String:
	var idx := posmod(month_index, MONTHS.size())
	return "%s, %s" % [MONTHS[idx], format_year(year)]


func flowering_season_matches(flowering_seasons: Variant, turn: int = -1) -> bool:
	var info := get_current_date_info(turn)
	var tags: Array[String] = [
		get_coarse_season(turn).to_lower(),
		str(info["season_name"]).to_lower(),
		str(info["month_name"]).to_lower(),
	]
	if flowering_seasons is Array:
		for fs in flowering_seasons:
			var key := str(fs).strip_edges().to_lower()
			if key.is_empty():
				continue
			for tag in tags:
				if tag == key or key in tag or tag in key:
					return true
	return false


func sync_calendar_state() -> void:
	current_season = get_coarse_season()


func get_current_season(turn: int = -1) -> String:
	return get_coarse_season(turn)


func get_season_day(turn: int = -1) -> int:
	return int(get_current_date_info(turn)["day_of_month"])


func turn_for_month_day(year: int, month_index: int, day_of_month: int) -> int:
	return (year - 1) * DAYS_PER_YEAR + month_index * DAYS_PER_MONTH + day_of_month


func get_community_event(turn: int) -> String:
	return str(community_events.get(turn, ""))


func get_history_playhead() -> int:
	if history_buffer.is_empty():
		return 0
	if history_playhead < 0:
		return history_buffer.size() - 1
	return clampi(history_playhead, 0, history_buffer.size() - 1)


func is_at_history_tip() -> bool:
	return history_buffer.is_empty() or get_history_playhead() >= history_buffer.size() - 1


func get_turn_at_history_index(index: int) -> int:
	if index < 0 or index >= history_buffer.size():
		return current_turn
	return int(history_buffer[index].get("turn", current_turn))


func set_history_playhead(index: int) -> void:
	if history_buffer.is_empty():
		history_playhead = -1
		return
	history_playhead = clampi(index, 0, history_buffer.size() - 1)


func clear_history_playhead() -> void:
	history_playhead = -1


func is_timeline_draft_pending() -> bool:
	return timeline_draft_pending


func can_scrub_timeline_forward() -> bool:
	if history_buffer.is_empty():
		return false
	if timeline_draft_pending:
		return false
	return get_history_playhead() < history_buffer.size() - 1


## Record that the player is experimenting on a past frame (futures kept until next turn).
func mark_timeline_draft() -> void:
	if not is_time_machine_enabled() or history_buffer.is_empty() or is_at_history_tip():
		return
	if not timeline_draft_pending:
		timeline_draft_anchor = get_history_playhead()
	timeline_draft_pending = true


## Undo/clear queue restored the anchor frame — player may scrub forward into the original future again.
func try_clear_timeline_draft() -> bool:
	if not timeline_draft_pending:
		return true
	if not action_queue.is_empty() or not blueprints.is_empty() or not redo_queue.is_empty():
		return false
	var anchor := timeline_draft_anchor
	if anchor < 0 or anchor >= history_buffer.size():
		timeline_draft_pending = false
		timeline_draft_anchor = -1
		return true
	if _state_matches_history_index(anchor):
		timeline_draft_pending = false
		timeline_draft_anchor = -1
		return true
	apply_history_snapshot(anchor)
	timeline_draft_pending = false
	timeline_draft_anchor = -1
	return true


## Called at sleep when a draft exists — discards the old future and keeps this branch.
func commit_timeline_branch_before_turn() -> void:
	if not timeline_draft_pending:
		return
	var playhead := timeline_draft_anchor if timeline_draft_anchor >= 0 else get_history_playhead()
	playhead = clampi(playhead, 0, history_buffer.size() - 1)
	while history_buffer.size() > playhead + 1:
		history_buffer.pop_back()
	history_buffer[playhead] = _build_snapshot_dict()
	history_playhead = playhead
	timeline_draft_pending = false
	timeline_draft_anchor = -1


func _state_matches_history_index(index: int) -> bool:
	if index < 0 or index >= history_buffer.size():
		return false
	var snap: Dictionary = history_buffer[index]
	if int(snap.get("money", -1)) != current_money:
		return false
	if int(snap.get("turn", -1)) != current_turn:
		return false
	if str(snap.get("season", "")) != current_season:
		return false
	return _grid_data_matches_variant(snap.get("grid_data", []))


func _build_snapshot_dict() -> Dictionary:
	var queue_copy: Array = []
	for item in action_queue:
		if typeof(item) == TYPE_DICTIONARY:
			queue_copy.append((item as Dictionary).duplicate(true))
		else:
			queue_copy.append(item)
	var blueprint_copy: Array = []
	for bp in blueprints:
		if typeof(bp) == TYPE_DICTIONARY:
			blueprint_copy.append((bp as Dictionary).duplicate(true))
		else:
			blueprint_copy.append(bp)
	return {
		"turn": current_turn,
		"season": current_season,
		"money": current_money,
		"grid_data": _duplicate_grid_data(),
		"action_queue": queue_copy,
		"blueprints": blueprint_copy,
	}


func _snapshot_grid() -> void:
	if not is_time_machine_enabled():
		return
	history_buffer.append(_build_snapshot_dict())
	while history_buffer.size() > MAX_HISTORY:
		history_buffer.pop_front()
		if history_playhead >= 0:
			history_playhead = maxi(0, history_playhead - 1)


func _grid_data_matches_variant(raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	if raw.size() != grid_data.size():
		return false
	for x in range(grid_data.size()):
		var src_col: Variant = raw[x]
		var live_col: Variant = grid_data[x]
		if typeof(src_col) != TYPE_ARRAY or typeof(live_col) != TYPE_ARRAY:
			return false
		if src_col.size() != live_col.size():
			return false
		for y in range(live_col.size()):
			var a: Variant = src_col[y]
			var b: Variant = live_col[y]
			if typeof(a) != typeof(b):
				return false
			if typeof(a) == TYPE_DICTIONARY:
				if (a as Dictionary).hash() != (b as Dictionary).hash():
					return false
			elif a != b:
				return false
	return true


func _duplicate_grid_data() -> Array:
	var copy: Array = []
	for x in range(grid_data.size()):
		var src_col: Variant = grid_data[x]
		var column: Array = []
		if typeof(src_col) == TYPE_ARRAY:
			for y in range(src_col.size()):
				var cell: Variant = src_col[y]
				if typeof(cell) == TYPE_DICTIONARY:
					column.append((cell as Dictionary).duplicate(true))
				else:
					column.append(cell)
		copy.append(column)
	return copy


func apply_history_snapshot(index: int) -> bool:
	if index < 0 or index >= history_buffer.size():
		return false
	var snap: Dictionary = history_buffer[index]
	var raw: Variant = snap.get("grid_data", [])
	if typeof(raw) != TYPE_ARRAY:
		return false
	var rebuilt: Array[Array] = []
	for col_v in raw:
		if typeof(col_v) != TYPE_ARRAY:
			continue
		var new_col: Array = []
		for cell_v in col_v:
			if typeof(cell_v) == TYPE_DICTIONARY:
				new_col.append((cell_v as Dictionary).duplicate(true))
			else:
				new_col.append(cell_v)
		rebuilt.append(new_col)
	grid_data = rebuilt
	current_turn = int(snap.get("turn", current_turn))
	current_money = int(snap.get("money", current_money))
	sync_calendar_state()

	action_queue.clear()
	var raw_queue: Variant = snap.get("action_queue", [])
	if typeof(raw_queue) == TYPE_ARRAY:
		for item in raw_queue:
			if typeof(item) == TYPE_DICTIONARY:
				action_queue.append((item as Dictionary).duplicate(true))

	blueprints.clear()
	var raw_bp: Variant = snap.get("blueprints", [])
	if typeof(raw_bp) == TYPE_ARRAY:
		for bp in raw_bp:
			if typeof(bp) == TYPE_DICTIONARY:
				blueprints.append((bp as Dictionary).duplicate(true))

	redo_queue.clear()
	return true


func add_to_inventory(id: String, amt: int) -> void:
	if id == "" or amt <= 0:
		return
	inventory[id] = get_inventory_count(id) + amt


func remove_from_inventory(id: String, amt: int) -> bool:
	if id == "" or amt <= 0:
		return false
	var current := get_inventory_count(id)
	if current < amt:
		return false
	var remaining := current - amt
	if remaining <= 0:
		inventory.erase(id)
	else:
		inventory[id] = remaining
	return true


func get_inventory_count(id: String) -> int:
	return int(inventory.get(id, 0))


func recalculate_energy_bonus() -> void:
	var bonus := 0
	if not auto_harvest:
		bonus += manual_energy_bonus
	if not auto_sell:
		bonus += manual_energy_bonus

	for w in workers:
		if w.get("id", "") == "player":
			var prev_max: int = int(w.get("max_energy", base_max_energy))
			w["max_energy"] = base_max_energy + bonus
			if prev_max > 0:
				w["energy"] = int(float(w.get("energy", 0)) / float(prev_max) * float(w["max_energy"]))
			w["energy"] = clampi(int(w.get("energy", 0)), 0, int(w["max_energy"]))
			break
	energy_changed.emit(get_energy(), get_max_energy())


func _apply_creative_plant_mods(overrides: Dictionary) -> void:
	if overrides.is_empty():
		return
	var PlantData := preload("res://data/data_plants.gd")
	var db_path := str(overrides.get("custom_database_path", ""))
	if db_path != "" and FileAccess.file_exists(db_path):
		PlantData.load_custom_database(db_path)
	else:
		PlantData.reload_default_database()
	var sprite_pack := str(overrides.get("custom_sprite_pack_path", ""))
	if sprite_pack != "":
		PlantData.apply_sprite_pack_from_path(sprite_pack)


func get_active_worker() -> Dictionary:
	for w in workers:
		if w.get("id", "") == active_worker_id:
			return w
	if workers.size() > 0:
		return workers[0]
	return {}


func get_energy() -> int:
	var w := get_active_worker()
	return w.get("energy", 0) if not w.is_empty() else 0


func get_max_energy() -> int:
	var w := get_active_worker()
	return w.get("max_energy", 20) if not w.is_empty() else 20


func spend_energy(amount: int) -> void:
	for i in range(workers.size()):
		if workers[i].get("id", "") == active_worker_id:
			workers[i]["energy"] = clampi(workers[i].get("energy", 0) - amount, 0, workers[i].get("max_energy", 20))
			energy_changed.emit(get_energy(), get_max_energy())
			return


func refund_energy(amount: int) -> void:
	for i in range(workers.size()):
		if workers[i].get("id", "") == active_worker_id:
			workers[i]["energy"] = clampi(workers[i].get("energy", 0) + amount, 0, workers[i].get("max_energy", 20))
			energy_changed.emit(get_energy(), get_max_energy())
			return


func wake_up_workers() -> void:
	for i in range(workers.size()):
		workers[i]["energy"] = workers[i].get("max_energy", 20)
	energy_changed.emit(get_energy(), get_max_energy())


const GVCS_STORAGE_PER_STRUCTURE := 50
const GVCS_BASE_POWER_CAPACITY := 10
const GVCS_SOLAR_CAPACITY_BONUS := 5
const GVCS_BATTERY_CAPACITY := 100


func count_fixture(fixture_id: String) -> int:
	var n := 0
	if grid_data.is_empty():
		return 0
	var w := mini(map_width, grid_data.size())
	for x in range(w):
		var col: Variant = grid_data[x]
		if typeof(col) != TYPE_ARRAY:
			continue
		var h := mini(map_height, col.size())
		for y in range(h):
			if not col[y] is Dictionary:
				continue
			var cell: Dictionary = col[y]
			if not cell.has("structure"):
				continue
			var s: Variant = cell["structure"]
			if typeof(s) == TYPE_STRING and str(s) == fixture_id:
				n += 1
	return n


func get_max_power_capacity() -> int:
	return (
		GVCS_BASE_POWER_CAPACITY
		+ count_fixture("solar_panel") * GVCS_SOLAR_CAPACITY_BONUS
		+ count_fixture("battery") * GVCS_BATTERY_CAPACITY
	)


func clamp_stored_power() -> void:
	current_power = mini(get_max_power_capacity(), current_power)


func get_max_water_capacity() -> int:
	return count_fixture("water_butt") * GVCS_STORAGE_PER_STRUCTURE


const PLANT_DEATH_LOG_MAX := 5

const PLANT_DEATH_REASON_LABELS: Dictionary = {
	"Thirsty!": "Low moisture",
	"Root Rot!": "Waterlogged roots",
	"Starved!": "Low nitrogen",
	"Nutrient Burn!": "Excess nitrogen",
	"Mineral Starved!": "Low minerals",
	"Lockout!": "Mineral lockout",
	"Toxic Soil!": "Soil toxicity",
	"Frost (weather)": "Frost",
	"Frostbite": "Winter frostbite",
	"Desiccation": "Dried out",
	"Swaled": "swaled",
}


func record_plant_death(cell: Dictionary, layer: String, plant_id: String, reason: String) -> void:
	if plant_id.is_empty():
		return
	var age_key := layer + "_age"
	var peak_key := layer + "_peak_age"
	var planted_key := layer + "_planted_turn"
	var peak_age := float(cell.get(peak_key, maxf(0.0, float(cell.get(age_key, 0.0)))))
	var planted_turn := int(cell.get(planted_key, -1))
	var lifespan_turns := current_turn - planted_turn if planted_turn >= 0 else int(round(peak_age))
	lifespan_turns = maxi(0, lifespan_turns)
	var stage_idx := PlantGrowth.growth_stage(plant_id, peak_age)
	var log: Array = []
	if cell.has("plant_death_log") and typeof(cell["plant_death_log"]) == TYPE_ARRAY:
		log = cell["plant_death_log"]
	log.insert(0, {
		"plant_id": plant_id,
		"layer": layer,
		"turn": current_turn,
		"reason": reason,
		"lifespan_turns": lifespan_turns,
		"growth_stage": stage_idx,
		"peak_age": peak_age,
	})
	while log.size() > PLANT_DEATH_LOG_MAX:
		log.pop_back()
	cell["plant_death_log"] = log


func mark_plant_planted(cell: Dictionary, layer: String) -> void:
	cell[layer + "_age"] = 0.0
	cell[layer + "_peak_age"] = 0.0
	cell[layer + "_planted_turn"] = current_turn


func erase_plant_tracking_keys(cell: Dictionary, layer: String) -> void:
	for suffix in ["_age", "_peak_age", "_planted_turn", "_yield"]:
		cell.erase(layer + suffix)


func format_plant_lifespan_text(lifespan_turns: int) -> String:
	if lifespan_turns <= 0:
		return "less than 1 turn"
	if lifespan_turns == 1:
		return "1 turn"
	return "%d turns" % lifespan_turns


func format_plant_death_reason(reason: String) -> String:
	return str(PLANT_DEATH_REASON_LABELS.get(reason, reason))


func format_plant_death_log(cell: Dictionary, max_entries: int = 3) -> String:
	var log: Array = cell.get("plant_death_log", [])
	if log.is_empty():
		return ""
	var plant_db = preload("res://data/data_plants.gd")
	var lines: PackedStringArray = []
	var show_count := mini(max_entries, log.size())
	for i in range(show_count):
		var entry: Dictionary = log[i]
		var pid := str(entry.get("plant_id", ""))
		var pname := str(plant_db.get_plant_data(pid).get("name", pid))
		var death_turn := int(entry.get("turn", current_turn))
		var turns_ago := maxi(0, current_turn - death_turn)
		var reason := format_plant_death_reason(str(entry.get("reason", "Unknown")))
		var layer := str(entry.get("layer", ""))
		var layer_part := (" (%s)" % layer.capitalize()) if layer != "" else ""
		var ago_txt := "this turn" if turns_ago == 0 else (
			"%d turn%s ago" % [turns_ago, "s" if turns_ago != 1 else ""]
		)
		var lifespan_txt := format_plant_lifespan_text(int(entry.get("lifespan_turns", 0)))
		var stage_idx := int(entry.get("growth_stage", -1))
		if stage_idx < 0:
			stage_idx = PlantGrowth.growth_stage(pid, float(entry.get("peak_age", 0.0)))
		var stage_num := clampi(stage_idx, 0, 5) + 1
		lines.append((
			"  • [color=#ef9a9a]%s[/color]%s — %s\n"
			+ "    [color=#b0bec5]Lived %s · reached stage %d · cause of death: %s[/color]"
		) % [pname, layer_part, ago_txt, lifespan_txt, stage_num, reason])
	var header := "[b][color=#e57373]☠ Plant history[/color][/b]\n"
	if log.size() > show_count:
		header = (
			"[b][color=#e57373]☠ Plant history[/color][/b] "
			+ "[color=#888](%d of %d)[/color]\n" % [show_count, log.size()]
		)
	return header + "\n".join(lines)
