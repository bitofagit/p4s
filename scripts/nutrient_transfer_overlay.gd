extends Node2D
class_name NutrientTransferOverlayNode
## Rim nutrient waves synced to sleep: prelude on space, dissipate at wake.

const FLOW_THRESHOLD := 0.03
const MAX_FLOW_LINES := 320

const PIXEL_SZ := 7.0
const SWELL_COUNT := 2
const LAP_COUNT := 3
const CREST_STEPS := 12
const MIN_CROSS_PX := 3
const MAX_CROSS_PX := 11
const FLOW_WIDTH_REF := 1.2

const _STAT_ORDER: Array[String] = ["moisture", "nitrogen", "minerals"]
const _CARDINAL_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1),
]

var map_ref: Node2D
var _flows: Array[Dictionary] = []
var _sleep_epoch: float = 0.0
var _session_lifetime: float = DataViewLayout.FLOW_LIFETIME
var _prelude_active: bool = false

const _TRANSFER_STATS: Array[String] = ["moisture", "nitrogen", "minerals"]
const _NEIGHBOR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]


func clear_flows() -> void:
	_flows.clear()
	_prelude_active = false
	queue_redraw()


func begin_sleep_vibe(epoch: float) -> void:
	_sleep_epoch = epoch
	_prelude_active = true
	_flows.clear()
	_session_lifetime = 14.0
	queue_redraw()


func finish_sleep_waves(epoch: float) -> void:
	if epoch > 0.0:
		_sleep_epoch = epoch
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = maxf(0.1, now - _sleep_epoch)
	_session_lifetime = elapsed
	_prelude_active = false
	queue_redraw()


func is_visually_active() -> bool:
	if _prelude_active:
		return true
	return not _flows.is_empty() and _count_live_flows(Time.get_ticks_msec() / 1000.0) > 0


func has_active_flows() -> bool:
	if map_ref == null:
		return false
	if not _flows.is_empty():
		if map_ref.is_sleeping:
			return _count_live_flows(Time.get_ticks_msec() / 1000.0) > 0
		return DataViewLayout.waves_enabled(map_ref)
	return false


func _flow_lifetime() -> float:
	return maxf(_session_lifetime, 1.0)


func _travel_sec() -> float:
	return clampf(_flow_lifetime() * 0.38, 1.4, 4.5)


func _count_live_flows(now: float) -> int:
	var life := _flow_lifetime()
	var n := 0
	for flow in _flows:
		if now - float(flow.get("born", 0.0)) < life:
			n += 1
	return n


func get_active_flows() -> Array[Dictionary]:
	if map_ref == null or _flows.is_empty():
		return []
	if not map_ref.is_sleeping and not DataViewLayout.waves_enabled(map_ref):
		return []
	var now: float = Time.get_ticks_msec() / 1000.0
	var travel := _travel_sec()
	var out: Array[Dictionary] = []
	for flow in _flows:
		var age: float = now - float(flow.get("born", 0.0))
		if age >= _flow_lifetime():
			continue
		var copy: Dictionary = flow.duplicate()
		copy["anim_t"] = clampf(age / travel, 0.0, 1.0)
		copy["age"] = age
		out.append(copy)
	return out


func show_turn_transfers(
	snapshot: Dictionary,
	recorded: Array,
	born_time: float = -1.0,
	lifetime: float = -1.0
) -> void:
	_prelude_active = false
	_flows.clear()
	var merged: Dictionary = {}
	var now: float = Time.get_ticks_msec() / 1000.0
	var born: float = born_time if born_time >= 0.0 else now

	if lifetime > 0.0:
		_session_lifetime = lifetime

	for raw in recorded:
		if raw is Dictionary:
			_merge_flow(merged, raw)

	_infer_flows_from_snapshot(snapshot, merged)

	var ranked: Array[Dictionary] = []
	for key in merged:
		var entry: Dictionary = merged[key]
		if float(entry.get("amount", 0.0)) >= FLOW_THRESHOLD:
			ranked.append(entry)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("amount", 0.0)) > float(b.get("amount", 0.0))
	)

	for i in range(mini(ranked.size(), MAX_FLOW_LINES)):
		var flow: Dictionary = ranked[i]
		flow["born"] = born
		_flows.append(flow)

	queue_redraw()


