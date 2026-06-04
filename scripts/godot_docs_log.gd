extends Node

## Autoload: mirrors Godot console output into the project `docs/` folder (next to CODEBASE_GUIDE.md).
## Session files: `docs/godot_error_log_YYYY-MM-DD_HH-mm-ss.txt` (keeps newest 10).
## Index: `docs/godot_error_log.txt` points at the current session log.


func _init() -> void:
	OS.add_logger(DocsFileLogger.new())


class DocsFileLogger extends Logger:
	const LOG_DIR := "res://docs/"
	const LOG_PREFIX := "godot_error_log_"
	const LOG_SUFFIX := ".txt"
	const INDEX_PATH := "res://docs/godot_error_log.txt"
	const MAX_RETAINED_LOGS := 10

	var _mutex := Mutex.new()
	var _file: FileAccess
	var _session_log_res_path := ""


	func _init() -> void:
		_open_file()


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


	func _ensure_log_dir() -> String:
		var abs_dir := ProjectSettings.globalize_path(LOG_DIR)
		DirAccess.make_dir_recursive_absolute(abs_dir)
		return abs_dir


	func _open_file() -> void:
		var abs_dir := _ensure_log_dir()
		var basename := _session_basename()
		_session_log_res_path = LOG_DIR.path_join(basename)
		var abs_path := ProjectSettings.globalize_path(_session_log_res_path)

		_file = FileAccess.open(abs_path, FileAccess.WRITE)
		if _file:
			_write_line("--- session %s ---" % Time.get_datetime_string_from_system())
			_write_line(
				"Godot %s | log: %s"
				% [Engine.get_version_info().get("string", "?"), abs_path]
			)
			_prune_old_logs(abs_dir)
			_write_index(abs_dir)


	func _list_session_logs(abs_dir: String) -> Array[String]:
		var names: Array[String] = []
		var dir := DirAccess.open(abs_dir)
		if dir == null:
			return names
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and entry.begins_with(LOG_PREFIX) and entry.ends_with(LOG_SUFFIX) \
				and entry != "godot_error_log.txt":
				names.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
		names.sort()
		return names


	func _prune_old_logs(abs_dir: String) -> void:
		var names := _list_session_logs(abs_dir)
		while names.size() > MAX_RETAINED_LOGS:
			var oldest := names[0]
			names.remove_at(0)
			DirAccess.remove_absolute(abs_dir.path_join(oldest))


	func _write_index(abs_dir: String) -> void:
		var names := _list_session_logs(abs_dir)
		names.reverse() # newest first
		var lines: PackedStringArray = PackedStringArray([
			"# P4S Godot error log index (auto-generated — do not edit)",
			"#",
			"# Convention: docs/godot_error_log_YYYY-MM-DD_HH-mm-ss.txt (project folder, not user://)",
			"# Retention: newest %d session files; oldest deleted on each new run." % MAX_RETAINED_LOGS,
			"#",
			"# Current session:",
			"docs/%s" % _session_log_res_path.get_file(),
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


	func _write_line(text: String) -> void:
		_mutex.lock()
		if _file and _file.is_open():
			_file.store_string(text.rstrip(" \t\r\n") + "\n")
			_file.flush()
		_mutex.unlock()


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


	func _log_message(message: String, error: bool) -> void:
		var tag := "WARN" if error else "LOG"
		var msg := message.strip_edges()
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
