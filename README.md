# Troon City

A SimCity-style city builder on Troon's real terrain. Built with Godot (free).

**Status: Phase 1 – Sandbox.** Paint roads and zones on a blank map, then save and load. The city doesn't grow yet; that's Phase 2.

## Play it

1. Install **Godot 4.6** (free) from https://godotengine.org/download and open it.
2. In the Project Manager, choose **Import**, pick this folder's `project.godot`, then **Import & Edit**.
3. Press **Play** (▶, top right) or F5.

| Control | Action |
| --- | --- |
| Left-drag | Build with the current tool |
| 1–5 | Road, Homes, Shops, Industry, Bulldoze |
| Right-drag, WASD, arrow keys, two-finger scroll | Move around |
| Mouse wheel or pinch | Zoom |
| Cmd+S / Cmd+L | Save / Load |

## The map

The game loads `map/troon_map.json`. Right now it holds a **made-up placeholder coast**, so everything works before the real data is added.

To switch to real Troon:

1. Download **OS Terrain 50** in **ASCII Grid** format (free, no sign-up): https://osdatahub.os.uk/data/downloads/open/Terrain50
2. From this folder, run:
   `python3 tools/make_troon_map.py ~/Downloads/<the zip you downloaded>`
3. Check `map/preview.png` looks like Troon, then press Play.

The map covers 6 × 6 km around Troon (harbour, town centre, Barassie, Royal Troon) at 50 m per tile, giving 120 × 120 tiles. Low ground joined to the map edge becomes sea.

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
