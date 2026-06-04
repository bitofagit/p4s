extends PanelContainer

signal sprite_updated(plant_id: String)

const PlantData := preload("res://data/data_plants.gd")
const SPRITE_DIR := "user://databases/sprites/"
const CANVAS_SIZES: Array[int] = [50, 100, 150, 200]
const DISPLAY_SIZE := Vector2(400, 400)
const FLOOD_FILL_MAX := 50000
const MAX_UNDO_STEPS := 20
const CATEGORY_LABELS: Array[String] = [
	"Plant", "Farmer/Worker", "Object/Structure", "Terrain",
]
const CATEGORY_PREFIXES: Array[String] = [
	"plant_", "farmer_", "object_", "terrain_",
]

var canvas_size: int = 50
## Set before `add_child()` when opening from the database editor; empty = new asset mode.
var target_id: String = ""
var current_tool: String = "pencil"
var brush_size: int = 1
var draw_start_pos: Vector2i = Vector2i(-1, -1)

var undo_history: Array[Image] = []
var selection_rect := Rect2i(-1, -1, 0, 0)
var floating_image: Image = null
var floating_pos := Vector2i.ZERO
var is_selecting := false
var is_dragging_floating := false

var image: Image
var texture: ImageTexture
var texture_rect: TextureRect
var selection_overlay: Control
var bg_checker: TextureRect
var color_picker: ColorPickerButton
var _toolbar: HBoxContainer
var _tool_group: ButtonGroup
var _brush_size_label: Label
var _brush_size_slider: HSlider
var _size_opt: OptionButton
var _bg_toggle_btn: Button
var _canvas_panel: PanelContainer
var _checker_tex: ImageTexture
var _solid_bg_tex: ImageTexture
var _bg_is_solid: bool = false
var _drawing: bool = false
var _last_drag_cell: Vector2i = Vector2i(-1, -1)
var _export_png_dialog: FileDialog
var _library_list: ItemList
var category_selector: OptionButton
var _filename_edit: LineEdit
var _status_label: Label
var _btn_apply_database: Button
var _current_filename: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(720, 520)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.06, 0.08, 1.0)
	add_theme_stylebox_override("panel", panel_style)

	_checker_tex = _make_checker_texture()
	_solid_bg_tex = _make_solid_texture(Color.WHITE)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 12)
	root.add_theme_constant_override("margin_right", 12)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_bottom", 12)
	add_child(root)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	root.add_child(main)

	var tools := VBoxContainer.new()
	tools.custom_minimum_size = Vector2(180, 0)
	tools.add_theme_constant_override("separation", 8)
	main.add_child(tools)

	var tools_title := Label.new()
	tools_title.text = "Tools"
	tools.add_theme_font_size_override("font_size", 18)
	tools.add_theme_color_override("font_color", Color("aed581"))
	tools.add_child(tools_title)

	color_picker = ColorPickerButton.new()
	color_picker.custom_minimum_size = Vector2(100, 40)
	color_picker.color = Color("4caf50")
	tools.add_child(color_picker)

	_tool_group = ButtonGroup.new()
	_toolbar = HBoxContainer.new()
	_toolbar.name = "toolbar"
	_toolbar.add_theme_constant_override("separation", 4)
	tools.add_child(_toolbar)

	var tool_defs: Array = [
		["✏️ Pencil", "pencil", true],
		["🧽 Eraser", "eraser", false],
		["🪣 Fill", "fill", false],
		["💧 Picker", "picker", false],
		["📏 Line", "line", false],
	]
	for tool_def in tool_defs:
		var btn := Button.new()
		btn.text = str(tool_def[0])
		btn.toggle_mode = true
		btn.button_group = _tool_group
		btn.focus_mode = Control.FOCUS_NONE
		btn.button_pressed = bool(tool_def[2])
		var tool_id: String = str(tool_def[1])
		btn.pressed.connect(_on_tool_button_pressed.bind(tool_id))
		_toolbar.add_child(btn)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	tools.add_child(size_row)

	_brush_size_label = Label.new()
	_brush_size_label.name = "brush_size_label"
	_brush_size_label.text = "Size: 1px"
	size_row.add_child(_brush_size_label)

	_brush_size_slider = HSlider.new()
	_brush_size_slider.name = "brush_size_slider"
	_brush_size_slider.min_value = 1.0
	_brush_size_slider.max_value = 10.0
	_brush_size_slider.step = 1.0
	_brush_size_slider.value = 1.0
	_brush_size_slider.custom_minimum_size.x = 100.0
	_brush_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brush_size_slider.value_changed.connect(_on_brush_size_changed)
	size_row.add_child(_brush_size_slider)

	_size_opt = _add_labeled_option(tools, "Canvas Size:", [
		["50 px", 50],
		["100 px", 100],
		["150 px", 150],
		["200 px", 200],
	])
	_size_opt.item_selected.connect(_on_canvas_size_selected)

	var btn_undo := Button.new()
	btn_undo.text = "Undo"
	btn_undo.pressed.connect(_on_undo_pressed)
	tools.add_child(btn_undo)

	_bg_toggle_btn = Button.new()
	_bg_toggle_btn.text = "Background: Transparent"
	_bg_toggle_btn.pressed.connect(_toggle_background)
	tools.add_child(_bg_toggle_btn)

	var btn_clear := Button.new()
	btn_clear.text = "Clear Canvas"
	btn_clear.pressed.connect(_clear_canvas)
	tools.add_child(btn_clear)

	_btn_apply_database = Button.new()
	_btn_apply_database.text = "Apply to Database"
	_btn_apply_database.pressed.connect(_on_apply_to_database)
	tools.add_child(_btn_apply_database)

	var btn_export := Button.new()
	btn_export.text = "Export PNG Copy…"
	btn_export.pressed.connect(func() -> void: _export_png_dialog.popup_centered_ratio(0.5))
	tools.add_child(btn_export)

	var hint := Label.new()
	hint.text = "Pencil/Eraser respect brush size. Picker samples a pixel colour. Undo ×20."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.55))
	tools.add_child(hint)

	var center_column := VBoxContainer.new()
	center_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_column.add_theme_constant_override("separation", 8)
	main.add_child(center_column)

	_canvas_panel = PanelContainer.new()
	_canvas_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas_panel.custom_minimum_size = DISPLAY_SIZE
	center_column.add_child(_canvas_panel)

	var save_toolbar := HBoxContainer.new()
	save_toolbar.add_theme_constant_override("separation", 8)
	var fn_lbl := Label.new()
	fn_lbl.text = "Filename:"
	save_toolbar.add_child(fn_lbl)
	var cat_lbl := Label.new()
	cat_lbl.text = "Category:"
	save_toolbar.add_child(cat_lbl)
	category_selector = OptionButton.new()
	for i in range(CATEGORY_LABELS.size()):
		category_selector.add_item(CATEGORY_LABELS[i], i)
	category_selector.custom_minimum_size = Vector2(140, 0)
	save_toolbar.add_child(category_selector)
	_filename_edit = LineEdit.new()
	_filename_edit.placeholder_text = "new_sprite"
	_filename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_toolbar.add_child(_filename_edit)
	var btn_save := Button.new()
	btn_save.text = "Save"
	btn_save.pressed.connect(func() -> void: _attempt_save(false))
	save_toolbar.add_child(btn_save)
	var btn_save_as := Button.new()
	btn_save_as.text = "Save As"
	btn_save_as.pressed.connect(func() -> void: _attempt_save(true))
	save_toolbar.add_child(btn_save_as)
	center_column.add_child(save_toolbar)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.65, 0.85, 0.65))
	center_column.add_child(_status_label)

	var library := VBoxContainer.new()
	library.custom_minimum_size = Vector2(160, 0)
	library.add_theme_constant_override("separation", 8)
	main.add_child(library)

	var lib_title := Label.new()
	lib_title.text = "Sprite Library"
	lib_title.add_theme_font_size_override("font_size", 16)
	lib_title.add_theme_color_override("font_color", Color("aed581"))
	library.add_child(lib_title)

	_library_list = ItemList.new()
	_library_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library_list.select_mode = ItemList.SELECT_SINGLE
	library.add_child(_library_list)

	var btn_load := Button.new()
	btn_load.text = "Load Selected"
	btn_load.pressed.connect(_on_load_selected)
	library.add_child(btn_load)

	var canvas_stack := Control.new()
	canvas_stack.custom_minimum_size = DISPLAY_SIZE
	canvas_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_stack.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_stack.gui_input.connect(_on_canvas_gui_input)
	_canvas_panel.add_child(canvas_stack)

	bg_checker = TextureRect.new()
	bg_checker.name = "BgChecker"
	bg_checker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_checker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg_checker.stretch_mode = TextureRect.STRETCH_TILE
	bg_checker.texture = _checker_tex
	bg_checker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_stack.add_child(bg_checker)

	texture_rect = TextureRect.new()
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_stack.add_child(texture_rect)

	selection_overlay = Control.new()
	selection_overlay.name = "SelectionOverlay"
	selection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_overlay.draw.connect(_draw_selection_overlay)
	texture_rect.add_child(selection_overlay)

	_export_png_dialog = FileDialog.new()
	_export_png_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_png_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_png_dialog.add_filter("*.png", "PNG Images")
	_export_png_dialog.title = "Export Plant Sprite"
	_export_png_dialog.file_selected.connect(_on_export_png_selected)
	add_child(_export_png_dialog)

	_init_canvas(false)
	_refresh_library()
	_apply_target_context()


