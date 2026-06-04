extends PanelContainer

## Asset Hub — campaign starting-grid painter (terrain + V3 soil inspector).

const SAVE_PATH := "user://campaigns/custom/starting_grid.json"

const LAND_COLORS: Dictionary = {
	"land": Color(0.45, 0.62, 0.28, 1.0),
	"water": Color(0.2, 0.45, 0.85, 1.0),
	"rock": Color(0.55, 0.55, 0.58, 1.0),
	"road": Color(0.25, 0.25, 0.28, 1.0),
	"structure": Color(0.72, 0.72, 0.76, 1.0),
}

var grid_data: Array = []
var map_width: int = 24
var map_height: int = 24
var cell_size: int = 32
var farmhouse_pos: Vector2i = Vector2i(-1, -1)
var inspected_cell: Vector2i = Vector2i(-1, -1)
var active_tool: String = "brush"
var _brush_land: String = "land"
var _is_painting: bool = false
var _inspector_syncing: bool = false

var _spin_width: SpinBox
var _map_status_label: Label
var _spin_height: SpinBox
var _brush_option: OptionButton
var _grid_canvas: Control
var _soil_inspector: VBoxContainer
var _soil_spins: Dictionary = {}
var _saved_grid_load_attempted: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 1.0)
	add_theme_stylebox_override("panel", style)

	var main := HBoxContainer.new()
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.add_theme_constant_override("separation", 10)
	add_child(main)

	_build_left_sidebar(main)
	_build_center_viewport(main)
	_build_right_inspector(main)

	_initialise_grid()
	# Saved grid loads when the Map tab is first opened (avoids AcceptDialog on main-menu boot).


func _build_left_sidebar(parent: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	left.add_theme_constant_override("separation", 8)
	parent.add_child(left)

	var settings_lbl := Label.new()
	settings_lbl.text = "Map Settings"
	settings_lbl.add_theme_font_size_override("font_size", 18)
	settings_lbl.add_theme_color_override("font_color", Color("aed581"))
	left.add_child(settings_lbl)

	var size_row := HBoxContainer.new()
	left.add_child(size_row)

	_spin_width = SpinBox.new()
	_spin_width.min_value = 10
	_spin_width.max_value = 100
	_spin_width.value = map_width
	_spin_width.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_width.tooltip_text = "Map width"
	size_row.add_child(_spin_width)

	_spin_height = SpinBox.new()
	_spin_height.min_value = 10
	_spin_height.max_value = 100
	_spin_height.value = map_height
	_spin_height.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_height.tooltip_text = "Map height"
	size_row.add_child(_spin_height)

	var btn_resize := Button.new()
	btn_resize.text = "Resize Grid"
	btn_resize.pressed.connect(_on_resize_grid_pressed)
	left.add_child(btn_resize)

	var brush_lbl := Label.new()
	brush_lbl.text = "Brush Type"
	left.add_child(brush_lbl)

	_brush_option = OptionButton.new()
	_brush_option.add_item("Land", 0)
	_brush_option.set_item_metadata(0, "land")
	_brush_option.add_item("Water", 1)
	_brush_option.set_item_metadata(1, "water")
	_brush_option.add_item("Rock", 2)
	_brush_option.set_item_metadata(2, "rock")
	_brush_option.add_item("Road", 3)
	_brush_option.set_item_metadata(3, "road")
	_brush_option.add_item("Structure", 4)
	_brush_option.set_item_metadata(4, "structure")
	_brush_option.item_selected.connect(_on_brush_selected)
	left.add_child(_brush_option)

	var btn_home := Button.new()
	btn_home.text = "Set Home (3x3)"
	btn_home.pressed.connect(_on_set_home_tool_pressed)
	left.add_child(btn_home)

	var btn_save := Button.new()
	btn_save.text = "Save Map"
	btn_save.pressed.connect(_on_save_grid_pressed)
	left.add_child(btn_save)

	var hint := Label.new()
	hint.text = "LMB: paint · Set Home: click 3×3 of Structure tiles · RMB: soil stats"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	left.add_child(hint)

	_map_status_label = Label.new()
	_map_status_label.text = ""
	_map_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_status_label.add_theme_font_size_override("font_size", 12)
	_map_status_label.add_theme_color_override("font_color", Color(0.55, 0.75, 0.55))
	left.add_child(_map_status_label)


func _build_center_viewport(parent: HBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)

	_grid_canvas = MapGridCanvas.new()
	_grid_canvas.name = "grid_canvas"
	_grid_canvas.editor = self
	_grid_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_canvas.gui_input.connect(_on_grid_canvas_gui_input)
	scroll.add_child(_grid_canvas)
	_update_canvas_size()


func _build_right_inspector(parent: HBoxContainer) -> void:
	_soil_inspector = VBoxContainer.new()
	_soil_inspector.name = "soil_inspector"
	_soil_inspector.custom_minimum_size = Vector2(220, 0)
	_soil_inspector.visible = false
	_soil_inspector.add_theme_constant_override("separation", 6)
	parent.add_child(_soil_inspector)

	var title := Label.new()
	title.text = "Soil Inspector"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("81d4fa"))
	_soil_inspector.add_child(title)

	var coord_lbl := Label.new()
	coord_lbl.name = "coord_label"
	coord_lbl.text = "Cell: —"
	_soil_inspector.add_child(coord_lbl)

	for stat_key in ["moisture", "nitrogen", "minerals", "toxicity", "structure"]:
		_soil_spins[stat_key] = _add_soil_stat_row(stat_key.capitalize(), stat_key)


