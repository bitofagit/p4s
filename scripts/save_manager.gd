extends Node

## SaveManager (autoload): writes/reads **per-slot farm saves** as JSON under `user://`.
## Also owns **settings** (`user://settings.json`): hotkeys + display (resolution, mode, UI scale).
## Set `pending_load_save_name` before changing to `world.tscn` so `starting_map` can load that slot once the map exists.
## Does not store Insight/unlocks — that is MetaManager (`shadow_logic_meta.json`).
## Broader orientation: docs/CODEBASE_GUIDE.md

const SETTINGS_PATH := "user://settings.json"

## Matches `project.godot` window overrides and graphics panel options (windowed sizes only).
## 16:10 defaults tuned for 16" MacBook Pro (Retina); FALLBACK fits macOS "Default" scaled pixels.
const DISPLAY_SETTINGS_VERSION := 1
const DEFAULT_RESOLUTION := Vector2i(1920, 1200)
const FALLBACK_RESOLUTION := Vector2i(1728, 1117)
const RESOLUTION_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	FALLBACK_RESOLUTION,
	Vector2i(1920, 1080),
	DEFAULT_RESOLUTION,
	Vector2i(2560, 1600),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

## If set, `starting_map` will call `load_game(self, pending_load_save_name)` once the map exists.
var pending_load_save_name: String = ""

var hotkeys: Dictionary = {
	"Rotovator": KEY_C,
	"Scythe": KEY_X,
	"Uproot": KEY_U,
	"Dig Swale": KEY_V,
	"Build Mound": KEY_B,
	"Plant": KEY_S,
	"Water": KEY_W,
	"Standard Lens": KEY_1,
	"Hydration Lens": KEY_2,
	"Nitrogen Lens": KEY_3,
	"Guild Vision": KEY_4,
}

var display_settings: Dictionary = {}
var gameplay_settings: Dictionary = {}


func _ready() -> void:
	_ensure_display_defaults()
	_ensure_gameplay_defaults()
	load_settings()
	apply_display_settings()


func _ensure_display_defaults() -> void:
	if not display_settings.is_empty():
		return
	var def := get_default_resolution()
	display_settings = {
		"window_mode": get_default_window_mode(),
		"width": def.x,
		"height": def.y,
		"ui_scale": 1.0,
		"_version": DISPLAY_SETTINGS_VERSION,
	}


func _ensure_gameplay_defaults() -> void:
	if not gameplay_settings.is_empty():
		return
	gameplay_settings = {
		"auto_harvest": true,
		"auto_sell": true,
		"manual_energy_bonus": 10,
	}


func apply_gameplay_settings_to_farm() -> void:
	_ensure_gameplay_defaults()
	FarmDataManager.auto_harvest = bool(gameplay_settings.get("auto_harvest", true))
	FarmDataManager.auto_sell = bool(gameplay_settings.get("auto_sell", true))
	FarmDataManager.manual_energy_bonus = int(gameplay_settings.get("manual_energy_bonus", 10))


func sync_gameplay_from_farm() -> void:
	_ensure_gameplay_defaults()
	gameplay_settings["auto_harvest"] = FarmDataManager.auto_harvest
	gameplay_settings["auto_sell"] = FarmDataManager.auto_sell
	gameplay_settings["manual_energy_bonus"] = FarmDataManager.manual_energy_bonus


func get_default_resolution() -> Vector2i:
	var w: int = int(
		ProjectSettings.get_setting("display/window/size/window_width_override", DEFAULT_RESOLUTION.x)
	)
	var h: int = int(
		ProjectSettings.get_setting("display/window/size/window_height_override", DEFAULT_RESOLUTION.y)
	)
	if w <= 0 or h <= 0:
		return DEFAULT_RESOLUTION
	return Vector2i(w, h)


func get_default_window_mode() -> DisplayServer.WindowMode:
	# Borderless fullscreen fills the display; canvas_items stretch scales the viewport.
	return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func clear_window_size_overrides() -> void:
	ProjectSettings.set_setting("display/window/size/window_width_override", 0)
	ProjectSettings.set_setting("display/window/size/window_height_override", 0)