func _refresh_library() -> void:
	if _library_list == null:
		return
	DirAccess.make_dir_recursive_absolute(SPRITE_DIR)
	_library_list.clear()
	if not DirAccess.dir_exists_absolute(SPRITE_DIR):
		return
	var dir := DirAccess.open(SPRITE_DIR)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.to_lower().ends_with(".png"):
			names.append(entry.get_basename())
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for file_base in names:
		_library_list.add_item(file_base)


func _safe_filename(raw: String) -> String:
	var s := raw.strip_edges().to_lower()
	var safe := ""
	for i in range(s.length()):
		var ch: String = s[i]
		var code := ch.unicode_at(0)
		if (code >= 48 and code <= 57) or (code >= 97 and code <= 122) or ch == "_":
			safe += ch
	return safe


func _show_warning(message: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Pixel Painter"
	dlg.dialog_text = message
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)


func _set_status(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = message


func _category_prefix(category_idx: int = -1) -> String:
	var idx := category_idx if category_idx >= 0 else category_selector.selected
	if idx < 0 or idx >= CATEGORY_PREFIXES.size():
		return ""
	return CATEGORY_PREFIXES[idx]


func _build_storage_filename(safe_base: String) -> String:
	var base := safe_base
	var prefix := _category_prefix()
	if prefix != "" and base.begins_with(prefix):
		return base
	return prefix + base


func _split_storage_filename(storage_name: String) -> Dictionary:
	var name := storage_name
	for i in range(CATEGORY_PREFIXES.size()):
		var prefix: String = CATEGORY_PREFIXES[i]
		if name.begins_with(prefix):
			return {"category": i, "base": name.substr(prefix.length())}
	return {"category": 0, "base": name}


func _apply_target_context() -> void:
	if target_id == "":
		_current_filename = ""
		if is_instance_valid(_filename_edit):
			_filename_edit.text = ""
			_filename_edit.placeholder_text = "new_sprite"
		if is_instance_valid(category_selector):
			category_selector.select(0)
		if is_instance_valid(_btn_apply_database):
			_btn_apply_database.visible = false
			_btn_apply_database.disabled = true
	else:
		_export_png_dialog.current_file = "%s.png" % target_id
		if is_instance_valid(category_selector):
			category_selector.select(0)
		if is_instance_valid(_filename_edit):
			_filename_edit.text = target_id
			_filename_edit.placeholder_text = target_id
		_current_filename = target_id
		if is_instance_valid(_btn_apply_database):
			_btn_apply_database.visible = true
			_btn_apply_database.disabled = false
		_try_load_existing_sprite()


func _attempt_save(is_save_as: bool) -> void:
	_stamp_floating_if_needed(true)
	var raw_name := _filename_edit.text.strip_edges()
	if raw_name == "":
		_show_warning("Please enter a filename.")
		return
	var safe_base := _safe_filename(raw_name)
	if safe_base == "":
		_show_warning("Filename must contain letters, numbers, or underscores.")
		return
	var storage_name := _build_storage_filename(safe_base)
	var filepath := SPRITE_DIR + storage_name + ".png"
	if is_save_as and FileAccess.file_exists(filepath):
		_show_warning("A sprite with this name already exists! Please choose a different name.")
		return
	var err: Error = image.save_png(filepath)
	if err != OK:
		_show_warning("Save failed (error %d)." % err)
		return
	_current_filename = storage_name
	_filename_edit.text = safe_base
	_refresh_library()
	_set_status("Saved to library: %s.png" % storage_name)


func load_sprite_from_path(filepath: String) -> void:
	if filepath == "" or not FileAccess.file_exists(filepath):
		_show_warning("File not found.")
		return
	_stamp_floating_if_needed(false)
	var loaded := Image.load_from_file(filepath)
	if loaded == null:
		_show_warning("Could not load: %s" % filepath.get_file())
		return
	if loaded.get_format() != Image.FORMAT_RGBA8:
		loaded.convert(Image.FORMAT_RGBA8)
	var w := loaded.get_width()
	var h := loaded.get_height()
	if w != canvas_size or h != canvas_size:
		for sz in CANVAS_SIZES:
			if sz >= maxi(w, h):
				_select_canvas_size(sz)
				break
		loaded.resize(canvas_size, canvas_size, Image.INTERPOLATE_NEAREST)
	image = loaded
	texture.set_image(image)
	undo_history.clear()
	_clear_selection()
	var base_name := filepath.get_file().get_basename()
	var storage_name := base_name
	if filepath.begins_with(SPRITE_DIR):
		storage_name = base_name
		var split := _split_storage_filename(base_name)
		if is_instance_valid(category_selector):
			category_selector.select(int(split["category"]))
		_filename_edit.text = str(split["base"])
	else:
		if is_instance_valid(_filename_edit):
			_filename_edit.text = base_name
	_current_filename = storage_name
	_set_status("Loaded: %s" % filepath.get_file())


func _on_load_selected() -> void:
	var selected: PackedInt32Array = _library_list.get_selected_items()
	if selected.is_empty():
		_show_warning("Select a sprite from the library first.")
		return
	var idx: int = selected[0]
	var storage_name := _library_list.get_item_text(idx)
	load_sprite_from_path(SPRITE_DIR + storage_name + ".png")


func _on_apply_to_database() -> void:
	if target_id == "":
		_show_warning("Open from the Database Editor to link a sprite to a plant row.")
		return
	if not PlantData.DATA.has(target_id):
		_show_warning("Plant ID '%s' is not in the database." % target_id)
		return
	_stamp_floating_if_needed(true)
	DirAccess.make_dir_recursive_absolute(SPRITE_DIR)
	var filepath := _sprite_path_for_id(target_id)
	var err: Error = image.save_png(filepath)
	if err != OK:
		_show_warning("Save failed (error %d)." % err)
		return
	PlantData.apply_custom_sprite(target_id, filepath)
	sprite_updated.emit(target_id)
	_refresh_library()
	_set_status("Linked to database plant: %s" % target_id)


func _add_labeled_option(parent: VBoxContainer, label_text: String, items: Array) -> OptionButton:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label_text
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var idx := 0
	for entry in items:
		if entry[1] is int:
			opt.add_item(str(entry[0]), int(entry[1]))
		else:
			opt.add_item(str(entry[0]))
			opt.set_item_metadata(idx, entry[1])
		idx += 1
	row.add_child(opt)
	parent.add_child(row)
	return opt


func _make_checker_texture() -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0.78, 0.78, 0.78, 1.0))
	img.set_pixel(1, 0, Color(1.0, 1.0, 1.0, 1.0))
	img.set_pixel(0, 1, Color(1.0, 1.0, 1.0, 1.0))
	img.set_pixel(1, 1, Color(0.78, 0.78, 0.78, 1.0))
	return ImageTexture.create_from_image(img)