func _flow_key(from_pos: Vector2i, to_pos: Vector2i, stat: String) -> String:
	return "%d,%d->%d,%d:%s" % [from_pos.x, from_pos.y, to_pos.x, to_pos.y, stat]


func _edge_key(from_pos: Vector2i, to_pos: Vector2i) -> String:
	return "%d,%d>%d,%d" % [from_pos.x, from_pos.y, to_pos.x, to_pos.y]


func _merge_flow(merged: Dictionary, flow: Dictionary) -> void:
	var from_pos: Vector2i = flow.get("from", Vector2i.ZERO)
	var to_pos: Vector2i = flow.get("to", Vector2i.ZERO)
	var stat: String = str(flow.get("stat", "moisture"))
	var amount: float = float(flow.get("amount", 0.0))
	if amount <= 0.0 or from_pos == to_pos:
		return
	var key := _flow_key(from_pos, to_pos, stat)
	if merged.has(key):
		merged[key]["amount"] = float(merged[key].get("amount", 0.0)) + amount
	else:
		merged[key] = {
			"from": from_pos,
			"to": to_pos,
			"stat": stat,
			"amount": amount,
		}


func _infer_flows_from_snapshot(snapshot: Dictionary, merged: Dictionary) -> void:
	var w: int = FarmDataManager.map_width
	var h: int = FarmDataManager.map_height
	for stat in _TRANSFER_STATS:
		var before: PackedFloat32Array = snapshot.get(stat, PackedFloat32Array())
		if before.size() != w * h:
			continue
		for x in range(w):
			for y in range(h):
				var idx: int = y * w + x
				var cell: Dictionary = FarmDataManager.grid_data[x][y]
				var after_self: float = float(cell.get(stat, 0.0))
				var delta_self: float = after_self - before[idx]
				if delta_self >= -FLOW_THRESHOLD:
					continue
				for d in _NEIGHBOR_DIRS:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var nidx: int = ny * w + nx
					var after_n: float = float(FarmDataManager.grid_data[nx][ny].get(stat, 0.0))
					var delta_n: float = after_n - before[nidx]
					if delta_n <= FLOW_THRESHOLD:
						continue
					var amt: float = minf(-delta_self, delta_n)
					if amt < FLOW_THRESHOLD:
						continue
					_merge_flow(merged, {
						"from": Vector2i(x, y),
						"to": Vector2i(nx, ny),
						"stat": stat,
						"amount": amt,
					})


func _process(_delta: float) -> void:
	if map_ref == null:
		return
	if map_ref.get("active_lens") not in ["soil_data", "plant_data"]:
		return
	if map_ref.is_sleeping:
		if not is_visually_active():
			return
	elif _flows.is_empty():
		return
	queue_redraw()
	if _flows.is_empty():
		return
	if not map_ref.is_sleeping and not DataViewLayout.waves_enabled(map_ref):
		return
	if _count_live_flows(Time.get_ticks_msec() / 1000.0) == 0:
		_flows.clear()
		_prelude_active = false


func _draw() -> void:
	if map_ref == null:
		return
	if map_ref.get("active_lens") not in ["soil_data", "plant_data"]:
		return
	if not map_ref.is_sleeping and not DataViewLayout.waves_enabled(map_ref):
		return

	var bounds: Rect2i = DataViewLayout.visible_tile_bounds(map_ref)
	var now: float = Time.get_ticks_msec() / 1000.0

	if _prelude_active and _flows.is_empty():
		_draw_sleep_prelude(bounds, now)
		return

	if _flows.is_empty():
		return

	var ribbons: Array[Dictionary] = _collect_edge_ribbons(bounds, now)
	ribbons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("total", 0.0)) < float(b.get("total", 0.0))
	)

	var drawn: int = 0
	for ribbon in ribbons:
		if drawn >= DataViewLayout.MAX_VISIBLE_WAVES:
			break
		_draw_harmonic_flow(ribbon, now)
		drawn += 1


