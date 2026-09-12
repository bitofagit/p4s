extends Node

## MetaManager (autoload): **cross-save** progression — Insight (research points), purchased upgrades, dev_mode flag.
## Persisted separately from farm saves (`user://shadow_logic_meta.json`). Farm state is FarmDataManager + SaveManager.
## Broader orientation: docs/CODEBASE_GUIDE.md

const SAVE_PATH = "user://shadow_logic_meta.json"

## 4-tier graphics preset IDs (stored in shadow_logic_meta.json as `graphics_preset`).
const PRESET_LOW := 0
const PRESET_MEDIUM := 1
const PRESET_HIGH := 2
const PRESET_CUSTOM := 3
const PRESET_LABELS: Array[String] = ["Low", "Medium", "High", "Custom"]

## Macro rendering matrix — applied when preset slider is 0, 1, or 2.
## Low keeps real LOD plant atlases (no vector/rect stand-ins) so species stay readable.
const PRESET_DEFINITIONS: Array[Dictionary] = [
	{
		"render_groundcover": false,
		"render_understory": true,
		"dynamic_zoom_culling": true,
		"low_end_gpu": true,
		"weather_particles": 80,
		"advanced_overlays": false,
		"data_lens_fx": false,
		"flora_vector_far_zoom": false,
		"music_lite": true,
	},
	{
		"render_groundcover": false,
		"render_understory": true,
		"dynamic_zoom_culling": true,
		"low_end_gpu": false,
		"weather_particles": 100,
		"advanced_overlays": false,
		"data_lens_fx": false,
		"flora_vector_far_zoom": false,
		"music_lite": true,
	},
	{
		"render_groundcover": true,
		"render_understory": true,
		"dynamic_zoom_culling": true,
		"low_end_gpu": false,
		"weather_particles": 500,
		"advanced_overlays": true,
		"data_lens_fx": true,
		"flora_vector_far_zoom": false,
		"music_lite": false,
	},
]

signal graphics_settings_changed

var current_insight: int = 0
var unlocked_upgrades: Array = []
var dev_mode: bool = false # Sandbox: skip training script and scripted weather
var magnetic_docking: bool = true

# --- Graphics settings (safe-boot LOW defaults until shadow_logic_meta.json exists) ---
var graphics_preset: int = PRESET_LOW
var render_groundcover: bool = false
var render_understory: bool = true
var dynamic_zoom_culling: bool = true
var low_end_gpu: bool = true
## Rain CPUParticles2D emission cap (clamped live when weather is active).
var weather_particles: int = 80
## Swale shimmers, structure washes, fence overlays, capillary loops.
var advanced_overlays: bool = false
## Trigonometric nutrient ribbons / rim waves in data lenses (flat blocks when off).
var data_lens_fx: bool = false
## Replace far LOD atlas sprites with basic vector shapes at extreme zoom-out.
## Off on Low/Medium/High: far LOD uses the baked sprite atlas, not coloured blobs.
var flora_vector_far_zoom: bool = false
## Skip the 16-track drum playlist; keep Idle / Planning / Dash only.
var music_lite: bool = true

var _applying_preset := false
var _first_boot_no_meta := false


func _ready() -> void:
	load_meta()
	call_deferred("_boot_graphics_profile")


func preset_label(preset_id: int = -1) -> String:
	var id := preset_id if preset_id >= 0 else graphics_preset
	id = clampi(id, PRESET_LOW, PRESET_CUSTOM)
	return PRESET_LABELS[id]


## Apply a fixed macro preset (0–2). Refines `low_end_gpu` for capable modern hardware.
func apply_graphics_preset(preset_id: int, persist: bool = true) -> void:
	if preset_id < PRESET_LOW or preset_id > PRESET_HIGH:
		return
	_applying_preset = true
	graphics_preset = preset_id
	_apply_definition_fields(PRESET_DEFINITIONS[preset_id])
	_detect_low_end_gpu()
	_applying_preset = false
	_sync_radio_music_profile()
	if persist:
		save_meta()
	graphics_settings_changed.emit()


func _apply_definition_fields(def: Dictionary) -> void:
	render_groundcover = bool(def.get("render_groundcover", false))
	render_understory = bool(def.get("render_understory", true))
	dynamic_zoom_culling = bool(def.get("dynamic_zoom_culling", true))
	low_end_gpu = bool(def.get("low_end_gpu", false))
	weather_particles = clampi(int(def.get("weather_particles", 80)), 20, 800)
	advanced_overlays = bool(def.get("advanced_overlays", false))
	data_lens_fx = bool(def.get("data_lens_fx", false))
	flora_vector_far_zoom = bool(def.get("flora_vector_far_zoom", false))
	music_lite = bool(def.get("music_lite", false))


