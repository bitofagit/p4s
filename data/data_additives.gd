extends Node

## Embedded content: soil **additive** shop text (cost/effect BBCode) for UI; gameplay numbers may also exist in `starting_map` additive tables.
## Broader orientation: docs/CODEBASE_GUIDE.md (section 5).

const ENTRIES: Dictionary = {
	"Aged Compost": """[font_size=24][color=#8d6e63][b]Aged Compost[/b][/color][/font_size]

[color=#ffcc80][b]Cost:[/b][/color] £5
[color=#4fc3f7][b]Effect:[/b][/color] +5.0 Nitrogen, +2.0 Moisture Capacity

Rich, dark, crumbly organic matter. Provides an immediate hit of available nitrogen to hungry crops and introduces beneficial microbes to dead soil.""",

	"Hardwood Woodchip": """[font_size=24][color=#8d6e63][b]Hardwood Woodchip[/b][/color][/font_size]

[color=#ffcc80][b]Cost:[/b][/color] £3
[color=#4fc3f7][b]Effect:[/b][/color] +10.0 Moisture Retention, -1.0 Nitrogen (Temporary Drawdown)

A heavy fungal mulch. Brilliant at stopping flash evaporation on bare soil. Note: The fungi require nitrogen to break the wood down, causing a temporary dip in soil nutrients.""",

	"Biochar": """[font_size=24][color=#8d6e63][b]Inoculated Biochar[/b][/color][/font_size]

[color=#ffcc80][b]Cost:[/b][/color] £12
[color=#4fc3f7][b]Effect:[/b][/color] Permanent +5.0 to Maximum Moisture Capacity

Pure carbon baked in a low-oxygen retort, soaked in compost tea. It acts as a permanent microscopic sponge in the soil, housing water and bacteria for centuries.""",

	"Blood and Bone": """[font_size=24][color=#8d6e63][b]Blood and Bone Meal[/b][/color][/font_size]

[color=#ffcc80][b]Cost:[/b][/color] £8
[color=#4fc3f7][b]Effect:[/b][/color] +8.0 Nitrogen

A potent, fast-acting organic fertiliser derived from abattoir waste. Excellent for emergency feeding when heavy fruit trees have entirely stripped the soil of nutrients."""
}
