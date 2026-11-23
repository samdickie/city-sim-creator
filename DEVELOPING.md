# Developing Silicon City

Notes for anyone changing the game. For how to play, see the [README](README.md).

For how everything works and progress so far, see `CLAUDE.md`; for the full design and the to-do list, `GAME_DESIGN.md`.

## The map

The game loads `map/menlo_park_map.json`:

- **What it covers:** Menlo Park, East Palo Alto and the Bay with the Dumbarton crossing.
- **Size:** 180 × 160 tiles at 50 m a tile.
- **Heights:** USGS and NOAA data, from AWS's free Terrain Tiles.
- **How it's made:** `tools/make_bay_map.py`, which works for any place (`--centre`, `--size`).

The earlier Palo Alto map is still in `map/`.

## Tools for building the game

| Command | What it does |
| --- | --- |
| `tools/screenshots.sh` | Builds a demo town and saves about 80 pictures of it |
| `tools/playtest.sh` | Plays the game with real mouse and key presses: about 500 checks |
| `tools/make_examples.sh` | Rebuilds the example cities |
| `tools/make_promo.sh` | Films a 27-second promo video |
| `python tools/make_buildings.py assets/models` | Builds the building models (needs Blender's `bpy`) |
| `python tools/make_menu_pictures.py ...` | Renders the Build menu pictures from the same models |

The test tools never touch your own saved city.

## Files

| Path | What it is |
| --- | --- |
| `game3d.tscn`, `scripts/game3d.gd` | The main scene: clock, mouse and keyboard, tools, saving |
| `scripts/simulation.gd` | The city's rules (no drawing code) |
| `scripts/settings.gd` | Every tuning number and the building catalogue |
| `scripts/world3d.gd` | Draws the 3D world: terrain, sea, roads, buildings, trees, day and night |
| `scripts/hud.gd` | The interface: Build menu, panels, letters, the guide |
| `scripts/advisors.gd`, `companies.gd` | Advisors' tips; the companies' letters |
| `scripts/traffic.gd`, `camera_rig.gd` | Cars and people on the streets; the camera |
| `shaders/` | Terrain, plots, sea, roads, buildings, foliage and glass |
| `assets/models/` | Building models, made by `tools/make_buildings.py` (Blender) |
| `assets/icons/` | Build menu pictures, rendered from the same models |
| `map/` | The maps |
| `examples/` | The example cities (ordinary save files) |
| `GAME_DESIGN.md` | The design: every system and the to-do list |
| `CLAUDE.md` | Notes on how everything works, and progress so far |
