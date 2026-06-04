extends RefCounted
class_name MapScrollBlockerUtil

## Returns true when the pointer is over UI that must consume wheel / trackpad (not the map camera).


static func should_block_map_scroll(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var hovered: Control = viewport.gui_get_hovered_control()
	while is_instance_valid(hovered):
		if hovered.is_in_group("map_scroll_blocker"):
			return true
		var parent := hovered.get_parent()
		if parent is Control:
			hovered = parent as Control
		else:
			break
	var mouse := viewport.get_mouse_position()
	for node in viewport.get_tree().get_nodes_in_group("map_scroll_blocker"):
		if node is Control:
			var ctrl := node as Control
			if not ctrl.is_visible_in_tree():
				continue
			if ctrl.get_global_rect().has_point(mouse):
				return true
	return false


static func tag_control_tree(root: Control) -> void:
	if not is_instance_valid(root):
		return
	root.add_to_group("map_scroll_blocker")
	for child in root.get_children():
		if child is Control:
			tag_control_tree(child as Control)