func resolution_preset_index(size: Vector2i) -> int:
	var best_i := 0
	var best_dist := 1_000_000
	for i in range(RESOLUTION_PRESETS.size()):
		var p: Vector2i = RESOLUTION_PRESETS[i]
		var dist: int = absi(p.x - size.x) + absi(p.y - size.y)
		if dist < best_dist:
			best_dist = dist
			best_i = i
	return best_i


func parse_resolution_label(label: String) -> Vector2i:
	var cleaned := label.strip_edges().replace(" ", "").to_lower()
	var parts := cleaned.split("x", false)
	if parts.size() >= 2:
		var w := int(parts[0])
		var h := int(parts[1])
		if w > 0 and h > 0:
			return Vector2i(w, h)
	push_warning("Could not parse resolution label '%s'; using fallback." % label)
	return FALLBACK_RESOLUTION


func clamp_resolution_to_monitor(target: Vector2i) -> Vector2i:
	var monitor_size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	# Headless boot / editor embed: monitor can report 0×0 — skip clamp + warning.
	if monitor_size.x <= 0 or monitor_size.y <= 0:
		return target
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var win := tree.root.get_window()
		if win and win.is_embedded():
			return target
	if target.x > monitor_size.x or target.y > monitor_size.y:
		var msg := (
			"Resolution %d×%d exceeds monitor (%d×%d). Using safe fallback %d×%d."
			% [
				target.x,
				target.y,
				monitor_size.x,
				monitor_size.y,
				FALLBACK_RESOLUTION.x,
				FALLBACK_RESOLUTION.y,
			]
		)
		push_warning(msg)
		return FALLBACK_RESOLUTION
	return target


## Godot ignores `window_set_size` while `window_*_override` in project.godot are non-zero — sync both.
func apply_windowed_size(target: Vector2i) -> void:
	ProjectSettings.set_setting("display/window/size/window_width_override", target.x)
	ProjectSettings.set_setting("display/window/size/window_height_override", target.y)
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var win := tree.root.get_window()
		if win and win.is_embedded():
			return
	DisplayServer.window_set_size(target)


func apply_display_settings(override: Dictionary = {}) -> void:
	_ensure_display_defaults()
	var d: Dictionary = display_settings.duplicate() if override.is_empty() else override
	var mode: int = int(d.get("window_mode", DisplayServer.WINDOW_MODE_WINDOWED))
	var size := Vector2i(int(d.get("width", FALLBACK_RESOLUTION.x)), int(d.get("height", FALLBACK_RESOLUTION.y)))
	var ui_scale: float = float(d.get("ui_scale", 1.0))
	var tree := Engine.get_main_loop() as SceneTree

	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		size = clamp_resolution_to_monitor(size)
		d["width"] = size.x
		d["height"] = size.y
		display_settings["width"] = size.x
		display_settings["height"] = size.y

		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if tree and tree.root:
			var win := tree.root.get_window()
			if win and not win.is_embedded():
				apply_windowed_size(size)
				win.move_to_center()
			else:
				# Still store overrides for exported builds; skip physical resize in editor embed.
				ProjectSettings.set_setting("display/window/size/window_width_override", size.x)
				ProjectSettings.set_setting("display/window/size/window_height_override", size.y)
		else:
			apply_windowed_size(size)
			var screen_size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
			DisplayServer.window_set_position(Vector2i(Vector2(screen_size - size) / 2.0))
	else:
		clear_window_size_overrides()
		DisplayServer.window_set_mode(mode)

	if tree and tree.root:
		tree.root.content_scale_factor = ui_scale
	elif get_tree() and get_tree().root:
		get_tree().root.content_scale_factor = ui_scale


