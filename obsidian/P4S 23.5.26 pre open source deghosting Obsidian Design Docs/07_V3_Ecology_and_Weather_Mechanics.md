# V3 Ecology & Weather Mechanics

This document outlines the core physics and biological systems of the V3 simulation engine (`starting_map.gd`), which replaced the legacy `m` and `n` cellular automata loop.

## 1. The V3 Soil Web
All cell data is now stored using the V3 schema. Most values are strictly clamped between `0.0` and `10.0` (except pH, which is 0-14).
* **Moisture:** Driven entirely by Weather and Earthworks.
* **Nitrogen / Minerals:** Consumed and produced by plant deltas and animal systems (Pigs/Ducks).
* **Structure / Macro-life / Fungi / Bacteria:** The "living soil" web, driven by plant affinities and ecological practices.

*(Note: Legacy save files containing only `m` and `n` are automatically upgraded to the V3 schema upon loading via `save_manager.gd`).*

## 2. Plant Biology (The Night Loop)
During `advance_turn()`, the engine evaluates every plant on the grid in two phases:

### Phase A: Gatekeepers (Survival)
Plants check the soil's current stats against their CSV requirements:
* `min_moisture` / `max_moisture`
* `min_nitrogen` / `max_nitrogen`
* `min_minerals` / `max_minerals`
If the soil falls outside these bounds, the plant immediately dies, drops off the layer, and spawns a specific warning (e.g., "Thirsty!", "Root Rot!", "Nutrient Burn!").

### Phase B: Exchange (Deltas)
If a plant survives the Gatekeepers, it modifies the soil based on its CSV data:
* Applies `moisture_delta`, `nitrogen_delta`, `mineral_delta`, and `structure_delta`.
* Applies `fungal_affinity`, `bacterial_affinity`, and `macro_life_affinity` (scaled by 10% per turn to build up slowly over time).

## 3. Dynamic Weather Physics
The legacy system's constant evaporation has been replaced by the 5-Day Forecast. Weather globally affects exposed soil:
* **Heavy Rain:** `+3.0` Moisture.
* **Clear Skies:** `-0.5` Moisture.
* **Dry:** `-2.0` Moisture (Rapid dry-down, kills shallow-rooted annuals).
* **Early Frost:** `-0.5` Moisture. Kills any plant with a `frost_hardiness` below 4.
* **The Polytunnel Shield:** Cells with `zone == "polytunnel"` are immune to Frost and global weather swings. They experience a constant, mild `-0.2` Moisture drain due to enclosed evaporation.

## 4. Earthworks (Water Management)
Earthworks actively manipulate the flow and retention of `moisture` to protect against the new extreme weather:

* **Hugelmounds (`land == "mound"`):**
  * Act as evaporation sponges. They lose exactly *half* as much moisture as normal soil during Clear Skies (`-0.25`) and Dry spells (`-1.0`).
  * Provide a massive boost to base `aeration` and `biodiversity`.
* **Swales (`land == "swale"`):**
  * Act as water batteries via Capillary Action.
  * If a Swale has `> 3.0` moisture, it pushes water into a 5x5 grid around itself.
  * Adjacent tiles are forced to a minimum hydration based on distance (e.g., a full 10/10 Swale will force immediate neighbours to stay at 7.5 moisture, saving them from drought).