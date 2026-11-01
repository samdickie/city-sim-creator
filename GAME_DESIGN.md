# Troon City — Game Design (one page)

Read this at the start of every build session. Keep it up to date when decisions change.

## Goal
Build a thriving town on a blank map of Troon's real land and coastline. Balance money against happiness.

## Decisions
- **Engine:** Godot 4.7, GDScript. Free tools only.
- **Map:** OS Terrain 50 heights, 50 m per tile, 140 × 130 tiles (7 × 6.5 km). Starts entirely blank: no roads or buildings.
- **View:** Realistic 3D (Forward+ renderer): real terrain, sea, sky and sun; buildings modelled on Troon (sandstone villas and tenements, slate roofs). Free photo textures from Poly Haven drop into `assets/textures/` and are used automatically. The old 2D view is kept in `main.tscn` as a backup.
- **Rules live apart from drawing.** Simulation code must not depend on graphics, so 2D can become 3D later.
- **Simulate tiles and totals, not individual people.** No real traffic; a zone counts as connected if a road touches it.

## Tiles
| Tile | Notes |
| --- | --- |
| Road | Connects zones. Can't go on sea. |
| Homes | Residential zone. Grows houses and people (Phase 2). |
| Shops | Commercial zone. Needs people nearby (Phase 2). |
| Industry | Jobs; causes pollution (Phase 2). |

## Money
- Start with £20,000. Every build costs money; bulldozing a built tile costs £5.
- Hills cost more (+8% per metre of slope); tiles steeper than 12 m can't be built on.
- All numbers live in `scripts/settings.gd`.

## Growth (Phase 2)
- One game month every 3 seconds (Space pauses, F fast-forwards).
- A zone grows when a road is within 2 tiles and the town wants more of it. Each zone grows in 3 levels.
- Homes add 20 people per level; shops 8 jobs; industry 15 jobs.
- Demand: homes follow jobs, shops follow residents, industry soaks up spare workers.
- Taxes (default 9%) come in monthly from residents and jobs; roads cost £0.50 per tile per month. Higher taxes cut demand.
- Rules live in `scripts/simulation.gd`, with no drawing code.

## Power
- Zones need electricity to grow; plots without it slowly shrink.
- A power plant (£3,000, £100/month upkeep) powers 200 zone levels.
- Power spreads through any touching built tiles: roads, zones, power lines (£5) and other plants.
- When a network runs short, plots furthest from the plant lose power first.

## Phases
1. **Sandbox** — map, pan and zoom, paint roads and zones, bulldoze, save and load. *Done when you can paint a city.*
2. **Living city** — simulation tick, demand, zones grow, power, taxes and upkeep. *Done when the city grows on its own.*
3. **Real game** — services, happiness, land value, overlay maps, goals. *Done when a friend asks for more.*
4. **Polish and share** — 3D art, sound, tutorial, publish on itch.io.

## Working rules
- One small feature per session; play it before moving on.
- Keep all tuning numbers (costs, growth rates) in one settings file.
- Commit to git after each working feature.
