# Six-Stage Growth & Dynamic Soil Exchange
**Tags:** #mechanics #plants #ecology #code-architecture #sprites

Plants in P4S opencore use a **universal 6-stage life cycle** for visuals, maturity timing, and **stage-scaled soil exchange**. CSV rows in `data/plants_v3.csv` hold the *baseline* ecological deltas; at runtime those deltas are multiplied by the plant’s current growth stage before they hit the cell.

Related: [[05_Plant_Ecology]], [[06_Plant_Data_Schema]], [[12_Understanding_Guilds]]

---

## 1. The Six Growth Stages

| Stage | Name | Age rule (`current_age` vs `days_to_mature`) |
|------:|------|-----------------------------------------------|
| 0 | **Sown** | `age == 0` |
| 1 | **Seedling** | `age > 0` and `< days_to_mature × 0.33` |
| 2 | **Vegetative** | `≥ 0.33` and `< 0.66` of mature |
| 3 | **Flowering** | `≥ 0.66` and `< days_to_mature` |
| 4 | **Mature / Fruiting** | `≥ days_to_mature` and `< days_to_senescence` |
| 5 | **Senescence** | `≥ days_to_senescence` |

### CSV timing columns
Each plant row defines:
- **`days_to_mature`** — when stage 4 begins (harvest-ready). Defaults to `10` if missing.
- **`days_to_senescence`** — when stage 5 begins. Defaults to `15` if missing.
- **`mature_turn`** — kept in sync with `days_to_mature` for legacy references.

Per-layer age is stored on the grid cell as `{layer}_age` (`ground_age`, `understory_age`, `canopy_age`).

---

## 2. Stage Multipliers (Permaculture Exchange Curve)

Baseline CSV deltas (`nitrogen_delta`, `mineral_delta`, `moisture_delta`) are **multiplied** each night during the biology **exchange** phase. Both **positive** (N-fixers, accumulators) and **negative** (heavy feeders) values follow the same curve.

| Stage | N mult | Minerals mult | Moisture mult | Design intent |
|------:|-------:|--------------:|--------------:|---------------|
| 0 Sown | 0.0 | 0.0 | 0.1 | Seed barely interacts |
| 1 Seedling | 0.25 | 0.1 | 0.5 | Fragile, low draw |
| 2 Vegetative | **1.0** | 0.5 | **1.0** | Peak leafy nitrogen hunger |
| 3 Flowering | 0.5 | **1.0** | **1.0** | Shift from N → minerals |
| 4 Mature | 0.2 | **1.0** | **1.0** | Fruiting mineral draw |
| 5 Senescence | 0.0 | 0.0 | 0.0 | Dead/dying — no active feeding |

**Not scaled by stage (applied at full CSV value):**
- `structure_delta`, `toxicity_delta`
- Soil-web affinities (`fungal_affinity`, `bacterial_affinity`, `macro_life_affinity` × 0.1)

### Example
Climbing bean with `nitrogen_delta: +0.25` (N-fixer):
- Vegetative → **+0.25** / turn  
- Seedling → **+0.06** / turn  
- Senescence → **0**

Sweetcorn with `nitrogen_delta: -0.20` (heavy feeder):
- Vegetative → **−0.20** / turn  
- Mature → **−0.04** / turn  

---

## 3. Code Map

| Responsibility | File |
|----------------|------|
| Stage math, multiplier table, sprite paths | `scripts/plant_growth.gd` (`class_name PlantGrowth`) |
| Night biology exchange (scaled deltas applied) | `scripts/starting_map.gd` → `_process_plant_biology(..., "exchange")` |
| Growth stage helper | `starting_map.gd` → `_get_plant_growth_stage()`, `_get_stage_multipliers()` |
| Tile rendering by stage | `starting_map.gd` → `_resolve_plant_atlas_x(plant_id, growth_stage)` |
| Shift-hover forecast & soil-profile ghosts | `scripts/plant_nutrient_forecast.gd` |
| Plant database | `data/plants_v3.csv` via `data/data_plants.gd` |

### Key functions (`PlantGrowth`)
```gdscript
PlantGrowth.growth_stage(plant_id, current_age) -> int          # 0–5
PlantGrowth.stage_label(stage) -> String                        # e.g. "Vegetative"
PlantGrowth.stage_multipliers(stage) -> Dictionary              # { "n", "min", "m" }
PlantGrowth.scaled_exchange_deltas(plant_data, stage) -> Dictionary
```

---

## 4. Player-Facing UI

**Hold Shift** over a tile:
- Each plant layer line shows `(Stage: Vegetative)` etc.
- **Next turn · plant exchange** lists per-plant scaled deltas, not raw CSV numbers.

Soil profile / data-lens frosted bars use `PlantNutrientForecast.compute(cell)` — same scaling as gameplay.

---

## 5. Sprite Art Pipeline

### Folder layout (preferred)
```
assets/base/sprites/flora/{plant_id}/stage_0.png  …  stage_5.png
assets/base/sprites/flora/{plant_id}/stage2.png   (underscore optional)
```

**Canopy trees** also accept fruiting variants (stage 4 = with fruit, others = no fruit):
```
flora/apple/stage2nofruit.png
flora/apple/stage4withfruit.png
```

### Flat alternate (also loaded)
```
assets/base/sprites/flora/{plant_id}_stage_0.png
```

### User mod override
```
user://databases/sprites/stages/{plant_id}/stage_{0-5}.png
```

**Specs:** 200×200 px PNG, nearest-neighbor. Stage 4 = harvest-ready look.

Until stage art exists, the engine falls back to the legacy single-sprite `atlas_x` / `custom_sprite_path`.

**Full checklist:** `assets/base/sprites/flora/STAGE_SPRITE_MANIFEST.txt`  
(33 species × 6 stages = 198 files; `[HAVE]` / `[NEED]` status per file.)

### Stage art brief
| Stage | Visual cue |
|------:|------------|
| 0 | Seed in soil / bare mound |
| 1 | First leaves |
| 2 | Leafy vegetative mass |
| 3 | Flowers / pre-fruit |
| 4 | Harvest-ready / full size |
| 5 | Withered / brown / dead |

---

## 6. Design-Doc Plants (V3 additions)

These eight species were added for guild / regional design coverage:

| id | Role | Layer |
|----|------|-------|
| `nettle` | Dynamic accumulator | ground |
| `dandelion` | Pioneer Blast taproot | ground |
| `sweetcorn` | Three Sisters core | understory |
| `climbing_bean` | Three Sisters N-fixer | understory |
| `squash` | Three Sisters living mulch | ground |
| `gooseberry` | Berry Thicket core | understory |
| `willow` | Boggart Brake wetland drainer | canopy |
| `reed` | Boggart Brake phytoremediator | ground |

Guild companion IDs in `data/data_guilds.gd` were aligned to real CSV ids (`white_clover`, `blackcurrant`, `comfrey_b14`, etc.).

---

## 7. Revision Log

- **2026-06** — Universal 6-stage schema; `days_to_mature` / `days_to_senescence` in `plants_v3.csv`; stage-scaled exchange multipliers; flora manifest.
