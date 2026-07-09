# Inbox Farmer — PixelLab → Godot animation pipeline

**For AI agents and future-me:** This is how the playable farmer got 8-direction walk cycles and idle poses. Do not replace the farmer with a flat `Sprite2D` unless you intentionally remove `character_anim`. The sleep “zip” queue depends on `AnimatedSprite2D` + `FarmerCharacterAnim`.

---

## 1. Where the art came from (PixelLab)

The sprites were made in **[PixelLab](https://www.pixellab.ai/)** using the **Objects** tool (not the tile or scene painter).

Typical workflow there:

1. Open PixelLab → **Objects**.
2. Describe / generate the farmer character.
3. Export **8-direction rotation** (standing poses) — one GIF showing the character facing each compass direction.
4. Export **per-direction walk cycles** — separate GIFs for walking “forward” in each of the 8 directions (PixelLab names them by compass: north, south-east, etc.).

Drop the downloaded GIFs into the repo folder:

```
inbox/
  farmer_character_rotations_8dir.gif
  farmer_character_The_farmer_walks_forward_with_a_steady_rhythmic_g_south.gif
  farmer_character_The_farmer_walks_forward_with_a_steady_rhythmic_g_south-east.gif
  … (east, north, north-east, north-west, west, south-west)
```

These are **source files only** — Godot does not load GIFs at runtime. They get converted to PNGs once (see §3).

**Frame specs (as exported):**

| Asset | Size | Frames |
|-------|------|--------|
| Rotations GIF | 136×136 per frame | 8 (one per direction) |
| Walk GIFs (most dirs) | 136×136 per frame | 9 |
| Walk east | 136×136 per frame | 17 |

**Icon rule:** The in-game farmer icon / roster sprite is **frame 0** of `farmer_character_rotations_8dir.gif` (first rotation frame), copied to `farmers/farmer.png`.

**Rotation frame order** (index → direction), matched to walk idle poses:

| Frame | Direction |
|-------|-----------|
| 0 | south |
| 1 | south_east |
| 2 | east |
| 3 | north_east |
| 4 | north |
| 5 | north_west |
| 6 | west |
| 7 | south_west |

---

## 2. Runtime assets (after conversion)

Converted PNGs live here:

```
assets/base/sprites/characters/farmers/
  farmer.png                    ← icon (frame 0 of rotations GIF)
  inbox_farmer/
    farmer.png                  ← duplicate icon inside anim pack
    idle_south.png … idle_south_west.png   ← 8 idle poses from rotations GIF
    walk_south_sheet.png … walk_south_west_sheet.png   ← horizontal strips
```

Walk sheets are **one row**: `(frame_width × frame_count)` × `136`, each frame 136px wide.

Open the Godot editor once after adding PNGs so `.import` files are generated.

---

## 3. Re-exporting from inbox GIFs

Conversion was done with Python + Pillow (one-off). To repeat after new PixelLab exports:

```bash
cd "/path/to/project"
python3 -m venv .venv_gif
.venv_gif/bin/pip install pillow
.venv_gif/bin/python3 - <<'PY'
from PIL import Image, ImageSequence
import os

INBOX = "inbox"
OUT = "assets/base/sprites/characters/farmers/inbox_farmer"
os.makedirs(OUT, exist_ok=True)

ROT_ORDER = [
    "south", "south_east", "east", "north_east",
    "north", "north_west", "west", "south_west",
]
WALK_FILES = {
    "south": "farmer_character_The_farmer_walks_forward_with_a_steady_rhythmic_g_south.gif",
    "south_east": "farmer_character_The_farmer_walks_forward_with_a_steady_rhythmic_g_south-east.gif",
    "east": "farmer_character_The_farmer_walks_forward_with_a_steady_rhythmic_g_east.gif",
    "north_east": "farmer_character_The_farmer_walks_forward_with_a_steady_rhythmic_g_north-east.gif",
    "north": "farmer_character_The_farmer_walks_forward_with_a_steady_rhythmic_g_north.gif",
    "north_west": "farmer_character_The_farmer_walks_forward_with_a_steady_rhythmic_g_north-west.gif",
    "west": "farmer_character_The_farmer_walks_forward_with_a_steady_rhythmic_g_west.gif",
    "south_west": "farmer_character_The_farmer_walks_forward_with_a_steady_rhythmic_g_south-west.gif",
}

rot_frames = list(ImageSequence.Iterator(Image.open(os.path.join(INBOX, "farmer_character_rotations_8dir.gif"))))
rot_frames[0].save(os.path.join(OUT, "farmer.png"))
rot_frames[0].save("assets/base/sprites/characters/farmers/farmer.png")
for i, d in enumerate(ROT_ORDER):
    rot_frames[i].save(os.path.join(OUT, f"idle_{d}.png"))

for d, fname in WALK_FILES.items():
    frames = [f.convert("RGBA") for f in ImageSequence.Iterator(Image.open(os.path.join(INBOX, fname)))]
    w, h = frames[0].size
    sheet = Image.new("RGBA", (w * len(frames), h))
    for i, fr in enumerate(frames):
        sheet.paste(fr, (i * w, 0))
    sheet.save(os.path.join(OUT, f"walk_{d}_sheet.png"))
    print(d, len(frames), "frames")
PY
```

If walk frame counts change (especially **east**), update `WALK_FRAME_COUNTS` in `scripts/farmer_character_anim.gd`.

---

## 4. Code architecture

### `scripts/farmer_character_anim.gd` (`class_name FarmerCharacterAnim`)

- Builds a cached `SpriteFrames` at runtime from the PNGs above.
- Animation names: `idle_south`, `walk_east`, etc. (underscore directions).
- `direction_from_delta(Vector2i)` maps grid step → 8-way compass using `atan2` and 45° sectors.
- `play_walk()` / `face_idle()` switch `AnimatedSprite2D` animations.

### `scripts/starting_map.gd`

| Helper | Role |
|--------|------|
| `_create_character_visual(w_data)` | Returns `AnimatedSprite2D` if animated, else legacy `Sprite2D`. |
| `_tween_character_move(...)` | Tweens position; plays walk during move, idle when stopped. |
| `_execute_worker_queue(...)` | Sleep-time action zip uses `_tween_character_move` per A* path segment. |

The on-map farmer node is `var farmer: Node2D` (usually `AnimatedSprite2D` for the player).

**Visual constants** (match old placeholder sprite):

- `scale = Vector2(1.5, 1.5)`
- `offset = Vector2(0, -60)` — feet on tile centre
- `z_index = 10`

During sleep, the main `farmer` is hidden; temporary worker sprites zip the queue, then `queue_free()`.

### `scripts/farm_data_manager.gd` — player worker entry

```gdscript
{
    "id": "player", "name": "Farmer", …
    "sprite": "res://assets/base/sprites/characters/farmers/farmer.png",
    "character_anim": "inbox_farmer",
}
```

`FarmerCharacterAnim.uses_animated_sprite()` returns true when:

- `character_anim == "inbox_farmer"`, **or**
- `sprite` path ends with `farmers/farmer.png` (old saves without `character_anim`).

---

## 5. When animations play

| Moment | Behaviour |
|--------|-----------|
| Daytime (standing on map) | `idle_south` loop on `farmer` |
| Sleep → action queue zip | Per path step: `walk_<direction>` while tweening, then `idle_<direction>` at each stop |
| Return home after queue | Same walk/idle logic along A* path back to `home_pos` |
| Other workers (no `character_anim`) | Still use static `Sprite2D` + texture path |

Direction is derived from **grid delta** `(to_cell - from_cell)`, not from velocity, so diagonals on the A* path pick the correct 8-way facing.

---

## 6. Adding another PixelLab character

1. Export rotations + 8 walk GIFs from PixelLab **Objects** → `inbox/`.
2. Run the export script (§3) into a new folder, e.g. `inbox_farmer/` → `inbox_caretaker/`.
3. Copy/adapt `farmer_character_anim.gd` or generalise `BASE_PATH` + `WALK_FRAME_COUNTS` per `character_anim` id.
4. Add a worker dict with `"character_anim": "inbox_caretaker"` and `"sprite": "…/caretaker.png"` (frame 0 of rotations).
5. Re-open Godot to import PNGs.

---

## 7. Prompting rule for AI

Before changing farmer visuals:

- Keep **200px tile** world alignment (`offset` lifts sprite above tile centre).
- Do not break sleep queue movement — it awaits `_tween_character_move`, not raw position tweens without animation.
- If replacing art, update **both** idle PNGs and walk sheets; frame size must stay **136×136** or update `FRAME_SIZE` and re-slice atlas regions.
- PixelLab source GIFs stay in `inbox/`; committed PNGs are the runtime truth.
