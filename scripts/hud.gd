extends Control

## In-game HUD (`hud.tscn` + runtime `hud.gd`): **status strip** (`StatusStrip`), **InfoDock** (tile hover + forecast), bottom tool bar, queue, inspector, almanac, workers, save/load **signals**.
## `starting_map.gd` connects these signals to FarmDataManager / SaveManager / tools — HUD stays mostly “dumb UI”.
## Pause overlay (`CanvasLayer/Pause_Overlay`): Sound / Graphics / Gameplay settings swap inside the pause panel (same pattern as main menu).
## Broader orientation: docs/CODEBASE_GUIDE.md

signal action_selected(action_name: String)
signal quick_tool_selected(tool_id: String)
signal lens_selected(lens_name: String)
signal inventory_selected(item_name: String)
@warning_ignore("unused_signal")
signal info_selected(info_name: String)
signal save_requested(save_name: String)
signal load_requested(save_name: String)
@warning_ignore("unused_signal")
signal settings_requested
@warning_ignore("unused_signal")
signal hotkeys_requested
signal main_menu_requested
signal undo_pressed
signal redo_pressed
signal produce_action_requested(action: String, item_key: String)

var weather_panel: PanelContainer
var season_label: Label
var weather_desc_label: Label

## Right-side tile hover + inbox dock (`_setup_info_dock`).
var info_dock_panel: PanelContainer
var forecast_events_content: RichTextLabel
var forecast_events_header: Label

## Weather & calendar sidebar docks (edge-tab pop-outs).
var weather_dock: PanelContainer
var weather_grid: GridContainer
var weather_detail_box: PanelContainer
var weather_detail_label: RichTextLabel

var calendar_dock: PanelContainer
var calendar_header_row: HBoxContainer
var calendar_month_title: Label
var calendar_prev_btn: Button
var calendar_today_btn: Button
var calendar_next_btn: Button
var calendar_month_grid: GridContainer
var calendar_detail_box: PanelContainer
var calendar_detail_label: RichTextLabel
var _calendar_view_year: int = 1
var _calendar_view_month_index: int = 0

var inspector_panel: PanelContainer
var inspector_preview_box: Control
var inspector_icon: TextureRect
var inspector_ground_rect: TextureRect
var inspector_understory_rect: TextureRect
var inspector_canopy_shadow_rect: TextureRect
var inspector_canopy_rect: TextureRect
var inspector_label: RichTextLabel
var soil_profile_ui: SoilProfileUI
var _inspector_flora_atlas_tex: Texture2D

var minimap_panel: PanelContainer
var minimap_rect: TextureRect

var queue_panel: PanelContainer
var queue_list: VBoxContainer

## Ergonomics: Civ-style edge tabs (collapsed symbols that pop panels out) + Tab quick-select wheel.
const EDGE_TAB_W := 48.0
const EDGE_TAB_YELLOW := Color(1.0, 0.92, 0.25, 1.0)
const BOTTOM_TOOLBAR_H := 130.0
const BOTTOM_PANEL_H := 110.0
const SLEEP_ICON_MAX := 92.0
const FORECAST_DAYS := 25
const FORECAST_COLS := 5
const ACCURATE_FORECAST_DAYS := 5
const MONTH_GRID_COLS := 7
const MONTH_DAYS := 28
const WEATHER_EMOJI := {
	"clear": "☀️",
	"rain": "🌧️",
	"dry": "🏜️",
	"frost": "❄️",
	"drought": "🏜️",
}
const WEATHER_FLAVOR := {
	"clear": "Sunny and bright. Plants will grow nicely, but keep an eye on the soil as it might start to dry out.",
	"rain": "A good splash of water for the farm. Great for naturally topping up your swales and giving thirsty plants a drink.",
	"dry": "A real scorcher. The ground will dry up quickly today, so make sure your thirsty crops are well watered!",
	"frost": "Bitter cold. Delicate plants won't survive this without protection, like a polytunnel.",
	"drought": "A real scorcher. The ground will dry up quickly today, so make sure your thirsty crops are well watered!",
}
var _edge_tab_strips: Dictionary = {} # DockSide -> VBoxContainer
var _edge_tabs: Dictionary = {} # panel -> Button
var _edge_close_btns: Dictionary = {} # DockSide -> Button
var _panel_dock_side: Dictionary = {} # panel -> DockSide
var _dock_open: Dictionary = {} # dock -> bool
var _dock_slide_tweens: Dictionary = {}
var quick_wheel: PanelContainer
var _quick_wheel_hover: String = ""

var active_tool_label: RichTextLabel
var _last_tool_display: String = ""
var _unread_mail: bool = false
var cell_context_menu: PopupMenu
var note_dialog: AcceptDialog
var note_input: TextEdit
var _context_grid_pos: Vector2i
var design_toolbar: PanelContainer
var clear_design_dialog: ConfirmationDialog

@onready var modal_dimmer: ColorRect = $CanvasLayer/Modal_Dimmer
@onready var almanac_window: Window = $CanvasLayer/Almanac_Window
@onready var almanac_content: RichTextLabel = $CanvasLayer/Almanac_Window/MarginContainer/VBoxContainer/Almanac_Content
@onready var almanac_close_button: Button = $CanvasLayer/Almanac_Window/MarginContainer/VBoxContainer/TitleRow/Almanac_Close_Button

var codex_window: Control
var _sidebar_drag: UISidebarDragController
var scanner_window: Window
var dev_console: RichTextLabel
var dev_panel: PanelContainer

var workers_window: PanelContainer
var dockable_panels: Array[Control] = []
## Stitch-style fixed side rails (scroll + reorder widgets; blocks map zoom wheel).
var left_sidebar_dock: UISidebarDock
var right_sidebar_dock: UISidebarDock
var _panel_sidebar_widgets: Dictionary = {}
var _dock_tween: Tween
var _workers_display_count: int = -1

## Money / turn on the status strip (`_setup_status_strip`).
var vitals_label: Label
## Oakhaven Defence political metrics (visible only for that campaign).
var political_metrics_bar: PanelContainer
var political_money_label: Label
var political_education_label: Label
var political_ecology_label: Label
var political_sanity_label: Label

const Z_SIDEBAR := 10
const Z_MODAL_CONTENT := 80
const Z_HUD_CHROME := 500

var indicator_settings: Dictionary = {
	"actions": true, # Planting, Scything, Uprooting
	"ecology": true, # Duck frenzies, soil remediation
	"warnings": true, # Seed explosions, frostbite, dry / harsh weather
}

# --- RADIO VARIABLES ---
var radio_label: Label

# --- TIME MACHINE (creative / dev) ---
var time_machine_controls: HBoxContainer
var timeline_slider: HSlider
var timeline_turn_label: Label
var timeline_index_label: Label
var _btn_time_back: Button
var _btn_time_forward: Button
var _time_machine_slider_syncing: bool = false

@onready var actions_menu: MenuButton = $CanvasLayer/Bottom_Dashboard/PanelContainer/HBoxContainer/Middle/Actions_Menu
@onready var build_menu: MenuButton = $CanvasLayer/Bottom_Dashboard/PanelContainer/HBoxContainer/Middle/Build_Menu
@onready var lenses_menu: MenuButton = $CanvasLayer/Bottom_Dashboard/PanelContainer/HBoxContainer/Middle/Lenses_Menu
@onready var inventory_menu: MenuButton = $CanvasLayer/Bottom_Dashboard/PanelContainer/HBoxContainer/Middle/Inventory_Menu

@onready var seed_picker = $CanvasLayer/SeedPicker
@onready var produce_picker = $CanvasLayer/ProducePicker
@onready var structure_picker: Control = get_node_or_null("CanvasLayer/StructurePicker")

@onready var pause_overlay: ColorRect = $CanvasLayer/Pause_Overlay
@onready var pause_menu: Control = $CanvasLayer/Pause_Overlay
@onready var btn_resume: Button = $CanvasLayer/Pause_Overlay/CenterContainer/PanelContainer/VBoxContainer/Resume
@onready var btn_save: Button = $CanvasLayer/Pause_Overlay/CenterContainer/PanelContainer/VBoxContainer/Save_Game
@onready var btn_load: Button = $CanvasLayer/Pause_Overlay/CenterContainer/PanelContainer/VBoxContainer/Load_Game
@onready var btn_settings: Button = $CanvasLayer/Pause_Overlay/CenterContainer/PanelContainer/VBoxContainer/Settings
@onready var btn_hotkeys: Button = $CanvasLayer/Pause_Overlay/CenterContainer/PanelContainer/VBoxContainer/Hotkeys
@onready var btn_main_menu: Button = $CanvasLayer/Pause_Overlay/CenterContainer/PanelContainer/VBoxContainer/Main_Menu
@onready var btn_exit_game: Button = $CanvasLayer/Pause_Overlay/CenterContainer/PanelContainer/VBoxContainer/Exit_Game

@onready var undo_button: Button = $CanvasLayer/Bottom_Dashboard/PanelContainer/HBoxContainer/Undo_Button

var save_dialog: ConfirmationDialog
var save_input: LineEdit
var leave_confirm_dialog: ConfirmationDialog
var _pending_leave_action: String = ""
var load_dialog: ConfirmationDialog
var load_list: ItemList
var hotkeys_dialog: AcceptDialog
var settings_dialog: AcceptDialog
var fullscreen_toggle: CheckButton

var pause_main_vbox: VBoxContainer
var pause_audio_scroll: ScrollContainer
var pause_graphics_scroll: ScrollContainer
var pause_gameplay_scroll: ScrollContainer

var is_rebinding: bool = false
var action_to_rebind: String = ""
var rebind_btn_ref: Button = null


