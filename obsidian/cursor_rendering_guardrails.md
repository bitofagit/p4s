# P4S Rendering & Map Architecture Guardrails

**CRITICAL DIRECTIVE FOR AI AGENTS:** Do NOT overwrite, simplify, or replace the procedural map rendering logic in `starting_map.gd` with standard Godot checkerboards, static `TileSet` resources, or default `TileMapLayer` painting. Permaculture 4 Squares (P4S) uses a highly specific procedural atlas generation system.

## 1. The Map & Tile Dimensions
*   **Tile Size:** The engine uses a strict **200px by 200px** tile size natively. Do not use legacy 256px or default 64px values.
*   **Grid Structure:** The map is a dynamic 2D array (`Array[Array]` of cell Dictionaries) owned by `FarmDataManager.grid_data`, usually sized 100x100. The playable area is clamped by `player_bounds_left` and `player_bounds_right`.
*   **Boot data source:** `starting_map._ready` boots from `_generate_procedural_grid_data()` (green wild biome, stream, forest) UNLESS `FarmDataManager.custom_starting_grid_loaded` is true. A custom grid only loads from `user://campaigns/<campaign_id>/starting_grid.json` for that exact campaign id. The Map Editor's scratch file (`user://campaigns/custom/starting_grid.json`) must NEVER hijack tutorial or standard campaign boots — a brown 24x24 "chequered" map at boot means this gate was broken, not the renderer.

## 2. Procedural Atlas Generation
The game does not use a pre-painted Godot TileSet. The atlas is generated dynamically at boot inside `starting_map.gd`:
*   The script creates a large blank `Image` at runtime.
*   It loads PNGs from `assets/base/sprites/environment/terrain/` subfolders (`grass`, `stream`, `river`, `forest`, `cultivated`, …) and stitches them into a single runtime atlas (plus user-drawn plant PNGs via `_stitch_custom_plant_sprites`).
*   **Biome Logic:** `_land_to_atlas_x(land, pos)` uses deterministic maths (primes and coordinates) to select texture variations from the stitched atlas, so neighbouring tiles vary naturally.
*   **DO NOT** replace the atlas stitching loop with a basic two-colour checkerboard pattern or flat `fill_rect` colours.

## 3. How Tiles are Painted
Visuals are updated via `update_visuals()` (full pass) or `_update_single_tile_visual(pos)` (single cell):
*   The terrain base is drawn first using the `land` string key (e.g. `"wild"`, `"cultivated"`, `"stream"`, `"swale"`, `"mound"`).
*   **Earthworks:** Paths, bridges, swales and mounds are drawn from the cell's `has_path` / `land` / `structure` state. Queued actions preview on `preview_overlay`, never by mutating the terrain atlas.

## 4. Plant Rendering & Biology
Plants are NOT baked into the terrain atlas. They render on dedicated `TileMapLayer` nodes stacked above the terrain (`GroundLayer` z=1, `UnderstoryLayer` z=2, `CanopyLayer` z=3, `StructureLayer` z=4).
*   If the map is empty of plants, the biology loop or the layer painting in `update_visuals()` was bypassed — not a sprite problem.
*   The renderer reads the cell's layer keys (`canopy`, `understory`, `ground`) and resolves atlas columns via `_resolve_plant_atlas_x()` from `get_plant_data()` (V3 CSV schema).
*   **Visual Plant Stress:** Do not delete stressed plants instantly. `_animate_plant_change()` spawns a temporary ghost sprite that tints toward sickly brown-yellow (`#a89f68`) under stress and shrinks/fades to zero on death.

## 5. Overlay Nodes
Tactical information is handled by separate `Node2D` overlays, NOT by modifying the base tiles:
*   **GuildVision / EnergyVision:** dedicated overlay nodes draw vector links, auras, heatmaps.
*   **Lens tints:** `LensOverlay` is a single Sprite2D scaled 200x per cell — never per-tile modulate loops.
*   **Water Shimmer:** Capillary water (moisture > 10, brimming swales) uses `CapillaryOverlayNode` alpha-scaled translucent blue rects, not tile swaps.
*   **Weather:** `WeatherModulate` (CanvasModulate in `world.tscn`) is tweened per daily weather; rain particles attach to the Camera2D. Neither touches tile data.

## 6. Prompting rule
Before generating any code for `starting_map.gd` or `world.gd`, reference this document. Do not break the 200px procedural atlas, the biome stitching, or the campaign-gated custom grid boot.
