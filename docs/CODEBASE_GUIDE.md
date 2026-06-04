# Codebase guide (read this first)

This file lives at **`docs/CODEBASE_GUIDE.md`**. This is a **Godot 4.x** farming / grid game. The goal of this document is to explain **where things live** and **how the big pieces talk to each other**, so you can change one area without getting lost. For a concise **stack / layer diagram** and HUD runtime layout notes, see **`docs/ARCHITECTURE.txt`**. An append-only **agent change log** is **`docs/cursor-action-log.txt`**.

---

## 1. How the game starts

1. **Main scene** is set in `project.godot` under **Application → Run → Main Scene** (currently the main menu).
2. From the menu, the player picks **Continue**, **New Game**, or **Load** → the game switches to `res://scenes/world.tscn`.
3. **World** is a small scene: a `Node2D` root, a **TileMapLayer** (this is the real “game map”), and a **Camera2D** (pan/zoom; script is `scripts/world.gd` even though the filename says “world” — it is the camera script).

**Mental model:** *Menu* → *World scene* → *map layer does almost everything*; *camera* only moves the view.

---

## 2. Autoloads (global singletons)

These are defined in `project.godot` under `[autoload]`. They exist for the whole run of the game and are accessed as **SaveManager**, **RadioManager**, **MetaManager**, **FarmDataManager** from anywhere (including `/root/SaveManager` in code).

| Name | Script | Role |
|------|--------|------|
| **FarmDataManager** | `scripts/farm_data_manager.gd` | **Authoritative game state:** turn, money, grid, workers, energy, inventory, seasons, action queues, etc. Emits signals when things change. |
| **SaveManager** | `scripts/save_manager.gd` | **Read/write save files** under `user://` (JSON). Also **hotkey settings** in `user://settings.json`. Can set `pending_load_save_name` so the map loads a save when it becomes ready. |
| **MetaManager** | `scripts/meta_manager.gd` | **Meta-progression** that is not a single farm save: karma, unlocks, “dev mode” flag. Persists in `user://shadow_logic_meta.json`. |
| **RadioManager** | `scripts/radio_manager.gd` | **Audio:** interactive music, beats, SFX pool. Other code can react to music/beat events. |

**Rule of thumb:** If you are adding “one save file per farm,” use **SaveManager** + **FarmDataManager**. If you are adding “account-wide unlocks or karma,” use **MetaManager**.

---

## 3. The heaviest script: `starting_map.gd`

`scripts/starting_map.gd` is attached to the **TileMapLayer** in `scenes/world.tscn`. It is large on purpose: it holds **map generation, tools, tiles, workers, UI hooks, narrative triggers, overnight events**, and coordination with the HUD.

When debugging gameplay bugs, **start here** and search for the tool name, signal, or feature you care about.

It talks to:

- **FarmDataManager** — all persistent simulation numbers and grid.
- **SaveManager** — saving/loading; listen for `pending_load_save_name` after scene ready.
- **MetaManager** — karma shop, upgrades, dev mode.
- **RadioManager** — timing/audio-driven beats if relevant.
- **NarrativeData** / **`DataScenario`** — CSV dialogue/lore and scripted weather (tutorial beats, Gen1 failure timing, etc.).
- **Child UI** — HUD (`hud.tscn` / `hud.gd`), popups, almanac, etc., often created or referenced from here.

### 3.1 Useful “where is it?” annotations (recent behaviors)

- **Plant death logs**: In `starting_map.gd`, the death prints in `_apply_plant_stress` and overnight weather/dehydration loops log **turn number** (`FarmDataManager.current_turn`) and **soil stats** (cell `moisture`, `nitrogen`, `minerals`) so you can debug why plants died without opening the grid dump.
- **Farmer + worker sprite sizing**: The `Sprite2D` nodes used for the farmer and worker animations are scaled up (and vertically offset) so they overlap the tile above, matching a roughly “taller than one tile” character silhouette.
- **Camera framing after events**: The camera script (`scripts/world.gd`, attached to the `Camera2D` in `world.tscn`) plays event queues; when the queue finishes, it tweens back to default zoom and recentres on the map.
- **Fresh story-mode start framing**: In `starting_map.gd` `_ready`, the Gen1 story path (non-dev-mode) snaps the camera to the farmhouse and sets an initial story zoom (currently `0.25`) so the player starts with a wider view of the plot.
- **Soil Profile UI safe zones**: The inspector’s `SoilProfileUI` bars now include **Nitrogen** + **Minerals** and can show a translucent **safe range overlay** computed from the overlapping min/max requirements of the plants in that cell (requirements are intersected across canopy/understory/ground). **Right-hand numbers** show the **raw** sim values (e.g. swale moisture can exceed 10); the **progress bars** still cap at the 0–10 display scale.
- **Narrative softlock failsafe**: `ui_narrative_popup.gd` `show_dialogue()` now force-adds a **Continue** button if dialogue options fail to generate, preventing a pause-with-no-buttons softlock.