func is_blocking_ui_open() -> bool:
	var seed_picker_node = get_tree().get_first_node_in_group("seed_picker")
	if seed_picker_node and seed_picker_node.visible:
		return true
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_sidebar_docks()
		_layout_edge_tab_strips()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)

	# Sleep ends the day on the map: runs the night action queue, then advance_turn() inside trigger_sleep().
	var btn_sleep := get_node_or_null("CanvasLayer/Bottom_Dashboard/PanelContainer/HBoxContainer/Sleep_Button") as Button
	if btn_sleep:
		btn_sleep.pressed.connect(func():
			var map: Node = get_tree().get_first_node_in_group("map") as Node
			if map and map.has_method("trigger_sleep"):
				map.trigger_sleep()
		)
		if HudIcons.apply_button_icon(btn_sleep, "sleep", "", SLEEP_ICON_MAX):
			btn_sleep.custom_minimum_size = Vector2(116, BOTTOM_PANEL_H - 14.0)
			btn_sleep.tooltip_text = "Sleep / Next Turn (Space)"
			_compact_sleep_button_style(btn_sleep, 3.0)

	# --- LOAD INFO WINDOW (shared: Codex, Upgrades, Additives) ---
	var InfoWindowScene = load("res://scenes/info_window.tscn")
	if InfoWindowScene:
		codex_window = InfoWindowScene.instantiate()
		$CanvasLayer.add_child(codex_window)
		codex_window.hide()

		var codex_dragger = PanelDragger.new(codex_window)
		codex_dragger.drag_ended.connect(func(p): _organize_docks(p))
		codex_window.add_child(codex_dragger)
		dockable_panels.append(codex_window)

		var codex_resizer = PanelResizer.new(codex_window)
		codex_resizer.resize_ended.connect(func(node): _organize_docks(node))
		codex_window.add_child(codex_resizer)

	var old_info_btn = get_node_or_null("CanvasLayer/Bottom_Dashboard/PanelContainer/HBoxContainer/Middle/Info_Menu")
	if old_info_btn:
		old_info_btn.queue_free()
	_setup_dialogs()
	_setup_actions_menu()
	_setup_build_menu()
	_setup_menu(
		lenses_menu,
		["Standard View", "Hydration Lens", "Nutrient Lens", "Growth Lens", "Design View", "Guild Vision"],
		_on_lens_pressed
	)
	var lenses_popup = lenses_menu.get_popup()
	lenses_popup.add_separator("Data")
	lenses_popup.add_item("Soil Data View")
	lenses_popup.set_item_metadata(lenses_popup.item_count - 1, "soil_data")
	lenses_popup.add_item("Plant Data View")
	lenses_popup.set_item_metadata(lenses_popup.item_count - 1, "plant_data")
	lenses_popup.add_separator("Abstract")
	lenses_popup.add_item("Energy Vision")
	lenses_popup.set_item_metadata(lenses_popup.item_count - 1, "energy")
	_setup_menu(
		inventory_menu,
		["Seeds", "Produce", "Additives", "Upgrades"],
		_on_inventory_pressed
	)

	seed_picker.seed_chosen.connect(func(seed_id: String): action_selected.emit("plant:" + seed_id))
	produce_picker.action_chosen.connect(func(act, key): produce_action_requested.emit(act, key))

	btn_resume.pressed.connect(_toggle_pause)
	btn_save.pressed.connect(_on_save_pressed)
	btn_load.pressed.connect(_on_load_pressed)
	btn_settings.pressed.connect(func(): settings_dialog.popup_centered())
	btn_hotkeys.pressed.connect(func(): hotkeys_dialog.popup_centered())
	btn_main_menu.pressed.connect(func(): _request_leave_game("main_menu"))
	btn_exit_game.pressed.connect(func(): _request_leave_game("exit"))

	var undo_parent = undo_button.get_parent()
	var undo_idx = undo_button.get_index()
	undo_parent.remove_child(undo_button)

	var stack_vbox = VBoxContainer.new()
	stack_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	stack_vbox.add_theme_constant_override("separation", 4)

	var redo_button = Button.new()
	redo_button.text = "↷ Redo"
	redo_button.add_theme_font_size_override("font_size", 14)
	redo_button.custom_minimum_size = Vector2(80, 38)
	redo_button.pressed.connect(func(): redo_pressed.emit())

	undo_button.text = "↶ Undo"
	undo_button.add_theme_font_size_override("font_size", 14)
	undo_button.custom_minimum_size = Vector2(80, 38)
	undo_button.pressed.connect(func(): undo_pressed.emit())

	stack_vbox.add_child(redo_button)
	stack_vbox.add_child(undo_button)
	undo_parent.add_child(stack_vbox)
	undo_parent.move_child(stack_vbox, undo_idx)

	# --- SETUP RADIO UI ---
	_setup_radio_ui()

	_setup_status_strip()
	_setup_political_metrics_bar()
	_setup_sidebar_docks()

	_setup_info_dock()
	_setup_weather_dock()
	_setup_calendar_dock()

	_setup_inspector_ui()

	_setup_minimap_ui()

	_setup_queue_ui()

	_inject_settings_into_pause_menu()

	modal_dimmer.process_mode = Node.PROCESS_MODE_ALWAYS
	almanac_window.process_mode = Node.PROCESS_MODE_ALWAYS
	almanac_close_button.process_mode = Node.PROCESS_MODE_ALWAYS
	almanac_close_button.pressed.connect(_on_almanac_close_pressed)
	_setup_almanac_title_icon()

	# Wire up draggable Window title-bar close buttons and custom body dragging
	if almanac_window:
		almanac_window.close_requested.connect(close_almanac)
		var drag_alma := PanelDragger.new(almanac_window)
		drag_alma.drag_ended.connect(func(p): _organize_docks(p))
		almanac_window.add_child(drag_alma)

	var hbox = $CanvasLayer/Bottom_Dashboard/PanelContainer/HBoxContainer/Middle
	if is_instance_valid(hbox):
		var is_story = not MetaManager.dev_mode

		# --- ADDITIVES MENU ---
		if not is_story:
			var amend_menu = MenuButton.new()
			amend_menu.text = "Additives"
			amend_menu.flat = false
			hbox.add_child(amend_menu)

			var a_popup = amend_menu.get_popup()
			a_popup.add_item("Bone Meal (£10)")
			a_popup.set_item_metadata(0, "additive:bone_meal")
			a_popup.add_item("Wood Ash (£5)")
			a_popup.set_item_metadata(1, "additive:wood_ash")
			a_popup.add_item("Compost (£15)")
			a_popup.set_item_metadata(2, "additive:compost")
			a_popup.add_item("Biochar (£20)")
			a_popup.set_item_metadata(3, "additive:biochar")
			a_popup.id_pressed.connect(func(pressed_id: int): _on_custom_menu_pressed(pressed_id, amend_menu))

		# --- UNIFIED INFO MENU ---
		var info_menu = MenuButton.new()
		info_menu.text = "Info"
		info_menu.flat = false
		hbox.add_child(info_menu)

		var info_popup = info_menu.get_popup()
		info_popup.add_item("Almanac")
		info_popup.add_item("Plant Codex")
		info_popup.add_item("Ecology Scanner")
		info_popup.add_separator()
		info_popup.add_item("Toggle Farm Hands")
		info_popup.add_item("Toggle Weather")
		info_popup.add_item("Toggle Calendar")
		info_popup.add_item("Toggle Dashboard")
		info_popup.add_item("Toggle Tile Inspector")

		if MetaManager.dev_mode:
			info_popup.add_item("Toggle Dev Console")

		info_popup.id_pressed.connect(func(menu_id: int):
			var idx := info_popup.get_item_index(menu_id)
			if idx < 0:
				return
			var txt := info_popup.get_item_text(idx)
			match txt:
				"Almanac":
					_open_almanac_vault()
				"Plant Codex":
					if is_instance_valid(codex_window):
						if codex_window.visible:
							codex_window.hide()
						else:
							_clamp_node_to_screen(codex_window)
							var pd := preload("res://data/data_plants.gd")
							codex_window.load_data("Permaculture Codex", pd.get_all_codex_data())
							if codex_window.has_method("set_title_icon"):
								codex_window.set_title_icon(HudIcons.get_icon("plant_codex", HudIcons.TITLE_ICON_PX))
							codex_window.show()
							_raise_hud_chrome()
				"Ecology Scanner":
					_toggle_sidebar_panel_with_focus(minimap_panel, UISidebarDock.DockSide.RIGHT)
				"Toggle Farm Hands":
					_toggle_sidebar_panel_with_focus(workers_window, UISidebarDock.DockSide.LEFT)
				"Toggle Weather":
					_toggle_sidebar_panel_with_focus(weather_dock, UISidebarDock.DockSide.RIGHT)
				"Toggle Calendar":
					_toggle_sidebar_panel_with_focus(calendar_dock, UISidebarDock.DockSide.RIGHT)
				"Toggle Dashboard":
					_toggle_sidebar_panel_with_focus(info_dock_panel, UISidebarDock.DockSide.RIGHT)
				"Toggle Tile Inspector":
					_toggle_sidebar_panel_with_focus(inspector_panel, UISidebarDock.DockSide.RIGHT)
				"Toggle Dev Console":
					_toggle_sidebar_panel_with_focus(dev_panel, UISidebarDock.DockSide.LEFT)
		)
		_apply_info_menu_icons(info_popup)

		# --- SYSTEM MENU (Wormfood roguelike end-run only) ---
		if FarmDataManager.active_campaign_id == "wormfood":
			var sys_menu = MenuButton.new()
			sys_menu.text = "System"
			sys_menu.flat = false
			hbox.add_child(sys_menu)
			var s_popup = sys_menu.get_popup()
			s_popup.add_item("Pass On (End Run)")
			s_popup.set_item_metadata(0, "die")
			s_popup.id_pressed.connect(func(pressed_id: int):
				var idx := s_popup.get_item_index(pressed_id)
				if idx < 0:
					return
				var req = s_popup.get_item_metadata(idx)
				if str(req) == "die":
					var map_node := get_parent()
					if map_node and map_node.has_method("_trigger_reincarnation"):
						map_node._trigger_reincarnation()
			)

	# Strip focus mode from all buttons so they don't eat the Spacebar input
	var all_nodes = find_children("*", "Button", true, false)
	for node in all_nodes:
		if node is Button:
			node.focus_mode = Control.FOCUS_NONE

	# --- LIVE DEV CONSOLE ---
	if MetaManager.dev_mode:
		dev_panel = PanelContainer.new()
		dev_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		dev_panel.offset_left = 10
		dev_panel.offset_top = 10
		dev_panel.mouse_filter = Control.MOUSE_FILTER_PASS # Allow clicks to pass through to the button

		var dev_style = StyleBoxFlat.new()
		dev_style.bg_color = Color(0, 0, 0, 0.6)
		dev_panel.add_theme_stylebox_override("panel", dev_style)

		# --- SCROLL CONTAINER ---
		var dev_scroll = ScrollContainer.new()
		dev_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		dev_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		dev_scroll.custom_minimum_size = Vector2(250, 200)

		var dev_vbox = VBoxContainer.new()
		dev_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dev_vbox.add_theme_constant_override("separation", 5)

		dev_scroll.add_child(dev_vbox)
		dev_panel.add_child(dev_scroll)

		dev_console = RichTextLabel.new()
		dev_console.custom_minimum_size = Vector2(250, 150)
		dev_console.bbcode_enabled = true
		dev_console.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dev_console.add_theme_font_size_override("normal_font_size", 12)
		dev_vbox.add_child(dev_console)

		# --- INJECT SPREADSHEET BUTTON ---
		var btn_sheet = Button.new()
		btn_sheet.text = "Open Data Spreadsheet"
		btn_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
		dev_vbox.add_child(btn_sheet)

		var sheet_panel = preload("res://scripts/dev_spreadsheet.gd").new()
		$CanvasLayer.add_child(sheet_panel)
		btn_sheet.pressed.connect(func(): sheet_panel.show())

		var close_dev = Button.new()
		close_dev.text = "×"
		close_dev.flat = true
		close_dev.focus_mode = Control.FOCUS_NONE
		close_dev.size_flags_horizontal = Control.SIZE_SHRINK_END
		close_dev.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		close_dev.add_theme_color_override("font_hover_color", Color(0.9, 0.2, 0.2))
		close_dev.pressed.connect(func(): dev_panel.hide())
		dev_vbox.add_child(close_dev)
		dev_vbox.move_child(close_dev, 0)

		dev_panel.custom_minimum_size = Vector2(260, 220)

	# --- DESIGN VIEW & NESTED CONTEXT MENU ---
	cell_context_menu = PopupMenu.new()
	cell_context_menu.name = "CellContextMenu"
	cell_context_menu.add_theme_font_size_override("font_size", 18)

	var popup_style = StyleBoxFlat.new()
	popup_style.bg_color = Color(0.1, 0.1, 0.12, 0.98)
	popup_style.content_margin_left = 15
	popup_style.content_margin_right = 15
	popup_style.content_margin_top = 10
	popup_style.content_margin_bottom = 10
	cell_context_menu.add_theme_stylebox_override("panel", popup_style)

	var menu_annotate = PopupMenu.new()
	menu_annotate.name = "AnnotateMenu"
	menu_annotate.add_theme_font_size_override("font_size", 16)
	menu_annotate.add_theme_stylebox_override("panel", popup_style)
	menu_annotate.add_item("Add Custom Note", 100)
	menu_annotate.add_separator()
	menu_annotate.add_item("Mark: Sun Trap", 101)
	menu_annotate.add_item("Mark: Frost Pocket", 102)
	menu_annotate.add_item("Mark: Waterlogged", 103)
	menu_annotate.add_separator()
	menu_annotate.add_item("Clear Annotations", 104)
	cell_context_menu.add_child(menu_annotate)

	var menu_action = PopupMenu.new()
	menu_action.name = "ActionMenu"
	menu_action.add_theme_font_size_override("font_size", 16)
	menu_action.add_theme_stylebox_override("panel", popup_style)
	menu_action.add_item("Rotovator", 200)
	menu_action.add_item("Scythe", 201)
	menu_action.add_item("Uproot", 202)
	menu_action.add_separator()
	menu_action.add_item("Plant Seed...", 203)
	menu_action.add_item("Build Menu...", 204)
	menu_action.add_item("Demolish", 205)
	cell_context_menu.add_child(menu_action)

	cell_context_menu.add_submenu_item("Annotate", "AnnotateMenu", 0)
	cell_context_menu.add_submenu_item("Action", "ActionMenu", 1)
	cell_context_menu.add_separator()
	cell_context_menu.add_item("Deep Info", 2)

	$CanvasLayer.add_child(cell_context_menu)
	cell_context_menu.id_pressed.connect(_on_context_menu_pressed)
	menu_annotate.id_pressed.connect(_on_context_menu_pressed)
	menu_action.id_pressed.connect(_on_context_menu_pressed)

	note_dialog = AcceptDialog.new()
	note_dialog.title = "Annotate Cell"
	note_dialog.dialog_hide_on_ok = true
	note_input = TextEdit.new()
	note_input.custom_minimum_size = Vector2(250, 100)
	note_input.placeholder_text = "Enter your observation or plan here..."
	note_dialog.add_child(note_input)
	$CanvasLayer.add_child(note_dialog)
	note_dialog.confirmed.connect(_on_note_confirmed)

	# --- DESIGN TOOLBAR ---
	design_toolbar = PanelContainer.new()
	# Anchor it to the middle-left of the screen
	design_toolbar.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	# Pad it 20 pixels from the left edge, and shift it up slightly so it is perfectly centred
	design_toolbar.position = Vector2(20, -180)
	var dt_style = StyleBoxFlat.new()
	dt_style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	dt_style.set_corner_radius_all(12)
	dt_style.set_border_width_all(2)
	dt_style.border_color = Color(0.4, 0.5, 0.6)
	design_toolbar.add_theme_stylebox_override("panel", dt_style)

	var dt_margin = MarginContainer.new()
	dt_margin.add_theme_constant_override("margin_left", 15)
	dt_margin.add_theme_constant_override("margin_right", 15)
	dt_margin.add_theme_constant_override("margin_top", 15)
	dt_margin.add_theme_constant_override("margin_bottom", 15)

	# Change from HBox to VBox so the tools stack vertically
	var dt_vbox = VBoxContainer.new()
	dt_vbox.add_theme_constant_override("separation", 15)

	var tools = ["Pen", "Rect", "Circle", "Arrow", "Eraser"]
	for t in tools:
		var tool_id: String = t.to_lower()
		var btn = Button.new()
		btn.text = t
		btn.pressed.connect(func():
			var map = get_tree().get_first_node_in_group("map")
			if map:
				map.design_tool = tool_id
		)
		dt_vbox.add_child(btn)

	var thick_vbox = VBoxContainer.new()
	var thick_lbl = Label.new()
	thick_lbl.text = "Thickness"
	thick_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thick_lbl.add_theme_font_size_override("font_size", 12)
	thick_vbox.add_child(thick_lbl)

	var thick_slider = HSlider.new()
	thick_slider.custom_minimum_size = Vector2(80, 0)
	thick_slider.min_value = 2.0
	thick_slider.max_value = 24.0
	thick_slider.value = 6.0
	thick_slider.value_changed.connect(func(v):
		var map = get_tree().get_first_node_in_group("map")
		if map:
			map.design_thickness = v
	)
	thick_vbox.add_child(thick_slider)
	dt_vbox.add_child(thick_vbox)

	var clear_btn = Button.new()
	clear_btn.text = "Erase All"
	clear_btn.add_theme_color_override("font_color", Color("ef5350"))
	clear_btn.pressed.connect(func(): clear_design_dialog.popup_centered())
	dt_vbox.add_child(clear_btn)

	dt_margin.add_child(dt_vbox)
	design_toolbar.add_child(dt_margin)
	$CanvasLayer.add_child(design_toolbar)
	design_toolbar.hide()

	clear_design_dialog = ConfirmationDialog.new()
	clear_design_dialog.title = "Are you sure?"
	clear_design_dialog.dialog_text = "This will permanently clear your entire screen of notes and scribbles."
	clear_design_dialog.confirmed.connect(func():
		FarmDataManager.scribbles.clear()
		FarmDataManager.cell_notes.clear()
		var map = get_tree().get_first_node_in_group("map")
		if map:
			map.queue_redraw()
			if map.get("design_overlay") and map.design_overlay:
				map.design_overlay.queue_redraw()
	)
	$CanvasLayer.add_child(clear_design_dialog)

	_setup_workers_ui()

	call_deferred("_mount_panels_into_sidebars")
	call_deferred("_layout_sidebar_docks")
	call_deferred("_raise_hud_chrome")
	call_deferred("_wire_toolbar_menu_popups")
	_setup_quick_wheel()
	call_deferred("_apply_panel_breathing_room")

	# Bottom toolbar sizing (draw order handled by _raise_hud_chrome).
	var bottom_dash = get_node_or_null("CanvasLayer/Bottom_Dashboard")
	if bottom_dash:
		bottom_dash.visible = true
		bottom_dash.custom_minimum_size = Vector2(0, maxf(bottom_dash.custom_minimum_size.y, BOTTOM_TOOLBAR_H))
		bottom_dash.offset_top = -BOTTOM_TOOLBAR_H
		var bottom_panel = bottom_dash.get_node_or_null("PanelContainer") as PanelContainer
		if bottom_panel:
			bottom_panel.custom_minimum_size = Vector2(0, maxf(bottom_panel.custom_minimum_size.y, BOTTOM_PANEL_H))

	# --- Settings panels in Pause Menu (same scripts as main menu) ---
	pause_main_vbox = btn_main_menu.get_parent() as VBoxContainer
	if pause_main_vbox:
		_setup_pause_settings_panels()
		var mm_idx := btn_main_menu.get_index()
		_add_pause_settings_button(
			pause_main_vbox, "Sound Settings", pause_audio_scroll, mm_idx
		)
		_add_pause_settings_button(
			pause_main_vbox, "Graphics & UI", pause_graphics_scroll, mm_idx
		)
		_add_pause_settings_button(
			pause_main_vbox, "Gameplay Settings", pause_gameplay_scroll, mm_idx
		)


func _process(_delta: float) -> void:
	if is_instance_valid(dev_console):
		var fps = Engine.get_frames_per_second()
		var mem := int(OS.get_static_memory_usage() / 1024.0 / 1024.0)
		var map = get_parent()

		var txt = "[color=#00ff00][b]DEV MODE ACTIVE[/b][/color]\n"
		txt += "FPS: %d | Mem: %d MB\n" % [int(fps), mem]
		if map:
			txt += "Date: %s | Season: %s\n" % [
				FarmDataManager.format_calendar_date(),
				FarmDataManager.current_season,
			]
			txt += "Entities in Queue: %d\n" % FarmDataManager.action_queue.size()
			var m_pos = map.local_to_map(map.get_local_mouse_position())
			txt += "Mouse Map Pos: (%d, %d)\n" % [m_pos.x, m_pos.y]

		dev_console.text = txt

	if is_instance_valid(workers_window) and workers_window.visible:
		if FarmDataManager.workers.size() != _workers_display_count:
			refresh_workers_ui()


func _setup_workers_ui() -> void:
	workers_window = PanelContainer.new()
	workers_window.name = "WorkersPanel"
	workers_window.custom_minimum_size = Vector2(280, 270)

	# Anchor to Top-Left, just below the Top Bar
	workers_window.set_anchors_preset(Control.PRESET_TOP_LEFT)
	workers_window.position = Vector2(20, 60)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.5, 0.6)
	style.set_corner_radius_all(6)
	workers_window.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.name = "WorkerMargin"
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)

	# --- SCROLL CONTAINER ---
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(260, 250)

	var vbox = VBoxContainer.new()
	var close_workers = Button.new()
	close_workers.name = "WorkerCloseButton"
	close_workers.text = "×"
	close_workers.flat = true
	close_workers.focus_mode = Control.FOCUS_NONE
	close_workers.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_workers.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	close_workers.add_theme_color_override("font_hover_color", Color(0.9, 0.2, 0.2))
	close_workers.pressed.connect(func(): workers_window.hide())
	vbox.add_child(close_workers)

	vbox.name = "WorkerList"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)

	scroll.add_child(vbox)
	margin.add_child(scroll)

	workers_window.add_child(margin)

	if not FarmDataManager.data_reset.is_connected(_on_workers_data_reset):
		FarmDataManager.data_reset.connect(_on_workers_data_reset)
	if not FarmDataManager.energy_changed.is_connected(_on_farm_energy_changed):
		FarmDataManager.energy_changed.connect(_on_farm_energy_changed)

	refresh_workers_ui()


func _on_workers_data_reset() -> void:
	refresh_workers_ui()


func _on_farm_energy_changed(_new_val: int, _max_val: int) -> void:
	if is_instance_valid(workers_window) and workers_window.visible:
		refresh_workers_ui()


func refresh_workers_ui() -> void:
	if not is_instance_valid(workers_window):
		return
	var list = workers_window.find_child("WorkerList", true, false) as VBoxContainer
	if not list:
		return
	for c in list.get_children():
		if c.name == "WorkerCloseButton":
			continue
		c.queue_free()

	for i in range(FarmDataManager.workers.size()):
		var w: Dictionary = FarmDataManager.workers[i]
		var hbox = HBoxContainer.new()

		var icon_btn = Button.new()
		icon_btn.custom_minimum_size = Vector2(30, 30)
		var style = StyleBoxFlat.new()
		var hex_col: String = str(w.get("color", "ffffff"))
		if not hex_col.begins_with("#"):
			hex_col = "#" + hex_col
		style.bg_color = Color(hex_col)
		if FarmDataManager.active_worker_id == str(w.get("id", "")):
			style.border_width_left = 3
			style.border_width_right = 3
			style.border_width_top = 3
			style.border_width_bottom = 3
			style.border_color = Color(1.0, 0.8, 0.2)
		icon_btn.add_theme_stylebox_override("normal", style)
		icon_btn.add_theme_stylebox_override("hover", style)
		var wid: String = str(w.get("id", ""))
		icon_btn.pressed.connect(func():
			FarmDataManager.active_worker_id = wid
			refresh_workers_ui()
			var map_node: Node = get_tree().get_first_node_in_group("map") as Node
			if map_node and map_node.has_method("_sync_hud_status"):
				map_node._sync_hud_status()
		)
		hbox.add_child(icon_btn)

		var details = VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_lbl = Label.new()
		name_lbl.text = w.get("name", "Unknown") + " (" + str(w.get("energy", 0)) + "/" + str(w.get("max_energy", 0)) + ")"
		name_lbl.add_theme_font_size_override("font_size", 14)

		var stamina_bar := ProgressBar.new()
		stamina_bar.max_value = maxf(1.0, float(w.get("max_energy", 1)))
		stamina_bar.value = float(w.get("energy", 0))
		stamina_bar.show_percentage = false
		stamina_bar.custom_minimum_size = Vector2(120, 16)
		stamina_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var fill_style = StyleBoxFlat.new()
		if float(w.get("energy", 0)) <= 2.0:
			fill_style.bg_color = Color("e53935") # Red for low energy
		else:
			fill_style.bg_color = Color("43a047") # Green
		stamina_bar.add_theme_stylebox_override("fill", fill_style)

		var role_btn = OptionButton.new()
		role_btn.add_item("Active")
		role_btn.add_item("Maintenance")
		role_btn.add_item("Resting")

		var current_role: String = str(w.get("role", "active"))
		if current_role == "active":
			role_btn.select(0)
		elif current_role == "maintenance":
			role_btn.select(1)
		else:
			role_btn.select(2)

		var w_idx: int = i
		role_btn.item_selected.connect(func(idx: int):
			var new_role := "active"
			if idx == 1:
				new_role = "maintenance"
			elif idx == 2:
				new_role = "resting"
			if w_idx >= 0 and w_idx < FarmDataManager.workers.size():
				FarmDataManager.workers[w_idx]["role"] = new_role
		)

		details.add_child(name_lbl)
		details.add_child(stamina_bar)
		details.add_child(role_btn)
		hbox.add_child(details)
		list.add_child(hbox)

	_workers_display_count = FarmDataManager.workers.size()


