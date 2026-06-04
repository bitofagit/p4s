extends TileMapLayer

## Game map controller (large file): generation, input, tools, workers, overlays, narrative hooks, HUD wiring.
## Uses autoloads: FarmDataManager (state), SaveManager (persistence + pending load), MetaManager (meta), RadioManager (audio).
## Story/tutorial weather: DataScenario loads res://data/story_weather.csv; _get_weather_for_day() fills the 5-slot forecast (scripted calendar days when not dev_mode, else random).
## Guild growth: standard guilds are 1-tile vertical stacks (canopy/understory/ground) via `_get_guild_synergy_mult`.
## Superguilds are role-based 3×3 neighborhoods via `_get_synergies_for_cell`.
## Prefer adding small helpers in new scripts only if you are clearly splitting a subsystem — most logic still lives here.
## Broader orientation: docs/CODEBASE_GUIDE.md

signal turn_stepped(new_turn: int, energy: int, money: int)
signal tile_hovered(data: Dictionary)
signal workers_finished

## Matches grid generation: `y >= _map_h() - RIVER_ROW_COUNT` is river.
const RIVER_ROW_COUNT: int = 3

func _map_w() -> int:
	return FarmDataManager.map_width


func _map_h() -> int:
	return FarmDataManager.map_height


## Dug swales can store more moisture than normal soil (0–10); rain + capillary use this ceiling.
const SWALE_MOISTURE_MAX := 25.0
## TileMap / A* / overlays: one cell = 200×200 world pixels (grep for 200 / 100 / 50).

var vitals_label: Label
var hover_label: Label
var active_tool: String = ""
var active_seed: String = ""
var active_structure: String = ""
var active_lens: String = "normal"
var overlay: Sprite2D
var lens_texture: ImageTexture
var door_menu: PopupMenu
var farmer: Sprite2D
var home_pos: Vector2i
var is_sleeping: bool = false
var hud_instance: Control
## Wired after HUD instantiate (scene paths).
var right_info_panel: PanelContainer
var almanac_window: Window
var modal_dimmer: ColorRect
var almanac_open: bool = false
var death_panel: PanelContainer
var _run_earned_insight: int = 0
var inbox_messages: Array[String] = []
var unread_mail: bool = false
var _active_zipping_workers: int = 0
var grass_atlas_xs: Array[int] = []
var stream_atlas_xs: Array[int] = []
var river_atlas_xs: Array[int] = []
var forest_atlas_xs: Array[int] = []
var industrial_atlas_xs: Array[int] = []
var cultivated_atlas_xs: Array[int] = []
var _next_custom_atlas_x: int = 19

@onready var _save_manager: Node = get_node("/root/SaveManager")

## Weighted flood-fill from the farmhouse; cheap on cells with has_path (roads / duck corridors).
var maintenance_bubble: Array[Vector2i] = []
var farmhouse_pos: Vector2i = Vector2i.ZERO

## Energy Vision: Dijkstra costs from farmer (cached until farmer moves).
var _energy_zone_cache: Dictionary = {}
var _energy_came_from: Dictionary = {}
var _cached_farmer_pos: Vector2i = Vector2i(-1, -1)
var _last_energy_mouse_cell: Vector2i = Vector2i(-1, -1)
var _last_camera_pos: Vector2 = Vector2.ZERO
var _last_energy_bg_farmer_cell: Vector2i = Vector2i(-1, -1)

# Zone colours (amorphous, translucent metaball layers)
const ZONE_COLORS: Array[Color] = [
	Color(0.2, 0.8, 0.2, 0.35), # Zone 0: Bright Green
	Color(0.5, 0.8, 0.2, 0.35), # Zone 1: Yellow-Green
	Color(0.8, 0.8, 0.2, 0.35), # Zone 2: Yellow
	Color(0.9, 0.6, 0.2, 0.35), # Zone 3: Orange
	Color(0.9, 0.3, 0.2, 0.35), # Zone 4: Red-Orange
	Color(0.8, 0.1, 0.2, 0.35), # Zone 5: Deep Red
]
const ENERGY_ZONE_MAX_COST := 150.0
const ENERGY_ZONE_DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
]

var narrative_ui: Control
var karma_shop: Control
var _gen1_day16_failure_shown: bool = false
var _desert_net_unlock_announced: bool = false

var is_dragging: bool = false
var _last_dragged_cell: Vector2i = Vector2i(-1, -1)
var _shift_drag_start: Vector2i = Vector2i(-1, -1)
var last_hover_pos: Vector2i = Vector2i(-1, -1)
var _is_scribbling: bool = false
var design_tool: String = "pen"
var design_thickness: float = 6.0
var _design_start_pos: Vector2 = Vector2.ZERO
var _current_shape_data: Dictionary = {}
var design_overlay: DesignOverlayNode
var guild_selected_cell: Vector2i = Vector2i(-1, -1)
var greyscale_overlay: ColorRect

## Debounced A* preview line (hover): avoids pathfinding every frame while painting.
var _preview_path_cache: Array = []
var _preview_path_target: Vector2i = Vector2i(-1, -1)
var _last_mouse_move_time: int = 0
var _current_batch_id: int = 0

var triage_cache: Dictionary = {}
var triage_overlay: TriageOverlayNode
var morning_triage_active: bool = false

## Overnight ecology beats for Camera2D director (weed_spread, plant_died, fox_attack, …).
var overnight_events: Array = []

@onready var main_camera: Camera2D = $"../Camera2D"

var additives_data = {
	"bone_meal": {"name": "Bone Meal", "cost": 10, "n": 2.0, "m": -1.0, "color": "e1bee7"},
	"wood_ash": {"name": "Wood Ash", "cost": 5, "n": -1.0, "m": -2.0, "color": "9e9e9e"},
	"compost": {"name": "Compost", "cost": 15, "n": 5.0, "m": 1.0, "color": "795548"},
	"biochar": {"name": "Biochar", "cost": 20, "n": 1.0, "m": 3.0, "color": "424242"},
}

var tooltip_canvas: CanvasLayer
var tooltip_panel: PanelContainer
var tooltip_label: RichTextLabel

var audio_pool: Array[AudioStreamPlayer] = []
# Generative daytime echoes (same Glockenspiel root as RadioManager.base_sample)
var base_chime: AudioStream = preload("res://assets/base/audio/sfx/chimes/glock-c1.wav")

var seasonal_scales = {
	"Spring": [2, 4, 6, 9, 11], # D Major Pentatonic (Bright, awakening)
	"Summer": [-3, -1, 1, 4, 6], # A Major Pentatonic (Golden, hazy)
	"Autumn": [4, 7, 9, 11, 14], # E Minor Pentatonic (Earthy, wistful)
	"Winter": [-1, 2, 4, 6, 9], # B Minor Pentatonic (Cold, crystalline)
}

var chime_index: int = 0

var night_memory: Array[Dictionary] = []
var _daytime_melody: Array[float] = []
var _sequence_step: int = 0

# A classic 16-step rolling arpeggiator motif (4 bars of 4 notes)
const MELODY_PATTERN: Array[int] = [
	0, 1, 2, 1, # Bar 1: Root, 2nd, 3rd, 2nd
	0, 2, 3, 2, # Bar 2: Root, 3rd, 4th, 3rd
	0, 1, 3, 1, # Bar 3: Root, 2nd, 4th, 2nd
	0, 2, 1, 0, # Bar 4: Root, 3rd, 2nd, Root
]
var echo_loop_length: float = 4.8 # A nice 4-bar loop at 100 BPM
var is_daytime: bool = true

var structure_overlay: Node2D
var energy_blackout: ColorRect
var tile_highlight: ColorRect
var maintenance_bubble_overlay: Node2D
var energy_zone_overlay: Node2D
var energy_cursor_overlay: Node2D
var preview_overlay: Node2D
var farm_astar: AStarGrid2D = AStarGrid2D.new()


const FLOATING_TEXT_POOL_SIZE: int = 30
var _floating_text_pool: Array[Dictionary] = []
var _floating_text_pool_rr: int = 0

var forecast: Array[String] = []
var _last_night_weather: String = "clear"
const GVCS_SOLAR_CHARGE_PER_PANEL := 10
const GVCS_WATER_PER_BUTT := 20
var weather_types: Dictionary = {
	"clear": {"name": "Clear Skies", "color": "e0e0e0", "prob": 60},
	"rain": {"name": "Heavy Rain", "color": "64b5f6", "prob": 25},
	"dry": {"name": "Dry", "color": "ffb74d", "prob": 10},
	"frost": {"name": 	"Early Frost", "color": "81d4fa", "prob": 5},
}


## -----------------------------------------------------------------------------
## Grid overload: `cell["structure"]` is two different concepts
## -----------------------------------------------------------------------------
## 1) **V3 soil structure** (`float`, commonly ~0–10) — tilth / aggregation. Written in
##    `_v3_apply_default_ecology` and advanced by the ecology sim. This is *not* a placed object.
## 2) **Fixture / building** (`String`) — id from `data_objects.gd` (fence, duck_house, …) drawn on
##    StructureLayer and intended to block planting, paths, etc.
##
## Why `_cell_str_nonempty(cell, "structure")` cannot mean “has a building”: numeric soil values stringify
## to non-empty text (`str(5.0)` → `"5.0"`), so cultivated tiles incorrectly looked blocked everywhere.
##
## - Use `_cell_str_nonempty` for string-id keys such as `ground`, `canopy`, `understory`.
## - Use `_cell_has_building_structure` whenever the question is “does a building or fixture occupy this cell?”
##   Grep `_cell_has_building_structure` for call sites (tile paint, path eligibility, plant/hover/build gating,
##   balsam spread, duck patrol).
## -----------------------------------------------------------------------------

## String-safe “non-empty string id” for layer keys (`ground`, `canopy`, …). Not for testing `structure`.
func _cell_str_nonempty(cell: Dictionary, key: String) -> bool:
	return str(cell.get(key, "")).strip_edges() != ""


func _cell_has_npc(cell: Dictionary) -> bool:
	return _cell_str_nonempty(cell, "npc")


## True only when `structure` holds a **building/fixture** id (non-empty string). Soil metrics are TYPE_FLOAT/INT.
func _cell_has_building_structure(cell: Dictionary) -> bool:
	if not cell.has("structure"):
		return false
	var s: Variant = cell["structure"]
	var t := typeof(s)
	# V3 ecology stores soil structure as a number on this key; do not treat as an object id.
	if t == TYPE_FLOAT or t == TYPE_INT:
		return false
	return str(s).strip_edges() != ""


func _cell_fixture_id(cell: Dictionary) -> String:
	if not cell.has("structure"):
		return ""
	var s: Variant = cell["structure"]
	if typeof(s) == TYPE_STRING:
		return str(s).strip_edges()
	return ""


func _cell_is_duck_corridor(cell: Dictionary) -> bool:
	return str(cell.get("zone", "")) == "duck_patrol"


func _cell_has_cheap_traversal(cell: Dictionary) -> bool:
	return bool(cell.get("has_path", false)) or _cell_is_duck_corridor(cell)


func _should_paint_grey_path_tile(cell: Dictionary, planned_state: Dictionary) -> bool:
	return bool(planned_state.get("has_path", false)) and not _cell_is_duck_corridor(cell)


func _sanitize_duck_corridor_tiles() -> void:
	for x in range(_map_w()):
		for y in range(_map_h()):
			var cell: Dictionary = FarmDataManager.grid_data[x][y]
			if _cell_is_duck_corridor(cell) and cell.get("has_path", false):
				cell["has_path"] = false


func _draw_duck_patrol_overlay(canvas: CanvasItem, center_px: Vector2, rect: Rect2) -> void:
	var fence_col := Color(0.38, 0.72, 0.42, 0.5)
	var path_col := Color(0.42, 0.78, 0.46, 0.32)
	var inset := rect.grow(-31)
	var corners: Array[Vector2] = [
		inset.position,
		Vector2(inset.end.x, inset.position.y),
		inset.end,
		Vector2(inset.position.x, inset.end.y),
	]
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var seg_len: float = a.distance_to(b)
		if seg_len < 1.0:
			continue
		var step := 22.0
		var t := 0.0
		while t < seg_len:
			var t1 := minf(t + step * 0.55, seg_len)
			var p0 := a + (b - a) * (t / seg_len)
			var p1 := a + (b - a) * (t1 / seg_len)
			canvas.draw_line(p0, p1, fence_col, 3.0)
			t += step
	for dot_i in range(5):
		var angle := float(dot_i) * TAU / 5.0
		var r := 14.0 + float(dot_i % 2) * 7.0
		var dot_pos := center_px + Vector2(cos(angle), sin(angle)) * r
		canvas.draw_circle(dot_pos, 4.5, path_col)
	canvas.draw_circle(center_px, 5.0, path_col.lightened(0.12))


func _cell_soil_structure_metric(cell: Dictionary) -> float:
	if _cell_has_building_structure(cell):
		return 0.0
	return float(cell.get("structure", 0.0))


const INFRA_LAND_TYPES: Array[String] = [
	"road", "bridge", "river", "stream", "house", "house_door",
]


func _land_is_infra(land: String) -> bool:
	return land in INFRA_LAND_TYPES


## Remove plant layer keys from grid data (used when stamping house / loading saves).
func _clear_cell_plant_data(cell: Dictionary) -> void:
	for layer_key: String in ["canopy", "understory", "ground"]:
		cell[layer_key] = ""
		var age_key: String = layer_key + "_age"
		if cell.has(age_key):
			cell.erase(age_key)
		var yield_key: String = layer_key + "_yield"
		if cell.has(yield_key):
			cell.erase(yield_key)


func _normalize_editor_land_cell(cell: Dictionary) -> void:
	var land_id := str(cell.get("land", "land"))
	match land_id:
		"land":
			cell["land"] = "cultivated"
		"water":
			cell["land"] = "river"
		"rock":
			cell["land"] = "wild"
			if not cell.has("soil_tags") or (cell["soil_tags"] is Array and (cell["soil_tags"] as Array).is_empty()):
				cell["soil_tags"] = ["rocky"]
		"road":
			cell["land"] = "road"
			cell["has_path"] = true
		"structure":
			cell["land"] = "cultivated"
		_:
			pass
	if not cell.has("moisture"):
		_v3_apply_default_ecology(cell, str(cell.get("land", "cultivated")))


func _apply_farmhouse_from_editor_origin(origin: Vector2i) -> void:
	for hx in range(3):
		for hy in range(3):
			var cx := origin.x + hx
			var cy := origin.y + hy
			if cx < 0 or cx >= _map_w() or cy < 0 or cy >= _map_h():
				continue
			var house_cell: Dictionary = FarmDataManager.grid_data[cx][cy]
			var part := "house"
			if hx == 1 and hy == 2:
				part = "house_door"
			house_cell["land"] = part
			_clear_cell_plant_data(house_cell)
	home_pos = origin + Vector2i(1, 2)


func _boot_from_custom_starting_grid() -> void:
	for x in range(_map_w()):
		for y in range(_map_h()):
			_normalize_editor_land_cell(FarmDataManager.grid_data[x][y])

	var fp := FarmDataManager.custom_farmhouse_pos
	if fp.x >= 0 and fp.y >= 0 and fp.x + 2 < _map_w() and fp.y + 2 < _map_h():
		_apply_farmhouse_from_editor_origin(fp)
	else:
		home_pos = Vector2i(_map_w() >> 1, _map_h() >> 1)

	farmhouse_pos = home_pos
	farmer.position = map_to_local(home_pos)
	_sanitize_plants_on_infra_cells()
	update_visuals()
	print("starting_map: booted from custom starting_grid.json (%dx%d)" % [_map_w(), _map_h()])


func _generate_procedural_grid_data() -> void:
	FarmDataManager.grid_data.clear()

	var stream_cells: Dictionary = {}
	var stream_center_x := float(_map_w()) * 0.5
	var bridge_center_x := float(_map_w()) * 0.5
	for cy in range(3, FarmDataManager.map_height - 2):
		stream_center_x += sin(cy * 0.15) * 1.5 + (randf() - 0.5) * 1.0
		stream_center_x = clamp(stream_center_x, 2.0, float(_map_w()) - 2.0)
		var cx := int(stream_center_x)
		if cy == 3:
			bridge_center_x = stream_center_x
		stream_cells[Vector2i(cx, cy)] = true
		stream_cells[Vector2i(cx + 1, cy)] = true
		stream_cells[Vector2i(cx, cy + 1)] = true
		stream_cells[Vector2i(cx + 1, cy + 1)] = true

	for x in range(FarmDataManager.map_width):
		var column: Array = []
		for y in range(FarmDataManager.map_height):
			var cell: Dictionary = {
				"land": "wild",
				"biodiversity": 10,
				"aeration": 20,
				"soil_tags": ["clay"],
				"has_path": false,
			}
			_v3_apply_default_ecology(cell, "wild")

			if y <= 2:
				cell["land"] = "road"
				cell["has_path"] = true
				_v3_apply_default_ecology(cell, "road")
			elif y == 3 and x >= int(bridge_center_x) - 1 and x <= int(bridge_center_x) + 2:
				cell["land"] = "bridge"
				cell["has_path"] = true
				_v3_apply_default_ecology(cell, "bridge")
			elif y >= _map_h() - RIVER_ROW_COUNT:
				cell["land"] = "river"
				_v3_apply_default_ecology(cell, "river")
			elif stream_cells.has(Vector2i(x, y)) and y > 3:
				cell["land"] = "stream"
				_v3_apply_default_ecology(cell, "stream")
			elif x <= FarmDataManager.player_bounds_left:
				cell["land"] = "wild"
				cell["soil_tags"] = ["loam", "mycorrhizally interconnected", "full o worms"]
				_v3_apply_default_ecology(cell, "wild", 8.0, 8.0, 6.0)
				if randf() > 0.6:
					cell["canopy"] = "hawthorn" if randf() > 0.5 else "alder"
					cell["canopy_age"] = 50
			elif x >= FarmDataManager.player_bounds_right:
				cell["land"] = "cultivated"
				cell["soil_tags"] = ["sandy"]
				_v3_apply_default_ecology(cell, "cultivated", 2.0, 0.5, 1.0)

			if FarmDataManager.active_campaign_id == "desert":
				_apply_desert_cell_baseline(cell, x, y)
			elif FarmDataManager.active_campaign_id == "heritage_garden":
				_apply_heritage_garden_cell_baseline(cell, x, y)
			elif FarmDataManager.active_campaign_id == "oakhaven_defence":
				_apply_oakhaven_defence_cell_baseline(cell, x, y)

			var land_type := str(cell.get("land", ""))
			if FarmDataManager.active_campaign_id not in ["desert", "oakhaven_defence"] \
				and (land_type == "wild" or land_type == "forest") \
				and not _cell_has_building_structure(cell):
				cell["ground"] = "grass" if randf() < 0.7 else "heather"
				if randf() < 0.25 and str(cell.get("understory", "")) == "":
					cell["understory"] = "bramble" if randf() < 0.5 else "bracken"
				if randf() < 0.05 and str(cell.get("canopy", "")) == "":
					cell["canopy"] = "alder" if randf() < 0.5 else "hawthorn"
				if cell.has("ground") and str(cell.get("ground", "")) != "":
					cell["ground_age"] = 15.0
				if cell.has("understory") and str(cell.get("understory", "")) != "":
					cell["understory_age"] = 25.0
				if cell.has("canopy") and str(cell.get("canopy", "")) != "":
					cell["canopy_age"] = 50.0

			if (x == FarmDataManager.player_bounds_left or x == FarmDataManager.player_bounds_right) \
				and y > 2 and y < _map_h() - RIVER_ROW_COUNT:
				if cell["land"] != "stream" and not stream_cells.has(Vector2i(x, y)):
					cell["structure"] = "fence"

			column.append(cell)
		FarmDataManager.grid_data.append(column)

	var house_placed := false
	var hw := 8
	var hh := 6
	var buffer := 2
	var center := FarmDataManager.map_width >> 1

	for radius in range(0, 30):
		if house_placed:
			break
		for dx in range(-radius, radius + 1):
			if house_placed:
				break
			for dy in range(-radius, radius + 1):
				if house_placed:
					break
				var sx := center + dx
				var sy := center + dy
				if sx < buffer or sx + hw + buffer >= _map_w() or sy < buffer or sy + hh + buffer >= _map_h():
					continue
				var valid := true
				for cx in range(sx - buffer, sx + hw + buffer):
					for cy in range(sy - buffer, sy + hh + buffer):
						if FarmDataManager.grid_data[cx][cy]["land"] == "river":
							valid = false
							break
					if not valid:
						break
				if valid:
					for hx in range(hw):
						for hy in range(hh):
							var part := "house"
							if hy == hh - 1 and hx == (hw >> 1):
								part = "house_door"
							var house_cell: Dictionary = FarmDataManager.grid_data[sx + hx][sy + hy]
							house_cell["land"] = part
							_clear_cell_plant_data(house_cell)
							if part == "house_door":
								home_pos = Vector2i(sx + hx, sy + hy)
								farmer.position = map_to_local(home_pos)
					house_placed = true

	_sanitize_plants_on_infra_cells()
	update_visuals()

	if not house_placed:
		home_pos = Vector2i(_map_w() >> 1, _map_h() >> 1)
		farmer.position = map_to_local(home_pos)

	farmhouse_pos = home_pos


func _apply_heritage_garden_cell_baseline(cell: Dictionary, x: int, y: int) -> void:
	var land_k := str(cell.get("land", ""))
	if land_k in ["road", "bridge", "river", "stream", "house", "house_door"]:
		return
	if x <= FarmDataManager.player_bounds_left or x >= FarmDataManager.player_bounds_right:
		return
	if y <= 2 or y >= _map_h() - RIVER_ROW_COUNT:
		return
	cell["moisture"] = 6.0
	cell["nitrogen"] = 5.0
	cell["minerals"] = 5.0
	cell["structure"] = 5.0
	cell["biodiversity"] = clampi(70, 0, 100)
	if land_k in ["wild", "cultivated"]:
		cell["soil_tags"] = ["loam", "full o worms"]


func _apply_oakhaven_defence_cell_baseline(cell: Dictionary, x: int, y: int) -> void:
	var land_k := str(cell.get("land", ""))
	if land_k in ["road", "bridge", "river", "stream", "house", "house_door"]:
		return
	if x <= FarmDataManager.player_bounds_left or x >= FarmDataManager.player_bounds_right:
		return
	if y <= 2 or y >= _map_h() - RIVER_ROW_COUNT:
		return
	cell["land"] = "cultivated"
	cell["moisture"] = 8.0
	cell["nitrogen"] = 9.0
	cell["minerals"] = 8.0
	cell["structure"] = 10.0
	cell["biodiversity"] = 90
	cell["soil_tags"] = ["loam", "mycorrhizally interconnected", "full o worms", "well aerated"]
	cell["canopy"] = "apple"
	cell["canopy_age"] = 20.0
	cell["understory"] = "hazel"
	cell["understory_age"] = 15.0
	cell["ground"] = "grass"
	cell["ground_age"] = 10.0


func _spawn_npc_event(grid_x: int, grid_y: int, npc_id: String, duration_turns: int) -> void:
	if grid_x < 0 or grid_x >= _map_w() or grid_y < 0 or grid_y >= _map_h():
		return
	var cell: Dictionary = FarmDataManager.grid_data[grid_x][grid_y]
	cell["npc"] = npc_id
	cell["npc_timer"] = maxi(1, duration_turns)
	if is_instance_valid(structure_overlay):
		structure_overlay.queue_redraw()


func _process_oakhaven_npc_turn() -> void:
	if FarmDataManager.active_campaign_id != "oakhaven_defence":
		return
	for x in range(_map_w()):
		for y in range(_map_h()):
			var cell: Dictionary = FarmDataManager.grid_data[x][y]
			if not _cell_str_nonempty(cell, "npc"):
				continue
			var npc_id := str(cell.get("npc", ""))
			if npc_id == "trustee_hargreaves":
				FarmDataManager.metric_sanity = clampi(FarmDataManager.metric_sanity - 2, 0, 100)
				cell["structure"] = maxf(0.0, _cell_soil_structure_metric(cell) - 1.0)
			elif npc_id == "sylva_student":
				FarmDataManager.metric_education = clampi(FarmDataManager.metric_education + 1, 0, 100)
			var timer := int(cell.get("npc_timer", 0)) - 1
			cell["npc_timer"] = timer
			if timer <= 0:
				cell.erase("npc")
				cell.erase("npc_timer")
	if is_instance_valid(structure_overlay):
		structure_overlay.queue_redraw()


func _heritage_garden_weather(weather: String) -> String:
	if FarmDataManager.active_campaign_id != "heritage_garden":
		return weather
	if weather in ["frost", "dry", "drought"]:
		return "clear"
	return weather


func _apply_desert_cell_baseline(cell: Dictionary, x: int, y: int) -> void:
	var land_k := str(cell.get("land", ""))
	if land_k in ["road", "bridge", "river", "stream", "house", "house_door"]:
		return
	if x <= FarmDataManager.player_bounds_left or x >= FarmDataManager.player_bounds_right:
		return
	if y <= 2 or y >= _map_h() - RIVER_ROW_COUNT:
		return
	cell["land"] = "sand"
	cell["moisture"] = 0.0
	cell["nitrogen"] = 0.0
	cell["minerals"] = 2.0
	cell["structure"] = 0.0
	cell["biodiversity"] = 0
	cell["soil_tags"] = ["sand"]
	for layer: String in ["canopy", "understory", "ground"]:
		cell[layer] = ""
		var age_key: String = layer + "_age"
		if cell.has(age_key):
			cell.erase(age_key)


func _cell_within_fixture_radius(pos: Vector2i, fixture_id: String, radius: int) -> bool:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var check := Vector2i(pos.x + dx, pos.y + dy)
			if check.x < 0 or check.x >= _map_w() or check.y < 0 or check.y >= _map_h():
				continue
			if _cell_fixture_id(FarmDataManager.grid_data[check.x][check.y]) == fixture_id:
				return true
	return false


func _apply_drone_pollinator(center: Vector2i) -> void:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var pos := Vector2i(center.x + dx, center.y + dy)
			if pos.x < 0 or pos.x >= _map_w() or pos.y < 0 or pos.y >= _map_h():
				continue
			var cell: Dictionary = FarmDataManager.grid_data[pos.x][pos.y]
			var boosted := false
			for layer in ["canopy", "understory", "ground"]:
				if not _cell_str_nonempty(cell, layer):
					continue
				cell["macro_life"] = maxf(float(cell.get("macro_life", 0.0)), 10.0)
				if not bool(cell.get("pollinator_boosted", false)):
					cell["pollinator_yield_bonus"] = int(cell.get("pollinator_yield_bonus", 0)) + 1
					cell["pollinator_boosted"] = true
				boosted = true
			if boosted:
				spawn_floating_text("Buzz!", Color("ce93d8"), pos, "ecology")


func _apply_moisture_net_drip(center: Vector2i) -> void:
	var offsets: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for off in offsets:
		var pos := center + off
		if pos.x < 0 or pos.x >= _map_w() or pos.y < 0 or pos.y >= _map_h():
			continue
		var ncell: Dictionary = FarmDataManager.grid_data[pos.x][pos.y]
		if str(ncell.get("land", "")) in ["road", "house", "house_door", "bridge", "river", "stream"]:
			continue
		ncell["moisture"] = clampf(float(ncell.get("moisture", 0.0)) + 1.0, 0.0, 10.0)


func _apply_automated_watering(center: Vector2i) -> void:
	var offsets: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for off in offsets:
		var pos := center + off
		if pos.x < 0 or pos.x >= _map_w() or pos.y < 0 or pos.y >= _map_h():
			continue
		var cell: Dictionary = FarmDataManager.grid_data[pos.x][pos.y]
		var land_k := str(cell.get("land", ""))
		if land_k in ["road", "house", "house_door", "bridge", "river", "stream"]:
			continue
		var mo_cap := SWALE_MOISTURE_MAX if land_k == "swale" else 10.0
		cell["moisture"] = clampf(float(cell.get("moisture", 5.0)) + 3.0, 0.0, mo_cap)


func _apply_drone_harvest(center: Vector2i) -> void:
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var pos := Vector2i(center.x + dx, center.y + dy)
			if pos.x < 0 or pos.x >= _map_w() or pos.y < 0 or pos.y >= _map_h():
				continue
			if pos.x <= FarmDataManager.player_bounds_left or pos.x >= FarmDataManager.player_bounds_right:
				continue
			var cell: Dictionary = FarmDataManager.grid_data[pos.x][pos.y]
			var mature := _mature_plant_on_cell(cell)
			if mature.is_empty():
				continue
			var layer: String = str(mature.get("layer", ""))
			var p_id: String = str(mature.get("id", ""))
			var p_data: Dictionary = mature.get("data", {})
			var age_key: String = str(mature.get("age_key", layer + "_age"))
			var was_pollinated := bool(cell.get("is_pollinated", false))
			var yield_amt := _compute_plant_yield_amount(pos.x, pos.y, p_id)
			_clear_cell_pollination(cell)
			var payout := 0
			if yield_amt > 0:
				if FarmDataManager.auto_sell:
					var base_cost = int(p_data.get("cost", 2))
					var charm_mult := 1.2 if MetaManager.has_upgrade("hypnotic_charm") else 1.0
					payout = int(round(base_cost * 2 * yield_amt * charm_mult))
					FarmDataManager.current_money += payout
				else:
					FarmDataManager.add_to_inventory(p_id, yield_amt)
			if str(p_data.get("lifecycle", "annual")) == "annual":
				_remove_plant_layer(cell, layer)
			else:
				cell[age_key] = float(p_data.get("mature_turn", 2)) / 2.0
			var beep := "Beep! +£%d" % payout if payout > 0 else "Beep!"
			if payout <= 0 and not FarmDataManager.auto_sell and yield_amt > 0:
				beep = "Beep! +%d" % yield_amt
			spawn_floating_text(beep, Color("4fc3f7"), pos, "actions")
			if was_pollinated:
				spawn_floating_text("Perfect Yield!", Color("fff59d"), pos + Vector2i(0, -18), "ecology")
			_update_single_tile_visual(pos)


func _compute_plant_yield_amount(x: int, y: int, p_id: String) -> int:
	var yield_amt := 1
	var guilds := preload("res://data/data_guilds.gd").ENTRIES
	var guild_peak: float = _get_guild_synergy_mult(x, y, str(p_id))
	for g in guilds.values():
		if str(g.get("core", "")) != str(p_id):
			continue
		if guild_peak >= float(g.get("growth_mult", 1.0)):
			yield_amt += int(g.get("yield_bonus", 0))
			break
	if x >= 0 and x < _map_w() and y >= 0 and y < _map_h():
		var cell: Dictionary = FarmDataManager.grid_data[x][y]
		yield_amt += int(cell.get("pollinator_yield_bonus", 0))
		if bool(cell.get("is_pollinated", false)):
			yield_amt += int(_get_plant_data(p_id).get("pollination_bonus", 1))
	return yield_amt


func _clear_cell_pollination(cell: Dictionary) -> void:
	if cell.has("is_pollinated"):
		cell.erase("is_pollinated")


func _season_matches_flowering(current_season: String, flowering_seasons: Variant) -> bool:
	var season_key := current_season.strip_edges().to_lower()
	if season_key == "":
		return false
	if flowering_seasons is Array:
		for fs in flowering_seasons:
			if str(fs).strip_edges().to_lower() == season_key:
				return true
	return false


func _apply_overnight_bee_pollination() -> void:
	var current_season := FarmDataManager.current_season.to_lower()
	for x in range(_map_w()):
		if x % 16 == 0:
			await get_tree().process_frame
		for y in range(_map_h()):
			var cell: Dictionary = FarmDataManager.grid_data[x][y]
			if _cell_fixture_id(cell) != "beehive":
				continue
			cell["biodiversity"] = minf(100.0, float(cell.get("biodiversity", 50.0)) + 2.0)
			for dx in range(-4, 5):
				for dy in range(-4, 5):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or nx >= _map_w() or ny < 0 or ny >= _map_h():
						continue
					var target_cell: Dictionary = FarmDataManager.grid_data[nx][ny]
					for layer: String in ["canopy", "understory", "ground"]:
						if not _cell_str_nonempty(target_cell, layer):
							continue
						var p_id := str(target_cell[layer])
						var plant_data: Dictionary = _get_plant_data(p_id)
						var seasons: Variant = plant_data.get("flowering_seasons", [])
						if not _season_matches_flowering(current_season, seasons):
							continue
						var age_key: String = layer + "_age"
						var mature_turn := float(plant_data.get("mature_turn", 2.0))
						if float(target_cell.get(age_key, 0.0)) < mature_turn * 0.5:
							continue
						target_cell["is_pollinated"] = true
						if randf() < 0.06:
							spawn_floating_text("Pollinated!", Color("fff59d"), Vector2i(nx, ny), "ecology")


func _top_plant_on_cell(cell: Dictionary) -> Dictionary:
	for layer: String in ["canopy", "understory", "ground"]:
		if _cell_str_nonempty(cell, layer):
			var p_id := str(cell[layer])
			var p_data: Dictionary = preload("res://data/data_plants.gd").get_plant_data(p_id)
			if not p_data.is_empty():
				return {"layer": layer, "id": p_id, "data": p_data}
	return {}


func _mature_plant_on_cell(cell: Dictionary) -> Dictionary:
	for layer: String in ["canopy", "understory", "ground"]:
		if not _cell_str_nonempty(cell, layer):
			continue
		var p_id := str(cell[layer])
		var age_key: String = layer + "_age"
		var p_data: Dictionary = preload("res://data/data_plants.gd").get_plant_data(p_id)
		if p_data.is_empty():
			continue
		if float(cell.get(age_key, 0)) >= float(p_data.get("mature_turn", 2)):
			return {"layer": layer, "id": p_id, "data": p_data, "age_key": age_key}
	return {}


func _remove_plant_layer(cell: Dictionary, layer: String) -> void:
	cell[layer] = ""
	var age_key: String = layer + "_age"
	if cell.has(age_key):
		cell.erase(age_key)
	var yield_key: String = layer + "_yield"
	if cell.has(yield_key):
		cell.erase(yield_key)


func _plant_biomass_score(p_data: Dictionary) -> float:
	var cost_raw: Variant = p_data.get("cost", 2)
	var cost_v: int = 0
	if typeof(cost_raw) == TYPE_INT or typeof(cost_raw) == TYPE_FLOAT:
		cost_v = int(cost_raw)
	else:
		cost_v = str(cost_raw).to_int()
	return maxf(1.0, float(p_data.get("yield_val", 1)) * 0.5 + float(cost_v) * 0.15)


func _apply_chop_and_drop_biomass(cell: Dictionary, p_data: Dictionary) -> float:
	var biomass := _plant_biomass_score(p_data)
	cell["nitrogen"] = clampf(float(cell.get("nitrogen", 5.0)) + biomass * 0.45, 0.0, 10.0)
	cell["minerals"] = clampf(float(cell.get("minerals", 5.0)) + biomass * 0.35, 0.0, 10.0)
	var s_val: Variant = cell.get("structure", 5.0)
	if typeof(s_val) == TYPE_STRING and str(s_val).strip_edges() != "":
		if not _cell_has_building_structure(cell):
			cell["structure"] = clampf(5.0 + biomass * 0.25, 0.0, 10.0)
	else:
		cell["structure"] = clampf(float(s_val) + biomass * 0.25, 0.0, 10.0)
	return biomass


func _sanitize_plants_on_infra_cells() -> void:
	for x in range(_map_w()):
		for y in range(_map_h()):
			var cell: Dictionary = FarmDataManager.grid_data[x][y]
			if _land_is_infra(str(cell.get("land", ""))):
				_clear_cell_plant_data(cell)


