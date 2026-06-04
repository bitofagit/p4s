extends PanelContainer

signal back_requested
signal paint_sprite_requested(plant_id: String)
signal row_selected(item_id: String)

const PlantData := preload("res://data/data_plants.gd")

const COL_KEYS: Array[String] = [
	"name", "layer", "cost", "nitrogen_delta", "moisture_delta", "yield_val", "energy_yield", "repels_pests",
]
const SPRITE_COL: int = 8

var tree: Tree
var _status_label: Label
var _export_dialog: FileDialog
var _close_sheet: Button
var _btn_back: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	z_index = 250

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	_close_sheet = Button.new()
	_close_sheet.text = "×"
	_close_sheet.flat = true
	_close_sheet.focus_mode = Control.FOCUS_NONE
	_close_sheet.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close_sheet.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_close_sheet.add_theme_color_override("font_hover_color", Color(0.9, 0.2, 0.2))
	_close_sheet.pressed.connect(_close_panel)
	vbox.add_child(_close_sheet)

	_btn_back = Button.new()
	_btn_back.text = "Back to Main Menu"
	_btn_back.pressed.connect(_close_panel)
	vbox.add_child(_btn_back)

	# --- HEADER ---
	var header = HBoxContainer.new()
	vbox.add_child(header)

	var title = Label.new()
	title.text = "DEVELOPER DATABASE: Plant Master List (Editable)"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("aed581"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	# --- TOOLBAR ---
	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	vbox.add_child(toolbar)

	var btn_reload = Button.new()
	btn_reload.text = "Reload Default V3 Database"
	btn_reload.pressed.connect(_on_reload_default)
	toolbar.add_child(btn_reload)

	var btn_save = Button.new()
	btn_save.text = "Save to Local Library"
	btn_save.pressed.connect(_on_save_local)
	toolbar.add_child(btn_save)

	var btn_export = Button.new()
	btn_export.text = "Export CSV for Sharing"
	btn_export.pressed.connect(_on_export_pressed)
	toolbar.add_child(btn_export)

	_status_label = Label.new()
	_status_label.text = "Double-click a cell to edit. Click Paint in Sprite column to open the pixel editor."
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.65))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_status_label)

	# --- SPREADSHEET (TREE NODE) ---
	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.columns = COL_KEYS.size() + 1
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.item_edited.connect(_on_tree_item_edited)
	tree.button_clicked.connect(_on_tree_button_clicked)
	tree.item_selected.connect(_on_tree_item_selected)

	var cols = ["Name", "Layer", "Cost (£)", "Nitrogen (N)", "Moisture (M)", "Yield", "Energy", "Roles / Pests", "Sprite"]
	for i in range(cols.size()):
		tree.set_column_title(i, cols[i])
		if i > 1 and i < 7:
			tree.set_column_expand(i, false)
			tree.set_column_custom_minimum_width(i, 100)
	tree.set_column_custom_minimum_width(SPRITE_COL, 72)

	vbox.add_child(tree)

	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.add_filter("*.csv", "CSV Files")
	_export_dialog.title = "Export Plant Database"
	_export_dialog.current_file = "plants_custom.csv"
	_export_dialog.file_selected.connect(_on_export_file_selected)
	add_child(_export_dialog)

	_refresh_tree()


func set_embedded_in_hub(is_embedded: bool) -> void:
	if is_instance_valid(_close_sheet):
		_close_sheet.visible = not is_embedded
	if is_instance_valid(_btn_back):
		_btn_back.visible = not is_embedded


