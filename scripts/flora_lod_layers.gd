extends Node2D
class_name FloraLodLayers

## Far-zoom flora via low-res atlas TileMapLayers (baked by bake_flora_lod_atlas.gd).
## Same grid coords as the full-res flora layers; visibility toggled by camera zoom.

const LAYER_KEYS: Array[String] = ["canopy", "understory", "ground"]
const LAYER_Z := {"canopy": 1, "understory": 2, "ground": 3}

var _mid_layers: Dictionary = {} # layer_key -> TileMapLayer
var _far_layers: Dictionary = {}
var _tile_sets: Dictionary = {} # tier_id -> TileSet
var _active_tier := "" # "", "mid", "far"


func setup(tile_sets: Dictionary, offsets: Dictionary, y_sort_origin: int) -> void:
	_tile_sets = tile_sets
	for tier_id in ["mid", "far"]:
		if not tile_sets.has(tier_id):
			continue
		var target: Dictionary = _mid_layers if tier_id == "mid" else _far_layers
		for layer_key in LAYER_KEYS:
			var node := TileMapLayer.new()
			node.name = "%sLod%sLayer" % [layer_key.capitalize(), tier_id.capitalize()]
			node.z_index = LAYER_Z.get(layer_key, 1)
			node.position = offsets.get(layer_key, Vector2.ZERO)
			node.y_sort_enabled = false
			node.y_sort_origin = y_sort_origin
			node.tile_set = tile_sets[tier_id]
			node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			node.rendering_quadrant_size = 32
			node.collision_enabled = false
			node.navigation_enabled = false
			node.visible = false
			add_child(node)
			target[layer_key] = node


func has_tiers() -> bool:
	return not _mid_layers.is_empty() or not _far_layers.is_empty()


var _show_ground := true
var _show_understory := true


func apply_layer_settings(show_ground: bool, show_understory: bool) -> void:
	_show_ground = show_ground
	_show_understory = show_understory
	set_lod_tier(_active_tier)


func set_lod_tier(tier_id: String) -> void:
	var want := tier_id if tier_id in ["mid", "far"] else ""
	if want == _active_tier:
		_sync_tier_visibility()
		return
	_active_tier = want
	_sync_tier_visibility()


func _sync_tier_visibility() -> void:
	for layer_key in LAYER_KEYS:
		var layer_on := true
		if layer_key == "ground":
			layer_on = _show_ground
		elif layer_key == "understory":
			layer_on = _show_understory
		var mid: TileMapLayer = _mid_layers.get(layer_key)
		var far: TileMapLayer = _far_layers.get(layer_key)
		if is_instance_valid(mid):
			mid.visible = _active_tier == "mid" and layer_on
		if is_instance_valid(far):
			far.visible = _active_tier == "far" and layer_on


func paint_cell(layer_key: String, pos: Vector2i, atlas_coord: Vector2i) -> void:
	for tier_id in ["mid", "far"]:
		var layers: Dictionary = _mid_layers if tier_id == "mid" else _far_layers
		var layer: TileMapLayer = layers.get(layer_key)
		if not is_instance_valid(layer):
			continue
		if atlas_coord.x >= 0:
			layer.set_cell(pos, 0, atlas_coord)
		else:
			layer.erase_cell(pos)


func erase_cell(layer_key: String, pos: Vector2i) -> void:
	for layers in [_mid_layers, _far_layers]:
		var layer: TileMapLayer = layers.get(layer_key)
		if is_instance_valid(layer):
			layer.erase_cell(pos)


func clear_all() -> void:
	for layers in [_mid_layers, _far_layers]:
		for layer_key in LAYER_KEYS:
			var layer: TileMapLayer = layers.get(layer_key)
			if is_instance_valid(layer):
				layer.clear()
	set_lod_tier("")