func _ready() -> void:
	# --- TURN-BASED OPTIMIZATION ---
	OS.low_processor_usage_mode = true

	add_to_group("map")

	# --- DEV MODE OVERRIDES ---
	if MetaManager.dev_mode:
		FarmDataManager.current_money = 99999
		FarmDataManager.workers.append({
			"id": "dev_helper", "name": "Dev Hand", "color": "4fc3f7",
			"role": "maintenance", "skills": {"dig": 1.0, "maintain": 1.5}, "action_queue": [],
			"energy": 30, "max_energy": 30,
			"sprite": "res://assets/base/sprites/characters/workers/dev_hand.png"
		})

	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# Base terrain: 19 procedural slots + N dynamic tiles (grass / forest / stream / river / industrial / cultivated), mipmapped for LOD.
	var T := 200
	# --- DYNAMIC SPRITE LOADING ---
	var dynamic_folders = {
		"grass": {"path": "res://assets/base/sprites/environment/terrain/grass", "files": [], "xs": []},
		"forest": {"path": "res://assets/base/sprites/environment/terrain/forest", "files": [], "xs": []},
		"stream": {"path": "res://assets/base/sprites/environment/water/stream", "files": [], "xs": []},
		"river": {"path": "res://assets/base/sprites/environment/water/river", "files": [], "xs": []},
		"industrial": {"path": "res://assets/base/sprites/environment/terrain/farmnextdoor", "files": [], "xs": []},
		"cultivated": {"path": "res://assets/base/sprites/environment/terrain/cultivated", "files": [], "xs": []}
	}

	var dynamic_total = 0
	for key in dynamic_folders:
		var dir = DirAccess.open(dynamic_folders[key]["path"])
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if not dir.current_is_dir():
					if file_name.ends_with(".import"):
						dynamic_folders[key]["files"].append(file_name.replace(".import", ""))
					elif file_name.ends_with(".png") and not dynamic_folders[key]["files"].has(file_name):
						dynamic_folders[key]["files"].append(file_name)
				file_name = dir.get_next()
			dir.list_dir_end()
			dynamic_total += dynamic_folders[key]["files"].size()

	var total_tiles = 19 + dynamic_total
	var image := Image.create(total_tiles * 200, 200, false, Image.FORMAT_RGBA8)
	# --- DRAW BASE HARDCODED TILES ---
	# Base Land (0-4)
	image.fill_rect(Rect2i(0 * T, 0, T, T), Color("2e7d32"))
	image.fill_rect(Rect2i(1 * T, 0, T, T), Color("4e342e"))
	image.fill_rect(Rect2i(2 * T, 0, T, T), Color("558b2f"))
	image.fill_rect(Rect2i(3 * T, 0, T, T), Color("283593"))
	image.fill_rect(Rect2i(4 * T, 0, T, T), Color("c4511a"))
	# River and House (5-7)
	image.fill_rect(Rect2i(5 * T, 0, T, T), Color("4fc3f7"))
	image.fill_rect(Rect2i(6 * T, 0, T, T), Color("b71c1c"))
	image.fill_rect(Rect2i(7 * T, 0, T, T), Color("111111"))
	# --- PLANT PLACEHOLDERS ---
	# First, ensure these three atlas tiles are completely transparent before drawing
	image.fill_rect(Rect2i(6 * T, 0, 3 * T, T), Color(0, 0, 0, 0))

	# 6: Canopy (Translucent Forest Green canopy floating at the top, thin brown trunk)
	image.fill_rect(Rect2i((6 * T) + 25, 13, 150, 94), Color("2e7d32", 0.5))
	image.fill_rect(Rect2i((6 * T) + 88, 106, 25, 94), Color("5d4037", 0.8))

	# 7: Understory (Opaque Bright Orange/Yellow block sitting in the lower-middle)
	image.fill_rect(Rect2i((7 * T) + 50, 94, 100, 78), Color("f9a825", 1.0))

	# 8: Groundcover (Opaque Bright Cyan/Neon strip hugging the very bottom edge)
	image.fill_rect(Rect2i((8 * T) + 13, 180, 175, 20), Color("00e5ff", 1.0))
	# 9: Hover Highlight (Transparent with thick Yellow border)
	image.fill_rect(Rect2i(9 * T, 0, T, T), Color(0, 0, 0, 0)) # Clear background
	image.fill_rect(Rect2i(9 * T, 0, T, 9), Color(1, 1, 0, 0.8)) # Top
	image.fill_rect(Rect2i(9 * T, T - 9, T, 9), Color(1, 1, 0, 0.8)) # Bottom
	image.fill_rect(Rect2i(9 * T, 0, 9, T), Color(1, 1, 0, 0.8)) # Left
	image.fill_rect(Rect2i((9 * T) + T - 9, 0, 9, T), Color(1, 1, 0, 0.8)) # Right
	# --- ZONE 0: THE FARMHOUSE (Slot 10) ---
	var house_x = 10 * T
	# Solid rich wood base spanning the entire tile
	image.fill_rect(Rect2i(house_x, 0, T, T), Color("5c4033"))
	# Draw floorboard gaps seamlessly from edge to edge
	for i in range(8):
		image.fill_rect(Rect2i(house_x + (i * 25), 0, 2, T), Color("3e2723"))
	# 11: The Road (Dark Grey Asphalt/Compacted Dirt)
	image.fill_rect(Rect2i(11 * T, 0, T, T), Color(0.2, 0.2, 0.22, 1.0))
	# Add some subtle tyre ruts/texture
	image.fill_rect(Rect2i((11 * T) + 31, 0, 13, T), Color(0.15, 0.15, 0.17, 1.0))
	image.fill_rect(Rect2i((11 * T) + 156, 0, 13, T), Color(0.15, 0.15, 0.17, 1.0))
	# 12: Duck House (Yellow)
	image.fill_rect(Rect2i(12 * T + 25, 25, 150, 150), Color("fff59d")) # 12: Duck House (Yellow)
	# 13: Stone Bridge Parapet (Solid stone wall running East-West)
	var br_x = 13 * T
	image.fill_rect(Rect2i(br_x, 0, T, T), Color("757575")) # Base stone
	image.fill_rect(Rect2i(br_x, 0, T, 25), Color("9e9e9e")) # Top highlight
	image.fill_rect(Rect2i(br_x, T - 25, T, 25), Color("424242")) # Bottom shadow
	# 14: The Stream (Clear, shallow blue water)
	var st_x = 14 * T
	image.fill_rect(Rect2i(st_x, 0, T, T), Color("29b6f6"))
	# Infrastructure (15–16 pig; 17–18 pen/gate moved from 13–14)
	image.fill_rect(Rect2i(15 * T + 50, 50, 100, 100), Color("ffcc80")) # 15: Honesty Box (Orange)
	image.fill_rect(Rect2i(16 * T + 25, 25, 150, 150), Color("f48fb1")) # 16: Pig House (Pink)
	image.fill_rect(Rect2i(17 * T, 75, T, 50), Color("8d6e63")) # 17: Pen Fence (Brown strip)
	image.fill_rect(Rect2i(18 * T + 50, 75, 100, 50), Color("5d4037")) # 18: Gate (Dark Brown)

	# --- STITCH DYNAMIC SPRITES ---
	grass_atlas_xs.clear()
	forest_atlas_xs.clear()
	stream_atlas_xs.clear()
	river_atlas_xs.clear()
	industrial_atlas_xs.clear()
	cultivated_atlas_xs.clear()
	var current_atlas_x = 19

	for key in dynamic_folders:
		for file in dynamic_folders[key]["files"]:
			var tex = load(dynamic_folders[key]["path"] + "/" + file) as Texture2D
			if tex:
				var img = tex.get_image()
				if img:
					if img.get_size() != Vector2i(200, 200):
						img.resize(200, 200)
					image.blend_rect(img, Rect2i(0, 0, 200, 200), Vector2i(current_atlas_x * 200, 0))

					if key == "grass":
						grass_atlas_xs.append(current_atlas_x)
					elif key == "forest":
						forest_atlas_xs.append(current_atlas_x)
					elif key == "stream":
						stream_atlas_xs.append(current_atlas_x)
					elif key == "river":
						river_atlas_xs.append(current_atlas_x)
					elif key == "industrial":
						industrial_atlas_xs.append(current_atlas_x)
					elif key == "cultivated":
						cultivated_atlas_xs.append(current_atlas_x)

					current_atlas_x += 1

	# --- STITCH CUSTOM PLANT SPRITES (user://databases/sprites/*.png) ---
	var stitch := _stitch_custom_plant_sprites(image, current_atlas_x)
	image = stitch["image"]
	current_atlas_x = int(stitch["atlas_x"])
	total_tiles = current_atlas_x

	image.generate_mipmaps()
	var image_texture := ImageTexture.create_from_image(image)
	var source := TileSetAtlasSource.new()
	source.texture = image_texture
	source.texture_region_size = Vector2i(200, 200)
	for tx in range(total_tiles):
		source.create_tile(Vector2i(tx, 0))

	var new_tile_set := TileSet.new()
	new_tile_set.tile_size = Vector2i(200, 200)
	new_tile_set.add_source(source, 0)
	tile_set = new_tile_set
	_next_custom_atlas_x = current_atlas_x

	tile_highlight = ColorRect.new()
	tile_highlight.size = Vector2(tile_set.tile_size)
	tile_highlight.color = Color(1.0, 1.0, 1.0, 0.2)
	tile_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_highlight.z_index = 50
	add_child(tile_highlight)

	# Dynamically generate the vertical rendering layers
	for layer_name in ["GroundLayer", "UnderstoryLayer", "CanopyLayer", "StructureLayer"]:
		if not has_node(layer_name):
			var new_layer = TileMapLayer.new()
			new_layer.name = layer_name
			new_layer.tile_set = tile_set # Inherit the tileset from the main map
			new_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

			# Ensure they stack visually from ground up to structures
			if layer_name == "GroundLayer":
				new_layer.z_index = 1
			elif layer_name == "UnderstoryLayer":
				new_layer.z_index = 2
			elif layer_name == "CanopyLayer":
				new_layer.z_index = 3
			elif layer_name == "StructureLayer":
				new_layer.z_index = 4

			add_child(new_layer)

	# Data lenses: Sprite2D 128² base → overlay.scale Vector2(200, 200) per cell (no set_cell_modulate / no per-tile tint loop).
	overlay = Sprite2D.new()
	overlay.name = "LensOverlay"
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	overlay.scale = Vector2(200, 200)
	overlay.centered = false
	overlay.z_index = 5
	overlay.hide()
	add_child(overlay)

	farmer = Sprite2D.new()
	farmer.name = "Farmer"
	farmer.centered = true
	# Load the actual sprite instead of creating a square image
	var active_w = FarmDataManager.get_active_worker()
	var tex_path = active_w.get("sprite", "res://icon.svg")
	if ResourceLoader.exists(tex_path):
		farmer.texture = load(tex_path)
	else:
		farmer.texture = preload("res://icon.svg")
	farmer.z_index = 10
	farmer.scale = Vector2(1.5, 1.5)
	farmer.offset = Vector2(0, -60)
	add_child(farmer)

	# 3. Generate Grid Data
	# --- BIOME GENERATION ---
	if FarmDataManager.custom_starting_grid_loaded and FarmDataManager.grid_data.size() > 0:
		_boot_from_custom_starting_grid()
	else:
		_generate_procedural_grid_data()
	_sanitize_duck_corridor_tiles()

	# 4. Connect HUD
	var hud_scene = preload("res://scenes/hud.tscn")
	hud_instance = hud_scene.instantiate()
	add_child(hud_instance)
	if hud_instance.has_method("update_action_button_text"):
		hud_instance.update_action_button_text("Rotovator")

	if hud_instance.get("vitals_label"):
		vitals_label = hud_instance.vitals_label
	hover_label = hud_instance.get_node_or_null(
		"CanvasLayer/InfoDock/DockMargin/DockScroll/DockBody/Hover_Label"
	)
	right_info_panel = hud_instance.get_node_or_null("CanvasLayer/InfoDock") as PanelContainer
	almanac_window = hud_instance.get_node_or_null("CanvasLayer/Almanac_Window") as Window
	modal_dimmer = hud_instance.get_node_or_null("CanvasLayer/Modal_Dimmer") as ColorRect

	# Wire up draggable Window title-bar close buttons
	if almanac_window:
		almanac_window.close_requested.connect(close_almanac)

	hud_instance.action_selected.connect(_on_hud_action_selected)
	if hud_instance.has_signal("produce_action_requested"):
		hud_instance.produce_action_requested.connect(process_produce_action)
	hud_instance.lens_selected.connect(_on_hud_lens_selected)
	if hud_instance.has_signal("inventory_selected"):
		hud_instance.inventory_selected.connect(_on_hud_inventory_selected)
	if hud_instance.has_signal("undo_pressed"):
		hud_instance.undo_pressed.connect(undo_last_action)
	if hud_instance.has_signal("redo_pressed"):
		hud_instance.redo_pressed.connect(redo_action)
	hud_instance.save_requested.connect(func(save_name: String): _save_manager.save_game(self, save_name))
	hud_instance.load_requested.connect(func(save_name: String):
		_save_manager.load_game(self, save_name)
		_sanitize_duck_corridor_tiles()
		_refresh_all_visuals()
	)

	if hud_instance.has_signal("main_menu_requested"):
		hud_instance.main_menu_requested.connect(func():
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		)

	narrative_ui = preload("res://scripts/ui_narrative_popup.gd").new()
	narrative_ui.hide()
	hud_instance.get_node("CanvasLayer").add_child(narrative_ui)
	narrative_ui.option_selected.connect(_on_narrative_option)

	karma_shop = preload("res://scripts/ui_karma_shop.gd").new()
	karma_shop.hide()
	hud_instance.get_node("CanvasLayer").add_child(karma_shop)
	karma_shop.reincarnate_pressed.connect(func():
		get_tree().paused = false
		get_tree().reload_current_scene()
	)

	_refresh_live_right_panel()

	if hud_instance.has_method("refresh_workers_ui"):
		hud_instance.refresh_workers_ui()

	if FarmDataManager.is_time_machine_enabled():
		if hud_instance.has_method("setup_time_machine_ui"):
			hud_instance.setup_time_machine_ui()
		FarmDataManager._snapshot_grid()
		_update_time_machine_timeline()

	door_menu = PopupMenu.new()
	door_menu.add_item("Enter House (WIP)", 0)
	door_menu.add_item("Sleep / Next Turn", 1)
	add_child(door_menu)
	door_menu.id_pressed.connect(_on_door_menu_pressed)

	# Generate Hover Layer
	var hover_layer = TileMapLayer.new()
	hover_layer.name = "HoverLayer"
	hover_layer.tile_set = tile_set
	hover_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hover_layer.z_index = 10 # Draw above everything
	add_child(hover_layer)

	# Generate Tooltip Canvas
	tooltip_canvas = CanvasLayer.new()
	tooltip_canvas.layer = 100 # Draw above HUD
	add_child(tooltip_canvas)

	tooltip_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.8, 0.8, 0.2, 1.0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	tooltip_panel.add_theme_stylebox_override("panel", style)

	tooltip_label = RichTextLabel.new()
	tooltip_label.fit_content = true
	tooltip_label.bbcode_enabled = true
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	tooltip_panel.add_child(tooltip_label)
	tooltip_canvas.add_child(tooltip_panel)
	tooltip_panel.hide()

	_refresh_minimap()
	set_current_tool("")

	if RadioManager.has_signal("native_beat_hit"):
		RadioManager.native_beat_hit.connect(_on_rhythm_tick)

	# --- THE AMBIENT SYNTHESISER ---
	# 1. Bathe the master bus in a huge, dreamy reverb (once — avoid stacking on scene reload)
	var bus_idx = AudioServer.get_bus_index("Master")
	var has_master_reverb := false
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		if AudioServer.get_bus_effect(bus_idx, i) is AudioEffectReverb:
			has_master_reverb = true
			break
	if not has_master_reverb:
		var reverb = AudioEffectReverb.new()
		reverb.room_size = 0.85
		reverb.damping = 0.4
		reverb.wet = 0.35
		AudioServer.add_bus_effect(bus_idx, reverb)

	# Create a dedicated "Echo" bus ONLY if it doesn't already exist
	var echo_idx = AudioServer.get_bus_index("Echo")
	if echo_idx == -1:
		AudioServer.add_bus(-1) # Add to the end
		echo_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(echo_idx, "Echo")
		AudioServer.set_bus_send(echo_idx, "Master")
		AudioServer.set_bus_volume_db(echo_idx, -4.0) # Much louder base volume

		# Apply a gentler Low-Pass Filter so the chime is muffled but audible
		var lpf = AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 1500.0 # Raised from 600Hz so the chime survives the filter
		lpf.resonance = 0.5
		AudioServer.add_bus_effect(echo_idx, lpf)

	# 2. Spawn a pool of 12 audio players so notes can overlap and ring out naturally
	for i in range(12):
		var p = AudioStreamPlayer.new()
		p.stream = base_chime
		add_child(p)
		audio_pool.append(p)

	# --- STRUCTURE OVERLAY ---
	structure_overlay = StructureOverlayNode.new()
	structure_overlay.z_index = 10 # Ensure it renders above the ground tiles and plants
	structure_overlay.map_ref = self
	add_child(structure_overlay)
	structure_overlay.queue_redraw()

	# --- ENERGY LENS BLACKOUT ---
	energy_blackout = ColorRect.new()
	energy_blackout.size = Vector2(_map_w() * 200, _map_h() * 200)
	energy_blackout.color = Color(0.02, 0.02, 0.04, 0.92) # Almost pure black/deep space blue
	energy_blackout.z_index = 5 # Sits above the dirt and crops, but below structures (10) and particles (90)
	energy_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	energy_blackout.hide()
	add_child(energy_blackout)

	energy_zone_overlay = EnergyZoneOverlayNode.new()
	energy_zone_overlay.name = "EnergyZoneOverlayNode"
	energy_zone_overlay.z_index = 7
	energy_zone_overlay.map_ref = self
	energy_zone_overlay.hide()
	add_child(energy_zone_overlay)

	energy_cursor_overlay = EnergyCursorOverlayNode.new()
	energy_cursor_overlay.name = "EnergyCursorOverlayNode"
	energy_cursor_overlay.z_index = 9
	energy_cursor_overlay.map_ref = self
	energy_cursor_overlay.hide()
	add_child(energy_cursor_overlay)

	maintenance_bubble_overlay = MaintenanceBubbleOverlayNode.new()
	maintenance_bubble_overlay.name = "MaintenanceBubbleOverlay"
	maintenance_bubble_overlay.z_index = 8
	maintenance_bubble_overlay.map_ref = self
	maintenance_bubble_overlay.hide()
	add_child(maintenance_bubble_overlay)

	# --- OPTIMISED TRUE DESATURATION SHADER ---
	greyscale_overlay = ColorRect.new()
	greyscale_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	greyscale_overlay.z_index = 7 # Above the map, below the GuildOverlayNode(8)
	greyscale_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var grey_shader := Shader.new()
	grey_shader.code = """
shader_type canvas_item;
// CRITICAL: 'filter_nearest' stops the engine from doing heavy blur calculations
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

void fragment() {
	vec4 current_colour = texture(screen_texture, SCREEN_UV);

	// Calculate the true luminance (brightness) of the pixel
	float lum = dot(current_colour.rgb, vec3(0.299, 0.587, 0.114));

	// Mix the original colour with pure greyscale.
	// 0.85 means it is 85% grey, 15% original colour, leaving a tiny bit of life.
	vec3 washed = mix(current_colour.rgb, vec3(lum), 0.85);

	// Add a slight brightness boost (0.05) so the screen doesn't feel oppressive
	COLOR = vec4(washed + vec3(0.05), current_colour.a);
}
"""
	var grey_mat := ShaderMaterial.new()
	grey_mat.shader = grey_shader
	greyscale_overlay.material = grey_mat

	# Must live on a CanvasLayer to cover the screen; prefer HUD CanvasLayer when available.
	if is_instance_valid(hud_instance):
		hud_instance.get_node("CanvasLayer").add_child(greyscale_overlay)
	else:
		add_child(greyscale_overlay)
	greyscale_overlay.hide()

	var guild_overlay = GuildOverlayNode.new()
	guild_overlay.name = "GuildOverlayNode"
	guild_overlay.z_index = 8
	guild_overlay.map_ref = self
	guild_overlay.hide()
	add_child(guild_overlay)

	# --- LIVE TOOL PREVIEW ---
	preview_overlay = PreviewOverlayNode.new()
	preview_overlay.z_index = 20 # Sits above absolutely everything
	preview_overlay.map_ref = self
	add_child(preview_overlay)
	preview_overlay.queue_redraw()

	design_overlay = DesignOverlayNode.new()
	design_overlay.z_index = 85
	design_overlay.map_ref = self
	add_child(design_overlay)

	# --- TRIAGE OVERLAY ---
	triage_overlay = TriageOverlayNode.new()
	triage_overlay.name = "TriageOverlay"
	triage_overlay.z_index = 80
	triage_overlay.map_ref = self
	add_child(triage_overlay)

	_setup_floating_text_pool()

	# --- INITIALIZE FORECAST ---
	# Five-day queue: calendar days current_turn … current_turn+4. Scripted rows in data/story_weather.csv (DataScenario).
	forecast.clear()
	for i in range(5):
		var target_day: int = FarmDataManager.current_turn + i
		forecast.append(_get_weather_for_day(target_day))

	# --- THE REINCARNATION SCREEN ---
	death_panel = PanelContainer.new()
	death_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_panel.hide()
	death_panel.z_index = 100
	death_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var death_style = StyleBoxFlat.new()
	death_style.bg_color = Color(0.05, 0.05, 0.08, 0.98)
	death_panel.add_theme_stylebox_override("panel", death_style)

	var death_vbox = VBoxContainer.new()
	death_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	death_panel.add_child(death_vbox)
	if is_instance_valid(hud_instance):
		hud_instance.get_node("CanvasLayer").add_child(death_panel)
	else:
		add_child(death_panel)

	# --- APPLY META UPGRADES ---
	if MetaManager.has_upgrade("trust_fund"):
		FarmDataManager.current_money += 30
	if MetaManager.has_upgrade("poltergeist_labour"):
		var aw_pl := FarmDataManager.get_active_worker()
		if not aw_pl.is_empty():
			aw_pl["max_energy"] = aw_pl.get("max_energy", 20) + 2
			aw_pl["energy"] = aw_pl["max_energy"]
		_sync_hud_status()

	_refresh_all_visuals()

	# --- PENDING LOAD FROM MAIN MENU (needs map node for SaveManager.load_game) ---
	# --- GENERATION 1 STORY (fresh run: £100, full seed roster, intro + CSV tutorial beats) ---
	var pending_save: String = _save_manager.pending_load_save_name
	if pending_save != "":
		_save_manager.pending_load_save_name = ""
		_save_manager.load_game(self, pending_save)
		_sanitize_plants_on_infra_cells()
		_sanitize_duck_corridor_tiles()
		_refresh_all_visuals()
		var sp_clear = hud_instance.get_node_or_null("CanvasLayer/SeedPicker")
		if sp_clear:
			sp_clear.allowed_seed_ids.clear()
	elif not MetaManager.dev_mode:
		var sp = hud_instance.get_node_or_null("CanvasLayer/SeedPicker")
		if sp:
			sp.allowed_seed_ids.clear()
		call_deferred("_sync_hud_money")
		if FarmDataManager.active_campaign_id == "wormfood":
			call_deferred("_trigger_intro_dialogue")
		elif FarmDataManager.active_campaign_id == "tutorial":
			call_deferred("_trigger_intro_dialogue", "tut_day_1")
	else:
		var sp_dev = hud_instance.get_node_or_null("CanvasLayer/SeedPicker")
		if sp_dev:
			sp_dev.allowed_seed_ids.clear()

	_init_farm_astar()
	_sync_hud_status()
	call_deferred("_snap_camera_to_farmhouse")


func _snap_camera_to_farmhouse() -> void:
	if not is_instance_valid(main_camera):
		return
	var target := map_to_local(farmhouse_pos)
	main_camera.global_position = target
	main_camera.desired_pos = target
	if FarmDataManager.map_width >= 100:
		main_camera.zoom = Vector2(0.25, 0.25)
		main_camera.target_zoom = 0.25
	elif FarmDataManager.map_width <= 32:
		main_camera.zoom = Vector2(0.5, 0.5)
		main_camera.target_zoom = 0.5
	else:
		main_camera.zoom = Vector2(0.8, 0.8)
		main_camera.target_zoom = 0.8
	if main_camera.has_method("_apply_map_bounds_from_farm"):
		main_camera._apply_map_bounds_from_farm()


func _sync_hud_money() -> void:
	if not is_instance_valid(hud_instance):
		return
	if vitals_label == null or not is_instance_valid(vitals_label):
		if hud_instance.get("vitals_label"):
			vitals_label = hud_instance.vitals_label
	if vitals_label:
		_sync_hud_status()


func _sync_hud_status() -> void:
	if not is_instance_valid(hud_instance):
		return
	if hud_instance.get("vitals_label") and hud_instance.vitals_label:
		var max_pwr := FarmDataManager.get_max_power_capacity()
		var max_h2o := FarmDataManager.get_max_water_capacity()
		hud_instance.vitals_label.text = "£%d | ⚡ %d/%d | 💧 %d/%d | Turn %d" % [
			FarmDataManager.current_money,
			FarmDataManager.current_power,
			max_pwr,
			FarmDataManager.current_water,
			max_h2o,
			FarmDataManager.current_turn,
		]
	if hud_instance.has_method("refresh_political_metrics_bar"):
		hud_instance.refresh_political_metrics_bar()
	if hud_instance.has_method("refresh_workers_ui"):
		hud_instance.refresh_workers_ui()


func _calculate_maintenance_bubble() -> void:
	maintenance_bubble.clear()

	# Find the worker assigned to maintenance
	var maintenance_worker: Dictionary = {}
	for w in FarmDataManager.workers:
		if w.get("role") == "maintenance":
			maintenance_worker = w
			break

	# If nobody is assigned to maintenance, abort completely.
	if maintenance_worker.is_empty():
		return

	# Pull the unspent energy directly from the maintenance worker, NOT the active worker
	var unspent_energy := float(maintenance_worker.get("energy", 0))
	if unspent_energy <= 0.0:
		return

	# --- FAST BFS (NO ARRAY RE-INDEXING OR SORTING) ---
	# Cap the energy processed so it doesn't freeze the engine in Dev Mode
	unspent_energy = minf(unspent_energy, 60.0)
	var queue: Array = [[farmhouse_pos, unspent_energy]]
	var visited: Dictionary = {farmhouse_pos: unspent_energy}

	var head := 0
	while head < queue.size():
		var current: Array = queue[head]
		head += 1 # Move the pointer instead of pop_front() to save performance

		var pos: Vector2i = current[0]
		var energy: float = current[1]

		if not pos in maintenance_bubble:
			maintenance_bubble.append(pos)

		var dirs: Array[Vector2i] = [
			Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)
		]
		for d in dirs:
			var neighbor: Vector2i = pos + d
			if neighbor.x >= 0 and neighbor.x < _map_w() and neighbor.y >= 0 and neighbor.y < _map_h():
				var cell: Dictionary = FarmDataManager.grid_data[neighbor.x][neighbor.y]
				var move_cost := 0.2 if _cell_has_cheap_traversal(cell) else 1.0
				var next_energy := energy - move_cost

				if next_energy > 0.0:
					if not visited.has(neighbor) or float(visited[neighbor]) < next_energy:
						visited[neighbor] = next_energy
						queue.append([neighbor, next_energy])


func _energy_step_cost_for_cell(cell: Dictionary) -> float:
	var land := str(cell.get("land", ""))
	if land == "stream":
		return 999.0
	if land == "bridge" or _cell_has_cheap_traversal(cell):
		return 0.3
	if land == "river":
		return 3.0
	return 1.0


func _energy_heap_push_heap(heap: Array, item: Dictionary) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if heap[p]["cost"] <= heap[i]["cost"]:
			break
		var tmp: Dictionary = heap[p]
		heap[p] = heap[i]
		heap[i] = tmp
		i = p


func _energy_heap_pop_heap(heap: Array) -> Dictionary:
	if heap.is_empty():
		return {}
	var n := heap.size()
	var root: Dictionary = heap[0]
	if n == 1:
		heap.clear()
		return root
	heap[0] = heap[n - 1]
	heap.resize(n - 1)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := i * 2 + 2
		var sm := i
		if l < heap.size() and heap[l]["cost"] < heap[sm]["cost"]:
			sm = l
		if r < heap.size() and heap[r]["cost"] < heap[sm]["cost"]:
			sm = r
		if sm == i:
			break
		var t: Dictionary = heap[i]
		heap[i] = heap[sm]
		heap[sm] = t
		i = sm
	return root


func _calculate_energy_zones() -> void:
	if not is_instance_valid(farmer):
		return
	var start_cell := local_to_map(farmer.position)
	if start_cell == _cached_farmer_pos and not _energy_zone_cache.is_empty():
		return

	_energy_zone_cache.clear()
	_energy_came_from.clear()
	_cached_farmer_pos = start_cell

	if start_cell.x < 0 or start_cell.x >= _map_w() or start_cell.y < 0 or start_cell.y >= _map_h():
		return

	var heap: Array = []
	_energy_zone_cache[start_cell] = 0.0
	_energy_heap_push_heap(heap, {"pos": start_cell, "cost": 0.0})

	while heap.size() > 0:
		var current: Dictionary = _energy_heap_pop_heap(heap)
		var pos: Vector2i = current["pos"]
		var current_cost: float = current["cost"]
		if current_cost > float(_energy_zone_cache.get(pos, INF)):
			continue

		for d in ENERGY_ZONE_DIRS:
			var next_pos: Vector2i = pos + d
			if next_pos.x < 0 or next_pos.x >= _map_w() or next_pos.y < 0 or next_pos.y >= _map_h():
				continue
			var cell_data: Dictionary = FarmDataManager.grid_data[next_pos.x][next_pos.y]
			var step_cost := _energy_step_cost_for_cell(cell_data)
			var next_cost := current_cost + step_cost
			if next_cost > ENERGY_ZONE_MAX_COST:
				continue
			if not _energy_zone_cache.has(next_pos) or next_cost < float(_energy_zone_cache[next_pos]):
				_energy_zone_cache[next_pos] = next_cost
				_energy_came_from[next_pos] = pos
				_energy_heap_push_heap(heap, {"pos": next_pos, "cost": next_cost})

	_last_energy_mouse_cell = Vector2i(-1, -1)
	_last_energy_bg_farmer_cell = Vector2i(-1, -1)


func _energy_cost_to_zone(cost: float) -> int:
	if cost > 120.0:
		return 5
	if cost > 90.0:
		return 4
	if cost > 60.0:
		return 3
	if cost > 35.0:
		return 2
	if cost > 15.0:
		return 1
	return 0


func _draw_energy_background(canvas: CanvasItem) -> void:
	_calculate_energy_zones()

	var vibrant_colors: Array[Color] = [
		Color(0.0, 0.6, 1.0, 0.15), # Zone 0: Bright Cyan/Blue
		Color(0.6, 1.0, 0.0, 0.15), # Zone 1: Lime
		Color(1.0, 0.9, 0.0, 0.15),
		Color(1.0, 0.5, 0.0, 0.15),
		Color(1.0, 0.0, 0.5, 0.15),
		Color(0.5, 0.0, 1.0, 0.15),
	]

	var zones: Dictionary = {0: [], 1: [], 2: [], 3: [], 4: [], 5: []}
	for cell in _energy_zone_cache:
		var cost: float = float(_energy_zone_cache[cell])
		var zone: int = _energy_cost_to_zone(cost)
		zones[zone].append(cell)

	var cam := get_viewport().get_camera_2d()
	var visible_rect := Rect2()
	if cam:
		var vp_size := get_viewport_rect().size / cam.zoom
		visible_rect = Rect2(cam.global_position - vp_size / 2.0, vp_size).grow(468)

	for z in range(5, -1, -1):
		var c: Color = vibrant_colors[z]
		for cell in zones[z]:
			var center = map_to_local(cell as Vector2i)
			if visible_rect.size != Vector2.ZERO and not visible_rect.has_point(to_global(center)):
				continue
			canvas.draw_circle(center, 234, c)
			if _cell_has_cheap_traversal(FarmDataManager.grid_data[cell.x][cell.y]):
				canvas.draw_circle(center, 62, Color(1, 1, 1, 0.2))

	var current_zoom := 1.0
	if cam:
		current_zoom = cam.zoom.x

	# 2.5 DRAW GIRIH MOSAIC PATTERNS (With LOD)
	for z in range(5, -1, -1):
		var base_color: Color = vibrant_colors[z]
		var geo_color: Color = base_color.blend(Color(1.0, 1.0, 1.0, 0.4))
		geo_color.a = 0.8

		for cell in zones[z]:
			var center_g = map_to_local(cell as Vector2i)
			if visible_rect.size != Vector2.ZERO and not visible_rect.has_point(to_global(center_g)):
				continue
			var c_data: Dictionary = FarmDataManager.grid_data[cell.x][cell.y]
			var land: String = str(c_data.get("land", ""))
			var has_plant := false
			for layer_key in ["canopy", "understory", "ground"]:
				if _cell_str_nonempty(c_data, layer_key):
					has_plant = true
					break

			# --- HIGH DETAIL (Zoomed In) ---
			if current_zoom >= 0.6:
				if has_plant:
					_draw_girih_pattern(canvas, center_g, 12, 78, 54, geo_color, 4)
					canvas.draw_circle(center_g, 15, geo_color)
				elif land == "cultivated":
					_draw_girih_pattern(canvas, center_g, 8, 70, 35, geo_color, 3)
				elif land == "swale":
					_draw_girih_pattern(canvas, center_g, 4, 85, 85, Color(0.2, 0.8, 1.0, 0.6), 3)
					_draw_girih_pattern(canvas, center_g, 4, 54, 54, Color(0.2, 0.8, 1.0, 0.6), 1)
				elif str(c_data.get("type", land)) == "stream":
					# STREAMS: Extremely cheap GPU rendering. Translucent blue overlay with simple current lines.
					var stream_rect := Rect2(center_g - Vector2(100, 100), Vector2(200, 200))
					canvas.draw_rect(stream_rect, Color(0.0, 0.3, 0.8, 0.4), true)
					canvas.draw_line(center_g - Vector2(62, 23), center_g + Vector2(62, 23), Color(0.0, 0.8, 1.0, 0.5), 4)
					canvas.draw_line(center_g - Vector2(39, -23), center_g + Vector2(39, -23), Color(0.0, 0.8, 1.0, 0.5), 4)
				elif _cell_has_cheap_traversal(c_data) or land == "bridge":
					# PATHS & BRIDGES: Interlocking geometric squares
					var path_rect := Rect2(center_g - Vector2(50, 50), Vector2(100, 100))
					canvas.draw_rect(path_rect, Color(1.0, 0.9, 0.1, 0.6), false, 4)
					_draw_girih_pattern(canvas, center_g, 4, 70, 70, Color(1.0, 0.9, 0.1, 0.6), 3)
				else:
					canvas.draw_circle(center_g, 3, geo_color * Color(1, 1, 1, 0.3))
					_draw_girih_pattern(canvas, center_g, 6, 93, 78, geo_color * Color(1, 1, 1, 0.2), 1)

			# --- MEDIUM DETAIL (Mid-Zoom) ---
			elif current_zoom >= 0.25:
				if has_plant:
					_draw_girih_pattern(canvas, center_g, 6, 78, 54, geo_color, 3)
				elif land == "cultivated":
					_draw_girih_pattern(canvas, center_g, 4, 70, 70, geo_color, 2)
				elif land == "swale":
					_draw_girih_pattern(canvas, center_g, 4, 85, 85, Color(0.2, 0.8, 1.0, 0.6), 2)
				elif str(c_data.get("type", land)) == "stream":
					var stream_rect_m := Rect2(center_g - Vector2(100, 100), Vector2(200, 200))
					canvas.draw_rect(stream_rect_m, Color(0.0, 0.3, 0.8, 0.4), true)
					canvas.draw_line(center_g - Vector2(62, 0), center_g + Vector2(62, 0), Color(0.0, 0.8, 1.0, 0.5), 3)
				elif _cell_has_cheap_traversal(c_data) or land == "bridge":
					var rect := Rect2(center_g - Vector2(50, 50), Vector2(100, 100))
					canvas.draw_rect(rect, Color(1.0, 0.9, 0.1, 0.6), false, 3)

			# --- LOW DETAIL (Fully Zoomed Out) ---
			else:
				pass


func _draw_energy_cursor(canvas: CanvasItem) -> void:
	_calculate_energy_zones()
	var font := ThemeDB.fallback_font

	var vibrant_colors: Array[Color] = [
		Color(0.0, 0.6, 1.0, 0.15), # Zone 0: Bright Cyan/Blue
		Color(0.6, 1.0, 0.0, 0.15), # Zone 1: Lime
		Color(1.0, 0.9, 0.0, 0.15),
		Color(1.0, 0.5, 0.0, 0.15),
		Color(1.0, 0.0, 0.5, 0.15),
		Color(0.5, 0.0, 1.0, 0.15),
	]

	var zones: Dictionary = {0: [], 1: [], 2: [], 3: [], 4: [], 5: []}
	for cell in _energy_zone_cache:
		var cost: float = float(_energy_zone_cache[cell])
		var zone: int = _energy_cost_to_zone(cost)
		zones[zone].append(cell)

	for z in range(0, 6):
		if zones[z].size() > 0:
			var label_pos = map_to_local(zones[z][0] as Vector2i) + Vector2(-46, 0)
			var text_color = vibrant_colors[z].blend(Color(1, 1, 1, 0.8))
			canvas.draw_string_outline(
				font,
				label_pos,
				"ZONE " + str(z),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				50,
				9,
				Color(0, 0, 0, 0.8)
			)
			canvas.draw_string(
				font,
				label_pos,
				"ZONE " + str(z),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				50,
				text_color
			)


func _hide_hover_for_narrative() -> void:
	if is_instance_valid(hud_instance) and hud_instance.inspector_panel:
		hud_instance.inspector_panel.hide()
	if tooltip_panel:
		tooltip_panel.hide()


func _trigger_intro_dialogue(dialogue_id: String = "intro") -> void:
	if not is_instance_valid(narrative_ui):
		return
	_hide_hover_for_narrative()
	var story := NarrativeData.get_dialogue(dialogue_id)
	if story.is_empty() and dialogue_id == "intro":
		story = NarrativeData.get_dialogue("0")
	if not story.is_empty():
		narrative_ui.show_dialogue(story["title"], story["body"], story["options"])


func _trigger_tutorial_beat(dialogue_id: String, flash_forecast: bool = false) -> void:
	_trigger_intro_dialogue(dialogue_id)
	if flash_forecast and is_instance_valid(hud_instance) and hud_instance.has_method("flash_forecast_attention"):
		hud_instance.flash_forecast_attention()


func _on_narrative_option(opt_id: String) -> void:
	if is_instance_valid(narrative_ui):
		narrative_ui.hide()

	if opt_id == "die":
		if FarmDataManager.active_campaign_id == "wormfood":
			MetaManager.current_insight += 7
			MetaManager.save_meta()
			get_tree().paused = true
			if is_instance_valid(karma_shop):
				karma_shop.refresh_from_meta()
				karma_shop.show()
		else:
			_trigger_game_over()
		return

	if opt_id == "recruit_digger":
		FarmDataManager.workers.append({
			"id": "worker_" + str(Time.get_ticks_msec()), "name": "Earthworker", "color": "ff5722",
			"role": "active", "skills": {"dig": 1.5, "maintain": 0.8}, "action_queue": [],
			"energy": 25, "max_energy": 25,
			"sprite": "res://assets/base/sprites/characters/workers/earthworker.png"
		})
	elif opt_id == "recruit_tender":
		FarmDataManager.workers.append({
			"id": "worker_" + str(Time.get_ticks_msec()), "name": "Caretaker", "color": "81c784",
			"role": "maintenance", "skills": {"dig": 0.8, "maintain": 1.5}, "action_queue": [],
			"energy": 15, "max_energy": 15,
			"sprite": "res://assets/base/sprites/characters/workers/caretaker.png"
		})

	if opt_id == "recruit_digger" or opt_id == "recruit_tender":
		if hud_instance and hud_instance.has_method("refresh_workers_ui"):
			hud_instance.refresh_workers_ui()

	get_tree().paused = false
	if opt_id == "start":
		pass


