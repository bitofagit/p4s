extends RefCounted
class_name NutrientPalette
## Shared nutrient colours and bar-scale constants (soil inspector, data lenses, HUD).

const BAR_FULL_SOIL := 10.0
const BAR_FULL_DELTA := 2.0
const BAR_FULL_GROWTH := 10.0

const COLORS := {
	"moisture": Color(0.28, 0.58, 1.0),
	"nitrogen": Color(0.68, 0.32, 0.92),
	"minerals": Color(0.95, 0.62, 0.18),
	"structure": Color(0.55, 0.38, 0.22),
	"fungi": Color(0.35, 0.78, 0.72),
	"bacteria": Color(0.45, 0.82, 0.38),
	"macro_life": Color(0.72, 0.55, 0.32),
	"toxicity": Color(0.92, 0.28, 0.35),
	"growth": Color(0.42, 0.88, 0.48),
	"ph": Color(0.78, 0.72, 0.95),
}


static func color_for(stat_id: String) -> Color:
	return COLORS.get(stat_id, Color(0.75, 0.78, 0.82))


static func stat_key_from_label(label_text: String) -> String:
	match label_text:
		"Nitrogen":
			return "nitrogen"
		"Minerals":
			return "minerals"
		"Moisture":
			return "moisture"
		"Structure":
			return "structure"
		"Fungi":
			return "fungi"
		"Bacteria":
			return "bacteria"
		"Macro-Life":
			return "macro_life"
		"Toxicity":
			return "toxicity"
		_:
			return ""


static func apply_label_color(label: Label, stat_id: String) -> void:
	if stat_id == "":
		return
	label.add_theme_color_override("font_color", color_for(stat_id))


static func bar_full_for(stat_id: String) -> float:
	match stat_id:
		"growth":
			return BAR_FULL_GROWTH
		"moisture_delta", "nitrogen_delta", "mineral_delta", "toxicity_delta":
			return BAR_FULL_DELTA
		_:
			return BAR_FULL_SOIL


static func fmt_overflow(value: float, full: float) -> String:
	if value <= full * 1.02:
		return ""
	return "%0.1f" % snappedf(value, 0.1)