func _setup_dialogs() -> void:
	$CanvasLayer.layer = 100

	save_dialog = ConfirmationDialog.new()
	save_dialog.title = "Save Game"
	save_dialog.dialog_text = "Enter a name for your farm:"
	save_dialog.process_mode = Node.PROCESS_MODE_ALWAYS

	save_input = LineEdit.new()
	save_input.placeholder_text = "e.g. spring_valley"
	save_dialog.add_child(save_input)
	$CanvasLayer.add_child(save_dialog)
	save_dialog.confirmed.connect(_execute_save)

	leave_confirm_dialog = ConfirmationDialog.new()
	leave_confirm_dialog.title = "Unsaved Progress"
	leave_confirm_dialog.dialog_text = (
		"You have unsaved progress.\n\n"
		+ "Leave anyway? Your current farm will be lost unless you save first."
	)
	leave_confirm_dialog.ok_button_text = "Leave Anyway"
	leave_confirm_dialog.cancel_button_text = "Stay in Game"
	leave_confirm_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	leave_confirm_dialog.confirmed.connect(_confirm_leave_game)
	$CanvasLayer.add_child(leave_confirm_dialog)

	load_dialog = ConfirmationDialog.new()
	load_dialog.title = "Load Game"
	load_dialog.process_mode = Node.PROCESS_MODE_ALWAYS

	load_list = ItemList.new()
	load_list.custom_minimum_size = Vector2(250, 150)
	load_dialog.add_child(load_list)
	$CanvasLayer.add_child(load_dialog)
	load_dialog.confirmed.connect(_execute_load)
	load_list.item_activated.connect(
		func(idx: int) -> void:
			load_list.select(idx)
			_execute_load()
			load_dialog.hide()
	)

	# Generate Hotkeys Dialog
	hotkeys_dialog = AcceptDialog.new()
	hotkeys_dialog.title = "Controls & Hotkeys"
	hotkeys_dialog.process_mode = Node.PROCESS_MODE_ALWAYS

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, 250)
	var hk_vbox := VBoxContainer.new()
	hk_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hk_vbox)

	for action in get_node("/root/SaveManager").hotkeys.keys():
		var hbox := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = action
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var btn := Button.new()
		btn.text = OS.get_keycode_string(get_node("/root/SaveManager").hotkeys[action])
		btn.custom_minimum_size = Vector2(120, 0)

		btn.pressed.connect(func(): _start_rebind(action, btn))

		hbox.add_child(lbl)
		hbox.add_child(btn)
		hk_vbox.add_child(hbox)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	margin.add_child(scroll)

	hotkeys_dialog.add_child(margin)
	$CanvasLayer.add_child(hotkeys_dialog)

	# Generate Settings Dialog
	settings_dialog = AcceptDialog.new()
	settings_dialog.title = "Settings"
	settings_dialog.process_mode = Node.PROCESS_MODE_ALWAYS

	var s_vbox := VBoxContainer.new()
	s_vbox.custom_minimum_size = Vector2(250, 100)

	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.text = "Enable Fullscreen"
	fullscreen_toggle.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)

	# --- UI SCALE SLIDER ---
	var scale_hbox := HBoxContainer.new()
	var scale_lbl := Label.new()
	scale_lbl.text = "UI Scale: %.2fx" % get_tree().root.content_scale_factor
	scale_lbl.custom_minimum_size = Vector2(100, 0)

	var scale_slider := HSlider.new()
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_slider.min_value = 0.75
	scale_slider.max_value = 3.0
	scale_slider.step = 0.05
	scale_slider.value = get_tree().root.content_scale_factor

	# Avoid slider feedback jitter: only apply scale when drag finishes.
	scale_slider.value_changed.connect(func(val: float) -> void:
		scale_lbl.text = "UI Scale: %.2fx" % val
	)

	scale_slider.drag_ended.connect(func(value_changed: bool) -> void:
		if not value_changed:
			return
		var final_scale := float(scale_slider.value)
		get_tree().root.content_scale_factor = final_scale
		scale_lbl.text = "UI Scale: %.2fx" % final_scale
	)

	scale_hbox.add_child(scale_lbl)
	scale_hbox.add_child(scale_slider)
	# -----------------------

	s_vbox.add_child(fullscreen_toggle)
	s_vbox.add_child(scale_hbox)
	settings_dialog.add_child(s_vbox)
	$CanvasLayer.add_child(settings_dialog)


func _on_fullscreen_toggled(is_pressed: bool) -> void:
	if is_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _execute_save() -> void:
	if save_input.text.strip_edges() != "":
		save_requested.emit(save_input.text)
		btn_save.text = "Saved!"
		await get_tree().create_timer(1.5, true).timeout
		btn_save.text = "Save Game"


func _execute_load() -> void:
	var selected := load_list.get_selected_items()
	if selected.size() > 0:
		var save_name := load_list.get_item_text(selected[0])
		if save_name != "No saves found":
			load_requested.emit(save_name)
			_toggle_pause()


func _start_rebind(action: String, btn: Button) -> void:
	is_rebinding = true
	action_to_rebind = action
	rebind_btn_ref = btn
	btn.text = "Press any key..."
	btn.release_focus()


func _input(event: InputEvent) -> void:
	# --- GLOBAL BRING-TO-FRONT (Fixes clicks swallowed by child nodes) ---
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hovered = get_viewport().gui_get_hovered_control()
		if is_instance_valid(hovered):
			var curr: Node = hovered
			while is_instance_valid(curr) and curr != $CanvasLayer and curr != get_tree().root:
				if curr is AcceptDialog or curr is ConfirmationDialog:
					break
				if (
					curr in dockable_panels
					or curr.name == "Bottom_Dashboard"
					or curr.name == "AlmanacVaultOverlay"
					or curr == almanac_window
					or curr is UISidebarDock
					or curr is UISidebarWidget
				):
					var parent = curr.get_parent()
					if parent:
						parent.move_child(curr, -1)
					break
				curr = curr.get_parent()

	if is_rebinding and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()

		if event.keycode == KEY_ESCAPE:
			is_rebinding = false
			if rebind_btn_ref:
				rebind_btn_ref.text = OS.get_keycode_string(get_node("/root/SaveManager").hotkeys[action_to_rebind])
			return

		get_node("/root/SaveManager").hotkeys[action_to_rebind] = event.keycode
		if rebind_btn_ref:
			rebind_btn_ref.text = OS.get_keycode_string(event.keycode)
		get_node("/root/SaveManager").save_settings()
		is_rebinding = false


func _unhandled_input(event: InputEvent) -> void:
	var map_node: Node = get_tree().get_first_node_in_group("map") as Node
	if map_node and map_node.get("almanac_open"):
		return
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()


func _on_almanac_close_pressed() -> void:
	var map_node: Node = get_tree().get_first_node_in_group("map") as Node
	if map_node and map_node.has_method("close_almanac"):
		map_node.close_almanac()


func _compact_sleep_button_style(btn: Button, margin: float) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBox = btn.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			var dup: StyleBoxFlat = sb.duplicate()
			dup.content_margin_left = margin
			dup.content_margin_right = margin
			dup.content_margin_top = margin
			dup.content_margin_bottom = margin
			btn.add_theme_stylebox_override(state, dup)


func _apply_info_menu_icons(info_popup: PopupMenu) -> void:
	if info_popup == null:
		return
	for i in range(info_popup.item_count):
		match info_popup.get_item_text(i):
			"Almanac":
				HudIcons.apply_popup_icon(info_popup, i, "almanac")
			"Plant Codex":
				HudIcons.apply_popup_icon(info_popup, i, "plant_codex")
			"Ecology Scanner":
				HudIcons.apply_popup_icon(info_popup, i, "ecology_scanner")
			"Toggle Farm Hands":
				HudIcons.apply_popup_icon(info_popup, i, "farm_hands")
			"Toggle Tile Inspector":
				HudIcons.apply_popup_icon(info_popup, i, "tile_inspector")
			"Toggle Dev Console":
				HudIcons.apply_popup_icon(info_popup, i, "dev_console")


func _setup_almanac_title_icon() -> void:
	var title_row := almanac_window.get_node_or_null(
		"MarginContainer/VBoxContainer/TitleRow"
	) as HBoxContainer
	var tex := HudIcons.get_icon("almanac", HudIcons.TITLE_ICON_PX)
	if title_row == null or tex == null:
		return
	if title_row.get_node_or_null("Almanac_Title_Icon") != null:
		return
	var icon := TextureRect.new()
	icon.name = "Almanac_Title_Icon"
	icon.texture = tex
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(32, 32)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	title_row.add_child(icon)
	title_row.move_child(icon, 0)


func close_almanac() -> void:
	_on_almanac_close_pressed()


func _md_to_bbcode(md: String) -> String:
	# Minimal markdown -> BBCode: only handles **bold** pairs.
	var out := md
	var is_open_tag := true
	while out.find("**") != -1:
		if is_open_tag:
			out = out.replace("**", "[b]")
		else:
			out = out.replace("**", "[/b]")
		is_open_tag = not is_open_tag
	return out


func _open_almanac_vault() -> void:
	var screen_center := CenterContainer.new()
	screen_center.name = "AlmanacVaultOverlay"
	screen_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_center.mouse_filter = Control.MOUSE_FILTER_STOP
	MapScrollBlockerUtil.tag_control_tree(screen_center)
	screen_center.z_index = Z_MODAL_CONTENT
	$CanvasLayer.add_child(screen_center)
	_raise_hud_chrome()

	var vault_panel := PanelContainer.new()
	vault_panel.custom_minimum_size = Vector2(900, 600)
	screen_center.add_child(vault_panel)
	MapScrollBlockerUtil.tag_control_tree(vault_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.1, 0.98)
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color(0.35, 0.45, 0.55)
	vault_panel.add_theme_stylebox_override("panel", style)

	var main_hbox := HBoxContainer.new()
	vault_panel.add_child(main_hbox)

	# --- LEFT PANE: TABLE OF CONTENTS ---
	var toc_scroll := ScrollContainer.new()
	toc_scroll.custom_minimum_size = Vector2(280, 0)
	toc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toc_scroll.gui_input.connect(_forward_scroll_block_to_viewport)

	var toc_vbox := VBoxContainer.new()
	toc_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toc_vbox.add_theme_constant_override("separation", 5)
	
	var index_title := Label.new()
	index_title.text = "Vault Index"
	index_title.add_theme_font_size_override("font_size", 18)
	index_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toc_vbox.add_child(index_title)
	toc_vbox.add_child(HSeparator.new())
	
	# --- RIGHT PANE: PAGE READER ---
	var reader_margin := MarginContainer.new()
	reader_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reader_margin.add_theme_constant_override("margin_left", 20)
	reader_margin.add_theme_constant_override("margin_right", 20)
	reader_margin.add_theme_constant_override("margin_top", 20)
	
	var reader_text := RichTextLabel.new()
	reader_text.bbcode_enabled = true
	reader_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reader_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reader_text.scroll_active = true
	reader_text.gui_input.connect(_forward_scroll_block_to_viewport)
	reader_margin.add_child(reader_text)
	
	# --- DYNAMIC FILE SCANNER (Improved) ---
	var db: Dictionary = {}
	var path := "res://data/almanac/"
	var dir := DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".md"):
				# Support both "100_Title.md" and "100 Title.md"
				var delimiter = "_" if file_name.contains("_") else " "
				var parts = file_name.split(delimiter, true, 1)
				if parts.size() > 0 and parts[0].is_valid_int():
					var page_id = parts[0].to_int()
					var raw_title = file_name.get_basename().trim_prefix(str(parts[0]) + delimiter).replace("_", " ").replace("-", " ")
					var content = FileAccess.get_file_as_string(path + file_name)
					db[page_id] = {"title": raw_title, "content": content}
					print("✅ Almanac Loaded: ", page_id, " - ", raw_title)
			file_name = dir.get_next()
	else:
		print("❌ CRITICAL: Could not find Almanac folder at: ", ProjectSettings.globalize_path(path))
			
	# --- NAVIGATION LOGIC ---
	var load_page := func(page_id: int) -> void:
		if db.has(page_id):
			var page = db[page_id]
			reader_text.text = "[font_size=28][b]" + str(page["title"]) + "[/b][/font_size]\n"
			reader_text.text += "[color=#5c6bc0][font_size=14]Ref ID: " + str(page_id) + "[/font_size][/color]\n[line]\n"
			reader_text.text += _md_to_bbcode(str(page["content"]))
		else:
			reader_text.text = "[color=red]Error: Page " + str(page_id) + " not found.[/color]"
			
	# Wire up Godot BBCode links! (e.g. [url=101]Click Here[/url] inside the markdown files)
	reader_text.meta_clicked.connect(func(meta):
		var target_page = str(meta).to_int()
		if target_page > 0:
			load_page.call(target_page)
	)

	# Populate the Index Buttons, sorted numerically
	var page_keys := db.keys()
	page_keys.sort()
	for p_id in page_keys:
		var btn := Button.new()
		# Format as "100: Welcome"
		btn.text = str(p_id) + ": " + str(db[p_id].get("title", "Untitled"))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func(): load_page.call(int(p_id)))
		toc_vbox.add_child(btn)

	toc_scroll.add_child(toc_vbox)
	main_hbox.add_child(toc_scroll)
	main_hbox.add_child(VSeparator.new())
	main_hbox.add_child(reader_margin)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_btn.pressed.connect(func() -> void: screen_center.queue_free())
	main_hbox.add_child(close_btn)

	# Open to page 100 by default (if it exists)
	if db.has(100):
		load_page.call(100)
	elif page_keys.size() > 0:
		load_page.call(int(page_keys[0]))


