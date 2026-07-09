extends Node

## Embedded content: plant **guild** defs (core crop, companions, growth_mult, yield_bonus, desc). Used for synergy rules / UI.
## Broader orientation: docs/CODEBASE_GUIDE.md (section 5).

const ENTRIES: Dictionary = {
	"orchard_trinity": {
		"name": "Orchard Trinity",
		"core": "apple",
		"companions": ["broad_bean", "daikon"],
		"growth_mult": 2.0,
		"yield_bonus": 2,
		"desc": "Beans fix nitrogen for the Canopy, while Daikon breaks clay to allow deep root hydration. Growth rate doubled."
	},
	"shade_garden": {
		"name": "Shade Garden",
		"core": "lettuce",
		"companions": ["apple"],
		"growth_mult": 1.5,
		"yield_bonus": 1,
		"desc": "Lettuce thrives in the cool, moist microclimate provided by the Apple canopy."
	},
	"the_three_sisters": {
		"name": "The Three Sisters",
		"core": "sweetcorn",
		"companions": ["climbing_bean", "squash"],
		"growth_mult": 2.5,
		"yield_bonus": 3,
		"desc": "An ancient polyculture. Corn provides a trellis, beans fix nitrogen, and squash acts as a living mulch to trap moisture."
	},
	"berry_thicket": {
		"name": "Berry Thicket",
		"core": "gooseberry",
		"companions": ["blackcurrant", "comfrey_b14"],
		"growth_mult": 1.8,
		"yield_bonus": 2,
		"desc": "Comfrey dynamically accumulates deep minerals to feed the heavy-fruiting understory bushes."
	},
	"pioneer_blast": {
		"name": "Pioneer Blast",
		"core": "white_clover",
		"companions": ["daikon", "dandelion"],
		"growth_mult": 1.5,
		"yield_bonus": 0, # Used purely for soil healing
		"desc": "An aggressive, fast-growing groundcover matrix designed to rapidly shatter compacted clay and inject nitrogen."
	}
}
