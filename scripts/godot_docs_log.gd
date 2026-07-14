extends Node

## Autoload: mirrors Godot console output to session log files.
## Editor  → res://docs/godot_error_log_*.txt (+ docs/godot_error_log.txt index)
## Export  → {exe folder}/P4S_logs/ (fallback: user://logs/ if exe dir is not writable)


## Perf heartbeat: a summary line every PERF_REPORT_INTERVAL_SEC, plus an
## immediate report whenever a single frame exceeds FRAME_SPIKE_MS.
const PERF_REPORT_INTERVAL_SEC := 5.0
const FRAME_SPIKE_MS := 120.0
const SPIKE_REPORT_COOLDOWN_SEC := 1.0

var _logger: DocsFileLogger
var _session_start_ms: int = 0

var _perf_accum := 0.0
var _perf_frames := 0
var _perf_worst_frame_ms := 0.0
var _perf_spike_count := 0
var _spike_cooldown := 0.0
var _startup_details_printed := false
var _map_census_scene := ""


func _init() -> void:
	_session_start_ms = Time.get_ticks_msec()
	_logger = DocsFileLogger.new()
	OS.add_logger(_logger)


func _ready() -> void:
	# Keep the perf heartbeat alive while the tree is paused (intro dialogue,
	# pause menu) — stalls during pause are exactly what we want to see.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_logger.write_session_open_block()
	log_milestone("autoloads_ready")


func _process(delta: float) -> void:
	if not _startup_details_printed:
		_startup_details_printed = true
		_print_startup_details()

	var frame_ms := delta * 1000.0
	_perf_accum += delta
	_perf_frames += 1
	_perf_worst_frame_ms = maxf(_perf_worst_frame_ms, frame_ms)
	_spike_cooldown = maxf(_spike_cooldown - delta, 0.0)

	if frame_ms > FRAME_SPIKE_MS:
		_perf_spike_count += 1
		if _spike_cooldown <= 0.0:
			_spike_cooldown = SPIKE_REPORT_COOLDOWN_SEC
			print(
				"[P4S spike +%.1fs] frame=%.0fms (process=%.0fms physics=%.0fms) scene=%s"
				% [
					_session_sec(),
					frame_ms,
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
					_current_scene_name(),
				]
			)

	if _perf_accum >= PERF_REPORT_INTERVAL_SEC:
		_print_perf_report()
		_maybe_print_map_census()
		_perf_accum = 0.0
		_perf_frames = 0
		_perf_worst_frame_ms = 0.0
		_perf_spike_count = 0


func _session_sec() -> float:
	return (Time.get_ticks_msec() - _session_start_ms) / 1000.0


func _current_scene_name() -> String:
	var scene := get_tree().current_scene
	return scene.name if scene != null else "?"


## One-time hardware / renderer / audio block, printed on the first drawn frame
## (so the GPU context and audio device are fully initialised).
func _print_startup_details() -> void:
	MetaManager.ensure_low_end_detected()
	var adapter_type_names := ["other", "integrated", "discrete", "virtual", "cpu"]
	var adapter_type := RenderingServer.get_video_adapter_type()
	var type_label: String = (
		adapter_type_names[adapter_type]
		if adapter_type < adapter_type_names.size()
		else str(adapter_type)
	)
	var vsync := DisplayServer.window_get_vsync_mode()
	var screen := DisplayServer.window_get_current_screen()
	var scale_factor := 1.0
	var win := get_window()
	if win:
		scale_factor = win.content_scale_factor
	var lines := PackedStringArray([
		"[P4S sysinfo] os=%s %s | cpu=%s x%d" % [
			OS.get_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count(),
		],
		"[P4S sysinfo] gpu=%s (%s, type=%s) api=%s" % [
			RenderingServer.get_video_adapter_name(),
			RenderingServer.get_video_adapter_vendor(),
			type_label,
			RenderingServer.get_video_adapter_api_version(),
		],
		"[P4S sysinfo] window=%s screen=%s @ %.0fHz vsync=%d max_fps=%d scale=%.2f low_end=%s" % [
			str(DisplayServer.window_get_size()),
			str(DisplayServer.screen_get_size(screen)),
			DisplayServer.screen_get_refresh_rate(screen),
			vsync,
			Engine.max_fps,
			scale_factor,
			str(MetaManager.low_end_gpu),
		],
		"[P4S sysinfo] audio mix_rate=%.0fHz latency=%.1fms driver_setting=%s" % [
			AudioServer.get_mix_rate(),
			AudioServer.get_output_latency() * 1000.0,
			str(ProjectSettings.get_setting("audio/driver/output_latency", "?")),
		],
	])
	var mem_info: Dictionary = OS.get_memory_info()
	if not mem_info.is_empty():
		lines.append(
			"[P4S sysinfo] ram physical=%.0fMB available=%.0fMB" % [
				float(mem_info.get("physical", 0)) / 1048576.0,
				float(mem_info.get("available", 0)) / 1048576.0,
			]
		)
	for line in lines:
		print(line)