func _forward_scroll_block_to_viewport(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [
			MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT,
			MOUSE_BUTTON_WHEEL_RIGHT,
		]:
			UIInputUtil.safe_set_input_handled(self)


func _toggle_pause() -> void:
	var is_paused := get_tree().paused
	get_tree().paused = not is_paused
	pause_overlay.visible = not is_paused
	if pause_overlay.visible:
		_show_pause_main_menu()


func _request_leave_game(action: String) -> void:
	_pending_leave_action = action
	var save_mgr: Node = get_node_or_null("/root/SaveManager")
	if save_mgr != null and save_mgr.has_method("has_unsaved_progress") and save_mgr.has_unsaved_progress():
		leave_confirm_dialog.popup_centered(Vector2(440, 170))
	else:
		_confirm_leave_game()


func _confirm_leave_game() -> void:
	var action := _pending_leave_action
	_pending_leave_action = ""
	get_tree().paused = false
	pause_overlay.visible = false
	match action:
		"main_menu":
			main_menu_requested.emit()
		"exit":
			get_tree().quit()
		_:
			pass


func _on_save_pressed() -> void:
	save_input.text = ""
	save_dialog.popup_centered(Vector2(350, 140))
	save_input.grab_focus()


func _on_load_pressed() -> void:
	load_list.clear()
	var saves: Array[String] = get_node("/root/SaveManager").get_saved_games()
	var ok_btn := load_dialog.get_ok_button()
	if saves.is_empty():
		load_list.add_item("No saves found")
		if ok_btn:
			ok_btn.disabled = true
	else:
		if ok_btn:
			ok_btn.disabled = false
		for s in saves:
			load_list.add_item(s)
		load_list.select(0)

	load_dialog.popup_centered(Vector2(350, 250))


func _setup_menu(menu: MenuButton, items: Array, callback: Callable) -> void:
	var popup := menu.get_popup()
	popup.clear()
	for i in range(items.size()):
		popup.add_item(items[i], i)
	popup.id_pressed.connect(
		func(id: int) -> void:
			callback.call(id, popup)
	)


func _setup_actions_menu() -> void:
	if not is_instance_valid(actions_menu):
		return
	_setup_menu(
		actions_menu,
		[
			"Rotovator", "Scythe", "Uproot", "Harvest", "Chop & Drop",
			"Dig Swale", "Build Mound", "Plant", "Water", "Compost Tea",
			"E-Tiller (1⚡)", "Hosepipe (1💧)",
		],
		_on_action_pressed
	)


func _setup_build_menu() -> void:
	if not is_instance_valid(build_menu):
		return
	var popup := build_menu.get_popup()
	popup.clear()
	var entries: Array = [
		["Duck House", "duck_house"],
		["Footbridge", "bridge"],
		["Polytunnel (£15)", "polytunnel"],
		["Compost Brewer (£40)", "compost_brewer"],
		["Honesty Box (£25)", "honesty_box"],
		["Pig House (£80)", "pig_house"],
		["Build Beehive (£80)", "beehive"],
		["Solar Panel (£100)", "solar_panel"],
		["Deep-Cycle Battery Array (£150)", "battery"],
		["Water Butt (£30)", "water_butt"],
	]
	if FarmDataManager.active_campaign_id == "automata":
		entries.append(["Build Auto-Sprinkler (£50)", "sprinkler"])
		entries.append(["Build Harvest Drone Hub (£150)", "drone_hub"])
		entries.append(["Build Smart Shade (£200)", "smart_shade"])
		entries.append(["Build Drone Pollinator (£300)", "drone_pollinator"])
	if FarmDataManager.active_campaign_id == "desert" and FarmDataManager.current_turn >= 15:
		entries.append(["Build Moisture Net (£75)", "moisture_net"])
	entries.append(["", ""])
	entries.append(["Build Path (£1)", "build_path"])
	entries.append(["Demolish Structure", "demolish"])
	for i in range(entries.size()):
		var label: String = str(entries[i][0])
		var meta: String = str(entries[i][1])
		if label == "":
			popup.add_separator("Maintenance")
			continue
		popup.add_item(label)
		popup.set_item_metadata(popup.item_count - 1, meta)
	if not popup.id_pressed.is_connected(_on_build_menu_pressed):
		popup.id_pressed.connect(_on_build_menu_pressed)


func refresh_build_menu() -> void:
	_setup_build_menu()


func _on_build_menu_pressed(id: int) -> void:
	var popup := build_menu.get_popup()
	var idx := popup.get_item_index(id)
	if idx < 0:
		return
	var meta: Variant = popup.get_item_metadata(idx)
	if meta == null:
		return
	var sid := str(meta)
	var map_node := get_tree().get_first_node_in_group("map") as Node
	if not map_node or not map_node.has_method("set_current_tool"):
		return
	if sid == "build_path":
		map_node.set_current_tool("build_path")
	elif sid == "demolish":
		map_node.set_current_tool("demolish")
	else:
		map_node.set_current_tool("build", "", sid)
	update_build_button_text(popup.get_item_text(idx))


func update_build_button_text(text: String) -> void:
	if is_instance_valid(build_menu):
		build_menu.text = "🏗️ Build: " + text


func reset_build_menu_button() -> void:
	if is_instance_valid(build_menu):
		build_menu.text = "🏗️ Build"


func sync_build_menu_from_tool(tool_name: String, structure_id: String) -> void:
	reset_build_menu_button()
	match tool_name:
		"build":
			if structure_id != "":
				update_build_button_text(_build_structure_menu_label(structure_id))
		"build_path":
			update_build_button_text("Build Path (£1)")
		"demolish":
			update_build_button_text("Demolish Structure")


func _build_structure_menu_label(structure_id: String) -> String:
	match structure_id:
		"duck_house":
			return "Duck House"
		"bridge":
			return "Footbridge"
		"polytunnel":
			return "Polytunnel (£15)"
		"honesty_box":
			return "Honesty Box (£25)"
		"pig_house":
			return "Pig House (£80)"
		"compost_brewer":
			return "Compost Brewer (£40)"
		"beehive":
			return "Beehive (£80)"
		"solar_panel":
			return "Solar Panel (£100)"
		"battery":
			return "Deep-Cycle Battery Array (£150)"
		"water_butt":
			return "Water Butt (£30)"
		"sprinkler":
			return "Auto-Sprinkler (£50)"
		"drone_hub":
			return "Harvest Drone Hub (£150)"
		"smart_shade":
			return "Smart Shade (£200)"
		"drone_pollinator":
			return "Drone Pollinator (£300)"
		"moisture_net":
			return "Moisture Net (£75)"
		_:
			return structure_id.capitalize().replace("_", " ")


func _on_custom_menu_pressed(id: int, menu_btn: MenuButton) -> void:
	var popup = menu_btn.get_popup()
	var idx = popup.get_item_index(id)
	if idx < 0:
		return
	var meta = popup.get_item_metadata(idx)
	if meta == null:
		return

	var action_name = str(meta)

	if action_name.begins_with("additive:"):
		var additive_id = action_name.split(":")[1]
		var map_node = get_parent()
		if map_node and map_node.has_method("set_current_tool"):
			map_node.set_current_tool("additive", additive_id)
			update_action_button_text(popup.get_item_text(idx))
		return

	if action_name != "":
		update_action_button_text(popup.get_item_text(idx))
		action_selected.emit(action_name)


func _on_action_pressed(id: int, popup: PopupMenu) -> void:
	var idx = popup.get_item_index(id)
	if idx < 0:
		return
	var meta = popup.get_item_metadata(idx)
	if meta != null and str(meta) != "":
		return
	var item_text = popup.get_item_text(idx)
	if item_text == "Plant":
		seed_picker.populate_and_show()
	elif item_text == "Build Structure":
		if structure_picker and structure_picker.has_method("populate_and_show"):
			structure_picker.populate_and_show()
	else:
		update_action_button_text(item_text)
		action_selected.emit(item_text)


func _on_lens_pressed(id: int, popup: PopupMenu) -> void:
	# Metadata overrides display text (e.g. soil_data / plant_data / energy).
	var idx = popup.get_item_index(id)
	if idx < 0:
		return
	var meta = popup.get_item_metadata(idx)
	if meta != null and str(meta) != "":
		lens_selected.emit(str(meta))
	else:
		lens_selected.emit(popup.get_item_text(idx))


func _on_inventory_pressed(id: int, popup: PopupMenu) -> void:
	var selection = popup.get_item_text(id)
	inventory_selected.emit(selection)

	if selection == "Upgrades":
		var data = preload("res://data/data_upgrades.gd").ENTRIES
		_clamp_node_to_screen(codex_window)
		codex_window.load_data("Meta Upgrades", data)
		if codex_window.has_method("set_title_icon"):
			codex_window.set_title_icon(null)
	elif selection == "Additives":
		var data = preload("res://data/data_additives.gd").ENTRIES
		_clamp_node_to_screen(codex_window)
		codex_window.load_data("Soil Additives", data)
		if codex_window.has_method("set_title_icon"):
			codex_window.set_title_icon(null)
	elif selection == "Seeds":
		seed_picker.populate_and_show()
	elif selection == "Produce":
		action_selected.emit("open_produce_menu")


func refresh_produce_ui(dict: Dictionary) -> void:
	produce_picker.populate_and_show(dict)


func update_action_button_text(text: String) -> void:
	if actions_menu:
		actions_menu.text = "Action: " + text


# --- RADIO FUNCTION ---
func _setup_radio_ui() -> void:
	var pause_vbox := $CanvasLayer/Pause_Overlay/CenterContainer/PanelContainer/VBoxContainer

	var sep := HSeparator.new()
	pause_vbox.add_child(sep)

	var radio_title := Label.new()
	radio_title.text = "--- RADIO ---"
	radio_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_vbox.add_child(radio_title)

	radio_label = Label.new()
	radio_label.text = "Radio Off"
	radio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	radio_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	pause_vbox.add_child(radio_label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var btn_class := Button.new()
	btn_class.text = "Classical"
	btn_class.pressed.connect(func(): RadioManager.load_station("Classical"))

	var btn_lofi := Button.new()
	btn_lofi.text = "Lo-Fi"
	btn_lofi.pressed.connect(func(): RadioManager.load_station("Lo-Fi"))

	var btn_r6 := Button.new()
	btn_r6.text = "Radio 6"
	btn_r6.pressed.connect(func(): RadioManager.load_station("Radio 6"))

	var btn_next := Button.new()
	btn_next.text = " ⏭ "
	btn_next.pressed.connect(func(): RadioManager.next_track())

	var btn_stop := Button.new()
	btn_stop.text = " ■ "
	btn_stop.pressed.connect(func(): RadioManager.stop())

	for btn in [btn_class, btn_lofi, btn_r6, btn_next, btn_stop]:
		hbox.add_child(btn)

	pause_vbox.add_child(hbox)

	if RadioManager.has_signal("track_changed"):
		RadioManager.track_changed.connect(func(text): radio_label.text = text)


func _setup_status_strip() -> void:
	weather_panel = PanelContainer.new()
	weather_panel.name = "StatusStrip"
	weather_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	weather_panel.custom_minimum_size = Vector2(0, 80)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.95)
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.3, 0.2)
	weather_panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)

	var hbox = HBoxContainer.new()

	# --- LEFT: WEATHER & SEASON ---
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	season_label = Label.new()
	season_label.text = FarmDataManager.format_calendar_date(1)
	season_label.add_theme_font_size_override("font_size", 16)
	season_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	left_vbox.add_child(season_label)

	weather_desc_label = Label.new()
	weather_desc_label.text = "Gentle rains. Perfect growing conditions."
	weather_desc_label.add_theme_font_size_override("font_size", 12)
	weather_desc_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9))
	left_vbox.add_child(weather_desc_label)

	hbox.add_child(left_vbox)

	# --- CENTER: ACTIVE TOOL ---
	active_tool_label = RichTextLabel.new()
	active_tool_label.bbcode_enabled = true
	active_tool_label.fit_content = true
	active_tool_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	active_tool_label.scroll_active = false
	active_tool_label.custom_minimum_size = Vector2(300, 0)
	active_tool_label.text = "[center]Equipped: Inspection Mode (Q)[/center]"
	active_tool_label.add_theme_font_size_override("font_size", 16)
	active_tool_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_tool_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(active_tool_label)

	# --- RIGHT: VITALS (Money, Turn) ---
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.alignment = BoxContainer.ALIGNMENT_END

	vitals_label = Label.new()
	vitals_label.text = "Money: £500 | Turn: 1"
	vitals_label.add_theme_font_size_override("font_size", 16)
	vitals_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vitals_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_vbox.add_child(vitals_label)

	hbox.add_child(right_vbox)

	margin.add_child(hbox)
	weather_panel.add_child(margin)

	$CanvasLayer.add_child(weather_panel)

	_redraw_active_tool_label()


func _setup_political_metrics_bar() -> void:
	political_metrics_bar = PanelContainer.new()
	political_metrics_bar.name = "political_metrics_bar"
	political_metrics_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	political_metrics_bar.offset_top = 80
	political_metrics_bar.custom_minimum_size = Vector2(0, 36)
	political_metrics_bar.visible = false

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.08, 0.06, 0.12, 0.92)
	bar_style.border_width_bottom = 1
	bar_style.border_color = Color(0.45, 0.35, 0.55)
	political_metrics_bar.add_theme_stylebox_override("panel", bar_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	political_money_label = Label.new()
	political_education_label = Label.new()
	political_ecology_label = Label.new()
	political_sanity_label = Label.new()
	for lbl in [political_money_label, political_education_label, political_ecology_label, political_sanity_label]:
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.98))
		hbox.add_child(lbl)

	margin.add_child(hbox)
	political_metrics_bar.add_child(margin)
	$CanvasLayer.add_child(political_metrics_bar)


func refresh_political_metrics_bar() -> void:
	if not is_instance_valid(political_metrics_bar):
		return
	var show := FarmDataManager.active_campaign_id == "oakhaven_defence"
	political_metrics_bar.visible = show
	if not show:
		_layout_sidebar_docks()
		return
	political_money_label.text = "Money: £%d" % FarmDataManager.current_money
	political_education_label.text = "Education: %d" % FarmDataManager.metric_education
	political_ecology_label.text = "Ecology: %d" % FarmDataManager.metric_ecology
	political_sanity_label.text = "Sanity: %d" % FarmDataManager.metric_sanity
	_layout_sidebar_docks()


func _setup_info_dock() -> void:
	info_dock_panel = PanelContainer.new()
	info_dock_panel.name = "InfoDock"
	info_dock_panel.custom_minimum_size = Vector2(280, 200)

	var dock_style := StyleBoxFlat.new()
	dock_style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	dock_style.set_border_width_all(2)
	dock_style.border_color = Color(0.4, 0.5, 0.6)
	dock_style.set_corner_radius_all(6)
	info_dock_panel.add_theme_stylebox_override("panel", dock_style)

	var margin := MarginContainer.new()
	margin.name = "DockMargin"
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)

	var scroll := ScrollContainer.new()
	scroll.name = "DockScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(288, 220)

	var col := VBoxContainer.new()
	col.name = "DockBody"
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var close_row := HBoxContainer.new()
	var close_spacer := Control.new()
	close_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dash_close := Button.new()
	dash_close.text = "×"
	dash_close.flat = true
	dash_close.focus_mode = Control.FOCUS_NONE
	dash_close.size_flags_horizontal = Control.SIZE_SHRINK_END
	dash_close.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	dash_close.add_theme_color_override("font_hover_color", Color(0.9, 0.2, 0.2))
	dash_close.pressed.connect(func(): info_dock_panel.hide())
	close_row.add_child(close_spacer)
	close_row.add_child(dash_close)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.09, 0.09, 0.1, 0.9)
	hover_style.set_border_width_all(1)
	hover_style.border_color = Color(0.4, 0.42, 0.48, 1)
	hover_style.set_corner_radius_all(4)
	hover_style.content_margin_left = 10
	hover_style.content_margin_top = 8
	hover_style.content_margin_right = 10
	hover_style.content_margin_bottom = 8

	var hover_lbl := Label.new()
	hover_lbl.name = "Hover_Label"
	hover_lbl.text = "Tile Data"
	hover_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hover_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_lbl.custom_minimum_size = Vector2(272, 0)
	hover_lbl.add_theme_font_size_override("font_size", 14)
	hover_lbl.add_theme_color_override("font_color", Color(0.92, 0.91, 0.88, 1))
	hover_lbl.add_theme_stylebox_override("normal", hover_style)

	forecast_events_header = Label.new()
	forecast_events_header.name = "Forecast_Events_Header"
	forecast_events_header.text = "Farm Dashboard"
	forecast_events_header.add_theme_font_size_override("font_size", 15)
	forecast_events_header.add_theme_color_override("font_color", Color(0.96, 0.94, 0.9, 1))

	forecast_events_content = RichTextLabel.new()
	forecast_events_content.name = "Forecast_Events_Content"
	forecast_events_content.bbcode_enabled = true
	forecast_events_content.fit_content = true
	forecast_events_content.scroll_active = false
	forecast_events_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forecast_events_content.custom_minimum_size = Vector2(272, 0)
	forecast_events_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forecast_events_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	col.add_child(close_row)
	col.add_child(hover_lbl)
	col.add_child(forecast_events_header)
	col.add_child(forecast_events_content)

	scroll.add_child(col)
	margin.add_child(scroll)
	info_dock_panel.add_child(margin)


func _setup_weather_dock() -> void:
	weather_dock = PanelContainer.new()
	weather_dock.name = "WeatherDock"

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	weather_grid = GridContainer.new()
	weather_grid.name = "Weather_Grid"
	weather_grid.columns = FORECAST_COLS
	weather_grid.add_theme_constant_override("h_separation", 4)
	weather_grid.add_theme_constant_override("v_separation", 4)
	weather_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var detail_parts := _make_detail_panel()
	weather_detail_box = detail_parts["panel"]
	weather_detail_label = detail_parts["label"]
	root.add_child(weather_grid)
	root.add_child(weather_detail_box)
	margin.add_child(root)
	weather_dock.add_child(margin)
	_set_weather_detail_text("Select a forecast day for details.")


func _setup_calendar_dock() -> void:
	calendar_dock = PanelContainer.new()
	calendar_dock.name = "CalendarDock"

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	calendar_header_row = HBoxContainer.new()
	calendar_header_row.name = "Calendar_Header_Row"
	calendar_header_row.add_theme_constant_override("separation", 4)
	calendar_header_row.alignment = BoxContainer.ALIGNMENT_CENTER

	calendar_prev_btn = Button.new()
	calendar_prev_btn.name = "Calendar_Prev"
	calendar_prev_btn.text = "‹"
	calendar_prev_btn.flat = true
	calendar_prev_btn.focus_mode = Control.FOCUS_NONE
	calendar_prev_btn.tooltip_text = "Previous month"
	calendar_prev_btn.custom_minimum_size = Vector2(28, 28)
	calendar_prev_btn.pressed.connect(_on_calendar_prev_month)

	calendar_month_title = Label.new()
	calendar_month_title.name = "Calendar_Month_Title"
	calendar_month_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	calendar_month_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	calendar_month_title.add_theme_font_size_override("font_size", 14)
	calendar_month_title.add_theme_color_override("font_color", Color(0.82, 0.9, 0.72, 1))

	calendar_today_btn = Button.new()
	calendar_today_btn.name = "Calendar_Today"
	calendar_today_btn.text = "📅"
	calendar_today_btn.flat = true
	calendar_today_btn.focus_mode = Control.FOCUS_NONE
	calendar_today_btn.tooltip_text = "Jump to current month"
	calendar_today_btn.custom_minimum_size = Vector2(28, 28)
	calendar_today_btn.pressed.connect(_on_calendar_jump_to_present)

	calendar_next_btn = Button.new()
	calendar_next_btn.name = "Calendar_Next"
	calendar_next_btn.text = "›"
	calendar_next_btn.flat = true
	calendar_next_btn.focus_mode = Control.FOCUS_NONE
	calendar_next_btn.tooltip_text = "Next month"
	calendar_next_btn.custom_minimum_size = Vector2(28, 28)
	calendar_next_btn.pressed.connect(_on_calendar_next_month)

	calendar_header_row.add_child(calendar_prev_btn)
	calendar_header_row.add_child(calendar_month_title)
	calendar_header_row.add_child(calendar_today_btn)
	calendar_header_row.add_child(calendar_next_btn)

	calendar_month_grid = GridContainer.new()
	calendar_month_grid.name = "Calendar_Month_Grid"
	calendar_month_grid.columns = MONTH_GRID_COLS
	calendar_month_grid.add_theme_constant_override("h_separation", 3)
	calendar_month_grid.add_theme_constant_override("v_separation", 3)
	calendar_month_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cal_detail_parts := _make_detail_panel()
	calendar_detail_box = cal_detail_parts["panel"]
	calendar_detail_label = cal_detail_parts["label"]
	root.add_child(calendar_header_row)
	root.add_child(calendar_month_grid)
	root.add_child(calendar_detail_box)
	margin.add_child(root)
	calendar_dock.add_child(margin)
	_set_calendar_detail_text("Select a day for event details.")
	_reset_calendar_view_to_present()
	refresh_calendar_dock()


func _reset_calendar_view_to_present() -> void:
	var info: Dictionary = FarmDataManager.get_current_date_info()
	_calendar_view_year = int(info["year"])
	_calendar_view_month_index = int(info["month_index"])


func _is_viewing_present_month() -> bool:
	var info: Dictionary = FarmDataManager.get_current_date_info()
	return _calendar_view_year == int(info["year"]) \
		and _calendar_view_month_index == int(info["month_index"])