func _trigger_reincarnation(add_insight: bool = true) -> void:
	if FarmDataManager.active_campaign_id != "wormfood":
		_trigger_game_over()
		return

	is_sleeping = true # Lock the game
	if add_insight:
		_run_earned_insight = int(float(FarmDataManager.current_turn) / 2.0)
		MetaManager.current_insight += _run_earned_insight
		MetaManager.save_meta()

	var vbox = death_panel.get_child(0) as VBoxContainer
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.free() # Clear old buttons (immediate so rebuild does not stack)

	var title = Label.new()
	title.text = "ECOSYSTEM COLLAPSED\nSimulation ended.\nEarned %d Insight. Total: %d" % [_run_earned_insight, MetaManager.current_insight]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	# Build the Meta-Dashboard upgrade list
	for u_id in MetaManager.upgrade_db:
		var u_data = MetaManager.upgrade_db[u_id]
		var captured_id: String = str(u_id)
		var btn = Button.new()
		var is_owned = MetaManager.has_upgrade(captured_id)
		btn.text = "%s - %s (%d Insight)\n%s" % [u_data["type"], u_data["name"], u_data["cost"], u_data["desc"]]
		btn.disabled = is_owned or MetaManager.current_insight < u_data["cost"]
		if is_owned:
			btn.text += " [OWNED]"

		btn.pressed.connect(func():
			if MetaManager.buy_upgrade(captured_id):
				_trigger_reincarnation(false) # Refresh the screen to update buttons and totals
		)
		vbox.add_child(btn)

	var restart_btn = Button.new()
	restart_btn.text = "START NEW SIMULATION"
	restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(restart_btn)

	death_panel.show()


func _trigger_game_over() -> void:
	is_sleeping = true
	get_tree().paused = true

	var vbox := death_panel.get_child(0) as VBoxContainer
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.free()

	var title := Label.new()
	title.text = "Game Over"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "This campaign has ended."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var menu_btn := Button.new()
	menu_btn.text = "Return to Main Menu"
	menu_btn.pressed.connect(func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	vbox.add_child(menu_btn)

	death_panel.show()


func _on_door_menu_pressed(id: int) -> void:
	if id == 1:
		trigger_sleep()


func _on_hud_action_selected(item: String) -> void:
	if item == "open_produce_menu":
		if hud_instance and hud_instance.has_method("refresh_produce_ui"):
			hud_instance.refresh_produce_ui(FarmDataManager.inventory)
		return
	if item.begins_with("plant:"):
		set_current_tool("plant", item.split(":")[1])
	else:
		match item:
			"Rotovator":
				set_current_tool("rotovate")
			"Scythe":
				set_current_tool("scythe")
			"Uproot":
				set_current_tool("uproot")
			"Harvest":
				set_current_tool("harvest")
			"Chop & Drop":
				set_current_tool("chop_and_drop")
			"Dig Swale":
				set_current_tool("dig_swale")
			"Build Mound":
				set_current_tool("build_mound")
			"Water":
				set_current_tool("water_tile")
			"Compost Tea":
				set_current_tool("apply_tea")
			"E-Tiller (1⚡)":
				set_current_tool("e_tiller")
			"Hosepipe (1💧)":
				set_current_tool("hosepipe")
			"Plant":
				set_current_tool("plant", "")
				if hud_instance:
					var sp := hud_instance.get_node_or_null("CanvasLayer/SeedPicker")
					if sp and sp.has_method("populate_and_show"):
						sp.populate_and_show()
			"Build Structure":
				set_current_tool("build")


func _on_hud_lens_selected(item: String) -> void:
	match item:
		"Standard View":
			active_lens = "normal"
		"Hydration Lens":
			active_lens = "moisture"
		"Nutrient Lens":
			active_lens = "nitrogen"
		"Growth Lens":
			active_lens = "growth"
		"Design View":
			active_lens = "design"
		"Guild Vision":
			active_lens = "guild"
		"energy", "Energy Vision":
			active_lens = "energy"
	_refresh_all_visuals()


func _on_hud_inventory_selected(_item: String) -> void:
	pass


func _refresh_live_right_panel() -> void:
	if not is_instance_valid(hud_instance):
		return
	var fc: RichTextLabel = hud_instance.get_node_or_null(
		"CanvasLayer/InfoDock/DockMargin/DockScroll/DockBody/Forecast_Events_Content"
	) as RichTextLabel
	if not is_instance_valid(fc):
		return

	unread_mail = false
	if hud_instance.has_method("apply_mail_indicator"):
		hud_instance.apply_mail_indicator(false)

	var bbcode = ""

	# 1. WEATHER FORECAST
	bbcode += "[b]5-Day Forecast[/b]\n"
	for i in range(forecast.size()):
		var w_id = forecast[i]
		if not weather_types.has(w_id):
			continue
		var w_name = weather_types[w_id]["name"]
		var w_col = weather_types[w_id]["color"]
		var day_label = "Tomorrow:" if i == 0 else "Day +" + str(i + 1) + ":"
		bbcode += "[color=#aaaaaa]%s[/color] [color=#%s]%s[/color]\n" % [day_label, w_col, w_name]

	# 2. INBOX & EVENTS
	bbcode += "\n[b]Inbox & Events[/b]\n"
	if inbox_messages.is_empty():
		bbcode += "[color=#888888]No recent events.[/color]\n"
	else:
		for m in inbox_messages:
			bbcode += m + "\n"

	# 3. ECONOMY & META
	bbcode += "\n[b]Status[/b]\n"
	bbcode += "Research Insight: %d\n" % MetaManager.current_insight
	bbcode += "[color=#888888]Market prices for produce remain stable.[/color]"

	fc.text = bbcode


func open_almanac() -> void:
	if is_sleeping:
		return
	if not is_instance_valid(hud_instance):
		return
	var dim: ColorRect = hud_instance.get_node_or_null("CanvasLayer/Modal_Dimmer") as ColorRect
	var content: RichTextLabel = hud_instance.get_node_or_null(
		"CanvasLayer/Almanac_Window/MarginContainer/VBoxContainer/Almanac_Content"
	) as RichTextLabel
	if dim:
		dim.show()
	almanac_open = true
	var entries: Dictionary = preload("res://data/data_almanac.gd").ENTRIES
	var bb := ""
	for title in entries.keys():
		bb += "[b]%s[/b]\n%s\n\n" % [title, str(entries[title])]
	if content:
		content.text = bb
	if is_instance_valid(almanac_window):
		almanac_window.show()
	get_tree().paused = true


func close_almanac() -> void:
	almanac_open = false
	if is_instance_valid(almanac_window):
		almanac_window.hide()
	if is_instance_valid(hud_instance):
		var dim: ColorRect = hud_instance.get_node_or_null("CanvasLayer/Modal_Dimmer") as ColorRect
		if dim:
			dim.hide()
	if not is_sleeping:
		get_tree().paused = false


func _refresh_all_visuals() -> void:
	update_visuals()
	apply_lens()
	if is_instance_valid(structure_overlay) and not is_sleeping:
		structure_overlay.queue_redraw()
	if is_instance_valid(preview_overlay):
		preview_overlay.queue_redraw()
	var hover_layer_refresh = get_node_or_null("HoverLayer")
	if hover_layer_refresh:
		hover_layer_refresh.queue_redraw()


func _refresh_minimap() -> void:
	var img = Image.create(_map_w(), _map_h(), false, Image.FORMAT_RGBA8)

	for x in range(_map_w()):
		for y in range(_map_h()):
			var cell = FarmDataManager.grid_data[x][y]
			var col = Color("4caf50") # Default wild grass

			# 1. Base Terrain Colours
			if cell["land"] == "road":
				col = Color("424242")
			elif cell["land"] == "river":
				col = Color("1e88e5")
			elif cell["land"] == "bridge":
				col = Color("9e9e9e")
			elif cell["land"] == "stream":
				col = Color("03a9f4")
			elif cell["land"] == "cultivated":
				col = Color("795548")
			elif cell["land"] == "house":
				col = Color("ffb300")
			elif cell["land"] == "swale":
				col = Color("3949ab")

			# 2. Plant Overrides (Draws over terrain)
			if str(cell.get("ground", "")) == "himalayan_balsam":
				col = Color("ff4081") # NEON PINK THREAT!
			elif _cell_str_nonempty(cell, "canopy"):
				col = Color("1b5e20") # Dark ancient forest
			elif _cell_str_nonempty(cell, "understory"):
				col = Color("c0ca33") # Bright shrubland

			img.set_pixel(x, y, col)

	var tex = ImageTexture.create_from_image(img)
	if hud_instance and hud_instance.has_method("update_minimap"):
		hud_instance.update_minimap(tex)


func _erase_plant_layers_at(pos: Vector2i, clear_ground: bool) -> void:
	for layer_key in ["canopy", "understory", "ground"]:
		if not clear_ground and layer_key == "ground":
			continue
		var layer_node = get_node_or_null(layer_key.capitalize() + "Layer")
		if layer_node:
			layer_node.set_cell(pos, -1, Vector2i(-1, -1))


func _get_worker_data(w_id: String) -> Dictionary:
	for w in FarmDataManager.workers:
		if str(w.get("id", "")) == w_id:
			return w
	if FarmDataManager.workers.size() > 0:
		return FarmDataManager.workers[0]
	return {}


func _pos_has_queued_plant_clear(pos: Vector2i) -> bool:
	for act in FarmDataManager.action_queue:
		if act.get("pos", Vector2i(-999999, -999999)) != pos:
			continue
		if str(act.get("action", "")) in ["rotovate", "hoe"]:
			return true
	return false


## Grid cell as it should appear during the day (queued rotovate/hoe strips plants before night).
func _get_visual_cell(pos: Vector2i, cell: Dictionary) -> Dictionary:
	if not _pos_has_queued_plant_clear(pos):
		return cell
	var visual := cell.duplicate(true)
	_clear_cell_plant_data(visual)
	return visual


func _get_planned_cell_state(pos: Vector2i, cell: Dictionary) -> Dictionary:
	var state: Dictionary = {
		"land": cell.get("land", "wild"),
		"has_path": cell.get("has_path", false),
	}
	for layer_key: String in ["canopy", "understory", "ground"]:
		state[layer_key] = cell.get(layer_key, "")
		var age_key: String = layer_key + "_age"
		if cell.has(age_key):
			state[age_key] = cell[age_key]
		var yield_key: String = layer_key + "_yield"
		if cell.has(yield_key):
			state[yield_key] = cell[yield_key]
	for bp in FarmDataManager.blueprints:
		if str(bp.get("structure", "")) != "bridge":
			continue
		var fp_bp: Variant = bp.get("footprint", [])
		if fp_bp is Array:
			for c in fp_bp:
				if c is Vector2i and c == pos:
					state["land"] = "bridge"
					state["has_path"] = true
	for act in FarmDataManager.action_queue:
		if str(act.get("action", "")) == "build" and str(act.get("structure", "")) == "bridge":
			var fp_q: Variant = act.get("footprint", [])
			if fp_q is Array:
				for c in fp_q:
					if c is Vector2i and c == pos:
						state["land"] = "bridge"
						state["has_path"] = true
	for act in FarmDataManager.action_queue:
		if act.get("pos", Vector2i(-999999, -999999)) != pos:
			continue
		var q_action: String = str(act.get("action", ""))
		match q_action:
			"rotovate", "hoe", "e_tiller":
				state["land"] = "cultivated"
				state["has_path"] = false
				_clear_cell_plant_data(state)
			"build_path":
				state["has_path"] = true
			"dig_swale":
				state["land"] = "swale"
			"build_mound":
				state["land"] = "mound"
			"scythe":
				state["land"] = "cultivated"
			"uproot":
				state["land"] = "wild"
			"plant":
				state["land"] = "cultivated"
	return state


func _init_farm_astar() -> void:
	farm_astar.region = Rect2i(0, 0, _map_w(), _map_h())
	farm_astar.cell_size = Vector2(200, 200)
	farm_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	farm_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	farm_astar.update()
	_sync_astar_with_grid()


func _sync_astar_with_grid() -> void:
	for x in range(_map_w()):
		for y in range(_map_h()):
			_update_astar_cell(Vector2i(x, y))


func _update_astar_cell(pos: Vector2i) -> void:
	if pos.x < 0 or pos.x >= _map_w() or pos.y < 0 or pos.y >= _map_h():
		return
	var cell: Dictionary = FarmDataManager.grid_data[pos.x][pos.y]
	var planned: Dictionary = _get_planned_cell_state(pos, cell)
	var land: String = str(planned.get("land", "wild"))
	var hp: bool = planned.get("has_path", false)

	var solid := false
	if land == "stream" or land == "river":
		solid = true
	elif land == "house":
		solid = true
	elif land == "house_door":
		solid = false

	if str(cell.get("structure", "")) in ["fence", "honesty_box", "duck_house", "pig_house", "compost_brewer", "beehive", "sprinkler", "drone_hub", "moisture_net", "smart_shade", "drone_pollinator", "solar_panel", "battery", "water_butt"]:
		solid = true

	if land == "bridge":
		solid = false

	farm_astar.set_point_solid(pos, solid)

	var ws := 1.0
	if hp or land == "bridge" or _cell_is_duck_corridor(cell):
		ws = 0.3
	elif land == "river":
		ws = 3.0
	farm_astar.set_point_weight_scale(pos, ws)


func _queue_path_start_cell() -> Vector2i:
	var active_id = FarmDataManager.active_worker_id

	# Search backwards for the LAST action queued specifically by this worker
	if FarmDataManager.action_queue.size() > 0:
		for i in range(FarmDataManager.action_queue.size() - 1, -1, -1):
			if FarmDataManager.action_queue[i].get("worker_id", "") == active_id:
				return FarmDataManager.action_queue[i].get("pos", Vector2i.ZERO) as Vector2i

	# If this specific worker has no jobs queued, their starting point is the farmhouse
	return farmhouse_pos


func _get_route_to_new_action(target_pos: Vector2i) -> Dictionary:
	var start: Vector2i = _queue_path_start_cell()
	if not farm_astar.is_in_boundsv(target_pos) or not farm_astar.is_in_boundsv(start):
		return {"path": [], "move_cost": INF}
	if start == target_pos:
		return {"path": [start], "move_cost": 0.0}

	# Temporarily make the target non-solid so we can route TO it (e.g., building a footbridge on a stream)
	var was_solid := farm_astar.is_point_solid(target_pos)
	if was_solid:
		farm_astar.set_point_solid(target_pos, false)

	var path: Array = farm_astar.get_id_path(start, target_pos)

	# Restore solidity immediately
	if was_solid:
		farm_astar.set_point_solid(target_pos, true)

	if path.is_empty():
		return {"path": [], "move_cost": INF}

	var raw_cost := 0.0
	for i in range(1, path.size()):
		var p: Vector2i = path[i]
		raw_cost += farm_astar.get_point_weight_scale(p)

	# Convert the raw movement cost into the 0-5 Zone penalty
	var zone_cost := float(_energy_cost_to_zone(raw_cost))

	return {"path": path, "move_cost": zone_cost}


func _draw_planned_journey_lines(canvas: CanvasItem) -> void:
	if is_sleeping:
		return

	var active_w := FarmDataManager.get_active_worker()
	var active_id: String = FarmDataManager.active_worker_id

	# 1. Identify how many unique workers are currently planning things
	var active_planners: Array[String] = []
	for item in FarmDataManager.action_queue:
		var wid: String = str(item.get("worker_id", ""))
		if wid != "" and not active_planners.has(wid):
			active_planners.append(wid)
	# Always include the currently selected worker so their preview has a reserved lane
	if not active_planners.has(active_id):
		active_planners.append(active_id)

	active_planners.sort()

	# 2. Calculate dynamic widths (shrinks as more workers are added)
	var total_lanes: int = active_planners.size()
	var lane_spacing: float = minf(25, float(93) / maxf(1.0, float(total_lanes)))
	var line_width: float = maxf(4, lane_spacing * 0.75)

	# Helper to get the specific pixel offset for a worker's line
	var get_worker_offset = func(w_id: String) -> Vector2:
		var lane_idx: int = active_planners.find(w_id)
		if lane_idx == -1:
			lane_idx = 0
		var shift: float = (float(lane_idx) - float(total_lanes - 1) / 2.0) * lane_spacing
		return Vector2(shift, shift)

	# 3. Draw historical queued actions using their assigned lane
	for item in FarmDataManager.action_queue:
		var path: Array = item.get("path", [])
		if path.size() < 2:
			continue

		var w_id: String = str(item.get("worker_id", ""))
		var offset: Vector2 = get_worker_offset.call(w_id)
		var hex_item: String = str(item.get("color", "fbc02d"))
		if not hex_item.begins_with("#"):
			hex_item = "#" + hex_item
		var item_color := Color(hex_item)

		var pts := PackedVector2Array()
		for p in path:
			pts.append(map_to_local(p as Vector2i) + offset)

		canvas.draw_polyline(pts, Color(0, 0, 0, 0.5), line_width + 6)
		canvas.draw_polyline(pts, item_color, line_width)

	# 4. Generate the live preview line for the active worker
	var mc := local_to_map(get_local_mouse_position())
	if mc.x < 0 or mc.x >= _map_w() or mc.y < 0 or mc.y >= _map_h():
		return

	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_mouse_move_time > 200:
		if mc != _preview_path_target:
			var route_pv: Dictionary = _get_route_to_new_action(mc)
			var pth: Variant = route_pv.get("path", [])
			_preview_path_cache = (pth as Array).duplicate() if pth is Array else Array()
			_preview_path_target = mc

	# 5. Draw the live preview in the active worker's lane
	if _preview_path_cache.size() > 1:
		var hex_live: String = str(active_w.get("color", "fbc02d"))
		if not hex_live.begins_with("#"):
			hex_live = "#" + hex_live
		var live_color := Color(hex_live)
		var offset_pv: Vector2 = get_worker_offset.call(active_id)
		var preview_pts := PackedVector2Array()

		for p in _preview_path_cache:
			preview_pts.append(map_to_local(p as Vector2i) + offset_pv)

		canvas.draw_polyline(preview_pts, Color(live_color.r, live_color.g, live_color.b, 0.6), line_width)


func _update_single_tile_visual(pos: Vector2i) -> void:
	var x: int = pos.x
	var y: int = pos.y
	if x < 0 or x >= _map_w() or y < 0 or y >= _map_h():
		return

	var cell: Dictionary = FarmDataManager.grid_data[x][y]
	var visual_cell: Dictionary = _get_visual_cell(pos, cell)
	var l_struct := get_node_or_null("StructureLayer") as TileMapLayer
	var object_entries: Dictionary = preload("res://data/data_objects.gd").ENTRIES
	# StructureLayer: draw fixtures only when `structure` is a string id (see grid overload doc above).

	var planned_state = _get_planned_cell_state(pos, cell)
	# Terrain atlas: ground truth only — queued rotovate/water previews draw on `preview_overlay`.
	var land: String = str(cell.get("land", "wild"))

	if _land_is_infra(land):
		set_cell(pos, 0, Vector2i(_land_to_atlas_x(land, pos), 0))
		_erase_plant_layers_at(pos, true)
		if l_struct:
			if _cell_has_building_structure(cell):
				var obj_inf: String = str(cell["structure"])
				if object_entries.has(obj_inf):
					var ax_inf: int = int(object_entries[obj_inf]["atlas_x"])
					l_struct.set_cell(pos, 0, Vector2i(ax_inf, 0))
				else:
					l_struct.erase_cell(pos)
			else:
				l_struct.erase_cell(pos)
		_update_astar_cell(pos)
		return

	if _should_paint_grey_path_tile(cell, planned_state):
		set_cell(pos, 0, Vector2i(11, 0))
		_erase_plant_layers_at(pos, false)
		if l_struct:
			if _cell_has_building_structure(cell):
				var obj_fp: String = str(cell["structure"])
				if object_entries.has(obj_fp):
					var ax_fp: int = int(object_entries[obj_fp]["atlas_x"])
					l_struct.set_cell(pos, 0, Vector2i(ax_fp, 0))
				else:
					l_struct.erase_cell(pos)
			else:
				l_struct.erase_cell(pos)
		return

	set_cell(pos, 0, Vector2i(_land_to_atlas_x(land, pos), 0))

	for layer_key in ["canopy", "understory", "ground"]:
		var layer_node_name = layer_key.capitalize() + "Layer"
		var layer_node = get_node_or_null(layer_node_name)

		if layer_node:
			if _cell_str_nonempty(visual_cell, layer_key):
				var p_id: String = str(visual_cell[layer_key])
				var atlas_x: int = _resolve_plant_atlas_x(p_id)
				layer_node.set_cell(pos, 0, Vector2i(atlas_x, 0))
			else:
				layer_node.set_cell(pos, -1, Vector2i(-1, -1))

	if l_struct:
		if _cell_has_building_structure(cell):
			var obj_id: String = str(cell["structure"])
			if object_entries.has(obj_id):
				var atlas_x: int = int(object_entries[obj_id]["atlas_x"])
				l_struct.set_cell(pos, 0, Vector2i(atlas_x, 0))
			else:
				l_struct.erase_cell(pos)
		else:
			l_struct.erase_cell(pos)

	_update_astar_cell(pos)


func _resolve_plant_atlas_x(plant_id: String) -> int:
	var pd := preload("res://data/data_plants.gd")
	var row: Dictionary = pd.get_plant_data(plant_id)
	if row.is_empty():
		return 0
	if row.has("custom_atlas_x"):
		return int(row["custom_atlas_x"])
	var custom_path := str(row.get("custom_sprite_path", ""))
	if custom_path != "" and FileAccess.file_exists(custom_path):
		var ax := register_custom_plant_sprite(plant_id, custom_path)
		if ax >= 0:
			return ax
	return int(row.get("atlas_x", 0))


const USER_PLANT_SPRITE_DIR := "user://databases/sprites/"


func _expand_master_atlas_image(master_image: Image, min_tile_count: int) -> Image:
	const T := 200
	var needed_w := min_tile_count * T
	if master_image.get_width() >= needed_w:
		return master_image
	var expanded := Image.create(needed_w, T, false, master_image.get_format())
	expanded.blit_rect(master_image, Rect2i(0, 0, master_image.get_width(), T), Vector2i.ZERO)
	return expanded


## Loads user-drawn plant PNGs, upscales to 200×200, stitches into the master atlas, sets `atlas_x`.
func _stitch_custom_plant_sprites(master_image: Image, next_atlas_x: int) -> Dictionary:
	const T := 200
	var pd := preload("res://data/data_plants.gd")
	pd.get_plant_data("")

	var img := master_image
	var ax := next_atlas_x

	if not DirAccess.dir_exists_absolute(USER_PLANT_SPRITE_DIR):
		return {"image": img, "atlas_x": ax}

	var dir := DirAccess.open(USER_PLANT_SPRITE_DIR)
	if dir == null:
		return {"image": img, "atlas_x": ax}

	var files: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.to_lower().ends_with(".png"):
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()

	for file_name in files:
		var plant_id := file_name.get_basename()
		if not pd.DATA.has(plant_id):
			continue

		var path := USER_PLANT_SPRITE_DIR.path_join(file_name)
		var custom_img := Image.load_from_file(path)
		if custom_img == null:
			push_warning("starting_map: could not load custom sprite %s" % path)
			continue

		if custom_img.get_format() != Image.FORMAT_RGBA8:
			custom_img.convert(Image.FORMAT_RGBA8)
		if custom_img.get_size() != Vector2i(T, T):
			custom_img.resize(T, T, Image.INTERPOLATE_NEAREST)

		img = _expand_master_atlas_image(img, ax + 1)
		img.blit_rect(custom_img, Rect2i(0, 0, T, T), Vector2i(ax * T, 0))

		pd.DATA[plant_id]["atlas_x"] = ax
		pd.DATA[plant_id]["custom_sprite_path"] = path
		pd.DATA[plant_id].erase("custom_atlas_x")
		print("Stitched custom plant sprite '%s' at atlas_x %d" % [plant_id, ax])
		ax += 1

	return {"image": img, "atlas_x": ax}


func register_custom_plant_sprite(plant_id: String, png_path: String) -> int:
	var pd := preload("res://data/data_plants.gd")
	var row: Dictionary = pd.get_plant_data(plant_id)
	if row.is_empty():
		return -1
	if row.has("custom_atlas_x"):
		return int(row["custom_atlas_x"])

	var src := tile_set.get_source(0) as TileSetAtlasSource
	if src == null:
		return -1
	var img := Image.load_from_file(png_path)
	if img == null:
		return -1
	const T := 200
	if img.get_size() != Vector2i(T, T):
		img.resize(T, T, Image.INTERPOLATE_NEAREST)

	var atlas_tex := src.texture as ImageTexture
	if atlas_tex == null:
		return -1
	var atlas_img := atlas_tex.get_image()
	if atlas_img == null:
		return -1

	var ax := _next_custom_atlas_x
	var needed_w := (ax + 1) * T
	if atlas_img.get_width() < needed_w:
		var expanded := Image.create(needed_w, T, false, atlas_img.get_format())
		expanded.blit_rect(atlas_img, Rect2i(0, 0, atlas_img.get_width(), T), Vector2i.ZERO)
		atlas_img = expanded

	atlas_img.blit_rect(img, Rect2i(0, 0, T, T), Vector2i(ax * T, 0))
	atlas_tex.set_image(atlas_img)
	if not src.has_tile(Vector2i(ax, 0)):
		src.create_tile(Vector2i(ax, 0))

	_next_custom_atlas_x += 1
	pd.DATA[plant_id]["custom_atlas_x"] = ax
	return ax


func update_visuals() -> void:
	if active_lens == "energy":
		if is_instance_valid(overlay):
			overlay.hide()
			overlay.texture = null
		if is_instance_valid(energy_zone_overlay):
			energy_zone_overlay.visible = true
			if not is_sleeping:
				energy_zone_overlay.queue_redraw()
		if is_instance_valid(energy_cursor_overlay):
			energy_cursor_overlay.visible = true
			if not is_sleeping:
				energy_cursor_overlay.queue_redraw()
		if is_instance_valid(maintenance_bubble_overlay):
			maintenance_bubble_overlay.visible = true
			maintenance_bubble_overlay.queue_redraw()
		return
	else:
		if active_lens in ["moisture", "nitrogen", "growth"] and is_instance_valid(overlay):
			overlay.show()

	var l_struct := get_node_or_null("StructureLayer") as TileMapLayer

	var object_entries: Dictionary = preload("res://data/data_objects.gd").ENTRIES
	# StructureLayer uses `_cell_has_building_structure` below — same overload as single-tile refresh.

	for x in range(_map_w()):
		for y in range(_map_h()):
			var cell: Dictionary = FarmDataManager.grid_data[x][y]
			var pos := Vector2i(x, y)
			var visual_cell: Dictionary = _get_visual_cell(pos, cell)

			# Path overlay still uses planned queue/blueprints; land atlas uses grid only (queue hints on preview overlay).
			var planned_state = _get_planned_cell_state(pos, cell)
			var land: String = str(cell.get("land", "wild"))

			if _land_is_infra(land):
				set_cell(pos, 0, Vector2i(_land_to_atlas_x(land, pos), 0))
				_erase_plant_layers_at(pos, true)
				if l_struct:
					if _cell_has_building_structure(cell):
						var obj_inf: String = str(cell["structure"])
						if object_entries.has(obj_inf):
							var ax_inf: int = int(object_entries[obj_inf]["atlas_x"])
							l_struct.set_cell(pos, 0, Vector2i(ax_inf, 0))
						else:
							l_struct.erase_cell(pos)
					else:
						l_struct.erase_cell(pos)
				continue

			if _should_paint_grey_path_tile(cell, planned_state):
				set_cell(pos, 0, Vector2i(11, 0))
				_erase_plant_layers_at(pos, false)
				if l_struct:
					if _cell_has_building_structure(cell):
						var obj_fp: String = str(cell["structure"])
						if object_entries.has(obj_fp):
							var ax_fp: int = int(object_entries[obj_fp]["atlas_x"])
							l_struct.set_cell(pos, 0, Vector2i(ax_fp, 0))
						else:
							l_struct.erase_cell(pos)
					else:
						l_struct.erase_cell(pos)
				continue

			set_cell(pos, 0, Vector2i(_land_to_atlas_x(land, pos), 0))

			# Draw Plants across all 3 layers (respect queued rotovate clearing)
			for layer_key in ["canopy", "understory", "ground"]:
				var layer_node_name = layer_key.capitalize() + "Layer"
				var layer_node = get_node_or_null(layer_node_name)

				if layer_node:
					if _cell_str_nonempty(visual_cell, layer_key):
						var p_id: String = str(visual_cell[layer_key])
						var atlas_x: int = _resolve_plant_atlas_x(p_id)
						layer_node.set_cell(pos, 0, Vector2i(atlas_x, 0))
					else:
						layer_node.set_cell(pos, -1, Vector2i(-1, -1))

			if l_struct:
				if _cell_has_building_structure(cell):
					var obj_id: String = str(cell["structure"])
					if object_entries.has(obj_id):
						var atlas_x: int = int(object_entries[obj_id]["atlas_x"])
						l_struct.set_cell(pos, 0, Vector2i(atlas_x, 0))
					else:
						l_struct.erase_cell(pos)
				else:
					l_struct.erase_cell(pos)

	# Energy Vision: zone metaballs + maintenance bubble (separate overlay nodes)
	if is_instance_valid(energy_zone_overlay):
		energy_zone_overlay.visible = (active_lens == "energy")
		if active_lens == "energy" and not is_sleeping:
			energy_zone_overlay.queue_redraw()
	if is_instance_valid(energy_cursor_overlay):
		energy_cursor_overlay.visible = (active_lens == "energy")
		if active_lens == "energy" and not is_sleeping:
			energy_cursor_overlay.queue_redraw()
	if is_instance_valid(maintenance_bubble_overlay):
		maintenance_bubble_overlay.visible = (active_lens == "energy")
		if active_lens == "energy":
			maintenance_bubble_overlay.queue_redraw()

	var guild_overlay := get_node_or_null("GuildOverlayNode") as Node2D
	if is_instance_valid(guild_overlay):
		guild_overlay.visible = (active_lens == "guild")
		if active_lens == "guild" and not is_sleeping:
			guild_overlay.queue_redraw()


func apply_lens() -> void:
	if is_instance_valid(energy_blackout):
		if active_lens == "energy":
			energy_blackout.show()
		else:
			energy_blackout.hide()

	if is_instance_valid(greyscale_overlay):
		greyscale_overlay.visible = (active_lens == "guild")

	if active_lens == "normal" or active_lens == "design":
		if is_instance_valid(hud_instance) and hud_instance.get("design_toolbar"):
			hud_instance.design_toolbar.visible = (active_lens == "design")
		if is_instance_valid(overlay):
			overlay.hide()
		if is_instance_valid(energy_zone_overlay):
			energy_zone_overlay.visible = false
		if is_instance_valid(energy_cursor_overlay):
			energy_cursor_overlay.visible = false
		if is_instance_valid(maintenance_bubble_overlay):
			maintenance_bubble_overlay.visible = false
		if is_instance_valid(design_overlay):
			design_overlay.queue_redraw()
		if active_lens == "normal":
			return
		if active_lens == "design":
			return

	if active_lens == "energy":
		if is_instance_valid(overlay):
			overlay.hide()
			overlay.texture = null
		if is_instance_valid(energy_zone_overlay):
			energy_zone_overlay.visible = true
			if not is_sleeping:
				energy_zone_overlay.queue_redraw()
		if is_instance_valid(energy_cursor_overlay):
			energy_cursor_overlay.visible = true
			if not is_sleeping:
				energy_cursor_overlay.queue_redraw()
		if is_instance_valid(maintenance_bubble_overlay):
			maintenance_bubble_overlay.visible = true
			maintenance_bubble_overlay.queue_redraw()
		return

	if is_instance_valid(energy_zone_overlay):
		energy_zone_overlay.visible = false
	if is_instance_valid(energy_cursor_overlay):
		energy_cursor_overlay.visible = false
	if is_instance_valid(maintenance_bubble_overlay):
		maintenance_bubble_overlay.visible = false

	overlay.show()
	var img_w := int(_map_w())
	var img_h := int(_map_w())
	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)

	for x in range(_map_w()):
		for y in range(_map_h()):
			var cell: Dictionary = FarmDataManager.grid_data[x][y]
			var c := Color.TRANSPARENT

			if active_lens == "moisture":
				var mw := float(cell.get("moisture", 5.0))
				var t := clampf(mw / 10.0, 0.0, 1.0)
				c = Color(0.8, 0.7, 0.5, 0.2).lerp(Color(0.2, 0.45, 1.0, 0.85), t)
				if mw > 10.0:
					var over := clampf((mw - 10.0) / 15.0, 0.0, 1.0)
					c = c.lerp(Color(0.0, 1.0, 1.0, 1.0), over)
			elif active_lens == "nitrogen":
				var nw := float(cell.get("nitrogen", 5.0))
				var t2 := clampf(nw / 10.0, 0.0, 1.0)
				c = Color(0.9, 0.9, 0.9, 0.1).lerp(Color(0.55, 0.18, 0.72, 0.85), t2)
			elif active_lens == "growth":
				var nw2 := float(cell.get("nitrogen", 5.0))
				var mw2 := float(cell.get("moisture", 5.0))
				var t3 := clampf((nw2 + mw2) / 20.0, 0.0, 1.0)
				c = Color(0.4, 0.3, 0.2, 0.1).lerp(Color(0.35, 0.78, 0.38, 0.85), t3)

			img.set_pixel(int(x), int(y), c)

	if lens_texture == null:
		lens_texture = ImageTexture.create_from_image(img)
	else:
		lens_texture.set_image(img)
	overlay.texture = lens_texture


func _land_to_atlas_x(land: String, pos: Vector2i = Vector2i(-1, -1)) -> int:
	match land:
		"wild":
			if pos != Vector2i(-1, -1):
				# The Old Growth Forest is strictly on the left boundary (x <= FarmDataManager.player_bounds_left)
				if pos.x <= FarmDataManager.player_bounds_left and forest_atlas_xs.size() > 0:
					var pseudo_random: int = abs(pos.x * 67280421 ^ pos.y * 22353149) as int
					return forest_atlas_xs[int(pseudo_random) % forest_atlas_xs.size()]
				# Everywhere else uses standard grass
				elif grass_atlas_xs.size() > 0:
					var pseudo_random_g: int = abs(pos.x * 73856093 ^ pos.y * 19349663) as int
					return grass_atlas_xs[int(pseudo_random_g) % grass_atlas_xs.size()]
			return 0
		"cultivated":
			if pos != Vector2i(-1, -1):
				# 1. The Industrial Farm is strictly on the right boundary
				if pos.x >= FarmDataManager.player_bounds_right and industrial_atlas_xs.size() > 0:
					var pseudo_random_i: int = abs(pos.x * 5432101 ^ pos.y * 9876541) as int
					return industrial_atlas_xs[int(pseudo_random_i) % industrial_atlas_xs.size()]
				# 2. The Player's Farm uses the rich, loamy cultivated sprites
				elif cultivated_atlas_xs.size() > 0:
					var pseudo_random_c: int = abs(pos.x * 8392817 ^ pos.y * 3829103) as int
					return cultivated_atlas_xs[int(pseudo_random_c) % cultivated_atlas_xs.size()]
			return 1 # Fallback to the hardcoded brown dirt tile
		"overgrown":
			return 2
		"swale":
			return 3
		"mound":
			return 4
		"river":
			if river_atlas_xs.size() > 0 and pos != Vector2i(-1, -1):
				var pseudo_random_r: int = abs(pos.x * 49157 ^ pos.y * 104729) as int
				return river_atlas_xs[int(pseudo_random_r) % river_atlas_xs.size()]
			return 5
		"road":
			return 11
		"bridge":
			return 13
		"stream":
			if stream_atlas_xs.size() > 0 and pos != Vector2i(-1, -1):
				var pseudo_random = abs(pos.x * 15485863 ^ pos.y * 32452843)
				return stream_atlas_xs[pseudo_random % stream_atlas_xs.size()]
			return 14
		"house":
			return 10
		"house_door":
			return 10
		"sand":
			if cultivated_atlas_xs.size() > 0 and pos != Vector2i(-1, -1):
				var pseudo_random_s: int = abs(pos.x * 91234567 ^ pos.y * 48291011) as int
				return cultivated_atlas_xs[int(pseudo_random_s) % cultivated_atlas_xs.size()]
			return 1
		_:
			return 0


func _preview_land_for_cell(cell: Dictionary) -> String:
	var preview_land: String = cell["land"]
	match active_tool:
		"rotovate", "e_tiller":
			preview_land = "cultivated"
		"scythe":
			preview_land = "wild"
		"uproot":
			preview_land = "cultivated"
		"dig_swale":
			preview_land = "swale"
		"build_mound":
			preview_land = "mound"
		"plant":
			preview_land = active_seed if active_seed != "" else "cultivated"
	return preview_land


func _earthworks_tile_ok(cell: Dictionary) -> bool:
	if cell["land"] == "overgrown":
		return false
	return cell["land"] == "wild" or cell["land"] == "cultivated"


## Paths must not cross building footprints. Numeric soil `structure` must not block paint (see overload header).
func _cell_can_build_path(cell: Dictionary) -> bool:
	if cell.get("has_path", false):
		return false
	if _cell_has_building_structure(cell):
		return false
	var land: String = str(cell.get("land", ""))
	if land in ["river", "stream", "bridge", "house", "house_door", "road"]:
		return false
	if land in ["swale", "mound"]:
		return false
	for layer_key in ["canopy", "understory", "ground"]:
		if _cell_str_nonempty(cell, layer_key):
			return false
	return true


func _demolish_neighbor_offsets() -> Array[Vector2i]:
	return [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]


func _demolish_path_network_eligible(c: Vector2i) -> bool:
	var d: Dictionary = FarmDataManager.grid_data[c.x][c.y]
	if not d.get("has_path", false):
		return false
	var land := str(d.get("land", ""))
	return land not in ["road", "house", "house_door", "river", "bridge"]


func _collect_demolish_footprint(start: Vector2i) -> Array[Vector2i]:
	var d0: Dictionary = FarmDataManager.grid_data[start.x][start.y]
	var land0 := str(d0.get("land", ""))
	var zone0 := str(d0.get("zone", ""))
	var dirs := _demolish_neighbor_offsets()

	if land0 == "bridge":
		var q: Array[Vector2i] = [start]
		var visited: Dictionary = {}
		visited[start] = true
		var out_br: Array[Vector2i] = []
		while not q.is_empty():
			var curr: Vector2i = q.pop_front()
			out_br.append(curr)
			for d_off in dirs:
				var n: Vector2i = curr + d_off
				if n.x < 0 or n.x >= _map_w() or n.y < 0 or n.y >= _map_h():
					continue
				if visited.has(n):
					continue
				if str(FarmDataManager.grid_data[n.x][n.y].get("land", "")) != "bridge":
					continue
				visited[n] = true
				q.append(n)
		return out_br

	if zone0 == "pen":
		var q2: Array[Vector2i] = [start]
		var visited2: Dictionary = {}
		visited2[start] = true
		var out_pen: Array[Vector2i] = []
		while not q2.is_empty():
			var curr2: Vector2i = q2.pop_front()
			out_pen.append(curr2)
			for d_off2 in dirs:
				var n2: Vector2i = curr2 + d_off2
				if n2.x < 0 or n2.x >= _map_w() or n2.y < 0 or n2.y >= _map_h():
					continue
				if visited2.has(n2):
					continue
				if str(FarmDataManager.grid_data[n2.x][n2.y].get("zone", "")) != "pen":
					continue
				visited2[n2] = true
				q2.append(n2)
		return out_pen

	if _demolish_path_network_eligible(start):
		var q3: Array[Vector2i] = [start]
		var visited3: Dictionary = {}
		visited3[start] = true
		var out_path: Array[Vector2i] = []
		while not q3.is_empty():
			var curr3: Vector2i = q3.pop_front()
			out_path.append(curr3)
			for d_off3 in dirs:
				var n3: Vector2i = curr3 + d_off3
				if n3.x < 0 or n3.x >= _map_w() or n3.y < 0 or n3.y >= _map_h():
					continue
				if visited3.has(n3):
					continue
				if not _demolish_path_network_eligible(n3):
					continue
				visited3[n3] = true
				q3.append(n3)
		return out_path

	return [start]


