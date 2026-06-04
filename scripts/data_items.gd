extends Node

## Base item definitions for physical inventory (produce, materials).
## Plant harvests typically use the plant `id` as the inventory key; see `get_item_data`.

static var DATA: Dictionary = {
	"base_produce": {
		"name": "Generic Produce",
		"type": "produce",
		"value": 5,
		"atlas_x": 0,
	},
	"wood": {
		"name": "Chopped Wood",
		"type": "material",
		"value": 2,
		"atlas_x": 1,
	},
}


static func get_item_data(id: String) -> Dictionary:
	if DATA.has(id):
		return DATA[id]
	return {}