func _migrate_display_settings() -> void:
	_ensure_display_defaults()
	var ver: int = int(display_settings.get("_version", 0))
	if ver >= DISPLAY_SETTINGS_VERSION:
		return
	display_settings["window_mode"] = get_default_window_mode()
	display_settings["width"] = DEFAULT_RESOLUTION.x
	display_settings["height"] = DEFAULT_RESOLUTION.y
	display_settings["ui_scale"] = 1.0
	display_settings["_version"] = DISPLAY_SETTINGS_VERSION
	save_settings()


func save_game(_map_node: Node, save_name: String) -> void:
	var safe_name := _sanitize_save_name(save_name)
	var path := "user://" + safe_name + ".json"
	var save_dict := {
		"turn": FarmDataManager.current_turn,
		"money": FarmDataManager.current_money,
		"difficulty": FarmDataManager.difficulty,
		"grid": _serialize_grid(FarmDataManager.grid_data),
		"inventory": FarmDataManager.inventory,
		"produce": FarmDataManager.inventory,
		"workers": FarmDataManager.workers,
		"active_worker_id": FarmDataManager.active_worker_id,
		"auto_harvest": FarmDataManager.auto_harvest,
		"auto_sell": FarmDataManager.auto_sell,
		"manual_energy_bonus": FarmDataManager.manual_energy_bonus,
		"base_max_energy": FarmDataManager.base_max_energy,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Save failed: could not open %s (error %s)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(save_dict))
	file.close()
	print("Saved to: ", path)