## Call when the player edits an individual graphics toggle while on a fixed tier.
func notify_graphics_customised() -> void:
	if _applying_preset or graphics_preset == PRESET_CUSTOM:
		return
	graphics_preset = PRESET_CUSTOM
	save_meta()
	graphics_settings_changed.emit()


## Deferred: GPU context is ready. First run picks Medium for Iris Xe / 8GB
## laptops (readable flora, no potato streaming) and keeps Low for VMware / HD 520.
func _boot_graphics_profile() -> void:
	_detect_low_end_gpu()
	if _first_boot_no_meta:
		var recommended := recommend_first_run_preset()
		_first_boot_no_meta = false
		apply_graphics_preset(recommended, true)
		print(
			"[P4S] first-run preset=%s low_end_gpu=%s (gpu=%s ram=%.0fMB)"
			% [
				preset_label(recommended),
				str(low_end_gpu),
				RenderingServer.get_video_adapter_name(),
				float(physical_ram_mb()),
			]
		)
		return
	_sync_radio_music_profile()


func recommend_first_run_preset() -> int:
	if OS.has_feature("p4s_low_end"):
		return PRESET_LOW
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	var vendor := RenderingServer.get_video_adapter_vendor().to_lower()
	var adapter_type := RenderingServer.get_video_adapter_type()
	if _is_legacy_or_virtual_gpu(gpu, vendor, adapter_type):
		return PRESET_LOW
	if _is_capable_modern_gpu(gpu, vendor):
		# Iris Xe / 8GB shared RAM: Medium flora (LOD atlases) + restrained FX.
		# High is opt-in for discrete GPUs with more than 8GB.
		if _is_discrete_gpu(adapter_type) and physical_ram_mb() > 8704:
			return PRESET_HIGH
		return PRESET_MEDIUM
	if physical_ram_mb() > 12000 and _is_discrete_gpu(adapter_type):
		return PRESET_HIGH
	return PRESET_LOW


func physical_ram_mb() -> int:
	var info: Dictionary = OS.get_memory_info()
	if info.is_empty():
		return 0
	return int(float(info.get("physical", 0)) / 1048576.0)


func is_memory_constrained() -> bool:
	var mb := physical_ram_mb()
	return mb > 0 and mb <= 8704


func _is_discrete_gpu(adapter_type: int) -> bool:
	return adapter_type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU


func _sync_radio_music_profile() -> void:
	var radio := Engine.get_main_loop()
	if radio == null:
		return
	var tree := radio as SceneTree
	if tree == null:
		return
	var node := tree.root.get_node_or_null("RadioManager")
	if node != null and node.has_method("apply_music_profile"):
		node.call("apply_music_profile")


func _detect_low_end_gpu() -> void:
	if OS.has_feature("p4s_low_end"):
		low_end_gpu = true
		print("[P4S] low_end_gpu=ON (export feature p4s_low_end)")
		return

	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	var vendor := RenderingServer.get_video_adapter_vendor().to_lower()
	var adapter_type := RenderingServer.get_video_adapter_type()

	if gpu.is_empty():
		return

	# Iris Xe / Arc / "Xe Graphics" are capable 2D iGPUs — never treat as SVGA.
	if _is_iris_xe_class(gpu):
		low_end_gpu = false
		print("[P4S] low_end_gpu=OFF (Iris Xe class: %s)" % RenderingServer.get_video_adapter_name())
		return

	if _is_legacy_or_virtual_gpu(gpu, vendor, adapter_type):
		low_end_gpu = true
		print("[P4S] low_end_gpu=ON (legacy/virtual: %s)" % RenderingServer.get_video_adapter_name())
		return

	if _is_capable_modern_gpu(gpu, vendor):
		low_end_gpu = false
		return


func _is_iris_xe_class(gpu: String) -> bool:
	return (
		"iris" in gpu
		or "xe graphics" in gpu
		or "intel(r) xe" in gpu
		or "intel xe" in gpu
		or "uhd graphics for" in gpu and "11th" in gpu
		or "7505" in gpu
		or "tiger lake" in gpu
	)


func _is_legacy_or_virtual_gpu(gpu: String, vendor: String, adapter_type: int) -> bool:
	return (
		"vmware" in gpu
		or "svga" in gpu
		or "virtual" in gpu
		or "vmware" in vendor
		or adapter_type == RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU
		or adapter_type == RenderingDevice.DEVICE_TYPE_CPU
		or "intel(r) hd graphics" in gpu
		or "intel hd graphics" in gpu
		or "intel(r) uhd graphics 6" in gpu
		or "intel(r) uhd graphics 5" in gpu
		or "uhd graphics 6" in gpu
		or "uhd graphics 5" in gpu
		or "hd graphics 4" in gpu
		or "hd graphics 5" in gpu
		or "hd graphics 6" in gpu
		or "radeon r4" in gpu
		or "radeon r5" in gpu
		or "radeon r7" in gpu
		or "radeon vega 3" in gpu
		or "radeon vega 8" in gpu
	)