func _add_soil_stat_row(label_text: String, stat_key: String) -> SpinBox:
	var row := HBoxContainer.new()
	_soil_inspector.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(72, 0)
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 10.0
	spin.step = 0.1
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float) -> void: _on_soil_stat_changed(stat_key, v))
	row.add_child(spin)
	return spin


func _default_cell() -> Dictionary:
	return {
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
	}


func _initialise_grid() -> void:
	grid_data.clear()
	for x in range(map_width):
		var column: Array = []
		for y in range(map_height):
			column.append(_default_cell().duplicate(true))
		grid_data.append(column)
	farmhouse_pos = Vector2i(-1, -1)
	inspected_cell = Vector2i(-1, -1)
	_queue_grid_redraw()


func _on_resize_grid_pressed() -> void:
	map_width = int(_spin_width.value)
	map_height = int(_spin_height.value)
	_initialise_grid()


func _on_brush_selected(_idx: int) -> void:
	var meta: Variant = _brush_option.get_selected_metadata()
	_brush_land = str(meta) if meta != null else "land"
	active_tool = "brush"
	_show_map_hint("Brush: %s" % _brush_land_id(), false)


func _on_set_home_tool_pressed() -> void:
	active_tool = "farmhouse"
	_show_map_hint("Click top-left of a 3×3 Structure footprint.", false)


func _brush_land_id() -> String:
	var meta: Variant = _brush_option.get_selected_metadata()
	return str(meta) if meta != null else _brush_land


func _grid_pos_from_local(local_pos: Vector2) -> Vector2i:
	return Vector2i(int(local_pos.x / cell_size), int(local_pos.y / cell_size))


func _grid_pos_in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.y >= 0 and grid_pos.x < map_width and grid_pos.y < map_height


func _on_grid_canvas_gui_input(event: InputEvent) -> void:
	var local_pos := Vector2.ZERO
	if event is InputEventMouseButton:
		local_pos = (event as InputEventMouseButton).position
	elif event is InputEventMouseMotion:
		local_pos = (event as InputEventMouseMotion).position

	var grid_pos := _grid_pos_from_local(local_pos)
	if not _grid_pos_in_bounds(grid_pos):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				_is_painting = false
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_handle_canvas_click(grid_pos, false)
			else:
				_is_painting = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_canvas_click(grid_pos, true)
	elif event is InputEventMouseMotion and _is_painting and active_tool == "brush":
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_handle_canvas_click(grid_pos, false)


