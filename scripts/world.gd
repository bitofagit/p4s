extends Camera2D

## Attached to the World scene’s Camera2D (filename is legacy: this file is **camera pan/zoom + bounds**, not the farm simulation).
## The TileMapLayer sibling uses `starting_map.gd` for almost all gameplay.
## Broader orientation: docs/CODEBASE_GUIDE.md

signal events_finished

## Baseline zoom for cinematic reset (set in _ready).
var default_zoom: Vector2
var is_playing_events: bool = false

const TILE_SIZE: float = 200.0

## Map extent in world pixels (updated from FarmDataManager on boot).
var map_bounds_width: float = TILE_SIZE * 128.0
var map_bounds_height: float = TILE_SIZE * 128.0

## Inset from map edges (0 … map bounds) for the camera centre, as a fraction of viewport size in world units.
## 0.25 = centre stays at least 25% of viewport width/height inside the map — centre never sits in the void.
const CENTER_MARGIN_FRAC := 0.25

## Trackpad / touch two-finger pan sensitivity.
var pan_speed: float = 250.0

## Multiplier for all panning (mouse drag + trackpad). 0.5 ≈ half speed.
const PAN_SPEED_SCALE := 0.5

var keyboard_pan_speed: float = 500.0
var keyboard_zoom_speed: float = 1.5

const ZOOM_SMOOTH_SPEED := 7.0
const _DEFAULT_MIN_ZOOM := 0.02

var target_zoom: float = 0.1
var min_zoom: float = _DEFAULT_MIN_ZOOM
var max_zoom: float = 1.5

const _FloraLodLayersScript := preload("res://scripts/flora_lod_layers.gd")
const _FloraLodVectorScript := preload("res://scripts/flora_lod_vector.gd")

## Dynamic zoom culling: above full_zoom_min use the full atlas; below that swap
## to baked low-res flora_atlas_lod_mid / _far TileMapLayers (see flora_lod_map.json).
var _cull_ground_layer: TileMapLayer
var _cull_understory_layer: TileMapLayer
var _cull_canopy_layer: TileMapLayer
var _cull_lod_layers: _FloraLodLayersScript
var _cull_vector_lod: _FloraLodVectorScript
var _cull_layers_resolved: bool = false
var _stream_map_ref: Node
var _last_stream_cam_pos: Vector2 = Vector2(INF, INF)
var _last_stream_zoom: float = -1.0
var _stream_cooldown: float = 0.0

## Aim point from input (may be outside bounds; we only apply clamped position to the camera).
var desired_pos: Vector2

var is_dragging: bool = false
var drag_start_mouse: Vector2
var drag_start_cam: Vector2

## Screen shake state — see apply_screen_shake(); decays each frame in _process.
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_time_left: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_map_bounds_from_farm()
	# low_end may not be detected yet at Camera _ready — also re-check deferred.
	_apply_low_end_camera_limits()
	call_deferred("_apply_low_end_camera_limits")
	target_zoom = zoom.x
	default_zoom = zoom
	var centre := Vector2(map_bounds_width / 2.0, map_bounds_height / 2.0)
	global_position = centre
	desired_pos = centre
	make_current()


func _apply_low_end_camera_limits() -> void:
	MetaManager.ensure_low_end_detected()
	if MetaManager.low_end_gpu:
		# Don't let the player zoom out to the whole farm on weak / virtual GPUs.
		min_zoom = 0.4
		if target_zoom < min_zoom:
			target_zoom = min_zoom
			zoom = Vector2(min_zoom, min_zoom)
	else:
		min_zoom = _DEFAULT_MIN_ZOOM


## Live refresh when graphics preset / toggles change in the pause or main menu.
func apply_meta_graphics_settings() -> void:
	_apply_low_end_camera_limits()


