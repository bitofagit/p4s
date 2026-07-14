extends VBoxContainer

signal back_pressed

var _mode_opt: OptionButton
var _res_opt: OptionButton
var _ui_slider: HSlider
var _hint_label: Label
var _preset_slider: HSlider
var _preset_label: Label
var _groundcover_btn: CheckButton
var _understory_btn: CheckButton
var _zoom_cull_btn: CheckButton
var _weather_slider: HSlider
var _weather_value_label: Label
var _advanced_overlays_btn: CheckButton
var _data_lens_fx_btn: CheckButton
var _vector_far_btn: CheckButton
var _syncing_controls := false


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

	# --- PERFORMANCE PRESET (4-tier macro matrix) ---
	var lbl_preset = Label.new()
	lbl_preset.text = "-- Performance Preset --"
	lbl_preset.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl_preset)

	var preset_hbox = HBoxContainer.new()
	var lbl_preset_slider = Label.new()
	lbl_preset_slider.text = "Quality Preset:"
	lbl_preset_slider.custom_minimum_size = Vector2(150, 0)
	preset_hbox.add_child(lbl_preset_slider)

	_preset_slider = HSlider.new()
	_preset_slider.name = "PresetSlider"
	_preset_slider.min_value = MetaManager.PRESET_LOW
	_preset_slider.max_value = MetaManager.PRESET_CUSTOM
	_preset_slider.step = 1.0
	_preset_slider.tick_count = 4
	_preset_slider.ticks_on_borders = true
	_preset_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_slider.value_changed.connect(_on_preset_slider_changed)
	preset_hbox.add_child(_preset_slider)

	_preset_label = Label.new()
	_preset_label.custom_minimum_size = Vector2(72, 0)
	_preset_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	preset_hbox.add_child(_preset_label)
	add_child(preset_hbox)

	var lbl_preset_hint = Label.new()
	lbl_preset_hint.text = (
		"Low is the safe boot default for weak laptops. Medium suits Iris Xe / mid-tier iGPUs. "
		+ "Manual tweaks switch to Custom."
	)
	lbl_preset_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_preset_hint.add_theme_font_size_override("font_size", 12)
	lbl_preset_hint.add_theme_color_override("font_color", Color(0.65, 0.75, 0.65))
	add_child(lbl_preset_hint)

	var lbl_perf = Label.new()
	lbl_perf.text = "-- Performance Details --"
	lbl_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl_perf)

	_groundcover_btn = _add_perf_toggle(
		"Render Groundcover:",
		MetaManager.render_groundcover,
		func(on: bool):
			MetaManager.render_groundcover = on
			_on_manual_graphics_changed()
	)
	_understory_btn = _add_perf_toggle(
		"Render Understory:",
		MetaManager.render_understory,
		func(on: bool):
			MetaManager.render_understory = on
			_on_manual_graphics_changed()
	)
	_zoom_cull_btn = _add_perf_toggle(
		"Dynamic Zoom Culling:",
		MetaManager.dynamic_zoom_culling,
		func(on: bool):
			MetaManager.dynamic_zoom_culling = on
			_on_manual_graphics_changed()
	)

	var weather_hbox = HBoxContainer.new()
	var lbl_weather = Label.new()
	lbl_weather.text = "Weather Particles:"
	lbl_weather.custom_minimum_size = Vector2(150, 0)
	weather_hbox.add_child(lbl_weather)
	_weather_slider = HSlider.new()
	_weather_slider.min_value = 80.0
	_weather_slider.max_value = 500.0
	_weather_slider.step = 10.0
	_weather_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weather_slider.value = MetaManager.weather_particles
	_weather_slider.value_changed.connect(_on_weather_particles_changed)
	weather_hbox.add_child(_weather_slider)
	_weather_value_label = Label.new()
	_weather_value_label.custom_minimum_size = Vector2(40, 0)
	_weather_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weather_hbox.add_child(_weather_value_label)
	add_child(weather_hbox)

	_advanced_overlays_btn = _add_perf_toggle(
		"Advanced Map Overlays:",
		MetaManager.advanced_overlays,
		func(on: bool):
			MetaManager.advanced_overlays = on
			_on_manual_graphics_changed()
	)
	_data_lens_fx_btn = _add_perf_toggle(
		"Data Lens Visual FX:",
		MetaManager.data_lens_fx,
		func(on: bool):
			MetaManager.data_lens_fx = on
			_on_manual_graphics_changed()
	)
	_vector_far_btn = _add_perf_toggle(
		"Vector Shapes (Far Zoom):",
		MetaManager.flora_vector_far_zoom,
		func(on: bool):
			MetaManager.flora_vector_far_zoom = on
			_on_manual_graphics_changed()
	)

	var lbl_perf_hint = Label.new()
	lbl_perf_hint.text = (
		"Groundcover is the heaviest flora layer. Advanced overlays include swale shimmers and "
		+ "structure washes. Vector shapes replace far LOD sprites when zoomed out."
	)
	lbl_perf_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_perf_hint.add_theme_font_size_override("font_size", 12)
	lbl_perf_hint.add_theme_color_override("font_color", Color(0.65, 0.75, 0.65))
	add_child(lbl_perf_hint)

	var btn_apply = Button.new()
	btn_apply.text = "Apply"
	btn_apply.pressed.connect(_on_apply_pressed)
	add_child(btn_apply)

	var btn_back = Button.new()
	btn_back.text = "Back"
	btn_back.pressed.connect(func(): back_pressed.emit())
	add_child(btn_back)

	sync_controls_from_system()