func _make_solid_texture(color: Color) -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _save_undo_state() -> void:
	if image == null:
		return
	undo_history.append(image.duplicate())
	if undo_history.size() > MAX_UNDO_STEPS:
		undo_history.pop_front()


func _on_undo_pressed() -> void:
	if undo_history.is_empty() or image == null:
		return
	image = undo_history.pop_back()
	texture.set_image(image)
	_clear_selection()
	_redraw_overlay()


func _toggle_background() -> void:
	_bg_is_solid = not _bg_is_solid
	if _bg_is_solid:
		bg_checker.texture = _solid_bg_tex
		_bg_toggle_btn.text = "Background: Solid White"
	else:
		bg_checker.texture = _checker_tex
		_bg_toggle_btn.text = "Background: Transparent"


func _on_tool_button_pressed(tool_id: String) -> void:
	if current_tool == "select" and tool_id != "select":
		_stamp_floating_if_needed(true)
	_clear_selection()
	current_tool = tool_id


func _on_brush_size_changed(value: float) -> void:
	brush_size = int(value)
	if is_instance_valid(_brush_size_label):
		_brush_size_label.text = "Size: %dpx" % brush_size


func _on_canvas_size_selected(_idx: int) -> void:
	var new_size: int = int(_size_opt.get_item_id(_size_opt.selected))
	if new_size == canvas_size:
		return
	_save_undo_state()
	_resize_canvas(new_size)


