extends PanelContainer

signal close_requested

const DevSpreadsheet := preload("res://scripts/dev_spreadsheet.gd")
const PixelPainter := preload("res://scripts/ui_pixel_painter.gd")
const MapEditor := preload("res://scripts/ui_map_editor.gd")
const PlantData := preload("res://data/data_plants.gd")

var SCAN_ROOTS = [
	"user://databases/",
	"user://audio/",
	"user://campaigns/",
]

var FILE_EXTENSIONS = [
	".csv", ".png", ".mp3", ".ogg", ".json",
]

const SPRITE_DIR := "user://databases/sprites/"

const TAB_ART := "art"
const TAB_DATA := "data"
const TAB_AUDIO := "audio"
const TAB_MAP := "map"

const TEXT_PRIMARY := Color(0.12, 0.12, 0.14)
const TEXT_MUTED := Color(0.38, 0.38, 0.42)

var current_inspected_id: String = ""
var _active_tab: String = TAB_DATA
var _view_mode: String = "list"
var _sort_column: int = 0
var _sort_ascending: bool = true

var _file_tree: Tree
var _icon_grid: ItemList
var _files_label: Label
var _left_panel: PanelContainer
var _viewport: MarginContainer
var _right_panel: PanelContainer
var _spreadsheet: PanelContainer
var _painter: PanelContainer
var _map_editor: PanelContainer
var _tab_buttons: Dictionary = {}
var _view_buttons: Dictionary = {}
var _fallback_icons: Dictionary = {}

var inspector_title: Label
var inspector_preview: TextureRect
var inspector_status: Label
var inspector_action_btn: Button

