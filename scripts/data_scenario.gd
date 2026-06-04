extends Node
class_name DataScenario

## CSV-backed scripted weather per campaign. Open-core campaigns declare `weather_csv` in `get_campaigns()`.

const DEFAULT_CAMPAIGN_ID := "tutorial"

static var STORY_WEATHER: Dictionary = {}
static var _loaded_campaign_id: String = ""


static func get_campaigns() -> Dictionary:
	return {
		"tutorial": {
			"name": "Permaculture 101",
			"description": "Learn the basics of soil ecology, earthworks, and standard guilds in this introductory open-core simulation.",
			"dialogue_csv": "res://data/opencore_dialogue.csv",
			"weather_csv": "res://data/opencore_weather.csv",
			"starting_money": 200,
			"map_width": 100,
			"map_height": 100,
			"bounds_left": 6,
			"bounds_right": 93,
		},
	}


## Normalized list for UI and `FarmDataManager` overrides (id, name, desc, width, height, bounds, money).
static func get_campaign_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var campaigns := get_campaigns()
	for cid in campaigns.keys():
		var raw: Dictionary = campaigns[cid]
		result.append({
			"id": cid,
			"name": raw.get("name", cid),
			"desc": raw.get("description", raw.get("desc", "")),
			"width": int(raw.get("map_width", raw.get("width", 100))),
			"height": int(raw.get("map_height", raw.get("height", 100))),
			"bounds": [
				int(raw.get("bounds_left", 6)),
				int(raw.get("bounds_right", 93)),
			],
			"money": int(raw.get("starting_money", raw.get("money", 200))),
			"dialogue_csv": str(raw.get("dialogue_csv", "")),
			"weather_csv": str(raw.get("weather_csv", "")),
		})
	return result


static func normalize_campaign_id(campaign_id: String) -> String:
	var cid := campaign_id.strip_edges()
	if cid != "" and get_campaigns().has(cid):
		return cid
	return DEFAULT_CAMPAIGN_ID


static func get_dialogue_csv_path(campaign_id: String) -> String:
	var cid := normalize_campaign_id(campaign_id)
	var def: Dictionary = get_campaigns().get(cid, {})
	if def.has("dialogue_csv"):
		var path := str(def["dialogue_csv"])
		if path != "" and (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
			return path
	return resolve_campaign_csv_path(cid, "dialogue.csv")


static func get_weather_csv_path(campaign_id: String) -> String:
	var cid := normalize_campaign_id(campaign_id)
	var def: Dictionary = get_campaigns().get(cid, {})
	if def.has("weather_csv"):
		var path := str(def["weather_csv"])
		if path != "" and (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
			return path
	return resolve_campaign_csv_path(cid, "story_weather.csv")


static func resolve_campaign_csv_path(campaign_id: String, filename: String) -> String:
	var cid := normalize_campaign_id(campaign_id)
	var user_path := "user://campaigns/%s/%s" % [cid, filename]
	if FileAccess.file_exists(user_path):
		return user_path
	var res_path := "res://campaigns/%s/%s" % [cid, filename]
	if ResourceLoader.exists(res_path) or FileAccess.file_exists(res_path):
		return res_path
	return "res://data/%s" % filename


static func load_data(campaign_id: String = DEFAULT_CAMPAIGN_ID) -> void:
	var cid := normalize_campaign_id(campaign_id)

	var user_campaign_dir := "user://campaigns/%s/" % cid
	DirAccess.make_dir_recursive_absolute(user_campaign_dir)

	STORY_WEATHER.clear()

	var weather_path := get_weather_csv_path(cid)
	var file := FileAccess.open(weather_path, FileAccess.READ)
	if file:
		file.get_csv_line()
		while not file.eof_reached():
			var line := file.get_csv_line()
			if line.size() >= 2 and line[0] != "":
				var day := int(line[0])
				var weather := str(line[1]).strip_edges().to_lower()
				STORY_WEATHER[day] = weather
		file.close()

	_loaded_campaign_id = cid


## Returns the scripted weather for a specific day, or an empty string if none is scripted.
static func get_scripted_weather(day: int) -> String:
	load_data(_active_campaign_id())
	return STORY_WEATHER.get(day, "")


static func _active_campaign_id() -> String:
	var farm := Engine.get_main_loop()
	if farm == null:
		return DEFAULT_CAMPAIGN_ID
	var root = farm.root
	if root == null:
		return DEFAULT_CAMPAIGN_ID
	var fdm = root.get_node_or_null("/root/FarmDataManager")
	if fdm == null:
		return DEFAULT_CAMPAIGN_ID
	return normalize_campaign_id(str(fdm.get("active_campaign_id")))