func _cell_has_demolishable_content(pos: Vector2i) -> bool:
	var d: Dictionary = FarmDataManager.grid_data[pos.x][pos.y]
	if str(d.get("land", "")) == "bridge":
		return true
	if str(d.get("zone", "")) in ["pen", "polytunnel"]:
		return true
	if str(d.get("structure", "")) != "":
		return true
	if _demolish_path_network_eligible(pos):
		return true
	for layer_key in ["canopy", "understory", "ground"]:
		if d.has(layer_key) and str(d.get(layer_key, "")) != "":
			return true
	return false


func _apply_demolish_to_cell(c: Vector2i) -> bool:
	var d: Dictionary = FarmDataManager.grid_data[c.x][c.y]
	var land_before := str(d.get("land", "wild"))
	var did_change := false

	for layer_key in ["canopy", "understory", "ground"]:
		if d.has(layer_key) and str(d.get(layer_key, "")) != "":
			d[layer_key] = ""
			if d.has(layer_key + "_age"):
				d.erase(layer_key + "_age")
			if d.has(layer_key + "_yield"):
				d.erase(layer_key + "_yield")
			did_change = true

	if land_before == "bridge":
		d["land"] = "stream"
		d["has_path"] = false
		did_change = true
	elif d.get("has_path", false) and land_before not in ["road", "house", "house_door", "river"]:
		d["has_path"] = false
		did_change = true

	var removed_fixture := str(d.get("structure", ""))
	if removed_fixture != "":
		d["structure"] = ""
		did_change = true
		if removed_fixture in ["battery", "solar_panel"]:
			FarmDataManager.clamp_stored_power()
	if str(d.get("zone", "")) != "":
		d["zone"] = ""
		did_change = true

	return did_change


func _try_smart_demolish(map_pos: Vector2i) -> bool:
	if is_sleeping:
		return false
	var e_cost := 1
	if FarmDataManager.get_energy() < e_cost:
		return false
	if not _cell_has_demolishable_content(map_pos):
		return false

	var tiles_to_demolish := _collect_demolish_footprint(map_pos)
	var actually_demolished := false
	for cell in tiles_to_demolish:
		if _apply_demolish_to_cell(cell):
			actually_demolished = true

	if not actually_demolished:
		return false

	FarmDataManager.clamp_stored_power()
	_on_time_machine_player_edit()
	FarmDataManager.spend_energy(e_cost)
	_sync_hud_status()

	if RadioManager.has_method("play_action_note"):
		RadioManager.play_action_note("build")

	if has_method("spawn_floating_text"):
		spawn_floating_text("Demolished", Color("9e9e9e"), map_pos, "actions")

	if has_method("_refresh_all_visuals"):
		_refresh_all_visuals()
	else:
		queue_redraw()

	call_deferred("advance_turn")
	return true


func _get_smart_drag_sequence(min_x: int, max_x: int, min_y: int, max_y: int) -> Array:
	var unvisited: Dictionary = {}
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			unvisited[Vector2i(x, y)] = true

	var islands: Array = []
	while unvisited.size() > 0:
		var start: Vector2i = unvisited.keys()[0]
		var island: Array = []
		var q: Array = [start]
		unvisited.erase(start)

		while q.size() > 0:
			var curr: Vector2i = q.pop_back()
			island.append(curr)

			for dir: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var n: Vector2i = curr + dir
				if unvisited.has(n):
					var w_curr := farm_astar.get_point_weight_scale(curr)
					var w_n := farm_astar.get_point_weight_scale(n)
					var solid_curr := farm_astar.is_point_solid(curr)
					var solid_n := farm_astar.is_point_solid(n)

					# Anything solid or with an A* weight >= 2.0 (like rivers) acts as a boundary
					var is_barrier_curr := solid_curr or w_curr >= 2.0
					var is_barrier_n := solid_n or w_n >= 2.0

					# Group normal land with normal land, and barriers with barriers. Don't mix them.
					if is_barrier_curr == is_barrier_n:
						unvisited.erase(n)
						q.append(n)
		islands.append(island)

	var start_pos := _queue_path_start_cell()
	islands.sort_custom(func(a, b):
		var dist_a = abs(a[0].x - start_pos.x) + abs(a[0].y - start_pos.y)
		var dist_b = abs(b[0].x - start_pos.x) + abs(b[0].y - start_pos.y)
		return dist_a < dist_b
	)

	var final_sequence: Array = []
	for island in islands:
		island.sort_custom(func(a, b):
			if a.y != b.y:
				return a.y < b.y
			if a.y % 2 == 0:
				return a.x < b.x
			else:
				return a.x > b.x
		)
		final_sequence.append_array(island)

	return final_sequence


func _attempt_grid_action(mouse_pos: Vector2) -> void:
	var grid_pos := local_to_map(to_local(mouse_pos))
	if grid_pos.x < 0 or grid_pos.x >= _map_w() or grid_pos.y < 0 or grid_pos.y >= _map_h():
		return

	var x := grid_pos.x
	var y := grid_pos.y

	if active_tool == "":
		if hud_instance and hud_instance.inspector_panel:
			var cell0 = FarmDataManager.grid_data[grid_pos.x][grid_pos.y]
			hud_instance.inspector_label.text = "[center][b]Tile Data[/b][/center]\n" + _get_soil_description(cell0)
			var noise = FastNoiseLite.new()
			noise.seed = x * 1000 + y
			var img = noise.get_image(200, 200)
			hud_instance.inspector_icon.texture = ImageTexture.create_from_image(img)
			hud_instance.inspector_panel.show()
		return

	if x <= FarmDataManager.player_bounds_left or x >= FarmDataManager.player_bounds_right:
		if has_method("spawn_floating_text"):
			spawn_floating_text("Not your land!", Color("ef5350"), Vector2i(x, y), "warnings")
		return

	var cell: Dictionary = FarmDataManager.grid_data[grid_pos.x][grid_pos.y]
	var pos := Vector2i(x, y)
	var planned_state: Dictionary = _get_planned_cell_state(pos, cell)
	if not is_dragging:
		var a_x := _land_to_atlas_x(cell["land"], pos)
		var pic := AtlasTexture.new()
		var src_atlas := tile_set.get_source(0) as TileSetAtlasSource
		if src_atlas:
			pic.atlas = src_atlas.texture
		pic.region = Rect2(a_x * 200, 0, 200, 200)
		if hud_instance and hud_instance.has_method("show_tile"):
			# SoilProfileUI V2 stats: `hud.show_tile` → `build_soil_inspector_stats` / `update_soil_inspector`
			hud_instance.show_tile(x, y, cell, pic)

	var current_land: String = planned_state["land"]

	if active_tool == "demolish":
		if current_land in ["house", "house_door"]:
			return
		_try_smart_demolish(pos)
		return

	if active_tool == "build" and active_structure == "bridge":
		var footprint := _get_bridge_footprint(pos)
		var valid := true
		for fp_cell in footprint:
			if fp_cell.x < 0 or fp_cell.x >= _map_w() or fp_cell.y < 0 or fp_cell.y >= _map_h():
				valid = false
				break
		if valid and str(cell.get("type", cell.get("land", ""))) == "stream":
			var route_br: Dictionary = _get_route_to_new_action(pos)
			if route_br["path"].is_empty():
				print("No path to footbridge site.")
				return
			var move_br := int(ceil(route_br["move_cost"]))
			if FarmDataManager.get_energy() < move_br:
				print("Not enough Energy or Capacity to do this!")
				return
			FarmDataManager.spend_energy(move_br)
			FarmDataManager.blueprints.append({
				"structure": "bridge", "footprint": footprint, "anchor": pos,
				"color": FarmDataManager.get_active_worker().get("color", "fbc02d"),
			})
			FarmDataManager.redo_queue.clear()
			_on_time_machine_player_edit()
			FarmDataManager.action_queue.append({
				"pos": pos,
				"action": "build",
				"structure": "bridge",
				"footprint": footprint,
				"energy_cost": move_br,
				"money_cost": 0,
				"path": route_br["path"],
				"batch_id": _current_batch_id,
				"worker_id": FarmDataManager.active_worker_id,
				"color": FarmDataManager.get_active_worker().get("color", "fbc02d"),
			})
			_update_astar_cell(Vector2i(x, y))
			if RadioManager.has_method("play_action_note"):
				RadioManager.play_action_note("ui")
			if is_instance_valid(preview_overlay):
				preview_overlay.queue_redraw()
			if is_instance_valid(hud_instance) and hud_instance.has_method("update_action_queue_ui"):
				hud_instance.update_action_queue_ui(FarmDataManager.action_queue)
			if RadioManager.has_method("set_music_state"):
				RadioManager.set_music_state("Planning")
			_sync_hud_status()
		return

	if active_tool == "build" and active_structure in ["duck_house", "polytunnel", "honesty_box", "pig_house", "compost_brewer", "beehive", "sprinkler", "drone_hub", "moisture_net", "smart_shade", "drone_pollinator", "solar_panel", "battery", "water_butt"]:
		if active_structure in ["sprinkler", "drone_hub", "smart_shade", "drone_pollinator"] and FarmDataManager.active_campaign_id != "automata":
			if has_method("spawn_floating_text"):
				spawn_floating_text("Neon Roots structures only!", Color("ef5350"), pos, "warnings")
			return
		if active_structure == "moisture_net":
			if FarmDataManager.active_campaign_id != "desert":
				if has_method("spawn_floating_text"):
					spawn_floating_text("Desert campaign only!", Color("ef5350"), pos, "warnings")
				return
			if FarmDataManager.current_turn < 15:
				if has_method("spawn_floating_text"):
					spawn_floating_text("Unlocks on Day 15!", Color("ef5350"), pos, "warnings")
				return
		var struct_fp: Array[Vector2i] = []
		match active_structure:
			"duck_house":
				struct_fp = _get_duck_house_footprint(pos)
			_:
				struct_fp = [pos]
		var struct_valid := true
		for fp_cell in struct_fp:
			if fp_cell.x < 0 or fp_cell.x >= _map_w() or fp_cell.y < 0 or fp_cell.y >= _map_h():
				struct_valid = false
				break
		if not struct_valid:
			return
		var can_struct := true
		# Footprint cells must be free of fixtures (string `structure`); soil metric float does not conflict.
		if active_structure == "duck_house":
			if _cell_has_building_structure(cell):
				can_struct = false
		elif active_structure == "polytunnel":
			if planned_state["land"] != "cultivated" or cell.get("zone", "") == "polytunnel":
				can_struct = false
		elif active_structure in ["honesty_box", "pig_house", "compost_brewer", "beehive", "sprinkler", "drone_hub", "moisture_net", "smart_shade", "drone_pollinator", "solar_panel", "battery", "water_butt"]:
			if _cell_has_building_structure(cell):
				can_struct = false
		if not can_struct:
			return
		var struct_costs := _build_structure_queue_costs(active_structure)
		var se_cost := struct_costs.x
		var sm_cost := struct_costs.y
		var route_st: Dictionary = _get_route_to_new_action(pos)
		if route_st["path"].is_empty():
			print("No path to build site.")
			return
		var move_st := int(ceil(route_st["move_cost"]))
		var total_se: int = se_cost + move_st
		if FarmDataManager.get_energy() < total_se or FarmDataManager.current_money < sm_cost:
			print("Not enough Energy or Capacity to do this!")
			return
		FarmDataManager.spend_energy(total_se)
		FarmDataManager.current_money -= sm_cost
		FarmDataManager.blueprints.append({
			"structure": active_structure, "footprint": struct_fp, "anchor": pos,
			"color": FarmDataManager.get_active_worker().get("color", "fbc02d"),
		})
		FarmDataManager.redo_queue.clear()
		_on_time_machine_player_edit()
		FarmDataManager.action_queue.append({
			"pos": pos,
			"action": "build",
			"structure": active_structure,
			"footprint": struct_fp,
			"energy_cost": total_se,
			"money_cost": sm_cost,
			"path": route_st["path"],
			"batch_id": _current_batch_id,
			"worker_id": FarmDataManager.active_worker_id,
			"color": FarmDataManager.get_active_worker().get("color", "fbc02d"),
		})
		_update_astar_cell(Vector2i(x, y))
		if RadioManager.has_method("play_action_note"):
			RadioManager.play_action_note("ui")
		if is_instance_valid(preview_overlay):
			preview_overlay.queue_redraw()
		if is_instance_valid(hud_instance) and hud_instance.has_method("update_action_queue_ui"):
			hud_instance.update_action_queue_ui(FarmDataManager.action_queue)
		if RadioManager.has_method("set_music_state"):
			RadioManager.set_music_state("Planning")
		_sync_hud_status()
		return

	if current_land in ["river", "stream", "bridge", "house", "house_door"]:
		if active_tool == "water_tile" or active_tool == "hosepipe":
			if current_land in ["house", "house_door"]:
				if current_land == "house_door":
					door_menu.position = get_viewport().get_mouse_position()
					door_menu.popup()
				return
			if current_land == "river":
				return
			# stream / bridge: allow manual watering (shallow water / crossing)
		else:
			if current_land == "house_door":
				door_menu.position = get_viewport().get_mouse_position()
				door_menu.popup()
			return

	# Undo: remove this exact queued plant (same tile + same layer) — click again to cancel seed
	if active_tool == "plant" and active_seed != "":
		for i in range(FarmDataManager.action_queue.size()):
			if FarmDataManager.action_queue[i]["pos"] != pos:
				continue
			if FarmDataManager.action_queue[i]["action"] != "plant":
				continue
			var new_layer_undo := str(preload("res://data/data_plants.gd").get_plant_data(active_seed).get("layer", "ground")).to_lower()
			var old_layer_undo := str(preload("res://data/data_plants.gd").get_plant_data(FarmDataManager.action_queue[i]["seed_id"]).get("layer", "ground")).to_lower()
			if new_layer_undo == old_layer_undo:
				var removed_undo: Dictionary = FarmDataManager.action_queue[i]
				FarmDataManager.refund_energy(int(removed_undo.get("energy_cost", 0)))
				FarmDataManager.current_money += int(removed_undo.get("money_cost", 0))
				FarmDataManager.redo_queue.clear()
				FarmDataManager.action_queue.remove_at(i)
				_update_astar_cell(Vector2i(x, y))
				_sync_hud_status()
				return

	# Find existing action in the queue for this tile (skip additive/poly/pig/demolish pairs per original rules)
	var existing_act_idx := -1
	for i in range(FarmDataManager.action_queue.size()):
		if FarmDataManager.action_queue[i]["pos"] != pos:
			continue
		var q_action = FarmDataManager.action_queue[i]

		if active_tool == "plant" and active_seed != "" and q_action["action"] == "plant":
			var new_layer := str(preload("res://data/data_plants.gd").get_plant_data(active_seed).get("layer", "ground")).to_lower()
			var old_layer := str(preload("res://data/data_plants.gd").get_plant_data(q_action["seed_id"]).get("layer", "ground")).to_lower()

			if new_layer == old_layer:
				existing_act_idx = i
				break
		elif active_tool == "additive" or q_action.get("action", "") == "additive" \
			or (active_tool == "build" and active_structure in ["polytunnel", "pig_house"]) \
			or (q_action.get("action", "") == "build" and str(q_action.get("structure", "")) in ["polytunnel", "pig_house"]) \
			or active_tool == "demolish" or q_action.get("action", "") == "demolish" \
			or (active_tool == "water_tile" and q_action.get("action", "") in ["plant", "rotovate", "hoe", "e_tiller", "build_mound", "dig_swale", "build_path", "additive"]) \
			or (q_action.get("action", "") == "water_tile" and active_tool in ["plant", "rotovate", "hoe", "e_tiller", "build_mound", "dig_swale", "build_path", "additive"]) \
			or (active_tool == "hosepipe" and q_action.get("action", "") in ["plant", "rotovate", "hoe", "e_tiller", "build_mound", "dig_swale", "build_path", "additive"]) \
			or (q_action.get("action", "") == "hosepipe" and active_tool in ["plant", "rotovate", "hoe", "e_tiller", "build_mound", "dig_swale", "build_path", "additive"]) \
			or (active_tool == "apply_tea" and q_action.get("action", "") in ["plant", "rotovate", "hoe", "e_tiller", "build_mound", "dig_swale", "build_path", "additive"]) \
			or (q_action.get("action", "") == "apply_tea" and active_tool in ["plant", "rotovate", "hoe", "e_tiller", "build_mound", "dig_swale", "build_path", "additive"]):
			continue
		else:
			existing_act_idx = i
			break

	if existing_act_idx != -1:
		var existing_type: String = str(FarmDataManager.action_queue[existing_act_idx].get("action", ""))
		var is_stacking_seed := (
			active_tool == "plant"
			and active_seed != ""
			and existing_type in ["hoe", "rotovate", "e_tiller"]
		)

		if is_stacking_seed:
			# Stack seed on cultivated dirt: keep rotovate/hoe; drop only prior plant entries on this tile
			for ri in range(FarmDataManager.action_queue.size() - 1, -1, -1):
				if FarmDataManager.action_queue[ri]["pos"] == pos and FarmDataManager.action_queue[ri].get("action") == "plant":
					var removed_p: Dictionary = FarmDataManager.action_queue[ri]
					FarmDataManager.refund_energy(int(removed_p.get("energy_cost", 0)))
					FarmDataManager.current_money += int(removed_p.get("money_cost", 0))
					FarmDataManager.redo_queue.clear()
					FarmDataManager.action_queue.remove_at(ri)
			_update_astar_cell(Vector2i(x, y))
			_sync_hud_status()
			# Fall through to append the new plant
		else:
			var removed: Dictionary = FarmDataManager.action_queue[existing_act_idx]
			if str(removed.get("action", "")) == "build":
				var ap: Vector2i = removed.get("pos", Vector2i(-1, -1))
				var st := str(removed.get("structure", ""))
				for bi in range(FarmDataManager.blueprints.size() - 1, -1, -1):
					if FarmDataManager.blueprints[bi].get("anchor", Vector2i(-99999, -99999)) == ap \
						and str(FarmDataManager.blueprints[bi].get("structure", "")) == st:
						FarmDataManager.blueprints.remove_at(bi)
				if is_instance_valid(preview_overlay):
					preview_overlay.queue_redraw()
			FarmDataManager.refund_energy(int(removed.get("energy_cost", 0)))
			FarmDataManager.current_money += int(removed.get("money_cost", 0))
			match str(removed.get("action", "")):
				"e_tiller":
					FarmDataManager.current_power = mini(
						FarmDataManager.get_max_power_capacity(),
						FarmDataManager.current_power + 1
					)
				"hosepipe":
					FarmDataManager.current_water = mini(
						FarmDataManager.get_max_water_capacity(),
						FarmDataManager.current_water + 1
					)
			FarmDataManager.redo_queue.clear()
			FarmDataManager.action_queue.remove_at(existing_act_idx)
			_update_astar_cell(Vector2i(x, y))
			_sync_hud_status()
			return

	var e_cost := 0
	var m_cost := 0

	if active_tool == "rotovate":
		if planned_state["has_path"] and planned_state["land"] == "cultivated":
			e_cost = 1
		else:
			e_cost = 2
	elif active_tool == "e_tiller":
		e_cost = 0
	elif active_tool == "hosepipe":
		e_cost = 0
	elif active_tool == "scythe":
		e_cost = 1
	elif active_tool == "harvest":
		e_cost = 2
	elif active_tool == "chop_and_drop":
		e_cost = 1
	elif active_tool == "uproot":
		e_cost = 1 if MetaManager.has_upgrade("thick_gloves") else 2
	elif active_tool == "dig_swale":
		e_cost = 5
	elif active_tool == "build_mound":
		e_cost = 5
		m_cost = 2
	elif active_tool == "plant":
		e_cost = 1
		if not preload("res://data/data_plants.gd").get_plant_data(active_seed).is_empty():
			m_cost = str(preload("res://data/data_plants.gd").get_plant_data(active_seed).get("cost", "0")).to_int()
	elif active_tool == "build":
		var bqc := _build_structure_queue_costs(active_structure)
		e_cost = bqc.x
		m_cost = bqc.y
		if active_structure not in ["bridge", "duck_house", "polytunnel", "honesty_box", "pig_house", "compost_brewer", "beehive", "sprinkler", "drone_hub", "moisture_net", "smart_shade", "drone_pollinator", "solar_panel", "battery", "water_butt"] \
			and preload("res://data/data_objects.gd").ENTRIES.has(active_structure):
			m_cost = int(preload("res://data/data_objects.gd").ENTRIES[active_structure].get("cost", 0))
	elif active_tool == "additive":
		e_cost = 1
	elif active_tool == "build_path":
		e_cost = 0
		m_cost = 1
	elif active_tool == "water_tile":
		e_cost = 0 if FarmDataManager.creative_infinite_water else 1
		m_cost = 0
	elif active_tool == "apply_tea":
		e_cost = 1
		m_cost = 0

	if active_tool == "plant" and active_seed == "":
		return

	if active_tool == "build":
		return

	if active_tool == "e_tiller" and FarmDataManager.current_power < 1:
		if has_method("spawn_floating_text"):
			spawn_floating_text("No stored power!", Color("ef5350"), pos, "warnings")
		return
	if active_tool == "hosepipe" and FarmDataManager.current_water < 1:
		if has_method("spawn_floating_text"):
			spawn_floating_text("No stored water!", Color("ef5350"), pos, "warnings")
		return

	var can_queue := true

	if active_tool == "rotovate" or active_tool == "e_tiller":
		if planned_state["land"] in ["road", "bridge"]:
			can_queue = false
		elif planned_state["has_path"] and planned_state["land"] == "cultivated":
			can_queue = true
		elif planned_state["land"] not in ["wild", "overgrown", "sand"]:
			can_queue = false
	elif active_tool == "scythe":
		if planned_state["land"] != "overgrown":
			can_queue = false
	elif active_tool == "harvest":
		if planned_state["land"] not in ["cultivated", "overgrown"]:
			can_queue = false
		elif _mature_plant_on_cell(cell).is_empty():
			can_queue = false
	elif active_tool == "chop_and_drop":
		if _top_plant_on_cell(cell).is_empty():
			can_queue = false
	elif active_tool == "uproot":
		if planned_state["land"] == "wild":
			can_queue = false
	elif active_tool == "plant":
		# Cultivated cells carry V3 soil `structure` as a float; only string ids mean a blocking fixture.
		if planned_state["has_path"]:
			can_queue = false
		elif planned_state["land"] != "cultivated":
			if has_method("spawn_floating_text"):
				spawn_floating_text("Needs Dirt!", Color("ef5350"), pos, "warnings")
			can_queue = false
		elif _cell_has_building_structure(cell):
			print("Cannot plant here: Building in the way!")
			can_queue = false
		else:
			var p_reqs = preload("res://data/data_plants.gd").get_plant_data(active_seed).get("soil_reqs", [])
			var current_tags = cell.get("soil_tags", ["clay"])
			var missing := PackedStringArray()
			for req in p_reqs:
				if not req in current_tags:
					missing.append(req)

			if missing.size() > 0:
				var miss_str := ", ".join(PackedStringArray(missing))
				print("Warning: Planted in poor soil missing: ", miss_str)

				if has_method("spawn_floating_text"):
					spawn_floating_text("Poor Soil!", Color("ffeb3b"), Vector2i(x, y), "warnings")

			var p_layer := str(preload("res://data/data_plants.gd").get_plant_data(active_seed).get("layer", "ground")).to_lower()
			if _cell_str_nonempty(cell, p_layer):
				if has_method("spawn_floating_text"):
					spawn_floating_text("Layer Full!", Color("ef5350"), pos, "warnings")
				can_queue = false
	elif active_tool == "additive":
		if active_seed == "" or not additives_data.has(active_seed):
			can_queue = false
	elif active_tool == "build_path":
		var cell_for_path: Dictionary = cell.duplicate()
		cell_for_path["land"] = planned_state["land"]
		cell_for_path["has_path"] = planned_state["has_path"]
		can_queue = _cell_can_build_path(cell_for_path)
	elif active_tool == "water_tile" or active_tool == "hosepipe":
		if planned_state["land"] in ["road", "house", "house_door", "river"]:
			can_queue = false
	elif active_tool == "apply_tea":
		if planned_state["land"] in ["road", "bridge", "house", "house_door", "river", "stream"]:
			can_queue = false

	if not can_queue:
		return

	if active_tool != "" and _cell_has_npc(cell):
		if has_method("spawn_floating_text"):
			spawn_floating_text("Someone's in the way!", Color("ffb74d"), pos, "warnings")
		return

	var route_info: Dictionary = _get_route_to_new_action(Vector2i(x, y))
	if route_info["path"].is_empty():
		print("Cannot reach tile — path blocked.")
		return
	var move_e := int(ceil(route_info["move_cost"]))
	var total_e: int = e_cost + move_e
	if FarmDataManager.get_energy() < total_e or FarmDataManager.current_money < m_cost:
		print("Not enough Energy or Capacity to do this!")
		return

	if active_tool == "e_tiller":
		FarmDataManager.current_power -= 1
	elif active_tool == "hosepipe":
		FarmDataManager.current_water -= 1

	FarmDataManager.spend_energy(total_e)
	FarmDataManager.current_money -= int(m_cost)
	var q_entry: Dictionary = {
		"pos": Vector2i(x, y),
		"action": active_tool,
		"seed_id": active_seed,
		"energy_cost": total_e,
		"money_cost": m_cost,
		"path": route_info["path"],
		"batch_id": _current_batch_id,
		"worker_id": FarmDataManager.active_worker_id,
		"color": FarmDataManager.get_active_worker().get("color", "fbc02d"),
	}
	if active_tool == "water_tile" or active_tool == "hosepipe":
		q_entry["color"] = "64b5f6"
	elif active_tool == "apply_tea":
		q_entry["color"] = "81c784"
	if active_tool == "additive":
		q_entry["seed"] = active_seed
	FarmDataManager.redo_queue.clear()
	_on_time_machine_player_edit()
	FarmDataManager.action_queue.append(q_entry)
	_update_astar_cell(Vector2i(x, y))

	# VIBE CODING: Tell the Interactive stream we are actively farming!
	if RadioManager.has_method("set_music_state"):
		RadioManager.set_music_state("Planning")

	# --- INSTANT VISUAL FEEDBACK (NO LAG) ---
	var preview_land: String = _preview_land_for_cell(cell)
	if active_tool == "plant" and str(active_seed) != "":
		preview_land = "cultivated"
	if active_tool == "build_path":
		set_cell(Vector2i(x, y), 0, Vector2i(11, 0))
	elif active_tool != "additive":
		set_cell(Vector2i(x, y), 0, Vector2i(_land_to_atlas_x(preview_land, Vector2i(x, y)), 0))
	if active_tool == "rotovate" or active_tool == "e_tiller":
		_erase_plant_layers_at(Vector2i(x, y), true)
	# ----------------------------------------

	if active_tool == "rotovate" or active_tool == "e_tiller" or active_tool == "build_path" or active_tool == "build":
		RadioManager.play_action_note("build")
		_spawn_click_particles(map_to_local(Vector2i(x, y)), Color("8d6e63")) # Dust/Dirt colour
	elif active_tool == "plant" and active_seed != "":
		RadioManager.play_action_note("plant")
		_spawn_click_particles(map_to_local(Vector2i(x, y)), Color("a5d6a7")) # Fresh green colour
	elif active_tool == "water_tile" or active_tool == "hosepipe":
		RadioManager.play_action_note("plant")
		_spawn_click_particles(map_to_local(Vector2i(x, y)), Color("64b5f6"))
	elif active_tool == "apply_tea":
		if RadioManager.has_method("play_action_note"):
			RadioManager.play_action_note("build")
		_spawn_click_particles(map_to_local(Vector2i(x, y)), Color("81c784"))
	_sync_hud_status()
	if is_instance_valid(preview_overlay):
		preview_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if is_sleeping:
		return

	if almanac_open:
		if event.is_action_pressed("ui_cancel"):
			close_almanac()
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		set_current_tool("")
		print("Tool cleared. Inspection mode active.")
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_H:
			set_current_tool("build", "", "duck_house")
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_P:
			set_current_tool("build", "", "polytunnel")
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_8:
			if MetaManager.dev_mode:
				var m_pos = local_to_map(get_local_mouse_position())
				if m_pos.x >= 0 and m_pos.x < _map_w() and m_pos.y >= 0 and m_pos.y < _map_w():
					var cell = FarmDataManager.grid_data[m_pos.x][m_pos.y]
					cell["ground"] = "himalayan_balsam"
					cell["ground_age"] = 0
					_update_single_tile_visual(m_pos)
					if has_method("_play_balsam_pop"):
						_play_balsam_pop()
					spawn_floating_text("DEV POP!", Color("e040fb"), m_pos, "warnings")
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_accept"):
		trigger_sleep()
		get_viewport().set_input_as_handled()
		return

	# --- HOTKEY LISTENER ---
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.is_command_or_control_pressed():
			if (event.keycode == KEY_Z and event.is_shift_pressed()) or (event.keycode == KEY_Y and not event.is_shift_pressed()):
				redo_action()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_Z and not event.is_shift_pressed():
				undo_last_action()
				get_viewport().set_input_as_handled()
				return
		for action_name in _save_manager.hotkeys.keys():
			if event.keycode == _save_manager.hotkeys[action_name]:
				if action_name == "Plant":
					set_current_tool("plant", active_seed)
					if hud_instance and hud_instance.get_node_or_null("CanvasLayer/SeedPicker"):
						hud_instance.get_node("CanvasLayer/SeedPicker").populate_and_show()
				elif action_name.ends_with("Lens") or action_name.ends_with("View"):
					if action_name == "Standard View" or action_name == "Standard Lens":
						active_lens = "normal"
					elif action_name == "Hydration Lens":
						active_lens = "moisture"
					elif action_name == "Nutrient Lens":
						active_lens = "nitrogen"
					elif action_name == "Guild Vision":
						active_lens = "guild"
					elif action_name == "Design View":
						active_lens = "design"

					print("Toggled Overlay: ", active_lens)

					# Trigger the visual refresh to apply the color modulation
					if has_method("apply_lens"):
						call("apply_lens")
					elif has_method("update_visuals"):
						call("update_visuals")
					elif has_method("_refresh_all_visuals"):
						call("_refresh_all_visuals")
				elif action_name == "Water":
					set_current_tool("water_tile")
				elif action_name == "Rotovator":
					set_current_tool("rotovate")
				else:
					var equipped: String = str(action_name).to_lower().replace(" ", "_")
					set_current_tool(equipped)

				get_viewport().set_input_as_handled()
				return
	# -----------------------

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		# UNIVERSAL CONTEXT MENU (Right Click OR Ctrl/Cmd + Left Click)
		var is_right_click = mb.button_index == MOUSE_BUTTON_RIGHT
		var is_ctrl_left_click = mb.button_index == MOUSE_BUTTON_LEFT and event.is_command_or_control_pressed()

		if (is_right_click or is_ctrl_left_click) and mb.pressed:
			var coords_r := local_to_map(to_local(get_global_mouse_position()))
			if coords_r.x >= 0 and coords_r.x < _map_w() and coords_r.y >= 0 and coords_r.y < _map_w():
				if is_instance_valid(hud_instance) and hud_instance.has_method("show_context_menu"):
					hud_instance.show_context_menu(mb.global_position, coords_r)
			get_viewport().set_input_as_handled()
			return

		# LEFT CLICK: Scribbling vs Farming
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if Input.is_key_pressed(KEY_SPACE):
				return # Ignore clicks while holding Space so the camera can pan

			if active_lens == "design":
				if mb.pressed:
					_is_scribbling = true
					_design_start_pos = get_local_mouse_position()
					if design_tool == "pen":
						_current_shape_data = {"type": "pen", "points": PackedVector2Array([_design_start_pos]), "thickness": design_thickness, "color": Color(1, 1, 1, 0.6)}
					else:
						_current_shape_data = {"type": design_tool, "points": PackedVector2Array([_design_start_pos, _design_start_pos]), "thickness": design_thickness, "color": Color(1, 1, 1, 0.6)}
				else:
					_is_scribbling = false
					if design_tool != "eraser" and _current_shape_data.get("points", []).size() > 1:
						FarmDataManager.scribbles.append(_current_shape_data.duplicate())
					_current_shape_data.clear()
				design_overlay.queue_redraw()
				get_viewport().set_input_as_handled()
				return

			if active_lens == "guild":
				if mb.pressed:
					var local_mouse := to_local(get_global_mouse_position())
					guild_selected_cell = local_to_map(local_mouse)
					var go = get_node_or_null("GuildOverlayNode")
					if go:
						go.queue_redraw()
				get_viewport().set_input_as_handled()
				return

			# EMPTY TOOL: Deep Info Inspection
			var current_equipped = str(active_tool)
			if current_equipped == "" or current_equipped == "<null>":
				if mb.pressed and not is_sleeping:
					var coords_r := local_to_map(to_local(get_global_mouse_position()))
					if coords_r.x >= 0 and coords_r.x < _map_w() and coords_r.y >= 0 and coords_r.y < _map_w():
						var cell_r: Dictionary = FarmDataManager.grid_data[coords_r.x][coords_r.y]
						var a_rx = _land_to_atlas_x(cell_r["land"], coords_r)
						var pic_r = AtlasTexture.new()
						if tile_set:
							var src = tile_set.get_source(0) as TileSetAtlasSource
							if src: pic_r.atlas = src.texture
						pic_r.region = Rect2(a_rx * 200, 0, 200, 200)
						if hud_instance and hud_instance.has_method("show_tile"):
							# SoilProfileUI V2 stats: `hud.show_tile` → `build_soil_inspector_stats` / `update_soil_inspector`
							hud_instance.show_tile(coords_r.x, coords_r.y, cell_r, pic_r)
				get_viewport().set_input_as_handled()
				return

			# (Existing farming logic follows...)
			if mb.pressed:
				if is_sleeping:
					return
				_last_dragged_cell = Vector2i(-1, -1)
				_current_batch_id += 1
				var current_cell := local_to_map(get_local_mouse_position())

				if Input.is_key_pressed(KEY_SHIFT):
					_shift_drag_start = current_cell
					is_dragging = true
				else:
					_shift_drag_start = Vector2i(-1, -1)
					_attempt_grid_action(get_global_mouse_position())
					_last_dragged_cell = current_cell
					is_dragging = true
			else:
				if is_dragging and _shift_drag_start != Vector2i(-1, -1):
					var current_cell := local_to_map(get_local_mouse_position())
					var min_x = mini(_shift_drag_start.x, current_cell.x)
					var max_x = maxi(_shift_drag_start.x, current_cell.x)
					var min_y = mini(_shift_drag_start.y, current_cell.y)
					var max_y = maxi(_shift_drag_start.y, current_cell.y)

					var sequence = _get_smart_drag_sequence(min_x, max_x, min_y, max_y)
					for cell in sequence:
						var target_pos = to_global(map_to_local(cell as Vector2i))
						_attempt_grid_action(target_pos)

				is_dragging = false
				_shift_drag_start = Vector2i(-1, -1)
				_last_dragged_cell = Vector2i(-1, -1)
				if has_method("_refresh_all_visuals"):
					_refresh_all_visuals()
				elif has_method("update_visuals"):
					update_visuals()
				if has_method("_calculate_maintenance_bubble"):
					_calculate_maintenance_bubble()
				if has_method("_refresh_queue_ui"):
					_refresh_queue_ui()
			get_viewport().set_input_as_handled()
			return

	elif event is InputEventMouseMotion:
		if _is_scribbling and active_lens == "design":
			var m_pos = get_local_mouse_position()
			if design_tool == "eraser":
				for i in range(FarmDataManager.scribbles.size() - 1, -1, -1):
					var s = FarmDataManager.scribbles[i]
					for p in s.get("points", PackedVector2Array()):
						if p.distance_to(m_pos) < 30.0:
							FarmDataManager.scribbles.remove_at(i)
							break
			elif design_tool == "pen":
				_current_shape_data["points"].append(m_pos)
			else:
				_current_shape_data["points"][1] = m_pos

			design_overlay.queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if is_dragging:
			if is_sleeping:
				return
			var local_pos = get_local_mouse_position()
			var grid_pos = local_to_map(local_pos)

			if Input.is_key_pressed(KEY_SHIFT) and _shift_drag_start != Vector2i(-1, -1):
				if is_instance_valid(preview_overlay):
					preview_overlay.queue_redraw()
			elif grid_pos != _last_dragged_cell:
				if _last_dragged_cell != Vector2i(-1, -1):
					var path = _bresenham_line(_last_dragged_cell, grid_pos)
					for i in range(1, path.size()):
						var target_pos = to_global(map_to_local(path[i] as Vector2i))
						_attempt_grid_action(target_pos)
				else:
					_attempt_grid_action(get_global_mouse_position())
				_last_dragged_cell = grid_pos
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if vitals_label:
		vitals_label.text = "Money: £%d | Turn: %d" % [FarmDataManager.current_money, FarmDataManager.current_turn]

	if is_instance_valid(hud_instance) and hud_instance.has_method("apply_mail_indicator"):
		hud_instance.apply_mail_indicator(unread_mail)

	# Sync the physical farmer sprite to the Active Worker's texture
	if not is_sleeping:
		var active_w = FarmDataManager.get_active_worker()
		var tex_path = active_w.get("sprite", "res://icon.svg")
		if is_instance_valid(farmer) and ResourceLoader.exists(tex_path):
			var expected_tex = load(tex_path)
			if farmer.texture != expected_tex:
				farmer.texture = expected_tex
				farmer.modulate = Color.WHITE # Ensure no lingering tint is applied

	var skip_tile_hover := false
	if is_instance_valid(hud_instance) and hud_instance.has_method("is_blocking_ui_open"):
		if hud_instance.is_blocking_ui_open():
			skip_tile_hover = true
	if skip_tile_hover and tooltip_panel:
		tooltip_panel.hide()

	var mouse_pos := get_global_mouse_position()
	var local_mouse := to_local(mouse_pos)
	var grid_pos := local_to_map(local_mouse)

	if is_instance_valid(tile_highlight) and tile_set:
		if is_sleeping or (_shift_drag_start != Vector2i(-1, -1) and is_dragging):
			tile_highlight.hide()
		elif is_nan(mouse_pos.x) or is_nan(mouse_pos.y) or is_inf(mouse_pos.x) or is_inf(mouse_pos.y) \
			or is_nan(local_mouse.x) or is_nan(local_mouse.y) or is_inf(local_mouse.x) or is_inf(local_mouse.y):
			tile_highlight.hide()
		else:
			var ts := Vector2(tile_set.tile_size)
			tile_highlight.size = ts
			tile_highlight.global_position = to_global(map_to_local(grid_pos)) - (ts * 0.5)
			if grid_pos.x >= 0 and grid_pos.x < _map_w() and grid_pos.y >= 0 and grid_pos.y < _map_w():
				tile_highlight.show()
			else:
				tile_highlight.hide()

	var hover_layer = get_node_or_null("HoverLayer")
	if hover_layer:
		var mouse_invalid := is_nan(mouse_pos.x) or is_nan(mouse_pos.y) or is_inf(mouse_pos.x) or is_inf(mouse_pos.y) \
			or is_nan(local_mouse.x) or is_nan(local_mouse.y) or is_inf(local_mouse.x) or is_inf(local_mouse.y)
		if mouse_invalid:
			if last_hover_pos != Vector2i(-1, -1):
				hover_layer.erase_cell(last_hover_pos)
				last_hover_pos = Vector2i(-1, -1)
		elif grid_pos != last_hover_pos:
			if last_hover_pos != Vector2i(-1, -1):
				hover_layer.erase_cell(last_hover_pos)
			if grid_pos.x >= 0 and grid_pos.x < _map_w() and grid_pos.y >= 0 and grid_pos.y < _map_w():
				hover_layer.set_cell(grid_pos, 0, Vector2i(9, 0))
			last_hover_pos = grid_pos
			_last_mouse_move_time = Time.get_ticks_msec()
			_preview_path_target = Vector2i(-1, -1)
			_preview_path_cache.clear()

			# --- OPTIMIZED REDRAW ---
			# Only recalculate pathfinding previews when the mouse enters a completely new tile
			if is_instance_valid(preview_overlay):
				preview_overlay.queue_redraw()

	if is_instance_valid(preview_overlay) and not is_sleeping:
		var mouse_invalid_preview := is_nan(mouse_pos.x) or is_nan(mouse_pos.y) or is_inf(mouse_pos.x) or is_inf(mouse_pos.y) \
			or is_nan(local_mouse.x) or is_nan(local_mouse.y) or is_inf(local_mouse.x) or is_inf(local_mouse.y)
		if not mouse_invalid_preview:
			var cur_hover_cell := local_to_map(get_local_mouse_position())
			if Time.get_ticks_msec() - _last_mouse_move_time > 200 and _preview_path_target != cur_hover_cell:
				preview_overlay.queue_redraw()

	if not skip_tile_hover:
		if tooltip_panel and tooltip_label:
			# ONLY show the tooltip if holding SHIFT and the mouse is valid
			if Input.is_key_pressed(KEY_SHIFT):
				tooltip_panel.position = get_viewport().get_mouse_position() + Vector2(25, 25)

				if grid_pos.x >= 0 and grid_pos.x < _map_w() and grid_pos.y >= 0 and grid_pos.y < _map_w():
					var cell: Dictionary = FarmDataManager.grid_data[grid_pos.x][grid_pos.y]
					var text := "[b]Tile (%d, %d)[/b]\n" % [grid_pos.x, grid_pos.y]
					text += "Land: %s\n" % str(cell.get("land", "wild")).capitalize()
					text += _get_soil_description(cell) + "\n"

					var plants: Array[String] = []
					if _cell_str_nonempty(cell, "canopy"):
						plants.append("[color=#a5d6a7]Canopy:[/color] " + str(cell.get("canopy", "")).capitalize())
					if _cell_str_nonempty(cell, "understory"):
						plants.append("[color=#ffe082]Under:[/color] " + str(cell.get("understory", "")).capitalize())
					if _cell_str_nonempty(cell, "ground"):
						plants.append("[color=#80deea]Ground:[/color] " + str(cell.get("ground", "")).capitalize())

					if plants.size() > 0:
						text += "---\n"
						for i in range(plants.size()):
							if i > 0:
								text += "\n"
							text += plants[i]

					# Tooltip: show fixture name only for string ids; hide numeric soil `structure` (overload header).
					if _cell_has_building_structure(cell):
						text += "\n---\n[color=#f48fb1]Structure:[/color] " + str(cell.get("structure", "")).capitalize()

					var phs: Dictionary = _planning_hover_state(grid_pos)
					if str(phs.get("kind", "")) == "preview":
						var be: int = int(phs.get("e_cost", 0))
						var mv: float = float(phs.get("move_cost", 0.0))
						var te: int = int(phs.get("total_e", 0))
						var ok_path: bool = bool(phs.get("path_ok", false))
						var bad := (not ok_path) or (te > FarmDataManager.get_energy())
						var plan_line := "\n---\n[b]Planned action[/b]\nBase: %d energy | Move: %.1f (total %d)" % [be, mv, te]
						if bad:
							plan_line = "[color=#ef5350]" + plan_line + "[/color]"
						text += plan_line

					if active_lens == "energy":
						_calculate_energy_zones()
						if _energy_zone_cache.has(grid_pos):
							var target_cost: float = float(_energy_zone_cache[grid_pos])
							var target_zone: int = _energy_cost_to_zone(target_cost)
							var energy_deduction := -target_zone
							var raw_dist := Vector2(_cached_farmer_pos).distance_to(Vector2(grid_pos))
							var has_bonus: bool = target_cost < raw_dist

							text += "\n\n--- ENERGY ROUTE ---"
							text += "\nTarget: Zone " + str(target_zone)
							text += "\nCost: " + str(energy_deduction) + " Energy"
							if has_bonus:
								text += "\n✨ Path Bonus Applied!"

					# --- PROPERTY BOUNDARY WARNING ---
					if grid_pos.x <= FarmDataManager.player_bounds_left or grid_pos.x >= FarmDataManager.player_bounds_right:
						text += "\n\n[color=#ef5350][b]Not your land![/b][/color]"

					# --- TRIAGE WARNING ---
					if triage_cache.has(grid_pos):
						var warn = triage_cache[grid_pos]
						text += "\n\n[color=#%s][b]⚠ %s[/b][/color]" % [warn["color"].to_html(false), warn["msg"]]

					if active_lens == "design" and FarmDataManager.cell_notes.has(grid_pos):
						var note_data = FarmDataManager.cell_notes[grid_pos]
						text += "\n\n[color=#%s][b]📝 Note:[/b][/color]\n%s" % [note_data["color"], note_data["text"]]

					tooltip_label.text = text
					tooltip_panel.show()
				else:
					tooltip_panel.hide()
			else:
				# Shift is NOT pressed, hide it
				tooltip_panel.hide()

	# --- SYNCHRONISED BREATHING (ENERGY VISION) ---
	if is_instance_valid(structure_overlay) and is_daytime:
		# Wall-clock phase so the pulse keeps breathing without echo_timer playback
		var breath_t := fmod(Time.get_ticks_msec() / 1000.0, echo_loop_length)
		var pulse = (sin((breath_t / echo_loop_length) * PI * 2.0) + 1.0) / 2.0

		if active_lens == "energy":
			# In Energy Vision, the structures glow intensely and breathe deeply
			structure_overlay.modulate = Color(1.2, 1.2, 1.5, 0.6 + (0.4 * pulse))
		else:
			# In normal mode, they remain solid
			structure_overlay.modulate = Color(1, 1, 1, 1)

	if active_lens == "energy" and not is_sleeping:
		var current_mouse_cell := local_to_map(get_local_mouse_position())
		var cam_energy := get_viewport().get_camera_2d()
		var cam_pos: Vector2 = Vector2.ZERO
		if is_instance_valid(cam_energy):
			cam_pos = cam_energy.global_position
		var farmer_cell := Vector2i(-1, -1)
		if is_instance_valid(farmer):
			farmer_cell = local_to_map(farmer.position)

		# 1. Redraw the heavy geometry ONLY if the camera pans, zones reset, or farmer moves
		if cam_pos != _last_camera_pos or _energy_zone_cache.is_empty() or farmer_cell != _last_energy_bg_farmer_cell:
			_last_camera_pos = cam_pos
			_last_energy_bg_farmer_cell = farmer_cell
			var energy_node := get_node_or_null("EnergyZoneOverlayNode")
			if energy_node:
				energy_node.queue_redraw()

		# 2. Redraw the fast cursor layer ONLY if the mouse enters a new tile
		if current_mouse_cell != _last_energy_mouse_cell:
			_last_energy_mouse_cell = current_mouse_cell
			var cursor_node := get_node_or_null("EnergyCursorOverlayNode")
			if cursor_node:
				cursor_node.queue_redraw()
			else:
				queue_redraw()
			if is_instance_valid(maintenance_bubble_overlay) and maintenance_bubble_overlay.visible:
				maintenance_bubble_overlay.queue_redraw()

	if active_lens == "guild" and not is_sleeping:
		var go := get_node_or_null("GuildOverlayNode") as Node2D
		if is_instance_valid(go):
			go.queue_redraw()

	var cam := get_viewport().get_camera_2d()
	if cam != null and cam.zoom.x < 0.8:
		return

	if not skip_tile_hover:
		if is_nan(mouse_pos.x) or is_nan(mouse_pos.y) or is_inf(mouse_pos.x) or is_inf(mouse_pos.y):
			if hover_label:
				hover_label.text = "Out of bounds"
			tile_hovered.emit({"in_bounds": false})
			return

		if is_nan(local_mouse.x) or is_nan(local_mouse.y) or is_inf(local_mouse.x) or is_inf(local_mouse.y):
			if hover_label:
				hover_label.text = "Out of bounds"
			tile_hovered.emit({"in_bounds": false})
			return

		var x := grid_pos.x
		var y := grid_pos.y

		if x >= 0 and x < _map_w() and y >= 0 and y < _map_w():
			var cell2: Dictionary = FarmDataManager.grid_data[x][y]
			var n_val := float(cell2.get("nitrogen", 5.0))
			var m_val := float(cell2.get("moisture", 5.0))
			var w_val := m_val # moisture alias for HUD (legacy `w` key retired from reads)
			if hover_label:
				hover_label.text = "Tile: (%d, %d)\nLand: %s\nN: %.1f | M: %.1f | W: %.1f" % [x, y, str(cell2.get("land", "?")), n_val, m_val, w_val]
			tile_hovered.emit(
				{
					"in_bounds": true,
					"x": x,
					"y": y,
					"land": str(cell2.get("land", "")),
					"n": n_val,
					"m": m_val,
					"w": w_val,
				}
			)
		else:
			if hover_label:
				hover_label.text = "Out of bounds"
			tile_hovered.emit({"in_bounds": false})