var _inspector_has_sprite: bool = false
var _inspector_sprite_path: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	z_index = 400

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.95, 0.95, 0.95)
	add_theme_stylebox_override("panel", bg_style)

	var panel_style := _make_panel_style()

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root_vbox.add_child(header)

	var title := Label.new()
	title.text = "Asset Manager"
	title.custom_minimum_size = Vector2(180, 0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", TEXT_PRIMARY)
	header.add_child(title)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 6)
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tab_bar)

	for tab_def in [
		[TAB_ART, "Art"],
		[TAB_DATA, "Data"],
		[TAB_AUDIO, "Audio"],
		[TAB_MAP, "Map Editor"],
	]:
		var tab_id: String = tab_def[0]
		var tab_label: String = tab_def[1]
		var btn := Button.new()
		btn.text = tab_label
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_tab_button_pressed.bind(tab_id))
		tab_bar.add_child(btn)
		_tab_buttons[tab_id] = btn

	var btn_close := Button.new()
	btn_close.text = "Close"
	btn_close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(btn_close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root_vbox.add_child(body)

	# --- Left: file explorer ---
	_left_panel = PanelContainer.new()
	_left_panel.custom_minimum_size = Vector2(320, 0)
	_left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_panel.add_theme_stylebox_override("panel", panel_style)
	body.add_child(_left_panel)

	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left.add_theme_constant_override("margin_left", 8)
	left.add_theme_constant_override("margin_right", 8)
	left.add_theme_constant_override("margin_top", 8)
	left.add_theme_constant_override("margin_bottom", 8)
	left.add_theme_constant_override("separation", 8)
	_left_panel.add_child(left)

	_files_label = Label.new()
	_files_label.text = "Data Files"
	_files_label.add_theme_font_size_override("font_size", 16)
	_files_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	left.add_child(_files_label)

	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 6)
	left.add_child(view_row)

	var view_group := ButtonGroup.new()
	for view_def in [["list", "List View"], ["icon", "Icon View"]]:
		var view_id: String = view_def[0]
		var view_btn := Button.new()
		view_btn.text = view_def[1]
		view_btn.toggle_mode = true
		view_btn.button_group = view_group
		view_btn.focus_mode = Control.FOCUS_NONE
		view_btn.button_pressed = view_id == "list"
		view_btn.pressed.connect(_on_view_button_pressed.bind(view_id))
		view_row.add_child(view_btn)
		_view_buttons[view_id] = view_btn

	_file_tree = Tree.new()
	_file_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_file_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_tree.hide_root = true
	_file_tree.column_titles_visible = true
	_file_tree.columns = 3
	_file_tree.set_column_title(0, "Name")
	_file_tree.set_column_title(1, "Type")
	_file_tree.set_column_title(2, "Date")
	_file_tree.set_column_expand(0, true)
	_file_tree.item_selected.connect(_on_file_tree_item_selected)
	_file_tree.column_title_clicked.connect(_on_tree_column_title_clicked)
	left.add_child(_file_tree)

	_icon_grid = ItemList.new()
	_icon_grid.name = "icon_grid"
	_icon_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_icon_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon_grid.max_columns = 0
	_icon_grid.icon_mode = ItemList.ICON_MODE_TOP
	_icon_grid.fixed_icon_size = Vector2(64, 64)
	_icon_grid.same_column_width = true
	_icon_grid.item_selected.connect(_on_icon_selected)
	_icon_grid.hide()
	left.add_child(_icon_grid)

	# --- Centre: editors ---
	_viewport = MarginContainer.new()
	_viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport.add_theme_constant_override("margin_left", 4)
	_viewport.add_theme_constant_override("margin_right", 4)
	_viewport.add_theme_constant_override("margin_top", 4)
	_viewport.add_theme_constant_override("margin_bottom", 4)
	body.add_child(_viewport)

	var center_panel := PanelContainer.new()
	center_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_panel.add_theme_stylebox_override("panel", panel_style)
	_viewport.add_child(center_panel)

	var center_inner := MarginContainer.new()
	center_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_inner.add_theme_constant_override("margin_left", 6)
	center_inner.add_theme_constant_override("margin_right", 6)
	center_inner.add_theme_constant_override("margin_top", 6)
	center_inner.add_theme_constant_override("margin_bottom", 6)
	center_panel.add_child(center_inner)

	_spreadsheet = DevSpreadsheet.new()
	_spreadsheet.set_embedded_in_hub(true)
	_spreadsheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_spreadsheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spreadsheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spreadsheet.row_selected.connect(_on_spreadsheet_row_selected)
	_spreadsheet.paint_sprite_requested.connect(_on_paint_sprite_from_spreadsheet)
	center_inner.add_child(_spreadsheet)
	_spreadsheet.hide()

	_painter = PixelPainter.new()
	_painter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_painter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_painter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_painter.sprite_updated.connect(_on_painter_sprite_updated)
	center_inner.add_child(_painter)
	_painter.hide()

	_map_editor = MapEditor.new()
	_map_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_inner.add_child(_map_editor)
	_map_editor.hide()

	# --- Right: asset linker inspector ---
	_right_panel = PanelContainer.new()
	_right_panel.custom_minimum_size = Vector2(250, 0)
	_right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_panel.add_theme_stylebox_override("panel", panel_style)
	body.add_child(_right_panel)

	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	right.add_theme_constant_override("margin_left", 10)
	right.add_theme_constant_override("margin_right", 10)
	right.add_theme_constant_override("margin_top", 10)
	right.add_theme_constant_override("margin_bottom", 10)
	right.add_theme_constant_override("separation", 10)
	_right_panel.add_child(right)

	var insp_header := Label.new()
	insp_header.text = "Asset Inspector"
	insp_header.add_theme_font_size_override("font_size", 16)
	insp_header.add_theme_color_override("font_color", TEXT_PRIMARY)
	right.add_child(insp_header)

	inspector_title = Label.new()
	inspector_title.name = "inspector_title"
	inspector_title.text = "Nothing Selected"
	inspector_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector_title.add_theme_color_override("font_color", TEXT_PRIMARY)
	right.add_child(inspector_title)

	inspector_preview = TextureRect.new()
	inspector_preview.name = "inspector_preview"
	inspector_preview.custom_minimum_size = Vector2(100, 100)
	inspector_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inspector_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(inspector_preview)

	inspector_status = Label.new()
	inspector_status.name = "inspector_status"
	inspector_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector_status.add_theme_color_override("font_color", TEXT_MUTED)
	right.add_child(inspector_status)

	inspector_action_btn = Button.new()
	inspector_action_btn.name = "inspector_action_btn"
	inspector_action_btn.text = "Draw Sprite"
	inspector_action_btn.visible = false
	inspector_action_btn.pressed.connect(_on_inspector_action_pressed)
	right.add_child(inspector_action_btn)

	_on_tab_changed(TAB_DATA)


