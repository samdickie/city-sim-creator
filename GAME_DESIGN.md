# Troon City — Game Design (one page)

Read this at the start of every build session. Keep it up to date when decisions change.

## Goal
Build a thriving town on a blank map of Troon's real land and coastline. Balance money against happiness.

## Decisions
- **Engine:** Godot 4.6, GDScript. Free tools only.
- **Map:** OS Terrain 50 heights, 50 m per tile, 120 × 120 tiles. Starts entirely blank: no roads or buildings.
- **View:** Top-down 2D now. 3D (Terrain3D add-on, Blender or Kenney models) once the game is fun.
- **Rules live apart from drawing.** Simulation code must not depend on graphics, so 2D can become 3D later.
- **Simulate tiles and totals, not individual people.** No real traffic; a zone counts as connected if a road touches it.

## Tiles
| Tile | Notes |
| --- | --- |
| Road | Connects zones. Can't go on sea. |
| Homes | Residential zone. Grows houses and people (Phase 2). |
| Shops | Commercial zone. Needs people nearby (Phase 2). |
| Industry | Jobs; causes pollution (Phase 2). |

## Phases
1. **Sandbox** — map, pan and zoom, paint roads and zones, bulldoze, save and load. *Done when you can paint a city.*
2. **Living city** — simulation tick, demand, zones grow, power, taxes and upkeep. *Done when the city grows on its own.*
3. **Real game** — services, happiness, land value, overlay maps, goals. *Done when a friend asks for more.*
4. **Polish and share** — 3D art, sound, tutorial, publish on itch.io.

## Working rules
- One small feature per session; play it before moving on.
- Keep all tuning numbers (costs, growth rates) in one settings file.
- Commit to git after each working feature.