func undo_last_action() -> void:
	if is_sleeping or FarmDataManager.action_queue.is_empty():
		return

	var last_action: Dictionary = FarmDataManager.action_queue.back()
	var target_batch_id: int = last_action.get("batch_id", -1)

	var refund_e := 0
	var refund_m := 0
	var popped_batch: Array = []

	# Pop all actions that share the same batch_id
	while FarmDataManager.action_queue.size() > 0:
		var check_act: Dictionary = FarmDataManager.action_queue.back()
		if check_act.get("batch_id", -1) == target_batch_id:
			var removed: Dictionary = FarmDataManager.action_queue.pop_back()
			popped_batch.append(removed)
			refund_e += int(removed.get("energy_cost", 0))
			refund_m += int(removed.get("money_cost", 0))

			if str(removed.get("action", "")) == "build":
				var ap: Vector2i = removed.get("pos", Vector2i(-1, -1))
				var st := str(removed.get("structure", ""))
				for bi in range(FarmDataManager.blueprints.size() - 1, -1, -1):
					if FarmDataManager.blueprints[bi].get("anchor", Vector2i(-99999, -99999)) == ap \
						and str(FarmDataManager.blueprints[bi].get("structure", "")) == st:
						FarmDataManager.blueprints.remove_at(bi)

			_update_astar_cell(removed["pos"])
		else:
			break

	popped_batch.reverse() # Restore chronological order for redo
	FarmDataManager.redo_queue.append(popped_batch)

	FarmDataManager.refund_energy(refund_e)
	FarmDataManager.current_money += refund_m

	_refresh_all_visuals()
	_sync_hud_status()
	if has_method("_refresh_queue_ui"):
		_refresh_queue_ui()
	_reconcile_time_machine_draft()


func clear_queued_actions() -> void:
	if is_sleeping or FarmDataManager.action_queue.is_empty():
		return

	var refund_e := 0
	var refund_m := 0
	var astar_touched: Dictionary = {} # Vector2i -> true

	for removed in FarmDataManager.action_queue:
		refund_e += int(removed.get("energy_cost", 0))
		refund_m += int(removed.get("money_cost", 0))

		var ap: Vector2i = removed.get("pos", Vector2i(-1, -1)) as Vector2i
		if ap != Vector2i(-1, -1):
			astar_touched[ap] = true

		if str(removed.get("action", "")) == "build":
			var st := str(removed.get("structure", ""))
			for bi in range(FarmDataManager.blueprints.size() - 1, -1, -1):
				if FarmDataManager.blueprints[bi].get("anchor", Vector2i(-99999, -99999)) == ap \
					and str(FarmDataManager.blueprints[bi].get("structure", "")) == st:
					FarmDataManager.blueprints.remove_at(bi)

	FarmDataManager.action_queue.clear()
	FarmDataManager.redo_queue.clear()

	FarmDataManager.refund_energy(refund_e)
	FarmDataManager.current_money += refund_m

	for cell_pos in astar_touched:
		_update_astar_cell(cell_pos)

	if is_instance_valid(preview_overlay):
		preview_overlay.queue_redraw()
	_refresh_all_visuals()
	_sync_hud_status()
	if has_method("_refresh_queue_ui"):
		_refresh_queue_ui()
	_reconcile_time_machine_draft()


func redo_action() -> void:
	if is_sleeping or FarmDataManager.redo_queue.is_empty():
		return

	var batch: Array = FarmDataManager.redo_queue.pop_back()
	var cost_e := 0
	var cost_m := 0

	_on_time_machine_player_edit()
	for act in batch:
		cost_e += int(act.get("energy_cost", 0))
		cost_m += int(act.get("money_cost", 0))

		if str(act.get("action", "")) == "build":
			FarmDataManager.blueprints.append({
				"structure": act.get("structure", ""),
				"footprint": act.get("footprint", []),
				"anchor": act.get("pos", Vector2i.ZERO),
				"color": act.get("color", "fbc02d")
			})

		FarmDataManager.action_queue.append(act)
		_update_astar_cell(act["pos"])

	FarmDataManager.spend_energy(cost_e)
	FarmDataManager.current_money -= cost_m

	if RadioManager.has_method("play_action_note"):
		RadioManager.play_action_note("build")

	_refresh_all_visuals()
	_sync_hud_status()
	if has_method("_refresh_queue_ui"):
		_refresh_queue_ui()


## Updates season/year labels only. V3 ecology no longer applies a global moisture modifier each turn.
func _refresh_season_display() -> void:
	var year = int((FarmDataManager.current_turn - 1) / 48.0) + 1
	var season_idx = int((FarmDataManager.current_turn - 1) / 12.0) % 4
	var seasons = ["Spring", "Summer", "Autumn", "Winter"]
	FarmDataManager.current_season = seasons[season_idx]

	var desc = ""
	match FarmDataManager.current_season:
		"Spring":
			desc = "Gentle rains. The water table rises."
		"Summer":
			desc = "Dry midsummer heat. Soil is baking."
		"Autumn":
			desc = "Cool and damp. Fungal networks thrive."
		"Winter":
			desc = "Hard frost. The earth sleeps."

	if hud_instance:
		var sl: Label = hud_instance.get("season_label") as Label
		var wdl: Label = hud_instance.get("weather_desc_label") as Label
		if is_instance_valid(sl):
			sl.text = "Year %d - %s (Turn %d)" % [year, FarmDataManager.current_season, FarmDataManager.current_turn]
		if is_instance_valid(wdl):
			wdl.text = desc


func _generate_random_weather() -> String:
	if FarmDataManager.creative_weatherproof:
		return "clear" if randi() % 2 == 0 else "rain"
	var roll = randi() % 100
	var cumulative = 0
	for w_key in weather_types.keys():
		cumulative += weather_types[w_key]["prob"]
		if roll < cumulative:
			# Prevent Frost in Summer, or Dry in Winter
			if w_key == "frost" and FarmDataManager.current_season == "Summer":
				return "clear"
			if w_key == "dry" and FarmDataManager.current_season == "Winter":
				return "clear"
			return w_key
	return "clear"


## Calendar-day weather: CSV override (training simulation) or procedural roll (sandbox / unlisted days).
func _get_weather_for_day(target_day: int) -> String:
	if (
		FarmDataManager.active_campaign_id == "wormfood"
		and not MetaManager.dev_mode
	):
		var scripted := DataScenario.get_scripted_weather(target_day)
		if scripted != "":
			return _heritage_garden_weather(scripted)
	return _heritage_garden_weather(_generate_random_weather())