func _handle_canvas_click(grid_pos: Vector2i, is_right_click: bool) -> void:
	if not _grid_pos_in_bounds(grid_pos):
		return

	if is_right_click:
		_inspect_cell(grid_pos)
		return

	if active_tool == "brush":
		_is_painting = true
		_paint_terrain(grid_pos)
		return

	if active_tool == "farmhouse":
		_try_set_farmhouse(grid_pos)
		return


func _inspect_cell(grid_pos: Vector2i) -> void:
	inspected_cell = grid_pos
	_soil_inspector.visible = true
	var coord_lbl: Label = _soil_inspector.get_node_or_null("coord_label") as Label
	if coord_lbl:
		coord_lbl.text = "Cell: (%d, %d)" % [grid_pos.x, grid_pos.y]
	_sync_inspector_from_cell(grid_data[grid_pos.x][grid_pos.y])
	_queue_grid_redraw()


func _paint_terrain(grid_pos: Vector2i) -> void:
	if not _grid_pos_in_bounds(grid_pos):
		return
	var cell: Dictionary = grid_data[grid_pos.x][grid_pos.y]
	cell["land"] = _brush_land_id()
	if cell["land"] == "road":
		cell["has_path"] = true
	else:
		cell["has_path"] = false
	_queue_grid_redraw()


func _try_set_farmhouse(origin: Vector2i) -> void:
	if active_tool != "farmhouse":
		return
	if origin.x + 2 >= map_width or origin.y + 2 >= map_height:
		_show_map_hint("3×3 home area must fit inside the map.")
		return
	for hx in range(3):
		for hy in range(3):
			var c: Dictionary = grid_data[origin.x + hx][origin.y + hy]
			if str(c.get("land", "")) != "structure":
				_show_map_hint("Home footprint must be 3×3 Structure tiles.")
				return
	farmhouse_pos = origin
	active_tool = "brush"
	_show_map_hint("Home set at (%d, %d)." % [origin.x, origin.y], false)
	_queue_grid_redraw()


func _sync_inspector_from_cell(cell: Dictionary) -> void:
	_inspector_syncing = true
	for stat_key in _soil_spins.keys():
		var spin: SpinBox = _soil_spins[stat_key]
		spin.value = float(cell.get(stat_key, 0.0))
	_inspector_syncing = false


func _on_soil_stat_changed(stat_key: String, value: float) -> void:
	if _inspector_syncing:
		return
	if inspected_cell.x < 0 or inspected_cell.y < 0:
		return
	if inspected_cell.x >= map_width or inspected_cell.y >= map_height:
		return
	grid_data[inspected_cell.x][inspected_cell.y][stat_key] = clampf(value, 0.0, 10.0)
	_queue_grid_redraw()


