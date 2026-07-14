extends Node

## RadioManager (autoload): **music and interactive audio** — playlist, beats, BPM/key hooks.
## Gameplay can sync to `native_beat_hit` / beat state where needed.
## Broader orientation: docs/CODEBASE_GUIDE.md

const RADIO_USER_DIR := "user://audio/radio/"

## Peak target for procedural drum one-shots in the Idle playlist (~-12 dBFS).
const BEAT_TARGET_PEAK_DB := -12.0
const BEAT_BUS_VOLUME_DB := -6.0
const SFX_POOL_VOLUME_DB := -12.0
const SFX_PLAY_VOLUME_MIN_DB := -12.0
const SFX_PLAY_VOLUME_MAX_DB := -6.0
const MUSIC_PLAYER_VOLUME_DB := -6.0

# --- Custom radio (user://audio/radio/<station>/*.mp3|ogg) ---
var custom_stations: Dictionary = {} # folder name -> Array of file paths
var current_station_name: String = ""
var current_radio_track_index: int = 0
var audio_mode: String = "generative" # "generative", "radio", or "mute"
var radio_player: AudioStreamPlayer
var _current_station_paths: Array[String] = []

# --- GODOT 4.3 INTERACTIVE AUDIO ---
var interactive_music: AudioStreamInteractive = preload("res://assets/base/audio/farm_music.tres")
var music_player: AudioStreamPlayer

# Native Godot signal to replace our manual metronome
signal native_beat_hit(beat_index: int)
var _global_beat_tracker: int = 0
var current_music_state: String = ""
## Last beat index from interactive stream playback (for sync loops like advance_turn).
var current_beat: int = 0

var current_bpm: int = 75
var current_key_index: int = 0 # 0 = C, 1 = C#, etc.

# Extended 2-Octave Major Pentatonic
const PENTATONIC_INTERVALS = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]
var last_interval_index: int = 4
var zip_index: int = 0

# Keys for the UI dropdown
const KEYS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# We will generate AudioStreamPlayers dynamically
var pool_size: int = 8
var audio_players: Array[AudioStreamPlayer] = []

# Generative daytime chimes (pentatonic SFX pool)
var base_sample: AudioStream = preload("res://assets/base/audio/sfx/chimes/glock-c1.wav")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()

	# Setup the Interactive Music Player
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Drums"
	music_player.volume_db = MUSIC_PLAYER_VOLUME_DB
	if interactive_music:
		music_player.stream = interactive_music
	add_child(music_player)

	# --- SAFE DYNAMIC PLAYLIST & SYNC ---
	if interactive_music:
		var dynamic_playlist = AudioStreamPlaylist.new()
		dynamic_playlist.shuffle = true

		var dir = DirAccess.open("res://assets/base/audio/beats")
		var collected: Array[AudioStream] = []
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if not dir.current_is_dir():
					var clean_name = file_name.replace(".import", "")
					if clean_name.ends_with(".wav") or clean_name.ends_with(".ogg"):
						var stream_loaded = load("res://assets/base/audio/beats/" + clean_name) as AudioStream
						if stream_loaded and stream_loaded not in collected:
							stream_loaded = _normalize_beat_stream(stream_loaded)
							stream_loaded.set("bpm", 75.0)
							stream_loaded.set("beat_count", 16)
							# CRITICAL: We do NOT set native loop_mode here.
							collected.append(stream_loaded)
				file_name = dir.get_next()
			dir.list_dir_end()

		if collected.size() > 0:
			dynamic_playlist.stream_count = collected.size()
			for idx in range(collected.size()):
				dynamic_playlist.set_list_stream(idx, collected[idx])

		for i in range(interactive_music.clip_count):
			var clip_name = interactive_music.get_clip_name(i)

			# Swap the single Idle track for our massive dynamic playlist
			if clip_name == &"Idle" and dynamic_playlist.stream_count > 0:
				interactive_music.set_clip_stream(i, dynamic_playlist)
			else:
				var stream = interactive_music.get_clip_stream(i)
				if stream:
					stream = _normalize_beat_stream(stream)
					interactive_music.set_clip_stream(i, stream)
					stream.set("bpm", 75.0)
					stream.set("beat_count", 16)

			# Force the Interactive Engine to safely loop the clips forever
			interactive_music.set_clip_auto_advance(i, AudioStreamInteractive.AUTO_ADVANCE_ENABLED)
			interactive_music.set_clip_auto_advance_next_clip(i, i)
	# ---------------------------------------------

	# Setup our Sound Effect AudioPool
	for i in range(pool_size):
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		p.volume_db = SFX_POOL_VOLUME_DB
		add_child(p)
		audio_players.append(p)

	_ensure_bus_reverb("SFX")

	# Fallback (reserved for bus layout sync with interactive music)
	AudioServer.bus_layout_changed.connect(_on_audio_server_update)

	radio_player = AudioStreamPlayer.new()
	radio_player.bus = "Music"
	add_child(radio_player)
	radio_player.finished.connect(_on_radio_track_finished)

	_scan_radio_folders()

	# Start the music!
	if interactive_music:
		music_player.play()