## One-shot per scene: what is actually generating canvas items?
## Reports every TileMapLayer (cell count, y-sort, quadrant size) and the
## visible CanvasItem population grouped by class.
func _maybe_print_map_census() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var key := "%s#%d" % [scene.name, scene.get_instance_id()]
	if key == _map_census_scene:
		return
	_map_census_scene = key

	var class_counts: Dictionary = {}
	var tilemap_lines: PackedStringArray = PackedStringArray()
	var stack: Array[Node] = [scene as Node]
	var visible_items := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		var ci := node as CanvasItem
		if ci == null or not ci.is_visible_in_tree():
			continue
		visible_items += 1
		var cls := node.get_class()
		class_counts[cls] = int(class_counts.get(cls, 0)) + 1
		var tml := node as TileMapLayer
		if tml != null:
			tilemap_lines.append(
				"[P4S census]   tilemap %s: cells=%d y_sort=%s quadrant=%d z=%d"
				% [
					node.name,
					tml.get_used_cells().size(),
					str(tml.y_sort_enabled),
					tml.rendering_quadrant_size,
					tml.z_index,
				]
			)
	var pairs: Array = []
	for cls in class_counts:
		pairs.append([cls, class_counts[cls]])
	pairs.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	var top: PackedStringArray = PackedStringArray()
	for i in mini(pairs.size(), 10):
		top.append("%s=%d" % [pairs[i][0], pairs[i][1]])
	print(
		"[P4S census] scene=%s visible_canvas_items=%d | %s"
		% [scene.name, visible_items, " ".join(top)]
	)
	for line in tilemap_lines:
		print(line)


