extends Node2D
class_name DataViewOverlayNode
## Per-cell bar charts (z above transfer waves); rim corridor left for waves.


class DataViewPanelOverlayNode extends Node2D:
	## Dark inner panel behind bars; drawn below transfer waves in the rim.
	var map_ref: Node2D

	func _process(_delta: float) -> void:
		if map_ref == null:
			return
		if map_ref.get("active_lens") not in ["soil_data", "plant_data"]:
			return
		queue_redraw()

	func _draw() -> void:
		if map_ref == null:
			return
		if map_ref.get("active_lens") not in ["soil_data", "plant_data"]:
			return
		var bounds: Rect2i = DataViewLayout.visible_tile_bounds(map_ref)
		if bounds.size.x <= 0:
			return
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
				var cell_tl: Vector2 = DataViewLayout.tile_top_left(map_ref, Vector2i(x, y))
				var inner: Rect2 = DataViewLayout.inner_rect(cell_tl)
				draw_rect(inner, Color(0.04, 0.05, 0.07, 0.72), true)
				draw_rect(inner, Color(0.22, 0.24, 0.28, 0.45), false, 1.5)

var map_ref: Node2D
var transfer_overlay: NutrientTransferOverlayNode

const _SOIL_STATS: Array[String] = [
	"moisture", "nitrogen", "minerals", "structure", "fungi", "bacteria",
]

const _PLANT_DELTA_STATS: Array[String] = [
	"moisture_delta", "nitrogen_delta", "mineral_delta", "toxicity_delta",
]


func _process(_delta: float) -> void:
	if map_ref == null:
		return
	if map_ref.get("active_lens") not in ["soil_data", "plant_data"]:
		return
	if map_ref.is_sleeping and (transfer_overlay == null or not transfer_overlay.is_visually_active()):
		return
	queue_redraw()


func _visible_tile_bounds() -> Rect2i:
	if map_ref == null:
		return Rect2i(0, 0, 0, 0)
	return DataViewLayout.visible_tile_bounds(map_ref)


func _animated_stat_value(cell_pos: Vector2i, stat_id: String, final_value: float) -> float:
	if transfer_overlay == null or map_ref == null:
		return final_value
	if not map_ref.is_sleeping and not DataViewLayout.waves_enabled(map_ref):
		return final_value
	var display: float = final_value
	for flow in transfer_overlay.get_active_flows():
		if str(flow.get("stat", "")) != stat_id:
			continue
		var t: float = float(flow.get("anim_t", 0.0))
		var amt: float = float(flow.get("amount", 0.0))
		var from_pos: Vector2i = flow.get("from", Vector2i.ZERO)
		var to_pos: Vector2i = flow.get("to", Vector2i.ZERO)
		if from_pos == cell_pos:
			display += amt * (1.0 - DataViewLayout.shrink_curve(t))
		if to_pos == cell_pos:
			display -= amt * (1.0 - DataViewLayout.grow_curve(t))
	return maxf(0.0, display)


func _draw() -> void:
	if map_ref == null:
		return
	if map_ref.is_sleeping and (transfer_overlay == null or not transfer_overlay.is_visually_active()):
		return
	var lens: String = str(map_ref.get("active_lens"))
	if lens not in ["soil_data", "plant_data"]:
		return

	var bounds: Rect2i = _visible_tile_bounds()
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return

	var font: Font = ThemeDB.fallback_font

	for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
		for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
			var cell_pos := Vector2i(x, y)
			var cell: Dictionary = FarmDataManager.grid_data[x][y]
			var cell_tl: Vector2 = DataViewLayout.tile_top_left(map_ref, cell_pos)
			if lens == "soil_data":
				_draw_soil_cell(cell_tl, cell_pos, cell, font)
			else:
				_draw_plant_cell(cell_tl, cell_pos, cell, font)


func _draw_soil_cell(cell_tl: Vector2, cell_pos: Vector2i, cell: Dictionary, font: Font) -> void:
	var origin: Vector2 = DataViewLayout.bar_panel_origin(cell_tl, _SOIL_STATS.size())
	var bar_w: float = DataViewLayout.bar_width(cell_tl)
	var forecast: Dictionary = PlantNutrientForecast.compute(cell).get("totals", {})
	var y_off := 0.0
	for stat in _SOIL_STATS:
		var final_v: float = float(cell.get(stat, 0.0))
		var raw: float = _animated_stat_value(cell_pos, stat, final_v)
		var bar_top: float = origin.y + y_off
		y_off = _draw_bar(origin, y_off, bar_w, stat, raw, NutrientPalette.BAR_FULL_SOIL, font)
		_draw_forecast_ghost(
			Vector2(origin.x, bar_top),
			bar_w,
			stat,
			raw,
			float(forecast.get(stat, 0.0))
		)


