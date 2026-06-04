extends PanelContainer

signal launch_creative(overrides_dict: Dictionary)
signal cancel_creative()

const PlantData := preload("res://data/data_plants.gd")
const DATABASES_DIR := "user://databases"
const SPRITES_DIR := "user://databases/sprites/"

var _money_slider: HSlider
var _money_value_label: Label
var _energy_slider: HSlider
var _energy_value_label: Label
var _time_lapse_slider: HSlider
var _time_lapse_label: Label
var _pre_staffed_opt: OptionButton
var _zen_check: CheckBox
var _weatherproof_check: CheckBox
var _infinite_water_check: CheckBox
var _auto_harvest_check: CheckBox
var _auto_sell_check: CheckBox
var _manual_bonus_slider: HSlider
var _manual_bonus_label: Label
var _db_opt: OptionButton
var _sprite_opt: OptionButton


func _ready() -> void:
	custom_minimum_size = Vector2(480, 320)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 16)
	outer_margin.add_theme_constant_override("margin_right", 16)
	outer_margin.add_theme_constant_override("margin_top", 12)
	outer_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(outer_margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(440, 400)
	outer_margin.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var title := Label.new()
	title.text = "Creative Mode Setup"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("aed581"))
	root.add_child(title)

	_db_opt = _add_option_row(root, "Custom Database:")
	_sprite_opt = _add_option_row(root, "Custom Sprite Pack:")
	refresh_mod_options()

	_money_slider = _add_slider_row(root, "money", "Starting Money:", 0, 10000, 100, 500)
	_energy_slider = _add_slider_row(root, "energy", "Max Energy:", 10, 100, 5, 30)
	_time_lapse_slider = _add_slider_row(root, "time_lapse", "Time-Lapse Growth:", 1, 10, 1, 1)

	var staff_row := HBoxContainer.new()
	staff_row.add_theme_constant_override("separation", 12)
	var staff_lbl := Label.new()
	staff_lbl.text = "Pre-Staffed Farm Hands:"
	staff_lbl.custom_minimum_size = Vector2(200, 0)
	staff_row.add_child(staff_lbl)
	_pre_staffed_opt = OptionButton.new()
	_pre_staffed_opt.add_item("0 extra hands", 0)
	_pre_staffed_opt.add_item("1 extra hand (Digger)", 1)
	_pre_staffed_opt.add_item("2 extra hands (Digger + Tender)", 2)
	_pre_staffed_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	staff_row.add_child(_pre_staffed_opt)
	root.add_child(staff_row)

	_zen_check = _add_checkbox(root, "Zen Mode (No Death)")
	_weatherproof_check = _add_checkbox(root, "Weatherproof (No Frost/Drought)")
	_infinite_water_check = _add_checkbox(root, "Infinite Water (Free Watering)")

	_auto_harvest_check = _add_checkbox(root, "Auto-Harvest Mature Crops")
	_auto_harvest_check.button_pressed = true
	_auto_sell_check = _add_checkbox(root, "Auto-Sell Harvested Produce")
	_auto_sell_check.button_pressed = true
	_manual_bonus_slider = _add_slider_row(root, "manual_bonus", "Manual Energy Bonus:", 0, 50, 5, 10)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)

	var btn_cancel := Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.pressed.connect(func() -> void: cancel_creative.emit())
	btn_row.add_child(btn_cancel)

	var btn_launch := Button.new()
	btn_launch.text = "Launch Sandbox"
	btn_launch.pressed.connect(_on_launch_pressed)
	btn_row.add_child(btn_launch)
	root.add_child(btn_row)

	_refresh_slider_labels()


func refresh_mod_options() -> void:
	_populate_database_options()
	_populate_sprite_pack_options()