func _execute_worker_queue(w_data: Dictionary, w_queue: Array, dash_dur: float, wait_dur: float) -> void:
	var worker_sprite := Sprite2D.new()

	var tex_path = w_data.get("sprite", "res://icon.svg")
	if ResourceLoader.exists(tex_path):
		worker_sprite.texture = load(tex_path)
	else:
		worker_sprite.texture = preload("res://icon.svg")

	worker_sprite.modulate = Color.WHITE # Remove the artificial tint
	worker_sprite.z_index = 10
	worker_sprite.scale = Vector2(1.5, 1.5)
	worker_sprite.offset = Vector2(0, -60)
	worker_sprite.position = map_to_local(farmhouse_pos)
	add_child(worker_sprite)

	var w_night_time: float = 0.0

	for item in w_queue:
		var pos: Vector2i = item["pos"]
		var ax: int = pos.x
		var ay: int = pos.y

		# --- THE FARMER DASH (sequenced along saved A* path) ---
		var path_arr: Array = item.get("path", [])
		if path_arr.size() >= 2:
			var seg_count: int = path_arr.size() - 1
			var step_dur: float = dash_dur / float(seg_count)
			for pi in range(1, path_arr.size()):
				var step_cell: Vector2i = path_arr[pi] as Vector2i
				var target_px := map_to_local(step_cell)
				var dash = create_tween()
				dash.tween_property(worker_sprite, "position", target_px, step_dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				await dash.finished
		else:
			var target_px = map_to_local(Vector2i(ax, ay))
			var dash = create_tween()
			dash.tween_property(worker_sprite, "position", target_px, dash_dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			await dash.finished

		var act: String = item["action"]
		var cell: Dictionary = FarmDataManager.grid_data[ax][ay]

		match act:
			"rotovate", "e_tiller":
				if cell.get("has_path", false):
					cell["has_path"] = false
				cell["land"] = "cultivated"
				_clear_cell_plant_data(cell)
				var till_msg := "E-Tilled" if act == "e_tiller" else "Rotovated"
				spawn_floating_text(till_msg, Color("8d6e63"), Vector2i(pos.x, pos.y), "actions")
			"harvest":
				var mature := _mature_plant_on_cell(cell)
				if mature.is_empty():
					spawn_floating_text("Not Mature", Color("ffeb3b"), Vector2i(pos.x, pos.y), "warnings")
				else:
					var p_data_h: Dictionary = mature["data"]
					var was_pollinated_h := bool(cell.get("is_pollinated", false))
					var yield_amt_h := _compute_plant_yield_amount(ax, ay, str(mature["id"]))
					_clear_cell_pollination(cell)
					FarmDataManager.add_to_inventory(str(mature["id"]), yield_amt_h)
					var p_name_h := str(p_data_h.get("name", mature["id"]))
					spawn_floating_text(
						"+%d %s" % [yield_amt_h, p_name_h],
						Color("a5d6a7"),
						Vector2i(pos.x, pos.y),
						"ecology"
					)
					if was_pollinated_h:
						var poll_bonus_h := int(p_data_h.get("pollination_bonus", 1))
						spawn_floating_text(
							"Perfect Yield! +%d" % poll_bonus_h,
							Color("fff59d"),
							Vector2i(pos.x, pos.y) + Vector2i(0, -18),
							"ecology"
						)
					if str(p_data_h.get("lifecycle", "annual")) == "annual":
						_remove_plant_layer(cell, str(mature["layer"]))
					else:
						cell[str(mature["age_key"])] = float(p_data_h.get("mature_turn", 2)) / 2.0
			"chop_and_drop":
				var top_plant := _top_plant_on_cell(cell)
				if top_plant.is_empty():
					spawn_floating_text("No Plant", Color("ffeb3b"), Vector2i(pos.x, pos.y), "warnings")
				else:
					_apply_chop_and_drop_biomass(cell, top_plant["data"])
					_remove_plant_layer(cell, str(top_plant["layer"]))
					spawn_floating_text("Biomass Dropped!", Color("8bc34a"), Vector2i(pos.x, pos.y), "ecology")
			"scythe", "uproot":
				if not cell.has("soil_tags"):
					cell["soil_tags"] = ["clay"]

				var triggered_explosion = false

				for layer in ["canopy", "understory", "ground"]:
					if _cell_str_nonempty(cell, layer):
						var p_id = cell[layer]
						var p_data = preload("res://data/data_plants.gd").get_plant_data(p_id)

						if p_data.get("toxicity", "") == "Invasive weed" and act == "scythe":
							print("DISASTER! Scything triggered a seed explosion!")
							spawn_floating_text("SEED EXPLOSION!", Color("ff1744"), Vector2i(pos.x, pos.y), "warnings")
							triggered_explosion = true
						else:
							var yields = p_data.get("soil_yields", [])
							for y_tag in yields:
								if not y_tag in cell["soil_tags"]:
									cell["soil_tags"].append(y_tag)

							if "clay" in cell["soil_tags"] and ("well aerated" in yields or "loam" in yields):
								cell["soil_tags"].erase("clay")

						cell[layer] = ""
						cell.erase(layer + "_age")

				if triggered_explosion:
					for dx in range(-1, 2):
						for dy in range(-1, 2):
							if dx != 0 or dy != 0:
								var nx = clampi(pos.x + dx, 0, _map_w() - 1)
								var ny = clampi(pos.y + dy, 0, _map_w() - 1)
								var n_cell = FarmDataManager.grid_data[nx][ny]
								if str(n_cell.get("land", "")) in ["wild", "overgrown", "cultivated"]:
									if not _cell_str_nonempty(n_cell, "ground"):
										n_cell["ground"] = "himalayan_balsam"
										n_cell["ground_age"] = 0

				if act == "scythe":
					cell["land"] = "cultivated"
				elif act == "uproot":
					cell["land"] = "wild"

				spawn_floating_text("Cleared", Color("ffb74d"), Vector2i(pos.x, pos.y), "actions")
			"dig_swale":
				cell["land"] = "swale"
				cell["moisture"] = 10.0
			"build_mound":
				cell["land"] = "mound"
				cell["nitrogen"] = 5.0
				# Hugelbeds breathe life into the earth!
				cell["aeration"] = 85
				cell["biodiversity"] = clampi(int(cell.get("biodiversity", 10)) + 15, 0, 100)
			"plant":
				var seed_id: String = item.get("seed_id", "")
				if seed_id != "":
					var p_data = preload("res://data/data_plants.gd").get_plant_data(seed_id)
					var layer = str(p_data.get("layer", "ground")).to_lower()
					cell[layer] = seed_id
					spawn_floating_text("+ Planted", Color("a5d6a7"), Vector2i(pos.x, pos.y), "actions")
					cell[layer + "_age"] = 0
					cell[layer + "_yield"] = 0
			"water_tile", "hosepipe":
				var w_cap := SWALE_MOISTURE_MAX if str(cell.get("land", "")) == "swale" else 10.0
				if FarmDataManager.creative_infinite_water:
					cell["moisture"] = minf(10.0, w_cap)
				else:
					cell["moisture"] = clampf(float(cell.get("moisture", 5.0)) + 3.0, 0.0, w_cap)
				var water_msg := "Hosed" if act == "hosepipe" else "Watered"
				spawn_floating_text(water_msg, Color("64b5f6"), Vector2i(pos.x, pos.y), "actions")
			"apply_tea":
				cell["nitrogen"] = clampf(float(cell.get("nitrogen", 5.0)) + 2.0, 0.0, 10.0)
				cell["bacteria"] = clampf(float(cell.get("bacteria", 0.0)) + 3.0, 0.0, 10.0)
				cell["moisture"] = clampf(float(cell.get("moisture", 5.0)) + 1.0, 0.0, 10.0)
				spawn_floating_text("Fed!", Color("81c784"), Vector2i(pos.x, pos.y), "actions")
			"additive":
				var add_id: String = str(item.get("seed", item.get("seed_id", "")))
				if additives_data.has(add_id):
					var data = additives_data[add_id]
					if FarmDataManager.current_money >= int(data["cost"]):
						FarmDataManager.current_money -= int(data["cost"])
						cell["nitrogen"] = clampf(float(cell.get("nitrogen", 5.0)) + float(data["n"]), 0.0, 10.0)
						cell["moisture"] = clampf(float(cell.get("moisture", 5.0)) + float(data["m"]), 0.0, 10.0)
						spawn_floating_text("+ " + str(data["name"]), Color("#" + str(data["color"])), Vector2i(ax, ay), "ecology")
						spawn_floating_text("-£" + str(data["cost"]), Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
					else:
						spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
			"demolish":
				var demo_struct := str(cell.get("structure", ""))
				cell["structure"] = ""
				if cell.has("zone") and cell["zone"] == "pen":
					cell["zone"] = ""
				if demo_struct in ["battery", "solar_panel"]:
					FarmDataManager.clamp_stored_power()
				spawn_floating_text("Demolished", Color("9e9e9e"), Vector2i(ax, ay), "actions")
			"build_path":
				cell["has_path"] = true
				spawn_floating_text("Path", Color("9e9e9e"), Vector2i(ax, ay), "actions")
			"build":
				match str(item.get("structure", "")):
					"bridge":
						var fp: Variant = item.get("footprint", [])
						if fp is Array:
							for c in fp:
								if not c is Vector2i:
									continue
								var cx: int = c.x
								var cy: int = c.y
								if cx < 0 or cx >= _map_w() or cy < 0 or cy >= _map_h():
									continue
								var bc: Dictionary = FarmDataManager.grid_data[cx][cy]
								bc["land"] = "bridge"
								bc["has_path"] = true
								_update_single_tile_visual(Vector2i(cx, cy))
						_cached_farmer_pos = Vector2i(-1, -1)
						if RadioManager.has_method("play_action_note"):
							RadioManager.play_action_note("build")
						spawn_floating_text("Footbridge", Color("8d6e63"), Vector2i(ax, ay), "actions")
					"duck_house":
						for dy in range(-1, 2):
							for dx in range(-1, 2):
								var nx = ax + dx
								var ny = ay + dy
								if nx >= 0 and nx < _map_w() and ny >= 0 and ny < _map_w():
									var stamp_cell = FarmDataManager.grid_data[nx][ny]
									stamp_cell["zone"] = "pen"
									if dx == 0 and dy == 0:
										stamp_cell["structure"] = "duck_house"
									elif dx == 0 and dy == 1:
										stamp_cell["structure"] = "gate"
									elif abs(dx) == 1 or abs(dy) == 1:
										stamp_cell["structure"] = "fence"
						var water_dh = _find_nearest_water(ax, ay + 1, 60)
						if water_dh != Vector2i(-1, -1):
							var path_dh = _bresenham_line(Vector2i(ax, ay + 1), water_dh)
							_apply_corridor_brush(path_dh)
							spawn_floating_text("Corridor Linked", Color("64b5f6"), water_dh, "ecology")
						else:
							spawn_floating_text("No River", Color("ef5350"), Vector2i(ax, ay), "ecology")
						for dy2 in range(-1, 2):
							for dx2 in range(-1, 2):
								var nx2 = ax + dx2
								var ny2 = ay + dy2
								if nx2 >= 0 and nx2 < _map_w() and ny2 >= 0 and ny2 < _map_w():
									_update_single_tile_visual(Vector2i(nx2, ny2))
						if water_dh != Vector2i(-1, -1):
							var path_vis = _bresenham_line(Vector2i(ax, ay + 1), water_dh)
							for p in path_vis:
								for dy3 in range(-2, 3):
									for dx3 in range(-2, 3):
										if dx3 * dx3 + dy3 * dy3 <= 5:
											var vx = p.x + dx3
											var vy = p.y + dy3
											if vx >= 0 and vx < _map_w() and vy >= 0 and vy < _map_w():
												_update_single_tile_visual(Vector2i(vx, vy))
					"polytunnel":
						if FarmDataManager.current_money >= 15:
							FarmDataManager.current_money -= 15
							cell["zone"] = "polytunnel"
							spawn_floating_text("Polytunnel", Color("e0f7fa"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£15", Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"honesty_box":
						if FarmDataManager.current_money >= 25:
							FarmDataManager.current_money -= 25
							cell["structure"] = "honesty_box"
							spawn_floating_text("Honesty Box", Color("ffcc80"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£25", Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"pig_house":
						if FarmDataManager.current_money >= 80:
							FarmDataManager.current_money -= 80
							cell["structure"] = "pig_house"
							spawn_floating_text("Pig House", Color("f48fb1"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£80", Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"compost_brewer":
						if FarmDataManager.current_money >= 40:
							FarmDataManager.current_money -= 40
							cell["structure"] = "compost_brewer"
							spawn_floating_text("Compost Brewer", Color("81c784"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£40", Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"beehive":
						if FarmDataManager.current_money >= 80:
							FarmDataManager.current_money -= 80
							cell["structure"] = "beehive"
							spawn_floating_text("Beehive", Color("fff176"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£80", Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"sprinkler":
						if FarmDataManager.current_money >= 50:
							FarmDataManager.current_money -= 50
							cell["structure"] = "sprinkler"
							spawn_floating_text("Auto-Sprinkler", Color("4fc3f7"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£50", Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"drone_hub":
						if FarmDataManager.current_money >= 150:
							FarmDataManager.current_money -= 150
							cell["structure"] = "drone_hub"
							spawn_floating_text("Drone Hub", Color("b0bec5"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£150", Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"moisture_net":
						if FarmDataManager.current_money >= 75:
							FarmDataManager.current_money -= 75
							cell["structure"] = "moisture_net"
							spawn_floating_text("Moisture Net", Color("81d4fa"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£75", Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"smart_shade":
						if FarmDataManager.current_money >= 200:
							FarmDataManager.current_money -= 200
							cell["structure"] = "smart_shade"
							spawn_floating_text("Smart Shade", Color("fff176"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£200", Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"drone_pollinator":
						if FarmDataManager.current_money >= 300:
							FarmDataManager.current_money -= 300
							cell["structure"] = "drone_pollinator"
							spawn_floating_text("Drone Pollinator", Color("ce93d8"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£300", Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"solar_panel":
						var solar_cost := int(preload("res://data/data_objects.gd").ENTRIES["solar_panel"]["cost"])
						if FarmDataManager.current_money >= solar_cost:
							FarmDataManager.current_money -= solar_cost
							cell["structure"] = "solar_panel"
							spawn_floating_text("Solar Panel", Color("ffeb3b"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£" + str(solar_cost), Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"battery":
						var battery_cost := int(preload("res://data/data_objects.gd").ENTRIES["battery"]["cost"])
						if FarmDataManager.current_money >= battery_cost:
							FarmDataManager.current_money -= battery_cost
							cell["structure"] = "battery"
							spawn_floating_text("Battery Array", Color("aed581"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£" + str(battery_cost), Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					"water_butt":
						var butt_cost := int(preload("res://data/data_objects.gd").ENTRIES["water_butt"]["cost"])
						if FarmDataManager.current_money >= butt_cost:
							FarmDataManager.current_money -= butt_cost
							cell["structure"] = "water_butt"
							spawn_floating_text("Water Butt", Color("4fc3f7"), Vector2i(ax, ay), "actions")
							spawn_floating_text("-£" + str(butt_cost), Color("ef5350"), Vector2i(ax, ay) + Vector2i(0, -20), "actions")
						else:
							spawn_floating_text("Too Poor!", Color("ef5350"), Vector2i(ax, ay), "warnings")
					_:
						pass
			_:
				pass

		_update_single_tile_visual(Vector2i(ax, ay))

		# Record this note using the true elapsed time of the night sequence
		# Pass the action type (act) so the chime knows the correct octave
		var played_pitch = play_synesthesia_chime(act, false)
		night_memory.append({"pitch": played_pitch, "y_pos": ay, "time": w_night_time, "played_this_loop": false})

		# Advance our internal clock by the exact time it takes to complete this loop step
		w_night_time += (dash_dur + wait_dur)

		# Use process_always=true so the timer doesn't accidentally snag on edge cases
		await get_tree().create_timer(wait_dur, true, false, true).timeout
	# --- RETURN HOME ---
	if is_instance_valid(worker_sprite):
		var start_pos: Vector2i = local_to_map(worker_sprite.position)
		var home_path: Array = farm_astar.get_id_path(start_pos, home_pos)
		if home_path.size() > 1:
			var seg_count: int = home_path.size() - 1
			var step_dur: float = 0.4 / float(seg_count)
			for pi in range(1, home_path.size()):
				var step_cell: Vector2i = home_path[pi] as Vector2i
				var target_px := map_to_local(step_cell)
				var return_seg = create_tween()
				return_seg.tween_property(worker_sprite, "position", target_px, step_dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				await return_seg.finished
		else:
			var return_dash = create_tween()
			return_dash.tween_property(worker_sprite, "position", map_to_local(home_pos), 0.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			await return_dash.finished

	worker_sprite.queue_free()
	_active_zipping_workers -= 1
	if _active_zipping_workers <= 0:
		workers_finished.emit()

func _generate_triage_data() -> void:
	triage_cache.clear()
	for x in range(FarmDataManager.player_bounds_left + 1, FarmDataManager.player_bounds_right):
		for y in range(_map_h()):
			var cell = FarmDataManager.grid_data[x][y]
			for layer in ["canopy", "understory", "ground"]:
				if _cell_str_nonempty(cell, layer):
					var p_id = cell[layer]
					var p_data = preload("res://data/data_plants.gd").get_plant_data(p_id)
					if float(cell.get("moisture", 5.0)) < 2.0:
						triage_cache[Vector2i(x, y)] = {"msg": "Thirsty!", "color": Color("ffb74d")}
						break
					elif float(cell.get("nitrogen", 5.0)) < 1.0:
						triage_cache[Vector2i(x, y)] = {"msg": "Hungry!", "color": Color("ba68c8")}
						break
					elif _is_in_canopy_shadow(x, y) and str(p_data.get("shade_tolerance", "Medium")) == "Low":
						triage_cache[Vector2i(x, y)] = {"msg": "Needs Sun!", "color": Color("9e9e9e")}
						break


func trigger_sleep() -> void:
	if is_sleeping:
		return
	if FarmDataManager.is_time_machine_enabled():
		FarmDataManager.commit_timeline_branch_before_turn()
	if almanac_open:
		close_almanac()
	OS.low_processor_usage_mode = false
	_cached_farmer_pos = Vector2i(-1, -1)
	is_sleeping = true
	is_daytime = false
	night_memory.clear()
	_daytime_melody.clear()
	_sequence_step = 0

	# 0. Uncap FPS for smooth cinematic playback
	Engine.max_fps = 60

	# Calculate dynamic playback speeds. The more actions queued, the faster the flurry!
	var dash_dur: float = 0.1
	var wait_dur: float = 0.15
	if FarmDataManager.action_queue.size() > 10:
		dash_dur = 0.05
		wait_dur = 0.05
	if FarmDataManager.action_queue.size() > 25:
		dash_dur = 0.02
		wait_dur = 0.02

	# Group actions by worker
	var queues_by_worker = {}
	for item in FarmDataManager.action_queue:
		var w_id = item.get("worker_id", FarmDataManager.active_worker_id)
		if not queues_by_worker.has(w_id):
			queues_by_worker[w_id] = []
		queues_by_worker[w_id].append(item)

	if queues_by_worker.size() > 0:
		_active_zipping_workers = queues_by_worker.size()
		if is_instance_valid(farmer):
			farmer.hide()
		for w_id in queues_by_worker:
			var w_data = _get_worker_data(w_id)
			_execute_worker_queue(w_data, queues_by_worker[w_id], dash_dur, wait_dur)
		await self.workers_finished
		if is_instance_valid(farmer):
			farmer.show()

	if is_instance_valid(farmer):
		farmer.position = map_to_local(home_pos)
	_cached_farmer_pos = Vector2i(-1, -1)

	FarmDataManager.blueprints.clear()
	if is_instance_valid(preview_overlay):
		preview_overlay.queue_redraw()
	queue_redraw()

	# 2. Advance the ecosystem math and weather (maintenance workers timelapse, then simulation)
	await advance_turn()

	# Wait for the camera director to finish its cinematic panning before returning control!
	if not overnight_events.is_empty() and is_instance_valid(main_camera) and main_camera.get("is_playing_events"):
		await main_camera.events_finished

	# 3. Final visual redraw
	if has_method("_refresh_all_visuals"):
		_refresh_all_visuals()
	if has_method("_refresh_minimap"):
		_refresh_minimap()

	FarmDataManager.action_queue.clear()
	_sync_astar_with_grid()
	_refresh_queue_ui()


	# --- COMPOSE THE DAYTIME AMBIENCE ---
	_daytime_melody.clear()
	for note in night_memory:
		_daytime_melody.append(note["pitch"])

	if _daytime_melody.size() > 0:
		# Sort the pitches lowest to highest to create a harmonious, sweeping chord
		_daytime_melody.sort()

	# Reset the 16-step sequencer for the new day
	_sequence_step = 0

	# One redraw after the zip phase (overlays were throttled while is_sleeping)
	if is_instance_valid(energy_zone_overlay):
		energy_zone_overlay.queue_redraw()
	if is_instance_valid(energy_cursor_overlay):
		energy_cursor_overlay.queue_redraw()
	if is_instance_valid(structure_overlay):
		structure_overlay.queue_redraw()

	is_daytime = true

	_generate_triage_data()
	morning_triage_active = false
	get_tree().create_timer(3.0, false).timeout.connect(func():
		morning_triage_active = true
		get_tree().create_timer(10.0, false).timeout.connect(func(): morning_triage_active = false)
	)
	is_sleeping = false
	OS.low_processor_usage_mode = true

	# VIBE CODING: Return to the chill, empty beat
	if RadioManager.has_method("set_music_state"):
		RadioManager.set_music_state("Idle")

	print("Turn advanced to: ", FarmDataManager.current_turn)


func advance_turn() -> void:
	_calculate_maintenance_bubble()
	if maintenance_bubble.is_empty():
		await _process_turn_logic()
		_finalize_turn_time_machine()
		return

	# VIBE CODING: Shift to the fast action sequence
	if RadioManager.has_method("set_music_state"):
		RadioManager.set_music_state("Dash")

	get_tree().paused = true

	# WAIT FOR THE DROP: Pause the code here until the metronome hits a strong beat (0 or 4)
	if RadioManager.has_signal("native_beat_hit"):
		while RadioManager.current_beat % 4 != 0:
			await RadioManager.native_beat_hit

	# Now that we are on the beat, uncap FPS and begin the flurry!
	Engine.max_fps = 60

	# Find the maintenance worker's sprite and color
	var tex_path = "res://icon.svg"
	var worker_color = Color("fbc02d")
	for w in FarmDataManager.workers:
		if w.get("role") == "maintenance":
			worker_color = Color(w.get("color", "fbc02d"))
			tex_path = w.get("sprite", "res://icon.svg")
			break

	var worker_root := Sprite2D.new()
	if ResourceLoader.exists(tex_path):
		worker_root.texture = load(tex_path)
		worker_root.modulate = Color.WHITE # Use the actual sprite colors
	else:
		worker_root.texture = preload("res://icon.svg")
		worker_root.modulate = worker_color # Fallback to tinted square

	worker_root.scale = Vector2(1.5, 1.5)
	worker_root.offset = Vector2(0, -60)
	worker_root.z_index = 100
	worker_root.position = map_to_local(farmhouse_pos)
	add_child(worker_root)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	var stops: int = mini(8, maintenance_bubble.size())
	var shuffled_bubble: Array = maintenance_bubble.duplicate()
	shuffled_bubble.shuffle()

	for i in range(stops):
		var target_pos: Vector2 = map_to_local(shuffled_bubble[i])
		var step_duration: float = (60.0 / float(RadioManager.current_bpm)) / 4.0 # 16th notes, locked to BPM
		var task_words: Array[String] = ["Watering", "Weeding", "Tending", "Pruning"]
		var tile_for_text: Vector2i = shuffled_bubble[i]
		tween.tween_callback(func(): spawn_floating_text(task_words.pick_random(), Color("aed581"), tile_for_text, "ecology"))

		# Use the dedicated sequential arpeggiator for the zip phase
		tween.tween_callback(func(): RadioManager.play_zip_note())
		tween.tween_property(worker_root, "position", target_pos, step_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(worker_root, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func():
		if is_instance_valid(worker_root):
			worker_root.queue_free()
		get_tree().paused = false
	)
	await tween.finished
	await _process_turn_logic()
	_finalize_turn_time_machine()


func _finalize_turn_time_machine() -> void:
	if not FarmDataManager.is_time_machine_enabled():
		return
	FarmDataManager._snapshot_grid()
	FarmDataManager.clear_history_playhead()
	_update_time_machine_timeline()
	if is_instance_valid(hud_instance) and hud_instance.has_method("update_action_queue_ui"):
		hud_instance.update_action_queue_ui(FarmDataManager.action_queue)
	_refresh_queue_ui()


func _time_machine_latest_index() -> int:
	return maxi(0, FarmDataManager.history_buffer.size() - 1)


func _update_time_machine_timeline() -> void:
	if not is_instance_valid(hud_instance) or not hud_instance.has_method("update_time_machine_slider"):
		return
	var latest := _time_machine_latest_index()
	var current := FarmDataManager.get_history_playhead()
	var turn := FarmDataManager.get_turn_at_history_index(current)
	hud_instance.update_time_machine_slider(latest, current, turn)


func _on_time_machine_player_edit() -> void:
	FarmDataManager.mark_timeline_draft()
	_update_time_machine_timeline()


func _reconcile_time_machine_draft() -> void:
	if not FarmDataManager.is_time_machine_enabled():
		return
	if not FarmDataManager.try_clear_timeline_draft():
		return
	_refresh_all_visuals()
	_sync_hud_status()
	if is_instance_valid(hud_instance) and hud_instance.has_method("update_action_queue_ui"):
		hud_instance.update_action_queue_ui(FarmDataManager.action_queue)
	_refresh_queue_ui()
	_update_time_machine_timeline()


func _on_timeline_scrub(index: int) -> void:
	if not FarmDataManager.is_time_machine_enabled():
		return
	if index < 0 or index >= FarmDataManager.history_buffer.size():
		return
	var prev := FarmDataManager.get_history_playhead()
	if index > prev and FarmDataManager.is_timeline_draft_pending():
		if not FarmDataManager.try_clear_timeline_draft():
			_update_time_machine_timeline()
			return
	FarmDataManager.set_history_playhead(index)
	if not FarmDataManager.apply_history_snapshot(index):
		return
	_refresh_all_visuals()
	_sync_hud_status()
	_refresh_season_display()
	if is_instance_valid(hud_instance) and hud_instance.has_method("update_action_queue_ui"):
		hud_instance.update_action_queue_ui(FarmDataManager.action_queue)
	_refresh_queue_ui()
	if index >= FarmDataManager.history_buffer.size() - 1 and not FarmDataManager.is_timeline_draft_pending():
		FarmDataManager.clear_history_playhead()
	_update_time_machine_timeline()


func _on_rhythm_tick(_beat_index: int) -> void:
	# Play the slow, echoey 4-bar arpeggio (1 note per beat)
	if _daytime_melody.size() > 0:

		# 1. Get the target index from our 16-step musical pattern
		var pattern_index = MELODY_PATTERN[_sequence_step]

		# 2. Safely wrap it to however many notes the player actually played yesterday
		var safe_index = pattern_index % _daytime_melody.size()
		var pitch_to_play = _daytime_melody[safe_index]

		if has_method("play_synesthesia_chime"):
			play_synesthesia_chime("", true, pitch_to_play)

		# 3. Advance the sequencer to the next step, looping back to 0 after 16 steps
		_sequence_step = (_sequence_step + 1) % MELODY_PATTERN.size()


func _process_turn_logic() -> void:
	overnight_events.clear()
	_process_oakhaven_npc_turn()

	if FarmDataManager.active_campaign_id == "automata":
		for x in range(FarmDataManager.map_width):
			for y in range(FarmDataManager.map_height):
				var cell_a: Dictionary = FarmDataManager.grid_data[x][y]
				if _cell_fixture_id(cell_a) == "sprinkler":
					_apply_automated_watering(Vector2i(x, y))
		for x in range(FarmDataManager.map_width):
			for y in range(FarmDataManager.map_height):
				var cell_b: Dictionary = FarmDataManager.grid_data[x][y]
				if _cell_fixture_id(cell_b) == "drone_hub":
					_apply_drone_harvest(Vector2i(x, y))
		for x in range(FarmDataManager.map_width):
			for y in range(FarmDataManager.map_height):
				var cell_c: Dictionary = FarmDataManager.grid_data[x][y]
				if _cell_fixture_id(cell_c) == "drone_pollinator":
					_apply_drone_pollinator(Vector2i(x, y))

	# --- CONSUME WEATHER EVENT ---
	# Pop = weather for this night’s transition; append replaces the far tail (day current_turn+5 after pop).
	if forecast.is_empty():
		forecast.clear()
		for i in range(5):
			var refill_day: int = FarmDataManager.current_turn + i
			forecast.append(_get_weather_for_day(refill_day))
	var todays_weather: String = forecast.pop_front()
	if todays_weather == "drought":
		todays_weather = "dry" # legacy key / old saves
	todays_weather = _heritage_garden_weather(todays_weather)
	forecast.append(_get_weather_for_day(FarmDataManager.current_turn + 5))

	var weather_data: Dictionary = weather_types.get(todays_weather, weather_types["clear"])
	if FarmDataManager.active_campaign_id == "automata":
		if todays_weather == "rain":
			weather_data = {"name": "Acid Rain", "color": "33ff66"}
		elif todays_weather == "clear":
			weather_data = {"name": "Scorcher", "color": "ff8f00"}
	spawn_floating_text(
		str(weather_data["name"]),
		Color("#" + str(weather_data["color"])),
		home_pos + Vector2i(0, -2),
		"warnings"
	)

	_last_night_weather = todays_weather

	# --- V3 DAILY WEATHER → moisture (0–10, swales 0–SWALE_MOISTURE_MAX); infra skip; polytunnel mild −0.2 ---
	const SKIP_WEATHER_LANDS: Array[String] = ["road", "house", "house_door", "bridge", "river", "stream"]
	for x in range(_map_w()):
		if x % 16 == 0:
			await get_tree().process_frame
		for y in range(_map_h()):
			var cell: Dictionary = FarmDataManager.grid_data[x][y]
			var land_k := str(cell.get("land", ""))
			if land_k in SKIP_WEATHER_LANDS:
				continue

			if FarmDataManager.active_campaign_id == "desert":
				var soil_struct := _cell_soil_structure_metric(cell)
				var evaporation := 0.2 if soil_struct > 3.0 else 1.0
				cell["moisture"] = maxf(0.0, float(cell.get("moisture", 0.0)) - evaporation)
				if _cell_fixture_id(cell) == "moisture_net":
					cell["moisture"] = minf(10.0, float(cell.get("moisture", 0.0)) + 2.0)
					_apply_moisture_net_drip(Vector2i(x, y))

			if FarmDataManager.active_campaign_id == "automata" \
				and not _cell_within_fixture_radius(Vector2i(x, y), "smart_shade", 2):
				var mo_ext := float(cell.get("moisture", 5.0))
				if todays_weather == "rain":
					cell["toxicity"] = minf(10.0, float(cell.get("toxicity", 0.0)) + 1.5)
					cell["moisture"] = minf(10.0, mo_ext + 3.0)
				elif todays_weather == "clear":
					cell["moisture"] = maxf(0.0, mo_ext - 1.5)

			var mo := float(cell.get("moisture", 5.0))

			if str(cell.get("zone", "")) == "polytunnel":
				cell["moisture"] = clampf(mo - 0.2, 0.0, 10.0)
				continue

			match todays_weather:
				"rain":
					if land_k == "swale":
						# Deep reservoir: +6 per rain, cap above normal soil (see SWALE_MOISTURE_MAX).
						mo += 6.0
					else:
						mo += 3.0
				"clear":
					mo -= 0.25 if land_k == "mound" else 0.5
				"dry":
					mo -= 1.0 if land_k == "mound" else 2.0
				"frost":
					mo -= 0.5
				_:
					mo -= 0.25 if land_k == "mound" else 0.5

			var mo_cap := SWALE_MOISTURE_MAX if land_k == "swale" else 10.0
			cell["moisture"] = clampf(mo, 0.0, mo_cap)

			if todays_weather == "frost" \
				and not FarmDataManager.creative_zen_mode \
				and FarmDataManager.active_campaign_id != "heritage_garden":
				if str(cell.get("zone", "")) == "polytunnel":
					continue # The plastic sheeting protects them!
				for l in ["canopy", "understory", "ground"]:
					var p_id = cell.get(l, "")
					if str(p_id) != "":
						var frost_resist = preload("res://data/data_plants.gd").get_plant_data(str(p_id)).get("frost_hardiness", 5)
						if frost_resist < 4:
							var wf_stats := "[M:%.1f N:%.1f Min:%.1f]" % [
								float(cell.get("moisture", 0.0)),
								float(cell.get("nitrogen", 0.0)),
								float(cell.get("minerals", 0.0)),
							]
							print(
								"❄️ Turn ",
								FarmDataManager.current_turn,
								" | Plant died at (",
								x,
								", ",
								y,
								") [",
								str(p_id),
								"] Reason: Frost (weather) Stats: ",
								wf_stats
							)
							cell[l] = ""
							cell.erase(l + "_age")
							spawn_floating_text("Frozen", Color("81d4fa"), Vector2i(x, y), "warnings")
							overnight_events.append({
								"type": "plant_died",
								"pos": map_to_local(Vector2i(x, y)),
							})

	await _apply_overnight_bee_pollination()

	var daily_profits: Array = []
	_refresh_season_display()
	var spreading_spawns: Array[Dictionary] = [] # BUFFER: Holds invasive plants trying to spread this turn

	const MOISTURE_CAP := 10.0
	for x in range(_map_w()):
		if x % 16 == 0:
			await get_tree().process_frame
		for y in range(_map_h()):
			var cell: Dictionary = FarmDataManager.grid_data[x][y]

			# 1.5 Infinite River Hydration & Capillary Action (V3: moisture 0–10)
			var land_here := str(cell.get("land", ""))
			if land_here == "river":
				cell["moisture"] = 10.0
			# 1.6 Stream Capillary Action (Smaller radius than the river)
			elif land_here == "stream":
				cell["moisture"] = 10.0
				for dx in range(-2, 3):
					for dy in range(-2, 3):
						var nx = clampi(x + dx, 0, _map_w() - 1)
						var ny = clampi(y + dy, 0, _map_w() - 1)
						if str(FarmDataManager.grid_data[nx][ny].get("land", "")) not in ["river", "stream", "bridge", "road"]:
							var dist = max(abs(dx), abs(dy))
							var min_w := 10.0 - (float(dist) * 1.33)
							min_w = maxf(min_w, 4.0)
							var nc: Dictionary = FarmDataManager.grid_data[nx][ny]
							if float(nc.get("moisture", 0.0)) < min_w:
								nc["moisture"] = min_w

			# 1.7 Swale capillary: slow-drip battery; only tops up thirsty neighbors; max bleed per night capped.
			elif land_here == "swale":
				var swale_m := float(cell.get("moisture", 0.0))
				const SWALE_MIN_MO := 3.0
				const MAX_BLEED_PER_TURN := 3.0
				if swale_m > SWALE_MIN_MO:
					var budget := minf(swale_m - SWALE_MIN_MO, MAX_BLEED_PER_TURN)
					var total_out := 0.0
					for dx in range(-2, 3):
						for dy in range(-2, 3):
							var dist := maxi(abs(dx), abs(dy))
							if dist <= 0:
								continue
							var nx := clampi(x + dx, 0, _map_w() - 1)
							var ny := clampi(y + dy, 0, _map_w() - 1)
							if str(FarmDataManager.grid_data[nx][ny].get("land", "")) in ["river", "stream", "bridge", "road", "swale"]:
								continue
							var nc: Dictionary = FarmDataManager.grid_data[nx][ny]
							var nc_mo := float(nc.get("moisture", 0.0))
							if nc_mo < 7.0:
								var want := 0.5 / float(dist)
								want = minf(want, 7.0 - nc_mo)
								want = minf(want, maxf(0.0, budget - total_out))
								if want > 0.0:
									nc["moisture"] = clampf(nc_mo + want, 0.0, MOISTURE_CAP)
									total_out += want
					cell["moisture"] = clampf(swale_m - total_out, SWALE_MIN_MO, SWALE_MOISTURE_MAX)

			elif y >= _map_h() - RIVER_ROW_COUNT - 6:
				# Capillary from static bottom river: vertical distance only (no 13×13 scan per river tile)
				var dist = (_map_h() - RIVER_ROW_COUNT) - y
				var min_w = 10.0 - (float(dist) * 1.33)
				min_w = maxf(min_w, 3.0)
				if float(cell.get("moisture", 0.0)) < min_w:
					cell["moisture"] = min_w

			var post_cap := SWALE_MOISTURE_MAX if land_here == "swale" else MOISTURE_CAP
			cell["moisture"] = clampf(float(cell.get("moisture", 5.0)), 0.0, post_cap)

	for rx in range(_map_w()):
		for ry in range(_map_w()):
			if str(FarmDataManager.grid_data[rx][ry].get("land", "")) == "river":
				var rc: Dictionary = FarmDataManager.grid_data[rx][ry]
				rc["moisture"] = 10.0

	# Process Plant Lifecycles
	var turn_profit := 0
	var solar_count := 0
	var battery_count := 0
	var butt_count := 0
	var gen_weather := todays_weather
	if not forecast.is_empty():
		gen_weather = forecast[0]

	for x in range(_map_w()):
		for y in range(_map_h()):
			var cell: Dictionary = FarmDataManager.grid_data[x][y]
			var st_id := str(cell.get("structure", ""))
			if st_id == "solar_panel":
				solar_count += 1
			elif st_id == "battery":
				battery_count += 1
			elif st_id == "water_butt":
				butt_count += 1

			# Process all vertical plant layers
			for layer in ["canopy", "understory", "ground"]:
				if _cell_str_nonempty(cell, layer):
					var p_id = cell[layer]
					var p_data = preload("res://data/data_plants.gd").get_plant_data(p_id)

					# 1. Synergy baseline + guild (3×3 companions → growth_mult from data_guilds)
					var syn_mult := 1.0
					var guild_buff: float = _get_guild_synergy_mult(x, y, str(p_id))
					if guild_buff > 1.0:
						syn_mult *= guild_buff
						if randf() < 0.06:
							spawn_floating_text("Synergy!", Color("81c784"), Vector2i(x, y), "ecology")

					# 1.5 Calculate Shade Tolerance
					var in_shadow = _is_in_canopy_shadow(x, y)
					var shade_tol = p_data.get("shade_tolerance", "Medium")

					if in_shadow and layer != "canopy":
						if shade_tol == "Low":
							syn_mult = 0.0 # Plant refuses to grow in the dark
							print("A sun-loving plant at ", x, ", ", y, " is stunted by canopy shadow!")
						elif shade_tol == "High":
							syn_mult *= 1.5 # Forest-floor plants thrive in the shade!
					elif not in_shadow and layer != "canopy" and shade_tol == "High":
						syn_mult = 0.5 # Deep-shade plants suffer if left out in the blazing sun

					# 1.6 SOIL QUALITY PENALTY
					var reqs = p_data.get("soil_reqs", [])
					var missing_count = 0
					var current_tags = cell.get("soil_tags", ["clay"])

					for r in reqs:
						if not r in current_tags:
							missing_count += 1

					if missing_count > 0:
						# Plant grows 50% slower for EVERY missing soil requirement
						syn_mult *= pow(0.5, missing_count)

					var age_key = layer + "_age"

					# 1.8 THE WINTER FROST
					if FarmDataManager.current_season == "Winter":
						syn_mult = 0.0 # Total dormancy. Nothing grows in the frozen ground.

						var hardiness = p_data.get("frost_hardiness", 5)
						if hardiness < 8:
							# Tender plants take severe frostbite damage
							cell[age_key] = float(cell.get(age_key, 0.0)) - 0.5
							spawn_floating_text("- Frostbite", Color("00e5ff"), Vector2i(x, y), "warnings")

							if FarmDataManager.creative_zen_mode:
								cell[age_key] = maxf(float(cell[age_key]), 0.1)
							elif float(cell[age_key]) < -3.0:
								var f_stats := "[M:%.1f N:%.1f Min:%.1f]" % [
									float(cell.get("moisture", 0.0)),
									float(cell.get("nitrogen", 0.0)),
									float(cell.get("minerals", 0.0)),
								]
								print(
									"❄️ Turn ",
									FarmDataManager.current_turn,
									" | Plant died at (",
									x,
									", ",
									y,
									") [",
									str(p_id),
									"] Reason: Frostbite Stats: ",
									f_stats
								)
								cell[layer] = ""
								cell.erase(age_key)
								continue # Plant is dead, skip the rest of the loop

					# 2. Apply Growth (roots read aeration; V3 gatekeepers can kill the plant)
					var bio_growth: float = _process_plant_biology(Vector2i(x, y), str(p_id), "growth", layer)
					if bio_growth < 0.0:
						continue
					cell[age_key] = cell.get(age_key, 0) + (1 * syn_mult * bio_growth)

					# 3. Handle Harvest (optional automation)
					if FarmDataManager.auto_harvest and cell[age_key] >= p_data.get("mature_turn", 2):
						var y_val = p_data.get("yield_val", 0)
						if y_val > 0:
							# ONLY HARVEST ON PLAYER PROPERTY
							if x > FarmDataManager.player_bounds_left and x < FarmDataManager.player_bounds_right:
								var was_pollinated_auto := bool(cell.get("is_pollinated", false))
								var yield_amt := _compute_plant_yield_amount(x, y, str(p_id))
								_clear_cell_pollination(cell)

								if FarmDataManager.auto_sell:
									var base_cost = p_data.get("cost", 2)
									var profit = base_cost * 2 * yield_amt
									var charm_mult = 1.2 if MetaManager.has_upgrade("hypnotic_charm") else 1.0
									var final_profit = int(round(profit * charm_mult))
									FarmDataManager.current_money += final_profit
									daily_profits.append({"pos": Vector2i(x, y), "amount": final_profit})
								else:
									FarmDataManager.add_to_inventory(str(p_id), yield_amt)
								if was_pollinated_auto:
									spawn_floating_text(
										"Perfect Yield! +%d" % int(p_data.get("pollination_bonus", 1)),
										Color("fff59d"),
										Vector2i(x, y),
										"ecology"
									)

							if p_data.get("lifecycle", "annual") == "annual":
								cell[layer] = ""
								cell.erase(age_key)
							else:
								cell[age_key] = float(p_data.get("mature_turn", 2)) / 2.0

					# 4. V3 soil web exchange (moisture/N/minerals + micro-life)
					if _cell_str_nonempty(cell, layer):
						_process_plant_biology(Vector2i(x, y), str(p_id), "exchange", layer)

					# 5. Invasive & Natural Spreading
					var spread_rate = p_data.get("spread_rate", 0)
					if FarmDataManager.current_season == "Winter":
						spread_rate = 0 # The frost halts all invasive creeping
					# Plants must be at least half mature to drop seeds or send runners
					if spread_rate > 0 and cell.get(age_key, 0) >= (float(p_data.get("mature_turn", 2)) / 2.0):
						# High spread rate = higher chance per turn (e.g. Balsam at 10 = 25% chance)
						# Drop the multiplier to 0.05. A spread rate of 10 now equals a 0.5% daily chance (~3.5% per week)
						if randf() * 100 < (spread_rate * 0.05):
							var dx = (randi() % 3) - 1
							var dy = (randi() % 3) - 1
							if dx != 0 or dy != 0:
								var nx = clampi(x + dx, 0, _map_w() - 1)
								var ny = clampi(y + dy, 0, _map_w() - 1)
								spreading_spawns.append({"x": nx, "y": ny, "layer": layer, "p_id": p_id})

			# --- DRY-WEATHER DEATH MECHANIC (legacy + V3 moisture) ---
			if float(cell.get("moisture", 0.0)) <= 0.0:
				var died = false
				for layer in ["canopy", "understory", "ground"]:
					if _cell_str_nonempty(cell, layer):
						var p_id = cell[layer]
						var p_data = preload("res://data/data_plants.gd").get_plant_data(p_id)
						if p_data.get("lifecycle", "annual") == "annual":
							var d_stats := "[M:%.1f N:%.1f Min:%.1f]" % [
								float(cell.get("moisture", 0.0)),
								float(cell.get("nitrogen", 0.0)),
								float(cell.get("minerals", 0.0)),
							]
							print(
								"🏜️ Turn ",
								FarmDataManager.current_turn,
								" | Plant died at (",
								x,
								", ",
								y,
								") [",
								p_id,
								"] Reason: Desiccation Stats: ",
								d_stats
							)
							cell[layer] = "" # Shallow-rooted annuals die
							cell.erase(layer + "_age")
							died = true
						else:
							cell[layer + "_age"] = 0 # Perennials survive but lose their current yield progress
				if died:
					overnight_events.append({
						"type": "plant_died",
						"pos": map_to_local(Vector2i(x, y)),
					})

	# Process Animal Systems (Pig Tractors)
	for x in range(_map_w()):
		if x % 16 == 0:
			await get_tree().process_frame
		for y in range(_map_h()):
			var cell: Dictionary = FarmDataManager.grid_data[x][y]
			if str(cell.get("structure", "")) == "pig_house":
				# The pig grazes a 3x3 area around its house for overgrown weeds
				var rooted := false
				for dx in range(-1, 2):
					if rooted:
						break
					for dy in range(-1, 2):
						if rooted:
							break
						var nx := clampi(x + dx, 0, _map_w() - 1)
						var ny := clampi(y + dy, 0, _map_w() - 1)

						if str(FarmDataManager.grid_data[nx][ny].get("land", "")) == "overgrown":
							# The pig roots up the weeds (rotovates) and leaves manure (+2.0 N)
							FarmDataManager.grid_data[nx][ny]["land"] = "cultivated"
							var pc: Dictionary = FarmDataManager.grid_data[nx][ny]
							pc["nitrogen"] = clampf(float(pc.get("nitrogen", 5.0)) + 0.4, 0.0, 10.0)
							pc["macro_life"] = clampf(float(pc.get("macro_life", 2.0)) + 0.2, 0.0, 10.0)
							rooted = true # Only clear one tile per turn to balance the game

	var base_power_capacity := FarmDataManager.GVCS_BASE_POWER_CAPACITY
	var total_max_power := base_power_capacity + (solar_count * FarmDataManager.GVCS_SOLAR_CAPACITY_BONUS) + (battery_count * FarmDataManager.GVCS_BATTERY_CAPACITY)
	var max_water := butt_count * FarmDataManager.GVCS_STORAGE_PER_STRUCTURE
	if gen_weather == "clear" and solar_count > 0:
		FarmDataManager.current_power = mini(
			total_max_power,
			FarmDataManager.current_power + (solar_count * GVCS_SOLAR_CHARGE_PER_PANEL)
		)
	if gen_weather == "rain":
		FarmDataManager.current_water = mini(
			max_water,
			FarmDataManager.current_water + (butt_count * GVCS_WATER_PER_BUTT)
		)
	FarmDataManager.current_power = mini(total_max_power, FarmDataManager.current_power)
	FarmDataManager.current_water = mini(max_water, FarmDataManager.current_water)

	FarmDataManager.current_money += turn_profit

	# Auto-Rest / Metabolism Bypass
	FarmDataManager.wake_up_workers()
	_sync_hud_status()

	# --- EXECUTE INVASIVE SPREADING ---
	for sp in spreading_spawns:
		var tx = sp["x"]
		var ty = sp["y"]
		var t_layer = sp["layer"]
		var t_cell = FarmDataManager.grid_data[tx][ty]

		# Plants can only colonise wild, overgrown, or cultivated earth
		if str(t_cell.get("land", "")) in ["wild", "overgrown", "cultivated"]:
			# The target vertical layer must be empty
			if not _cell_str_nonempty(t_cell, t_layer):
				# Final check: Sun-loving weeds will not spread into deep canopy shadow
				var target_shaded = _is_in_canopy_shadow(tx, ty)
				var sp_data = preload("res://data/data_plants.gd").get_plant_data(sp["p_id"])
				if not (target_shaded and sp_data.get("shade_tolerance", "Medium") == "Low"):
					t_cell[t_layer] = sp["p_id"]
					t_cell[t_layer + "_age"] = 0
					if sp_data.get("toxicity", "") == "Invasive weed":
						overnight_events.append({
							"type": "weed_spread",
							"pos": map_to_local(Vector2i(tx, ty)),
						})
					# Optional: Turn wild soil to overgrown if a weed takes it over
					if str(t_cell.get("land", "")) == "wild" and sp_data.get("toxicity", "") == "Invasive weed":
						t_cell["land"] = "overgrown"

	FarmDataManager.current_turn += 1
	if FarmDataManager.active_campaign_id == "desert" and FarmDataManager.current_turn == 15 and not _desert_net_unlock_announced:
		_desert_net_unlock_announced = true
		spawn_floating_text("Moisture Nets Invented!", Color("81d4fa"), home_pos, "warnings")
		if is_instance_valid(hud_instance) and hud_instance.has_method("refresh_build_menu"):
			hud_instance.refresh_build_menu()
	turn_stepped.emit(FarmDataManager.current_turn, FarmDataManager.get_energy(), FarmDataManager.current_money)

	# --- VISUALISE ECONOMY BASED ON ZOOM LEVEL ---
	if daily_profits.size() > 0:
		var cam = get_viewport().get_camera_2d()
		# Zoom ranges from 0.02 (far) to 1.5 (close). Midpoint threshold is roughly 0.5
		var current_zoom = cam.zoom.x if cam else 1.0

		if current_zoom >= 0.5:
			# Top half of zoom: Show granular text data
			for p in daily_profits:
				spawn_floating_text("+£" + str(p["amount"]), Color("ffd54f"), p["pos"], "actions")
		else:
			# Bottom half of zoom: Group text and glow tiles to prevent static
			var profit_chunks: Dictionary = {}

			for p in daily_profits:
				var pos: Vector2i = p["pos"]

				# 1. Spawn a glowing yellow square directly on the cell
				var glow = ColorRect.new()
				glow.color = Color(1.0, 0.84, 0.0, 0.4) # Bright yellow, semi-transparent
				glow.size = Vector2(200, 200)
				glow.position = map_to_local(pos) - Vector2(100, 100) # Center over tile
				glow.z_index = 50
				add_child(glow)

				var tween = create_tween()
				tween.tween_property(glow, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN)
				tween.chain().tween_callback(func(): glow.queue_free())

				# 2. Group the text into 8x8 radius chunks
				var chunk = Vector2i(int(pos.x / 8.0), int(pos.y / 8.0))
				profit_chunks[chunk] = profit_chunks.get(chunk, 0) + p["amount"]

			# 3. Spawn a single bold £ symbol at the center of each profitable chunk
			for chunk in profit_chunks.keys():
				var center_pos = Vector2i(chunk.x * 8 + 4, chunk.y * 8 + 4)
				spawn_floating_text("£", Color("ffd54f"), center_pos, "actions")

	# --- DUCK PATROL ECOLOGY (Diluted by Area) ---
	var duck_houses = 0
	var patrol_tiles: Array[Vector2i] = []

	# 1. Gather all duck infrastructure
	for x in range(_map_w()):
		for y in range(_map_h()):
			var cell = FarmDataManager.grid_data[x][y]
			if str(cell.get("structure", "")) == "duck_house":
				duck_houses += 1
			if str(cell.get("zone", "")) in ["duck_patrol", "pen"]:
				patrol_tiles.append(Vector2i(x, y))

	# 2. Distribute finite benefits across the area
	if duck_houses > 0 and patrol_tiles.size() > 0:
		# Each house provides a flat pool of 15.0 N and 40 slug grazes per day
		var total_n_pool = duck_houses * 1.0
		var n_per_tile = total_n_pool / float(patrol_tiles.size())

		# Calculate probability of ducks grazing slugs on any given tile
		var slug_eat_chance = (duck_houses * 40.0) / float(patrol_tiles.size())

		for pos in patrol_tiles:
			var cell = FarmDataManager.grid_data[pos.x][pos.y]

			# Apply diluted Nitrogen
			cell["nitrogen"] = clampf(float(cell.get("nitrogen", 5.0)) + n_per_tile, 0.0, 10.0)
			cell["macro_life"] = clampf(float(cell.get("macro_life", 2.0)) + 0.02, 0.0, 10.0)

			# Apply diluted Slug clearing
			if cell.get("has_slugs", false):
				if randf() < slug_eat_chance:
					cell["has_slugs"] = false

					# 5% chance to pop the visual so the player knows ducks are working,
					# but without lagging the engine with 40 text nodes.
					if randf() < 0.05:
						spawn_floating_text("- Slugs", Color("69f0ae"), pos, "ecology")

	# --- PIG ECOLOGY (The Rototiller) ---
	for x in range(_map_w()):
		for y in range(_map_h()):
			if str(FarmDataManager.grid_data[x][y].get("structure", "")) == "pig_house":
				# Pigs aggressively root and till in a 3-tile radius
				for dy in range(-3, 4):
					for dx in range(-3, 4):
						if dx * dx + dy * dy <= 10: # Circular radius
							var nx = x + dx
							var ny = y + dy
							if nx >= 0 and nx < _map_w() and ny >= 0 and ny < _map_w():
								var p_cell = FarmDataManager.grid_data[nx][ny]
								if str(p_cell.get("structure", "")) != "pig_house" and not p_cell.get("is_river", false):
									# 1. Rototill the land and fertilize
									p_cell["land"] = "cultivated"
									p_cell["nitrogen"] = clampf(float(p_cell.get("nitrogen", 5.0)) + 0.08, 0.0, 10.0)
									p_cell["macro_life"] = clampf(float(p_cell.get("macro_life", 2.0)) + 0.04, 0.0, 10.0)
									p_cell["has_slugs"] = false

									# 2. Utterly destroy any ground/understory plants (weeds and crops!)
									var destroyed = false
									for l in ["ground", "understory"]:
										if _cell_str_nonempty(p_cell, l):
											p_cell[l] = ""
											p_cell.erase(l + "_age")
											destroyed = true

									if destroyed and randf() < 0.15:
										spawn_floating_text("Oink! (Clearing)", Color("f48fb1"), Vector2i(nx, ny), "ecology")

	# --- HIMALAYAN BALSAM ECOLOGY (The Virus) ---
	var new_balsam: Array[Vector2i] = []
	for x in range(_map_w()):
		if x % 16 == 0:
			await get_tree().process_frame
		for y in range(_map_h()):
			var cell = FarmDataManager.grid_data[x][y]
			if str(cell.get("ground", "")) == "himalayan_balsam":
				# 25% chance to explode and spread every single night
				if randf() < 0.25:
					# Find a random adjacent tile
					var dirs: Array[Vector2i] = [
						Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
						Vector2i(1, 1), Vector2i(-1, -1)
					]
					dirs.shuffle()

					for d in dirs:
						var nx = x + d.x
						var ny = y + d.y
						if nx >= 0 and nx < _map_w() and ny >= 0 and ny < _map_w():
							var n_cell = FarmDataManager.grid_data[nx][ny]
							var is_water = n_cell.get("is_river", false) or str(n_cell.get("land", "")) in ["river", "stream", "swale"]

							# Target empty ground layer and no building fixture (soil `structure` float is fine — overload header).
							if not _cell_str_nonempty(n_cell, "ground") and not _cell_has_building_structure(n_cell) and not is_water:
								# It thrives in wet soil (80% spread chance) but struggles in dry clay (10%)
								var spread_chance = 0.8 if float(n_cell.get("moisture", 5.0)) > 5.0 else 0.10

								# Polytunnels completely block the spread
								if str(n_cell.get("zone", "")) == "polytunnel":
									spread_chance = 0.0

								if randf() < spread_chance:
									new_balsam.append(Vector2i(nx, ny))
									break # Only launch one successful seed per plant per night

	# Apply the new growth and trigger the Synesthesia visuals
	for pos in new_balsam:
		FarmDataManager.grid_data[pos.x][pos.y]["ground"] = "himalayan_balsam"
		FarmDataManager.grid_data[pos.x][pos.y]["ground_age"] = 0
		overnight_events.append({
			"type": "weed_spread",
			"pos": map_to_local(pos),
		})
		# 20% chance to pop the visual so we don't crash the engine with 500 particles
		if randf() < 0.20:
			spawn_floating_text("POP!", Color("e040fb"), pos, "warnings")
			_play_balsam_pop()

	# --- STRUGGLING PLANT INDICATORS (MORNING TRIAGE) ---
	var warning_count = 0
	# Only scan the player's actual farm boundaries
	for x in range(FarmDataManager.player_bounds_left + 1, FarmDataManager.player_bounds_right):
		if x % 16 == 0:
			await get_tree().process_frame
		for y in range(_map_h()):
			var cell = FarmDataManager.grid_data[x][y]
			for layer in ["canopy", "understory", "ground"]:
				if _cell_str_nonempty(cell, layer):
					var p_id = cell[layer]
					var p_data = preload("res://data/data_plants.gd").get_plant_data(p_id)
					var msg = ""
					var col = Color.WHITE

					if float(cell.get("moisture", 5.0)) < 2.0:
						msg = "Thirsty!"
						col = Color("ffb74d") # Warning Orange
					elif float(cell.get("nitrogen", 5.0)) < 1.0:
						msg = "Hungry!"
						col = Color("ba68c8") # Nutrient Purple
					elif _is_in_canopy_shadow(x, y) and str(p_data.get("shade_tolerance", "Medium")) == "Low":
						msg = "Needs Sun!"
						col = Color("9e9e9e") # Shaded Grey

					if msg != "":
						# Cap the maximum amount of warnings to avoid screen spam
						if randf() < 0.4 and warning_count < 12:
							# Use a random timer delay so they pop up organically like popcorn
							get_tree().create_timer(randf() * 1.5, false).timeout.connect(func():
								spawn_floating_text(msg, col, Vector2i(x, y), "warnings")
							)
							warning_count += 1

	_generate_daily_narrative()

	# --- LIVE UI REFRESH ---
	if is_instance_valid(hud_instance):
		_refresh_live_right_panel()

	# --- GENERATION 1: DAY 16 FAILURE (after Day 15 frost tutorial + forced frost night) ---
	if (
		FarmDataManager.active_campaign_id == "wormfood"
		and not MetaManager.dev_mode
		and is_instance_valid(narrative_ui)
		and FarmDataManager.current_turn == 16
		and not _gen1_day16_failure_shown
	):
		_gen1_day16_failure_shown = true
		_hide_hover_for_narrative()
		var story = NarrativeData.get_dialogue("day_15_failure")
		if not story.is_empty():
			narrative_ui.show_dialogue(story["title"], story["body"], story["options"])

	if is_instance_valid(main_camera) and main_camera.has_method("play_event_queue") and not overnight_events.is_empty():
		main_camera.play_event_queue(overnight_events)


func _generate_daily_narrative() -> void:
	var boxes_owned = 0
	for x in range(_map_w()):
		for y in range(_map_h()):
			if str(FarmDataManager.grid_data[x][y].get("structure", "")) == "honesty_box":
				boxes_owned += 1

	# 1. Honesty Box Income
	if boxes_owned > 0:
		# Base profit + bonus if they have the Hypnotic Charm upgrade
		var daily_profit = (randi() % 8 + 3) * boxes_owned
		if MetaManager.has_upgrade("hypnotic_charm"):
			daily_profit += int(daily_profit * 0.2) + 2
		FarmDataManager.current_money += daily_profit

		var msg = "[color=#a5d6a7]Day %d: Someone left £%d in the Honesty Box for your surplus produce.[/color]" % [FarmDataManager.current_turn, daily_profit]
		inbox_messages.push_front(msg)
		unread_mail = true
		spawn_floating_text("+£" + str(daily_profit), Color("a5d6a7"), home_pos, "ecology")

	# 2. Fixed Story Beats (Pulled from data)
	var story_msg = NarrativeData.get_lore(FarmDataManager.current_turn)

	if FarmDataManager.active_campaign_id == "tutorial":
		match FarmDataManager.current_turn:
			1:
				_trigger_tutorial_beat("tut_day_1")
			2:
				_trigger_tutorial_beat("tut_day_2", true)
			4:
				_trigger_tutorial_beat("tut_day_4")
			6:
				_trigger_tutorial_beat("tut_day_6")
			8:
				_trigger_tutorial_beat("tut_day_8")
			10:
				_trigger_tutorial_beat("tut_day_10")
		story_msg = ""
	elif FarmDataManager.active_campaign_id == "wormfood" and FarmDataManager.current_turn in [3, 6, 8, 9, 12, 15]:
		if is_instance_valid(narrative_ui):
			_hide_hover_for_narrative()
			var story = NarrativeData.get_dialogue("tut_day_" + str(FarmDataManager.current_turn))
			if not story.is_empty():
				narrative_ui.show_dialogue(story["title"], story["body"], story["options"])
			story_msg = ""

	# Handle specific mechanical triggers tied to story days (wormfood only)
	if FarmDataManager.active_campaign_id == "wormfood" and FarmDataManager.current_turn == 5:
		if is_instance_valid(narrative_ui):
			_hide_hover_for_narrative()
			var story = NarrativeData.get_dialogue("day_5_workers")
			if not story.is_empty():
				narrative_ui.show_dialogue(story["title"], story["body"], story["options"])
			story_msg = "" # Prevent it from also going to the inbox
	elif FarmDataManager.active_campaign_id == "wormfood" and FarmDataManager.current_turn == 8:
		# Spawn Patient Zero along the river
		for x in range(_map_w()):
			for y in range(_map_h()):
				var cell = FarmDataManager.grid_data[x][y]
				if cell.get("is_river", false) or str(cell.get("land", "")) == "river":
					if randf() < 0.05: # 5% of river tiles get infected
						# Check adjacent tiles and infect an empty ground slot
						var nx = clampi(x + (randi() % 3 - 1), 0, _map_w() - 1)
						var ny = clampi(y + (randi() % 3 - 1), 0, _map_w() - 1)
						if not _cell_str_nonempty(FarmDataManager.grid_data[nx][ny], "ground"):
							var target = FarmDataManager.grid_data[nx][ny]
							var is_water = target.get("is_river", false) or str(target.get("land", "")) in ["river", "stream", "swale"]
							if not is_water:
								target["ground"] = "himalayan_balsam"
								target["ground_age"] = 0
								_play_balsam_pop()
								spawn_floating_text("POP!", Color("e040fb"), Vector2i(nx, ny), "warnings")

	# Day-14 lore references the Honesty Box; skip inbox if none built yet
	if FarmDataManager.current_turn == 14 and boxes_owned <= 0:
		story_msg = ""

	if story_msg != "":
		inbox_messages.push_front("[color=#e0e0e0]Day %d: %s[/color]" % [FarmDataManager.current_turn, story_msg])
		unread_mail = true


func process_produce_action(action: String, item_key: String) -> void:
	if FarmDataManager.get_inventory_count(item_key) <= 0:
		return
	if not FarmDataManager.remove_from_inventory(item_key, 1):
		return

		var e_yield := 3
		var m_yield := 2
		if item_key != "wild_greens":
			var db: Dictionary = preload("res://data/data_plants.gd").get_plant_data(item_key)
			e_yield = int(db.get("energy_yield", 5))
			m_yield = int(db.get("yield_val", 5))

		if action == "eat":
			FarmDataManager.refund_energy(e_yield)
			_sync_hud_status()
		elif action == "sell":
			var charm_mult = 1.2 if MetaManager.has_upgrade("hypnotic_charm") else 1.0
			FarmDataManager.current_money += int(round(m_yield * charm_mult))

		_refresh_all_visuals()
		if hud_instance and hud_instance.has_method("refresh_produce_ui"):
			hud_instance.refresh_produce_ui(FarmDataManager.inventory)


func _tool_energy_cost(action: String) -> int:
	match action:
		"rotovate":
			return 2
		"scythe":
			return 1
		"harvest":
			return 2
		"chop_and_drop":
			return 1
		"uproot":
			return 1 if MetaManager.has_upgrade("thick_gloves") else 2
		"dig_swale":
			return 5
		"build_mound":
			return 5
		"plant":
			return 1
		"water_tile":
			return 0 if FarmDataManager.creative_infinite_water else 1
		"e_tiller", "hosepipe":
			return 0
		"apply_tea":
			return 1
		"build":
			return _build_structure_queue_costs(active_structure).x
		_:
			return 1


func _get_planning_e_m_costs(cell_pos: Vector2i) -> Vector2i:
	var e_cost := 0
	var m_cost := 0
	var cx := cell_pos.x
	var cy := cell_pos.y
	match active_tool:
		"rotovate":
			if cx >= 0 and cx < _map_w() and cy >= 0 and cy < _map_w() \
				and FarmDataManager.grid_data[cx][cy].get("has_path", false) and FarmDataManager.grid_data[cx][cy]["land"] == "cultivated":
				e_cost = 1
			else:
				e_cost = 2
		"e_tiller":
			e_cost = 0
		"hosepipe":
			e_cost = 0
		"scythe":
			e_cost = 1
		"harvest":
			e_cost = 2
		"chop_and_drop":
			e_cost = 1
		"uproot":
			e_cost = 1 if MetaManager.has_upgrade("thick_gloves") else 2
		"dig_swale":
			e_cost = 5
		"build_mound":
			e_cost = 5
			m_cost = 2
		"plant":
			e_cost = 1
			if not preload("res://data/data_plants.gd").get_plant_data(active_seed).is_empty():
				m_cost = str(preload("res://data/data_plants.gd").get_plant_data(active_seed).get("cost", "0")).to_int()
		"build":
			var bqc_plan := _build_structure_queue_costs(active_structure)
			e_cost = bqc_plan.x
			m_cost = bqc_plan.y
			if active_structure not in ["bridge", "duck_house", "polytunnel", "honesty_box", "pig_house", "compost_brewer", "beehive", "sprinkler", "drone_hub", "moisture_net", "smart_shade", "drone_pollinator", "solar_panel", "battery", "water_butt"] \
				and preload("res://data/data_objects.gd").ENTRIES.has(active_structure):
				m_cost = int(preload("res://data/data_objects.gd").ENTRIES[active_structure].get("cost", 0))
		"additive":
			e_cost = 1
		"demolish":
			e_cost = 1
		"build_path":
			e_cost = 0
			m_cost = 1
		"water_tile":
			e_cost = 0 if FarmDataManager.creative_infinite_water else 1
			m_cost = 0
		"e_tiller", "hosepipe":
			e_cost = 0
			m_cost = 0
		"apply_tea":
			e_cost = 1
			m_cost = 0
		_:
			e_cost = _tool_energy_cost(active_tool)
	return Vector2i(e_cost, m_cost)


## Shared planning-hover preview: energy bar, tooltips, and route costs.
func _planning_hover_state(grid_pos: Vector2i) -> Dictionary:
	var out := {"kind": "none"}
	if is_sleeping or active_tool == "":
		return out

	var x := grid_pos.x
	var y := grid_pos.y
	if x <= FarmDataManager.player_bounds_left or x >= FarmDataManager.player_bounds_right:
		return out
	if x < 0 or x >= _map_w() or y < 0 or y >= _map_h():
		return out

	var current_land: String = FarmDataManager.grid_data[x][y]["land"]
	if current_land in ["river", "stream", "bridge", "house", "house_door"]:
		var allow_on_land := active_tool == "build" and active_structure == "bridge" and current_land == "stream"
		var allow_demolish_bridge := active_tool == "demolish" and current_land == "bridge"
		var allow_water_shallow := active_tool in ["water_tile", "hosepipe"] and current_land in ["stream", "bridge"]
		if not allow_on_land and not allow_demolish_bridge and not allow_water_shallow:
			return out

	var existing_action_idx := -1
	for i in range(FarmDataManager.action_queue.size()):
		if FarmDataManager.action_queue[i]["pos"] != Vector2i(x, y):
			continue
		var q_action: Dictionary = FarmDataManager.action_queue[i]
		if active_tool == "plant" and active_seed != "" and q_action["action"] == "plant":
			var new_layer := str(preload("res://data/data_plants.gd").get_plant_data(active_seed).get("layer", "ground")).to_lower()
			var old_layer := str(preload("res://data/data_plants.gd").get_plant_data(q_action["seed_id"]).get("layer", "ground")).to_lower()
			if new_layer == old_layer:
				existing_action_idx = i
				break
		elif active_tool == "additive" or q_action.get("action", "") == "additive" \
			or (active_tool == "build" and active_structure in ["polytunnel", "pig_house", "compost_brewer"]) \
			or (q_action.get("action", "") == "build" and str(q_action.get("structure", "")) in ["polytunnel", "pig_house", "compost_brewer"]) \
			or active_tool == "demolish" or q_action.get("action", "") == "demolish":
			continue
		else:
			existing_action_idx = i
			break

	if existing_action_idx >= 0:
		var removed: Dictionary = FarmDataManager.action_queue[existing_action_idx]
		var refund := int(removed.get("energy_cost", 0))
		return {"kind": "refund", "refund": refund}

	var costs := _get_planning_e_m_costs(grid_pos)
	var e_cost: int = costs.x
	var m_cost: int = costs.y

	if active_tool == "plant" and active_seed == "":
		return out

	if active_tool == "e_tiller" and FarmDataManager.current_power < 1:
		return out
	if active_tool == "hosepipe" and FarmDataManager.current_water < 1:
		return out

	if FarmDataManager.get_energy() < e_cost or FarmDataManager.current_money < m_cost:
		return out

	var can_queue := true
	if _cell_has_npc(FarmDataManager.grid_data[x][y]):
		can_queue = false
	if active_tool == "rotovate" or active_tool == "e_tiller":
		if FarmDataManager.grid_data[x][y]["land"] in ["road", "bridge"]:
			can_queue = false
		elif FarmDataManager.grid_data[x][y].get("has_path", false) and FarmDataManager.grid_data[x][y]["land"] == "cultivated":
			can_queue = true
		elif FarmDataManager.grid_data[x][y]["land"] != "wild" and FarmDataManager.grid_data[x][y]["land"] != "overgrown":
			can_queue = false
	elif active_tool == "scythe":
		if FarmDataManager.grid_data[x][y]["land"] != "overgrown":
			can_queue = false
	elif active_tool == "harvest":
		var h_cell: Dictionary = FarmDataManager.grid_data[x][y]
		if str(h_cell.get("land", "")) not in ["cultivated", "overgrown"]:
			can_queue = false
		elif _mature_plant_on_cell(h_cell).is_empty():
			can_queue = false
	elif active_tool == "chop_and_drop":
		if _top_plant_on_cell(FarmDataManager.grid_data[x][y]).is_empty():
			can_queue = false
	elif active_tool == "uproot":
		if FarmDataManager.grid_data[x][y]["land"] == "wild":
			can_queue = false
	elif active_tool == "plant":
		# Mirror `_attempt_grid_action` plant rules; soil `structure` float must not invalidate hover (overload header).
		var planned := _get_planned_cell_state(grid_pos, FarmDataManager.grid_data[x][y])
		if planned.get("has_path", false):
			can_queue = false
		elif str(planned.get("land", "")) != "cultivated":
			can_queue = false
		elif _cell_has_building_structure(FarmDataManager.grid_data[x][y]):
			can_queue = false
		else:
			var p_layer := str(preload("res://data/data_plants.gd").get_plant_data(active_seed).get("layer", "ground")).to_lower()
			if _cell_str_nonempty(FarmDataManager.grid_data[x][y], p_layer):
				can_queue = false
	elif active_tool == "build":
		match active_structure:
			"bridge":
				can_queue = (str(FarmDataManager.grid_data[x][y].get("type", FarmDataManager.grid_data[x][y].get("land", ""))) == "stream")
			"duck_house":
				# Placement preview: block only real fixtures, not V3 soil `structure` (overload header).
				if _cell_has_building_structure(FarmDataManager.grid_data[x][y]):
					can_queue = false
			"polytunnel":
				if FarmDataManager.grid_data[x][y].get("land", "") != "cultivated":
					can_queue = false
				elif FarmDataManager.grid_data[x][y].get("zone", "") == "polytunnel":
					can_queue = false
			"honesty_box", "pig_house", "compost_brewer", "beehive", "sprinkler", "drone_hub", "moisture_net", "smart_shade", "drone_pollinator", "solar_panel", "battery", "water_butt":
				if _cell_has_building_structure(FarmDataManager.grid_data[x][y]):
					can_queue = false # fixture overlap only; soil metric ignored (overload header)
			_:
				var gc_plan: Dictionary = FarmDataManager.grid_data[x][y]
				if _cell_str_nonempty(gc_plan, "canopy") or _cell_str_nonempty(gc_plan, "understory") or _cell_str_nonempty(gc_plan, "ground"):
					can_queue = false
	elif active_tool == "additive":
		if active_seed == "" or not additives_data.has(active_seed):
			can_queue = false
	elif active_tool == "demolish":
		if current_land in ["house", "house_door"]:
			can_queue = false
		elif not _cell_has_demolishable_content(Vector2i(x, y)):
			can_queue = false
	elif active_tool == "build_path":
		can_queue = _cell_can_build_path(FarmDataManager.grid_data[x][y])
	elif active_tool == "water_tile" or active_tool == "hosepipe":
		if FarmDataManager.grid_data[x][y]["land"] in ["road", "house", "house_door", "river"]:
			can_queue = false
	elif active_tool == "apply_tea":
		if FarmDataManager.grid_data[x][y]["land"] in ["road", "bridge", "house", "house_door", "river", "stream"]:
			can_queue = false

	if not can_queue:
		return out

	var route := _get_route_to_new_action(grid_pos)
	var move_e := int(ceil(route["move_cost"]))
	var total_e: int = e_cost + move_e
	var path_ok: bool = not route["path"].is_empty()
	return {
		"kind": "preview",
		"e_cost": e_cost,
		"m_cost": m_cost,
		"move_cost": route["move_cost"],
		"move_e": move_e,
		"total_e": total_e,
		"path_ok": path_ok,
	}


func _is_in_canopy_shadow(target_x: int, target_y: int) -> bool:
	# Check a 3x3 grid around the tile. If any tile has a canopy plant, this tile is shaded.
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var nx = clampi(target_x + dx, 0, _map_w() - 1)
			var ny = clampi(target_y + dy, 0, _map_w() - 1)
			if _cell_str_nonempty(FarmDataManager.grid_data[nx][ny], "canopy"):
				return true
	return false


func _setup_floating_text_pool() -> void:
	_floating_text_pool.clear()
	for i in FLOATING_TEXT_POOL_SIZE:
		var root := Node2D.new()
		root.name = "FloatingTextPool_%d" % i
		root.visible = false
		root.z_index = 100
		var burst := CPUParticles2D.new()
		burst.emitting = false
		burst.one_shot = true
		burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		burst.spread = 180.0
		burst.gravity = Vector2(0, -50)
		burst.z_index = 90
		var lbl := Label.new()
		lbl.visible = false
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		lbl.add_theme_constant_override("outline_size", 16)
		lbl.add_theme_font_size_override("font_size", 120)
		lbl.z_index = 100
		root.add_child(burst)
		root.add_child(lbl)
		add_child(root)
		_floating_text_pool.append({
			"root": root,
			"label": lbl,
			"burst": burst,
			"busy": false,
			"tween": null,
		})


func _acquire_floating_text_bundle() -> Dictionary:
	for b in _floating_text_pool:
		if not b.busy:
			b.busy = true
			return b
	var b: Dictionary = _floating_text_pool[_floating_text_pool_rr]
	_floating_text_pool_rr = (_floating_text_pool_rr + 1) % FLOATING_TEXT_POOL_SIZE
	if b.has("tween") and is_instance_valid(b.tween):
		b.tween.kill()
		b.tween = null
	_floating_text_bundle_reset_visuals(b)
	b.busy = true
	return b


func _floating_text_bundle_reset_visuals(b: Dictionary) -> void:
	var lbl: Label = b.label
	var burst: CPUParticles2D = b.burst
	var root: Node2D = b.root
	lbl.visible = false
	root.visible = false
	burst.emitting = false
	lbl.modulate = Color.WHITE


func _recycle_floating_text_bundle(bundle: Dictionary) -> void:
	bundle.tween = null
	_floating_text_bundle_reset_visuals(bundle)
	bundle.busy = false


func spawn_floating_text(msg: String, col: Color, cell_pos: Vector2i, category: String) -> void:
	if hud_instance:
		var indicator_settings = hud_instance.get("indicator_settings")
		if indicator_settings is Dictionary and not indicator_settings.get(category, true):
			return

	var bundle := _acquire_floating_text_bundle()
	var lbl: Label = bundle.label
	var burst: CPUParticles2D = bundle.burst
	var root: Node2D = bundle.root

	lbl.text = msg
	lbl.add_theme_color_override("font_color", col)

	var cam = get_viewport().get_camera_2d()
	var current_zoom = cam.zoom.x if cam else 1.0

	lbl.scale = (Vector2.ONE * 0.25) / current_zoom
	lbl.position = -Vector2(20, 20)
	root.position = map_to_local(cell_pos)

	burst.amount = 16 if category == "warnings" else 12
	burst.lifetime = 0.8 if category == "warnings" else 0.6
	burst.explosiveness = 0.95 if category == "warnings" else 0.9
	burst.emission_sphere_radius = 25.0 if category == "warnings" else 20.0
	burst.initial_velocity_min = 80.0 if category == "warnings" else 50.0
	burst.initial_velocity_max = 200.0 if category == "warnings" else 150.0
	burst.scale_amount_min = 6.0 if category == "warnings" else 4.0
	burst.scale_amount_max = 12.0 if category == "warnings" else 8.0
	burst.color = col * 2.5
	burst.position = Vector2.ZERO

	burst.emitting = true

	lbl.visible = true
	root.visible = true

	var tween := create_tween()
	bundle.tween = tween
	tween.set_parallel(true)
	var target_pos = lbl.position + Vector2(randf_range(-30, 30), -150 / current_zoom)
	tween.tween_property(lbl, "position", target_pos, 2.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(lbl, "modulate:a", 0.0, 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	tween.chain().tween_callback(func(): _recycle_floating_text_bundle(bundle))


func _get_soil_description(cell: Dictionary) -> String:
	var land = cell.get("land", "wild")
	var is_water = cell.get("is_river", false) or land in ["river", "stream", "swale"]
	var m = float(cell.get("moisture", 5.0))

	if is_water:
		if cell.get("is_river", false) or land == "river":
			return "[color=#4fc3f7]Flowing River[/color]"
		else:
			return "[color=#4fc3f7]Surface Water[/color]"
	elif m >= 9.0:
		return "[color=#4fc3f7]Waterlogged Soil[/color]"
	if land in ["road", "bridge", "house"]:
		return "[color=#9e9e9e]Compacted / Dead[/color]"

	var tags = cell.get("soil_tags", ["clay"])
	var base_soil = "[color=#795548]Heavy Clay[/color]"

	if "loam" in tags:
		base_soil = "[color=#8d6e63]Rich Loam[/color]"
	elif "sandy" in tags:
		base_soil = "[color=#ffb74d]Sandy[/color]"

	var modifiers = []
	if "well aerated" in tags:
		modifiers.append("Aerated")
	if "full o worms" in tags:
		modifiers.append("Living")
	if "mycorrhizally interconnected" in tags:
		modifiers.append("Mycorrhizal")

	if modifiers.size() > 0:
		return base_soil + " [color=#aed581](" + ", ".join(PackedStringArray(modifiers)) + ")[/color]"

	return base_soil


func _refresh_queue_ui() -> void:
	if hud_instance and hud_instance.has_method("update_action_queue_ui"):
		hud_instance.update_action_queue_ui(FarmDataManager.action_queue)


func play_synesthesia_chime(act_type: String = "", is_echo: bool = false, forced_pitch: float = 0.0) -> float:
	var pitch = forced_pitch

	if pitch == 0.0:
		var scale_offsets = seasonal_scales.get(FarmDataManager.current_season, seasonal_scales["Spring"])

		# Cycle sequentially through the pentatonic scale
		chime_index = (chime_index + 1) % 5

		# Octave dictated by function, not position
		var octave_shift = 0
		match act_type:
			"rotovate", "build_path", "build", "dig_swale", "build_mound", "demolish", "scythe", "uproot":
				octave_shift = -1
			"plant", "additive", "pop", "water_tile", "apply_tea", "harvest", "chop_and_drop":
				octave_shift = 1

		var base_semitone = scale_offsets[chime_index]
		var final_semitone = base_semitone + (octave_shift * 12)
		pitch = pow(2.0, final_semitone / 12.0)

	for p in audio_pool:
		if not p.playing:
			p.pitch_scale = pitch
			if is_echo:
				p.bus = "Echo"
				p.volume_db = -8.0 + randf_range(-2.0, 2.0)
			else:
				p.bus = "Master"
				p.volume_db = -5.0 + randf_range(-2.0, 2.0)
			p.play()
			break

	return pitch


func _play_balsam_pop() -> void:
	# Prefer project pop; fallback if missing (drop-in pop.wav under environment/ anytime).
	var pop_paths: Array[String] = [
		"res://assets/base/audio/sfx/environment/pop.wav",
		"res://assets/base/audio/sfx/chimes/chimehit.wav",
	]
	var pop_stream: AudioStream
	for path in pop_paths:
		var s = load(path) as AudioStream
		if s:
			pop_stream = s
			break
	if not pop_stream:
		push_warning("Balsam pop: add res://assets/base/audio/sfx/environment/pop.wav (or fix audio import paths).")
		return

	var p = AudioStreamPlayer.new()
	p.stream = pop_stream
	p.bus = "SFX"
	p.volume_db = 2.0 # Slightly louder to ensure it punches through
	p.pitch_scale = randf_range(0.85, 1.15)
	p.process_mode = Node.PROCESS_MODE_ALWAYS # 2. CRITICAL: Play even if the scene tree is paused!

	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func set_current_tool(t_name: String, t_seed: String = "", t_struct: String = "") -> void:
	active_tool = t_name
	active_seed = t_seed
	active_structure = t_struct

	var display_name = t_name
	if t_name == "plant" and t_seed != "":
		display_name = "Seed: " + t_seed
	elif t_name == "demolish":
		display_name = "Demolish"
	elif t_name == "build_path":
		display_name = "Build Path (£1)"
	elif t_name == "build" and t_struct != "":
		match t_struct:
			"bridge":
				display_name = "Footbridge (Blueprint)"
			"duck_house":
				display_name = "Blueprint: Duck House"
			"polytunnel":
				display_name = "Polytunnel (£15)"
			"honesty_box":
				display_name = "Honesty Box (£25)"
			"pig_house":
				display_name = "Pig House (£80)"
			"compost_brewer":
				display_name = "Compost Brewer (£40)"
			_:
				display_name = "Blueprint: " + t_struct.capitalize().replace("_", " ")
	elif t_name == "additive" and t_seed != "" and additives_data.has(t_seed):
		display_name = str(additives_data[t_seed].get("name", t_seed))
	elif t_name == "water_tile":
		display_name = "Watering Can"
	elif t_name == "apply_tea":
		display_name = "Compost Tea"
	elif t_name == "rotovate":
		display_name = "Rotovator"
	elif t_name == "harvest":
		display_name = "Harvest"
	elif t_name == "chop_and_drop":
		display_name = "Chop & Drop"

	if hud_instance and hud_instance.has_method("update_active_tool_display"):
		hud_instance.update_active_tool_display(display_name)

	if hud_instance and hud_instance.has_method("sync_build_menu_from_tool"):
		hud_instance.sync_build_menu_from_tool(t_name, t_struct)

	if hud_instance and hud_instance.inspector_panel:
		hud_instance.inspector_panel.hide()


func _get_bridge_footprint(center_cell: Vector2i) -> Array[Vector2i]:
	var footprint: Array[Vector2i] = []
	var is_vertical := false

	if center_cell.x < 0 or center_cell.x >= _map_w() or center_cell.y < 0 or center_cell.y >= _map_h():
		return footprint

	var cell_data: Dictionary = FarmDataManager.grid_data[center_cell.x][center_cell.y]
	# Auto-snap: stream flow — if water is to the left or right, bridge spans perpendicular (vertical deck).
	if str(cell_data.get("type", cell_data.get("land", ""))) == "stream":
		var left_stream := false
		var right_stream := false
		if center_cell.x > 0:
			var lc: Dictionary = FarmDataManager.grid_data[center_cell.x - 1][center_cell.y]
			left_stream = str(lc.get("type", lc.get("land", ""))) == "stream"
		if center_cell.x < _map_w() - 1:
			var rc: Dictionary = FarmDataManager.grid_data[center_cell.x + 1][center_cell.y]
			right_stream = str(rc.get("type", rc.get("land", ""))) == "stream"
		if left_stream or right_stream:
			is_vertical = true

	if is_vertical:
		footprint = [
			center_cell + Vector2i(0, -1),
			center_cell,
			center_cell + Vector2i(0, 1),
			center_cell + Vector2i(0, 2),
		]
	else:
		footprint = [
			center_cell + Vector2i(-1, 0),
			center_cell,
			center_cell + Vector2i(1, 0),
			center_cell + Vector2i(2, 0),
		]
	return footprint


func _get_duck_house_footprint(center_cell: Vector2i) -> Array[Vector2i]:
	var footprint: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := Vector2i(center_cell.x + dx, center_cell.y + dy)
			if c.x >= 0 and c.x < _map_w() and c.y >= 0 and c.y < _map_w():
				footprint.append(c)
	return footprint


func _build_structure_queue_costs(struct_id: String) -> Vector2i:
	match struct_id:
		"bridge":
			return Vector2i(0, 0)
		"duck_house", "polytunnel", "honesty_box", "pig_house", "compost_brewer", "beehive", "sprinkler", "drone_hub", "moisture_net", "smart_shade", "drone_pollinator", "solar_panel", "battery", "water_butt":
			return Vector2i(1, 0)
		_:
			return Vector2i(5, 0)


func _on_structure_overlay_draw(canvas: CanvasItem) -> void:
	for x in range(_map_w()):
		for y in range(_map_h()):
			var cd: Dictionary = FarmDataManager.grid_data[x][y]
			var st := str(cd.get("structure", ""))
			var zone := str(cd.get("zone", ""))
			var land_s := str(cd.get("land", ""))

			var center_px = map_to_local(Vector2i(x, y))
			var rect = Rect2(center_px - Vector2(100, 100), Vector2(200, 200))

			if _cell_str_nonempty(cd, "npc"):
				var npc_id := str(cd.get("npc", ""))
				var npc_col := Color(0.75, 0.22, 0.28, 0.82)
				if npc_id == "sylva_student":
					npc_col = Color(0.28, 0.58, 0.92, 0.82)
				elif npc_id == "trustee_hargreaves":
					npc_col = Color(0.55, 0.18, 0.55, 0.85)
				canvas.draw_circle(center_px, 44, npc_col)
				canvas.draw_rect(Rect2(center_px - Vector2(28, 52), Vector2(56, 72)), npc_col.darkened(0.15))

			# --- 0. DRAW WATER & TERRAIN ---
			# Parentheses required: `or` must not combine `(is_river or land)` with `== "river"` (float/string crash).
			var is_river_tile: bool = bool(cd.get("is_river", false)) or (land_s == "river")
			var is_swale_tile: bool = land_s == "swale"
			var moisture := float(cd.get("moisture", 5.0))

			if is_river_tile:
				# Deep, flowing river: Blue wash with horizontal cyan current lines
				canvas.draw_rect(rect, Color(0.12, 0.53, 0.90, 0.25))
				var rx := 62
				var ry := 23
				canvas.draw_line(Vector2(center_px.x - rx, center_px.y - ry), Vector2(center_px.x + rx, center_px.y - ry), Color(0.5, 0.85, 1.0, 0.4), 4)
				var rx2 := 46
				var ry2 := 31
				canvas.draw_line(Vector2(center_px.x - rx2, center_px.y + ry2), Vector2(center_px.x + rx2, center_px.y + ry2), Color(0.5, 0.85, 1.0, 0.4), 4)

			elif is_swale_tile or moisture >= 9.0:
				# Waterlogged mud / Swales: Dark, heavy wash with stagnant circular puddles
				canvas.draw_rect(rect, Color(0.24, 0.18, 0.15, 0.4))
				canvas.draw_circle(center_px - Vector2(31, 31), 18, Color(0.2, 0.4, 0.5, 0.4))
				canvas.draw_circle(center_px + Vector2(23, 15), 28, Color(0.2, 0.4, 0.5, 0.4))

			if st == "" and zone == "":
				continue

			# 1. Draw the Zones
			if zone == "duck_patrol":
				_draw_duck_patrol_overlay(canvas, center_px, rect)
			elif zone == "pen":
				# Subtle trampled dirt look for the pen interior
				canvas.draw_rect(rect, Color(0.5, 0.4, 0.3, 0.1))
			elif zone == "polytunnel":
				# A glassy, semi-transparent white/blue arch
				var poly_rect = rect.grow(-3)
				canvas.draw_rect(poly_rect, Color(0.85, 0.95, 1.0, 0.25)) # Frosty glass fill
				canvas.draw_rect(poly_rect, Color(0.7, 0.9, 1.0, 0.6), false, 4) # Thick plastic edge

				# Draw horizontal ribs to sell the "tunnel" look
				var rib := 39
				canvas.draw_line(Vector2(poly_rect.position.x, center_px.y - rib), Vector2(poly_rect.end.x, center_px.y - rib), Color(0.7, 0.9, 1.0, 0.4), 3)
				canvas.draw_line(Vector2(poly_rect.position.x, center_px.y + rib), Vector2(poly_rect.end.x, center_px.y + rib), Color(0.7, 0.9, 1.0, 0.4), 3)

			# 2. Draw the Structures
			if st == "duck_house":
				canvas.draw_rect(rect.grow(-31), Color("8d6e63"))
				var roof_points = PackedVector2Array([
					Vector2(center_px.x, center_px.y - 78),
					Vector2(center_px.x - 78, center_px.y - 15),
					Vector2(center_px.x + 78, center_px.y - 15)
				])
				canvas.draw_polygon(roof_points, PackedColorArray([Color("4e342e")]))
				canvas.draw_rect(Rect2(center_px.x - 15, center_px.y + 23, 31, 45), Color("3e2723"))
			elif st == "pig_house":
				# A muddy footprint
				canvas.draw_rect(rect.grow(-7), Color(0.3, 0.2, 0.15, 0.6))
				# A corrugated iron shelter with an angled roof
				var pig_roof = PackedVector2Array([
					Vector2(center_px.x - 62, center_px.y + 31),
					Vector2(center_px.x - 62, center_px.y - 46),
					Vector2(center_px.x + 62, center_px.y - 15),
					Vector2(center_px.x + 62, center_px.y + 31)
				])
				canvas.draw_polygon(pig_roof, PackedColorArray([Color("78909c")]))
				canvas.draw_rect(Rect2(center_px.x - 15, center_px.y + 7, 31, 23), Color("212121")) # Dark entrance
				# A wooden grazing trough
				canvas.draw_rect(Rect2(center_px.x - 46, center_px.y + 62, 93, 15), Color("5d4037"))
			elif st == "fence":
				canvas.draw_rect(rect.grow(-7), Color("ffcc80"), false, 6)
			elif st == "gate":
				canvas.draw_rect(rect.grow(-15), Color("8d6e63"), false, 12)
			elif st == "honesty_box":
				# A small wooden crate with a coin slot and a little roof
				var box_rect = Rect2(center_px - Vector2(50, 50), Vector2(100, 100))
				canvas.draw_rect(box_rect, Color("8d6e63"))
				canvas.draw_rect(Rect2(center_px.x - 54, center_px.y - 54, 109, 15), Color("4e342e")) # Roof
				canvas.draw_rect(Rect2(center_px.x - 23, center_px.y - 15, 46, 7), Color("212121")) # Coin slot
			elif st == "compost_brewer":
				canvas.draw_rect(rect.grow(-23), Color(0.35, 0.28, 0.2, 0.85))
				canvas.draw_rect(Rect2(center_px.x - 54, center_px.y - 46, 109, 23), Color(0.25, 0.45, 0.22, 0.75))
				canvas.draw_rect(Rect2(center_px.x - 15, center_px.y + 15, 31, 38), Color(0.15, 0.35, 0.18, 0.9))
			elif st == "beehive":
				var hive_rect := Rect2(center_px - Vector2(55, 55), Vector2(110, 110))
				canvas.draw_rect(hive_rect, Color(1.0, 0.85, 0.2, 0.92))
				canvas.draw_rect(hive_rect, Color(0.95, 0.7, 0.05, 0.85), false, 4)
				canvas.draw_rect(Rect2(center_px.x - 18, center_px.y - 38, 36, 22), Color(0.35, 0.22, 0.05, 0.9))
				var forage_rect := Rect2(center_px - Vector2(400, 400), Vector2(800, 800))
				canvas.draw_rect(forage_rect, Color(1.0, 0.92, 0.35, 0.06))
				canvas.draw_rect(forage_rect, Color(1.0, 0.88, 0.2, 0.28), false, 2)
			elif st == "sprinkler":
				canvas.draw_circle(center_px, 28, Color(0.2, 0.55, 1.0, 0.85))
				canvas.draw_circle(center_px, 62, Color(0.3, 0.7, 1.0, 0.2))
				for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var apx := map_to_local(Vector2i(x, y) + off)
					canvas.draw_circle(apx, 18, Color(0.35, 0.75, 1.0, 0.35))
			elif st == "drone_hub":
				var hub_rect := Rect2(center_px - Vector2(70, 70), Vector2(140, 140))
				canvas.draw_rect(hub_rect, Color(0.55, 0.58, 0.62, 0.9))
				canvas.draw_rect(hub_rect, Color(0.75, 0.8, 0.85, 0.6), false, 4)
				var scan_rect := Rect2(center_px - Vector2(200, 200), Vector2(400, 400))
				canvas.draw_rect(scan_rect, Color(0.4, 0.85, 1.0, 0.08))
				canvas.draw_rect(scan_rect, Color(0.5, 0.9, 1.0, 0.25), false, 2)
			elif st == "moisture_net":
				var net_rect := Rect2(center_px - Vector2(90, 90), Vector2(180, 180))
				canvas.draw_rect(net_rect, Color(0.55, 0.82, 1.0, 0.22))
				canvas.draw_rect(net_rect, Color(0.7, 0.9, 1.0, 0.55), false, 3)
				var mesh_step := 28
				for gx in range(-3, 4):
					var lx: float = center_px.x + float(gx * mesh_step)
					canvas.draw_line(Vector2(lx, net_rect.position.y), Vector2(lx, net_rect.end.y), Color(0.85, 0.95, 1.0, 0.35), 2)
				for gy in range(-3, 4):
					var ly: float = center_px.y + float(gy * mesh_step)
					canvas.draw_line(Vector2(net_rect.position.x, ly), Vector2(net_rect.end.x, ly), Color(0.85, 0.95, 1.0, 0.35), 2)
			elif st == "smart_shade":
				var shade_rect := Rect2(center_px - Vector2(125, 125), Vector2(250, 250))
				canvas.draw_rect(shade_rect, Color(1.0, 0.92, 0.23, 0.18))
				canvas.draw_rect(shade_rect, Color(1.0, 0.85, 0.1, 0.55), false, 4)
				var hex_step := 50.0
				for hx in range(-2, 3):
					for hy in range(-2, 3):
						var hxp: float = center_px.x + float(hx) * hex_step
						var hyp: float = center_px.y + float(hy) * hex_step * 0.86
						var hex_r := 22.0
						var pts: PackedVector2Array = PackedVector2Array()
						for seg in range(6):
							var ang := float(seg) * TAU / 6.0
							pts.append(Vector2(hxp + cos(ang) * hex_r, hyp + sin(ang) * hex_r))
						canvas.draw_colored_polygon(pts, Color(1.0, 0.95, 0.4, 0.12))
						canvas.draw_polyline(pts, Color(1.0, 0.9, 0.35, 0.45), true, 2.0)
			elif st == "drone_pollinator":
				var pulse := 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) * 0.008 + float(x + y))
				canvas.draw_circle(center_px, 22, Color(0.85, 0.45, 0.95, pulse))
				canvas.draw_circle(center_px, 10, Color(1.0, 0.75, 1.0, 0.9))
				var pol_rect := Rect2(center_px - Vector2(75, 75), Vector2(150, 150))
				canvas.draw_rect(pol_rect, Color(0.75, 0.35, 0.9, 0.1))
				canvas.draw_rect(pol_rect, Color(0.9, 0.5, 1.0, 0.35), false, 2)
			elif st == "solar_panel":
				var panel_rect := Rect2(center_px - Vector2(70, 46), Vector2(140, 92))
				canvas.draw_rect(panel_rect, Color(0.12, 0.14, 0.22, 0.92))
				canvas.draw_rect(panel_rect, Color(1.0, 0.92, 0.35, 0.75), false, 4)
				for row in range(3):
					var ly: float = panel_rect.position.y + 18.0 + float(row) * 22.0
					canvas.draw_line(
						Vector2(panel_rect.position.x + 12, ly),
						Vector2(panel_rect.end.x - 12, ly),
						Color(0.35, 0.55, 0.95, 0.55),
						2.0
					)
			elif st == "battery":
				var batt_rect := Rect2(center_px - Vector2(58, 70), Vector2(116, 140))
				canvas.draw_rect(batt_rect, Color(0.22, 0.28, 0.32, 0.92))
				canvas.draw_rect(batt_rect, Color(0.65, 0.85, 0.45, 0.7), false, 4)
				for tier in range(3):
					var ty: float = batt_rect.position.y + 24.0 + float(tier) * 36.0
					canvas.draw_rect(
						Rect2(batt_rect.position.x + 14, ty, batt_rect.size.x - 28, 22),
						Color(0.45, 0.72, 0.35, 0.55)
					)
			elif st == "water_butt":
				var butt_rect := Rect2(center_px - Vector2(40, 54), Vector2(80, 108))
				canvas.draw_rect(butt_rect, Color(0.35, 0.42, 0.5, 0.88))
				canvas.draw_rect(Rect2(center_px.x - 46, center_px.y - 62, 92, 18), Color(0.28, 0.35, 0.42, 0.9))
				canvas.draw_circle(Vector2(center_px.x, center_px.y + 8), 28, Color(0.2, 0.55, 0.95, 0.35))


func _find_nearest_water(start_x: int, start_y: int, max_steps: int) -> Vector2i:
	var best = Vector2i(-1, -1)
	var best_d = 999999.0

	var min_x = max(0, start_x - max_steps)
	var max_x = mini(_map_w() - 1, start_x + max_steps)
	var min_y = max(0, start_y - max_steps)
	var max_y = mini(_map_w() - 1, start_y + max_steps)

	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var cell = FarmDataManager.grid_data[x][y]
			# Target anything that is wet: Rivers, meandering streams, or dug swales
			if bool(cell.get("is_river", false)) or str(cell.get("land", "")) in ["river", "stream", "swale"]:
				var d = Vector2(x - start_x, y - start_y).length()
				if d <= max_steps and d < best_d:
					best_d = d
					best = Vector2i(x, y)
	return best


func _bresenham_line(start: Vector2i, end: Vector2i) -> Array:
	var path: Array = []
	var x0 = start.x
	var y0 = start.y
	var x1 = end.x
	var y1 = end.y

	var dx = absi(x1 - x0)
	var sx = 1 if x0 < x1 else -1
	var dy = -absi(y1 - y0)
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy

	while true:
		path.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return path


func _apply_corridor_brush(path: Array) -> void:
	var visited: Dictionary = {}
	for p in path:
		# Drag a radius 2 brush along the spine
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx * dx + dy * dy <= 5:
					var nx = p.x + dx
					var ny = p.y + dy
					if nx >= 0 and nx < _map_w() and ny >= 0 and ny < _map_w():
						var key = str(nx) + "," + str(ny)
						if not visited.has(key):
							visited[key] = true
							var cell = FarmDataManager.grid_data[nx][ny]
							# Skip pens, rivers, and building tiles (string `structure` only — overload header).
							if cell.get("zone", "") != "pen" and not _cell_has_building_structure(cell) and not cell.get("is_river", false):
								cell["zone"] = "duck_patrol"
								cell["has_path"] = false


## Legacy mirrors (`m`/`n`/`w`) removed — V3 keys `moisture` / `nitrogen` are authoritative.
func _v3_sync_legacy_mn(_cell: Dictionary) -> void:
	pass


## V3 ecology baselines on grid cells (0–10 scale except pH 0–14).
func _v3_apply_default_ecology(cell: Dictionary, land_key: String, mo := 6.0, ni := 5.0, mi := 5.0) -> void:
	var fb := 2.0 if land_key in ["wild", "forest"] else 0.0
	var use_mo := mo
	var use_ni := ni
	var use_mi := mi
	var structure := 5.0
	var macro := 2.0
	match land_key:
		"road", "bridge":
			use_mo = 0.0
			use_ni = 0.0
			use_mi = 0.0
			fb = 0.0
			structure = 0.0
			macro = 0.0
		"river", "stream":
			use_mo = 10.0
			use_ni = 2.0
			use_mi = 4.0
			fb = 0.0
		"cultivated":
			use_mo = mo
			use_ni = ni
			use_mi = mi
			fb = 0.0
		_:
			pass
	cell["moisture"] = use_mo
	cell["nitrogen"] = use_ni
	cell["minerals"] = use_mi
	cell["ph"] = 6.5
	cell["toxicity"] = 0.0
	# Same key as building ids after placement — readers must use `_cell_has_building_structure` for “blocking object”.
	cell["structure"] = structure
	cell["macro_life"] = macro
	cell["fungi"] = fb
	cell["bacteria"] = fb
	_v3_sync_legacy_mn(cell)


func _apply_plant_stress(cell: Dictionary, layer: String, map_pos: Vector2i, reason: String) -> bool:
	var age_key := layer + "_age"
	var current_age = float(cell.get(age_key, 0.0))

	var damage := 0.5
	var death_threshold := -3.0 # Normal mode buffer (survives 6 days of stress)

	if FarmDataManager.difficulty == "Easy":
		damage = 0.1
		death_threshold = -10.0 # Massive buffer (survives 100 days of stress)
	elif FarmDataManager.difficulty == "Hard":
		damage = 1.0
		death_threshold = -1.0 # Brutal buffer (dies very quickly)

	# Stress damages the plant
	cell[age_key] = current_age - damage

	if FarmDataManager.active_campaign_id == "heritage_garden":
		if float(cell[age_key]) < 0.0:
			cell[age_key] = 0.0
		if randf() < 0.05 and reason != "":
			if has_method("spawn_floating_text"):
				spawn_floating_text(reason, Color("c8e6c9"), map_pos, "warnings")
		return false

	if FarmDataManager.creative_zen_mode:
		cell[age_key] = maxf(float(cell[age_key]), 0.1)
		if randf() < 0.05:
			if has_method("spawn_floating_text"):
				spawn_floating_text(reason, Color("ffb74d"), map_pos, "warnings")
		return false

	# Check if the plant has exhausted its negative stress buffer
	if float(cell[age_key]) < death_threshold:
		var plant_id := str(cell.get(layer, "unknown_plant"))
		var stats := "[M:%.1f N:%.1f Min:%.1f]" % [
			float(cell.get("moisture", 0.0)),
			float(cell.get("nitrogen", 0.0)),
			float(cell.get("minerals", 0.0)),
		]
		print(
			"☠️ Turn ",
			FarmDataManager.current_turn,
			" | Plant died at (",
			map_pos.x,
			", ",
			map_pos.y,
			") [",
			plant_id,
			"] Reason: ",
			reason,
			" Stats: ",
			stats
		)
		cell[layer] = ""
		cell.erase(age_key)
		if has_method("spawn_floating_text"):
			spawn_floating_text("Fatal: " + reason, Color("ff5252"), map_pos, "warnings")
		return true # The plant died

	# The plant survived, but is stressed (struggling seedling)
	if randf() < 0.05:
		if has_method("spawn_floating_text"):
			spawn_floating_text(reason, Color("ffb74d"), map_pos, "warnings")
	return false # Still alive


func _get_plant_data(plant_id: String) -> Dictionary:
	return preload("res://data/data_plants.gd").get_plant_data(plant_id)


## phase "growth" — V3 gatekeepers (stress chips age; **0** growth that turn, **-1** if dead) then taproot/aeration modifier.
## phase "exchange" — V3 ecological deltas + scaled soil-web affinities (0–10 clamps).
func _process_plant_biology(map_pos: Vector2i, plant_id: String, phase: String = "growth", layer: String = "") -> float:
	if map_pos.x < 0 or map_pos.x >= _map_w() or map_pos.y < 0 or map_pos.y >= _map_h():
		return 1.0
	var cell: Dictionary = FarmDataManager.grid_data[map_pos.x][map_pos.y]
	var plant_data: Dictionary = preload("res://data/data_plants.gd").get_plant_data(plant_id)
	if plant_data.is_empty():
		return 1.0
	if layer == "":
		for cand in ["canopy", "understory", "ground"]:
			if str(cell.get(cand, "")) == plant_id:
				layer = cand
				break
		if layer == "":
			return 1.0

	match phase:
		"growth":
			if str(cell.get(layer, "")) != plant_id:
				return 1.0
			var mo := float(cell.get("moisture", 5.0))
			var nit := float(cell.get("nitrogen", 5.0))
			var minr := float(cell.get("minerals", 5.0))
			var pmin_m := float(plant_data.get("min_moisture", 0))
			var pmax_m := float(plant_data.get("max_moisture", 10))
			var pmin_n := float(plant_data.get("min_nitrogen", 0))
			var pmax_n := float(plant_data.get("max_nitrogen", 10))
			var pmin_min := float(plant_data.get("min_minerals", 0))
			var pmax_min := float(plant_data.get("max_minerals", 10))

			var reason := ""
			if mo < pmin_m:
				reason = "Thirsty!"
			elif mo > pmax_m:
				reason = "Root Rot!"
			elif nit < pmin_n:
				reason = "Starved!"
			elif nit > pmax_n:
				reason = "Nutrient Burn!"
			elif minr < pmin_min:
				reason = "Mineral Starved!"
			elif minr > pmax_min:
				reason = "Lockout!"
			else:
				var soil_tox := float(cell.get("toxicity", 0.0))
				var max_tox := float(plant_data.get("max_toxicity", 10.0))
				if soil_tox > max_tox:
					reason = "Toxic Soil!"

			if reason != "":
				var died := _apply_plant_stress(cell, layer, map_pos, reason)
				if died:
					return -1.0
				return 0.0

			var growth_modifier: float = 1.0
			var root_type := str(plant_data.get("root_type", "Fibrous"))
			if "Taproot" in root_type:
				var aer := int(cell.get("aeration", 20))
				if aer < 30:
					growth_modifier = 0.5
				elif aer > 70:
					growth_modifier = 2.0
			growth_modifier *= FarmDataManager.creative_time_lapse
			return growth_modifier
		"exchange":
			if str(cell.get(layer, "")) != plant_id:
				return 1.0

			var md := float(plant_data.get("moisture_delta", 0))
			var nd := float(plant_data.get("nitrogen_delta", 0))
			var mind := float(plant_data.get("mineral_delta", 0))
			var sd := float(plant_data.get("structure_delta", 0))
			var td := float(plant_data.get("toxicity_delta", 0))

			cell["moisture"] = clampf(float(cell.get("moisture", 5.0)) + md, 0.0, 10.0)
			cell["nitrogen"] = clampf(float(cell.get("nitrogen", 5.0)) + nd, 0.0, 10.0)
			cell["minerals"] = clampf(float(cell.get("minerals", 5.0)) + mind, 0.0, 10.0)
			cell["structure"] = clampf(float(cell.get("structure", 5.0)) + sd, 0.0, 10.0)
			cell["toxicity"] = clampf(float(cell.get("toxicity", 0.0)) + td, 0.0, 10.0)

			var fungi_gain := float(plant_data.get("fungal_affinity", 0)) * 0.1
			if MetaManager.has_upgrade("ecto_fungi"):
				fungi_gain *= 1.2
			cell["fungi"] = clampf(float(cell.get("fungi", 0.0)) + fungi_gain, 0.0, 10.0)
			cell["bacteria"] = clampf(float(cell.get("bacteria", 0.0)) + float(plant_data.get("bacterial_affinity", 0)) * 0.1, 0.0, 10.0)
			cell["macro_life"] = clampf(float(cell.get("macro_life", 2.0)) + float(plant_data.get("macro_life_affinity", 0)) * 0.1, 0.0, 10.0)

			var is_fixer: bool = plant_data.get("nitrogen_fixer", false) == true
			var is_accum: bool = plant_data.get("dynamic_accumulator", false) == true
			if is_fixer or is_accum:
				cell["biodiversity"] = clampi(int(cell.get("biodiversity", 10)) + 2, 0, 100)
				cell["aeration"] = clampi(int(cell.get("aeration", 20)) + 1, 0, 100)

			_v3_sync_legacy_mn(cell)
			return 1.0
		_:
			return 1.0


func _is_guild_satisfied(cx: int, cy: int, guild: Dictionary) -> bool:
	# Standard guilds ONLY check the exact 1-tile coordinate
	var cell: Dictionary = FarmDataManager.grid_data[cx][cy]
	var local_plants: Array[String] = []
	for p_layer in ["canopy", "understory", "ground"]:
		var n_pid := str(cell.get(p_layer, ""))
		if n_pid != "":
			local_plants.append(n_pid)
	var seed_only := str(cell.get("seed_id", ""))
	if seed_only != "":
		local_plants.append(seed_only)

	for comp in guild.get("companions", []):
		if not local_plants.has(str(comp)):
			return false
	return true


func _get_guild_synergy_mult(x: int, y: int, core_plant_id: String) -> float:
	var mult: float = 1.0
	var guilds_dict: Dictionary = preload("res://data/data_guilds.gd").ENTRIES
	for guild_key in guilds_dict:
		var guild: Dictionary = guilds_dict[guild_key]
		if str(guild.get("core", "")) != core_plant_id:
			continue
		if _is_guild_satisfied(x, y, guild):
			mult = maxf(mult, float(guild.get("growth_mult", 1.0)))
	return mult


## Returns satisfied standard guild names and role-based superguild names for the 3×3 neighborhood around (cx, cy).
func _get_synergies_for_cell(cx: int, cy: int) -> Dictionary:
	var active_guilds: Array[Dictionary] = []
	var active_superguilds: Array[Dictionary] = []
	var guilds_dict = preload("res://data/data_guilds.gd").ENTRIES
	var superguilds_dict = preload("res://data/data_superguilds.gd").ENTRIES

	# --- 1. 1-TILE STANDARD GUILD CHECK ---
	var center_cell: Dictionary = FarmDataManager.grid_data[cx][cy]
	for layer in ["canopy", "understory", "ground"]:
		var p_id := str(center_cell.get(layer, ""))
		if p_id == "":
			continue
		for g_key in guilds_dict:
			var guild: Dictionary = guilds_dict[g_key]
			if str(guild.get("core", "")) == p_id:
				if _is_guild_satisfied(cx, cy, guild):
					var nm := str(guild.get("name", ""))
					if nm != "" and not active_guilds.has(guild):
						active_guilds.append(guild)

	# --- SUPERGUILD CHECK (Role-Based) ---
	# 1. Tally all roles present in the 3x3 neighbourhood
	var local_roles: Dictionary = {}
	var plant_db = preload("res://data/data_plants.gd")
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var nx = clampi(cx + dx, 0, _map_w() - 1)
			var ny = clampi(cy + dy, 0, _map_w() - 1)
			var n_cell = FarmDataManager.grid_data[nx][ny]
			for layer in ["canopy", "understory", "ground"]:
				var p_id = str(n_cell.get(layer, ""))
				if p_id == "":
					continue
				var p_data = plant_db.get_plant_data(p_id)

				# Tally boolean traits as roles (e.g., "nitrogen_fixer": true -> count + 1)
				for trait_key in p_data.keys():
					if typeof(p_data[trait_key]) == TYPE_BOOL and p_data[trait_key] == true:
						local_roles[trait_key] = local_roles.get(trait_key, 0) + 1

				# Tally explicit string roles or categories if they exist
				var cat = str(p_data.get("category", ""))
				if cat != "":
					local_roles[cat] = local_roles.get(cat, 0) + 1

	# 2. Check if the tallied roles satisfy any Superguild requirements
	for sg_key in superguilds_dict:
		var sg = superguilds_dict[sg_key]
		var reqs: Dictionary = sg.get("req_roles", {})
		var satisfies_sg = true

		for req_role in reqs.keys():
			var required_amount = reqs[req_role]
			var actual_amount = local_roles.get(req_role, 0)
			if actual_amount < required_amount:
				satisfies_sg = false
				break

		if satisfies_sg and reqs.size() > 0:
			var sg_name := str(sg.get("name", ""))
			if sg_name != "" and not active_superguilds.has(sg):
				active_superguilds.append(sg)

	return {"guilds": active_guilds, "superguilds": active_superguilds}


func _draw_girih_pattern(canvas: CanvasItem, center: Vector2, points: int, outer_r: float, inner_r: float, color: Color, line_width: float = 4.0) -> void:
	var pts := PackedVector2Array()
	var angle_step := PI / float(points)
	for i in range(points * 2 + 1):
		var r := outer_r if i % 2 == 0 else inner_r
		var a := float(i) * angle_step
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	canvas.draw_polyline(pts, color, line_width)

	if points >= 8:
		var inner_pts := PackedVector2Array()
		for i in range(points * 2 + 1):
			var r2 := (outer_r * 0.5) if i % 2 == 0 else (inner_r * 0.5)
			var a2 := (float(i) * angle_step) + (PI / float(points))
			inner_pts.append(center + Vector2(cos(a2), sin(a2)) * r2)
		canvas.draw_polyline(inner_pts, color, line_width / 2.0)


class EnergyZoneOverlayNode extends Node2D:
	var map_ref: Node2D

	func _draw() -> void:
		if map_ref == null or map_ref.get("active_lens") != "energy":
			return
		if map_ref.has_method("_draw_energy_background"):
			map_ref._draw_energy_background(self)


class GuildOverlayNode extends Node2D:
	var map_ref: Node2D
	var _guilds_by_core: Dictionary = {}
	var _guilds_loaded := false

	func _ensure_loaded() -> void:
		if _guilds_loaded:
			return
		_guilds_loaded = true
		var guilds_dict: Dictionary = preload("res://data/data_guilds.gd").ENTRIES
		for g_key in guilds_dict:
			var g: Dictionary = guilds_dict[g_key]
			var core_id := str(g.get("core", ""))
			if core_id == "":
				continue
			if not _guilds_by_core.has(core_id):
				_guilds_by_core[core_id] = []
			(_guilds_by_core[core_id] as Array).append(g)

	func _draw() -> void:
		if map_ref == null or map_ref.get("active_lens") != "guild":
			return
			
		var guilds_dict: Dictionary = preload("res://data/data_guilds.gd").ENTRIES
		var superguilds_dict: Dictionary = preload("res://data/data_superguilds.gd").ENTRIES
		var plant_db = preload("res://data/data_plants.gd")
		
		# --- 1. Draw the Selected 3x3 Interaction Box ---
		var selected_cell: Vector2i = map_ref.guild_selected_cell
		if selected_cell != Vector2i(-1, -1):
			var sel_px = map_ref.map_to_local(selected_cell)
			var box_rect = Rect2(sel_px - Vector2(300, 300), Vector2(600, 600))
			draw_rect(box_rect, Color(1.0, 1.0, 1.0, 0.05), true) 
			draw_rect(box_rect, Color(1.0, 1.0, 1.0, 0.3), false, 4.0) 
			
			var font = ThemeDB.fallback_font
			draw_string_outline(font, sel_px - Vector2(280, 270), "3x3 Superguild Zone", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0,0,0,0.8))
			draw_string(font, sel_px - Vector2(280, 270), "3x3 Superguild Zone", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

		# --- 2. Scan and Draw Synergy Networks ---
		for x in range(map_ref._map_w()):
			for y in range(map_ref._map_h()):
				var center_px = map_ref.map_to_local(Vector2i(x, y))
				var cell = FarmDataManager.grid_data[x][y]
				
				# A. Check for standard 1-tile guilds
				var has_standard_guild: bool = false
				for layer in ["canopy", "understory", "ground"]:
					var p_id = str(cell.get(layer, ""))
					if p_id == "":
						continue
					for g_key in guilds_dict:
						var guild = guilds_dict[g_key]
						if str(guild.get("core", "")) == p_id:
							if map_ref._is_guild_satisfied(x, y, guild):
								has_standard_guild = true
								break
				
				# B. Check for 3x3 Superguilds
				var local_roles: Dictionary = {}
				var contributor_positions: Array[Vector2] = []
				
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						var nx = clampi(x + dx, 0, map_ref._map_w() - 1)
						var ny = clampi(y + dy, 0, map_ref._map_h() - 1)
						var n_cell = FarmDataManager.grid_data[nx][ny]
						var pos_px = map_ref.map_to_local(Vector2i(nx, ny))
						
						var cell_contributed: bool = false
						for layer in ["canopy", "understory", "ground"]:
							var p_id = str(n_cell.get(layer, ""))
							if p_id == "":
								continue
							var p_data = plant_db.get_plant_data(p_id)
							
							for trait_key in p_data.keys():
								if typeof(p_data[trait_key]) == TYPE_BOOL and p_data[trait_key] == true:
									local_roles[trait_key] = local_roles.get(trait_key, 0) + 1
									cell_contributed = true
							var cat = str(p_data.get("category", ""))
							if cat != "": 
								local_roles[cat] = local_roles.get(cat, 0) + 1
								cell_contributed = true
								
						if cell_contributed:
							contributor_positions.append(pos_px)
							
				var is_superguild: bool = false
				for sg_key in superguilds_dict:
					var sg = superguilds_dict[sg_key]
					var reqs: Dictionary = sg.get("req_roles", {})
					var satisfies_sg: bool = true
					
					for req_role in reqs.keys():
						if local_roles.get(req_role, 0) < reqs[req_role]:
							satisfies_sg = false
							break
							
					if satisfies_sg and reqs.size() > 0:
						is_superguild = true
						break
				
				# --- 3. Render the Visuals ---
				if is_superguild:
					# Draw Superguild Web (Neon Magenta / Purple)
					var pulse = (sin(Time.get_ticks_msec() / 200.0) + 1.0) / 2.0
					# Faint inner core
					draw_circle(center_px, 60.0, Color(0.85, 0.2, 0.85, 0.3 + (0.2 * pulse)))
					# Thick, bright outer ring
					draw_arc(center_px, 65.0, 0.0, TAU, 64, Color(0.95, 0.3, 0.95, 1.0), 8.0, true)
					
					for comp_px in contributor_positions:
						if comp_px != center_px:
							# Thick, bright connecting lines
							draw_line(center_px, comp_px, Color(0.8, 0.3, 0.9, 0.85), 10.0, true)
							# Solid bright nodes at the companion tiles
							draw_circle(comp_px, 25.0, Color(0.9, 0.2, 0.8, 1.0))
							draw_circle(comp_px, 15.0, Color(1.0, 1.0, 1.0, 1.0)) # White hot centre
				elif has_standard_guild:
					# Draw Standard Guild (Massive Neon Gold Aura)
					var pulse = (sin(Time.get_ticks_msec() / 300.0) + 1.0) / 2.0
					draw_circle(center_px, 90.0, Color(1.0, 0.85, 0.1, 0.25 + (0.2 * pulse)))
					draw_arc(center_px, 95.0, 0.0, TAU, 72, Color(1.0, 0.85, 0.2, 1.0), 8.0, true)


class EnergyCursorOverlayNode extends Node2D:
	var map_ref: Node2D

	func _draw() -> void:
		if map_ref == null or map_ref.get("active_lens") != "energy":
			return
		if map_ref.has_method("_draw_energy_cursor"):
			map_ref._draw_energy_cursor(self)


class MaintenanceBubbleOverlayNode extends Node2D:
	var map_ref: Node2D

	func _draw() -> void:
		pass # Disabled: Energy Vision now handles movement visualization


class StructureOverlayNode extends Node2D:
	var map_ref: Node2D

	func _draw() -> void:
		if map_ref and map_ref.has_method("_on_structure_overlay_draw"):
			map_ref._on_structure_overlay_draw(self)


func _on_preview_overlay_draw(canvas: CanvasItem) -> void:
	# --- DRAW EMPLACED BLUEPRINTS (preview tiles for structures queued but not yet built) ---
	for bp in FarmDataManager.blueprints:
		var bps := str(bp.get("structure", ""))
		var hex_bp: String = str(bp.get("color", "fbc02d"))
		if not hex_bp.begins_with("#"):
			hex_bp = "#" + hex_bp
		var bp_color := Color(hex_bp)
		var fp: Variant = bp.get("footprint", [])
		if not fp is Array:
			continue
		for cell in fp:
			if not cell is Vector2i:
				continue
			var c: Vector2i = cell
			if c.x < 0 or c.x >= _map_w() or c.y < 0 or c.y >= _map_h():
				continue
			var bp_rect := Rect2(map_to_local(c) - Vector2(100, 100), Vector2(200, 200))
			if bps == "bridge":
				canvas.draw_rect(bp_rect, Color(bp_color.r, bp_color.g, bp_color.b, 0.4), true)
				canvas.draw_rect(bp_rect, Color(bp_color.r, bp_color.g, bp_color.b, 0.85), false, 4.0)
			elif bps == "duck_house":
				canvas.draw_rect(bp_rect, Color(bp_color.r, bp_color.g, bp_color.b, 0.35), true)
				canvas.draw_rect(bp_rect, Color(bp_color.r, bp_color.g, bp_color.b, 0.75), false, 3.0)
			elif bps in ["polytunnel", "honesty_box", "pig_house", "compost_brewer"]:
				canvas.draw_rect(bp_rect, Color(bp_color.r, bp_color.g, bp_color.b, 0.4), true)
				canvas.draw_rect(bp_rect, Color(bp_color.r, bp_color.g, bp_color.b, 0.75), false, 3.0)

	# --- QUEUED TILE ACTIONS (earthworks + water): translucent — terrain atlas stays ground truth above.
	for q_action in FarmDataManager.action_queue:
		var pos_raw: Variant = q_action.get("pos", Vector2i(-1, -1))
		if not pos_raw is Vector2i:
			continue
		var qpos: Vector2i = pos_raw
		var action_type := str(q_action.get("action", ""))
		if qpos.x < 0 or qpos.x >= _map_w() or qpos.y < 0 or qpos.y >= _map_h():
			continue
		var tile_rect := Rect2(map_to_local(qpos) - Vector2(100, 100), Vector2(200, 200))
		if action_type == "rotovate" or action_type == "hoe":
			canvas.draw_rect(tile_rect, Color(0.365, 0.251, 0.216, 0.6), true)
		elif action_type == "dig_swale":
			canvas.draw_rect(tile_rect, Color(0.157, 0.208, 0.576, 0.6), true)
		elif action_type == "build_mound":
			canvas.draw_rect(tile_rect, Color(0.769, 0.318, 0.102, 0.6), true)
		elif action_type == "water_tile":
			var drop_color := Color(0.31, 0.765, 0.969, 0.7)
			var center_px := map_to_local(qpos)
			canvas.draw_circle(Vector2(center_px.x, center_px.y + 10.0), 18.0, drop_color)
			var top_tri := PackedVector2Array([
				Vector2(center_px.x, center_px.y - 25.0),
				Vector2(center_px.x + 17.0, center_px.y + 5.0),
				Vector2(center_px.x - 17.0, center_px.y + 5.0),
			])
			canvas.draw_colored_polygon(top_tri, drop_color)
		elif action_type == "apply_tea":
			canvas.draw_rect(tile_rect, Color(0.5, 0.78, 0.52, 0.6), true)

	# --- LIVE: 4×1 FOOTBRIDGE PREVIEW (blueprint tool) ---
	if active_tool == "build" and active_structure == "bridge":
		var mouse_cell := local_to_map(get_local_mouse_position())
		if mouse_cell.x >= 0 and mouse_cell.x < _map_w() and mouse_cell.y >= 0 and mouse_cell.y < _map_w():
			var footprint := _get_bridge_footprint(mouse_cell)
			for cell in footprint:
				if cell.x < 0 or cell.x >= _map_w() or cell.y < 0 or cell.y >= _map_h():
					continue
				var rect := Rect2(map_to_local(cell) - Vector2(100, 100), Vector2(200, 200))
				canvas.draw_rect(rect, Color(0.55, 0.27, 0.07, 0.6), true)
				canvas.draw_rect(rect, Color(1, 1, 1, 0.8), false, 4.0)

	# --- LIVE: DUCK HOUSE PREVIEW ---
	if active_tool == "build" and active_structure == "duck_house":
		var local_mouse := get_local_mouse_position()
		var map_pos := local_to_map(local_mouse)

		if map_pos.x >= 0 and map_pos.x < _map_w() and map_pos.y >= 0 and map_pos.y < _map_w():
			var center_px := map_to_local(map_pos)

			var water = _find_nearest_water(map_pos.x, map_pos.y + 1, 60)
			if water != Vector2i(-1, -1):
				var path = _bresenham_line(Vector2i(map_pos.x, map_pos.y + 1), water)
				for p in path:
					var p_px = map_to_local(p as Vector2i)
					canvas.draw_circle(p_px, 400.0, Color(0.4, 0.8, 0.9, 0.2))


			var pen_rect := Rect2(center_px - Vector2(300, 300), Vector2(600, 600))
			canvas.draw_rect(pen_rect, Color(0.5, 0.4, 0.3, 0.3))

			var house_rect := Rect2(center_px - Vector2(100, 100), Vector2(200, 200))
			canvas.draw_rect(house_rect, Color(0.55, 0.43, 0.39, 0.8))

	if active_tool == "build" and active_structure in ["polytunnel", "honesty_box", "pig_house", "compost_brewer", "beehive", "sprinkler", "drone_hub", "moisture_net", "smart_shade", "drone_pollinator", "solar_panel", "battery", "water_butt"]:
		var mc := local_to_map(get_local_mouse_position())
		if mc.x >= 0 and mc.x < _map_w() and mc.y >= 0 and mc.y < _map_h():
			if active_structure == "beehive":
				var hp_hv := map_to_local(mc)
				var hive_pr := Rect2(hp_hv - Vector2(55, 55), Vector2(110, 110))
				canvas.draw_rect(hive_pr, Color(1.0, 0.88, 0.25, 0.65), true)
				canvas.draw_rect(hive_pr, Color(0.95, 0.75, 0.1, 0.85), false, 3)
				var forage_pr := Rect2(hp_hv - Vector2(400, 400), Vector2(800, 800))
				canvas.draw_rect(forage_pr, Color(1.0, 0.92, 0.35, 0.08))
				canvas.draw_rect(forage_pr, Color(1.0, 0.88, 0.2, 0.35), false, 2)
			elif active_structure == "smart_shade":
				var hp_sh := map_to_local(mc)
				var shade_pr := Rect2(hp_sh - Vector2(125, 125), Vector2(250, 250))
				canvas.draw_rect(shade_pr, Color(1.0, 0.9, 0.2, 0.15), true)
				canvas.draw_rect(shade_pr, Color(1.0, 0.85, 0.1, 0.6), false, 4)
			elif active_structure == "drone_pollinator":
				var hp_po := map_to_local(mc)
				canvas.draw_circle(hp_po, 22, Color(0.8, 0.4, 0.95, 0.75))
				var pol_pr := Rect2(hp_po - Vector2(75, 75), Vector2(150, 150))
				canvas.draw_rect(pol_pr, Color(0.75, 0.35, 0.9, 0.12))
				canvas.draw_rect(pol_pr, Color(0.9, 0.5, 1.0, 0.45), false, 2)
			elif active_structure == "moisture_net":
				var hp_net := map_to_local(mc)
				var net_pr := Rect2(hp_net - Vector2(90, 90), Vector2(180, 180))
				canvas.draw_rect(net_pr, Color(0.5, 0.8, 1.0, 0.2), true)
				canvas.draw_rect(net_pr, Color(0.75, 0.92, 1.0, 0.65), false, 3)
			elif active_structure == "sprinkler":
				var cp_sp := map_to_local(mc)
				canvas.draw_circle(cp_sp, 28, Color(0.25, 0.6, 1.0, 0.7))
				canvas.draw_circle(cp_sp, 62, Color(0.3, 0.7, 1.0, 0.15))
				for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					canvas.draw_circle(map_to_local(mc + off), 16, Color(0.35, 0.75, 1.0, 0.25))
			elif active_structure == "drone_hub":
				var hp_dh := map_to_local(mc)
				var hub_pr := Rect2(hp_dh - Vector2(70, 70), Vector2(140, 140))
				canvas.draw_rect(hub_pr, Color(0.5, 0.55, 0.6, 0.55), true)
				canvas.draw_rect(hub_pr, Color(0.7, 0.85, 1.0, 0.7), false, 3.0)
				var scan_pr := Rect2(hp_dh - Vector2(200, 200), Vector2(400, 400))
				canvas.draw_rect(scan_pr, Color(0.4, 0.85, 1.0, 0.06))
				canvas.draw_rect(scan_pr, Color(0.55, 0.9, 1.0, 0.2), false, 2)
			else:
				var pr := Rect2(map_to_local(mc) - Vector2(100, 100), Vector2(200, 200))
				canvas.draw_rect(pr, Color(0.35, 0.55, 0.28, 0.45), true)
				canvas.draw_rect(pr, Color(0.85, 1.0, 0.75, 0.75), false, 3.0)

	_draw_planned_journey_lines(canvas)

	# --- LIVE: SHIFT-DRAG RECTANGLE GRID ---
	if _shift_drag_start != Vector2i(-1, -1) and is_dragging:
		var map_ref: Node2D = self
		var cur_hover := local_to_map(get_local_mouse_position())
		var min_x = mini(_shift_drag_start.x, cur_hover.x)
		var max_x = maxi(_shift_drag_start.x, cur_hover.x)
		var min_y = mini(_shift_drag_start.y, cur_hover.y)
		var max_y = maxi(_shift_drag_start.y, cur_hover.y)

		var accumulated_energy = 0
		var current_e = FarmDataManager.get_energy()

		var sequence = map_ref._get_smart_drag_sequence(min_x, max_x, min_y, max_y)
		for cell_pos in sequence:
			var costs = map_ref._get_planning_e_m_costs(cell_pos)
			var tile_cost = costs.x + 1 # Approximate move cost

			var fill_color = Color(0.5, 0.5, 0.5, 0.5) # Basic Grey (Unaffordable)
			if accumulated_energy + tile_cost <= current_e:
				fill_color = Color(0.3, 0.9, 0.3, 0.6) # Bright Green (Affordable)
				accumulated_energy += tile_cost
			else:
				accumulated_energy += tile_cost

			var rect = Rect2(map_ref.map_to_local(cell_pos) - Vector2(100, 100), Vector2(200, 200))
			canvas.draw_rect(rect, fill_color, true)
			canvas.draw_rect(rect, Color(1, 1, 1, 0.2), false, 4.0) # Subtle inner border


func _spawn_click_particles(pos: Vector2, burst_color: Color) -> void:
	var burst = CPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 15.0
	burst.spread = 180.0
	burst.gravity = Vector2(0, -100)
	burst.initial_velocity_min = 40.0
	burst.initial_velocity_max = 80.0
	burst.scale_amount_min = 4.0
	burst.scale_amount_max = 8.0
	burst.color = burst_color
	burst.z_index = 100
	burst.position = pos
	add_child(burst)
	burst.emitting = true

	var t = get_tree().create_timer(1.0, false)
	t.timeout.connect(func(): if is_instance_valid(burst): burst.queue_free())


class PreviewOverlayNode extends Node2D:
	var map_ref: Node2D

	func _draw() -> void:
		if map_ref and map_ref.has_method("_on_preview_overlay_draw"):
			map_ref._on_preview_overlay_draw(self)


class TriageOverlayNode extends Node2D:
	var map_ref: Node2D

	func _process(_delta: float) -> void:
		if map_ref and not map_ref.is_sleeping and map_ref.triage_cache.size() > 0:
			queue_redraw()

	func _draw() -> void:
		if map_ref == null or map_ref.is_sleeping or map_ref.triage_cache.is_empty():
			return

		var cam = get_viewport().get_camera_2d()
		if not cam:
			return
		var cam_pos = cam.global_position
		var zoom = cam.zoom.x
		var font = ThemeDB.fallback_font

		for cell in map_ref.triage_cache:
			var data = map_ref.triage_cache[cell]
			var target_pos = map_ref.map_to_local(cell)
			var dist = cam_pos.distance_to(map_ref.to_global(target_pos))

			var alpha = 0.0
			if map_ref.morning_triage_active:
				alpha = 1.0 # Fully visible during the morning phase
			else:
				# Fade in gently as the camera scrolls near
				var vis_radius = 1200.0 / zoom
				var fade_start = vis_radius * 0.4
				var fade_end = vis_radius * 0.8
				alpha = 1.0 - clamp((dist - fade_start) / (fade_end - fade_start), 0.0, 1.0)

			if alpha > 0.01:
				var c: Color = data["color"]
				c.a = alpha
				var text_pos = target_pos + Vector2(0, -60)
				draw_string_outline(font, text_pos, data["msg"], HORIZONTAL_ALIGNMENT_CENTER, -1, 32, 6, Color(0, 0, 0, alpha * 0.8))
				draw_string(font, text_pos, data["msg"], HORIZONTAL_ALIGNMENT_CENTER, -1, 32, c)


class DesignOverlayNode extends Node2D:
	var map_ref: Node2D

	func _draw_scribble(s: Dictionary) -> void:
		var pts = s.get("points", PackedVector2Array())
		if pts.size() < 2:
			return
		var thick: float = float(s.get("thickness", 6.0))
		var col: Color = s.get("color", Color(1, 1, 1, 0.6))

		match str(s.get("type", "pen")):
			"pen":
				draw_polyline(pts, col, thick)
			"rect":
				var rect = Rect2(pts[0], pts[1] - pts[0]).abs()
				draw_rect(rect, col, false, thick)
			"circle":
				var radius = pts[0].distance_to(pts[1])
				draw_circle(pts[0], radius, Color.TRANSPARENT)
				draw_arc(pts[0], radius, 0.0, TAU, 32, col, thick, true)
			"arrow":
				var dvec = pts[1] - pts[0]
				if dvec.length() < 0.01:
					return
				draw_line(pts[0], pts[1], col, thick)
				var dir = dvec.normalized()
				var head = thick * 4.0
				var p3 = pts[1] - dir * head + dir.orthogonal() * (head * 0.6)
				var p4 = pts[1] - dir * head - dir.orthogonal() * (head * 0.6)
				draw_polygon(PackedVector2Array([pts[1], p3, p4]), PackedColorArray([col, col, col]))
			"eraser":
				pass

	func _draw() -> void:
		if map_ref == null or map_ref.get("active_lens") != "design":
			return

		for s in FarmDataManager.scribbles:
			if s is Dictionary:
				_draw_scribble(s)

		if map_ref._is_scribbling and map_ref._current_shape_data.has("points"):
			_draw_scribble(map_ref._current_shape_data)

		for pos in FarmDataManager.cell_notes:
			var px = map_ref.map_to_local(pos)
			var hex_str: String = str(FarmDataManager.cell_notes[pos]["color"])
			if not hex_str.begins_with("#"):
				hex_str = "#" + hex_str
			var col = Color(hex_str)
			draw_circle(px - Vector2(75, 75), 15.0, col)
			draw_rect(Rect2(px - Vector2(100, 100), Vector2(200, 200)), Color(col.r, col.g, col.b, 0.15), true)
			draw_rect(Rect2(px - Vector2(100, 100), Vector2(200, 200)), Color(col.r, col.g, col.b, 0.6), false, 4.0)
