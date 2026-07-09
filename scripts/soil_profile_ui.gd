extends Control
class_name SoilProfileUI
## Soil telemetry for the tile inspector: uniform rows with ProgressBars + explicit numbers (0–10).

const MAX_STAT := 10.0
const BAR_H := 16.0
const NAME_COL_W := 90.0
const VALUE_COL_W := 40.0

var _main: VBoxContainer
var vitality_header: RichTextLabel
var depth_value: Label
var ph_value: Label
var temp_value: Label

var bar_nitrogen: ProgressBar
var value_nitrogen: Label
var bar_minerals: ProgressBar
var value_minerals: Label

var bar_moisture: ProgressBar
var bar_structure: ProgressBar
var bar_fungi: ProgressBar
var bar_bacteria: ProgressBar
var bar_macro: ProgressBar
var bar_toxicity: ProgressBar

var value_moisture: Label
var value_structure: Label
var value_fungi: Label
var value_bacteria: Label
var value_macro: Label
var value_toxicity: Label
var _forecast_hint: Label


func _ready() -> void:
	custom_minimum_size = Vector2(260, 330)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func _create_stat_row(stat_name: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = stat_name
	name_label.custom_minimum_size.x = NAME_COL_W
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.82, 0.84, 0.86))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = MAX_STAT
	bar.step = 0.1
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, BAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var safe_zone = ColorRect.new()
	safe_zone.name = "SafeZone"
	safe_zone.color = Color(0.4, 0.9, 0.4, 0.25)
	safe_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_zone.hide()
	bar.add_child(safe_zone)

	var value_label := Label.new()
	value_label.custom_minimum_size.x = VALUE_COL_W
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	row.add_child(name_label)
	row.add_child(bar)
	row.add_child(value_label)

	return {
		"name_label": name_label,
		"bar": bar,
		"value_label": value_label,
		"row": row,
	}


func _build_ui() -> void:
	_main = VBoxContainer.new()
	_main.name = "SoilTelemetryVBox"
	_main.set_anchors_preset(PRESET_FULL_RECT)
	_main.add_theme_constant_override("separation", 10)
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main)

	vitality_header = RichTextLabel.new()
	vitality_header.name = "VitalityHeader"
	vitality_header.bbcode_enabled = true
	vitality_header.fit_content = true
	vitality_header.scroll_active = false
	vitality_header.autowrap_mode = TextServer.AUTOWRAP_OFF
	vitality_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vitality_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.add_child(vitality_header)

	var grid := GridContainer.new()
	grid.name = "SoilGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE

	grid.add_child(_grid_key("Depth (cm)"))
	depth_value = _grid_value()
	grid.add_child(depth_value)

	grid.add_child(_grid_key("pH"))
	ph_value = _grid_value()
	grid.add_child(ph_value)

	grid.add_child(_grid_key("Temp (°C)"))
	temp_value = _grid_value()
	grid.add_child(temp_value)

	_main.add_child(grid)

	var bars_block := VBoxContainer.new()
	bars_block.name = "BarStats"
	bars_block.add_theme_constant_override("separation", 8)
	bars_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var d_n := _create_stat_row("Nitrogen")
	bars_block.add_child(d_n.row)
	bar_nitrogen = d_n.bar
	value_nitrogen = d_n.value_label
	_tint_stat_row(d_n, "nitrogen")

	var d_min := _create_stat_row("Minerals")
	bars_block.add_child(d_min.row)
	bar_minerals = d_min.bar
	value_minerals = d_min.value_label
	_tint_stat_row(d_min, "minerals")

	var d_m := _create_stat_row("Moisture")
	bars_block.add_child(d_m.row)
	bar_moisture = d_m.bar
	value_moisture = d_m.value_label
	_tint_stat_row(d_m, "moisture")

	var d_s := _create_stat_row("Structure")
	bars_block.add_child(d_s.row)
	bar_structure = d_s.bar
	value_structure = d_s.value_label
	_tint_stat_row(d_s, "structure")

	var d_fu := _create_stat_row("Fungi")
	bars_block.add_child(d_fu.row)
	bar_fungi = d_fu.bar
	value_fungi = d_fu.value_label
	_tint_stat_row(d_fu, "fungi")

	var d_b := _create_stat_row("Bacteria")
	bars_block.add_child(d_b.row)
	bar_bacteria = d_b.bar
	value_bacteria = d_b.value_label
	_tint_stat_row(d_b, "bacteria")

	var d_ma := _create_stat_row("Macro-Life")
	bars_block.add_child(d_ma.row)
	bar_macro = d_ma.bar
	value_macro = d_ma.value_label
	_tint_stat_row(d_ma, "macro_life")

	var d_t := _create_stat_row("Toxicity")
	bars_block.add_child(d_t.row)
	bar_toxicity = d_t.bar
	value_toxicity = d_t.value_label
	_tint_stat_row(d_t, "toxicity")

	_main.add_child(bars_block)

	_forecast_hint = Label.new()
	_forecast_hint.name = "ForecastHint"
	_forecast_hint.text = "Frosted bar = next-turn plant change · Hold Shift on tile for per-plant detail"
	_forecast_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forecast_hint.add_theme_font_size_override("font_size", 10)
	_forecast_hint.add_theme_color_override("font_color", Color(0.52, 0.55, 0.58))
	_forecast_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forecast_hint.hide()
	_main.add_child(_forecast_hint)