func _scan_radio_folders() -> void:
	custom_stations.clear()
	DirAccess.make_dir_recursive_absolute(RADIO_USER_DIR)
	var root := DirAccess.open(RADIO_USER_DIR)
	if root == null:
		return
	var err := root.list_dir_begin()
	if err != OK:
		root.list_dir_end()
		return
	var entry := root.get_next()
	while entry != "":
		if entry != "." and entry != ".." and root.current_is_dir():
			var folder_path := RADIO_USER_DIR.path_join(entry)
			var paths: Array[String] = []
			var sub := DirAccess.open(folder_path)
			if sub != null:
				var sub_err := sub.list_dir_begin()
				if sub_err == OK:
					var file_name := sub.get_next()
					while file_name != "":
						if not sub.current_is_dir():
							var lower := file_name.to_lower()
							if lower.ends_with(".mp3") or lower.ends_with(".ogg"):
								paths.append(folder_path.path_join(file_name))
						file_name = sub.get_next()
					sub.list_dir_end()
			if paths.size() > 0:
				custom_stations[entry] = paths
		entry = root.get_next()
	root.list_dir_end()


func play_radio_station(station_name: String) -> void:
	if not custom_stations.has(station_name):
		push_warning("RadioManager: unknown station '%s'" % station_name)
		return
	current_station_name = station_name
	current_radio_track_index = 0
	_current_station_paths.clear()
	for path in custom_stations[station_name]:
		_current_station_paths.append(str(path))
	_current_station_paths.shuffle()
	set_audio_mode("radio")
	_play_current_radio_track()


func _play_current_radio_track() -> void:
	if _current_station_paths.is_empty():
		return
	if current_radio_track_index < 0 or current_radio_track_index >= _current_station_paths.size():
		current_radio_track_index = 0
	var path: String = _current_station_paths[current_radio_track_index]
	var stream: AudioStream = _load_external_audio_stream(path)
	if stream == null:
		push_warning("RadioManager: could not load track '%s'" % path)
		return
	radio_player.stream = stream
	radio_player.play()
	var track_label := path.get_file()
	track_changed.emit("%s — %s" % [current_station_name, track_label])


func _load_external_audio_stream(path: String) -> AudioStream:
	var lower := path.to_lower()
	if lower.ends_with(".mp3"):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return null
		var mp3 := AudioStreamMP3.new()
		mp3.data = file.get_buffer(file.get_length())
		return mp3
	if lower.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(path)
	return null


func _on_radio_track_finished() -> void:
	if audio_mode != "radio" or _current_station_paths.is_empty():
		return
	current_radio_track_index += 1
	if current_radio_track_index >= _current_station_paths.size():
		current_radio_track_index = 0
	_play_current_radio_track()


func set_audio_mode(mode: String) -> void:
	if mode not in ["generative", "radio", "mute"]:
		push_warning("RadioManager: unknown audio mode '%s'" % mode)
		return
	audio_mode = mode
	match mode:
		"generative":
			radio_player.stop()
			if interactive_music and music_player.stream:
				if not music_player.playing:
					music_player.play()
			track_changed.emit("Generative")
		"radio":
			music_player.stop()
			if _current_station_paths.is_empty() and current_station_name != "" \
				and custom_stations.has(current_station_name):
				_current_station_paths.clear()
				for path in custom_stations[current_station_name]:
					_current_station_paths.append(str(path))
				_current_station_paths.shuffle()
				current_radio_track_index = 0
			if _current_station_paths.is_empty():
				track_changed.emit("Custom Radio (no tracks)")
		"mute":
			music_player.stop()
			radio_player.stop()
			track_changed.emit("Muted")


func skip_radio_track() -> void:
	if audio_mode != "radio" or _current_station_paths.is_empty():
		return
	current_radio_track_index += 1
	if current_radio_track_index >= _current_station_paths.size():
		current_radio_track_index = 0
	_play_current_radio_track()


func refresh_custom_stations() -> void:
	_scan_radio_folders()


func _on_audio_server_update() -> void:
	_ensure_audio_buses()


func _ensure_audio_buses() -> void:
	_ensure_bus_chain("SFX", "Master")
	_ensure_bus_chain("Music", "Master")
	_ensure_bus_chain("Drums", "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Drums"), BEAT_BUS_VOLUME_DB)
	for bus_name in ["SFX", "Music", "Drums"]:
		_ensure_bus_limiter(bus_name)


func _ensure_bus_chain(bus_name: String, send_to: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus(-1)
		idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, bus_name)
	if AudioServer.get_bus_send(idx) != send_to:
		AudioServer.set_bus_send(idx, send_to)


