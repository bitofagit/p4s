# Permaculture 4 Squares (P4S)

**Version 0.9.5.27** — Open-source permaculture farming simulator built with **Godot 4**.

You plant crops on a grid, manage soil as a living system, and sleep to advance the calendar. This is the **open-core** edition (Permaculture 101 / sandbox). It is free under the [MIT Licence](LICENSE).

---

## What you need

| Requirement | Details |
|-------------|---------|
| **Godot** | **4.6.x** (Stable). This project was built for Godot **4.6**. Older 4.x may open with warnings; Godot 3 will **not** work. |
| **Computer** | Windows, macOS, or Linux |
| **Download size** | A few hundred MB once Godot imports assets on first open |

**Get Godot here:** [https://godotengine.org/download](https://godotengine.org/download)

- Choose **Godot Engine** (standard editor), **not** the .NET / C# build (this project uses GDScript only).
- Pick your OS, download the zip, and unzip it somewhere easy to find (e.g. Applications, Desktop, or `C:\Godot`).

---

## Install and run (absolute beginners)

### 1. Get the game files

**Option A — Download a zip (easiest)**

1. Open the releases page: [https://github.com/bitofagit/p4s/releases](https://github.com/bitofagit/p4s/releases)
2. Download the latest release (**v0.9.5.27** or newer). Older releases such as **v0.9.5.26** stay available if you need them.
3. Unzip the archive to a folder you can find again.

**Option B — Clone with Git**

```bash
git clone https://github.com/bitofagit/p4s.git
cd p4s
```

### 2. Open the project in Godot

1. Launch **Godot 4.6**.
2. In the Project Manager, click **Import** (or **Scan** if you prefer).
3. Browse to the folder that contains **`project.godot`** and select that file.
4. Click **Import & Edit**.

**Important:** Open **this** project folder — the one with `project.godot`, `scenes/`, `scripts/`, and `data/` at the top level.

Do **not** open nested stub folders such as `p-4s-8.5.26/` or `new-game-project/`. Those are old leftovers and are not the game.

### 3. First load (wait for import)

The first time you open the project, Godot imports sprites and data. That can take a few minutes. Wait until the editor looks ready (no big “Importing…” progress blocking everything).

### 4. Play

- Press **F5**, or click the **Play** button (▶) in the top-right of the editor.
- The main menu should appear. Start a new game or load a save from there.

---

## Quick controls (in-game)

Exact bindings can change with settings, but typically:

- **Pan** the map with middle-mouse drag, or trackpad / arrow keys
- **Zoom** with the mouse wheel
- **Click** tiles to inspect / use tools from the HUD
- **Esc** opens the pause / graphics menu
- **Sleep** advances time after you have planned your day’s work

Graphics presets (**Low / Medium / High / Custom**) live under Graphics settings — start on **Low** if the farm feels slow.

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| “Failed to load” / missing scripts | Confirm you opened the folder with `project.godot` at the root, and you are on **Godot 4.6**. |
| Blank or pink textures | Wait for first-time import to finish, then close and reopen the project. |
| Very slow on a laptop | Use Graphics → Quality Preset → **Low**. |
| Empty seed inventory in an exported `.exe` | Prefer running from the Godot editor with this repo, or download a fresh release build that includes packed `data/*.csv` files. |
| Wrong Godot version warning | Install [Godot 4.6 Stable](https://godotengine.org/download) and open the project with that editor. |

---

## Releases (old versions stay available)

- Latest: [v0.9.5.27](https://github.com/bitofagit/p4s/releases/tag/v0.9.5.27)
- Previous: [v0.9.5.26](https://github.com/bitofagit/p4s/releases/tag/v0.9.5.26)

New tags do **not** delete older ones. You can always download a previous version from the [Releases](https://github.com/bitofagit/p4s/releases) page.

---

## Documentation for developers

If you are changing code or design (not just playing):

- **[Codebase guide](docs/CODEBASE_GUIDE.md)** — Scenes, autoloads, map, HUD, and `data/`
- **[Architecture](docs/ARCHITECTURE.txt)** — Scene flow and persistence boundaries
- **[Open Core](obsidian/10_Open_Core_Architecture.md)** — Public vs premium content rules
- **[Recent engineering notes](docs/GEMINI_RECENT_CHANGES.txt)** — LOD, graphics presets, export notes

---

## Licence

MIT — see [LICENSE](LICENSE).