func _grid_key(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size.x = NAME_COL_W
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.8))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _grid_value() -> Label:
	var lbl := Label.new()
	lbl.custom_minimum_size.x = VALUE_COL_W
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _tint_stat_row(row_data: Dictionary, stat_id: String) -> void:
	var name_lbl: Label = row_data.get("name_label")
	var value_lbl: Label = row_data.get("value_label")
	if is_instance_valid(name_lbl):
		NutrientPalette.apply_label_color(name_lbl, stat_id)
	if is_instance_valid(value_lbl):
		NutrientPalette.apply_label_color(value_lbl, stat_id)
	var bar: ProgressBar = row_data.get("bar")
	if is_instance_valid(bar):
		var fill := StyleBoxFlat.new()
		fill.bg_color = NutrientPalette.color_for(stat_id)
		bar.add_theme_stylebox_override("fill", fill)


func _fmt_bar_stat(v: float) -> String:
	# Allow numbers to exceed MAX_STAT so deep reservoirs display correctly
	return "%0.1f" % snappedf(v, 0.1)


func _apply_safe_zone(bar: ProgressBar, range_arr: Variant) -> void:
	var sz = bar.get_node_or_null("SafeZone") as ColorRect
	if not sz:
		return

	if range_arr is Array and range_arr.size() == 2:
		sz.show()
		var min_val = clampf(float(range_arr[0]), 0.0, MAX_STAT)
		var max_val = clampf(float(range_arr[1]), 0.0, MAX_STAT)

		# If incompatible plants are stacked, min might be higher than max!
		if min_val > max_val:
			sz.color = Color(0.9, 0.2, 0.2, 0.3) # Conflicting requirements (Red)
			var temp = min_val
			min_val = max_val
			max_val = temp
		else:
			sz.color = Color(0.4, 0.9, 0.4, 0.25) # Safe range (Green)

		sz.anchor_top = 0.0
		sz.anchor_bottom = 1.0
		sz.anchor_left = min_val / MAX_STAT
		sz.anchor_right = max_val / MAX_STAT
		sz.offset_left = 0
		sz.offset_right = 0
		sz.offset_top = 0
		sz.offset_bottom = 0
	else:
		sz.hide()


func _apply_forecast_ghost(bar: ProgressBar, current: float, delta: float, stat_id: String) -> void:
	var ghost := bar.get_node_or_null("ForecastGhost") as ColorRect
	if ghost == null:
		ghost = ColorRect.new()
		ghost.name = "ForecastGhost"
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(ghost)

	if absf(delta) < 0.02:
		ghost.hide()
		return

	ghost.show()
	var col := NutrientPalette.color_for(stat_id)
	col.a = 0.32
	if delta < 0.0:
		col = col.lerp(Color(0.92, 0.38, 0.38), 0.35)
		col.a = 0.38

	ghost.color = col
	var cur_frac: float = current / MAX_STAT
	var end_frac: float = (current + delta) / MAX_STAT
	var left: float = clampf(minf(cur_frac, end_frac), 0.0, 1.0)
	var right: float = clampf(maxf(cur_frac, end_frac), 0.0, 1.0)
	if right - left < 0.004:
		ghost.hide()
		return

	ghost.anchor_top = 0.0
	ghost.anchor_bottom = 1.0
	ghost.anchor_left = left
	ghost.anchor_right = right
	ghost.offset_left = 0
	ghost.offset_right = 0
	ghost.offset_top = 0
	ghost.offset_bottom = 0


