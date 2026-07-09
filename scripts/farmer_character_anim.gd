extends RefCounted
class_name FarmerCharacterAnim

## 8-direction farmer from inbox GIFs (idle rotations + walk cycles).

const BASE_PATH := "res://assets/base/sprites/characters/farmers/inbox_farmer"
const FRAME_SIZE := Vector2i(136, 136)
const DIRECTIONS: Array[String] = [
	"south", "south_east", "east", "north_east",
	"north", "north_west", "west", "south_west",
]
const WALK_FRAME_COUNTS: Dictionary = {
	"south": 9,
	"south_east": 9,
	"east": 17,
	"north_east": 9,
	"north": 9,
	"north_west": 9,
	"west": 9,
	"south_west": 9,
}
const DELTA_TO_DIR: Array[String] = [
	"east", "south_east", "south", "south_west",
	"west", "north_west", "north", "north_east",
]

static var _sprite_frames: SpriteFrames


static func uses_animated_sprite(worker: Dictionary) -> bool:
	if str(worker.get("character_anim", "")) == "inbox_farmer":
		return true
	var sprite_path := str(worker.get("sprite", ""))
	return sprite_path.ends_with("farmers/farmer.png") \
		or sprite_path.contains("inbox_farmer/farmer.png")


static func get_sprite_frames() -> SpriteFrames:
	if _sprite_frames != null:
		return _sprite_frames
	var sf := SpriteFrames.new()
	for d in DIRECTIONS:
		_add_idle_animation(sf, d)
		_add_walk_animation(sf, d)
	_sprite_frames = sf
	return sf


static func _add_idle_animation(sf: SpriteFrames, direction: String) -> void:
	var anim := "idle_%s" % direction
	var tex_path := "%s/idle_%s.png" % [BASE_PATH, direction]
	if not ResourceLoader.exists(tex_path):
		return
	sf.add_animation(anim)
	sf.set_animation_loop(anim, true)
	sf.set_animation_speed(anim, 1.0)
	sf.add_frame(anim, load(tex_path) as Texture2D)


static func _add_walk_animation(sf: SpriteFrames, direction: String) -> void:
	var anim := "walk_%s" % direction
	var sheet_path := "%s/walk_%s_sheet.png" % [BASE_PATH, direction]
	if not ResourceLoader.exists(sheet_path):
		return
	var sheet := load(sheet_path) as Texture2D
	var frame_count: int = int(WALK_FRAME_COUNTS.get(direction, 9))
	sf.add_animation(anim)
	sf.set_animation_loop(anim, true)
	sf.set_animation_speed(anim, 12.0)
	for i in range(frame_count):
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2i(i * FRAME_SIZE.x, 0, FRAME_SIZE.x, FRAME_SIZE.y)
		sf.add_frame(anim, at)


static func setup_sprite(sprite: AnimatedSprite2D, _worker: Dictionary = {}) -> void:
	sprite.sprite_frames = get_sprite_frames()
	sprite.centered = true
	face_idle(sprite, "south")


static func direction_from_delta(delta: Vector2i) -> String:
	if delta == Vector2i.ZERO:
		return "south"
	var angle := rad_to_deg(atan2(float(delta.y), float(delta.x)))
	if angle < 0.0:
		angle += 360.0
	var sector := int(round(angle / 45.0)) % 8
	return DELTA_TO_DIR[sector]


static func play_walk(sprite: AnimatedSprite2D, direction: String) -> void:
	var anim := "walk_%s" % direction
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)


static func face_idle(sprite: AnimatedSprite2D, direction: String) -> void:
	var anim := "idle_%s" % direction
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
