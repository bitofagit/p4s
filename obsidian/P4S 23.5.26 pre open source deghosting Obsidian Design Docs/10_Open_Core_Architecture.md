# Open Core Architecture
**Tags:** #architecture #open-source #workflow

Permaculture 4 Squares is built on an "Open Core" model. The underlying permaculture engine (grid math, soil simulation, generic UI) will be open-sourced under an MIT licence. The premium game (the Yorkshire lore, ghost story, procedural audio, and pixel art) is strictly closed-source and copyrighted.

## 1. The Asset Split
To maintain this legal boundary, assets MUST be strictly divided into two folders:
* `res://assets/base/`: Contains generic, open-source "developer art" (e.g., plain green squares for plants, simple UI icons). This folder is committed to the public repository.
* `res://assets/premium/`: Contains all copyrighted pixel art, narrative audio, and proprietary branding. **This folder is Git-ignored from the public repository.**

## 2. Code Rules
* **No Hardcoded Premium Paths:** Core engine scripts (like `starting_map.gd` or `hud.gd`) must NEVER hardcode paths to `res://assets/premium/`. They must always point to the `base` folder, or rely on export variables that can be overridden in the editor.
* **No Story in the Engine:** The core cellular automata loops must remain entirely agnostic to the ghost story. Narrative events must be triggered via decoupled signals or data parsers (like `data_narrative.gd`).

## 3. The "Inherited Scene" Workflow
When building the commercial version of the game:
1. Do not directly edit the base scenes (e.g., `starting_map.tscn`).
2. Create an **Inherited Scene** (e.g., `yorkshire_map.tscn`) saved in a closed-source folder.
3. Swap the `base` textures for `premium` textures inside the inherited scene.

*This ensures that when the open-source community updates the core engine, the premium game inherits the bug fixes without breaking the custom art.*

## 4. Codebase path audit (2026-05-23)
Hardcoded `.png` / `.wav` / `.mp3` references in `.gd` scripts resolve under `res://assets/base/`:

| Script | Notes |
|--------|--------|
| `starting_map.gd` | Chime preload, terrain atlas folders, worker sprites, balsam SFX |
| `radio_manager.gd` | `farm_music.tres`, beat scan dir, glock sample |
| `farm_data_manager.gd` | Default farmer sprite |

Do not relocate `.csv`, `.gd`, `.tscn`, or `.tres` paths in this audit unless they are premium-only overrides in inherited scenes.

## 5. Premium narrative (commercial only)

Ghost story, roguelike Karma, and scripted tutorial beats are documented in **[[11_Premium_Ghost_Story_Archive]]** — strip from the public repo; reattach via inherited scenes + gitignored CSVs when shipping Permaculture 4 Squares commercial.