func update_profile(stats: Dictionary) -> void:
	var raw_moisture: float = float(stats.get("moisture", 0.0))
	var raw_nitrogen: float = float(stats.get("nitrogen", 0.0))
	var raw_minerals: float = float(stats.get("minerals", 0.0))
	var raw_structure: float = float(stats.get("structure", 0.0))
	var raw_fungi: float = float(stats.get("fungi", 0.0))
	var raw_bacteria: float = float(stats.get("bacteria", 0.0))
	var raw_macro: float = float(stats.get("macro_life", 0.0))
	var raw_toxicity: float = float(stats.get("toxicity", 0.0))

	var depth_cm: float = clampf(float(stats.get("depth", 0)), 0.0, 120.0)
	var structure: float = clampf(raw_structure, 0.0, MAX_STAT)
	var moisture: float = clampf(raw_moisture, 0.0, MAX_STAT)
	var nitrogen: float = clampf(raw_nitrogen, 0.0, MAX_STAT)
	var minerals: float = clampf(raw_minerals, 0.0, MAX_STAT)
	var fungi: float = clampf(raw_fungi, 0.0, MAX_STAT)
	var bacteria: float = clampf(raw_bacteria, 0.0, MAX_STAT)
	var macro_life: float = clampf(raw_macro, 0.0, MAX_STAT)
	var ph: float = clampf(float(stats.get("ph", 7.0)), 0.0, 14.0)
	var toxicity: float = clampf(raw_toxicity, 0.0, MAX_STAT)
	var temp_i: int = int(stats.get("temp", 15))

	depth_value.text = str(int(round(depth_cm)))
	ph_value.text = "%0.1f" % ph
	temp_value.text = str(temp_i)

	bar_moisture.value = moisture
	bar_nitrogen.value = nitrogen
	bar_minerals.value = minerals
	bar_structure.value = structure
	bar_fungi.value = fungi
	bar_bacteria.value = bacteria
	bar_macro.value = macro_life
	bar_toxicity.value = toxicity

	value_moisture.text = _fmt_bar_stat(raw_moisture)
	value_nitrogen.text = _fmt_bar_stat(raw_nitrogen)
	value_minerals.text = _fmt_bar_stat(raw_minerals)
	value_structure.text = _fmt_bar_stat(raw_structure)
	value_fungi.text = _fmt_bar_stat(raw_fungi)
	value_bacteria.text = _fmt_bar_stat(raw_bacteria)
	value_macro.text = _fmt_bar_stat(raw_macro)
	value_toxicity.text = _fmt_bar_stat(raw_toxicity)

	var reqs = stats.get("reqs", {})
	_apply_safe_zone(bar_moisture, reqs.get("moisture"))
	_apply_safe_zone(bar_nitrogen, reqs.get("nitrogen"))
	_apply_safe_zone(bar_minerals, reqs.get("minerals"))

	var forecast: Dictionary = stats.get("forecast", {})
	var ftotals: Dictionary = forecast.get("totals", {})
	_apply_forecast_ghost(bar_moisture, raw_moisture, float(ftotals.get("moisture", 0.0)), "moisture")
	_apply_forecast_ghost(bar_nitrogen, raw_nitrogen, float(ftotals.get("nitrogen", 0.0)), "nitrogen")
	_apply_forecast_ghost(bar_minerals, raw_minerals, float(ftotals.get("minerals", 0.0)), "minerals")
	_apply_forecast_ghost(bar_structure, raw_structure, float(ftotals.get("structure", 0.0)), "structure")
	_apply_forecast_ghost(bar_fungi, raw_fungi, float(ftotals.get("fungi", 0.0)), "fungi")
	_apply_forecast_ghost(bar_bacteria, raw_bacteria, float(ftotals.get("bacteria", 0.0)), "bacteria")
	_apply_forecast_ghost(bar_macro, raw_macro, float(ftotals.get("macro_life", 0.0)), "macro_life")
	_apply_forecast_ghost(bar_toxicity, raw_toxicity, float(ftotals.get("toxicity", 0.0)), "toxicity")

	if is_instance_valid(_forecast_hint):
		_forecast_hint.visible = PlantNutrientForecast.has_forecast(forecast)

	var vitality_pct := ((fungi * bacteria * macro_life) / 1000.0) * 100.0
	vitality_pct = clampf(vitality_pct, 0.0, 100.0)
	var vi := int(round(vitality_pct))
	vitality_header.text = "[center][b]Vitality[/b] · [color=#aed581]%d%%[/color][/center]" % vi
