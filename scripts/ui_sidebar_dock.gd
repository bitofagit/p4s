extends Control
class_name UISidebarDock

## Fixed-width scrollable sidebar for Stitch-style dock widgets (left or right).

signal widget_drag_started(widget: UISidebarWidget)

enum DockSide { LEFT, RIGHT }

const WIDTH := 320
const COLOR_RAIL := Color(0.102, 0.11, 0.098, 0.72)

var dock_side: DockSide = DockSide.LEFT

var _scroll: ScrollContainer
var _stack: VBoxContainer
var _widgets: Array[UISidebarWidget] = []


func _ready() -> void:
	MapScrollBlockerUtil.tag_control_tree(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

	var rail := PanelContainer.new()
	rail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rail.mouse_filter = Control.MOUSE_FILTER_STOP
	var rail_style := StyleBoxFlat.new()
	rail_style.bg_color = COLOR_RAIL
	rail_style.set_border_width_all(0)
	if dock_side == DockSide.LEFT:
		rail_style.border_width_right = 1
	else:
		rail_style.border_width_left = 1
	rail_style.border_color = Color(0.26, 0.28, 0.26, 0.35)
	rail.add_theme_stylebox_override("panel", rail_style)
	add_child(rail)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.mouse_filter = Control.MOUSE_FILTER_STOP
	rail.add_child(pad)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.gui_input.connect(_on_scroll_gui_input)
	pad.add_child(_scroll)

	_stack = VBoxContainer.new()
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.add_theme_constant_override("separation", 12)
	_stack.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_stack)


func get_stack() -> VBoxContainer:
	return _stack


func get_scroll() -> ScrollContainer:
	return _scroll


func add_widget(widget: UISidebarWidget, at_index: int = -1) -> void:
	if widget in _widgets:
		return
	_widgets.append(widget)
	widget.reorder_drag_ended.connect(_on_widget_reorder_ended)
	widget.drag_handle_pressed.connect(_on_widget_drag_handle_pressed)
	_insert_child_at(_stack, widget, at_index)


func _insert_child_at(parent: VBoxContainer, node: Control, at_index: int) -> void:
	if at_index < 0 or at_index >= parent.get_child_count():
		parent.add_child(node)
	else:
		parent.add_child(node)
		parent.move_child(node, at_index)


func insert_placeholder(placeholder: Control, at_index: int) -> void:
	if placeholder.get_parent() != _stack:
		if placeholder.get_parent():
			placeholder.get_parent().remove_child(placeholder)
		_insert_child_at(_stack, placeholder, at_index)
	elif placeholder.get_index() != at_index:
		_stack.move_child(placeholder, clampi(at_index, 0, _stack.get_child_count() - 1))


func find_insert_index_for_global_y(global_y: float) -> int:
	for i in range(_stack.get_child_count()):
		var child := _stack.get_child(i)
		if not child is Control:
			continue
		var rect := (child as Control).get_global_rect()
		if global_y < rect.position.y + rect.size.y * 0.5:
			return i
	return _stack.get_child_count()


func unregister_widget(widget: UISidebarWidget) -> void:
	_widgets.erase(widget)


func finalize_widget_drop(widget: UISidebarWidget, at_index: int) -> void:
	if not is_instance_valid(widget):
		return
	if widget.get_parent() != _stack:
		if widget.get_parent():
			widget.get_parent().remove_child(widget)
		_stack.add_child(widget)
	if not widget in _widgets:
		_widgets.append(widget)
	at_index = clampi(at_index, 0, maxi(0, _stack.get_child_count() - 1))
	_insert_child_at(_stack, widget, at_index)
	widget.visible = true
	_rebuild_widget_list()


func scroll_to_widget(widget: UISidebarWidget) -> void:
	if not is_instance_valid(widget) or not is_instance_valid(_scroll):
		return
	await get_tree().process_frame
	_scroll.ensure_control_visible(widget)


func get_widget_for_content(node: Control) -> UISidebarWidget:
	for w in _widgets:
		if not is_instance_valid(w):
			continue
		if w.get_mounted_content() == node:
			return w
	return null


func _on_widget_drag_handle_pressed(widget: UISidebarWidget) -> void:
	widget_drag_started.emit(widget)


func _on_widget_reorder_ended() -> void:
	_rebuild_widget_list()


func _rebuild_widget_list() -> void:
	_widgets.clear()
	for child in _stack.get_children():
		if child is UISidebarWidget:
			_widgets.append(child)


func _on_scroll_gui_input(event: InputEvent) -> void:
	_consume_scroll_wheel(event)


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