func _draw_sleep_prelude(bounds: Rect2i, now: float) -> void:
	var age: float = now - _sleep_epoch
	var breath: float = 0.5 + 0.5 * sin(age * 2.2)
	var alpha: float = 0.22 * breath
	var pixel: float = PIXEL_SZ * DataViewLayout.wave_draw_scale(map_ref)

	for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
		for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
			for d in _CARDINAL_DIRS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= FarmDataManager.map_width or ny >= FarmDataManager.map_height:
					continue
				var cell: Dictionary = FarmDataManager.grid_data[x][y]
				var ncell: Dictionary = FarmDataManager.grid_data[nx][ny]
				var mo: float = float(cell.get("moisture", 0.0))
				var nmo: float = float(ncell.get("moisture", 0.0))
				if absf(mo - nmo) < 0.15:
					continue
				var from_cell := Vector2i(x, y)
				var to_cell := Vector2i(nx, ny)
				if mo < nmo:
					from_cell = Vector2i(nx, ny)
					to_cell = Vector2i(x, y)
				var phase: float = age * 1.6 + float(x) * 0.17 + float(y) * 0.23
				for step in range(8):
					var t: float = float(step) / 7.0
					var pt: Vector2 = DataViewLayout.shore_wave_point(
						map_ref, from_cell, to_cell, t, age, phase, -2.0
					)
					var rim_out: Vector2 = DataViewLayout.rim_exit_px(map_ref, from_cell, to_cell)
					var rim_in: Vector2 = DataViewLayout.rim_entry_px(map_ref, from_cell, to_cell)
					var dir: Vector2 = (rim_in - rim_out).normalized()
					var norm: Vector2 = Vector2(-dir.y, dir.x)
					var col := Color(0.55, 0.82, 1.0, alpha * (0.6 + 0.4 * sin(t * PI + age)))
					_draw_soft_dot(pt, norm, col, col.a, pixel * 0.9)


func _collect_edge_ribbons(bounds: Rect2i, now: float) -> Array[Dictionary]:
	var edge_map: Dictionary = {}
	var life := _flow_lifetime()
	for flow in _flows:
		var age: float = now - float(flow.get("born", 0.0))
		if age >= life:
			continue
		var from_cell: Vector2i = flow["from"]
		var to_cell: Vector2i = flow["to"]
		if not DataViewLayout.cell_in_bounds(from_cell, bounds) and not DataViewLayout.cell_in_bounds(to_cell, bounds):
			continue
		var ekey := _edge_key(from_cell, to_cell)
		if not edge_map.has(ekey):
			edge_map[ekey] = {
				"from": from_cell,
				"to": to_cell,
				"born": float(flow.get("born", 0.0)),
				"amounts": {},
				"total": 0.0,
			}
		var entry: Dictionary = edge_map[ekey]
		var stat: String = str(flow.get("stat", "moisture"))
		var amt: float = float(flow.get("amount", 0.0))
		var amounts: Dictionary = entry["amounts"]
		amounts[stat] = float(amounts.get(stat, 0.0)) + amt
		entry["total"] = float(entry.get("total", 0.0)) + amt

	var out: Array[Dictionary] = []
	for ekey in edge_map:
		var e: Dictionary = edge_map[ekey]
		if float(e.get("total", 0.0)) < FLOW_THRESHOLD:
			continue
		out.append(e)
	return out


func _fade_for_age(age: float) -> float:
	var life := _flow_lifetime()
	var t: float = clampf(age / life, 0.0, 1.0)
	# Gentle ease-out: strong mid-sleep, soft tail at wake.
	var base: float = 1.0 - t * t * (3.0 - 2.0 * t)
	var shimmer: float = 0.88 + 0.12 * sin(age * 1.35)
	return clampf(base * shimmer, 0.0, 1.0)