---

## 4. HUD and UI

- **`scenes/hud.tscn`** + **`scripts/hud.gd`** — Main overlay: tools, vitals, minimap, almanac, workers, save/load signals, etc. It emits signals (e.g. tool picked, save requested); **starting_map** or other controllers connect to those signals. **Pause** is the in-scene **`Pause_Overlay`** on the HUD’s `CanvasLayer` (not a separate pause scene). At runtime, `_ready` adds a **Sound Settings** button that opens **`ui_audio_panel.gd`** (same script instance pattern as the main menu).
- **`scripts/main_menu.gd`** — First screen; sets `SaveManager.pending_load_save_name` and changes scene to `world.tscn`. Spawns a top-left **Mute Audio** toggle (Master bus) plus embedded graphics/audio panel scripts.
- Other UI pieces live under `scenes/` (`info_window`, pickers, etc.) and are opened from the map or HUD as needed.

---

## 5. Data (content, not code)

Under **`data/`**, scripts named **`data_*.gd`** fall into two patterns:

1. **CSV-backed loaders** — Read `res://data/*.csv` at runtime (or on first use), cache into static dictionaries, expose getters. Example: **`data_plants.gd`** + `plants.csv`; **`data_narrative.gd`** (`NarrativeData`) + `lore.csv` / **`dialogue.csv`** via `load_data()` (dialogue rows are **RFC 4180–quoted** so commas in `title`/`body` are safe). **`story_weather.csv`** — calendar **`day` → `weather`** for scripted tutorial/story beats; parsed by **`scripts/data_scenario.gd`** (`class_name DataScenario`), consumed from **`starting_map.gd`** via **`_get_weather_for_day()`** (non–dev mode uses CSV when a row exists, otherwise random weather).
2. **Embedded `ENTRIES` dictionaries** — All content is in the `.gd` file as `const ENTRIES` (no CSV). Examples: **almanac** topics, **`data_guilds.gd` guilds** (standard guilds are **1-tile vertical stacks** checked by `_get_guild_synergy_mult()`), **`data_superguilds.gd` superguilds** (role-based **3×3** checks via `_get_synergies_for_cell()`), **placeable objects**, **upgrade blurbs**, **additives** text. Edit the dictionary (or split to CSV later if the file grows).

Each `data_*.gd` file has a short **`##` header** describing which pattern it uses. **`data_scenario.gd`** lives under **`scripts/`** (same CSV pattern, not named `data_*.gd`). Broader orientation: this document.

---

## 6. Persistence locations (quick reference)

| Path | What |
|------|------|
| `user://<save_name>.json` | Farm saves (via SaveManager). |
| `user://settings.json` | Hotkeys / settings. |
| `user://shadow_logic_meta.json` | Karma, unlocks (MetaManager). |

Use Godot’s **user://** paths — they resolve to the machine’s user data folder for this project.

---

## 7. What to open when you change…

| Task | Likely files |
|------|----------------|
| Tool behavior on the map | `starting_map.gd`, sometimes `hud.gd` |
| Economy, turn, grid, workers | `farm_data_manager.gd`, `starting_map.gd` |
| Save format | `save_manager.gd`, `farm_data_manager.gd` |
| New crop / item stats | `data/plants.csv`, `data/data_plants.gd` |
| Menu flow | `main_menu.gd`, `project.godot` main scene |
| Camera feel | `world.gd` (Camera2D) |
| Music / rhythm hooks | `radio_manager.gd` |
| Full-screen UI layout | `hud.tscn`, `hud.gd` |
| Scripted weather by calendar day | `data/story_weather.csv`, `scripts/data_scenario.gd`, `starting_map.gd` (`_get_weather_for_day`, forecast init / night append) |
| Branching dialogue & daily lore | `data/dialogue.csv`, `data/lore.csv`, `data/data_narrative.gd` |
| Pause audio UI | `hud.gd` (Sound Settings → `ui_audio_panel.gd`), main menu mute in `main_menu.gd` |

---

## 8. Conventions worth knowing

- **Groups:** The map may register nodes in groups (e.g. `"map"`); the camera checks groups before handling input. Search for `add_to_group` / `get_first_node_in_group`.
- **Signals:** Many flows use Godot signals (`FarmDataManager.energy_changed`, HUD signals, etc.) instead of tight coupling — when adding features, prefer connecting signals in `_ready` or when instancing UI.
- **Scene UIDs:** Godot 4 stores **uid://** in scenes; use the editor to move resources when possible so references stay valid.

If something is still unclear, search the project for the **class name** or **signal name** you see in the inspector — that will usually lead you to the right script.
