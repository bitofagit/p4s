extends PanelContainer
class_name UISidebarWidget

## Stitch-style dock widget: drag handle reorder, title, close, scroll-safe body slot.

signal close_requested
signal reorder_drag_started
signal reorder_drag_ended
signal drag_handle_pressed(widget: UISidebarWidget)

const COLOR_PANEL := Color(0.16, 0.17, 0.15, 0.92)
const COLOR_BORDER := Color(0.26, 0.28, 0.26, 0.55)
const COLOR_HEADER := Color(0.89, 0.89, 0.87)
const COLOR_MUTED := Color(0.76, 0.78, 0.76)
const COLOR_FLASH := Color(1.0, 0.92, 0.2, 1.0)

var _body: MarginContainer
var _title_label: Label
var _content_parent: Control
var _base_style: StyleBoxFlat
var _flash_tween: Tween
var _dragging_visual := false


func _init() -> void:
	MapScrollBlockerUtil.tag_control_tree(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(288, 120)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_base_style = StyleBoxFlat.new()
	_base_style.bg_color = COLOR_PANEL
	_base_style.set_border_width_all(1)
	_base_style.border_color = COLOR_BORDER
	_base_style.set_corner_radius_all(8)
	_base_style.content_margin_left = 12
	_base_style.content_margin_right = 12
	_base_style.content_margin_top = 10
	_base_style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", _base_style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(header)

	var drag := Label.new()
	drag.text = "⠿"
	drag.tooltip_text = "Drag to reorder (drop on left or right rail)"
	drag.mouse_default_cursor_shape = Control.CURSOR_DRAG
	drag.add_theme_color_override("font_color", COLOR_MUTED)
	drag.add_theme_font_size_override("font_size", 16)
	drag.mouse_filter = Control.MOUSE_FILTER_STOP
	drag.gui_input.connect(_on_drag_handle_input)
	header.add_child(drag)

	_title_label = Label.new()
	_title_label.text = "Panel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", COLOR_HEADER)
	_title_label.add_theme_font_size_override("font_size", 16)
	header.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_color_override("font_color", COLOR_MUTED)
	close_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.35, 0.3))
	close_btn.pressed.connect(func() -> void:
		visible = false
		close_requested.emit()
	)
	header.add_child(close_btn)

	_body = MarginContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(_body)

	_content_parent = VBoxContainer.new()
	_content_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_content_parent)


func set_title(title: String) -> void:
	_title_label.text = title


func get_title() -> String:
	return _title_label.text


func mount_content(node: Control) -> void:
	for child in _content_parent.get_children():
		child.queue_free()
	if node.get_parent():
		node.get_parent().remove_child(node)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_content_parent.add_child(node)
	MapScrollBlockerUtil.tag_control_tree(node)


func get_mounted_content() -> Control:
	if _content_parent.get_child_count() > 0:
		return _content_parent.get_child(0) as Control
	return null


func set_drag_visual_active(active: bool) -> void:
	_dragging_visual = active
	if active:
		modulate = Color(1, 1, 1, 0.25)
	else:
		modulate = Color.WHITE
		visible = true


func play_attention_flash(duration: float = 1.0) -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	var flash_style := _base_style.duplicate() as StyleBoxFlat
	flash_style.border_color = COLOR_FLASH
	flash_style.set_border_width_all(3)
	add_theme_stylebox_override("panel", flash_style)
	_flash_tween = create_tween()
	_flash_tween.tween_interval(duration * 0.55)
	_flash_tween.tween_method(_apply_flash_border_width, 3.0, 0.0, duration * 0.45)
	_flash_tween.tween_callback(func() -> void: add_theme_stylebox_override("panel", _base_style))


func _apply_flash_border_width(width: float) -> void:
	var s := get_theme_stylebox("panel")
	if s is StyleBoxFlat:
		var flat := s.duplicate() as StyleBoxFlat
		flat.set_border_width_all(int(roundi(width)))
		if width > 0.1:
			flat.border_color = COLOR_FLASH
		add_theme_stylebox_override("panel", flat)


func _on_drag_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				drag_handle_pressed.emit(self)
				reorder_drag_started.emit()
				UIInputUtil.safe_set_input_handled(self)
			else:
				reorder_drag_ended.emit()


func _gui_input(event: InputEvent) -> void:
	_consume_scroll_wheel(event)


func _consume_scroll_wheel(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [
			MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT,
			MOUSE_BUTTON_WHEEL_RIGHT,
		]:
			accept_event()
			UIInputUtil.safe_set_input_handled(self)