func _apply_map_bounds_from_farm() -> void:
	map_bounds_width = float(FarmDataManager.map_width) * TILE_SIZE
	map_bounds_height = float(FarmDataManager.map_height) * TILE_SIZE
	limit_left = 0
	limit_top = 0
	limit_right = int(map_bounds_width)
	limit_bottom = int(map_bounds_height)


func _exp_blend(speed: float, delta: float) -> float:
	return 1.0 - exp(-speed * delta)


func _clamp_center_to_map(p: Vector2) -> Vector2:
	var z := maxf(target_zoom, 0.0001)
	var vp_size := get_viewport_rect().size / z
	var mx := CENTER_MARGIN_FRAC * vp_size.x
	var my := CENTER_MARGIN_FRAC * vp_size.y
	var min_x := mx
	var max_x := map_bounds_width - mx
	var min_y := my
	var max_y := map_bounds_height - my
	if max_x < min_x:
		min_x = map_bounds_width / 2.0
		max_x = min_x
	if max_y < min_y:
		min_y = map_bounds_height / 2.0
		max_y = min_y
	return Vector2(clampf(p.x, min_x, max_x), clampf(p.y, min_y, max_y))


func _pointer_over_map_scroll_blocker() -> bool:
	return MapScrollBlockerUtil.should_block_map_scroll(get_viewport())


func _unhandled_input(event: InputEvent) -> void:
	if is_playing_events:
		return
	var map_node := get_tree().get_first_node_in_group("map") as Node
	if map_node and map_node.get("almanac_open"):
		return
	if _pointer_over_map_scroll_blocker():
		if event is InputEventPanGesture or event is InputEventMagnifyGesture:
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index in [
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT,
			]:
				get_viewport().set_input_as_handled()
				return
	if event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		desired_pos -= (pan.delta * pan_speed * PAN_SPEED_SCALE) / zoom.x
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMagnifyGesture:
		var mag := event as InputEventMagnifyGesture
		if is_nan(mag.factor) or is_inf(mag.factor):
			get_viewport().set_input_as_handled()
			return
		var old_zoom := target_zoom
		target_zoom = clampf(target_zoom * mag.factor, min_zoom, max_zoom)
		_apply_zoom_reanchor(old_zoom)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var is_middle = event.button_index == MOUSE_BUTTON_MIDDLE
		var is_space_left = event.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SPACE)

		if is_middle or is_space_left:
			if event.pressed:
				is_dragging = true
				drag_start_mouse = event.position
				drag_start_cam = global_position
			else:
				is_dragging = false

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(0.85)

	elif event is InputEventMouseMotion and is_dragging:
		var drag_delta: Vector2 = (drag_start_mouse - event.position) / zoom.x
		desired_pos = drag_start_cam + drag_delta


func _zoom_camera(factor: float) -> void:
	var old_zoom := target_zoom
	target_zoom = clampf(target_zoom * factor, min_zoom, max_zoom)
	_apply_zoom_reanchor(old_zoom)


func _apply_zoom_reanchor(old_zoom: float) -> void:
	var mouse_pos := get_global_mouse_position()
	var zoom_ratio := target_zoom / old_zoom
	if is_equal_approx(zoom_ratio, 1.0):
		return
	desired_pos = desired_pos + (mouse_pos - desired_pos) * (1.0 - 1.0 / zoom_ratio)


func _resolve_cull_layers() -> void:
	if _cull_layers_resolved:
		return
	var map := get_tree().get_first_node_in_group("map") as Node
	if map == null:
		return
	_stream_map_ref = map
	_cull_ground_layer = map.get("ground_layer") as TileMapLayer
	_cull_understory_layer = map.get("understory_layer") as TileMapLayer
	_cull_canopy_layer = map.get("canopy_layer") as TileMapLayer
	_cull_lod_layers = map.get("flora_lod_layers") as _FloraLodLayersScript
	_cull_vector_lod = map.get("flora_lod_vector") as _FloraLodVectorScript
	if is_instance_valid(_cull_ground_layer) or is_instance_valid(_cull_understory_layer) \
		or is_instance_valid(_cull_canopy_layer):
		_cull_layers_resolved = true


