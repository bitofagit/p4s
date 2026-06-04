extends Node
class_name NarrativeData

## CSV-backed dialogue and lore. Paths resolve per campaign: user → res → `res://data/` fallback.
## Broader orientation: docs/CODEBASE_GUIDE.md (section 5).

static var DIALOGUES: Dictionary = {}
static var DAILY_LORE: Dictionary = {}
static var _loaded_campaign_id: String = ""


static func load_data(campaign_id: String = "") -> void:
	var cid := DataScenario.normalize_campaign_id(campaign_id)

	var user_campaign_dir := "user://campaigns/%s/" % cid
	DirAccess.make_dir_recursive_absolute(user_campaign_dir)

	DIALOGUES.clear()
	DAILY_LORE.clear()

	var lore_path := DataScenario.resolve_campaign_csv_path(cid, "lore.csv")
	var lore_file := FileAccess.open(lore_path, FileAccess.READ)
	if lore_file:
		lore_file.get_csv_line()
		while not lore_file.eof_reached():
			var line := lore_file.get_csv_line()
			if line.size() >= 2 and line[0] != "":
				DAILY_LORE[int(line[0])] = line[1].replace("\\n", "\n")
		lore_file.close()

	var dialogue_path := DataScenario.get_dialogue_csv_path(cid)
	var diag_file := FileAccess.open(dialogue_path, FileAccess.READ)
	if diag_file:
		var header := diag_file.get_csv_line()
		var key_col := 0
		if header.size() > 0 and str(header[0]).to_lower() == "day":
			key_col = 0
		elif header.size() > 0 and str(header[0]).to_lower() == "id":
			key_col = 0
		while not diag_file.eof_reached():
			var line := diag_file.get_csv_line()
			if line.size() >= 4 and line[key_col] != "":
				var d_id := str(line[key_col]).strip_edges()
				var d_title := str(line[1])
				var d_body := str(line[2]).replace("\\n", "\n")
				var raw_options := str(line[3]).strip_edges()

				var parsed_options := {}
				if raw_options != "":
					if "|" in raw_options or ":" in raw_options:
						var opt_pairs := raw_options.split("|")
						for pair in opt_pairs:
							var parts := pair.split(":")
							if parts.size() == 2:
								parsed_options[parts[0].strip_edges()] = parts[1].strip_edges()
					else:
						parsed_options["start"] = raw_options.strip_edges().trim_prefix('"').trim_suffix('"')

				var entry := {
					"title": d_title,
					"body": d_body,
					"options": parsed_options,
				}
				DIALOGUES[d_id] = entry
				if d_id == "0":
					DIALOGUES["intro"] = entry
		diag_file.close()

	_loaded_campaign_id = cid


static func get_dialogue(id: String) -> Dictionary:
	load_data(_active_campaign_id())
	return DIALOGUES.get(id, {})


static func get_lore(day: int) -> String:
	load_data(_active_campaign_id())
	return DAILY_LORE.get(day, "")


static func _active_campaign_id() -> String:
	var farm := Engine.get_main_loop()
	if farm == null:
		return DataScenario.DEFAULT_CAMPAIGN_ID
	var root = farm.root
	if root == null:
		return DataScenario.DEFAULT_CAMPAIGN_ID
	var fdm = root.get_node_or_null("/root/FarmDataManager")
	if fdm == null:
		return DataScenario.DEFAULT_CAMPAIGN_ID
	return DataScenario.normalize_campaign_id(str(fdm.get("active_campaign_id")))