func _add_perf_toggle(label_text: String, initial: bool, on_toggled: Callable) -> CheckButton:
	var hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)
	var btn = CheckButton.new()
	btn.button_pressed = initial
	btn.toggled.connect(on_toggled)
	hbox.add_child(btn)
	add_child(hbox)
	return btn


func _on_preset_slider_changed(value: float) -> void:
	if _syncing_controls:
		return
	var preset_id := clampi(int(value), MetaManager.PRESET_LOW, MetaManager.PRESET_CUSTOM)
	_update_preset_label(preset_id)
	if preset_id == MetaManager.PRESET_CUSTOM:
		return
	MetaManager.apply_graphics_preset(preset_id)
	_sync_perf_controls_from_meta()
	_apply_graphics_runtime()


func _on_weather_particles_changed(value: float) -> void:
	if _syncing_controls:
		return
	MetaManager.weather_particles = clampi(int(value), 20, 800)
	_update_weather_label()
	_on_manual_graphics_changed()


func _update_weather_label() -> void:
	if _weather_value_label != null:
		_weather_value_label.text = str(MetaManager.weather_particles)


func _sync_perf_controls_from_meta() -> void:
	if _groundcover_btn != null:
		_groundcover_btn.set_pressed_no_signal(MetaManager.render_groundcover)
		_understory_btn.set_pressed_no_signal(MetaManager.render_understory)
		_zoom_cull_btn.set_pressed_no_signal(MetaManager.dynamic_zoom_culling)
	if _weather_slider != null:
		_weather_slider.value = MetaManager.weather_particles
		_update_weather_label()
	if _advanced_overlays_btn != null:
		_advanced_overlays_btn.set_pressed_no_signal(MetaManager.advanced_overlays)
	if _data_lens_fx_btn != null:
		_data_lens_fx_btn.set_pressed_no_signal(MetaManager.data_lens_fx)
	if _vector_far_btn != null:
		_vector_far_btn.set_pressed_no_signal(MetaManager.flora_vector_far_zoom)


func _on_manual_graphics_changed() -> void:
	if _syncing_controls:
		return
	MetaManager.notify_graphics_customised()
	if _preset_slider != null:
		_syncing_controls = true
		_preset_slider.value = MetaManager.PRESET_CUSTOM
		_update_preset_label(MetaManager.PRESET_CUSTOM)
		_syncing_controls = false
	MetaManager.save_meta()
	_apply_graphics_runtime()


func _update_preset_label(preset_id: int) -> void:
	if _preset_label != null:
		_preset_label.text = MetaManager.preset_label(preset_id)


## Push flora layer visibility and low-end overlays to the live map (if loaded).
func _apply_graphics_runtime() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var map := tree.get_first_node_in_group("map") as Node
	if map != null:
		if map.has_method("apply_meta_graphics_settings"):
			map.apply_meta_graphics_settings()
		elif map.has_method("_redraw_data_lens_overlays"):
			map.call("_redraw_data_lens_overlays")
	var world_cam := tree.current_scene
	if world_cam is Camera2D and world_cam.has_method("apply_meta_graphics_settings"):
		world_cam.apply_meta_graphics_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		sync_controls_from_system()


func sync_controls_from_system() -> void:
	if _mode_opt == null:
		return

	_syncing_controls = true
	_sync_perf_controls_from_meta()
	if _preset_slider != null:
		_preset_slider.value = MetaManager.graphics_preset
		_update_preset_label(MetaManager.graphics_preset)
	_syncing_controls = false

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

		# 3–4. Apply size and centre (only when not the editor's embedded game viewport).
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