func _is_capable_modern_gpu(gpu: String, vendor: String) -> bool:
	if _is_iris_xe_class(gpu) or " arc " in gpu or "intel(r) arc" in gpu:
		return true
	if "apple" in gpu or "apple" in vendor or "m1" in gpu or "m2" in gpu or "m3" in gpu or "m4" in gpu:
		return true
	if "nvidia" in gpu or "nvidia" in vendor or "geforce" in gpu or "rtx" in gpu or "gtx" in gpu:
		return true
	if "radeon" in gpu and not _is_legacy_radeon_igpu(gpu):
		return true
	return false


func _is_legacy_radeon_igpu(gpu: String) -> bool:
	return (
		"radeon r4" in gpu
		or "radeon r5" in gpu
		or "radeon r7" in gpu
		or "radeon vega 3" in gpu
		or "radeon vega 8" in gpu
	)


func ensure_low_end_detected() -> void:
	_detect_low_end_gpu()


var upgrade_db = {
	"trust_fund": {
		"name": "Starter Grant",
		"type": "Agricultural",
		"cost": 10,
		"desc": "Field subsidy. Start with +£30."
	},
	"thick_gloves": {
		"name": "Ergonomic Tools",
		"type": "Agricultural",
		"cost": 15,
		"desc": "Uprooting costs 1 Energy instead of 2."
	},
	"poltergeist_labour": {
		"name": "Automated Maintenance",
		"type": "Systemic",
		"cost": 25,
		"desc": "+2 Maximum Energy each run."
	},
	"ecto_fungi": {
		"name": "Inoculated Soil",
		"type": "Systemic",
		"cost": 30,
		"desc": "Fungal affinity gains +20% from plants."
	},
	"hypnotic_charm": {
		"name": "Premium Organic Certification",
		"type": "Systemic",
		"cost": 40,
		"desc": "Farm stand +£2 per sale; crop sales +20%."
	}
}


func load_meta() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_first_boot_no_meta = true
		apply_graphics_preset(PRESET_LOW, false)
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	if data and typeof(data) == TYPE_DICTIONARY:
		if data.has("insight"):
			current_insight = int(data.get("insight", 0))
		else:
			current_insight = int(data.get("karma", 0))
		unlocked_upgrades = data.get("unlocked", [])
		magnetic_docking = bool(data.get("magnetic_docking", true))
		graphics_preset = clampi(int(data.get("graphics_preset", PRESET_LOW)), PRESET_LOW, PRESET_CUSTOM)
		if graphics_preset == PRESET_CUSTOM:
			render_groundcover = bool(data.get("render_groundcover", false))
			render_understory = bool(data.get("render_understory", false))
			dynamic_zoom_culling = bool(data.get("dynamic_zoom_culling", true))
			low_end_gpu = bool(data.get("low_end_gpu", true))
			weather_particles = clampi(int(data.get("weather_particles", 80)), 20, 800)
			advanced_overlays = bool(data.get("advanced_overlays", false))
			data_lens_fx = bool(data.get("data_lens_fx", false))
			flora_vector_far_zoom = bool(data.get("flora_vector_far_zoom", false))
			music_lite = bool(data.get("music_lite", true))
		else:
			apply_graphics_preset(graphics_preset, false)


func save_meta() -> void:
	var data = {
		"insight": current_insight,
		"unlocked": unlocked_upgrades,
		"magnetic_docking": magnetic_docking,
		"graphics_preset": graphics_preset,
		"render_groundcover": render_groundcover,
		"render_understory": render_understory,
		"dynamic_zoom_culling": dynamic_zoom_culling,
		"low_end_gpu": low_end_gpu,
		"weather_particles": weather_particles,
		"advanced_overlays": advanced_overlays,
		"data_lens_fx": data_lens_fx,
		"flora_vector_far_zoom": flora_vector_far_zoom,
		"music_lite": music_lite,
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))


func has_upgrade(id: String) -> bool:
	return unlocked_upgrades.has(id)


func buy_upgrade(id: String) -> bool:
	if not upgrade_db.has(id) or has_upgrade(id):
		return false
	var cost = upgrade_db[id]["cost"]
	if current_insight >= cost:
		current_insight -= cost
		unlocked_upgrades.append(id)
		save_meta()
		return true
	return false
