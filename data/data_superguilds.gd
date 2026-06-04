extends Node

const ENTRIES: Dictionary = {
	"sg001": {
		"name": "Three Sisters Core",
		"req_roles": {"tall_support": 1, "legume": 1, "groundcover": 1},
		"yield_mult": 1.4,
		"desc": "The oldest guild in the Americas. The tall support lifts the legume's leaves into the sun whilst the groundcover locks moisture below."
	},
	"sg002": {
		"name": "Orchard Core Guild",
		"req_roles": {"fruit_tree": 1, "dynamic_accumulator": 1, "nitrogen_fixer": 1},
		"yield_mult": 1.8,
		"desc": "The classic permaculture orchard trio. The nitrogen fixer restores what the fruit tree plunders and the dynamic accumulator mines deep minerals."
	},
	"sg_york_01": {
		"name": "Riparian Windbreak",
		"req_roles": {"nitrogen_fixer": 1, "wetland": 1, "windbreak": 1},
		"yield_mult": 1.0,
		"desc": "Alder's Frankia root bacteria activate when a windbreak shelters wet ground from drying winds."
	},
	"sg_york_02": {
		"name": "Temperate Orchard Stack",
		"req_roles": {"fruit_tree": 1, "nitrogen_fixer": 1, "dynamic_accumulator": 1},
		"yield_mult": 2.0,
		"desc": "When comfrey mines deep minerals and a nitrogen fixer restores what the fruit tree draws, the guild reaches full potential."
	},
	"sg_york_04": {
		"name": "The Hungry Valley",
		"req_roles": {"leafy_crop": 2, "nitrogen_fixer": 1},
		"yield_mult": 1.5,
		"desc": "Rhubarb and Cabbage are both famously hungry crops. When a nitrogen fixer stands between them, they reach their maximum yield."
	},
	"sg_york_08": {
		"name": "The Comfrey Engine",
		"req_roles": {"dynamic_accumulator": 1, "heavy_feeder": 1},
		"yield_mult": 1.0,
		"desc": "A single Comfrey plant adjacent to a heavy feeder activates a closed mineral loop, continuously mining subsoil minerals."
	},
	"sg_york_11": {
		"name": "The Clay Breakers",
		"req_roles": {"root_crop": 2, "structural": 2},
		"yield_mult": 1.1,
		"desc": "Two heavy root crops working the same neighbourhood shatter compacted clay from multiple depths simultaneously."
	}
}