func _make_panel_style() -> StyleBoxFlat:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.98, 0.98, 0.98)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.85, 0.85, 0.85)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	return panel_style


func _on_view_button_pressed(view_id: String) -> void:
	_set_view_mode(view_id)


func _set_view_mode(view_id: String) -> void:
	_view_mode = view_id
	for id in _view_buttons.keys():
		var btn: Button = _view_buttons[id]
		btn.button_pressed = id == view_id
	_file_tree.visible = view_id == "list"
	_icon_grid.visible = view_id == "icon"


func _on_tab_button_pressed(tab_id: String) -> void:
	_on_tab_changed(tab_id)


func _on_tab_changed(tab_name: String) -> void:
	_active_tab = tab_name
	for id in _tab_buttons.keys():
		var btn: Button = _tab_buttons[id]
		btn.button_pressed = id == tab_name

	_spreadsheet.hide()
	_painter.hide()
	_map_editor.hide()

	match tab_name:
		TAB_ART:
			_files_label.text = "Sprite Files"
			_painter.show()
			_reset_inspector_for_file("Art", "Select a .png to edit sprites.")
		TAB_DATA:
			_files_label.text = "Data Files"
			_spreadsheet.show()
			_reset_inspector_for_file("Data", "Select a .csv database to edit plant rows.")
		TAB_AUDIO:
			_files_label.text = "Audio Files"
			_reset_inspector_for_file("Audio", "Select .mp3 or .ogg for custom radio stations.")
		TAB_MAP:
			_files_label.text = "Campaign Grids"
			_map_editor.show()
			if _map_editor.has_method("ensure_default_grid_loaded"):
				_map_editor.ensure_default_grid_loaded()
			_reset_inspector_for_file(
				"Map Editor",
				"Open starting_grid.json or paint a new map. Save writes to user://campaigns/custom/."
			)
		_:
			pass

	_populate_file_tree()


func _on_tree_column_title_clicked(column: int) -> void:
	if column == _sort_column:
		_sort_ascending = not _sort_ascending
	else:
		_sort_column = column
		_sort_ascending = true
	_populate_file_tree()


func _populate_file_tree() -> void:
	_file_tree.clear()
	_icon_grid.clear()
	var root_item := _file_tree.create_item()
	root_item.set_text(0, "Assets")
	root_item.set_metadata(0, "user://")
	for scan_path in SCAN_ROOTS:
		_scan_directory(scan_path, root_item)
	root_item.set_collapsed(false)


func _scan_directory(dir_path: String, parent_item: TreeItem) -> void:
	if dir_path == "":
		return
	DirAccess.make_dir_recursive_absolute(dir_path)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var err := dir.list_dir_begin()
	if err != OK:
		dir.list_dir_end()
		return
	var entry := dir.get_next()
	var dir_entries: Array[Dictionary] = []
	var file_entries: Array[Dictionary] = []
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full_path := dir_path.path_join(entry)
		if dir.current_is_dir():
			var dir_unix := FileAccess.get_modified_time(full_path) if FileAccess.file_exists(full_path) else 0
			dir_entries.append({
				"name": entry,
				"path": full_path,
				"type": "Folder",
				"unix_time": dir_unix,
				"is_dir": true,
			})
		elif _file_visible_for_tab(entry):
			var file_unix := FileAccess.get_modified_time(full_path)
			file_entries.append({
				"name": entry,
				"path": full_path,
				"type": _infer_asset_type(full_path, entry),
				"unix_time": file_unix,
				"is_dir": false,
			})
		entry = dir.get_next()
	dir.list_dir_end()

	_sort_entries(dir_entries)
	_sort_entries(file_entries)

	for dir_entry in dir_entries:
		var folder_item := _file_tree.create_item(parent_item)
		_apply_tree_row(folder_item, dir_entry)
		_scan_directory(str(dir_entry["path"]), folder_item)

	for file_entry in file_entries:
		var file_item := _file_tree.create_item(parent_item)
		_apply_tree_row(file_item, file_entry)
		_add_icon_grid_item(file_entry)


func _sort_entries(entries: Array) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var av: Variant = _entry_sort_value(a, _sort_column)
		var bv: Variant = _entry_sort_value(b, _sort_column)
		if av == bv:
			var an: String = str(a.get("name", ""))
			var bn: String = str(b.get("name", ""))
			return an < bn if _sort_ascending else an > bn
		if av is String and bv is String:
			return av < bv if _sort_ascending else av > bv
		return int(av) < int(bv) if _sort_ascending else int(av) > int(bv)
	)


