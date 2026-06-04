extends Node

## MetaManager (autoload): **cross-save** progression — Insight (research points), purchased upgrades, dev_mode flag.
## Persisted separately from farm saves (`user://shadow_logic_meta.json`). Farm state is FarmDataManager + SaveManager.
## Broader orientation: docs/CODEBASE_GUIDE.md

const SAVE_PATH = "user://shadow_logic_meta.json"

var current_insight: int = 0
var unlocked_upgrades: Array = []
var dev_mode: bool = false # Sandbox: skip training script and scripted weather
var magnetic_docking: bool = true

var upgrade_db = {
	"trust_fund": {
		"name": "Starter Grant",
		"type": "Agricultural",
		"cost": 10,
		"desc": "Field subsidy. Start with +£30."
	},
	"thick_gloves": {
		"name": "Ergonomic Tools",
		"type": "Agricultural",
		"cost": 15,
		"desc": "Uprooting costs 1 Energy instead of 2."
	},
	"poltergeist_labour": {
		"name": "Automated Maintenance",
		"type": "Systemic",
		"cost": 25,
		"desc": "+2 Maximum Energy each run."
	},
	"ecto_fungi": {
		"name": "Inoculated Soil",
		"type": "Systemic",
		"cost": 30,
		"desc": "Fungal affinity gains +20% from plants."
	},
	"hypnotic_charm": {
		"name": "Premium Organic Certification",
		"type": "Systemic",
		"cost": 40,
		"desc": "Farm stand +£2 per sale; crop sales +20%."
	}
}


func _ready() -> void:
	load_meta()


func load_meta() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	if data and typeof(data) == TYPE_DICTIONARY:
		if data.has("insight"):
			current_insight = int(data.get("insight", 0))
		else:
			current_insight = int(data.get("karma", 0)) # legacy save key
		unlocked_upgrades = data.get("unlocked", [])
		magnetic_docking = bool(data.get("magnetic_docking", true))


func save_meta() -> void:
	var data = {
		"insight": current_insight,
		"unlocked": unlocked_upgrades,
		"magnetic_docking": magnetic_docking
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))


func has_upgrade(id: String) -> bool:
	return unlocked_upgrades.has(id)


func buy_upgrade(id: String) -> bool:
	if not upgrade_db.has(id) or has_upgrade(id):
		return false
	var cost = upgrade_db[id]["cost"]
	if current_insight >= cost:
		current_insight -= cost
		unlocked_upgrades.append(id)
		save_meta()
		return true
	return false