func load_game(map_node: Node, save_name: String) -> void:
	var path := "user://" + _sanitize_save_name(save_name) + ".json"
	if not FileAccess.file_exists(path):
		push_error("Load failed: file not found: %s" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Load failed: could not open %s (error %s)" % [path, FileAccess.get_open_error()])
		return
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("Load failed: JSON parse error %s" % json.get_error_message())
		return

	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Load failed: root is not a dictionary.")
		return

	var d: Dictionary = data
	FarmDataManager.current_turn = int(d.get("turn", 1))
	FarmDataManager.current_money = int(d.get("money", 0))
	FarmDataManager.difficulty = str(d.get("difficulty", "Normal"))
	FarmDataManager.grid_data = _deserialize_grid(d.get("grid", []))
	var inventory_raw: Variant = d.get("inventory", d.get("produce", {}))
	FarmDataManager.inventory = inventory_raw if typeof(inventory_raw) == TYPE_DICTIONARY else {}
	if d.has("auto_harvest"):
		FarmDataManager.auto_harvest = bool(d.get("auto_harvest", true))
	if d.has("auto_sell"):
		FarmDataManager.auto_sell = bool(d.get("auto_sell", true))
	if d.has("manual_energy_bonus"):
		FarmDataManager.manual_energy_bonus = int(d.get("manual_energy_bonus", 10))

	var workers_raw: Variant = d.get("workers", [])
	if typeof(workers_raw) == TYPE_ARRAY and workers_raw.size() > 0:
		FarmDataManager.workers.clear()
		for it in workers_raw:
			if it is Dictionary:
				FarmDataManager.workers.append(it)
		for w in FarmDataManager.workers:
			if not w.has("energy"):
				w["energy"] = 20
			if not w.has("max_energy"):
				w["max_energy"] = 20
		var awid: Variant = d.get("active_worker_id", "player")
		FarmDataManager.active_worker_id = str(awid) if str(awid) != "" else "player"
	else:
		var old_e: int = int(d.get("energy", 20))
		FarmDataManager.workers = [{
			"id": "player", "name": "Farmer", "color": "fbc02d",
			"role": "active", "skills": {"dig": 1.0, "maintain": 1.0}, "action_queue": [],
			"energy": clampi(old_e, 0, 100),
			"max_energy": 20
		}]
		FarmDataManager.active_worker_id = "player"

	if d.has("base_max_energy"):
		FarmDataManager.base_max_energy = int(d.get("base_max_energy", 30))
	else:
		for w in FarmDataManager.workers:
			if w.get("id", "") == "player":
				FarmDataManager.base_max_energy = int(w.get("max_energy", 30))
				break
	if not d.has("auto_harvest") and not d.has("auto_sell"):
		apply_gameplay_settings_to_farm()
	FarmDataManager.recalculate_energy_bonus()

	map_node.turn_stepped.emit(FarmDataManager.current_turn, FarmDataManager.get_energy(), FarmDataManager.current_money)
	map_node._refresh_all_visuals()
	print("Loaded: ", path)


func get_saved_games() -> Array[String]:
	var saves: Array[String] = []
	var dir := DirAccess.open("user://")
	if dir == null:
		return saves
	var err := dir.list_dir_begin()
	if err != OK:
		dir.list_dir_end()
		return saves
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			if file_name.get_basename() == "settings":
				continue
			saves.append(file_name.get_basename())
	dir.list_dir_end()
	return saves


func _sanitize_save_name(save_name: String) -> String:
	var s := save_name.strip_edges()
	if s == "":
		return "slot_1"
	return s


func _serialize_grid(grid: Array) -> Array:
	var out: Array = []
	for col in grid:
		if col is Array:
			out.append(col)
	return out


func _deserialize_grid(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array = []
	for col_raw in raw:
		if typeof(col_raw) != TYPE_ARRAY:
			continue
		var col: Array = []
		for cell_raw in col_raw:
			if cell_raw is Dictionary:
				col.append(cell_raw)
			else:
				col.append({})
		out.append(col)
	return out


func save_settings() -> void:
	_ensure_display_defaults()
	_ensure_gameplay_defaults()
	var payload := {
		"hotkeys": hotkeys,
		"display": display_settings,
		"gameplay": gameplay_settings,
	}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Settings save failed: could not open %s (error %s)" % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(payload))
	file.close()


func load_settings() -> void:
	_ensure_display_defaults()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		push_error("Settings load failed: could not open %s (error %s)" % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("Settings load failed: JSON parse error %s" % json.get_error_message())
		return

	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return

	var d: Dictionary = data
	if d.has("hotkeys") and typeof(d["hotkeys"]) == TYPE_DICTIONARY:
		var loaded_hk: Dictionary = d["hotkeys"]
		if loaded_hk.has("Cultivate") and not loaded_hk.has("Rotovator"):
			loaded_hk["Rotovator"] = loaded_hk["Cultivate"]
			loaded_hk.erase("Cultivate")
		if loaded_hk.has("Rotovate") and not loaded_hk.has("Rotovator"):
			loaded_hk["Rotovator"] = loaded_hk["Rotovate"]
			loaded_hk.erase("Rotovate")
		for key in loaded_hk:
			if hotkeys.has(key):
				hotkeys[key] = int(loaded_hk[key])
		var disp: Variant = d.get("display", {})
		if typeof(disp) == TYPE_DICTIONARY:
			_merge_display_settings(disp)
		var gameplay: Variant = d.get("gameplay", {})
		if typeof(gameplay) == TYPE_DICTIONARY:
			_merge_gameplay_settings(gameplay)
	else:
		# Legacy: flat hotkey map only
		for key in d:
			if hotkeys.has(key):
				hotkeys[key] = int(d[key])
	_migrate_display_settings()


func _merge_display_settings(disp: Dictionary) -> void:
	if disp.has("window_mode"):
		display_settings["window_mode"] = int(disp["window_mode"])
	if disp.has("width"):
		display_settings["width"] = int(disp["width"])
	if disp.has("height"):
		display_settings["height"] = int(disp["height"])
	if disp.has("ui_scale"):
		display_settings["ui_scale"] = float(disp["ui_scale"])
	if disp.has("_version"):
		display_settings["_version"] = int(disp["_version"])


func _merge_gameplay_settings(gameplay: Dictionary) -> void:
	_ensure_gameplay_defaults()
	if gameplay.has("auto_harvest"):
		gameplay_settings["auto_harvest"] = bool(gameplay["auto_harvest"])
	if gameplay.has("auto_sell"):
		gameplay_settings["auto_sell"] = bool(gameplay["auto_sell"])
	if gameplay.has("manual_energy_bonus"):
		gameplay_settings["manual_energy_bonus"] = int(gameplay["manual_energy_bonus"])