func load_database_csv(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		_set_status("CSV not found: %s" % path)
		return
	PlantData.load_custom_database(path)
	_refresh_tree()
	_set_status("Loaded database: %s (%d plants)" % [path.get_file(), PlantData.DATA.size()])


func _close_panel() -> void:
	hide()
	back_requested.emit()


func _refresh_tree() -> void:
	tree.clear()
	_populate_data()


func _populate_data() -> void:
	PlantData.get_plant_data("") # Ensures plant DB is registered

	var root = tree.create_item()

	for key in PlantData.DATA.keys():
		var p: Dictionary = PlantData.DATA[key]
		var item := tree.create_item(root)
		item.set_metadata(0, key)

		item.set_text(0, str(p.get("name", key)))
		item.set_text(1, str(p.get("layer", "")).capitalize())
		item.set_text(2, str(p.get("cost", "0")))
		item.set_text(3, str(p.get("nitrogen_delta", "0")))
		item.set_text(4, str(p.get("moisture_delta", "0")))
		item.set_text(5, str(p.get("yield_val", "0")))
		item.set_text(6, str(p.get("energy_yield", "0")))
		var rp = p.get("repels_pests", [])
		if rp is Array:
			item.set_text(7, ", ".join(PackedStringArray(rp)) if rp.size() > 0 else "None")
		else:
			item.set_text(7, str(rp if rp != null else "None"))

		var has_sprite := str(p.get("custom_sprite_path", "")) != ""
		item.set_text(SPRITE_COL, "Custom" if has_sprite else "—")
		item.add_button(SPRITE_COL, preload("res://icon.svg"), 0, false, "Paint Sprite")

		for col in range(COL_KEYS.size()):
			item.set_editable(col, true)
		item.set_editable(SPRITE_COL, false)


func _on_tree_item_selected() -> void:
	var selected := tree.get_selected()
	if selected == null:
		return
	var item_id := str(selected.get_metadata(0))
	if item_id == "":
		item_id = selected.get_text(0)
	if item_id == "":
		return
	row_selected.emit(item_id)


func _on_tree_button_clicked(item: TreeItem, column: int, _id: int, _mouse_button_index: int) -> void:
	if column != SPRITE_COL or item == null:
		return
	var plant_id := str(item.get_metadata(0))
	if plant_id == "":
		return
	paint_sprite_requested.emit(plant_id)


func _on_sprite_updated(plant_id: String) -> void:
	_refresh_tree()
	_set_status("Sprite saved for '%s' → user://databases/sprites/%s.png" % [plant_id, plant_id])
	var map := get_tree().get_first_node_in_group("map")
	if map == null:
		return
	var path := str(PlantData.DATA.get(plant_id, {}).get("custom_sprite_path", ""))
	if path != "" and map.has_method("register_custom_plant_sprite"):
		map.register_custom_plant_sprite(plant_id, path)
		if map.has_method("update_visuals"):
			map.update_visuals()


func _on_tree_item_edited() -> void:
	var item: TreeItem = tree.get_edited()
	if item == null:
		return
	var col: int = tree.get_edited_column()
	if col < 0 or col >= COL_KEYS.size():
		return

	var plant_id: String = str(item.get_metadata(0))
	if plant_id == "" or not PlantData.DATA.has(plant_id):
		return

	var field_key: String = COL_KEYS[col]
	var raw_text: String = item.get_text(col)
	var parsed: Variant = _coerce_edited_value(field_key, raw_text)

	var row: Dictionary = PlantData.DATA[plant_id]
	row[field_key] = parsed

	item.set_text(col, _format_cell_for_tree(field_key, parsed))


func _coerce_edited_value(field_key: String, raw_text: String) -> Variant:
	if field_key == "repels_pests":
		var trimmed := raw_text.strip_edges()
		if trimmed == "" or trimmed.to_lower() == "none":
			return []
		var parts: Array = []
		for segment in trimmed.split(","):
			var s := str(segment).strip_edges()
			if s != "":
				parts.append(s)
		return parts
	if field_key == "layer":
		return raw_text.strip_edges().to_lower()
	return PlantData.coerce_field(field_key, raw_text.strip_edges())


func _format_cell_for_tree(field_key: String, value: Variant) -> String:
	if field_key == "repels_pests":
		if value is Array:
			return ", ".join(PackedStringArray(value)) if value.size() > 0 else "None"
		return str(value)
	if field_key == "layer":
		return str(value).capitalize()
	return str(value)


func _set_status(msg: String) -> void:
	_status_label.text = msg


func _on_reload_default() -> void:
	PlantData.reload_default_database()
	_refresh_tree()
	_set_status("Reloaded default V3 database from res://data/plants_v3.csv")


func _on_save_local() -> void:
	var dir_path := "user://databases"
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			_set_status("Failed to create databases folder (error %d)" % err)
			return
	var save_path := PlantData.CUSTOM_PLANTS_PATH
	if PlantData.export_to_csv(save_path, PlantData.DATA):
		_set_status("Saved %d plants to %s" % [PlantData.DATA.size(), save_path])
	else:
		_set_status("Save failed — see Godot Output for details")


func _on_export_pressed() -> void:
	_export_dialog.popup_centered_ratio(0.6)


func _on_export_file_selected(path: String) -> void:
	var export_path := path
	if not export_path.to_lower().ends_with(".csv"):
		export_path += ".csv"
	if PlantData.export_to_csv(export_path, PlantData.DATA):
		_set_status("Exported %d plants to: %s" % [PlantData.DATA.size(), export_path])
	else:
		_set_status("Export failed — see Godot Output for details")
