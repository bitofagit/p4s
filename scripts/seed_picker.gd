extends PanelContainer

var allowed_seed_ids: Array = [] # If empty, all seeds are allowed

signal seed_chosen(seed_id: String)

@onready var tab_container: TabContainer = $VBoxContainer/TabContainer
@onready var cancel_button: Button = $VBoxContainer/Cancel_Button

var _tooltip_panel: PanelContainer
var _tooltip_label: RichTextLabel
var _hovered_plant_id: String = ""
var _tip_canvas: CanvasLayer

var list_keys: Dictionary = {
	"Canopy": [],
	"Understory": [],
	"Ground": [],
}


func _ready() -> void:
	add_to_group("seed_picker")

	cancel_button.pressed.connect(hide)

	for child in tab_container.get_children():
		if child is ItemList:
			child.item_activated.connect(_on_item_activated.bind(child.name))
			child.gui_input.connect(func(event): _on_list_gui_input(event, child))
			child.mouse_exited.connect(func(): _hovered_plant_id = "")

	call_deferred("_setup_tooltip_overlay")

	hide()


func _setup_tooltip_overlay() -> void:
	_tip_canvas = CanvasLayer.new()
	_tip_canvas.layer = 128
	get_tree().root.add_child(_tip_canvas)

	_tooltip_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.8, 0.8, 0.2, 1.0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_tooltip_panel.add_theme_stylebox_override("panel", style)
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.fit_content = true
	_tooltip_label.bbcode_enabled = false
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tooltip_panel.add_child(_tooltip_label)
	_tip_canvas.add_child(_tooltip_panel)
	_tooltip_panel.hide()

	visibility_changed.connect(func():
		if not visible and is_instance_valid(_tooltip_panel):
			_tooltip_panel.hide()
			_hovered_plant_id = ""
	)


func populate_and_show() -> void:
	for child in tab_container.get_children():
		if child is ItemList:
			child.clear()

	for key in list_keys.keys():
		list_keys[key].clear()

	var pd = preload("res://data/data_plants.gd") # Ensure this path matches your setup
	if pd.DATA.is_empty():
		pd._load_csv()

	for plant_id in pd.DATA.keys():
		if allowed_seed_ids.size() > 0 and not allowed_seed_ids.has(plant_id):
			continue

		var p = pd.DATA[plant_id]
		var text = "%s - £%d" % [
			p.get("name", "Unknown"),
			int(p.get("cost", 2)),
		]

		var layer_name := "Ground"
		var lyr := str(p.get("layer", "ground")).to_lower()
		if lyr == "canopy":
			layer_name = "Canopy"
		elif lyr == "understory":
			layer_name = "Understory"
		elif lyr == "ground":
			layer_name = "Ground"

		var target_list := tab_container.get_node_or_null(layer_name) as ItemList
		if target_list:
			target_list.add_item(text)
			list_keys[layer_name].append(plant_id)

	show()


func _process(_delta: float) -> void:
	if not is_instance_valid(_tooltip_panel):
		return
	if not visible:
		_tooltip_panel.hide()
		return

	if not Input.is_key_pressed(KEY_SHIFT) or _hovered_plant_id == "":
		_tooltip_panel.hide()
		return

	var d = preload("res://data/data_plants.gd").get_plant_data(_hovered_plant_id)
	if d.is_empty():
		_tooltip_panel.hide()
		return

	var pd := preload("res://data/data_plants.gd")
	var tip = "%s  (%s)\n" % [d.get("name", ""), d.get("latin_name", "")]
	tip += "£%d · %s · %s · turn %d\n" % [
		pd.as_int(d.get("cost", 0)),
		d.get("layer", ""),
		d.get("lifecycle", ""),
		pd.as_int(d.get("mature_turn", 0)),
	]
	tip += "---------------------\n"
	tip += "moisture  %d-%d  %+d/turn\n" % [
		pd.as_int(d.get("min_moisture", 0)),
		pd.as_int(d.get("max_moisture", 10)),
		pd.as_int(d.get("moisture_delta", 0)),
	]
	tip += "nitrogen  %d-%d  %+d/turn\n" % [
		pd.as_int(d.get("min_nitrogen", 0)),
		pd.as_int(d.get("max_nitrogen", 10)),
		pd.as_int(d.get("nitrogen_delta", 0)),
	]
	tip += "minerals  %d-%d  %+d/turn\n" % [
		pd.as_int(d.get("min_minerals", 0)),
		pd.as_int(d.get("max_minerals", 10)),
		pd.as_int(d.get("mineral_delta", 0)),
	]
	tip += "structure        %+d/turn\n" % pd.as_int(d.get("structure_delta", 0))
	tip += "---------------------\n"
	tip += "fungi %-2d  bact %-2d  macro %-2d\n" % [
		pd.as_int(d.get("fungal_affinity", 0)),
		pd.as_int(d.get("bacterial_affinity", 0)),
		pd.as_int(d.get("macro_life_affinity", 0)),
	]
	tip += "N-fix: %s  acc: %s  pH %s–%s" % [str(d.get("nitrogen_fixer", false)), str(d.get("dynamic_accumulator", false)), str(d.get("ideal_ph_min", "")), str(d.get("ideal_ph_max", ""))]

	_tooltip_label.text = tip
	_tooltip_panel.position = get_viewport().get_mouse_position() + Vector2(20, 20)
	_tooltip_panel.show()


func _on_list_gui_input(event: InputEvent, list: ItemList) -> void:
	if not event is InputEventMouseMotion:
		return
	var index: int = list.get_item_at_position(event.position)
	if index == -1:
		_hovered_plant_id = ""
		return
	if not list_keys.has(list.name) or index >= list_keys[list.name].size():
		_hovered_plant_id = ""
		return
	_hovered_plant_id = list_keys[list.name][index]


func _on_item_activated(index: int, list_name: String) -> void:
	var seed_id: String = list_keys[list_name][index]
	seed_chosen.emit(seed_id)
	hide()