func _resize_canvas(new_size: int) -> void:
	var old_img: Image = image.duplicate() if image != null else null
	canvas_size = new_size
	image = Image.create(canvas_size, canvas_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if old_img != null:
		old_img.resize(canvas_size, canvas_size, Image.INTERPOLATE_NEAREST)
		image.blit_rect(old_img, Rect2i(0, 0, canvas_size, canvas_size), Vector2i.ZERO)
	texture = ImageTexture.create_from_image(image)
	texture_rect.texture = texture
	_commit_texture()
	_redraw_overlay()


func setup_for_target_id(id: String) -> void:
	target_id = id
	if image == null or texture == null:
		return
	_stamp_floating_if_needed(false)
	image.fill(Color(0, 0, 0, 0))
	texture.update(image)
	undo_history.clear()
	_clear_selection()
	if is_instance_valid(_filename_edit):
		_filename_edit.text = id
	if is_instance_valid(category_selector):
		category_selector.select(0)
	_current_filename = id
	_set_status("Ready to draw for: %s" % id)


func open_for_target(linked_id: String = "", category_idx: int = 0) -> void:
	target_id = linked_id
	if is_instance_valid(category_selector):
		category_selector.select(category_idx)
	_select_canvas_size(50)
	_init_canvas(false)
	_apply_target_context()
	_refresh_library()
	show()


func open_for_plant(plant_id: String) -> void:
	open_for_target(plant_id, 0)


func _select_canvas_size(px: int) -> void:
	for i in range(_size_opt.item_count):
		if int(_size_opt.get_item_id(i)) == px:
			_size_opt.select(i)
			canvas_size = px
			return


func _init_canvas(preserve: bool) -> void:
	var old: Image = image.duplicate() if preserve and image != null else null
	image = Image.create(canvas_size, canvas_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if old != null:
		var copy := old.duplicate()
		copy.resize(canvas_size, canvas_size, Image.INTERPOLATE_NEAREST)
		image.blit_rect(copy, Rect2i(0, 0, canvas_size, canvas_size), Vector2i.ZERO)
	texture = ImageTexture.create_from_image(image)
	texture_rect.texture = texture
	undo_history.clear()
	_clear_selection()
	_drawing = false
	draw_start_pos = Vector2i(-1, -1)
	current_tool = "pencil"
	_set_tool_button_pressed("pencil")


func _set_tool_button_pressed(tool_id: String) -> void:
	if not is_instance_valid(_toolbar):
		return
	var tool_defs: Array = ["pencil", "eraser", "fill", "picker", "line"]
	for i in range(mini(_toolbar.get_child_count(), tool_defs.size())):
		var btn := _toolbar.get_child(i) as Button
		if btn:
			btn.button_pressed = str(tool_defs[i]) == tool_id


func _try_load_existing_sprite() -> void:
	if target_id == "":
		return
	var path := _sprite_path_for_id(target_id)
	var row: Dictionary = PlantData.get_plant_data(target_id)
	if row.has("custom_sprite_path"):
		var custom := str(row.get("custom_sprite_path", ""))
		if custom != "":
			path = custom
	if not FileAccess.file_exists(path):
		return
	var loaded := Image.load_from_file(path)
	if loaded == null:
		return
	var src_w := loaded.get_width()
	var src_h := loaded.get_height()
	if src_w != canvas_size or src_h != canvas_size:
		for sz in CANVAS_SIZES:
			if sz >= maxi(src_w, src_h):
				_select_canvas_size(sz)
				break
		loaded.resize(canvas_size, canvas_size, Image.INTERPOLATE_NEAREST)
	image = loaded
	texture.set_image(image)
	undo_history.clear()


func _sprite_path_for_id(linked_id: String) -> String:
	var direct := SPRITE_DIR + linked_id + ".png"
	if FileAccess.file_exists(direct):
		return direct
	var prefixed := SPRITE_DIR + "plant_" + linked_id + ".png"
	if FileAccess.file_exists(prefixed):
		return prefixed
	return direct


func _clear_canvas() -> void:
	_stamp_floating_if_needed(false)
	_save_undo_state()
	image.fill(Color(0, 0, 0, 0))
	_clear_selection()
	_commit_texture()


func _clear_selection() -> void:
	selection_rect = Rect2i(-1, -1, 0, 0)
	floating_image = null
	floating_pos = Vector2i.ZERO
	is_selecting = false
	is_dragging_floating = false
	_last_drag_cell = Vector2i(-1, -1)
	_redraw_overlay()


func _stamp_floating_if_needed(save_undo: bool) -> void:
	if floating_image == null:
		return
	if save_undo:
		_save_undo_state()
	var sz := floating_image.get_size()
	var dest := Rect2i(floating_pos, sz)
	dest = dest.intersection(Rect2i(0, 0, canvas_size, canvas_size))
	if dest.size.x > 0 and dest.size.y > 0:
		var src := Rect2i(Vector2i.ZERO, dest.size)
		image.blit_rect(floating_image, src, dest.position)
	floating_image = null
	selection_rect = Rect2i(-1, -1, 0, 0)
	_commit_texture()
	_redraw_overlay()


func _normalized_selection_rect() -> Rect2i:
	if selection_rect.size.x <= 0 or selection_rect.size.y <= 0:
		return Rect2i()
	var x0 := selection_rect.position.x
	var y0 := selection_rect.position.y
	var x1 := selection_rect.position.x + selection_rect.size.x - 1
	var y1 := selection_rect.position.y + selection_rect.size.y - 1
	return _rect_from_points(Vector2i(x0, y0), Vector2i(x1, y1))


func _rect_from_points(a: Vector2i, b: Vector2i) -> Rect2i:
	var x0: int = mini(a.x, b.x)
	var y0: int = mini(a.y, b.y)
	var x1: int = maxi(a.x, b.x)
	var y1: int = maxi(a.y, b.y)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _point_in_selection(p: Vector2i) -> bool:
	var r := _normalized_selection_rect()
	if r.size.x <= 0 or r.size.y <= 0:
		return false
	return r.has_point(p)


func _cut_selection_to_floating() -> void:
	var r := _normalized_selection_rect()
	if r.size.x <= 0 or r.size.y <= 0:
		return
	_save_undo_state()
	floating_image = image.get_region(r)
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			image.set_pixel(x, y, Color(0, 0, 0, 0))
	floating_pos = r.position
	selection_rect = r
	_commit_texture()
	_redraw_overlay()


func _layout_vectors() -> Array[Vector2]:
	var rect_size: Vector2 = _canvas_panel.size
	var tex_size: float = float(canvas_size)
	var aspect: float = minf(rect_size.x / tex_size, rect_size.y / tex_size)
	var drawn: Vector2 = Vector2(tex_size * aspect, tex_size * aspect)
	var offset: Vector2 = (rect_size - drawn) * 0.5
	var scale: Vector2 = Vector2(drawn.x / tex_size, drawn.y / tex_size)
	return [offset, drawn, scale]


func _pixel_to_screen(px: Vector2i) -> Vector2:
	var layout: Array[Vector2] = _layout_vectors()
	var offset: Vector2 = layout[0]
	var scale: Vector2 = layout[2]
	return offset + Vector2(px.x, px.y) * scale


func _pixel_rect_to_screen(r: Rect2i) -> Rect2:
	var layout: Array[Vector2] = _layout_vectors()
	var offset: Vector2 = layout[0]
	var scale: Vector2 = layout[2]
	return Rect2(offset + Vector2(r.position) * scale, Vector2(r.size) * scale)


func _draw_selection_overlay() -> void:
	var dash_color := Color(0.1, 0.1, 0.1, 1.0)
	var r := _normalized_selection_rect()
	if r.size.x > 0 and r.size.y > 0 and floating_image == null:
		_draw_dashed_rect(_pixel_rect_to_screen(r), dash_color)
	if floating_image != null:
		var fr := Rect2i(floating_pos, floating_image.get_size())
		var screen_r := _pixel_rect_to_screen(fr)
		var ftex := ImageTexture.create_from_image(floating_image)
		selection_overlay.draw_texture_rect(ftex, screen_r, false)
		_draw_dashed_rect(screen_r, Color(0.0, 0.45, 1.0, 1.0))


func _draw_dashed_rect(rect: Rect2, color: Color) -> void:
	var dash := 4.0
	var gap := 4.0
	var end := rect.position + rect.size
	_draw_dashed_line(rect.position, Vector2(end.x, rect.position.y), dash, gap, color)
	_draw_dashed_line(Vector2(end.x, rect.position.y), end, dash, gap, color)
	_draw_dashed_line(end, Vector2(rect.position.x, end.y), dash, gap, color)
	_draw_dashed_line(Vector2(rect.position.x, end.y), rect.position, dash, gap, color)


func _draw_dashed_line(from: Vector2, to: Vector2, dash: float, gap: float, color: Color) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.001:
		return
	dir /= length
	var pos := 0.0
	var draw_on := true
	while pos < length:
		var seg_len := dash if draw_on else gap
		var next_pos := minf(pos + seg_len, length)
		if draw_on:
			selection_overlay.draw_line(from + dir * pos, from + dir * next_pos, color, 1.0, true)
		pos = next_pos
		draw_on = not draw_on


func _redraw_overlay() -> void:
	if is_instance_valid(selection_overlay):
		selection_overlay.queue_redraw()


func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var cell := _mouse_to_pixel(mb.position)
		if mb.pressed:
			if cell.x < 0:
				return
			draw_start_pos = cell
			_drawing = true
			match current_tool:
				"select":
					_handle_select_pressed(cell)
				"picker":
					color_picker.color = image.get_pixel(cell.x, cell.y)
					_drawing = false
					draw_start_pos = Vector2i(-1, -1)
				"pencil", "eraser":
					_save_undo_state()
					_paint_brush_at(cell.x, cell.y)
				"fill":
					_save_undo_state()
					_flood_fill(cell.x, cell.y, image.get_pixel(cell.x, cell.y), _active_color())
					_drawing = false
					draw_start_pos = Vector2i(-1, -1)
		else:
			if _drawing:
				var end_cell := _mouse_to_pixel(mb.position)
				if end_cell.x < 0:
					end_cell = draw_start_pos
				match current_tool:
					"select":
						_handle_select_released(end_cell)
					"line":
						_save_undo_state()
						_draw_line(draw_start_pos, end_cell, _active_color())
					"rect":
						_save_undo_state()
						_draw_rect_outline(draw_start_pos, end_cell, _active_color())
			_drawing = false
			draw_start_pos = Vector2i(-1, -1)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var cell := _mouse_to_pixel(mm.position)
		if current_tool == "select":
			if is_selecting and cell.x >= 0:
				selection_rect = _rect_from_points(draw_start_pos, cell)
				_redraw_overlay()
			elif is_dragging_floating and cell.x >= 0:
				if _last_drag_cell.x < 0:
					_last_drag_cell = cell
				else:
					var delta := cell - _last_drag_cell
					floating_pos += delta
					if floating_image != null:
						var fw: int = floating_image.get_width()
						var fh: int = floating_image.get_height()
						floating_pos.x = clampi(floating_pos.x, 0, maxi(0, canvas_size - fw))
						floating_pos.y = clampi(floating_pos.y, 0, maxi(0, canvas_size - fh))
					if floating_image != null:
						selection_rect = Rect2i(floating_pos, floating_image.get_size())
					_last_drag_cell = cell
					_redraw_overlay()
		elif _drawing and current_tool in ["pencil", "eraser"]:
			if cell.x >= 0:
				_paint_brush_at(cell.x, cell.y)


func _handle_select_pressed(cell: Vector2i) -> void:
	if floating_image != null:
		if _point_in_selection(cell):
			is_dragging_floating = true
			_last_drag_cell = cell
		else:
			_save_undo_state()
			_stamp_floating_if_needed(false)
			is_selecting = true
			draw_start_pos = cell
			selection_rect = Rect2i(cell, Vector2i.ZERO)
	elif _point_in_selection(cell):
		_cut_selection_to_floating()
		is_dragging_floating = true
		_last_drag_cell = cell
	else:
		is_selecting = true
		draw_start_pos = cell
		selection_rect = Rect2i(cell, Vector2i.ZERO)
	_redraw_overlay()


func _handle_select_released(end_cell: Vector2i) -> void:
	if is_selecting:
		selection_rect = _rect_from_points(draw_start_pos, end_cell)
		selection_rect = selection_rect.intersection(Rect2i(0, 0, canvas_size, canvas_size))
	is_selecting = false
	is_dragging_floating = false
	_last_drag_cell = Vector2i(-1, -1)
	_redraw_overlay()


func _mouse_to_pixel(local_pos: Vector2) -> Vector2i:
	var layout: Array[Vector2] = _layout_vectors()
	var offset: Vector2 = layout[0]
	var drawn: Vector2 = layout[1]
	var rel: Vector2 = local_pos - offset
	if rel.x < 0.0 or rel.y < 0.0 or rel.x >= drawn.x or rel.y >= drawn.y:
		return Vector2i(-1, -1)
	var x := clampi(int((rel.x / drawn.x) * float(canvas_size)), 0, canvas_size - 1)
	var y := clampi(int((rel.y / drawn.y) * float(canvas_size)), 0, canvas_size - 1)
	return Vector2i(x, y)


func _active_color() -> Color:
	if current_tool == "eraser":
		return Color(0, 0, 0, 0)
	return color_picker.color


func _paint_pixel_brush(center_x: int, center_y: int, paint_color: Color) -> void:
	var offset := brush_size - 1
	for dx in range(-offset, offset + 1):
		for dy in range(-offset, offset + 1):
			var px := center_x + dx
			var py := center_y + dy
			if px >= 0 and px < canvas_size and py >= 0 and py < canvas_size:
				image.set_pixel(px, py, paint_color)


func _paint_brush_at(x: int, y: int) -> void:
	if x < 0 or x >= canvas_size or y < 0 or y >= canvas_size:
		return
	_paint_pixel_brush(x, y, _active_color())
	_commit_texture()


func _commit_texture() -> void:
	texture.set_image(image)


func _flood_fill(start_x: int, start_y: int, target_color: Color, replacement_color: Color) -> void:
	if target_color == replacement_color:
		return
	if start_x < 0 or start_x >= canvas_size or start_y < 0 or start_y >= canvas_size:
		return
	var queue: Array[Vector2i] = [Vector2i(start_x, start_y)]
	var visited: Dictionary = {}
	var steps := 0
	while queue.size() > 0 and steps < FLOOD_FILL_MAX:
		var p: Vector2i = queue.pop_front()
		var key := "%d,%d" % [p.x, p.y]
		if visited.has(key):
			continue
		visited[key] = true
		steps += 1
		if p.x < 0 or p.x >= canvas_size or p.y < 0 or p.y >= canvas_size:
			continue
		if image.get_pixel(p.x, p.y) != target_color:
			continue
		image.set_pixel(p.x, p.y, replacement_color)
		queue.append(Vector2i(p.x + 1, p.y))
		queue.append(Vector2i(p.x - 1, p.y))
		queue.append(Vector2i(p.x, p.y + 1))
		queue.append(Vector2i(p.x, p.y - 1))
	_commit_texture()


func _draw_line(from: Vector2i, to: Vector2i, color: Color) -> void:
	var x0 := from.x
	var y0 := from.y
	var x1 := to.x
	var y1 := to.y
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err_i: int = dx + dy
	while true:
		_paint_pixel_brush(x0, y0, color)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err_i
		if e2 >= dy:
			err_i += dy
			x0 += sx
		if e2 <= dx:
			err_i += dx
			y0 += sy
	_commit_texture()


func _draw_rect_outline(from: Vector2i, to: Vector2i, color: Color) -> void:
	var x0: int = mini(from.x, to.x)
	var y0: int = mini(from.y, to.y)
	var x1: int = maxi(from.x, to.x)
	var y1: int = maxi(from.y, to.y)
	for x in range(x0, x1 + 1):
		_paint_pixel_brush(x, y0, color)
		_paint_pixel_brush(x, y1, color)
	for y in range(y0, y1 + 1):
		_paint_pixel_brush(x0, y, color)
		_paint_pixel_brush(x1, y, color)
	_commit_texture()


func _on_export_png_selected(path: String) -> void:
	_stamp_floating_if_needed(true)
	var export_path := path
	if not export_path.to_lower().ends_with(".png"):
		export_path += ".png"
	var export_img := image.duplicate()
	var export_px := maxi(canvas_size, 200)
	if export_img.get_width() != export_px or export_img.get_height() != export_px:
		export_img.resize(export_px, export_px, Image.INTERPOLATE_NEAREST)
	var err: Error = export_img.save_png(export_path)
	if err != OK:
		push_error("ui_pixel_painter: export failed (%d)" % err)