func _shift_calendar_view(delta_months: int) -> void:
	_calendar_view_month_index += delta_months
	while _calendar_view_month_index < 0:
		_calendar_view_month_index += 12
		_calendar_view_year -= 1
	while _calendar_view_month_index >= 12:
		_calendar_view_month_index -= 12
		_calendar_view_year += 1
	_calendar_view_year = maxi(1, _calendar_view_year)
	refresh_calendar_dock()


func _on_calendar_prev_month() -> void:
	_shift_calendar_view(-1)


func _on_calendar_next_month() -> void:
	_shift_calendar_view(1)


func _on_calendar_jump_to_present() -> void:
	_reset_calendar_view_to_present()
	refresh_calendar_dock()
	_set_calendar_detail_text("Back to the present month.")


func _make_detail_panel() -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 88)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.12, 0.95)
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color(0.32, 0.36, 0.4, 0.9)
	panel.add_theme_stylebox_override("panel", style)
	var detail_margin := MarginContainer.new()
	detail_margin.name = "DetailMargin"
	detail_margin.add_theme_constant_override("margin_left", 8)
	detail_margin.add_theme_constant_override("margin_right", 8)
	detail_margin.add_theme_constant_override("margin_top", 8)
	detail_margin.add_theme_constant_override("margin_bottom", 8)
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_margin.add_child(lbl)
	panel.add_child(detail_margin)
	return {"panel": panel, "label": lbl}


func _configure_grid_icon_button(btn: Button) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	btn.add_theme_font_size_override("font_size", 10)
	btn.custom_minimum_size = Vector2(48, 52)


func refresh_info_dock(forecast: Array) -> void:
	refresh_weather_dock(forecast)
	refresh_calendar_dock()


func build_forecast_calendar(forecast: Array) -> void:
	refresh_info_dock(forecast)


func _forecast_confidence_percent(day_offset: int, target_turn: int) -> int:
	if day_offset < ACCURATE_FORECAST_DAYS:
		return 100
	var rng := RandomNumberGenerator.new()
	rng.seed = target_turn
	return rng.randi_range(30, 85)


func refresh_weather_dock(forecast: Array) -> void:
	if not is_instance_valid(weather_grid):
		return

	for child in weather_grid.get_children():
		child.queue_free()

	var padded: Array[String] = []
	for i in range(FORECAST_DAYS):
		if i < forecast.size():
			padded.append(str(forecast[i]))
		else:
			padded.append("clear")

	for i in range(FORECAST_DAYS):
		var weather_id := padded[i].strip_edges().to_lower()
		if weather_id == "drought":
			weather_id = "dry"
		var target_turn := FarmDataManager.current_turn + i
		var date_info: Dictionary = FarmDataManager.get_current_date_info(target_turn)
		var weekday: String = str(date_info["weekday"])
		var day_num: int = int(date_info["day_of_month"])
		var accurate := i < ACCURATE_FORECAST_DAYS
		var prob := _forecast_confidence_percent(i, target_turn)
		var emoji: String = str(WEATHER_EMOJI.get(weather_id, "☀️"))
		var line2 := emoji if accurate else "%d%% %s" % [prob, emoji]
		var label := "%s %d\n%s" % [weekday, day_num, line2]
		var btn := Button.new()
		_configure_grid_icon_button(btn)
		btn.text = label
		btn.tooltip_text = FarmDataManager.format_calendar_date(target_turn)
		btn.modulate.a = 1.0 if accurate else 0.6
		btn.pressed.connect(_on_weather_day_clicked.bind(i, weather_id, date_info, prob))
		weather_grid.add_child(btn)

	if padded.size() > 0:
		var first_id := padded[0].strip_edges().to_lower()
		if first_id == "drought":
			first_id = "dry"
		var first_info: Dictionary = FarmDataManager.get_current_date_info(FarmDataManager.current_turn)
		_on_weather_day_clicked(0, first_id, first_info, 100)


func refresh_calendar_dock() -> void:
	if not is_instance_valid(calendar_month_grid):
		return

	FarmDataManager.sync_calendar_state()
	var present: Dictionary = FarmDataManager.get_current_date_info()
	var year := _calendar_view_year
	var month_index := _calendar_view_month_index
	var viewing_present := _is_viewing_present_month()
	var today_day: int = int(present["day_of_month"]) if viewing_present else -1

	if is_instance_valid(calendar_month_title):
		calendar_month_title.text = FarmDataManager.format_month_year(year, month_index)
		calendar_month_title.tooltip_text = "%s · %s" % [
			FarmDataManager.get_month_season_name(month_index),
			FarmDataManager.get_coarse_season(
				FarmDataManager.turn_for_month_day(year, month_index, 1)
			),
		]
	if is_instance_valid(calendar_today_btn):
		calendar_today_btn.modulate.a = 0.45 if viewing_present else 1.0

	for child in calendar_month_grid.get_children():
		child.queue_free()

	for wd in FarmDataManager.WEEKDAYS:
		var hdr := Label.new()
		hdr.text = wd
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hdr.add_theme_font_size_override("font_size", 10)
		hdr.add_theme_color_override("font_color", Color(0.55, 0.57, 0.6, 1.0))
		hdr.custom_minimum_size = Vector2(34, 16)
		calendar_month_grid.add_child(hdr)

	var month_start_turn := FarmDataManager.turn_for_month_day(year, month_index, 1)
	var start_weekday_idx := (month_start_turn - 1) % FarmDataManager.WEEKDAYS.size()
	for _i in range(start_weekday_idx):
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(34, 34)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		calendar_month_grid.add_child(pad)

	for day in range(1, MONTH_DAYS + 1):
		var abs_turn := FarmDataManager.turn_for_month_day(year, month_index, day)
		var btn := Button.new()
		_configure_grid_icon_button(btn)
		btn.custom_minimum_size = Vector2(34, 40)
		var btn_text := str(day)
		if not FarmDataManager.get_community_event(abs_turn).is_empty():
			btn_text += "\n⭐"
		btn.text = btn_text
		if day == today_day:
			var today_style := StyleBoxFlat.new()
			today_style.bg_color = Color(0.18, 0.32, 0.18, 1.0)
			today_style.border_color = Color(1.0, 0.92, 0.25, 0.95)
			today_style.set_border_width_all(2)
			today_style.set_corner_radius_all(3)
			today_style.content_margin_left = 4.0
			today_style.content_margin_top = 4.0
			today_style.content_margin_right = 4.0
			today_style.content_margin_bottom = 4.0
			btn.add_theme_stylebox_override("normal", today_style)
			btn.add_theme_stylebox_override("hover", today_style)
			btn.add_theme_stylebox_override("pressed", today_style)
		btn.pressed.connect(_on_calendar_day_clicked.bind(abs_turn))
		calendar_month_grid.add_child(btn)


func _on_weather_day_clicked(day_offset: int, weather_id: String, date_info: Dictionary, prob: int) -> void:
	var weekday: String = str(date_info.get("weekday", ""))
	var day_num: int = int(date_info.get("day_of_month", 0))
	var flavor: String = str(WEATHER_FLAVOR.get(weather_id, "A steady day on the farm."))
	var certainty := "[color=green]✓ 100% Guaranteed[/color]" if day_offset < ACCURATE_FORECAST_DAYS \
		else "[color=orange]~ %d%% Chance (Looking Ahead)[/color]" % prob
	var bb := "[b]Weather for %s, %d[/b]\n" % [weekday, day_num]
	bb += certainty + "\n\n"
	bb += flavor
	_set_weather_detail_text(bb)


func _on_calendar_day_clicked(absolute_turn: int) -> void:
	var info: Dictionary = FarmDataManager.get_current_date_info(absolute_turn)
	var event_name := FarmDataManager.get_community_event(absolute_turn)
	var bb := "[b]%s[/b] [color=#a5d6a7](%s · %s)[/color]\n" % [
		FarmDataManager.format_calendar_date(absolute_turn),
		str(info.get("season_name", "")),
		FarmDataManager.get_coarse_season(absolute_turn),
	]
	bb += "%s · Turn %d\n" % [str(info["weekday"]), absolute_turn]
	if event_name.is_empty():
		bb += "\n[color=#888888]No community events scheduled.[/color]"
	else:
		bb += "\n[color=#ffe082]⭐ %s[/color]" % event_name
	_set_calendar_detail_text(bb)


func _set_weather_detail_text(bbcode: String) -> void:
	if is_instance_valid(weather_detail_label):
		weather_detail_label.text = bbcode


func _set_calendar_detail_text(bbcode: String) -> void:
	if is_instance_valid(calendar_detail_label):
		calendar_detail_label.text = bbcode


func _setup_top_bar() -> void:
	push_warning("HUD: _setup_top_bar is deprecated; use _setup_status_strip")
	_setup_status_strip()


func flash_forecast_attention() -> void:
	var tab_btn: Button = _edge_tabs.get(weather_dock, null) as Button
	if not is_instance_valid(tab_btn):
		if not is_instance_valid(forecast_events_header):
			return
		tab_btn = null
	var base_color: Color
	if is_instance_valid(tab_btn):
		base_color = tab_btn.get_theme_color("font_color")
	else:
		base_color = forecast_events_header.get_theme_color("font_color")
	var tween := create_tween()
	tween.set_loops(3)
	tween.tween_callback(func() -> void:
		if is_instance_valid(tab_btn):
			tab_btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.25))
		if is_instance_valid(forecast_events_header):
			forecast_events_header.add_theme_color_override("font_color", Color(1.0, 0.92, 0.25))
	)
	tween.tween_interval(0.18)
	tween.tween_callback(func() -> void:
		if is_instance_valid(tab_btn):
			tab_btn.add_theme_color_override("font_color", base_color)
		if is_instance_valid(forecast_events_header):
			forecast_events_header.add_theme_color_override("font_color", base_color)
	)
	tween.tween_interval(0.18)


func update_weather_display(season: String, desc: String, is_dry: bool) -> void:
	if not is_instance_valid(season_label):
		return
	season_label.text = season
	weather_desc_label.text = desc
	var panel_sb = weather_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if is_dry:
		season_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2))
		if panel_sb:
			panel_sb.border_color = Color(0.9, 0.3, 0.2)
	else:
		season_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		if panel_sb:
			panel_sb.border_color = Color(0.2, 0.3, 0.2)
	var map_node: Node = get_tree().get_first_node_in_group("map")
	if map_node and "forecast" in map_node:
		refresh_info_dock(map_node.forecast)


func show_tool(tool_name: String) -> void:
	if not is_instance_valid(inspector_label):
		return
	if is_instance_valid(inspector_panel):
		_set_sidebar_panel_visible(inspector_panel, true)
	_clear_inspector_plant_sprites()
	if is_instance_valid(inspector_icon):
		inspector_icon.texture = null
	var text = "[b][color=#ffe082]ACTIVE TOOL[/color][/b]\n\n"
	text += "[font_size=24]%s[/font_size]\n" % tool_name.capitalize().replace("_", " ")
	inspector_label.text = text


func _format_role_name(raw_name: String) -> String:
	var words = raw_name.split("_")
	var clean = ""
	for w in words:
		clean += w.capitalize() + " "
	return clean.strip_edges()


func show_tile(x: int, y: int, cell_data: Dictionary, atlas_tex: Texture2D) -> void:
	if is_instance_valid(inspector_panel):
		_set_sidebar_panel_visible(inspector_panel, true)
	_update_inspector_preview(cell_data, atlas_tex)

	if not is_instance_valid(inspector_label):
		update_soil_inspector(build_soil_inspector_stats(cell_data))
		return

	var text = "[b]Tile (%d, %d)[/b] - %s\n" % [x, y, str(cell_data["land"]).capitalize()]

	var map_node = get_tree().get_first_node_in_group("map")
	
	# --- GUILD INSPECTOR OVERRIDE ---
	if map_node and map_node.get("active_lens") == "guild":
		var cell = FarmDataManager.grid_data[x][y]
		var plant_db = preload("res://data/data_plants.gd")
		
		text = "[b][color=#ffb300]🔍 GUILD INSPECTOR[/color][/b]\n"
		text += "[color=#888888]Coordinate: (" + str(x) + ", " + str(y) + ")[/color]\n\n"
		
		# 1. Break down the roles provided by THIS specific tile
		text += "[b]Contributions to Network:[/b]\n"
		var found_any_role := false
		for layer in ["canopy", "understory", "ground"]:
			var p_id = str(cell.get(layer, ""))
			if p_id != "":
				var p_data = plant_db.get_plant_data(p_id)
				var p_name = str(p_data.get("name", p_id))
				var roles: Array[String] = []
				
				# Extract boolean traits
				for k in p_data.keys():
					if typeof(p_data[k]) == TYPE_BOOL and p_data[k]:
						roles.append(_format_role_name(str(k)))
				# Extract category
				var cat = str(p_data.get("category", ""))
				if cat != "":
					roles.append(_format_role_name(cat))
				
				if roles.size() > 0:
					text += "  • [b]" + p_name + ":[/b] [color=#64b5f6]" + ", ".join(PackedStringArray(roles)) + "[/color]\n"
					found_any_role = true
				else:
					text += "  • [b]" + p_name + ":[/b] [color=#888888]No active synergies[/color]\n"
					
		if not found_any_role:
			text += "  [color=#888888]No ecological roles found on this tile.[/color]\n"
			
		# 2. Fetch and detail Active Synergies
		text += "\n[line]\n"
		var synergies = map_node._get_synergies_for_cell(x, y) if map_node.has_method("_get_synergies_for_cell") else {"guilds": [], "superguilds": []}
		
		if synergies["guilds"].size() > 0:
			text += "\n[b][color=#fbc02d]⭐ ACTIVE 1-TILE GUILDS[/color][/b]\n"
			for g in synergies["guilds"]:
				text += "[b]" + str(g.get("name", "Unknown")) + "[/b] (Yield Bonus: +" + str(g.get("yield_bonus", 0)) + ")\n"
				text += "[color=#b0bec5][i]" + str(g.get("desc", "")) + "[/i][/color]\n\n"

		if synergies["superguilds"].size() > 0:
			text += "\n[b][color=#ba68c8]✨ ACTIVE 3x3 SUPERGUILDS ✨[/color][/b]\n"
			for sg in synergies["superguilds"]:
				text += "[b]" + str(sg.get("name", "Unknown")) + "[/b] (Yield Mult: x" + str(sg.get("yield_mult", 1.0)) + ")\n"
				
				# Dynamically format and print the exact mathematical requirements
				var reqs: Dictionary = sg.get("req_roles", {})
				var req_string := ""
				for r_key in reqs.keys():
					req_string += str(reqs[r_key]) + "x " + _format_role_name(str(r_key)) + ", "
				req_string = req_string.trim_suffix(", ")
				
				text += "[color=#e1bee7]Requires:[/color] [color=#ffffff]" + req_string + "[/color]\n"
				text += "[color=#b0bec5][i]" + str(sg.get("desc", "")) + "[/i][/color]\n\n"
				
		if synergies["guilds"].size() == 0 and synergies["superguilds"].size() == 0:
			text += "\n[color=#888888]This tile is not currently part of any active Guild or Superguild network.[/color]"

		inspector_label.text = text
		update_soil_inspector(build_soil_inspector_stats(cell_data))
		return
	# --- END GUILD INSPECTOR OVERRIDE ---

	var tags = cell_data.get("soil_tags", ["clay"])
	var formatted_tags: Array = []
	for t in tags:
		# Colour-code the tags for better UX
		if t == "clay" or t == "sandy":
			formatted_tags.append("[color=#d84315]%s[/color]" % t)
		else:
			formatted_tags.append("[color=#9ccc65]%s[/color]" % t)

	text += "[b]Soil Profile:[/b] "
	for fi in range(formatted_tags.size()):
		if fi > 0:
			text += ", "
		text += str(formatted_tags[fi])
	text += "\n\n"

	var plants := PackedStringArray()
	for layer_key in ["canopy", "understory", "ground"]:
		if cell_data.has(layer_key) and cell_data[layer_key] != "":
			var p_id = cell_data[layer_key]
			var p_data = preload("res://data/data_plants.gd").get_plant_data(p_id)

			var layer_color = "#a5d6a7" if layer_key == "canopy" else ("#ffe082" if layer_key == "understory" else "#80deea")
			var entry = "[color=%s]%s[/color] [i](%s)[/i]\n" % [
				layer_color,
				str(p_data.get("name", "?")),
				str(p_data.get("latin_name", "")),
			]

			# Extract deeper ecological data
			entry += "  ├ Roots: %s\n" % p_data.get("root_type", "Unknown")

			var traits := PackedStringArray()
			if p_data.get("dynamic_accumulator", false):
				traits.append("Accumulator")
			if p_data.get("nitrogen_fixer", false):
				traits.append("N-Fixer")
			if p_data.get("windbreak_rating", 0) > 6:
				traits.append("Windbreak")
			if p_data.get("coppice_yield", 0) > 0:
				traits.append("Coppiceable")

			if traits.size() > 0:
				entry += "  └ Traits: %s" % ", ".join(PackedStringArray(traits))
			else:
				var pd := preload("res://data/data_plants.gd")
				entry += "  └ Hardiness: %d/10" % pd.as_int(p_data.get("frost_hardiness", 5))

			plants.append(entry)

	if plants.size() > 0:
		text += "\n".join(PackedStringArray(plants))
	else:
		text += "[color=#757575]No plants growing here.[/color]"

	var death_history := FarmDataManager.format_plant_death_log(cell_data)
	if death_history != "":
		text += "\n\n" + death_history

	inspector_label.text = text

	update_soil_inspector(build_soil_inspector_stats(cell_data))


func _get_flora_atlas_texture() -> Texture2D:
	if is_instance_valid(_inspector_flora_atlas_tex):
		return _inspector_flora_atlas_tex
	var meta := PlantGrowth.flora_atlas_meta()
	var path := str(meta.get("atlas_path", "res://assets/base/sprites/atlas/flora_atlas.png"))
	if ResourceLoader.exists(path):
		_inspector_flora_atlas_tex = load(path) as Texture2D
	return _inspector_flora_atlas_tex


