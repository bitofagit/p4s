@tool
extends EditorScript

const Baker := preload("res://scripts/tools/flora_atlas_baker.gd")

## Editor: File → Run to rebake flora_atlas.png and flora_atlas_map.json.

func _run() -> void:
	Baker.bake()
