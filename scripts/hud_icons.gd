extends RefCounted
class_name HudIcons
## HUD pixel icons under res://assets/base/sprites/ui/icons/hud/
## High-res sources are downscaled at load time (nearest) for crisp UI sizing.

const BASE := "res://assets/base/sprites/ui/icons/hud/"
const POPUP_ICON_PX := 36
const TITLE_ICON_PX := 32
const EDGE_TAB_ICON_PX := 34

const PATHS: Dictionary = {
	"farm_hands": BASE + "farmhands.png",
	"tile_inspector": BASE + "tileinspector.png",
	"todays_plan": BASE + "todaysplan.png",
	"sleep": BASE + "sleep147.png",
	"almanac": BASE + "almanac book icon.png",
	"plant_codex": BASE + "plant codex icon.png",
	"ecology_scanner": BASE + "ecologyscanner icon.png",
	"dev_console": BASE + "devconsole icon.png",
}

static var _scaled_cache: Dictionary = {}


static func get_icon(key: String, max_px: int = 64) -> Texture2D:
	var path: String = str(PATHS.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return null
	return _fit_icon(tex, max_px)


static func apply_button_icon(
	btn: Button,
	key: String,
	fallback_text: String = "",
	icon_max: float = float(EDGE_TAB_ICON_PX)
) -> bool:
	if btn == null:
		return false
	var px := maxi(1, int(icon_max))
	var tex := get_icon(key, px)
	if tex == null:
		btn.text = fallback_text
		return false
	btn.text = fallback_text
	btn.icon = tex
	btn.expand_icon = true
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.add_theme_constant_override("icon_max_width", px)
	btn.add_theme_constant_override("icon_max_height", px)
	return true


static func apply_popup_icon(popup: PopupMenu, item_index: int, key: String) -> void:
	if popup == null or item_index < 0:
		return
	var tex := get_icon(key, POPUP_ICON_PX)
	if tex:
		popup.set_item_icon(item_index, tex)


static func _fit_icon(tex: Texture2D, max_px: int) -> Texture2D:
	if max_px <= 0:
		return tex
	var w := tex.get_width()
	var h := tex.get_height()
	if w <= max_px and h <= max_px:
		return tex
	var cache_key := "%s#%d" % [tex.resource_path, max_px]
	if _scaled_cache.has(cache_key):
		return _scaled_cache[cache_key]
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	var scale := float(max_px) / float(maxi(w, h))
	var nw := maxi(1, int(floorf(float(w) * scale)))
	var nh := maxi(1, int(floorf(float(h) * scale)))
	img = img.duplicate()
	img.resize(nw, nh, Image.INTERPOLATE_NEAREST)
	var out := ImageTexture.create_from_image(img)
	_scaled_cache[cache_key] = out
	return out