func _draw_harmonic_flow(ribbon: Dictionary, now: float) -> void:
	var from_cell: Vector2i = ribbon["from"]
	var to_cell: Vector2i = ribbon["to"]
	var total: float = float(ribbon.get("total", 0.0))
	var amounts: Dictionary = ribbon["amounts"]
	var age: float = now - float(ribbon.get("born", 0.0))
	var fade: float = _fade_for_age(age)

	var rim_out: Vector2 = DataViewLayout.rim_exit_px(map_ref, from_cell, to_cell)
	var rim_in: Vector2 = DataViewLayout.rim_entry_px(map_ref, from_cell, to_cell)
	var dir: Vector2 = (rim_in - rim_out).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	var norm: Vector2 = Vector2(-dir.y, dir.x)

	var pixel: float = PIXEL_SZ * DataViewLayout.wave_draw_scale(map_ref)
	var cross_px: int = clampi(
		int(round(lerpf(float(MIN_CROSS_PX), float(MAX_CROSS_PX), clampf(total / FLOW_WIDTH_REF, 0.0, 1.0)))),
		MIN_CROSS_PX,
		MAX_CROSS_PX
	)
	var band_px: Dictionary = _allocate_band_pixels(amounts, total, cross_px)
	if band_px.is_empty():
		return

	var phase_seed: float = float(from_cell.x) * 0.41 + float(from_cell.y) * 0.73
	var harmony: Color = _harmonic_blend(amounts, total)
	var travel := _travel_sec()

	# Soft underglow trail.
	var trail := PackedVector2Array()
	for step in range(16):
		var t: float = float(step) / 15.0
		trail.append(DataViewLayout.shore_wave_point(
			map_ref, from_cell, to_cell, t, age, phase_seed, 0.0
		))
	draw_polyline(trail, Color(harmony.r, harmony.g, harmony.b, 0.14 * fade), pixel * 2.2, true)

	# Two gentle swells rolling source → shore.
	for swell_i in range(SWELL_COUNT):
		var swell_phase: float = fmod(age / travel + float(swell_i) * 0.48, 1.0)
		var crest_t: float = swell_phase * 0.9 + 0.05
		_draw_soft_crest(from_cell, to_cell, crest_t, norm, band_px, harmony, fade * 0.9, pixel, age, phase_seed)

	# Shore lap + receive bloom.
	for lap_i in range(LAP_COUNT):
		var lap_phase: float = fmod(age * 0.85 + float(lap_i) * 0.28, 1.0)
		var lap_t: float = lerpf(0.7, 0.97, lap_phase)
		var lap_pt: Vector2 = DataViewLayout.shore_wave_point(
			map_ref, from_cell, to_cell, lap_t, age, phase_seed, float(lap_i) + 8.0
		)
		var lap_a: float = (1.0 - lap_phase) * fade * 0.75
		_draw_soft_dot(lap_pt, norm, harmony.lightened(0.35), lap_a, pixel * 1.1)
		if lap_phase < 0.35:
			_draw_soft_dot(rim_in, norm, harmony.lightened(0.5), fade * 0.4, pixel)

	# Subtle flow hint (single soft arrow).
	var hint_t: float = fmod(age / travel * 0.5 + 0.2, 0.85) + 0.05
	var hint_pt: Vector2 = DataViewLayout.shore_wave_point(
		map_ref, from_cell, to_cell, hint_t, age, phase_seed, 3.0
	)
	_draw_flow_hint(hint_pt, dir, harmony, fade * 0.55, pixel)

	_draw_source_pulse(rim_out, -dir, norm, harmony, fade * 0.5, pixel, age)


func _draw_soft_crest(
	from_cell: Vector2i,
	to_cell: Vector2i,
	crest_t: float,
	norm: Vector2,
	band_px: Dictionary,
	harmony: Color,
	alpha: float,
	pixel: float,
	age: float,
	phase_seed: float
) -> void:
	for step in range(CREST_STEPS):
		var u: float = float(step) / float(CREST_STEPS - 1) - 0.5
		var along_t: float = clampf(crest_t + u * 0.07, 0.03, 0.97)
		var pt: Vector2 = DataViewLayout.shore_wave_point(
			map_ref, from_cell, to_cell, along_t, age, phase_seed, 0.0
		)
		var crest_a: float = alpha * (1.0 - absf(u) * 1.4)
		_draw_pixel_cross(pt, norm, band_px, crest_a, pixel, harmony, true)


