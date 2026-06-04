extends VBoxContainer

signal back_pressed

var _mode_opt: OptionButton
var _res_opt: OptionButton
var _ui_slider: HSlider
var _hint_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 15)

	var lbl_gfx = Label.new()
	lbl_gfx.text = "-- Graphics Settings --"
	lbl_gfx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl_gfx)

	# --- DISPLAY MODE ---
	var mode_hbox = HBoxContainer.new()
	var lbl_mode = Label.new()
	lbl_mode.text = "Display Mode:"
	lbl_mode.custom_minimum_size = Vector2(150, 0)
	mode_hbox.add_child(lbl_mode)

	_mode_opt = OptionButton.new()
	_mode_opt.add_item("Windowed", DisplayServer.WINDOW_MODE_WINDOWED)
	_mode_opt.add_item("Fullscreen", DisplayServer.WINDOW_MODE_FULLSCREEN)
	_mode_opt.add_item("Borderless Fullscreen", DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	_mode_opt.item_selected.connect(_on_mode_changed)
	mode_hbox.add_child(_mode_opt)
	add_child(mode_hbox)

	# --- RESOLUTION (windowed presets; same list as SaveManager / project.godot default) ---
	var res_hbox = HBoxContainer.new()
	var lbl_res = Label.new()
	lbl_res.text = "Resolution:"
	lbl_res.custom_minimum_size = Vector2(150, 0)
	res_hbox.add_child(lbl_res)

	_res_opt = OptionButton.new()
	for i in range(SaveManager.RESOLUTION_PRESETS.size()):
		var r: Vector2i = SaveManager.RESOLUTION_PRESETS[i]
		_res_opt.add_item("%d x %d" % [r.x, r.y], i)
	res_hbox.add_child(_res_opt)
	add_child(res_hbox)

	# --- UI SCALE ---
	var ui_hbox = HBoxContainer.new()
	var lbl_ui = Label.new()
	lbl_ui.text = "UI Scale:"
	lbl_ui.custom_minimum_size = Vector2(150, 0)
	ui_hbox.add_child(lbl_ui)

	_ui_slider = HSlider.new()
	_ui_slider.min_value = 0.5
	_ui_slider.max_value = 2.0
	_ui_slider.step = 0.1
	_ui_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_hbox.add_child(_ui_slider)
	add_child(ui_hbox)

	_hint_label = Label.new()
	_hint_label.text = "Change options, then click Apply to preview. Settings are saved when you apply."
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.65))
	add_child(_hint_label)

	# --- MAGNETIC DOCKING ---
	var mag_hbox = HBoxContainer.new()
	var lbl_mag = Label.new()
	lbl_mag.text = "Magnetic Docking:"
	lbl_mag.custom_minimum_size = Vector2(150, 0)
	mag_hbox.add_child(lbl_mag)

	var mag_btn = CheckButton.new()
	mag_btn.button_pressed = MetaManager.magnetic_docking
	mag_btn.toggled.connect(func(toggled_on: bool):
		MetaManager.magnetic_docking = toggled_on
		MetaManager.save_meta()
	)
	mag_hbox.add_child(mag_btn)
	add_child(mag_hbox)

	var btn_apply = Button.new()
	btn_apply.text = "Apply"
	btn_apply.pressed.connect(_on_apply_pressed)
	add_child(btn_apply)

	var btn_back = Button.new()
	btn_back.text = "Back"
	btn_back.pressed.connect(func(): back_pressed.emit())
	add_child(btn_back)

	sync_controls_from_system()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		sync_controls_from_system()


func sync_controls_from_system() -> void:
	if _mode_opt == null:
		return

	var current_mode := DisplayServer.window_get_mode()
	for i in range(_mode_opt.item_count):
		if _mode_opt.get_item_id(i) == current_mode:
			_mode_opt.select(i)
			break

	var target_size := DisplayServer.window_get_size()
	if current_mode != DisplayServer.WINDOW_MODE_WINDOWED:
		target_size = Vector2i(
			int(SaveManager.display_settings.get("width", SaveManager.get_default_resolution().x)),
			int(SaveManager.display_settings.get("height", SaveManager.get_default_resolution().y))
		)
	_res_opt.select(SaveManager.resolution_preset_index(target_size))

	if get_tree() and get_tree().root:
		_ui_slider.value = get_tree().root.content_scale_factor
	else:
		_ui_slider.value = float(SaveManager.display_settings.get("ui_scale", 1.0))

	_on_mode_changed(_mode_opt.selected)


func _on_mode_changed(_index: int) -> void:
	var windowed := _mode_opt.get_item_id(_mode_opt.selected) == DisplayServer.WINDOW_MODE_WINDOWED
	_res_opt.disabled = not windowed


func _on_apply_pressed() -> void:
	_apply_display_async()


func _apply_display_async() -> void:
	var mode: int = _mode_opt.get_item_id(_mode_opt.selected)
	var ui_scale: float = float(_ui_slider.value)
	var is_windowed: bool = (mode == DisplayServer.WINDOW_MODE_WINDOWED)

	# Parse resolution label (e.g. "1920 x 1080" → 1920×1080).
	var res_string: String = _res_opt.get_item_text(_res_opt.selected)
	var target_res: Vector2i = _parse_resolution_string(res_string)

	if is_windowed:
		# 1. Windowed mode FIRST — required before size changes take effect.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

		# Let DisplayServer finish leaving fullscreen/exclusive modes.
		await get_tree().process_frame

		# 2. Monitor safety check
		var monitor_size: Vector2i = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
		if target_res.x > monitor_size.x or target_res.y > monitor_size.y:
			print("Warning: Resolution too large for monitor. Snapping to safe fallback.")
			target_res = SaveManager.FALLBACK_RESOLUTION
			_res_opt.select(SaveManager.resolution_preset_index(target_res))

		# 3–4. Apply size and center (only when not the editor's embedded game viewport).
		var window := get_window()
		if window and not window.is_embedded():
			SaveManager.apply_windowed_size(target_res)
			window.move_to_center()
			_hint_label.text = "Applied %d x %d (windowed). Settings saved." % [target_res.x, target_res.y]
		else:
			print("Editor Mode: Skipping physical window resize to avoid embedded window error.")
			_hint_label.text = (
				"Saved %d x %d for standalone run. (Editor embed: resize skipped.)" % [target_res.x, target_res.y]
			)
	else:
		target_res = SaveManager.clamp_resolution_to_monitor(target_res)
		_res_opt.select(SaveManager.resolution_preset_index(target_res))
		_hint_label.text = "Applied display mode. Windowed size will be %d x %d." % [target_res.x, target_res.y]

	# 5–6. Persist and apply (fullscreen clears window size overrides).
	var disp: Dictionary = SaveManager.display_settings.duplicate()
	disp["window_mode"] = mode
	disp["width"] = target_res.x
	disp["height"] = target_res.y
	disp["ui_scale"] = ui_scale
	if not disp.has("_version"):
		disp["_version"] = SaveManager.DISPLAY_SETTINGS_VERSION
	SaveManager.display_settings = disp
	SaveManager.apply_display_settings()
	SaveManager.save_settings()


func _parse_resolution_string(res_string: String) -> Vector2i:
	var cleaned := res_string.strip_edges().replace(" ", "")
	var dims := cleaned.split("x", false)
	if dims.size() >= 2:
		var w := int(dims[0])
		var h := int(dims[1])
		if w > 0 and h > 0:
			return Vector2i(w, h)
	return SaveManager.FALLBACK_RESOLUTION
