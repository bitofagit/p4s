extends PanelContainer

var title_label: Label
var text_label: RichTextLabel
var button_container: VBoxContainer
var image_rect: ColorRect

signal option_selected(option_id: String)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Runs while game is paused
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 300
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.02, 0.02, 0.04, 0.95)
	add_theme_stylebox_override("panel", bg_style)

	var center = CenterContainer.new()
	add_child(center)

	var main_panel = PanelContainer.new()
	main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color(0.1, 0.1, 0.12, 1.0)
	border_style.set_border_width_all(2)
	border_style.border_color = Color("aed581")
	main_panel.add_theme_stylebox_override("panel", border_style)
	center.add_child(main_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	main_panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 30)
	margin.add_child(hbox)

	# --- LEFT SIDE: IMAGE PLACEHOLDER ---
	image_rect = ColorRect.new()
	image_rect.custom_minimum_size = Vector2(250, 250)
	image_rect.color = Color(0.2, 0.2, 0.25)
	hbox.add_child(image_rect)

	var img_label = Label.new()
	img_label.text = "[ PIXEL ART\nPLACEHOLDER ]"
	img_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	img_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	img_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	img_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	image_rect.add_child(img_label)

	# --- RIGHT SIDE: TEXT & BUTTONS ---
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(400, 0)
	vbox.add_theme_constant_override("separation", 20)
	hbox.add_child(vbox)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color("aed581"))
	vbox.add_child(title_label)

	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	vbox.add_child(text_label)

	button_container = VBoxContainer.new()
	button_container.add_theme_constant_override("separation", 10)
	vbox.add_child(button_container)

	hide()


func show_dialogue(title: String, text: String, options: Dictionary, _image_path: String = "") -> void:
	title_label.text = title
	text_label.text = text

	# Clear old buttons
	for child in button_container.get_children():
		child.queue_free()

	for opt_id in options.keys():
		var btn = Button.new()
		btn.text = str(options[opt_id])
		var captured_id: String = str(opt_id)
		btn.pressed.connect(func():
			option_selected.emit(captured_id)
		)
		button_container.add_child(btn)

	# FAILSAFE: If the CSV parsing failed and generated no options, force a continue button
	if button_container.get_child_count() == 0:
		var fallback = Button.new()
		fallback.text = "Continue"
		fallback.pressed.connect(func(): option_selected.emit("continue"))
		button_container.add_child(fallback)

	get_tree().paused = true
	show()