func _update_zoom_culling() -> void:
	_resolve_cull_layers()
	if not _cull_layers_resolved:
		return
	var culling: bool = MetaManager.dynamic_zoom_culling
	var use_lod: bool = culling and is_instance_valid(_cull_lod_layers) and _cull_lod_layers.has_tiers()
	var lod_tier := ""
	if use_lod:
		lod_tier = PlantGrowth.flora_lod_tier_for_zoom(zoom.x)
		use_lod = lod_tier != ""
	var show_full: bool = not use_lod
	if is_instance_valid(_cull_ground_layer):
		var want_ground: bool = MetaManager.render_groundcover and show_full
		if _cull_ground_layer.visible != want_ground:
			_cull_ground_layer.visible = want_ground
	if is_instance_valid(_cull_understory_layer):
		var want_understory: bool = MetaManager.render_understory and show_full
		if _cull_understory_layer.visible != want_understory:
			_cull_understory_layer.visible = want_understory
	if is_instance_valid(_cull_canopy_layer):
		var want_canopy: bool = show_full
		if _cull_canopy_layer.visible != want_canopy:
			_cull_canopy_layer.visible = want_canopy
	if is_instance_valid(_cull_lod_layers):
		_cull_lod_layers.apply_layer_settings(
			MetaManager.render_groundcover,
			MetaManager.render_understory,
		)
		var atlas_tier := lod_tier
		if atlas_tier == "far" and MetaManager.flora_vector_far_zoom:
			atlas_tier = ""
		_cull_lod_layers.set_lod_tier(atlas_tier if use_lod else "")
	if is_instance_valid(_cull_vector_lod):
		var want_vector := use_lod and lod_tier == "far" and MetaManager.flora_vector_far_zoom
		_cull_vector_lod.apply_layer_settings(
			MetaManager.render_groundcover,
			MetaManager.render_understory,
		)
		_cull_vector_lod.set_active(want_vector)


func _maybe_stream_map_visuals() -> void:
	if _stream_map_ref == null or not is_instance_valid(_stream_map_ref):
		_resolve_cull_layers()
	if _stream_map_ref == null or not _stream_map_ref.has_method("stream_map_visuals_if_needed"):
		return
	if not MetaManager.low_end_gpu:
		return
	if _stream_cooldown > 0.0:
		return
	if (
		global_position.distance_squared_to(_last_stream_cam_pos) > 400000.0
		or not is_equal_approx(zoom.x, _last_stream_zoom)
	):
		_last_stream_cam_pos = global_position
		_last_stream_zoom = zoom.x
		_stream_cooldown = 0.45
		_stream_map_ref.call("stream_map_visuals_if_needed")


func _process(delta: float) -> void:
	_process_screen_shake(delta)
	_stream_cooldown = maxf(_stream_cooldown - delta, 0.0)
	_maybe_stream_map_visuals()
	_update_zoom_culling()
	if is_playing_events:
		return

	# --- KEYBOARD PANNING & ZOOMING ---
	var pan_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		pan_dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		pan_dir.x += 1

	if Input.is_key_pressed(KEY_SHIFT):
		# SHIFT + UP/DOWN = Zoom
		if Input.is_key_pressed(KEY_UP):
			var old_tz := target_zoom
			target_zoom = clampf(target_zoom + (keyboard_zoom_speed * target_zoom * delta), min_zoom, max_zoom)
			_apply_zoom_reanchor(old_tz)
		if Input.is_key_pressed(KEY_DOWN):
			var old_tz2 := target_zoom
			target_zoom = clampf(target_zoom - (keyboard_zoom_speed * target_zoom * delta), min_zoom, max_zoom)
			_apply_zoom_reanchor(old_tz2)
	else:
		# UP/DOWN = Pan
		if Input.is_key_pressed(KEY_UP):
			pan_dir.y -= 1
		if Input.is_key_pressed(KEY_DOWN):
			pan_dir.y += 1

	if pan_dir != Vector2.ZERO:
		pan_dir = pan_dir.normalized()
		# Move slower when zoomed in, faster when zoomed out
		desired_pos += (pan_dir * keyboard_pan_speed * delta) / zoom.x
	# ----------------------------------

	var zb := _exp_blend(ZOOM_SMOOTH_SPEED, delta)
	zoom = zoom.lerp(Vector2(target_zoom, target_zoom), zb)

	# Clamp the invisible target to the map boundaries so we don't plan a trip into the void
	desired_pos = _clamp_center_to_map(desired_pos)

	if is_dragging:
		# When dragging, strictly lock the camera to the mouse for perfectly tight 1:1 control
		global_position = desired_pos
	else:
		# When using keyboard or trackpad, let the camera smoothly catch up to the target (momentum)
		var pb := _exp_blend(8.0, delta)
		global_position = global_position.lerp(desired_pos, pb)