func _on_save_grid_pressed() -> void:
	if farmhouse_pos.x < 0 or farmhouse_pos.y < 0:
		_show_warning("Set a 3×3 home footprint before saving.")
		return
	var save_path := SAVE_PATH
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://campaigns/custom/"))
	var save_data: Dictionary = {
		"width": map_width,
		"height": map_height,
		"farmhouse_pos": {"x": farmhouse_pos.x, "y": farmhouse_pos.y},
		"grid_data": grid_data,
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		print("Grid saved successfully to: ", save_path)
		_show_status("Saved to %s" % save_path)
	else:
		push_error("Failed to open file for writing: %s" % save_path)
		_show_warning("Could not write %s" % save_path)


## Call when the Map Editor tab becomes visible (Asset Hub). Safe on main menu — no UI popups.
func ensure_default_grid_loaded() -> void:
	if _saved_grid_load_attempted:
		return
	_saved_grid_load_attempted = true
	_try_load_saved_grid()


func _try_load_saved_grid() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	load_grid_from_file(SAVE_PATH)


func load_grid_from_file(path: String) -> bool:
	if path == "" or not FileAccess.file_exists(path):
		push_warning("Grid file not found: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Map Editor: could not read %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Map Editor: invalid campaign grid JSON: %s" % path)
		return false
	_apply_loaded_grid(parsed as Dictionary, path)
	return true


func _apply_loaded_grid(data: Dictionary, source_path: String = "") -> void:
	var w := int(data.get("width", map_width))
	var h := int(data.get("height", map_height))
	w = clampi(w, 10, 100)
	h = clampi(h, 10, 100)
	map_width = w
	map_height = h
	_spin_width.value = w
	_spin_height.value = h

	var raw_grid: Variant = data.get("grid_data", [])
	if typeof(raw_grid) != TYPE_ARRAY:
		return

	grid_data.clear()
	for x in range(map_width):
		var src_col: Variant = raw_grid[x] if x < raw_grid.size() else []
		var column: Array = []
		for y in range(map_height):
			if typeof(src_col) == TYPE_ARRAY and y < src_col.size() and typeof(src_col[y]) == TYPE_DICTIONARY:
				var cell: Dictionary = (src_col[y] as Dictionary).duplicate(true)
				column.append(cell)
			else:
				column.append(_default_cell().duplicate(true))
		grid_data.append(column)

	var fp: Variant = data.get("farmhouse_pos", {})
	if typeof(fp) == TYPE_DICTIONARY:
		farmhouse_pos = Vector2i(int(fp.get("x", -1)), int(fp.get("y", -1)))
	else:
		farmhouse_pos = Vector2i(-1, -1)

	_update_canvas_size()
	_queue_grid_redraw()
	var loaded_from := source_path if source_path != "" else SAVE_PATH
	_show_status("Loaded %s" % loaded_from)


func _update_canvas_size() -> void:
	_grid_canvas.custom_minimum_size = Vector2(map_width * cell_size, map_height * cell_size)
	_grid_canvas.size = _grid_canvas.custom_minimum_size


func _queue_grid_redraw() -> void:
	if is_instance_valid(_grid_canvas):
		_grid_canvas.queue_redraw()


func draw_grid(canvas: CanvasItem) -> void:
	if grid_data.is_empty():
		return
	for x in range(map_width):
		if x >= grid_data.size():
			break
		var column: Array = grid_data[x]
		for y in range(map_height):
			if y >= column.size():
				continue
			var cell: Dictionary = column[y]
			var land_id := str(cell.get("land", "land"))
			var fill: Color = LAND_COLORS.get(land_id, LAND_COLORS["land"]) as Color
			var rect := Rect2(x * cell_size, y * cell_size, cell_size, cell_size)
			canvas.draw_rect(rect, fill)
			canvas.draw_rect(rect, Color(0.0, 0.0, 0.0, 0.35), false, 1.0)

	if farmhouse_pos.x >= 0 and farmhouse_pos.y >= 0:
		var home_rect := Rect2(
			farmhouse_pos.x * cell_size,
			farmhouse_pos.y * cell_size,
			cell_size * 3,
			cell_size * 3
		)
		canvas.draw_rect(home_rect, Color(1.0, 0.84, 0.0, 0.2))
		canvas.draw_rect(home_rect, Color(1.0, 0.75, 0.1, 1.0), false, 3.0)

	if inspected_cell.x >= 0 and inspected_cell.y >= 0:
		var hi := Rect2(inspected_cell.x * cell_size, inspected_cell.y * cell_size, cell_size, cell_size)
		canvas.draw_rect(hi, Color(1.0, 1.0, 1.0, 0.35))
		canvas.draw_rect(hi, Color(1.0, 1.0, 1.0, 0.95), false, 2.0)


func _show_map_hint(message: String, is_error: bool = true) -> void:
	if is_instance_valid(_map_status_label):
		_map_status_label.text = message
		var color := Color(1.0, 0.55, 0.45) if is_error else Color(0.55, 0.78, 0.55)
		_map_status_label.add_theme_color_override("font_color", color)


func _show_warning(message: String) -> void:
	_show_map_hint(message, true)


func _show_status(message: String) -> void:
	_show_map_hint(message, false)
	print("MapEditor: ", message)


class MapGridCanvas extends Control:
	var editor: Node = null

	func _draw() -> void:
		if editor != null and editor.has_method("draw_grid"):
			editor.draw_grid(self)
