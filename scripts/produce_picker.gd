extends PanelContainer

signal action_chosen(action: String, item_key: String)

@onready var item_list: ItemList = $VBoxContainer/Item_List
@onready var btn_eat: Button = $VBoxContainer/HBoxContainer/Btn_Eat
@onready var btn_sell: Button = $VBoxContainer/HBoxContainer/Btn_Sell
@onready var btn_close: Button = $VBoxContainer/Btn_Close

var current_keys: Array = []
var selected_index: int = -1

func _ready() -> void:
	btn_close.pressed.connect(hide)
	item_list.item_selected.connect(_on_select)
	btn_eat.pressed.connect(func(): _on_action("eat"))
	btn_sell.pressed.connect(func(): _on_action("sell"))
	hide()

func populate_and_show(produce_dict: Dictionary) -> void:
	item_list.clear()
	current_keys.clear()
	selected_index = -1
	btn_eat.disabled = true
	btn_sell.disabled = true

	var plant_db = preload("res://data/data_plants.gd").DATA
	const ItemData := preload("res://scripts/data_items.gd")

	for key in produce_dict.keys():
		var count = produce_dict[key]
		if count <= 0:
			continue

		var p_name = key
		var e_yield = 3
		var m_yield = 2
		if key == "wild_greens":
			p_name = "Wild Greens"
		elif plant_db.has(key):
			p_name = plant_db[key]["name"]
			e_yield = plant_db[key].get("energy_yield", 5)
			m_yield = plant_db[key].get("yield_val", 5)
		else:
			var item_row: Dictionary = ItemData.get_item_data(key)
			if not item_row.is_empty():
				p_name = str(item_row.get("name", key))
				m_yield = int(item_row.get("value", m_yield))

		var pd := preload("res://data/data_plants.gd")
		var text = "%s (x%d) | +%d E | +£%d" % [
			p_name,
			count,
			pd.as_int(e_yield),
			pd.as_int(m_yield),
		]
		item_list.add_item(text)
		current_keys.append(key)

	if current_keys.is_empty():
		item_list.add_item("Inventory is empty.")

	show()

func _on_select(idx: int) -> void:
	if current_keys.is_empty():
		return
	selected_index = idx
	btn_eat.disabled = false
	btn_sell.disabled = false

func _on_action(action: String) -> void:
	if selected_index >= 0:
		action_chosen.emit(action, current_keys[selected_index])
