extends SceneTree

const Baker := preload("res://scripts/tools/flora_atlas_baker.gd")

func _initialize() -> void:
	Baker.bake()
	quit()
