extends Camera2D
## Standalone director (reference; not on a scene by default). The main game Camera2D uses
## `world.gd` — that script owns player pan/zoom (mouse, trackpad, **arrow keys**), map bounds,
## and this event queue API (`play_event_queue`, `events_finished`).

signal events_finished

var default_zoom: Vector2
var is_playing_events: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Run while paused
	default_zoom = zoom
	make_current()

func play_event_queue(events: Array) -> void:
	is_playing_events = true
	_play_next_event(events.duplicate())

func _play_next_event(events: Array) -> void:
	if events.is_empty():
		# Reset camera and return control
		var reset_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		reset_tween.tween_property(self, "zoom", default_zoom, 0.5).set_trans(Tween.TRANS_SINE)
		reset_tween.tween_callback(func():
			is_playing_events = false
			events_finished.emit()
		)
		return

	var current_event = events.pop_front()
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	# 1. Pan to the location
	tween.tween_property(self, "global_position", current_event.pos, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	match current_event.type:
		"weed_spread":
			tween.tween_callback(func():
				# Ominous pinging
				if RadioManager.has_method("play_action_note"):
					RadioManager.play_action_note("ui") # High pitch ping
			)
			tween.tween_interval(0.3)

		"fox_attack":
			# Zoom in fast and wobble
			tween.tween_property(self, "zoom", default_zoom * 1.5, 0.2).set_trans(Tween.TRANS_EXPO)
			tween.tween_callback(func():
				# Low pitch razz
				if RadioManager.has_method("play_action_note"):
					RadioManager.play_action_note("build")
				_screen_shake(15.0, 0.4)
			)
			tween.tween_interval(0.8)

		"plant_died":
			tween.tween_property(self, "zoom", default_zoom * 1.2, 0.3)
			tween.tween_interval(0.5)

	# Chain the next event
	tween.tween_callback(func(): _play_next_event(events))

func _screen_shake(intensity: float, duration: float) -> void:
	var shake_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var steps = int(duration / 0.05)
	for i in range(steps):
		var shake_offset := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		shake_tween.tween_property(self, "offset", shake_offset, 0.05)
	shake_tween.tween_property(self, "offset", Vector2.ZERO, 0.05)