func _entry_sort_value(entry: Dictionary, column: int) -> Variant:
	match column:
		1:
			return str(entry.get("type", "")).to_lower()
		2:
			return int(entry.get("unix_time", 0))
		_:
			return str(entry.get("name", "")).to_lower()


func _apply_tree_row(item: TreeItem, entry: Dictionary) -> void:
	var path: String = str(entry.get("path", ""))
	item.set_text(0, str(entry.get("name", "")))
	item.set_text(1, str(entry.get("type", "")))
	item.set_text(2, _format_file_date(int(entry.get("unix_time", 0))))
	item.set_metadata(0, path)


func _format_file_date(unix_time: int) -> String:
	if unix_time <= 0:
		return "—"
	return Time.get_datetime_string_from_unix_time(unix_time, false)


func _infer_asset_type(path: String, file_name: String) -> String:
	var lower_path := path.to_lower()
	var lower_name := file_name.to_lower()
	if lower_name.ends_with(".json") or "campaigns" in lower_path:
		return "Map"
	if lower_name.ends_with(".csv"):
		return "Data"
	if lower_name.ends_with(".png") or "/sprites/" in lower_path:
		return "Art"
	if lower_name.ends_with(".mp3") or lower_name.ends_with(".ogg") or "/audio/" in lower_path:
		return "Audio"
	return "File"


func _add_icon_grid_item(entry: Dictionary) -> void:
	var path: String = str(entry.get("path", ""))
	var file_name: String = str(entry.get("name", ""))
	var idx := _icon_grid.add_item(file_name)
	_icon_grid.set_item_metadata(idx, path)
	var lower := file_name.to_lower()
	if lower.ends_with(".png"):
		var tex := _load_file_icon_texture(path)
		if tex:
			_icon_grid.set_item_icon(idx, tex)
	else:
		var type_key := str(entry.get("type", "File"))
		_icon_grid.set_item_icon(idx, _fallback_icon_for_type(type_key))


