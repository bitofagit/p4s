extends Node

## Embedded content: meta **upgrade** BBCode blurbs (titles align with MetaManager upgrade names).
## Costs and unlock logic live in `meta_manager.gd`. Broader orientation: docs/CODEBASE_GUIDE.md.

const ENTRIES: Dictionary = {
	"Starter Grant": """[font_size=24][color=#ffb74d][b]Starter Grant (Agricultural)[/b][/color][/font_size]

[color=#81c784][b]Effect:[/b][/color] Start with +£30.

A one-time field subsidy from the training programme's seed fund.""",

	"Ergonomic Tools": """[font_size=24][color=#ffb74d][b]Ergonomic Tools (Agricultural)[/b][/color][/font_size]

[color=#81c784][b]Effect:[/b][/color] Uprooting weeds costs 1 Energy instead of 2.

Better leverage and grip reduce strain on repetitive clearing work.""",

	"Automated Maintenance": """[font_size=24][color=#4fc3f7][b]Automated Maintenance (Systemic)[/b][/color][/font_size]

[color=#81c784][b]Effect:[/b][/color] +2 Maximum Energy for all future runs.

Scheduled overnight routines and lighter tool loads raise your daily work capacity.""",

	"Inoculated Soil": """[font_size=24][color=#4fc3f7][b]Inoculated Soil (Systemic)[/b][/color][/font_size]

[color=#81c784][b]Effect:[/b][/color] Fungal affinity scales 20% faster across the grid.

Pre-inoculated mycorrhizal networks establish in the rhizosphere sooner.""",

	"Premium Organic Certification": """[font_size=24][color=#4fc3f7][b]Premium Organic Certification (Systemic)[/b][/color][/font_size]

[color=#81c784][b]Effect:[/b][/color] Farm stand +£2 extra per sale and harvested crops sell for +20%.

Certified produce commands higher prices at the honesty box and market."""
}