func _ensure_bus_limiter(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	for i in range(AudioServer.get_bus_effect_count(idx)):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectLimiter:
			return
	var lim := AudioEffectLimiter.new()
	lim.threshold_db = -8.0
	lim.ceiling_db = -0.5
	lim.soft_clip_db = 2.0
	AudioServer.add_bus_effect(idx, lim)


func _ensure_bus_reverb(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	for i in range(AudioServer.get_bus_effect_count(idx)):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectReverb:
			return
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.6
	rev.damping = 0.5
	rev.wet = 0.4
	AudioServer.add_bus_effect(idx, rev)


func _clamp_volume_db(volume_db: float, min_db: float, max_db: float) -> float:
	return clampf(volume_db, min_db, max_db)


func _normalize_beat_stream(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav := stream.duplicate() as AudioStreamWAV
		var data := wav.data
		if data.is_empty() or wav.format != AudioStreamWAV.FORMAT_16_BITS:
			return stream
		var peak := 0
		for offset in range(0, data.size() - 1, 2):
			var sample := data.decode_s16(offset)
			peak = maxi(peak, absi(sample))
		if peak <= 0:
			return wav
		var target_peak := int(32768.0 * pow(10.0, BEAT_TARGET_PEAK_DB / 20.0))
		target_peak = maxi(target_peak, 1)
		if peak <= target_peak:
			return wav
		var gain := float(target_peak) / float(peak)
		var normalized := PackedByteArray()
		normalized.resize(data.size())
		for offset in range(0, data.size() - 1, 2):
			var scaled := int(round(float(data.decode_s16(offset)) * gain))
			normalized.encode_s16(offset, clampi(scaled, -32768, 32767))
		wav.data = normalized
		return wav
	return stream


func set_music_state(clip_name: String) -> void:
	# Don't restart the music if we are already in this vibe!
	if clip_name == current_music_state:
		return

	current_music_state = clip_name
	print("🎵 VIBE SHIFT: Changing music state to -> ", clip_name)

	if music_player.stream is AudioStreamInteractive:
		var playback = music_player.get_stream_playback()
		if playback and playback.has_method("switch_to_clip_by_name"):
			playback.switch_to_clip_by_name(StringName(clip_name))
	else:
		print("⚠️ No Interactive Music resource loaded in RadioManager yet!")


# We process this purely to extract Godot's native timing for our Daytime Echoes
func _process(_delta: float) -> void:
	if music_player.playing:
		var playback = music_player.get_stream_playback()
		if playback and playback.has_method("get_current_beat"):
			var current_engine_beat = int(playback.get_current_beat())
			if current_engine_beat != _global_beat_tracker:
				_global_beat_tracker = current_engine_beat
				current_beat = _global_beat_tracker
				native_beat_hit.emit(_global_beat_tracker)


func get_beat_duration() -> float:
	# 60 seconds / BPM = duration of one quarter note
	return 60.0 / float(current_bpm)


func play_action_note(action_type: String = "") -> void:
	if not base_sample:
		return

	# Wander up or down the pentatonic scale for variety
	var step_options = [-2, -1, 1, 2]
	var step = step_options.pick_random()
	last_interval_index = clampi(last_interval_index + step, 0, PENTATONIC_INTERVALS.size() - 1)

	var selected_interval = PENTATONIC_INTERVALS[last_interval_index]

	# Drop the pitch down an octave for heavy ground-work!
	var octave_shift = 0
	if action_type in ["rotovate", "dig", "build", "earthworks"]:
		octave_shift = -1

	var total_semitones = current_key_index + selected_interval + (octave_shift * 12)
	var pitch = pow(2.0, float(total_semitones) / 12.0)

	# Find an empty audio player in our pool and play the note
	for p in audio_players:
		if not p.playing:
			p.stream = base_sample
			p.pitch_scale = pitch
			p.volume_db = _clamp_volume_db(
				randf_range(SFX_PLAY_VOLUME_MIN_DB, SFX_PLAY_VOLUME_MAX_DB),
				SFX_PLAY_VOLUME_MIN_DB,
				SFX_PLAY_VOLUME_MAX_DB,
			)
			p.play()
			break


# --- Legacy pause-menu hooks (station playlists removed). Keeps HUD buttons from erroring. ---
signal track_changed(track_name: String)


func load_station(station_name: String) -> void:
	play_radio_station(station_name)


func next_track() -> void:
	skip_radio_track()


func stop() -> void:
	set_audio_mode("mute")


func play_zip_note() -> void:
	if not base_sample:
		return

	zip_index = (zip_index + 1) % PENTATONIC_INTERVALS.size()
	var selected_interval = PENTATONIC_INTERVALS[zip_index]

	# Push it up +2 Octaves so it sounds like chimes/fairy dust
	var total_semitones = current_key_index + selected_interval + 24
	var pitch = pow(2.0, float(total_semitones) / 12.0)

	for p in audio_players:
		if not p.playing:
			p.stream = base_sample
			p.pitch_scale = pitch
			p.volume_db = -24.0 # EXTREMELY quiet, letting the reverb do the work
			p.play()
			break
