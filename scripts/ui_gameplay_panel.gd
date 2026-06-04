extends VBoxContainer

signal back_pressed

var _harvest_check: CheckButton
var _sell_check: CheckButton
var _bonus_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 15)

	var lbl := Label.new()
	lbl.text = "-- Gameplay Settings --"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)

	var hint := Label.new()
	hint.text = "Turn off automation to earn extra max energy (per disabled option)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.65, 0.75, 0.65))
	add_child(hint)

	_harvest_check = CheckButton.new()
	_harvest_check.text = "Auto-Harvest Mature Crops"
	_harvest_check.button_pressed = FarmDataManager.auto_harvest
	_harvest_check.toggled.connect(_on_auto_harvest_toggled)
	add_child(_harvest_check)

	_sell_check = CheckButton.new()
	_sell_check.text = "Auto-Sell Harvested Produce"
	_sell_check.button_pressed = FarmDataManager.auto_sell
	_sell_check.toggled.connect(_on_auto_sell_toggled)
	add_child(_sell_check)

	_bonus_label = Label.new()
	_bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bonus_label.add_theme_font_size_override("font_size", 12)
	add_child(_bonus_label)
	_refresh_bonus_hint()

	add_child(HSeparator.new())

	var btn_back := Button.new()
	btn_back.text = "Back"
	btn_back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(btn_back)


func sync_controls_from_farm() -> void:
	if is_instance_valid(_harvest_check):
		_harvest_check.button_pressed = FarmDataManager.auto_harvest
	if is_instance_valid(_sell_check):
		_sell_check.button_pressed = FarmDataManager.auto_sell
	_refresh_bonus_hint()


func _on_auto_harvest_toggled(enabled: bool) -> void:
	FarmDataManager.auto_harvest = enabled
	_persist_gameplay_settings()
	FarmDataManager.recalculate_energy_bonus()
	_refresh_bonus_hint()


func _on_auto_sell_toggled(enabled: bool) -> void:
	FarmDataManager.auto_sell = enabled
	_persist_gameplay_settings()
	FarmDataManager.recalculate_energy_bonus()
	_refresh_bonus_hint()


func _persist_gameplay_settings() -> void:
	if SaveManager.has_method("sync_gameplay_from_farm"):
		SaveManager.sync_gameplay_from_farm()
	else:
		SaveManager.gameplay_settings["auto_harvest"] = FarmDataManager.auto_harvest
		SaveManager.gameplay_settings["auto_sell"] = FarmDataManager.auto_sell
		SaveManager.gameplay_settings["manual_energy_bonus"] = FarmDataManager.manual_energy_bonus
	SaveManager.save_settings()


func _refresh_bonus_hint() -> void:
	if not is_instance_valid(_bonus_label):
		return
	var bonus := 0
	if not FarmDataManager.auto_harvest:
		bonus += FarmDataManager.manual_energy_bonus
	if not FarmDataManager.auto_sell:
		bonus += FarmDataManager.manual_energy_bonus
	_bonus_label.text = "Manual mode bonus: +%d max energy (base %d → %d)" % [
		bonus,
		FarmDataManager.base_max_energy,
		FarmDataManager.base_max_energy + bonus,
	]
