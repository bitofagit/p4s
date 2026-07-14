@tool
extends EditorScript

const Baker := preload("res://scripts/tools/flora_lod_atlas_baker.gd")

## Editor: File → Run to bake low-res flora LOD atlases into assets/base/sprites/atlas/lod/
## Run bake_flora_atlas.gd first if flora_atlas.png is missing.


func _run() -> void:
	var result := Baker.bake()
	if not bool(result.get("ok", false)):
		push_error("Flora LOD atlas bake failed.")
	else:
		print("Flora LOD atlas bake complete.")
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.scan()
