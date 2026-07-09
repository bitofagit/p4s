extends RefCounted
class_name PlantNutrientForecast
## Predicts per-turn plant soil exchange (mirrors `_process_plant_biology` exchange phase).

const LAYERS: Array[String] = ["canopy", "understory", "ground"]

const _DELTA_KEYS: Dictionary = {
	"moisture": "moisture_delta",
	"nitrogen": "nitrogen_delta",
	"minerals": "mineral_delta",
	"structure": "structure_delta",
	"toxicity": "toxicity_delta",
}

const _STAT_ORDER: Array[String] = [
	"moisture", "nitrogen", "minerals", "structure", "toxicity", "fungi", "bacteria", "macro_life",
]


static func compute(cell: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	var contributors: Array[Dictionary] = []
	var plant_db = preload("res://data/data_plants.gd")

	for layer in LAYERS:
		var p_id := str(cell.get(layer, ""))
		if p_id == "":
			continue
		var p_data: Dictionary = plant_db.get_plant_data(p_id)
		if p_data.is_empty():
			continue

		var age_key := "%s_age" % layer
		var plant_age := float(cell.get(age_key, 0.0))
		var stage := PlantGrowth.growth_stage(p_id, plant_age)
		var scaled: Dictionary = PlantGrowth.scaled_exchange_deltas(p_data, stage)

		var deltas: Dictionary = {}
		for stat in ["moisture", "nitrogen", "minerals", "structure", "toxicity"]:
			deltas[stat] = float(scaled.get(stat, 0))

		var fungi_gain: float = float(p_data.get("fungal_affinity", 0)) * 0.1
		if MetaManager.has_upgrade("ecto_fungi"):
			fungi_gain *= 1.2
		deltas["fungi"] = fungi_gain
		deltas["bacteria"] = float(p_data.get("bacterial_affinity", 0)) * 0.1
		deltas["macro_life"] = float(p_data.get("macro_life_affinity", 0)) * 0.1

		contributors.append({
			"layer": layer,
			"plant_id": p_id,
			"name": str(p_data.get("name", p_id.capitalize())),
			"growth_stage": stage,
			"stage_label": PlantGrowth.stage_label(stage),
			"deltas": deltas,
			"nitrogen_fixer": p_data.get("nitrogen_fixer", false) == true,
			"dynamic_accumulator": p_data.get("dynamic_accumulator", false) == true,
		})

		for stat in deltas:
			totals[stat] = float(totals.get(stat, 0.0)) + float(deltas[stat])

	return {"totals": totals, "contributors": contributors}


static func has_forecast(forecast: Dictionary) -> bool:
	return not (forecast.get("contributors", []) as Array).is_empty()


static func format_shift_tooltip_section(forecast: Dictionary) -> String:
	var contributors: Array = forecast.get("contributors", [])
	if contributors.is_empty():
		return ""

	var text := "\n---\n[b]Next turn · plant exchange[/b]\n"
	for c in contributors:
		if not c is Dictionary:
			continue
		var layer_name := str(c.get("layer", "")).capitalize()
		var plant_name := str(c.get("name", ""))
		var stage_label := str(c.get("stage_label", ""))
		if stage_label != "":
			text += "• [b]%s[/b] (%s · Stage: %s): " % [plant_name, layer_name, stage_label]
		else:
			text += "• [b]%s[/b] (%s): " % [plant_name, layer_name]
		var parts: PackedStringArray = []
		var deltas: Dictionary = c.get("deltas", {})
		for stat in _STAT_ORDER:
			var d: float = float(deltas.get(stat, 0.0))
			if absf(d) < 0.02:
				continue
			var col: Color = NutrientPalette.color_for(stat)
			parts.append(
				"[color=#%s]%s %+.2f[/color]" % [col.to_html(false), _stat_label(stat), d]
			)
		if parts.is_empty():
			text += "[color=#888888]steady[/color]"
		else:
			text += ", ".join(parts)
		var tags: PackedStringArray = []
		if c.get("nitrogen_fixer", false):
			tags.append("N-fixer")
		if c.get("dynamic_accumulator", false):
			tags.append("accumulator")
		if tags.size() > 0:
			text += " [color=#aed581](%s)[/color]" % ", ".join(tags)
		text += "\n"

	var totals: Dictionary = forecast.get("totals", {})
	var net_parts: PackedStringArray = []
	for stat in ["moisture", "nitrogen", "minerals"]:
		var t: float = float(totals.get(stat, 0.0))
		if absf(t) < 0.02:
			continue
		var col2: Color = NutrientPalette.color_for(stat)
		net_parts.append("[color=#%s]%s %+.2f[/color]" % [col2.to_html(false), _stat_label(stat), t])
	if net_parts.size() > 0:
		text += "[i]Net: " + ", ".join(net_parts) + "[/i]"
	return text


static func _stat_label(stat_id: String) -> String:
	match stat_id:
		"macro_life":
			return "Macro-life"
		_:
			return stat_id.capitalize()