func _draw_flow_hint(center: Vector2, dir: Vector2, col: Color, alpha: float, pixel: float) -> void:
	var tip: Vector2 = center + dir * pixel * 1.1
	var c := Color(col.r, col.g, col.b, alpha)
	draw_line(center - dir * pixel * 0.3, tip, c, pixel * 0.4, true)
	_draw_soft_dot(tip, Vector2(-dir.y, dir.x), c.lightened(0.4), alpha, pixel * 0.7)


func _draw_source_pulse(
	center: Vector2,
	out_dir: Vector2,
	norm: Vector2,
	col: Color,
	alpha: float,
	pixel: float,
	age: float
) -> void:
	var ring: float = pixel * (1.5 + fmod(age * 1.8, 1.0) * 2.0)
	var p: Vector2 = center + out_dir * ring * 0.25
	_draw_soft_dot(p, norm, col.lightened(0.25), alpha * 0.55, pixel * 0.85)


func _harmonic_blend(amounts: Dictionary, total: float) -> Color:
	var blend := Color(0.45, 0.5, 0.62)
	var weight_sum := 0.0
	for stat in _STAT_ORDER:
		var amt: float = float(amounts.get(stat, 0.0))
		if amt < FLOW_THRESHOLD:
			continue
		var c := NutrientPalette.color_for(stat).lerp(Color(0.92, 0.88, 1.0), 0.32)
		blend = blend.lerp(c, amt / total)
		weight_sum += amt
	if weight_sum <= 0.0:
		return Color(0.6, 0.85, 1.0)
	return blend.lightened(0.12)


func _allocate_band_pixels(amounts: Dictionary, total: float, cross_px: int) -> Dictionary:
	var present: Array[String] = []
	for stat in _STAT_ORDER:
		if float(amounts.get(stat, 0.0)) >= FLOW_THRESHOLD:
			present.append(stat)
	if present.is_empty():
		return {}

	var out: Dictionary = {}
	var remaining: int = cross_px
	for i in range(present.size()):
		var stat: String = present[i]
		var amt: float = float(amounts.get(stat, 0.0))
		var px: int
		if i == present.size() - 1:
			px = maxi(1, remaining)
		else:
			px = maxi(1, int(round(float(cross_px) * amt / total)))
			px = mini(px, remaining - 1)
		out[stat] = px
		remaining -= px
	return out


func _draw_pixel_cross(
	center: Vector2,
	norm: Vector2,
	band_px: Dictionary,
	alpha: float,
	pixel: float,
	harmony: Color,
	bright: bool
) -> void:
	var total_px: int = 0
	for stat in _STAT_ORDER:
		total_px += int(band_px.get(stat, 0))
	if total_px <= 0:
		return

	var start_off: float = -float(total_px) * pixel * 0.5
	var cursor: float = start_off

	for stat in _STAT_ORDER:
		var count: int = int(band_px.get(stat, 0))
		if count <= 0:
			continue
		var base: Color = NutrientPalette.color_for(stat).lerp(harmony, 0.45)
		if bright:
			base = base.lerp(Color(0.95, 0.92, 1.0), 0.42)
		for i in range(count):
			var along: float = cursor + (float(i) + 0.5) * pixel
			var p: Vector2 = center + norm * along
			var col := Color(base.r, base.g, base.b, clampf(alpha, 0.0, 1.0))
			_draw_soft_dot(p, norm, col, alpha, pixel)
		cursor += float(count) * pixel


func _draw_soft_dot(center: Vector2, _norm: Vector2, col: Color, alpha: float, pixel: float) -> void:
	if alpha < 0.03:
		return
	var c := Color(col.r, col.g, col.b, clampf(alpha, 0.0, 1.0))
	var px: float = floor(center.x / PIXEL_SZ) * PIXEL_SZ
	var py: float = floor(center.y / PIXEL_SZ) * PIXEL_SZ
	var sz: float = maxf(pixel - 0.5, 4.0)
	draw_rect(Rect2(px, py, sz, sz), c, true)
	if c.a > 0.15:
		var glow := Color(c.r, c.g, c.b, c.a * 0.42)
		draw_rect(Rect2(px - 1.5, py - 1.5, sz + 3.0, sz + 3.0), glow, true)