func play_event_queue(events: Array) -> void:
	is_playing_events = true
	_play_next_event(events.duplicate())


func _play_next_event(events: Array) -> void:
	if events.is_empty():
		var reset_tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		reset_tween.set_parallel(true)
		reset_tween.tween_property(self, "zoom", default_zoom, 0.5).set_trans(Tween.TRANS_SINE)

		# Fetch the exact farmhouse position from the map node
		var map_node = get_tree().get_first_node_in_group("map")
		var target_pos = Vector2(map_bounds_width / 2.0, map_bounds_height / 2.0)
		if map_node and map_node.get("home_pos"):
			target_pos = map_node.map_to_local(map_node.home_pos)

		reset_tween.tween_property(self, "global_position", target_pos, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		reset_tween.chain().tween_callback(func():
			target_zoom = default_zoom.x
			desired_pos = global_position
			is_playing_events = false
			events_finished.emit()
		)
		return

	var current_event = events.pop_front()
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	tween.tween_property(self, "global_position", current_event.pos, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	match current_event.type:
		"weed_spread":
			tween.tween_callback(func():
				if RadioManager.has_method("play_action_note"):
					RadioManager.play_action_note("ui")
			)
			tween.tween_interval(0.3)

		"fox_attack":
			tween.tween_property(self, "zoom", default_zoom * 1.5, 0.2).set_trans(Tween.TRANS_EXPO)
			tween.tween_callback(func():
				if RadioManager.has_method("play_action_note"):
					RadioManager.play_action_note("build")
				_screen_shake(15.0, 0.4)
			)
			tween.tween_interval(0.8)

		"plant_died":
			tween.tween_property(self, "zoom", default_zoom * 1.2, 0.3)
			tween.tween_interval(0.5)

	tween.tween_callback(func(): _play_next_event(events))


## Public API: randomised, decaying camera shake. Stronger requests override weaker in-flight ones.
func apply_screen_shake(intensity: float, duration: float = 0.3) -> void:
	var current_strength := 0.0
	if _shake_duration > 0.0:
		current_strength = _shake_intensity * (_shake_time_left / _shake_duration)
	if intensity < current_strength:
		return
	_shake_intensity = intensity
	_shake_duration = maxf(duration, 0.01)
	_shake_time_left = _shake_duration


func _process_screen_shake(delta: float) -> void:
	if _shake_time_left <= 0.0:
		return
	_shake_time_left = maxf(_shake_time_left - delta, 0.0)
	var decay := _shake_time_left / _shake_duration
	var strength := _shake_intensity * decay * decay
	if _shake_time_left <= 0.0 or strength < 0.1:
		offset = Vector2.ZERO
		_shake_intensity = 0.0
		_shake_duration = 0.0
		_shake_time_left = 0.0
		return
	offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))


func _screen_shake(intensity: float, duration: float) -> void:
	apply_screen_shake(intensity, duration)
