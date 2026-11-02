# Troon City

A SimCity-style city builder on Troon's real terrain. Built with Godot (free).

**Status: Phase 2 – Living city, now in 3D.** Zones grow when they have a road and power; demand, taxes and upkeep run monthly.

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

The game loads `map/troon_map.json`. Right now it holds a **made-up placeholder coast**, so everything works before the real data is added.

To switch to real Troon:

1. Download **OS Terrain 50** in **ASCII Grid** format (free, no sign-up): https://osdatahub.os.uk/data/downloads/open/Terrain50
2. From this folder, run:
   `python3 tools/make_troon_map.py ~/Downloads/<the zip you downloaded>`
3. Check `map/preview.png` looks like Troon, then press Play.

The map covers 7 × 6.5 km around Troon (harbour, town centre, Barassie, Royal Troon and the hills to the east) at 50 m per tile, giving 140 × 130 tiles. Low ground joined to the map edge becomes sea.

## Files

| Path | What it is |
| --- | --- |
| `scripts/main.gd` | All game code for Phase 1 |
| `main.tscn` | The game's main scene |
| `map/` | The map file and its preview picture |
| `tools/make_troon_map.py` | Converts OS height data into the map file |
| `GAME_DESIGN.md` | One-page design doc — read this before each build session |

## Credits

Real-terrain maps contain OS data © Crown copyright and database right (Open Government Licence). The credit shows in the game automatically.
