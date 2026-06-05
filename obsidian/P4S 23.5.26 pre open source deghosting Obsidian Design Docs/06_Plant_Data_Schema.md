# Plant Data Schema
**Tags:** #data-structure #code-architecture #plants

This defines the exact data structure Cursor should use when generating the GDScript for the plant database. It maps to the Soil Ecosystem and the Weather system.

## 1. Core Identity
* `id`: String (e.g., "tomato_heirloom")
* `name`: String
* `lifecycle`: String ("Annual", "Biennial", "Perennial")
* `layer`: String ("Canopy", "Understory", "Ground")

## 2. The Gatekeepers (What it needs to survive)
* **Physical:**
  * `min_depth`: Int (cm)
  * `shade_tolerance`: String ("High", "Medium", "Low")
  * `min_germination_temp`: Int (°C) - *Frost/planting threshold.*
  * `max_temp`: Int (°C) - *Heat stress/bolting threshold.*
* **Chemical:**
  * `min_moisture`: Int (0-10) - *Drought threshold.*
  * `max_moisture`: Int (0-10) - *Flood/Root-rot threshold.*
  * `min_nitrogen`: Int (0-10) - *Volatile fuel.*
  * `max_nitrogen`: Int (0-10) - *Nutrient burn threshold.*
  * `min_minerals`: Int (0-10) - *Stable bedrock fuel.*
  * `max_minerals`: Int (0-10) - *Nutrient lockout threshold.*
  * `ideal_ph_min`: Float (0.0-14.0)
  * `ideal_ph_max`: Float (0.0-14.0)
  * `max_toxicity`: Int (0-10)

## 3. Ecological Outputs (How it alters the cell per turn/season)
* `moisture_delta`: Int (Transpiration rate; negative drains water)
* `nitrogen_delta`: Int (Negative for heavy feeders, positive for nitrogen fixers like legumes)
* `mineral_delta`: Int (Negative for heavy fruiters, positive for dynamic accumulators/taproots)
* `toxicity_delta`: Int (Negative for phytoremediators pulling toxins out)
* `structure_delta`: Int (Passive increase from taproots breaking clay)

## 4. Biological Modifiers (The Soil Web Impact)
* `fungal_affinity`: Int (0-10) - Boosts fungi (high for trees).
* `bacterial_affinity`: Int (0-10) - Boosts bacteria when decomposing (high for leafy greens).
* `macro_life_affinity`: Int (0-10) - How much worms/beetles love this plant.