func _populate_database_options() -> void:
	_db_opt.clear()
	var idx := 0
	_db_opt.add_item("Default V3 Database")
	_db_opt.set_item_metadata(idx, "")
	idx += 1
	if not DirAccess.dir_exists_absolute(DATABASES_DIR):
		return
	var dir := DirAccess.open(DATABASES_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.to_lower().ends_with(".csv"):
			var full_path := DATABASES_DIR.path_join(entry)
			_db_opt.add_item(entry)
			_db_opt.set_item_metadata(idx, full_path)
			idx += 1
		entry = dir.get_next()
	dir.list_dir_end()


func _populate_sprite_pack_options() -> void:
	_sprite_opt.clear()
	var idx := 0
	_sprite_opt.add_item("Default Sprites")
	_sprite_opt.set_item_metadata(idx, "")
	idx += 1
	if DirAccess.dir_exists_absolute(SPRITES_DIR):
		_sprite_opt.add_item("All Custom Sprites (sprites/)")
		_sprite_opt.set_item_metadata(idx, SPRITES_DIR)
		idx += 1
		var dir := DirAccess.open(SPRITES_DIR)
		if dir != null:
			dir.list_dir_begin()
			var entry := dir.get_next()
			while entry != "":
				if dir.current_is_dir() and entry != "." and entry != "..":
					var folder_path := SPRITES_DIR.path_join(entry)
					_sprite_opt.add_item("Pack: %s" % entry)
					_sprite_opt.set_item_metadata(idx, folder_path)
					idx += 1
				elif not dir.current_is_dir() and entry.to_lower().ends_with(".png"):
					var png_path := SPRITES_DIR.path_join(entry)
					_sprite_opt.add_item(entry)
					_sprite_opt.set_item_metadata(idx, png_path)
					idx += 1
				entry = dir.get_next()
			dir.list_dir_end()


func _add_option_row(parent: VBoxContainer, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(200, 0)
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(opt)
	parent.add_child(row)
	return opt


func _add_slider_row(
	parent: VBoxContainer,
	slider_id: String,
	prefix: String,
	min_v: float,
	max_v: float,
	step: float,
	default_v: float
) -> HSlider:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	parent.add_child(block)

	var header := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = prefix
	lbl.custom_minimum_size = Vector2(200, 0)
	header.add_child(lbl)

	var value_lbl := Label.new()
	value_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(value_lbl)
	block.add_child(header)

	match slider_id:
		"money":
			_money_value_label = value_lbl
		"energy":
			_energy_value_label = value_lbl
		"time_lapse":
			_time_lapse_label = value_lbl
		"manual_bonus":
			_manual_bonus_label = value_lbl

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = default_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(_v: float) -> void: _refresh_slider_labels())
	block.add_child(slider)
	return slider


func _add_checkbox(parent: VBoxContainer, label_text: String) -> CheckBox:
	var row := HBoxContainer.new()
	var chk := CheckBox.new()
	chk.text = label_text
	chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(chk)
	parent.add_child(row)
	return chk


func _refresh_slider_labels() -> void:
	_money_value_label.text = "£%d" % int(_money_slider.value)
	_energy_value_label.text = str(int(_energy_slider.value))
	_time_lapse_label.text = "%dx" % int(_time_lapse_slider.value)
	if is_instance_valid(_manual_bonus_label):
		_manual_bonus_label.text = "+%d" % int(_manual_bonus_slider.value)


func _selected_metadata(opt: OptionButton) -> String:
	var i := opt.selected
	if i < 0 or i >= opt.item_count:
		return ""
	return str(opt.get_item_metadata(i))


func _on_launch_pressed() -> void:
	var overrides := {
		"money": int(_money_slider.value),
		"energy": int(_energy_slider.value),
		"time_lapse": float(_time_lapse_slider.value),
		"pre_staffed": _pre_staffed_opt.get_selected_id(),
		"zen_mode": _zen_check.button_pressed,
		"weatherproof": _weatherproof_check.button_pressed,
		"infinite_water": _infinite_water_check.button_pressed,
		"custom_database_path": _selected_metadata(_db_opt),
		"custom_sprite_pack_path": _selected_metadata(_sprite_opt),
		"auto_harvest": _auto_harvest_check.button_pressed,
		"auto_sell": _auto_sell_check.button_pressed,
		"manual_energy_bonus": int(_manual_bonus_slider.value),
	}
	launch_creative.emit(overrides)