func _clear_inspector_plant_sprites() -> void:
	for rect in [
		inspector_ground_rect,
		inspector_understory_rect,
		inspector_canopy_shadow_rect,
		inspector_canopy_rect,
	]:
		if is_instance_valid(rect):
			rect.texture = null
			rect.visible = false


func _flora_atlas_texture_for_cell(layer_key: String, cell_data: Dictionary) -> Texture2D:
	var p_id := str(cell_data.get(layer_key, ""))
	if p_id == "":
		return null
	var atlas_tex := _get_flora_atlas_texture()
	if atlas_tex == null:
		return null
	var tile_sz := int(PlantGrowth.flora_atlas_meta().get("tile_size", 200))
	var plant_age := float(cell_data.get("%s_age" % layer_key, 0.0))
	var growth_stage := PlantGrowth.growth_stage(p_id, plant_age)
	var coord := PlantGrowth.flora_atlas_coord(p_id, growth_stage)
	if coord.x < 0:
		return null
	var layer_tex := AtlasTexture.new()
	layer_tex.atlas = atlas_tex
	layer_tex.region = Rect2(coord.x * tile_sz, coord.y * tile_sz, tile_sz, tile_sz)
	return layer_tex


func _update_inspector_preview(cell_data: Dictionary, terrain_tex: Texture2D) -> void:
	if is_instance_valid(inspector_icon):
		inspector_icon.texture = terrain_tex
	_clear_inspector_plant_sprites()
	if is_instance_valid(inspector_ground_rect):
		var ground_tex := _flora_atlas_texture_for_cell("ground", cell_data)
		inspector_ground_rect.texture = ground_tex
		inspector_ground_rect.visible = ground_tex != null
	if is_instance_valid(inspector_understory_rect):
		var understory_tex := _flora_atlas_texture_for_cell("understory", cell_data)
		inspector_understory_rect.texture = understory_tex
		inspector_understory_rect.visible = understory_tex != null
	if is_instance_valid(inspector_canopy_rect):
		var canopy_tex := _flora_atlas_texture_for_cell("canopy", cell_data)
		inspector_canopy_rect.texture = canopy_tex
		inspector_canopy_rect.visible = canopy_tex != null
	if is_instance_valid(inspector_canopy_shadow_rect):
		var shadow_tex := _flora_atlas_texture_for_cell("canopy", cell_data)
		inspector_canopy_shadow_rect.texture = shadow_tex
		inspector_canopy_shadow_rect.visible = shadow_tex != null


func build_soil_inspector_stats(cell: Dictionary) -> Dictionary:
	var stats = {
		"depth": float(cell.get("depth", 30)),
		"structure": float(cell.get("structure", 5.0)),
		"moisture": float(cell.get("moisture", 5.0)),
		"nitrogen": float(cell.get("nitrogen", 5.0)),
		"minerals": float(cell.get("minerals", 5.0)),
		"fungi": float(cell.get("fungi", 0.0)),
		"bacteria": float(cell.get("bacteria", 0.0)),
		"macro_life": float(cell.get("macro_life", 0.0)),
		"ph": float(cell.get("ph", 6.5)),
		"toxicity": float(cell.get("toxicity", 0.0)),
		"temp": int(cell.get("temp", 15)),
		"reqs": {},
	}

	# Calculate the strictest overlapping requirements for all plants on this tile
	var p_min_m := 0.0
	var p_max_m := 10.0
	var p_min_n := 0.0
	var p_max_n := 10.0
	var p_min_min := 0.0
	var p_max_min := 10.0
	var has_plant := false

	for layer in ["canopy", "understory", "ground"]:
		if cell.has(layer) and str(cell[layer]) != "":
			var p_id = cell[layer]
			var p_data = preload("res://data/data_plants.gd").get_plant_data(p_id)
			p_min_m = maxf(p_min_m, float(p_data.get("min_moisture", 0.0)))
			p_max_m = minf(p_max_m, float(p_data.get("max_moisture", 10.0)))
			p_min_n = maxf(p_min_n, float(p_data.get("min_nitrogen", 0.0)))
			p_max_n = minf(p_max_n, float(p_data.get("max_nitrogen", 10.0)))
			p_min_min = maxf(p_min_min, float(p_data.get("min_minerals", 0.0)))
			p_max_min = minf(p_max_min, float(p_data.get("max_minerals", 10.0)))
			has_plant = true

	if has_plant:
		stats["reqs"] = {
			"moisture": [p_min_m, p_max_m],
			"nitrogen": [p_min_n, p_max_n],
			"minerals": [p_min_min, p_max_min],
		}

	stats["forecast"] = PlantNutrientForecast.compute(cell)
	return stats


func update_soil_inspector(stats: Dictionary) -> void:
	if is_instance_valid(soil_profile_ui):
		soil_profile_ui.update_profile(stats)


func _setup_minimap_ui() -> void:
	minimap_panel = PanelContainer.new()
	minimap_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.set_border_width_all(3)
	style.border_color = Color(0.3, 0.5, 0.3, 1.0)
	style.set_corner_radius_all(4)
	minimap_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title = Label.new()
	title.text = "ECOLOGY SCANNER"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	minimap_rect = TextureRect.new()
	minimap_rect.custom_minimum_size = Vector2(128, 128)
	minimap_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minimap_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# CRITICAL: Nearest filter ensures the 128x128 image stays sharp, not blurry
	minimap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	minimap_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(minimap_rect)

	minimap_panel.add_child(vbox)


func update_minimap(tex: Texture2D) -> void:
	if is_instance_valid(minimap_rect):
		minimap_rect.texture = tex


func _add_pause_settings_button(
	pause_vbox: VBoxContainer,
	label: String,
	settings_scroll: ScrollContainer,
	insert_before_index: int
) -> void:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	pause_vbox.add_child(btn)
	pause_vbox.move_child(btn, insert_before_index)
	btn.pressed.connect(func() -> void: _show_pause_subpanel(settings_scroll))


func _setup_pause_settings_panels() -> void:
	var panel_root := pause_main_vbox.get_parent() as PanelContainer
	if not panel_root:
		return
	pause_audio_scroll = _make_pause_settings_scroll(preload("res://scripts/ui_audio_panel.gd"))
	pause_graphics_scroll = _make_pause_settings_scroll(preload("res://scripts/ui_graphics_panel.gd"))
	pause_gameplay_scroll = _make_pause_settings_scroll(preload("res://scripts/ui_gameplay_panel.gd"))
	for scroll in [pause_audio_scroll, pause_graphics_scroll, pause_gameplay_scroll]:
		panel_root.add_child(scroll)


func _make_pause_settings_scroll(panel_script: Script) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	scroll.custom_minimum_size = Vector2(420, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.hide()
	var panel: Control = panel_script.new()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	scroll.add_child(panel)
	if panel.has_signal("back_pressed"):
		panel.back_pressed.connect(_show_pause_main_menu)
	return scroll


func _show_pause_subpanel(scroll: ScrollContainer) -> void:
	if not is_instance_valid(scroll) or scroll.get_child_count() == 0:
		return
	var panel := scroll.get_child(0) as Control
	if panel.has_method("sync_controls_from_farm"):
		panel.sync_controls_from_farm()
	elif panel.has_method("sync_controls_from_system"):
		panel.sync_controls_from_system()
	if is_instance_valid(pause_main_vbox):
		pause_main_vbox.hide()
	for s in [pause_audio_scroll, pause_graphics_scroll, pause_gameplay_scroll]:
		if is_instance_valid(s):
			s.hide()
	scroll.show()


func _show_pause_main_menu() -> void:
	for s in [pause_audio_scroll, pause_graphics_scroll, pause_gameplay_scroll]:
		if is_instance_valid(s):
			s.hide()
	if is_instance_valid(pause_main_vbox):
		pause_main_vbox.show()


func _inject_settings_into_pause_menu() -> void:
	# Find the main vertical container inside the existing pause menu
	var target_vbox: VBoxContainer = null
	for child in pause_menu.find_children("*", "VBoxContainer", true, false):
		target_vbox = child as VBoxContainer
		break

	if not target_vbox:
		push_error("Could not find a VBoxContainer in the pause menu to inject settings!")
		return

	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 20)
	target_vbox.add_child(separator)

	var title = Label.new()
	title.text = "VISUAL FEEDBACK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	target_vbox.add_child(title)

	# Generate Toggles dynamically
	for key in indicator_settings.keys():
		var setting_key = key
		var hbox = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = "Show " + str(setting_key).capitalize()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var btn = CheckButton.new()
		btn.button_pressed = indicator_settings[setting_key]
		btn.toggled.connect(func(toggled_on: bool): indicator_settings[setting_key] = toggled_on)

		hbox.add_child(lbl)
		hbox.add_child(btn)
		target_vbox.add_child(hbox)


func _setup_inspector_ui() -> void:
	inspector_panel = PanelContainer.new()
	inspector_panel.name = "TileInspector"
	inspector_panel.hide()

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.5, 0.6)
	style.set_corner_radius_all(6)
	inspector_panel.add_theme_stylebox_override("panel", style)

	# Add a margin container so the text isn't glued to the borders
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)

	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var close_inspector = Button.new()
	close_inspector.text = "×"
	close_inspector.flat = true
	close_inspector.focus_mode = Control.FOCUS_NONE
	close_inspector.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_inspector.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	close_inspector.add_theme_color_override("font_hover_color", Color(0.9, 0.2, 0.2))
	close_inspector.pressed.connect(func(): inspector_panel.hide())
	main_vbox.add_child(close_inspector)

	# --- SCROLL CONTAINER ---
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(290, 450) # The default viewable height before scrolling kicks in

	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 10)

	inspector_preview_box = Control.new()
	inspector_preview_box.name = "InspectorDiorama"
	inspector_preview_box.custom_minimum_size = Vector2(200, 200)
	inspector_preview_box.clip_contents = true
	inspector_preview_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	inspector_icon = TextureRect.new()
	inspector_icon.name = "TerrainPreview"
	inspector_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspector_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	inspector_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inspector_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspector_preview_box.add_child(inspector_icon)

	inspector_understory_rect = _make_inspector_diorama_rect("understory_rect")
	inspector_understory_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspector_understory_rect.scale = Vector2(1.0, 1.0)
	inspector_understory_rect.position = Vector2.ZERO
	inspector_preview_box.add_child(inspector_understory_rect)

	inspector_canopy_shadow_rect = _make_inspector_diorama_rect("canopy_shadow_rect")
	inspector_canopy_shadow_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspector_canopy_shadow_rect.modulate = Color(0, 0, 0, 0.5)
	inspector_canopy_shadow_rect.scale = Vector2(1.15, 1.15)
	inspector_canopy_shadow_rect.position = Vector2(-30, -40)
	inspector_preview_box.add_child(inspector_canopy_shadow_rect)

	inspector_canopy_rect = _make_inspector_diorama_rect("canopy_rect")
	inspector_canopy_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspector_canopy_rect.scale = Vector2(1.15, 1.15)
	inspector_canopy_rect.position = Vector2(-35, -45)
	inspector_preview_box.add_child(inspector_canopy_rect)

	inspector_ground_rect = _make_inspector_diorama_rect("ground_rect")
	inspector_ground_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspector_ground_rect.scale = Vector2(1.0, 1.0)
	inspector_ground_rect.position = Vector2.ZERO
	inspector_preview_box.add_child(inspector_ground_rect)

	content_vbox.add_child(inspector_preview_box)

	inspector_label = RichTextLabel.new()
	inspector_label.custom_minimum_size = Vector2(280, 150)
	inspector_label.bbcode_enabled = true
	inspector_label.fit_content = true
	content_vbox.add_child(inspector_label)

	soil_profile_ui = SoilProfileUI.new()
	soil_profile_ui.name = "SoilProfileUI"
	soil_profile_ui.custom_minimum_size = Vector2(280, 260)
	soil_profile_ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(soil_profile_ui)

	scroll.add_child(content_vbox)
	main_vbox.add_child(scroll)

	margin.add_child(main_vbox)
	inspector_panel.add_child(margin)


func _make_inspector_diorama_rect(node_name: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	rect.visible = false
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _setup_queue_ui() -> void:
	queue_panel = PanelContainer.new()
	queue_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	queue_panel.position = Vector2(-420, -200) # Tucked nicely on the right

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.7, 0.4)
	style.set_corner_radius_all(6)
	queue_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()

	var title_row = HBoxContainer.new()
	var title = Label.new()
	title.text = "TODAY'S PLAN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))

	var close_queue = Button.new()
	close_queue.text = "×"
	close_queue.flat = true
	close_queue.focus_mode = Control.FOCUS_NONE
	close_queue.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_queue.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	close_queue.add_theme_color_override("font_hover_color", Color(0.9, 0.2, 0.2))
	close_queue.pressed.connect(func():
		var map_n: Node = get_tree().get_first_node_in_group("map") as Node
		if map_n and map_n.has_method("clear_queued_actions"):
			map_n.clear_queued_actions()
	)

	title_row.add_child(title)
	title_row.add_child(close_queue)
	vbox.add_child(title_row)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Use a ScrollContainer in case the player queues 50 actions
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	queue_list = VBoxContainer.new()
	queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(queue_list)

	vbox.add_child(scroll)
	queue_panel.add_child(vbox)

	queue_panel.hide() # Hidden by default until an action is queued


func update_action_queue_ui(queue: Array) -> void:
	if not is_instance_valid(queue_list):
		return

	for child in queue_list.get_children():
		child.queue_free()

	if queue.is_empty():
		_set_sidebar_panel_visible(queue_panel, false)
		return

	_focus_sidebar_panel(queue_panel, UISidebarDock.DockSide.RIGHT)
	for action in queue:
		var lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var cs := str(action.get("color", "fbc02d"))
		if not cs.begins_with("#"):
			cs = "#" + cs
		var act_color := Color(cs)
		lbl.add_theme_color_override("font_color", act_color)

		var act_name = str(action.get("action", "")).capitalize()
		var pos: Vector2i = action.get("pos", Vector2i.ZERO) as Vector2i

		if action.get("action") == "plant" and (action.has("seed_id") or action.has("seed")):
			var seed_id = action.get("seed_id", action.get("seed", ""))
			var seed_name = str(seed_id).capitalize().replace("_", " ")
			lbl.text = "• Plant %s (%d, %d)" % [seed_name, pos.x, pos.y]
		elif action.get("action") == "build":
			var sid := str(action.get("structure", ""))
			var pretty := sid.capitalize().replace("_", " ")
			match sid:
				"duck_house":
					pretty = "Duck House"
				"bridge":
					pretty = "Footbridge"
				"polytunnel":
					pretty = "Polytunnel"
				"honesty_box":
					pretty = "Honesty Box"
				"pig_house":
					pretty = "Pig House"
				"compost_brewer":
					pretty = "Compost Brewer"
			lbl.text = "• Build %s (%d, %d)" % [pretty, pos.x, pos.y]
		elif action.get("action") == "demolish":
			lbl.text = "• Demolish Structure (%d, %d)" % [pos.x, pos.y]
		elif action.get("action") == "build_path":
			lbl.text = "• Build Path (%d, %d)" % [pos.x, pos.y]
		elif action.get("action") == "water_tile":
			lbl.text = "• Water (%d, %d)" % [pos.x, pos.y]
		elif action.get("action") == "apply_tea":
			lbl.text = "• Compost Tea (%d, %d)" % [pos.x, pos.y]
		elif action.get("action") == "rotovate":
			lbl.text = "• Rotovator (%d, %d)" % [pos.x, pos.y]
		elif action.get("action") == "e_tiller":
			lbl.text = "• E-Tiller (%d, %d)" % [pos.x, pos.y]
		elif action.get("action") == "hosepipe":
			lbl.text = "• Hosepipe (%d, %d)" % [pos.x, pos.y]
		elif action.get("action") == "additive":
			var add_name = str(action.get("seed", "")).capitalize().replace("_", " ")
			lbl.text = "• Apply %s (%d, %d)" % [add_name, pos.x, pos.y]
		else:
			lbl.text = "• %s (%d, %d)" % [act_name, pos.x, pos.y]

		queue_list.add_child(lbl)


func update_active_tool_display(tool_name: String) -> void:
	if not is_instance_valid(active_tool_label):
		return

	_last_tool_display = tool_name

	if is_instance_valid(weather_panel):
		var sb = weather_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			if tool_name == "":
				sb.border_color = Color(0.2, 0.3, 0.2)
			else:
				sb.border_color = Color(0.8, 0.6, 0.2)

	_redraw_active_tool_label()


func apply_mail_indicator(unread: bool) -> void:
	if _unread_mail == unread:
		return
	_unread_mail = unread
	_redraw_active_tool_label()


func _redraw_active_tool_label() -> void:
	if not is_instance_valid(active_tool_label):
		return

	var body: String = "[center]"
	if _last_tool_display == "":
		body += "Equipped: Inspection Mode (Q)"
	else:
		body += "Equipped: " + _last_tool_display.replace("_", " ")
	if _unread_mail:
		body += " [color=#ffeb3b](! Unread Mail !)[/color]"
	body += "[/center]"

	active_tool_label.text = body


func show_context_menu(pos: Vector2, grid_pos: Vector2i) -> void:
	_context_grid_pos = grid_pos
	cell_context_menu.position = Vector2i(roundi(pos.x), roundi(pos.y))
	cell_context_menu.popup()


