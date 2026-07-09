extends RefCounted
class_name DataViewLayout
## Shared geometry for data lenses: central bar panel + peripheral rim corridor.

const CELL_PX := 200.0
const TILE_HALF := Vector2(100.0, 100.0)
const RIM_FRAC := 0.15
const RIM_PX := CELL_PX * RIM_FRAC
const INNER_PX := CELL_PX - RIM_PX * 2.0

const BAR_H := 11.0
const BAR_GAP := 4.0
const BAR_PAD_X := 8.0
const FONT_SZ := 9

const WAVE_TRAVEL_SEC := 2.2
const FLOW_LIFETIME := 10.0
## Camera zoom.x must reach this before rim waves + bar transfer animation run (0.02–1.5 range).
const MIN_WAVE_ZOOM := 0.5
const MAX_VISIBLE_WAVES := 96


static func tile_top_left(map_ref: Node2D, map_pos: Vector2i) -> Vector2:
	return map_ref.map_to_local(map_pos) - TILE_HALF


static func tile_center(map_ref: Node2D, map_pos: Vector2i) -> Vector2:
	return map_ref.map_to_local(map_pos)


static func inner_rect(cell_tl: Vector2) -> Rect2:
	return Rect2(cell_tl + Vector2(RIM_PX, RIM_PX), Vector2(INNER_PX, INNER_PX))


static func bar_panel_origin(cell_tl: Vector2, bar_count: int) -> Vector2:
	var inner := inner_rect(cell_tl)
	var bar_w := inner.size.x - BAR_PAD_X * 2.0
	var stack_h := float(bar_count) * BAR_H + float(bar_count - 1) * BAR_GAP
	var y0 := inner.position.y + (inner.size.y - stack_h) * 0.5
	return Vector2(inner.position.x + BAR_PAD_X, y0)


static func bar_width(cell_tl: Vector2) -> float:
	return inner_rect(cell_tl).size.x - BAR_PAD_X * 2.0


static func rim_exit_px(map_ref: Node2D, from_pos: Vector2i, to_pos: Vector2i) -> Vector2:
	var fc := tile_center(map_ref, from_pos)
	var tc := tile_center(map_ref, to_pos)
	var dir := (tc - fc).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	return fc + dir * (INNER_PX * 0.5)


static func rim_entry_px(map_ref: Node2D, from_pos: Vector2i, to_pos: Vector2i) -> Vector2:
	var fc := tile_center(map_ref, from_pos)
	var tc := tile_center(map_ref, to_pos)
	var dir := (tc - fc).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	return tc - dir * (INNER_PX * 0.5)


static func corridor_mid_px(map_ref: Node2D, from_pos: Vector2i, to_pos: Vector2i) -> Vector2:
	var fc := tile_center(map_ref, from_pos)
	var tc := tile_center(map_ref, to_pos)
	return (fc + tc) * 0.5


static func wave_path_point(map_ref: Node2D, from_pos: Vector2i, to_pos: Vector2i, t: float) -> Vector2:
	var p0 := rim_exit_px(map_ref, from_pos, to_pos)
	var p1 := corridor_mid_px(map_ref, from_pos, to_pos)
	var p2 := rim_entry_px(map_ref, from_pos, to_pos)
	var u := 1.0 - t
	return u * u * p0 + 2.0 * u * t * p1 + t * t * p2


static func liquid_path_point(
	map_ref: Node2D,
	from_pos: Vector2i,
	to_pos: Vector2i,
	t: float,
	age: float,
	phase_seed: float
) -> Vector2:
	return shore_wave_point(map_ref, from_pos, to_pos, t, age, phase_seed, 0.0)


## Rim-corridor surf: base path stays in the 30px cell border (visible under bar charts).
static func shore_wave_point(
	map_ref: Node2D,
	from_pos: Vector2i,
	to_pos: Vector2i,
	t: float,
	age: float,
	phase_seed: float,
	lap_index: float
) -> Vector2:
	var base := wave_path_point(map_ref, from_pos, to_pos, t)
	var fc := tile_center(map_ref, from_pos)
	var tc := tile_center(map_ref, to_pos)
	var dir := (tc - fc).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	var norm := Vector2(-dir.y, dir.x)

	var lateral := sin(t * TAU * 3.2 - age * 3.8 + phase_seed + lap_index * 0.65) * 14.0
	lateral += sin(t * TAU * 5.5 - age * 5.2 + phase_seed * 1.3) * 5.0
	var surge := sin(t * PI - age * 2.6 + lap_index * 0.4) * 10.0
	var runup := sin(age * 2.1 + lap_index) * 5.0 * (1.0 - t)

	return base + norm * lateral + dir * (surge + runup)


static func wave_draw_scale(map_ref: Node2D) -> float:
	return clampf(0.62 / camera_zoom(map_ref), 1.0, 2.4)


static func camera_zoom(map_ref: Node2D) -> float:
	var cam := map_ref.get_viewport().get_camera_2d()
	if cam == null:
		return 1.0
	return cam.zoom.x


static func waves_enabled(map_ref: Node2D) -> bool:
	return camera_zoom(map_ref) >= MIN_WAVE_ZOOM


static func visible_tile_bounds(map_ref: Node2D) -> Rect2i:
	var w: int = int(map_ref.call("_map_w"))
	var h: int = int(map_ref.call("_map_h"))
	var cam := map_ref.get_viewport().get_camera_2d()
	if cam == null:
		return Rect2i(0, 0, w, h)
	var vp := map_ref.get_viewport_rect().size
	var half := vp / (2.0 * cam.zoom)
	var center := map_ref.to_local(cam.global_position)
	var tl := center - half
	var br := center + half
	var min_x := clampi(int(floor(tl.x / CELL_PX)) - 2, 0, w - 1)
	var max_x := clampi(int(ceil(br.x / CELL_PX)) + 2, 0, w - 1)
	var min_y := clampi(int(floor(tl.y / CELL_PX)) - 2, 0, h - 1)
	var max_y := clampi(int(ceil(br.y / CELL_PX)) + 2, 0, h - 1)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


static func cell_in_bounds(cell: Vector2i, bounds: Rect2i) -> bool:
	return (
		cell.x >= bounds.position.x
		and cell.y >= bounds.position.y
		and cell.x < bounds.position.x + bounds.size.x
		and cell.y < bounds.position.y + bounds.size.y
	)


static func shrink_curve(t: float) -> float:
	if t < 0.12:
		return 0.0
	return clampf((t - 0.12) / 0.5, 0.0, 1.0)


static func grow_curve(t: float) -> float:
	if t < 0.42:
		return 0.0
	return clampf((t - 0.42) / 0.5, 0.0, 1.0)