func _draw_plant_cell(cell_tl: Vector2, cell_pos: Vector2i, cell: Dictionary, font: Font) -> void:
	var top: Dictionary = map_ref.call("_top_plant_on_cell", cell) as Dictionary
	var inner: Rect2 = DataViewLayout.inner_rect(cell_tl)
	if not top.is_empty():
		var info: Dictionary = top
		var layer: String = str(info.get("layer", "ground"))
		var age_key: String = layer + "_age"
		var p_data: Dictionary = info.get("data", {})
		var age := float(cell.get(age_key, 0.0))
		var mature := maxf(float(PlantGrowth.days_to_mature(p_data)), 1.0)
		var bar_count: int = 1 + _PLANT_DELTA_STATS.size()
		var origin: Vector2 = DataViewLayout.bar_panel_origin(cell_tl, bar_count)
		var bar_w: float = DataViewLayout.bar_width(cell_tl)
		var y_off: float = _draw_bar(origin, 0.0, bar_w, "growth", age, mature, font)
		for stat in _PLANT_DELTA_STATS:
			var delta: float = float(p_data.get(stat, 0.0))
			if absf(delta) < 0.01 and stat == "toxicity_delta":
				continue
			var palette_key := stat.replace("_delta", "")
			y_off = _draw_delta_bar(origin, y_off, bar_w, palette_key, delta, font)
	else:
		draw_string(
			font,
			inner.position + Vector2(inner.size.x * 0.42, inner.size.y * 0.48),
			"—",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			DataViewLayout.FONT_SZ + 2,
			Color(0.5, 0.52, 0.55, 0.55)
		)


func _draw_bar(
	origin: Vector2,
	y_off: float,
	bar_w: float,
	stat_id: String,
	value: float,
	full: float,
	font: Font
) -> float:
	var col := NutrientPalette.color_for(stat_id)
	var frac := clampf(value / full, 0.0, 1.0)
	var y := origin.y + y_off
	draw_rect(Rect2(origin.x, y, bar_w, DataViewLayout.BAR_H), Color(0.05, 0.06, 0.08, 0.8), true)
	if frac > 0.0:
		draw_rect(
			Rect2(origin.x, y, bar_w * frac, DataViewLayout.BAR_H),
			Color(col.r, col.g, col.b, 0.94),
			true
		)
	var overflow := NutrientPalette.fmt_overflow(value, full)
	if overflow != "":
		draw_string(
			font,
			Vector2(origin.x + bar_w + 3.0, y + DataViewLayout.BAR_H - 1.0),
			overflow,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			DataViewLayout.FONT_SZ,
			col
		)
	return y_off + DataViewLayout.BAR_H + DataViewLayout.BAR_GAP


func _draw_forecast_ghost(
	bar_origin: Vector2,
	bar_w: float,
	stat_id: String,
	current: float,
	delta: float
) -> void:
	if absf(delta) < 0.02:
		return

	var full: float = NutrientPalette.BAR_FULL_SOIL
	var col := NutrientPalette.color_for(stat_id)
	col.a = 0.28
	if delta < 0.0:
		col = col.lerp(Color(0.92, 0.38, 0.38), 0.3)
		col.a = 0.34

	var cur_frac: float = clampf(current / full, 0.0, 1.0)
	var end_frac: float = clampf((current + delta) / full, 0.0, 1.05)
	var left: float = minf(cur_frac, end_frac)
	var right: float = maxf(cur_frac, end_frac)
	if right - left < 0.004:
		return

	var y: float = bar_origin.y
	var ghost_rect := Rect2(
		bar_origin.x + bar_w * left,
		y,
		bar_w * (right - left),
		DataViewLayout.BAR_H
	)
	draw_rect(ghost_rect, col, true)
	draw_rect(ghost_rect, Color(col.r, col.g, col.b, col.a + 0.22), false, 1.0)


func _draw_delta_bar(
	origin: Vector2,
	y_off: float,
	bar_w: float,
	palette_key: String,
	delta: float,
	font: Font
) -> float:
	var col := NutrientPalette.color_for(palette_key)
	if delta < 0.0:
		col = col.lerp(Color(0.95, 0.35, 0.35), 0.45)
	var mag := absf(delta)
	var full := NutrientPalette.BAR_FULL_DELTA
	var frac := clampf(mag / full, 0.0, 1.0)
	var y := origin.y + y_off
	draw_rect(Rect2(origin.x, y, bar_w, DataViewLayout.BAR_H), Color(0.05, 0.06, 0.08, 0.8), true)
	if frac > 0.0:
		draw_rect(
			Rect2(origin.x, y, bar_w * frac, DataViewLayout.BAR_H),
			Color(col.r, col.g, col.b, 0.9),
			true
		)
	var label := "%+.1f" % snappedf(delta, 0.1) if absf(delta) >= 0.05 else ""
	if label != "":
		draw_string(
			font,
			Vector2(origin.x + bar_w + 3.0, y + DataViewLayout.BAR_H - 1.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			DataViewLayout.FONT_SZ,
			col
		)
	return y_off + DataViewLayout.BAR_H + DataViewLayout.BAR_GAP
