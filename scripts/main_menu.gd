extends Control

## Main menu UI: entry point before `scenes/world.tscn`. Sets `SaveManager.pending_load_save_name`
## and `MetaManager.dev_mode` then **change_scene** to the world. Application main scene in project settings.
## `_ready` adds a top-left **Mute Audio** CheckButton (AudioServer Master bus) and embeds `ui_graphics_panel` / `ui_audio_panel` scripts.
## Broader orientation: docs/CODEBASE_GUIDE.md

var main_panel: VBoxContainer
var graphics_panel: Control
var audio_panel: Control
var creative_panel: Control
var campaign_panel: Control
var _asset_hub: Control
var _mute_btn: CheckButton

## Autoload singletons (resolved via /root/ so the parser always sees a declared identifier).
@onready var _farm_data_manager: Node = get_node("/root/FarmDataManager")
@onready var _save_manager: Node = get_node("/root/SaveManager")
@onready var _meta_manager: Node = get_node("/root/MetaManager")


func _ready() -> void:
	# SaveManager (autoload _ready) already applied display mode + UI scale.
	var saved_ui := float(_save_manager.display_settings.get("ui_scale", 1.0))
	get_tree().root.content_scale_factor = saved_ui

	# --- BACKGROUND ---
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var wrapper = VBoxContainer.new()
	wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
	wrapper.add_theme_constant_override("separation", 40)
	center.add_child(wrapper)

	# --- TITLE ---
	var title = Label.new()
	title.text = "Permaculture 4 Squares"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("aed581"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrapper.add_child(title)

	# --- MAIN MENU PANEL ---
	main_panel = VBoxContainer.new()
	main_panel.add_theme_constant_override("separation", 15)
	wrapper.add_child(main_panel)

	var btn_continue = Button.new()
	btn_continue.text = "Continue"
	btn_continue.pressed.connect(func():
		_save_manager.pending_load_save_name = "autosave"
		_meta_manager.dev_mode = false
		get_tree().change_scene_to_file("res://scenes/world.tscn")
	)
	main_panel.add_child(btn_continue)

	var btn_campaign = Button.new()
	btn_campaign.text = "Play Campaign"
	btn_campaign.pressed.connect(func():
		main_panel.hide()
		campaign_panel.show()
	)
	main_panel.add_child(btn_campaign)

	var diff_hbox = HBoxContainer.new()
	diff_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var diff_label = Label.new()
	diff_label.text = "Difficulty: "
	diff_hbox.add_child(diff_label)
	var diff_dropdown = OptionButton.new()
	diff_dropdown.add_item("Easy")
	diff_dropdown.add_item("Normal")
	diff_dropdown.add_item("Hard")
	diff_dropdown.select(1)
	diff_dropdown.item_selected.connect(func(idx: int):
		_farm_data_manager.difficulty = diff_dropdown.get_item_text(idx)
	)
	diff_hbox.add_child(diff_dropdown)
	_farm_data_manager.difficulty = "Normal"
	main_panel.add_child(diff_hbox)
	main_panel.move_child(diff_hbox, btn_campaign.get_index())

	var btn_creative = Button.new()
	btn_creative.text = "Creative Sandbox"
	btn_creative.pressed.connect(func():
		main_panel.hide()
		if creative_panel.has_method("refresh_mod_options"):
			creative_panel.refresh_mod_options()
		creative_panel.show()
	)
	main_panel.add_child(btn_creative)

	var btn_dev = Button.new()
	btn_dev.text = "New Game (Dev Mode)"
	btn_dev.pressed.connect(_launch_game.bind(true))
	main_panel.add_child(btn_dev)

	var btn_load = Button.new()
	btn_load.text = "Load Game"
	btn_load.pressed.connect(func():
		_save_manager.pending_load_save_name = "slot_1"
		_meta_manager.dev_mode = false
		get_tree().change_scene_to_file("res://scenes/world.tscn")
	)
	main_panel.add_child(btn_load)

	var btn_gfx = Button.new()
	btn_gfx.text = "Graphics & UI"
	btn_gfx.pressed.connect(func():
		main_panel.hide()
		if graphics_panel.has_method("sync_controls_from_system"):
			graphics_panel.sync_controls_from_system()
		graphics_panel.show()
	)
	main_panel.add_child(btn_gfx)

	var btn_audio = Button.new()
	btn_audio.text = "Sound Settings"
	btn_audio.pressed.connect(func(): main_panel.hide(); audio_panel.show())
	main_panel.add_child(btn_audio)

	var btn_asset_os = Button.new()
	btn_asset_os.text = "Asset Manager"
	btn_asset_os.pressed.connect(_open_asset_hub)
	main_panel.add_child(btn_asset_os)

	var btn_quit = Button.new()
	btn_quit.text = "Quit"
	btn_quit.pressed.connect(func(): get_tree().quit())
	main_panel.add_child(btn_quit)

	# --- GRAPHICS PANEL ---
	graphics_panel = preload("res://scripts/ui_graphics_panel.gd").new()
	graphics_panel.hide()
	wrapper.add_child(graphics_panel)

	graphics_panel.back_pressed.connect(func(): graphics_panel.hide(); main_panel.show())

	# --- AUDIO PANEL ---
	audio_panel = preload("res://scripts/ui_audio_panel.gd").new()
	audio_panel.hide()
	wrapper.add_child(audio_panel)
	audio_panel.back_pressed.connect(func(): audio_panel.hide(); main_panel.show())

	# --- CREATIVE MODE PANEL ---
	creative_panel = preload("res://scripts/ui_creative_setup.gd").new()
	creative_panel.hide()
	wrapper.add_child(creative_panel)
	creative_panel.launch_creative.connect(_on_launch_creative)
	creative_panel.cancel_creative.connect(func(): creative_panel.hide(); main_panel.show())

	campaign_panel = preload("res://scripts/ui_campaign_select.gd").new()
	campaign_panel.hide()
	wrapper.add_child(campaign_panel)
	campaign_panel.cancel_campaign.connect(func(): campaign_panel.hide(); main_panel.show())

	_asset_hub = preload("res://scripts/ui_asset_hub.gd").new()
	_asset_hub.hide()
	_asset_hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_asset_hub)
	_asset_hub.close_requested.connect(_close_asset_hub)

	# --- Mute Toggle ---
	_mute_btn = CheckButton.new()
	_mute_btn.text = "Mute Audio"
	_mute_btn.position = Vector2(20, 20)
	_mute_btn.focus_mode = Control.FOCUS_NONE
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		_mute_btn.button_pressed = AudioServer.is_bus_mute(master_bus)
		_mute_btn.toggled.connect(func(is_muted: bool):
			AudioServer.set_bus_mute(master_bus, is_muted)
		)
	else:
		_mute_btn.disabled = true
	add_child(_mute_btn)

	GodotDocsLog.log_milestone("main_menu_ready")


func _unhandled_input(event: InputEvent) -> void:
	if _mute_btn == null or _mute_btn.disabled:
		return
	if not event is InputEventKey:
		return
	var key_ev := event as InputEventKey
	if not key_ev.pressed or key_ev.echo:
		return
	if key_ev.keycode != KEY_M and key_ev.physical_keycode != KEY_M:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	_mute_btn.button_pressed = not _mute_btn.button_pressed
	get_viewport().set_input_as_handled()


func _launch_game(is_dev: bool) -> void:
	_meta_manager.dev_mode = is_dev
	_save_manager.pending_load_save_name = ""
	_farm_data_manager.reset_data()
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _on_launch_creative(overrides: Dictionary) -> void:
	_meta_manager.dev_mode = false
	_save_manager.pending_load_save_name = ""
	_farm_data_manager.reset_data(overrides)
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _open_asset_hub() -> void:
	main_panel.hide()
	if is_instance_valid(_asset_hub):
		_asset_hub.show()
		if _asset_hub.has_method("_populate_file_tree"):
			_asset_hub._populate_file_tree()


func _close_asset_hub() -> void:
	if is_instance_valid(_asset_hub):
		_asset_hub.hide()
	main_panel.show()
