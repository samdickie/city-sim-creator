# Troon City

A SimCity-style city builder on Troon's real terrain. Built with Godot (free).

**Status: Phase 3 – Real game, in 3D.** Services, happiness, pollution, advisors and districts are in. See `CLAUDE.md` for progress and `GAME_DESIGN.md` for the design.

## Play it

1. Install **Godot 4.7** (free) from https://godotengine.org/download and open it.
2. In the Project Manager, choose **Import**, pick this folder's `project.godot`, then **Import & Edit**.
3. Press **Play** (▶, top right) or F5.

| Control | Action |
| --- | --- |
| Left-drag | Preview, then release to build (Esc cancels) |
| 1–9 | Road, Homes, Shops, Industry, Bulldoze, Power plant, Power line, Park, Street grid |
| Two-finger scroll, middle-drag, WASD | Move around |
| Right-drag, Q / E, Shift + two-finger scroll | Rotate and tilt |
| Pinch or mouse wheel | Zoom |
| Space / F / H | Pause / fast-forward / help |
| Cmd+S / Cmd+L | Save / Load |

## The map

The game loads `map/troon_map.json`. It holds Troon's real terrain (OS Terrain 50).

To switch to real Troon:

1. Download **OS Terrain 50** in **ASCII Grid** format (free, no sign-up): https://osdatahub.os.uk/data/downloads/open/Terrain50
2. From this folder, run:
   `python3 tools/make_troon_map.py ~/Downloads/<the zip you downloaded>`
3. Check `map/preview.png` looks like Troon, then press Play.

The map covers 7 × 6.5 km around Troon (harbour, town centre, Barassie, Royal Troon and the hills to the east) at 50 m per tile, giving 140 × 130 tiles. Low ground joined to the map edge becomes sea.

## Files

| Path | What it is |
| --- | --- |
| `game3d.tscn` | The game's main scene |
| `scripts/game3d.gd` | Runs the game: clock, mouse and keyboard, saving |
| `scripts/simulation.gd` | The city's rules (no drawing code) |
| `scripts/settings.gd` | Every tuning number |
| `scripts/world3d.gd` | Draws the 3D world: terrain, roads, buildings, trees, day and night |
| `scripts/hud.gd`, `camera_rig.gd`, `traffic.gd` | Interface (Build menu, panels), camera, cars and people on the streets |
| `scripts/icons.gd` | Build menu pictures, made by `tools/make_icons.py` |
| `shaders/` | Terrain, sea, road, wall, roof, model, foliage and glass looks |
| `assets/models/` | Building models, made by `tools/make_buildings.py` (Blender) |
| `archive/2d/` | The old 2D version, kept for reference (Godot ignores it) |
| `map/` | The map file and its preview picture |
| `tools/make_troon_map.py` | Converts OS height data into the map file |
| `GAME_DESIGN.md` | One-page design doc — read this before each build session |

## Credits

Real-terrain maps contain OS data © Crown copyright and database right (Open Government Licence). The credit shows in the game automatically.
