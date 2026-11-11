# Troon City: context for Claude

A SimCity-style city builder on Troon's real terrain (Ayrshire, Scotland), built in **Godot 4.7** (GDScript) by Sam.
Read this first, then `GAME_DESIGN.md` (the full design) before changing gameplay.

## Working with Sam
- Sam is semi non-technical: explain in plain words, keep replies short and don't repeat yourself.
- In-game text: plain, short, British English.
- One feature at a time; Sam plays it in Godot and reports back. Commit after each working feature.
- Godot can't be run by Claude in the cloud, so changes there are untested until Sam plays them. On Sam's Mac, Godot may be available; if so, check with `godot --headless --path . --quit` (or `--check-only` on a script).

## Project map
| Path | What |
| --- | --- |
| `game3d.tscn`, `scripts/game3d.gd` | Main scene: clock, input, tools, saving, `_refresh_hud()` each month |
| `scripts/simulation.gd` | The town's rules (no drawing): tiles, zones, growth, demand, happiness, taxes, services, power and water networks, rubbish, pollution, abandoned plots, districts, save/load |
| `scripts/settings.gd` | Every tuning number and the building catalogue (`Settings.BUILDINGS`) |
| `scripts/world3d.gd` | 3D world: terrain, sea, roads, buildings (boxes and .glb models), trees, props, overlays, day/night, coal smoke |
| `scripts/hud.gd` | Frosted-glass interface built in code: stats panel, Build menu, advisors card, info and overlay panels |
| `scripts/advisors.gd` | Advisor tips: a static function reading the sim |
| `scripts/traffic.gd` | Cars, buses and people near the camera (T toggles) |
| `scripts/camera_rig.gd`, `scripts/icons.gd` | Orbit camera; fallback SVG menu icons (made by `tools/make_icons.py`) |
| `shaders/` | building, roof, model, terrain, road, sea, foliage, glass |
| `assets/models/*.glb` | Building models made by `tools/make_buildings.py` |
| `assets/icons/*.png` | Build menu pictures rendered from the same models by `tools/make_menu_pictures.py` |
| `assets/textures/`, `assets/hdri/` | Photo textures (Poly Haven) and sky |
| `map/troon_map.json` | Real terrain (OS Terrain 50), made by `tools/make_troon_map.py` |
| `archive/2d/` | The old 2D version (Godot ignores it) |

## Code rules (these have caused real bugs)
- **Strict typing.** Never infer with `:=` from a Variant (Dictionary/Array element, untyped function or `sim` member): write `var x: float = d["k"]`. Type loop variables: `for i: int in n`. Godot errors "Cannot infer the type" otherwise.
- **Shared enums must match**: `Tile`, `Growth` and `Overlay` are repeated across scripts with asserts in `game3d.gd`. `hud.gd` `OVERLAY_NAMES`/`OVERLAY_TIPS` line up with `world3d.gd` `Overlay` by index.
- All tuning numbers go in `settings.gd`.
- New saves must still load old ones: read new fields with defaults.
- Every model swap keeps the old boxes as a fallback: `if _models.has("name"): _add_model(...) else: <boxes>`.
- Syntax check: `gdparse <file>` (pip package `gdtoolkit`).

## How things work (short)
- **Demand and happiness.** `happiness` (0–1) is built from parts: taxes vs services, services, leisure, rubbish, jobs, housing, power, water, pollution. `appeal() = 3 * happiness - 1` drives home demand: below 50% happiness nobody moves in, below 33% people leave. Shops and industry use `business_appeal()` (taxes, services, leisure, rubbish only). The `complaint_keys()`, `complaint_text()` and `complaint_fix()` wording is shared by the HUD, hover text and advisors.
- **Taxes** only hurt when services are poor (tax tolerance scales with service cover).
- **Growth.** Zones need a road (or bus cover), power, and water past the first stage. Districts: conservation caps height; the CBD allows skyscrapers (stages 7–8), which need transit cover.
- **Abandoned.** After 36 months in decline a plot may be boarded up. The instance colour alpha 0.5 tells the shaders (`COLOR.a < 0.75`) to draw it run-down.
- **Pollution** comes from industry, coal, gas, landfill and the harbour. Parks reduce it. It lowers land value and home growth, and has its own Pollution map view.
- **Rendering.** Box buildings use a MultiMesh with `INSTANCE_CUSTOM = (w, h, d, style)`. Models are stretched to each planned block and grouped into MultiMeshes per (model, 400 m chunk). `model.gdshader` picks its look per part by the .glb material name: stone, roof, glass, frame, door, metal, pot, fascia, render, awning, lead, cladding, sheet, accent. Modern blocks and skyscrapers are stacked storey by storey.

## Building models and menu pictures
- Built headless with Blender's Python module (pip `bpy`; 5.1.2 was used with Python 3.13):
  `python tools/make_buildings.py assets/models [preview_dir]`. Set `ONLY=name1,name2` to rebuild just some models; the previews are worth looking at.
- Blender +Y is the street side, and becomes local −Z after glTF export. Each model function returns `(builder, (w, d, wall_h, roof_rise))`, which must match `MODEL_DIMS` in `world3d.gd`.
- Menu pictures: `python tools/make_menu_pictures.py assets/icons assets/textures item1,item2`. They use the same models and textures, so the menu matches the game. (Sam rejected menu art that differs from in-game looks.)

## Progress so far
- **Phases 1–2 done:** map, roads and zones, save/load, growth, demand, money, power.
- **Phase 3 mostly done:**
  - services (police, fire, schools, hospitals, with funding)
  - land value, density and house prices
  - map views: land value, power, roads, growth, services, water, districts, pollution
  - taxes judged against services, and happiness
  - utilities: water network, rubbish
  - leisure and landmarks; transport (bus depot, station, harbour)
  - districts and skyscrapers
  - advisors, pollution and abandoned buildings
  - still to do: goals
- **Look:**
  - realistic 3D with photo textures, day and night, trees everywhere, tilt-shift
  - Troon-style models with variants: villas, bungalows, terraces, tenements, shops, sandstone classical blocks, fire station, school, hospital, power stations, clubhouse and more
  - modern stacked blocks; people and traffic
  - frosted-glass Build menu with pictures rendered from the models
- **Last delivered (Nov 2026), not yet played:**
  - happiness, advisors, pollution, abandoned buildings, traffic, new models, services wording
  - things to check in Godot: the run-down look of abandoned plots, the stadium end-stand orientation, coal smoke on the chimney tops, and stutter from advisors in big towns

## Ideas not started
- Goals and scenarios
- Sound
- Tutorial
- Publishing on itch.io
- Traffic affecting pollution or commutes
- Station canopies and landfill models
