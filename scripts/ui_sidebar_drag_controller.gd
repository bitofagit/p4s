extends Node
class_name UISidebarDragController

## Shared drag-reorder across left/right sidebars: ghost preview, gap placeholder, smooth nudge.

const GHOST_MODULATE := Color(1, 1, 1, 0.88)
const PLACEHOLDER_COLOR := Color(0.67, 0.81, 0.72, 0.35)

var _left: UISidebarDock
var _right: UISidebarDock
var _layer: CanvasLayer

var _widget: UISidebarWidget = null
var _ghost: PanelContainer = null
var _placeholder: Control = null
var _source_dock: UISidebarDock = null
var _drag_offset := Vector2.ZERO
var _dragging := false


func setup(left_dock: UISidebarDock, right_dock: UISidebarDock, canvas_layer: CanvasLayer) -> void:
	_left = left_dock
	_right = right_dock
	_layer = canvas_layer
	_left.widget_drag_started.connect(_on_widget_drag_started)
	_right.widget_drag_started.connect(_on_widget_drag_started)


func _process(_delta: float) -> void:
	if not _dragging:
		return
	if not is_instance_valid(_widget):
		_end_drag()
		return
	var mouse := _layer.get_viewport().get_mouse_position()
	if is_instance_valid(_ghost):
		_ghost.global_position = mouse - _drag_offset
	_update_placeholder(mouse)


func _on_widget_drag_started(widget: UISidebarWidget) -> void:
	if _dragging:
		_end_drag()
	begin_drag(widget)


func begin_drag(widget: UISidebarWidget) -> void:
	if not is_instance_valid(widget):
		return
	_widget = widget
	_source_dock = _dock_holding_widget(widget)
	if _source_dock == null:
		return
	_source_dock.unregister_widget(widget)
	_dragging = true
	var mouse := _layer.get_viewport().get_mouse_position()
	_drag_offset = mouse - widget.global_position
	_build_ghost(widget)
	_build_placeholder(widget)
	widget.set_drag_visual_active(true)


func _build_ghost(widget: UISidebarWidget) -> void:
	_teardown_ghost()
	_ghost = PanelContainer.new()
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.z_index = 450
	_ghost.modulate = GHOST_MODULATE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.22, 0.19, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.67, 0.81, 0.72, 1)
	style.set_corner_radius_all(8)
	style.shadow_size = 10
	style.shadow_color = Color(0, 0, 0, 0.45)
	_ghost.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = "  %s  " % widget.get_title()
	lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 0.9))
	lbl.add_theme_font_size_override("font_size", 15)
	_ghost.add_child(lbl)
	_ghost.custom_minimum_size = Vector2(widget.size.x, maxf(48.0, widget.size.y * 0.35))
	_layer.add_child(_ghost)
	_ghost.global_position = widget.global_position


func _build_placeholder(widget: UISidebarWidget) -> void:
	_teardown_placeholder()
	_placeholder = PanelContainer.new()
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.custom_minimum_size = Vector2(widget.size.x, maxf(56.0, widget.size.y))
	var place_style := StyleBoxFlat.new()
	place_style.bg_color = PLACEHOLDER_COLOR
	place_style.set_border_width_all(2)
	place_style.border_color = Color(1, 0.92, 0.25, 0.85)
	place_style.set_corner_radius_all(6)
	(_placeholder as PanelContainer).add_theme_stylebox_override("panel", place_style)
	var dock := _source_dock
	var idx := 0
	if widget.is_inside_tree() and widget.get_parent() == dock.get_stack():
		idx = widget.get_index()
		widget.get_parent().remove_child(widget)
	dock.insert_placeholder(_placeholder, idx)


func _update_placeholder(mouse: Vector2) -> void:
	var dock := _pick_dock(mouse)
	if dock == null or not is_instance_valid(_placeholder):
		return
	var idx := dock.find_insert_index_for_global_y(mouse.y)
	if _placeholder.get_parent() != dock.get_stack():
		var old_parent := _placeholder.get_parent()
		if old_parent:
			old_parent.remove_child(_placeholder)
		dock.insert_placeholder(_placeholder, idx)
	else:
		dock.insert_placeholder(_placeholder, idx)


func _pick_dock(mouse: Vector2) -> UISidebarDock:
	if is_instance_valid(_left) and _left.get_global_rect().has_point(mouse):
		return _left
	if is_instance_valid(_right) and _right.get_global_rect().has_point(mouse):
		return _right
	var mid := _layer.get_viewport().get_visible_rect().size.x * 0.5
	return _left if mouse.x < mid else _right


func _end_drag() -> void:
	if not _dragging:
		return
	var mouse := _layer.get_viewport().get_mouse_position()
	var target_dock := _pick_dock(mouse)
	var drop_index := 0
	if is_instance_valid(_placeholder) and is_instance_valid(_placeholder.get_parent()):
		drop_index = _placeholder.get_index()
	elif target_dock:
		drop_index = target_dock.find_insert_index_for_global_y(mouse.y)
	_teardown_placeholder()
	if target_dock and is_instance_valid(_widget):
		target_dock.finalize_widget_drop(_widget, drop_index)
		if is_instance_valid(_widget):
			_widget.set_drag_visual_active(false)
	_teardown_ghost()
	_widget = null
	_source_dock = null
	_dragging = false


func _dock_holding_widget(widget: UISidebarWidget) -> UISidebarDock:
	if is_instance_valid(_left) and widget.get_parent() == _left.get_stack():
		return _left
	if is_instance_valid(_right) and widget.get_parent() == _right.get_stack():
		return _right
	return null


func _teardown_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null


func _teardown_placeholder() -> void:
	if is_instance_valid(_placeholder):
		_placeholder.queue_free()
	_placeholder = null


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_end_drag()
			UIInputUtil.safe_set_input_handled(self)
