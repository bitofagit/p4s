extends Node2D
class_name FloraLodVector

## Far-zoom flora stand-in: flat vector shapes (cheaper than far LOD atlas tiles).
## Enabled via MetaManager.flora_vector_far_zoom when camera tier is "far".

const LAYER_SHAPES := {
	"canopy": {"radius": 38.0, "height": 72.0, "width": 56.0, "kind": "ellipse"},
	"understory": {"radius": 28.0, "height": 48.0, "width": 44.0, "kind": "rect"},
	"ground": {"radius": 18.0, "height": 28.0, "width": 32.0, "kind": "rect"},
}
const LAYER_Z := {"canopy": 1, "understory": 2, "ground": 3}

var _cells: Dictionary = {} # Vector2i -> Dictionary layer_key -> Color
var _show_ground := true
var _show_understory := true
var _active := false


func apply_layer_settings(show_ground: bool, show_understory: bool) -> void:
	_show_ground = show_ground
	_show_understory = show_understory
	queue_redraw()


func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	visible = active
	set_process(active)
	if active:
		queue_redraw()


func _process(_delta: float) -> void:
	if _active:
		queue_redraw()


func paint_cell(layer_key: String, pos: Vector2i, plant_id: String) -> void:
	if plant_id == "":
		erase_cell(layer_key, pos)
		return
	if not _cells.has(pos):
		_cells[pos] = {}
	_cells[pos][layer_key] = PlantGrowth.flora_lod_vector_colour(plant_id, layer_key)


func erase_cell(layer_key: String, pos: Vector2i) -> void:
	if not _cells.has(pos):
		return
	var layers: Dictionary = _cells[pos]
	layers.erase(layer_key)
	if layers.is_empty():
		_cells.erase(pos)


func clear_all() -> void:
	_cells.clear()
	queue_redraw()


func _draw() -> void:
	if not _active or _cells.is_empty():
		return
	var map_ref := get_parent() as Node2D
	if map_ref == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var z := maxf(cam.zoom.x, 0.0001)
	var half := get_viewport().get_visible_rect().size / z * 0.5
	var centre: Vector2 = map_ref.to_local(cam.global_position)
	var pad := 250.0
	var tl: Vector2 = centre - half - Vector2(pad, pad)
	var br: Vector2 = centre + half + Vector2(pad, pad)

	for pos: Vector2i in _cells:
		var centre_px: Vector2 = map_ref.map_to_local(pos)
		if centre_px.x < tl.x or centre_px.x > br.x or centre_px.y < tl.y or centre_px.y > br.y:
			continue
		var layers: Dictionary = _cells[pos]
		for layer_key in ["ground", "understory", "canopy"]:
			if layer_key == "ground" and not _show_ground:
				continue
			if layer_key == "understory" and not _show_understory:
				continue
			if not layers.has(layer_key):
				continue
			var col: Color = layers[layer_key]
			var spec: Dictionary = LAYER_SHAPES.get(layer_key, LAYER_SHAPES["ground"])
			if str(spec.get("kind", "rect")) == "ellipse":
				draw_circle(centre_px, float(spec.get("radius", 24.0)), col)
			else:
				var w := float(spec.get("width", 32.0))
				var h := float(spec.get("height", 28.0))
				draw_rect(Rect2(centre_px - Vector2(w * 0.5, h * 0.5), Vector2(w, h)), col, true)