func _on_context_menu_pressed(id: int) -> void:
	var map = get_tree().get_first_node_in_group("map")
	match id:
		100:
			note_input.text = FarmDataManager.cell_notes.get(_context_grid_pos, {}).get("text", "")
			note_dialog.popup_centered(Vector2(300, 150))
		101:
			FarmDataManager.cell_notes[_context_grid_pos] = {"text": "Sun Trap", "color": "fff176"}
			if map:
				map.queue_redraw()
		102:
			FarmDataManager.cell_notes[_context_grid_pos] = {"text": "Frost Pocket", "color": "81d4fa"}
			if map:
				map.queue_redraw()
		103:
			FarmDataManager.cell_notes[_context_grid_pos] = {"text": "Waterlogged", "color": "3949ab"}
			if map:
				map.queue_redraw()
		104:
			FarmDataManager.cell_notes.erase(_context_grid_pos)
			if map:
				map.queue_redraw()
		200:
			if map:
				map.set_current_tool("rotovate")
		201:
			if map:
				map.set_current_tool("scythe")
		202:
			if map:
				map.set_current_tool("uproot")
		203:
			seed_picker.populate_and_show()
		204:
			var m_pos = get_viewport().get_mouse_position()
			build_menu.get_popup().popup(Rect2i(Vector2i(roundi(m_pos.x), roundi(m_pos.y)), Vector2i.ZERO))
		205:
			if map:
				map.set_current_tool("demolish")
		2:
			if map and map.has_method("_land_to_atlas_x"):
				var cell_r = FarmDataManager.grid_data[_context_grid_pos.x][_context_grid_pos.y]
				var a_rx = map._land_to_atlas_x(cell_r["land"], _context_grid_pos)
				var pic_r = AtlasTexture.new()
				if map.tile_set:
					var src = map.tile_set.get_source(0) as TileSetAtlasSource
					if src:
						pic_r.atlas = src.texture
				pic_r.region = Rect2(a_rx * 200, 0, 200, 200)
				show_tile(_context_grid_pos.x, _context_grid_pos.y, cell_r, pic_r)


func _on_note_confirmed() -> void:
	if note_input.text.strip_edges() != "":
		FarmDataManager.cell_notes[_context_grid_pos] = {"text": note_input.text, "color": "e0e0e0"}
	else:
		FarmDataManager.cell_notes.erase(_context_grid_pos)
	var map = get_tree().get_first_node_in_group("map")
	if map:
		map.queue_redraw()


func _setup_sidebar_docks() -> void:
	add_to_group("hud")
	left_sidebar_dock = UISidebarDock.new()
	left_sidebar_dock.name = "LeftSidebarDock"
	left_sidebar_dock.dock_side = UISidebarDock.DockSide.LEFT
	$CanvasLayer.add_child(left_sidebar_dock)
	left_sidebar_dock.z_index = Z_SIDEBAR

	right_sidebar_dock = UISidebarDock.new()
	right_sidebar_dock.name = "RightSidebarDock"
	right_sidebar_dock.dock_side = UISidebarDock.DockSide.RIGHT
	$CanvasLayer.add_child(right_sidebar_dock)
	right_sidebar_dock.z_index = Z_SIDEBAR

	_layout_sidebar_docks()


## Resting horizontal offsets for a dock: tucked behind its edge-tab strip when closed,
## flush beside it when open (Civ-style pop-out).
func _dock_rest_offsets(from_left: bool, open: bool) -> Vector2:
	var w := float(UISidebarDock.WIDTH)
	var shown_l := EDGE_TAB_W if from_left else -(EDGE_TAB_W + w)
	var shown_r := (EDGE_TAB_W + w) if from_left else -EDGE_TAB_W
	if open:
		return Vector2(shown_l, shown_r)
	var dir := -1.0 if from_left else 1.0
	return Vector2(shown_l + dir * w, shown_r + dir * w)


func _layout_sidebar_docks() -> void:
	if not is_instance_valid(left_sidebar_dock) or not is_instance_valid(right_sidebar_dock):
		return
	var top := 84.0
	if is_instance_valid(political_metrics_bar) and political_metrics_bar.visible:
		top = 120.0
	var bottom := int(BOTTOM_TOOLBAR_H) + 2

	var l_open := bool(_dock_open.get(left_sidebar_dock, false))
	var lo := _dock_rest_offsets(true, l_open)
	left_sidebar_dock.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_sidebar_dock.anchor_bottom = 1.0
	left_sidebar_dock.offset_left = lo.x
	left_sidebar_dock.offset_right = lo.y
	left_sidebar_dock.offset_top = top
	left_sidebar_dock.offset_bottom = -bottom
	left_sidebar_dock.visible = l_open

	var r_open := bool(_dock_open.get(right_sidebar_dock, false))
	var ro := _dock_rest_offsets(false, r_open)
	right_sidebar_dock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_sidebar_dock.anchor_bottom = 1.0
	right_sidebar_dock.offset_left = ro.x
	right_sidebar_dock.offset_right = ro.y
	right_sidebar_dock.offset_top = top
	right_sidebar_dock.offset_bottom = -bottom
	right_sidebar_dock.visible = r_open


func _raise_hud_chrome() -> void:
	var canvas := $CanvasLayer
	if canvas == null:
		return
	var bottom_dash := canvas.get_node_or_null("Bottom_Dashboard") as Control
	if bottom_dash:
		bottom_dash.z_index = Z_HUD_CHROME
		canvas.move_child(bottom_dash, -1)
	if is_instance_valid(weather_panel):
		weather_panel.z_index = Z_HUD_CHROME - 1
	if is_instance_valid(political_metrics_bar):
		political_metrics_bar.z_index = Z_HUD_CHROME - 1
	if is_instance_valid(pause_overlay):
		pause_overlay.z_index = Z_HUD_CHROME + 50
	if is_instance_valid(modal_dimmer):
		modal_dimmer.z_index = Z_HUD_CHROME + 40
	for child in canvas.get_children():
		if child is Control and str(child.name) == "AlmanacVaultOverlay":
			(child as Control).z_index = Z_MODAL_CONTENT
	if is_instance_valid(codex_window):
		codex_window.z_index = Z_MODAL_CONTENT + 10
		canvas.move_child(codex_window, canvas.get_child_count() - 2)


func _wire_toolbar_menu_popups() -> void:
	var menus: Array[MenuButton] = [
		actions_menu, build_menu, lenses_menu, inventory_menu,
	]
	for mb in menus:
		if mb == null:
			continue
		_configure_menu_popup_on_top(mb)
	# Runtime Info menu lives on the bottom bar.
	var middle := get_node_or_null(
		"CanvasLayer/Bottom_Dashboard/PanelContainer/HBoxContainer/Middle"
	)
	if middle:
		for child in middle.get_children():
			if child is MenuButton:
				_configure_menu_popup_on_top(child as MenuButton)


func setup_time_machine_ui() -> void:
	if is_instance_valid(time_machine_controls):
		return
	var bar := get_node_or_null(
		"CanvasLayer/Bottom_Dashboard/PanelContainer/HBoxContainer"
	) as HBoxContainer
	if bar == null:
		return

	time_machine_controls = HBoxContainer.new()
	time_machine_controls.name = "time_machine_controls"
	time_machine_controls.add_theme_constant_override("separation", 8)
	time_machine_controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_btn_time_back = Button.new()
	_btn_time_back.text = "◀"
	_btn_time_back.tooltip_text = "Earlier turn"
	_btn_time_back.focus_mode = Control.FOCUS_NONE
	_btn_time_back.custom_minimum_size = Vector2(40, 40)
	_btn_time_back.pressed.connect(_on_time_machine_back)

	_btn_time_forward = Button.new()
	_btn_time_forward.text = "▶"
	_btn_time_forward.tooltip_text = "Later turn"
	_btn_time_forward.focus_mode = Control.FOCUS_NONE
	_btn_time_forward.custom_minimum_size = Vector2(40, 40)
	_btn_time_forward.pressed.connect(_on_time_machine_forward)

	var slider_col := VBoxContainer.new()
	slider_col.add_theme_constant_override("separation", 2)
	slider_col.custom_minimum_size = Vector2(220, 0)
	slider_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label_row := HBoxContainer.new()
	label_row.add_theme_constant_override("separation", 8)
	timeline_turn_label = Label.new()
	timeline_turn_label.text = "Day 1"
	timeline_turn_label.add_theme_font_size_override("font_size", 13)
	timeline_index_label = Label.new()
	timeline_index_label.text = "1 / 1"
	timeline_index_label.add_theme_font_size_override("font_size", 12)
	timeline_index_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	timeline_index_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_row.add_child(timeline_turn_label)
	label_row.add_child(timeline_index_label)

	timeline_slider = HSlider.new()
	timeline_slider.name = "timeline_slider"
	timeline_slider.min_value = 0.0
	timeline_slider.max_value = 0.0
	timeline_slider.step = 1.0
	timeline_slider.tick_count = 1
	timeline_slider.ticks_on_borders = true
	timeline_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_slider.custom_minimum_size = Vector2(200, 22)
	timeline_slider.focus_mode = Control.FOCUS_NONE
	timeline_slider.value_changed.connect(_on_timeline_scrub)

	slider_col.add_child(label_row)
	slider_col.add_child(timeline_slider)

	time_machine_controls.add_child(_btn_time_back)
	time_machine_controls.add_child(slider_col)
	time_machine_controls.add_child(_btn_time_forward)

	var sleep_btn := bar.get_node_or_null("Sleep_Button")
	var insert_idx := sleep_btn.get_index() if sleep_btn else bar.get_child_count()
	bar.add_child(time_machine_controls)
	bar.move_child(time_machine_controls, insert_idx)


func update_time_machine_slider(max_index: int, current_index: int, turn_number: int = -1) -> void:
	if not is_instance_valid(timeline_slider):
		return
	_time_machine_slider_syncing = true
	timeline_slider.max_value = maxf(0.0, float(max_index))
	timeline_slider.tick_count = int(timeline_slider.max_value) + 1
	timeline_slider.value = clampf(float(current_index), timeline_slider.min_value, timeline_slider.max_value)
	_time_machine_slider_syncing = false
	if turn_number < 0:
		turn_number = FarmDataManager.get_turn_at_history_index(current_index)
	if is_instance_valid(timeline_turn_label):
		var day_txt := "Day %d" % turn_number
		if FarmDataManager.is_timeline_draft_pending():
			day_txt += " · draft"
		timeline_turn_label.text = day_txt
	if is_instance_valid(timeline_index_label):
		timeline_index_label.text = "%d / %d" % [current_index + 1, max_index + 1]
	if is_instance_valid(_btn_time_back):
		_btn_time_back.disabled = current_index <= 0
	if is_instance_valid(_btn_time_forward):
		_btn_time_forward.disabled = (
			current_index >= max_index or not FarmDataManager.can_scrub_timeline_forward()
		)


func _on_timeline_scrub(value: float) -> void:
	if _time_machine_slider_syncing:
		return
	var map := get_tree().get_first_node_in_group("map") as Node
	if map and map.has_method("_on_timeline_scrub"):
		map._on_timeline_scrub(int(value))


func _on_time_machine_back() -> void:
	if not is_instance_valid(timeline_slider):
		return
	timeline_slider.value = maxf(timeline_slider.min_value, timeline_slider.value - 1.0)


func _on_time_machine_forward() -> void:
	if not is_instance_valid(timeline_slider):
		return
	timeline_slider.value = minf(timeline_slider.max_value, timeline_slider.value + 1.0)


func _configure_menu_popup_on_top(menu_btn: MenuButton) -> void:
	if menu_btn == null:
		return
	var popup := menu_btn.get_popup()
	if popup == null:
		return
	popup.transparent = true
	popup.set_flag(Window.FLAG_ALWAYS_ON_TOP, true)
	if not menu_btn.about_to_popup.is_connected(_on_toolbar_menu_about_to_popup.bind(menu_btn)):
		menu_btn.about_to_popup.connect(_on_toolbar_menu_about_to_popup.bind(menu_btn))


func _on_toolbar_menu_about_to_popup(menu_btn: MenuButton) -> void:
	_raise_hud_chrome()
	var menu_popup := menu_btn.get_popup() if menu_btn else null
	if menu_popup:
		menu_popup.set_flag(Window.FLAG_ALWAYS_ON_TOP, true)


func _setup_sidebar_drag_controller() -> void:
	if is_instance_valid(_sidebar_drag):
		return
	_sidebar_drag = UISidebarDragController.new()
	_sidebar_drag.name = "SidebarDragController"
	_sidebar_drag.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sidebar_drag)
	_sidebar_drag.setup(left_sidebar_dock, right_sidebar_dock, $CanvasLayer)


func _mount_panels_into_sidebars() -> void:
	_dock_panel_to_sidebar(workers_window, UISidebarDock.DockSide.LEFT, "Farm Hands", 0)
	if MetaManager.dev_mode and is_instance_valid(dev_panel):
		_dock_panel_to_sidebar(dev_panel, UISidebarDock.DockSide.LEFT, "Dev Console", 1)
	_dock_panel_to_sidebar(inspector_panel, UISidebarDock.DockSide.RIGHT, "Tile Inspector", 0)
	_dock_panel_to_sidebar(weather_dock, UISidebarDock.DockSide.RIGHT, "Weather", 1)
	_dock_panel_to_sidebar(calendar_dock, UISidebarDock.DockSide.RIGHT, "Calendar", 2)
	_dock_panel_to_sidebar(info_dock_panel, UISidebarDock.DockSide.RIGHT, "Farm Dashboard", 3)
	_dock_panel_to_sidebar(minimap_panel, UISidebarDock.DockSide.RIGHT, "Ecology Scanner", 4)
	_dock_panel_to_sidebar(queue_panel, UISidebarDock.DockSide.RIGHT, "Today's Plan", 5)

	# Civ-style edge tabs: panels start collapsed to symbols; clicking pops them out.
	_setup_edge_tab_strips()
	_register_edge_tab(workers_window, "👥", "Farm Hands", UISidebarDock.DockSide.LEFT, "farm_hands")
	if MetaManager.dev_mode and is_instance_valid(dev_panel):
		_register_edge_tab(dev_panel, "🛠", "Dev Console", UISidebarDock.DockSide.LEFT, "dev_console")
	_register_edge_tab(inspector_panel, "🔍", "Tile Inspector", UISidebarDock.DockSide.RIGHT, "tile_inspector")
	_register_edge_tab(weather_dock, "🌦️", "Weather Forecast", UISidebarDock.DockSide.RIGHT)
	_register_edge_tab(calendar_dock, "📅", "Calendar", UISidebarDock.DockSide.RIGHT)
	_register_edge_tab(info_dock_panel, "📋", "Farm Dashboard", UISidebarDock.DockSide.RIGHT)
	_register_edge_tab(minimap_panel, "🗺", "Ecology Scanner", UISidebarDock.DockSide.RIGHT, "ecology_scanner")
	_register_edge_tab(queue_panel, "📝", "Today's Plan", UISidebarDock.DockSide.RIGHT, "todays_plan")
	_finalize_edge_tab_strips()

	# Everything collapsed by default — maximum playfield, Civ-style.
	_set_sidebar_panel_visible(workers_window, false)
	if is_instance_valid(dev_panel):
		_set_sidebar_panel_visible(dev_panel, false)
	_set_sidebar_panel_visible(info_dock_panel, false)
	_set_sidebar_panel_visible(weather_dock, false)
	_set_sidebar_panel_visible(calendar_dock, false)
	_set_sidebar_panel_visible(inspector_panel, false)
	_set_sidebar_panel_visible(minimap_panel, false)
	_set_sidebar_panel_visible(queue_panel, false)
	_layout_sidebar_docks()
	_setup_sidebar_drag_controller()


func _dock_panel_to_sidebar(
	panel: Control,
	side: UISidebarDock.DockSide,
	title: String,
	order: int = -1
) -> void:
	if not is_instance_valid(panel):
		return
	var dock := left_sidebar_dock if side == UISidebarDock.DockSide.LEFT else right_sidebar_dock
	if not is_instance_valid(dock):
		return
	_strip_floating_chrome(panel)
	if panel is PanelContainer:
		var inner := StyleBoxFlat.new()
		inner.bg_color = Color(0, 0, 0, 0)
		inner.set_border_width_all(0)
		(panel as PanelContainer).add_theme_stylebox_override("panel", inner)
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = UISidebarDock.WIDTH - 48

	var widget := UISidebarWidget.new()
	widget.set_title(title)
	widget.mount_content(panel)
	dock.add_widget(widget, order)
	_panel_sidebar_widgets[panel] = widget
	widget.close_requested.connect(func() -> void: _set_sidebar_panel_visible(panel, false))


func _strip_floating_chrome(panel: Control) -> void:
	for child in panel.get_children():
		if child is PanelDragger or child is PanelResizer:
			child.queue_free()


func _toggle_sidebar_panel(panel: Control) -> void:
	_toggle_sidebar_panel_with_focus(panel, UISidebarDock.DockSide.RIGHT)


func _toggle_sidebar_panel_with_focus(panel: Control, side: UISidebarDock.DockSide) -> void:
	if not is_instance_valid(panel):
		return
	var widget: UISidebarWidget = _panel_sidebar_widgets.get(panel, null)
	var is_visible := widget.visible if widget else panel.visible
	if is_visible:
		_set_sidebar_panel_visible(panel, false)
	else:
		_focus_sidebar_panel(panel, side)


func _focus_sidebar_panel(panel: Control, side: UISidebarDock.DockSide) -> void:
	if not is_instance_valid(panel):
		return
	if not _panel_sidebar_widgets.has(panel):
		push_warning("HUD: panel not in sidebar — cannot focus: %s" % panel.name)
		return
	_set_sidebar_panel_visible(panel, true)
	var widget: UISidebarWidget = _panel_sidebar_widgets[panel]
	var dock := left_sidebar_dock if side == UISidebarDock.DockSide.LEFT else right_sidebar_dock
	if widget.get_parent() != dock.get_stack():
		if widget.get_parent():
			widget.get_parent().remove_child(widget)
		dock.get_stack().add_child(widget)
	dock.scroll_to_widget(widget)
	widget.play_attention_flash()