func _load_file_icon_texture(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null:
		return null
	if img.get_width() != 64 or img.get_height() != 64:
		img.resize(64, 64, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


func _fallback_icon_for_type(type_key: String) -> Texture2D:
	if _fallback_icons.has(type_key):
		return _fallback_icons[type_key]
	var fill := Color(0.55, 0.55, 0.58)
	match type_key:
		"Art":
			fill = Color(0.45, 0.72, 0.42)
		"Data":
			fill = Color(0.35, 0.55, 0.85)
		"Audio":
			fill = Color(0.75, 0.45, 0.82)
		"Map":
			fill = Color(0.92, 0.68, 0.28)
		"Folder":
			fill = Color(0.7, 0.7, 0.74)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	var tex := ImageTexture.create_from_image(img)
	_fallback_icons[type_key] = tex
	return tex


func _file_visible_for_tab(file_name: String) -> bool:
	var lower := file_name.to_lower()
	match _active_tab:
		TAB_ART:
			return lower.ends_with(".png")
		TAB_DATA:
			return lower.ends_with(".csv")
		TAB_AUDIO:
			return lower.ends_with(".mp3") or lower.ends_with(".ogg")
		TAB_MAP:
			return lower.ends_with(".json")
		_:
			return _is_supported_asset(file_name)


func _is_supported_asset(file_name: String) -> bool:
	var lower := file_name.to_lower()
	for ext in FILE_EXTENSIONS:
		if lower.ends_with(ext):
			return true
	return false


func _sprite_path_for_plant(id: String) -> String:
	if id == "":
		return ""
	var direct := SPRITE_DIR + id + ".png"
	if FileAccess.file_exists(direct):
		return direct
	var prefixed := SPRITE_DIR + "plant_" + id + ".png"
	if FileAccess.file_exists(prefixed):
		return prefixed
	if PlantData.DATA.has(id):
		var custom := str(PlantData.DATA[id].get("custom_sprite_path", ""))
		if custom != "" and FileAccess.file_exists(custom):
			return custom
	return ""


func _load_inspector_preview(path: String) -> void:
	inspector_preview.texture = null
	if path == "" or not FileAccess.file_exists(path):
		return
	var img := Image.load_from_file(path)
	if img == null:
		return
	var tex := ImageTexture.create_from_image(img)
	inspector_preview.texture = tex


func _reset_inspector_for_file(title_text: String, status_text: String) -> void:
	current_inspected_id = ""
	_inspector_has_sprite = false
	_inspector_sprite_path = ""
	inspector_title.text = title_text
	inspector_preview.texture = null
	inspector_status.text = status_text
	inspector_action_btn.visible = false


func _on_spreadsheet_row_selected(id: String) -> void:
	current_inspected_id = id
	inspector_title.text = "Target: " + id
	inspector_action_btn.visible = true

	var path := _sprite_path_for_plant(id)
	if path != "":
		_inspector_has_sprite = true
		_inspector_sprite_path = path
		_load_inspector_preview(path)
		inspector_status.text = "Status: Linked ✅"
		inspector_action_btn.text = "Edit Sprite"
	else:
		_inspector_has_sprite = false
		_inspector_sprite_path = ""
		inspector_preview.texture = null
		inspector_status.text = "Status: Missing Art ❌"
		inspector_action_btn.text = "Draw Sprite"


func _on_inspector_action_pressed() -> void:
	if current_inspected_id == "":
		return
	_on_tab_changed(TAB_ART)
	_open_painter_for_current_inspected(_inspector_has_sprite)


func _open_painter_for_current_inspected(load_existing: bool) -> void:
	if current_inspected_id == "":
		return
	_spreadsheet.hide()
	_map_editor.hide()
	_painter.show()
	_painter.setup_for_target_id(current_inspected_id)
	if load_existing and _inspector_sprite_path != "":
		_painter.load_sprite_from_path(_inspector_sprite_path)


func _on_file_tree_item_selected() -> void:
	var item := _file_tree.get_selected()
	if item == null:
		return
	var path: Variant = item.get_metadata(0)
	_open_asset_path(str(path))


func _on_icon_selected(index: int) -> void:
	if index < 0:
		return
	var path: Variant = _icon_grid.get_item_metadata(index)
	_open_asset_path(str(path))


func _open_asset_path(file_path: String) -> void:
	if file_path == "":
		return
	if not FileAccess.file_exists(file_path) and not DirAccess.dir_exists_absolute(file_path):
		return
	if DirAccess.dir_exists_absolute(file_path):
		_reset_inspector_for_file("Folder: %s" % file_path.get_file(), file_path)
		return

	var lower := file_path.to_lower()
	if lower.ends_with(".json"):
		_on_tab_changed(TAB_MAP)
		_map_editor.load_grid_from_file(file_path)
		_reset_inspector_for_file(
			"Grid: %s" % file_path.get_file(),
			"Campaign starting grid — edit in Map Editor, then save."
		)
		return

	if lower.ends_with(".csv"):
		_on_tab_changed(TAB_DATA)
		_spreadsheet.load_database_csv(file_path)
		_reset_inspector_for_file(
			"Database: %s" % file_path.get_file(),
			"Select a plant row to inspect and link sprites."
		)
		return

	if lower.ends_with(".png"):
		_on_tab_changed(TAB_ART)
		_painter.load_sprite_from_path(file_path)
		_reset_inspector_for_file(
			"Sprite: %s" % file_path.get_file(),
			file_path
		)
		return

	if lower.ends_with(".mp3") or lower.ends_with(".ogg"):
		_on_tab_changed(TAB_AUDIO)
		_reset_inspector_for_file(
			"Audio: %s" % file_path.get_file(),
			"Use Sound Settings → Custom Radio for station playback."
		)
		return

	_reset_inspector_for_file("Selected: %s" % file_path.get_file(), file_path)


func _on_paint_sprite_from_spreadsheet(plant_id: String) -> void:
	current_inspected_id = plant_id
	_on_spreadsheet_row_selected(plant_id)
	_on_tab_changed(TAB_ART)
	_open_painter_for_current_inspected(_inspector_has_sprite)


func _on_painter_sprite_updated(plant_id: String) -> void:
	if is_instance_valid(_spreadsheet):
		_spreadsheet._on_sprite_updated(plant_id)
	if plant_id == current_inspected_id:
		_on_spreadsheet_row_selected(plant_id)
