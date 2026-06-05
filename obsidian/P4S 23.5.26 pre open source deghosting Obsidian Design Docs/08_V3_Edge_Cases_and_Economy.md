# V3 Edge Cases, Economy, and Save Upgrades

This document outlines how the V3 engine handles legacy data, produce values, and specific weather interactions.

## 1. Save File Backward Compatibility
Because the game shifted from `m` and `n` variables to a 10-stat ecosystem (`moisture`, `nitrogen`, `macro_life`, etc.), old save files would naturally crash the engine.
* **The Fix:** `save_manager.gd` intercepts legacy saves during `_deserialize_grid`. If a cell lacks the `"moisture"` key, it automatically upgrades the cell, mapping the old `m` and `n` values to the new schema and injecting safe defaults for the biological web (fungi, bacteria, etc.). Old runs are never lost.

## 2. Produce Economy (Energy & Wealth)
Eating and selling produce drives the player's progression loop. The V3 `data_plants.gd` CSV parser strictly enforces these values:
* **`energy_yield`:** Cast as an integer. Determines how much stamina the player regains when eating the crop.
* **`yield_val`:** Cast as an integer. Determines how much Money (£) the player receives when selling the crop.
* **Failsafes:** If the CSV cell is left blank or missing, the parser defaults to `-1` temporarily, and the engine catches it and assigns a safe baseline value of `5` for both stats. A tomato will naturally yield more than a weed!

## 3. Frost vs. Polytunnels
The `advance_turn()` weather loop checks for `"frost"`. Frost immediately drops soil moisture by `-0.5` and executes a kill-check against the `frost_hardiness` of every plant on the grid.
* **The Exception:** If a cell's `zone` is `"polytunnel"`, the engine explicitly executes a `continue` statement, skipping the kill-check entirely. The plastic sheeting serves as a physical, mechanical shield against winter die-offs.