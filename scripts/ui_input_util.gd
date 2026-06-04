extends RefCounted
class_name UIInputUtil


static func safe_set_input_handled(node: Node) -> void:
	if node == null:
		return
	var vp: Viewport = node.get_viewport()
	if vp:
		vp.set_input_as_handled()
