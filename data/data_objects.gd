extends Node

## Embedded content: placeable **buildings/zones** (cost, type, tile atlas_x, desc). Must stay in sync with tile atlas layout when changing art.
## Broader orientation: docs/CODEBASE_GUIDE.md (section 5).

const ENTRIES: Dictionary = {
	"house": {
		"name": "Farmhouse",
		"cost": 50,
		"type": "building",
		"atlas_x": 10, # CRITICAL: Must be 10!
		"desc": "Zone 0. The heart of the farm.",
	},
	"pig_house": {"name": "Pig House", "cost": 80, "type": "building", "atlas_x": 16},
	"duck_house": {"name": "Duck House", "cost": 50, "type": "building", "atlas_x": 12},
	"pen": {"name": "Animal Pen", "cost": 6, "type": "zone", "atlas_x": 17},
	"gate": {"name": "Gate", "cost": 12, "type": "building", "atlas_x": 18},
	"honesty_box": {"name": "Honesty Box", "cost": 25, "type": "building", "atlas_x": 15},
	"compost_brewer": {"name": "Compost Brewer", "cost": 40, "type": "building", "atlas_x": 19},
	"solar_panel": {
		"name": "Solar Panel",
		"cost": 100,
		"type": "building",
		"atlas_x": 20,
		"desc": "Generates power on clear nights (+5 storage cap).",
	},
	"battery": {
		"name": "Deep-Cycle Battery Array",
		"cost": 150,
		"type": "building",
		"atlas_x": 22,
		"desc": "Adds 100 units of stored power capacity.",
	},
	"water_butt": {
		"name": "Water Butt",
		"cost": 30,
		"type": "building",
		"atlas_x": 21,
		"desc": "Stores rainwater on rainy nights (50 cap per butt).",
	},
}