func _set_sidebar_panel_visible(panel: Control, show: bool) -> void:
	if not is_instance_valid(panel):
		return
	if show and panel == calendar_dock:
		_reset_calendar_view_to_present()
		refresh_calendar_dock()
	var widget: UISidebarWidget = _panel_sidebar_widgets.get(panel, null)
	if widget:
		widget.visible = show
	panel.visible = show
	var tab: Button = _edge_tabs.get(panel, null)
	if is_instance_valid(tab):
		tab.set_pressed_no_signal(show)
		_apply_edge_tab_style(tab, show)
	var side: Variant = _panel_dock_side.get(panel, null)
	if side != null:
		_refresh_edge_strip_ui(side as UISidebarDock.DockSide)
	_refresh_dock_slides()


# ============================================================
# CIV-STYLE EDGE TABS — collapsed symbols that pop panels out
# ============================================================

func _setup_edge_tab_strips() -> void:
	for side in [UISidebarDock.DockSide.LEFT, UISidebarDock.DockSide.RIGHT]:
		var strip := VBoxContainer.new()
		strip.name = "EdgeTabsLeft" if side == UISidebarDock.DockSide.LEFT else "EdgeTabsRight"
		strip.add_theme_constant_override("separation", 6)
		$CanvasLayer.add_child(strip)
		strip.z_index = Z_SIDEBAR + 1
		_edge_tab_strips[side] = strip
	_layout_edge_tab_strips()


func _layout_edge_tab_strips() -> void:
	var vp := get_viewport_rect().size
	for side in _edge_tab_strips:
		var strip: VBoxContainer = _edge_tab_strips[side]
		if not is_instance_valid(strip):
			continue
		strip.reset_size()
		var y := (vp.y - strip.size.y) / 2.0
		if side == UISidebarDock.DockSide.LEFT:
			strip.position = Vector2(2.0, y)
		else:
			strip.position = Vector2(vp.x - strip.size.x - 2.0, y)


func _edge_tab_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.11, 0.92)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	if selected:
		sb.set_border_width_all(3)
		sb.border_color = EDGE_TAB_YELLOW
	else:
		sb.set_border_width_all(1)
		sb.border_color = Color(0.35, 0.38, 0.32, 0.65)
	return sb


func _apply_edge_tab_style(btn: Button, selected: bool) -> void:
	var sb := _edge_tab_style(selected)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("focus", sb)


func _side_has_open_panel(side: UISidebarDock.DockSide) -> bool:
	for panel in _edge_tabs:
		if _panel_dock_side.get(panel) != side:
			continue
		var tab: Button = _edge_tabs[panel]
		if is_instance_valid(tab) and tab.button_pressed:
			return true
	return false


func _refresh_edge_strip_ui(side: UISidebarDock.DockSide) -> void:
	for panel in _edge_tabs:
		if _panel_dock_side.get(panel) != side:
			continue
		var tab: Button = _edge_tabs[panel]
		if is_instance_valid(tab):
			_apply_edge_tab_style(tab, tab.button_pressed)
	var close_btn: Button = _edge_close_btns.get(side, null)
	if is_instance_valid(close_btn):
		close_btn.visible = _side_has_open_panel(side)


func _close_all_on_side(side: UISidebarDock.DockSide) -> void:
	for panel in _edge_tabs.duplicate():
		if _panel_dock_side.get(panel) == side:
			_set_sidebar_panel_visible(panel, false)


func _finalize_edge_tab_strips() -> void:
	for side in _edge_tab_strips:
		var strip: VBoxContainer = _edge_tab_strips[side]
		if not is_instance_valid(strip) or _edge_close_btns.has(side):
			continue
		var close_btn := Button.new()
		close_btn.name = "CloseAll"
		close_btn.text = "×"
		close_btn.tooltip_text = "Close all panels on this side"
		close_btn.focus_mode = Control.FOCUS_NONE
		close_btn.custom_minimum_size = Vector2(EDGE_TAB_W, 32.0)
		close_btn.add_theme_font_size_override("font_size", 20)
		close_btn.add_theme_color_override("font_color", EDGE_TAB_YELLOW)
		var close_sb := StyleBoxFlat.new()
		close_sb.bg_color = Color(0.1, 0.1, 0.1, 0.85)
		close_sb.set_corner_radius_all(4)
		close_sb.set_border_width_all(1)
		close_sb.border_color = Color(0.45, 0.45, 0.4, 0.8)
		close_btn.add_theme_stylebox_override("normal", close_sb)
		close_btn.add_theme_stylebox_override("hover", close_sb)
		close_btn.add_theme_stylebox_override("pressed", close_sb)
		close_btn.visible = false
		close_btn.pressed.connect(_close_all_on_side.bind(side))
		MapScrollBlockerUtil.tag_control_tree(close_btn)
		strip.add_child(close_btn)
		_edge_close_btns[side] = close_btn
	_layout_edge_tab_strips()


func _register_edge_tab(
	panel: Control,
	glyph: String,
	title: String,
	side: UISidebarDock.DockSide,
	icon_key: String = ""
) -> void:
	if not is_instance_valid(panel) or _edge_tabs.has(panel):
		return
	var strip: VBoxContainer = _edge_tab_strips.get(side, null)
	if strip == null:
		return
	var btn := Button.new()
	btn.tooltip_text = title
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(EDGE_TAB_W, EDGE_TAB_W)
	var has_icon := icon_key != "" and HudIcons.apply_button_icon(
		btn, icon_key, "", HudIcons.EDGE_TAB_ICON_PX
	)
	if not has_icon:
		btn.text = glyph
		btn.add_theme_font_size_override("font_size", 22)
	_apply_edge_tab_style(btn, false)
	btn.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_focus_sidebar_panel(panel, side)
		else:
			_set_sidebar_panel_visible(panel, false)
	)
	MapScrollBlockerUtil.tag_control_tree(btn)
	strip.add_child(btn)
	_edge_tabs[panel] = btn
	_panel_dock_side[panel] = side
	_layout_edge_tab_strips()


func _dock_has_visible_widget(dock: UISidebarDock) -> bool:
	if not is_instance_valid(dock):
		return false
	for child in dock.get_stack().get_children():
		if child is UISidebarWidget and (child as Control).visible:
			return true
	return false


func _refresh_dock_slides() -> void:
	_slide_dock(left_sidebar_dock, _dock_has_visible_widget(left_sidebar_dock), true)
	_slide_dock(right_sidebar_dock, _dock_has_visible_widget(right_sidebar_dock), false)


## Slide the dock out from behind its edge tabs (show) or tuck it away (hide).
func _slide_dock(dock: UISidebarDock, show: bool, from_left: bool) -> void:
	if not is_instance_valid(dock):
		return
	if bool(_dock_open.get(dock, false)) == show:
		return
	_dock_open[dock] = show
	var w := float(UISidebarDock.WIDTH)
	var shown_l := EDGE_TAB_W if from_left else -(EDGE_TAB_W + w)
	var shown_r := (EDGE_TAB_W + w) if from_left else -EDGE_TAB_W
	var dir := -1.0 if from_left else 1.0
	var hidden_l := shown_l + dir * w
	var hidden_r := shown_r + dir * w

	var old: Tween = _dock_slide_tweens.get(dock, null)
	if old and old.is_valid():
		old.kill()
	var tween := create_tween().set_parallel(true)
	if show:
		dock.visible = true
		dock.offset_left = hidden_l
		dock.offset_right = hidden_r
		tween.tween_property(dock, "offset_left", shown_l, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(dock, "offset_right", shown_r, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(dock, "offset_left", hidden_l, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(dock, "offset_right", hidden_r, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(func() -> void:
			if not bool(_dock_open.get(dock, false)):
				dock.visible = false
		)
	_dock_slide_tweens[dock] = tween


# ============================================================
# QUICK-SELECT TOOL WHEEL (hold Tab on the map)
# ============================================================

func _setup_quick_wheel() -> void:
	quick_wheel = PanelContainer.new()
	quick_wheel.name = "QuickWheel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1, 0.96)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = Color("aed581")
	sb.set_content_margin_all(12)
	quick_wheel.add_theme_stylebox_override("panel", sb)
	quick_wheel.z_index = 200
	quick_wheel.hide()

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	quick_wheel.add_child(grid)

	for opt in [
		["inspect", "Inspect"],
		["rotovate", "Rotovate"],
		["water", "Watering Can"],
		["seeds", "Seed Picker"],
	]:
		var tool_id: String = opt[0]
		var btn := Button.new()
		btn.text = str(opt[1])
		btn.custom_minimum_size = Vector2(160, 90)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 20)
		btn.mouse_entered.connect(func() -> void: _quick_wheel_hover = tool_id)
		btn.mouse_exited.connect(func() -> void:
			if _quick_wheel_hover == tool_id:
				_quick_wheel_hover = ""
		)
		btn.pressed.connect(func() -> void: _select_quick_tool(tool_id))
		grid.add_child(btn)

	$CanvasLayer.add_child(quick_wheel)


## Pop the wheel centred on the cursor (clamped to the viewport).
func show_quick_wheel(screen_pos: Vector2) -> void:
	if not is_instance_valid(quick_wheel) or quick_wheel.visible:
		return
	_quick_wheel_hover = ""
	quick_wheel.reset_size()
	var vp := get_viewport_rect().size
	var half := quick_wheel.size / 2.0
	quick_wheel.position = Vector2(
		clampf(screen_pos.x - half.x, 8.0, maxf(8.0, vp.x - quick_wheel.size.x - 8.0)),
		clampf(screen_pos.y - half.y, 8.0, maxf(8.0, vp.y - quick_wheel.size.y - 8.0)),
	)
	quick_wheel.pivot_offset = half
	quick_wheel.scale = Vector2(0.85, 0.85)
	quick_wheel.show()
	var tween := create_tween()
	tween.tween_property(quick_wheel, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Tab released: equip whatever the cursor is over, otherwise just close.
func commit_quick_wheel() -> void:
	if not is_instance_valid(quick_wheel) or not quick_wheel.visible:
		return
	if _quick_wheel_hover != "":
		_select_quick_tool(_quick_wheel_hover)
	else:
		hide_quick_wheel()


func hide_quick_wheel() -> void:
	if is_instance_valid(quick_wheel):
		quick_wheel.hide()
	_quick_wheel_hover = ""


func _select_quick_tool(tool_id: String) -> void:
	quick_tool_selected.emit(tool_id)
	hide_quick_wheel()


## Ensure every PanelContainer gives its content at least 12px breathing room.
func _apply_panel_breathing_room() -> void:
	for node in find_children("*", "PanelContainer", true, false):
		var pc := node as PanelContainer
		if pc == null:
			continue
		var sb := pc.get_theme_stylebox("panel")
		if sb == null:
			continue
		var padded: StyleBox = sb.duplicate()
		padded.content_margin_left = maxf(padded.content_margin_left, 12.0)
		padded.content_margin_top = maxf(padded.content_margin_top, 12.0)
		padded.content_margin_right = maxf(padded.content_margin_right, 12.0)
		padded.content_margin_bottom = maxf(padded.content_margin_bottom, 12.0)
		pc.add_theme_stylebox_override("panel", padded)


func _organize_docks(_dragged_node: Node = null) -> void:
	# Panels live in fixed sidebars; legacy magnetic docking is disabled.
	return
	if not MetaManager.magnetic_docking:
		return
	kill_dock_tween()

	var screen_size = get_viewport_rect().size
	var left_thresh = screen_size.x * 0.35
	var right_thresh = screen_size.x * 0.65

	var zones := {"top_l": [], "mid_l": [], "bot_l": [], "top_r": [], "mid_r": [], "bot_r": []}

	for panel in dockable_panels:
		if not is_instance_valid(panel) or not panel.visible:
			continue
		var cx = panel.position.x + (panel.size.x / 2.0)
		var cy = panel.position.y + (panel.size.y / 2.0)
		var side = "l" if cx < left_thresh else ("r" if cx > right_thresh else "float")
		if side == "float":
			continue

		var v_zone = "top"
		if cy > screen_size.y * 0.66:
			v_zone = "bot"
		elif cy > screen_size.y * 0.33:
			v_zone = "mid"
		zones[v_zone + "_" + side].append(panel)

	for key in zones:
		zones[key].sort_custom(func(a, b): return a.position.y < b.position.y)

	_dock_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	var snap = func(p_array: Array, is_right: bool, start_y: float, dir: int):
		var cur_y = start_y
		for p in p_array:
			if p.name == "InfoDock":
				p.size.y = minf(600.0, screen_size.y - 180.0)

			var px = screen_size.x - p.size.x - 20.0 if is_right else 20.0
			var py = cur_y if dir > 0 else cur_y - p.size.y
			var target_pos = Vector2(px, py)

			if p.position.distance_to(target_pos) > 2.0:
				_dock_tween.tween_property(p, "position", target_pos, 0.35)
			cur_y += (p.size.y + 15) * dir

	snap.call(zones["top_l"], false, 60.0, 1)
	snap.call(zones["mid_l"], false, (screen_size.y / 2.0) - 100.0, 1)
	snap.call(zones["bot_l"], false, screen_size.y - 160.0, -1)

	snap.call(zones["top_r"], true, 60.0, 1)
	snap.call(zones["mid_r"], true, (screen_size.y / 2.0) - 100.0, 1)
	snap.call(zones["bot_r"], true, screen_size.y - 160.0, -1)


func kill_dock_tween() -> void:
	if _dock_tween and _dock_tween.is_valid():
		_dock_tween.kill()


func _clamp_node_to_screen(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var screen_size = get_viewport_rect().size
	var n_pos: Vector2
	var n_size: Vector2

	if node is Window:
		n_pos = Vector2(node.position)
		n_size = Vector2(node.size)
	elif node is Control:
		n_pos = node.position
		n_size = node.size
	else:
		return

	var new_x = clampf(n_pos.x, 0.0, maxf(0.0, screen_size.x - n_size.x))
	var new_y = clampf(n_pos.y, 0.0, maxf(0.0, screen_size.y - n_size.y))

	if node is Window:
		node.position = Vector2i(roundi(new_x), roundi(new_y))
	elif node is Control:
		node.position = Vector2(new_x, new_y)


class PanelDragger extends Node:
	signal drag_ended(dragged_panel: Node)

	var target_panel: Control
	var target_window: Window
	var _use_window: bool = false
	var is_pressing: bool = false
	var is_dragging: bool = false
	var hold_timer: float = 0.0

	func _init(panel: Node) -> void:
		if panel is Window:
			_use_window = true
			target_window = panel as Window
			target_window.window_input.connect(_on_gui_input)
		else:
			target_panel = panel as Control
			target_panel.gui_input.connect(_on_gui_input)
		set_process(true)

	func _process(delta: float) -> void:
		if is_pressing and not is_dragging:
			hold_timer += delta
			if hold_timer > 0.15:
				is_dragging = true
				if not _use_window:
					target_panel.mouse_default_cursor_shape = Control.CURSOR_DRAG

	func _on_gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_pressing = true
				hold_timer = 0.0

				# Kill active tweens so magnetism doesn't fight the drag
				var node_ref: Node = (target_window as Node) if _use_window else (target_panel as Node)
				var map = node_ref.get_tree().get_first_node_in_group("map")
				if map and map.get("hud_instance") and map.hud_instance.has_method("kill_dock_tween"):
					map.hud_instance.kill_dock_tween()

				# --- BRING PANEL TO FRONT ---
				var bring: Node
				if _use_window:
					bring = target_window
				else:
					bring = target_panel
				var parent = bring.get_parent()
				if parent:
					parent.move_child(bring, -1)

			else:
				is_pressing = false
				if not _use_window:
					target_panel.mouse_default_cursor_shape = Control.CURSOR_ARROW
				if is_dragging:
					is_dragging = false
					var dragged_node: Node = (target_window as Node) if _use_window else (target_panel as Node)
					drag_ended.emit(dragged_node)

		elif event is InputEventMouseMotion and is_dragging:
			if _use_window:
				target_window.position += Vector2i(roundi(event.relative.x), roundi(event.relative.y))
			else:
				target_panel.position += event.relative


class PanelResizer extends Control:
	signal resize_ended(dragged_node: Node)
	var target: Control
	var is_resizing: bool = false

	func _init(p_target: Control) -> void:
		target = p_target
		custom_minimum_size = Vector2(24, 24)
		mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		top_level = true
		target.resized.connect(_align)
		target.item_rect_changed.connect(_align)
		target.visibility_changed.connect(_align)

	func _enter_tree() -> void:
		call_deferred("_align")

	func _align() -> void:
		if not is_instance_valid(target):
			return
		visible = target.visible
		position = target.global_position + target.size - custom_minimum_size

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			is_resizing = event.pressed
			if is_resizing:
				var map = target.get_tree().get_first_node_in_group("map")
				if map and map.get("hud_instance") and map.hud_instance.has_method("kill_dock_tween"):
					map.hud_instance.kill_dock_tween()
				var parent = target.get_parent()
				if parent:
					parent.move_child(target, -1)
			else:
				resize_ended.emit(target)
			accept_event()
		elif event is InputEventMouseMotion and is_resizing:
			target.custom_minimum_size += event.relative
			target.size = target.custom_minimum_size
			_align()
			accept_event()

	func _draw() -> void:
		var c = Color(1, 1, 1, 0.4)
		var s = size
		draw_line(Vector2(s.x - 16, s.y - 2), Vector2(s.x - 2, s.y - 16), c, 2)
		draw_line(Vector2(s.x - 10, s.y - 2), Vector2(s.x - 2, s.y - 10), c, 2)
		draw_line(Vector2(s.x - 4, s.y - 2), Vector2(s.x - 2, s.y - 4), c, 2)
