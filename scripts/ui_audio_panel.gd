extends VBoxContainer

signal back_pressed

var _mode_opt: OptionButton
var _station_opt: OptionButton
var _skip_btn: Button
var _station_row: HBoxContainer
var _skip_row: HBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 15)

	var lbl_audio = Label.new()
	lbl_audio.text = "-- Sound Settings --"
	lbl_audio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl_audio)

	# --- MUSICAL SETTINGS ---
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)

	# BPM Slider
	var lbl_bpm = Label.new()
	lbl_bpm.text = "Tempo (BPM): " + str(RadioManager.current_bpm)
	grid.add_child(lbl_bpm)

	var bpm_slider = HSlider.new()
	bpm_slider.min_value = 80
	bpm_slider.max_value = 140
	bpm_slider.step = 1
	bpm_slider.value = RadioManager.current_bpm
	bpm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bpm_slider.value_changed.connect(func(v):
		RadioManager.current_bpm = int(v)
		lbl_bpm.text = "Tempo (BPM): " + str(RadioManager.current_bpm)
	)
	grid.add_child(bpm_slider)

	# Key Selector
	var lbl_key = Label.new()
	lbl_key.text = "Musical Key:"
	grid.add_child(lbl_key)

	var key_opt = OptionButton.new()
	for i in range(RadioManager.KEYS.size()):
		key_opt.add_item(RadioManager.KEYS[i] + " Pentatonic", i)
	key_opt.select(RadioManager.current_key_index)
	key_opt.item_selected.connect(func(idx: int):
		RadioManager.current_key_index = idx
	)
	grid.add_child(key_opt)

	# Spacer
	var sep = HSeparator.new()
	add_child(sep)

	# --- RADIO CONTROLS ---
	var radio_box := VBoxContainer.new()
	radio_box.add_theme_constant_override("separation", 8)
	add_child(radio_box)

	var radio_title := Label.new()
	radio_title.text = "-- Radio --"
	radio_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	radio_box.add_child(radio_title)

	var mode_row := HBoxContainer.new()
	var lbl_mode := Label.new()
	lbl_mode.text = "Audio Mode:"
	lbl_mode.custom_minimum_size = Vector2(150, 0)
	mode_row.add_child(lbl_mode)
	_mode_opt = OptionButton.new()
	_mode_opt.add_item("Generative", 0)
	_mode_opt.add_item("Custom Radio", 1)
	_mode_opt.add_item("Muted", 2)
	_mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_opt.item_selected.connect(_on_audio_mode_selected)
	mode_row.add_child(_mode_opt)
	radio_box.add_child(mode_row)

	_station_row = HBoxContainer.new()
	var lbl_station := Label.new()
	lbl_station.text = "Radio Station:"
	lbl_station.custom_minimum_size = Vector2(150, 0)
	_station_row.add_child(lbl_station)
	_station_opt = OptionButton.new()
	_station_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_station_opt.item_selected.connect(_on_station_selected)
	_station_row.add_child(_station_opt)
	radio_box.add_child(_station_row)

	_skip_row = HBoxContainer.new()
	_skip_btn = Button.new()
	_skip_btn.text = "Skip Track"
	_skip_btn.pressed.connect(func() -> void: RadioManager.skip_radio_track())
	_skip_row.add_child(_skip_btn)
	radio_box.add_child(_skip_row)

	var radio_sep := HSeparator.new()
	add_child(radio_sep)

	RadioManager.refresh_custom_stations()
	_populate_station_options()
	_sync_mode_from_manager()
	_update_radio_controls_visibility()

	# Godot buses (skipped if missing). Include Beat for procedural note volume when you add that bus.
	var buses = ["Master", "Music", "SFX", "Beat"]

	for bus_name in buses:
		var bus_idx = AudioServer.get_bus_index(bus_name)
		if bus_idx == -1:
			continue

		var hbox = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = bus_name + " Volume:"
		lbl.custom_minimum_size = Vector2(150, 0)
		hbox.add_child(lbl)

		var slider = HSlider.new()
		slider.min_value = 0.0001 # Avoids -infinity dB math errors
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var idx: int = bus_idx
		slider.value_changed.connect(func(v: float):
			AudioServer.set_bus_volume_db(idx, linear_to_db(v))
		)
		hbox.add_child(slider)
		add_child(hbox)

	var btn_back = Button.new()
	btn_back.text = "Back"
	btn_back.pressed.connect(func(): back_pressed.emit())
	add_child(btn_back)


func _populate_station_options() -> void:
	if not is_instance_valid(_station_opt):
		return
	_station_opt.clear()
	var names: Array = RadioManager.custom_stations.keys()
	names.sort()
	if names.is_empty():
		_station_opt.add_item("(Add folders under user://audio/radio/)")
		_station_opt.disabled = true
		return
	_station_opt.disabled = false
	var select_idx := 0
	for i in range(names.size()):
		var station_name := str(names[i])
		_station_opt.add_item(station_name, i)
		if station_name == RadioManager.current_station_name:
			select_idx = i
	_station_opt.select(select_idx)


func _sync_mode_from_manager() -> void:
	if not is_instance_valid(_mode_opt):
		return
	match RadioManager.audio_mode:
		"radio":
			_mode_opt.select(1)
		"mute":
			_mode_opt.select(2)
		_:
			_mode_opt.select(0)


func _update_radio_controls_visibility() -> void:
	var is_radio := is_instance_valid(_mode_opt) and _mode_opt.selected == 1
	if is_instance_valid(_station_row):
		_station_row.visible = is_radio
	if is_instance_valid(_skip_row):
		_skip_row.visible = is_radio
	if is_instance_valid(_station_opt):
		_station_opt.disabled = not is_radio or RadioManager.custom_stations.is_empty()
	if is_instance_valid(_skip_btn):
		_skip_btn.disabled = not is_radio or RadioManager.custom_stations.is_empty()


func _on_audio_mode_selected(idx: int) -> void:
	match idx:
		0:
			RadioManager.set_audio_mode("generative")
		1:
			RadioManager.set_audio_mode("radio")
			if not RadioManager.custom_stations.is_empty() and is_instance_valid(_station_opt):
				if _station_opt.disabled or _station_opt.item_count == 0:
					pass
				else:
					var station_name := _station_opt.get_item_text(_station_opt.selected)
					if station_name.begins_with("("):
						return
					RadioManager.play_radio_station(station_name)
		2:
			RadioManager.set_audio_mode("mute")
	_update_radio_controls_visibility()


func _on_station_selected(_idx: int) -> void:
	if not is_instance_valid(_mode_opt) or _mode_opt.selected != 1:
		return
	if _station_opt.disabled:
		return
	var station_name := _station_opt.get_item_text(_station_opt.selected)
	if station_name.begins_with("("):
		return
	RadioManager.play_radio_station(station_name)