func _print_perf_report() -> void:
	var avg_frame_ms := (_perf_accum / maxi(_perf_frames, 1)) * 1000.0
	print(
		"[P4S perf +%.1fs] fps=%.0f avg=%.1fms worst=%.0fms spikes=%d | proc=%.0fms | draws=%d objs=%d prims=%d | vram=%.0fMB tex=%.0fMB mem=%.0fMB | nodes=%d orphans=%d | audio_lat=%.1fms | scene=%s"
		% [
			_session_sec(),
			Performance.get_monitor(Performance.TIME_FPS),
			avg_frame_ms,
			_perf_worst_frame_ms,
			_perf_spike_count,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			Performance.get_monitor(Performance.AUDIO_OUTPUT_LATENCY) * 1000.0,
			_current_scene_name(),
		]
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_logger.finalize_session(_session_start_ms)


func _exit_tree() -> void:
	_logger.finalize_session(_session_start_ms)


## Startup timing hook — also mirrored into the session log via print().
func log_milestone(label: String) -> void:
	var ms := Time.get_ticks_msec() - _session_start_ms
	print("[P4S milestone +%dms] %s" % [ms, label])


class DocsFileLogger extends Logger:
	const EDITOR_LOG_DIR := "res://docs/"
	const EXPORT_LOG_FOLDER := "P4S_logs"
	const LOG_PREFIX := "godot_error_log_"
	const LOG_SUFFIX := ".txt"
	const INDEX_PATH := "res://docs/godot_error_log.txt"
	const MAX_RETAINED_LOGS := 10

	var _mutex := Mutex.new()
	var _file: FileAccess
	var _abs_log_dir := ""
	var _session_log_filename := ""
	var _session_log_abs_path := ""
	var _log_dir_is_exe := false
	var _finalized := false


	func _init() -> void:
		_open_file()


	func _running_in_editor() -> bool:
		return OS.has_feature("editor")


	func _dir_is_writable(abs_dir: String) -> bool:
		DirAccess.make_dir_recursive_absolute(abs_dir)
		var probe := abs_dir.path_join(".write_probe")
		var f := FileAccess.open(probe, FileAccess.WRITE)
		if f == null:
			return false
		f.store_string("ok")
		f.close()
		DirAccess.remove_absolute(probe)
		return true


	func _resolve_log_dir() -> String:
		if _running_in_editor():
			var editor_dir := ProjectSettings.globalize_path(EDITOR_LOG_DIR)
			DirAccess.make_dir_recursive_absolute(editor_dir)
			_log_dir_is_exe = false
			return editor_dir

		var exe_dir := OS.get_executable_path().get_base_dir()
		var exe_logs := exe_dir.path_join(EXPORT_LOG_FOLDER)
		if _dir_is_writable(exe_logs):
			_log_dir_is_exe = true
			return exe_logs

		var user_logs := OS.get_user_data_dir().path_join("logs")
		DirAccess.make_dir_recursive_absolute(user_logs)
		_log_dir_is_exe = false
		_write_exe_pointer_file(exe_dir, user_logs)
		return user_logs


	func _write_exe_pointer_file(exe_dir: String, actual_log_dir: String) -> void:
		var pointer := exe_dir.path_join("P4S_WHERE_ARE_MY_LOGS.txt")
		var body := PackedStringArray([
			"P4S opencore — session logs",
			"===========================",
			"",
			"The game could not write logs next to the .exe (folder may be read-only).",
			"Session logs are stored here instead:",
			"",
			"  %s" % actual_log_dir,
			"",
			"Look for files named godot_error_log_YYYY-MM-DD_HH-mm-ss.txt",
			"and latest_session.txt inside that folder.",
			"",
			"Send the newest log when reporting bugs or Windows slowness.",
		])
		var f := FileAccess.open(pointer, FileAccess.WRITE)
		if f:
			f.store_string("\n".join(body) + "\n")
			f.close()


	func _session_basename() -> String:
		var dt := Time.get_datetime_dict_from_system()
		return "%s%04d-%02d-%02d_%02d-%02d-%02d%s" % [
			LOG_PREFIX,
			int(dt.get("year", 1970)),
			int(dt.get("month", 1)),
			int(dt.get("day", 1)),
			int(dt.get("hour", 0)),
			int(dt.get("minute", 0)),
			int(dt.get("second", 0)),
			LOG_SUFFIX,
		]


	func _open_file() -> void:
		_abs_log_dir = _resolve_log_dir()
		_session_log_filename = _session_basename()
		_session_log_abs_path = _abs_log_dir.path_join(_session_log_filename)

		_file = FileAccess.open(_session_log_abs_path, FileAccess.WRITE)
		if _file:
			_write_line("--- session %s ---" % Time.get_datetime_string_from_system())
			_write_line(
				"Godot %s | log: %s"
				% [Engine.get_version_info().get("string", "?"), _session_log_abs_path]
			)
			_prune_old_logs()
			if _running_in_editor():
				_write_editor_index()
			else:
				_write_export_sidecars([])


	func _list_session_logs() -> Array[String]:
		var names: Array[String] = []
		var dir := DirAccess.open(_abs_log_dir)
		if dir == null:
			return names
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and entry.begins_with(LOG_PREFIX) and entry.ends_with(LOG_SUFFIX):
				names.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
		names.sort()
		return names


	func _prune_old_logs() -> void:
		var names := _list_session_logs()
		while names.size() > MAX_RETAINED_LOGS:
			var oldest := names[0]
			names.remove_at(0)
			DirAccess.remove_absolute(_abs_log_dir.path_join(oldest))


	func _write_editor_index() -> void:
		var names := _list_session_logs()
		names.reverse()
		var lines: PackedStringArray = PackedStringArray([
			"# P4S Godot error log index (auto-generated — do not edit)",
			"#",
			"# Convention: docs/godot_error_log_YYYY-MM-DD_HH-mm-ss.txt (project folder, not user://)",
			"# Retention: newest %d session files; oldest deleted on each new run." % MAX_RETAINED_LOGS,
			"#",
			"# Current session:",
			"docs/%s" % _session_log_filename,
			"#",
			"# Recent sessions (newest first):",
		])
		if names.is_empty():
			lines.append("# (none yet)")
		else:
			for n in names:
				lines.append("- docs/%s" % n)
		var index_abs := ProjectSettings.globalize_path(INDEX_PATH)
		var index_file := FileAccess.open(index_abs, FileAccess.WRITE)
		if index_file:
			index_file.store_string("\n".join(lines) + "\n")
			index_file.close()


	func _write_export_sidecars(extra_lines: PackedStringArray) -> void:
		var readme_path := _abs_log_dir.path_join("README.txt")
		if not FileAccess.file_exists(readme_path):
			var readme := PackedStringArray([
				"P4S opencore — session logs",
				"===========================",
				"",
				"Each run creates godot_error_log_YYYY-MM-DD_HH-mm-ss.txt in this folder.",
				"latest_session.txt always points at the most recent run.",
				"",
				"If this folder is missing, check P4S_WHERE_ARE_MY_LOGS.txt beside the .exe",
				"or look under your Godot app user data folder.",
				"",
				"Send the newest log when reporting bugs or Windows slowness.",
			])
			var rf := FileAccess.open(readme_path, FileAccess.WRITE)
			if rf:
				rf.store_string("\n".join(readme) + "\n")
				rf.close()

		var latest_lines: PackedStringArray = PackedStringArray([
			"P4S opencore — latest session",
			"==============================",
			"",
			"log_file: %s" % _session_log_abs_path,
			"log_dir: %s" % _abs_log_dir,
			"beside_exe: %s" % str(_log_dir_is_exe),
			"",
		])
		latest_lines.append_array(extra_lines)
		var latest_path := _abs_log_dir.path_join("latest_session.txt")
		var lf := FileAccess.open(latest_path, FileAccess.WRITE)
		if lf:
			lf.store_string("\n".join(latest_lines) + "\n")
			lf.close()


	func _build_session_info_lines() -> PackedStringArray:
		var lines: PackedStringArray = PackedStringArray([
			"=== session open ===",
			"started: %s" % Time.get_datetime_string_from_system(),
			"project: %s v%s"
			% [
				ProjectSettings.get_setting("application/config/name", "P4S"),
				ProjectSettings.get_setting("application/config/version", "?"),
			],
			"godot: %s" % Engine.get_version_info().get("string", "?"),
			"executable: %s" % OS.get_executable_path(),
			"log_dir: %s" % _abs_log_dir,
			"user_data: %s" % OS.get_user_data_dir(),
			"os: %s" % OS.get_name(),
			"os_version: %s" % OS.get_version(),
			"locale: %s" % OS.get_locale(),
			"processor_count: %d" % OS.get_processor_count(),
			"unique_id: %s" % OS.get_unique_id(),
		])

		var mem_static := OS.get_static_memory_usage()
		lines.append("memory_static_mb: %.1f" % (mem_static / 1048576.0))

		var mem_info: Dictionary = OS.get_memory_info()
		if not mem_info.is_empty():
			lines.append(
				"memory_physical_mb: %.1f"
				% (float(mem_info.get("physical", 0)) / 1048576.0)
			)
			lines.append(
				"memory_available_mb: %.1f"
				% (float(mem_info.get("available", 0)) / 1048576.0)
			)

		lines.append("gpu: %s" % RenderingServer.get_video_adapter_name())
		lines.append("gpu_vendor: %s" % RenderingServer.get_video_adapter_vendor())
		lines.append("gpu_api_version: %s" % RenderingServer.get_video_adapter_api_version())

		var win := DisplayServer.window_get_size()
		lines.append(
			"window: %dx%d mode=%d"
			% [win.x, win.y, DisplayServer.window_get_mode()]
		)
		lines.append("screen_count: %d" % DisplayServer.get_screen_count())
		lines.append(
			"render_features: %s"
			% str(ProjectSettings.get_setting("application/config/features", []))
		)
		lines.append(
			"rendering_driver_windows: %s"
			% ProjectSettings.get_setting("rendering/rendering_device/driver.windows", "?")
		)
		return lines


	func _build_session_close_lines(session_start_ms: int) -> PackedStringArray:
		var elapsed_ms := maxi(Time.get_ticks_msec() - session_start_ms, 1)
		var lines: PackedStringArray = PackedStringArray([
			"=== session closed ===",
			"ended: %s" % Time.get_datetime_string_from_system(),
			"duration_sec: %.2f" % (elapsed_ms / 1000.0),
			"frames_drawn: %d" % Engine.get_frames_drawn(),
			"process_frames: %d" % Engine.get_process_frames(),
			"avg_fps_drawn: %.1f" % (Engine.get_frames_drawn() * 1000.0 / float(elapsed_ms)),
			"memory_static_mb_end: %.1f" % (OS.get_static_memory_usage() / 1048576.0),
		])
		var mem_info: Dictionary = OS.get_memory_info()
		if not mem_info.is_empty():
			lines.append(
				"memory_available_mb_end: %.1f"
				% (float(mem_info.get("available", 0)) / 1048576.0)
			)
		return lines


	func write_session_open_block() -> void:
		_write_line("────────────────────────────────────────")
		for line in _build_session_info_lines():
			_write_line(line)
		_write_line("────────────────────────────────────────")
		if not _running_in_editor():
			_write_export_sidecars(_build_session_info_lines())


	func finalize_session(session_start_ms: int) -> void:
		if _finalized:
			return
		_finalized = true
		var close_lines := _build_session_close_lines(session_start_ms)
		_write_line("────────────────────────────────────────")
		for line in close_lines:
			_write_line(line)
		_write_line("────────────────────────────────────────")
		_mutex.lock()
		if _file and _file.is_open():
			_file.close()
		_mutex.unlock()
		if not _running_in_editor():
			_write_export_sidecars(close_lines)


	func _write_line(text: String) -> void:
		_mutex.lock()
		_raw_write_line(text)
		_mutex.unlock()


	## Caller must hold _mutex.
	func _raw_write_line(text: String) -> void:
		if _file and _file.is_open():
			_file.store_string(text.rstrip(" \t\r\n") + "\n")
			_file.flush()


	func _write_multiline(prefix: String, body: String) -> void:
		for line in body.split("\n", false):
			if line.strip_edges().is_empty():
				continue
			_write_line("%s%s" % [prefix, line])


	func _timestamp() -> String:
		return Time.get_time_string_from_system()


	func _error_kind_label(error_type: int) -> String:
		match error_type:
			0:
				return "ERROR"
			1:
				return "WARNING"
			2:
				return "SCRIPT"
			3:
				return "SHADER"
			_:
				return "ERR_%d" % error_type


	func _format_backtraces(backtraces: Array[ScriptBacktrace]) -> String:
		if backtraces.is_empty():
			return ""
		var parts: PackedStringArray = PackedStringArray()
		for bt in backtraces:
			if bt == null or bt.is_empty():
				continue
			var lang := bt.get_language_name()
			if lang.is_empty():
				lang = "Script"
			parts.append("[%s stack]" % lang)
			parts.append(bt.format(0, 2))
		return "\n".join(parts)


	## Rate-limiter: identical strings are only written once per rendered frame.
	## Prevents error storms (e.g. a per-cell loop) from writing thousands of
	## duplicate lines and stalling the game on disk I/O.
	var _frame_seen: Dictionary = {}
	var _frame_stamp: int = -1
	var _frame_suppressed: int = 0

	func _should_write_once_per_frame(key: String) -> bool:
		var now := Engine.get_process_frames()
		_mutex.lock()
		if now != _frame_stamp:
			if _frame_suppressed > 0:
				_raw_write_line(
					"[%s] [LOG] (throttled: %d duplicate log lines suppressed last frame)"
					% [_timestamp(), _frame_suppressed]
				)
			_frame_stamp = now
			_frame_seen.clear()
			_frame_suppressed = 0
		if _frame_seen.has(key):
			_frame_suppressed += 1
			_mutex.unlock()
			return false
		_frame_seen[key] = true
		_mutex.unlock()
		return true


	func _log_message(message: String, error: bool) -> void:
		var tag := "WARN" if error else "LOG"
		var msg := message.strip_edges()
		if not _should_write_once_per_frame(tag + "|" + msg):
			return
		if "\n" in msg:
			_write_line("[%s] [%s]" % [_timestamp(), tag])
			_write_multiline("  ", msg)
		else:
			_write_line("[%s] [%s] %s" % [_timestamp(), tag, msg])


	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		editor_notify: bool,
		error_type: int,
		script_backtraces: Array[ScriptBacktrace],
	) -> void:
		if not _should_write_once_per_frame("ERR|%s|%s|%d|%s" % [rationale, file, line, code]):
			return
		_write_line("────────────────────────────────────────")
		var kind := _error_kind_label(error_type)
		_write_line("[%s] [%s] %s" % [_timestamp(), kind, rationale if not rationale.is_empty() else code])

		if not file.is_empty() or not function.is_empty():
			var at_line := ":%d" % line if line > 0 else ""
			_write_line("  at: %s%s @ %s()" % [file, at_line, function])

		if not code.is_empty() and code != rationale:
			_write_line("  code: %s" % code)

		if editor_notify:
			_write_line("  editor_notify: true")

		var trace_text := _format_backtraces(script_backtraces)
		if not trace_text.is_empty():
			_write_line("  backtrace:")
			_write_multiline("    ", trace_text)

		if trace_text.is_empty() and not rationale.is_empty() and rationale != code:
			_write_line("  detail: %s" % rationale)
