extends SceneTree

## Headless CLI: bake low-res flora LOD atlases.
##   godot --headless --path . --script res://scripts/tools/run_flora_lod_bake.gd


func _initialize() -> void:
	var Baker := preload("res://scripts/tools/flora_lod_atlas_baker.gd")
	var result: Dictionary = Baker.bake()
	if not bool(result.get("ok", false)):
		push_error("Flora LOD bake failed.")
		quit(1)
	else:
		quit(0)
