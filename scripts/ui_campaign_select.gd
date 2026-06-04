extends PanelContainer

signal cancel_campaign()

const DataScenario = preload("res://scripts/data_scenario.gd")

var _campaigns: Array[Dictionary] = []
var _campaign_list: ItemList
var _desc_label: RichTextLabel


func _ready() -> void:
	custom_minimum_size = Vector2(520, 420)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title = Label.new()
	title.text = "Select Campaign"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("aed581"))
	root.add_child(title)

	_campaign_list = ItemList.new()
	_campaign_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_campaign_list.custom_minimum_size = Vector2(0, 140)
	_campaign_list.item_selected.connect(_on_campaign_selected)
	_campaign_list.item_activated.connect(_on_campaign_activated)
	root.add_child(_campaign_list)

	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.fit_content = true
	_desc_label.custom_minimum_size = Vector2(0, 120)
	_desc_label.scroll_active = true
	_desc_label.text = "[color=#888888]Choose a campaign to see details.[/color]"
	root.add_child(_desc_label)

	var hint = Label.new()
	hint.text = "Double-click a campaign (or press Enter) to launch."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.55))
	root.add_child(hint)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)

	var btn_back = Button.new()
	btn_back.text = "Back"
	btn_back.pressed.connect(func() -> void: cancel_campaign.emit())
	btn_row.add_child(btn_back)

	root.add_child(btn_row)

	_populate_campaigns()


func _populate_campaigns() -> void:
	_campaign_list.clear()
	_campaigns = DataScenario.get_campaign_list()
	for i in range(_campaigns.size()):
		var campaign = _campaigns[i]
		_campaign_list.add_item(str(campaign.get("name", "Campaign")))
	if _campaigns.size() > 0:
		_campaign_list.select(0)
		_on_campaign_selected(0)
		_campaign_list.grab_focus()


func _on_campaign_selected(index: int) -> void:
	if index < 0 or index >= _campaigns.size():
		return
	var campaign = _campaigns[index]
	var bounds: Array = campaign.get("bounds", [6, 17])
	var min_x = int(bounds[0]) if bounds.size() > 0 else 6
	var max_x = int(bounds[1]) if bounds.size() > 1 else 17
	_desc_label.text = (
		"[b]%s[/b]\n\n%s\n\n"
		+ "[color=#888888]Map: %d × %d  |  Plot: x %d–%d  |  Starting money: £%d[/color]"
	) % [
		campaign.get("name", ""),
		campaign.get("desc", ""),
		int(campaign.get("width", 100)),
		int(campaign.get("height", 100)),
		min_x,
		max_x,
		int(campaign.get("money", 0)),
	]


func _overrides_from_campaign(c: Dictionary) -> Dictionary:
	var campaign_id = str(c.get("id", ""))
	var bounds: Array = c.get("bounds", [6, 17])
	var overrides: Dictionary = c.duplicate(true)
	overrides["id"] = campaign_id
	overrides["campaign_id"] = campaign_id
	overrides["active_campaign_id"] = campaign_id
	overrides["width"] = int(c.get("width", 100))
	overrides["height"] = int(c.get("height", 100))
	overrides["map_width"] = overrides["width"]
	overrides["map_height"] = overrides["height"]
	overrides["bounds"] = bounds
	overrides["money"] = int(c.get("money", 500))
	overrides["player_bounds_left"] = int(bounds[0]) if bounds.size() > 0 else 6
	overrides["player_bounds_right"] = int(bounds[1]) if bounds.size() > 1 else 93
	return overrides


func _on_campaign_activated(index: int) -> void:
	if index < 0 or index >= _campaigns.size():
		return
	var campaign = _campaigns[index]
	var overrides = _overrides_from_campaign(campaign)
	var farm = get_node_or_null("/root/FarmDataManager")
	if farm and farm.has_method("reset_data"):
		farm.reset_data(overrides)
	var meta = get_node_or_null("/root/MetaManager")
	if meta:
		meta.dev_mode = false
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		save_mgr.pending_load_save_name = ""
	get_tree().change_scene_to_file("res://scenes/world.tscn")
