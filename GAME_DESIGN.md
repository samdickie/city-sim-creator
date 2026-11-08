# Troon City — Game Design (one page)

Read this at the start of every build session. Keep it up to date when decisions change.

## Goal
Build a thriving town on a blank map of Troon's real land and coastline. Balance money against happiness.

## Decisions
- **Engine:** Godot 4.7, GDScript. Free tools only.
- **Map:** OS Terrain 50 heights, 50 m per tile, 140 × 130 tiles (7 × 6.5 km). Starts entirely blank: no roads or buildings.
- **View:** Realistic 3D (Forward+ renderer): real terrain, sea, sky and sun; buildings modelled on Troon (sandstone villas and tenements, slate roofs). Free photo textures from Poly Haven drop into `assets/textures/` and are used automatically. The old 2D version is kept in `archive/2d/` for reference (Godot ignores it).
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
- Demand: people from the region want to move in (100 plus 4% of the population), more for spare jobs and fewer when people are out of work. Shops and offices want 0.2 jobs per resident; industry employs the remaining workers.
- Taxes (default 9%) and services together set the town's appeal. Each 1% above 9% cuts the pull by 10% (each 1% below adds 10%), but people put up with taxes they can see paying for services: with every home fully covered, high taxes hurt only 0.3x as much; with no services, 1.3x. Bigger towns also expect services (full cover expected from 4,000 people, up to 70%), and better or worse than expected moves appeal up or down.
- People only leave when appeal drops below 0 (high taxes AND poor services), and the worst-served plots shrink first. A well-served town still grows at 20% tax. The HUD shows services (good, patchy, poor) and how taxes are going down. Roads cost £0.50 per tile per month.
- Rules live in `scripts/simulation.gd`, with no drawing code.

## Happiness
- One number, 0-100%, sums up how residents feel, and it is what draws people in: demand for homes = (100 + 4% of the population) x appeal, where appeal = 3 x happiness - 1, plus the pull of spare jobs. 67% is a normal town; below 50% people stop moving in; below 33% they leave.
- Made of parts in appeal points, added to 1: taxes against services (as above), services against what people expect, leisure (up to +0.3), uncollected rubbish (up to -0.5), unemployment above 5% (x2, from 400 people), housing shortage (up to -0.15), share of homes without power (up to -0.8) or water (up to -0.6). Pollution can be added later as one more part.
- Businesses weigh only the town-wide parts (taxes, services, leisure, rubbish), so jobs, housing, power and water problems don't stop shops and industry coming to fix them. The tax line uses the same.
- HUD: "Happiness 72%: happy" under the population; below 60% it shows the main complaint, red below 50%. Zone hover text names the top complaint and its fix. Words: delighted (80+), happy (60+), content (50+), unhappy (33+), angry.
- Worked out from the town each month (and when taxes change), so nothing extra is saved. Numbers in `Settings` under Happiness; complaint wording in `COMPLAINTS` in `simulation.gd`.

## Zoning density
- Homes and shops are zoned low, medium or high density (Tab or the buttons above the toolbar). Industry has one density.
- A plot's building stage = its level + the density's head start: 1 villas, 2 terraces, 3 tenements, 4 mansion flats, 5 modern flats, 6 towers (shops: corner shops up to an office tower).
- Low: stages 1-2 (never above 2 storeys). Medium: stages 2-4 (mansion flats only when space is short). High: stages 3-6 (as high as land value allows: stage 4/5/6 need 0.35/0.5/0.65).
- Each stage holds more people/jobs (homes 20/40/60/100/150/220) and uses more power. Zoning costs more the denser you go (homes £40/60/100, shops £60/80/120).
- Each month, valuable plots that can build taller go first; then everything else grows in random order.
- Re-zone by dragging a different density over an area; buildings trim to the new maximum.

## Districts and skyscrapers
- District tool (Z) paints a height rule over any land, free: CBD, conservation area, or back to normal. Choosing it shows the Districts map view.
- Conservation area: nothing above stage 3 (tenements, four storeys); +0.03 land value for character. Existing taller buildings are trimmed back.
- CBD: high-density homes and shops can rise two more stages, to skyscrapers: stage 7 (20-26 storeys; 350 residents or 160 jobs) and stage 8 (32-42 storey landmark with two setbacks and a spire; 500 residents or 260 jobs). +0.08 land value across the CBD, and tall buildings grow 1.5x faster there.
- Skyscrapers also need land value 0.72 / 0.8, a town of 8,000 people, and a working railway station or bus depot within 600 m. Each stands on a three-storey podium (glass, or classical with shopfronts) with a planted plaza behind.

## Building models
- Low-rise Troon buildings are detailed 3D models made in Blender by `tools/make_buildings.py` (saved to `assets/models/*.glb`): villa, bungalow (dormers), terrace of three, tenements (3 and 4 storeys, canted bays, close door, cornice, chimney stacks), shop parades (one storey, or two with flats and a slate roof) and sandstone shops with flats (2-4 storeys, flat roof with lift housing and vents).
- Details are real geometry: sash windows with frames and glazing bars, stone sills, lintels and surrounds, bay windows, doors with fanlights and steps, skews, gutters, chimney pots, shopfronts with fascias and awnings.
- Variants so streets don't repeat: three villas (bay and door; hipped with a porch; twin bays with a central gable), two bungalows, two terraces (bays; flat fronts with dormers), two of each tenement (bays; flat-fronted with wallhead gables), two of each shop parade. One is picked per building by its position.
- Also modelled: an industrial shed (ribbed metal over a brick base, roller doors, office, roof lights) used for every pitched industrial building (works, factories, gas plant hall, recycling, bus depot, harbour warehouse); and the classical sandstone block in 2-7 storeys (plain, with shopfronts, or with bays) used for mansion flats, classical offices, police station, library, museum, town hall and station.
- Civic models: a red sandstone fire station (three engine bays with red doors front and back, crew rooms above, flagpole) and its hose-drying tower; a Victorian board school (gabled wings, entrance porch, tall many-paned windows, bellcote, ridge ventilators); and a modern hospital (ribbon windows, glazed stair tower, red cross on a white pier, roof plant, helipad space).
- Modern blocks and skyscrapers are stacked storey by storey from four models, so any height looks right: a glazed ground floor with entrance canopy, upper storeys (glazed and clad bays, or punched windows in deep frames; or all-glass curtain walling for offices and the best land) and a roof with a set-back penthouse and glass-edged terrace.
- An "accent" material takes the building's second colour (fire station doors, the hospital's cross).
- The game swaps in these models wherever a matching block is planned, stretched to fit; everything else still uses the simple blocks. Materials get the game's own shader (`shaders/model.gdshader`): stone and slate photo textures, varied door and shopfront colours, windows lit at night, map overlay colours.
- Models are drawn in 400 m squares, so Godot can skip what's off screen and use simpler versions far away.

## Tall building design
- Taller plots mix two families: classical sandstone (rusticated ground floor, sash windows in stone surrounds, bay windows, cornice, slate mansard with dormers; classical shopfronts for shops) and modern premium (glass ground floor, framed glazing with timber/bronze/stone bays, staggered glass balconies, set-back glass penthouse, roof canopy; all glass on the best land).
- Courts between tall blocks are landscaped (lawn, path, trees) with parking underground.

## Density, land value and prices
- Plots grow freely up to stage 3 (tenements) whenever there's demand. Industry stops at 3.
- When demand is more than those plots can still take, the town is "short of space": medium-density plots may rise to mansion flats, and high-density plots build upwards (stage 4/5/6 need land value 0.35/0.5/0.65).
- Land value (0-1): base 0.3, up to +0.3 by the sea, plus parks and shops nearby; minus industry, power plants and pollution nearby.
- Better land gets better buildings (glass on the best land) and pays more tax (0.6x to 1.4x).
- Home prices = £160k x (0.5 + land value) x (1 + 0.8 x housing shortage).

## Power
- Zones need electricity to grow; plots without it slowly shrink.
- Power tool (6), pick with Tab: coal plant (£3,000, £100/month, 200 units, smoky), gas plant (£5,000, 400 units, from 1,000 people), nuclear (£15,000, 1,500 units, from 5,000 people), wind turbines (£400 a tile, 25 units each, drag a wind farm), solar farm (£300 a tile, 15 units, from 300 people), power lines (£5).
- Power spreads through any touching built tiles: roads, zones, power lines (£5) and other plants.
- When a network runs short, plots furthest from the plant lose power first.

## Build menu
- A frosted-glass panel, bottom left: categories down the side (All, Zones, Roads, Power, Utilities, Services, Leisure, Transport, Districts); each item has a small isometric picture, a name, a one-line description and its price (padlock and "Needs N people" while locked; the full explanation on hover).
- Build button shows or hides it (M); Bulldoze button beside it. Number keys and Tab still pick tools, and the menu follows.
- All the interface panels use the same frosted glass (blurred game behind, rounded corners, hairline edge).
- Item pictures are rendered in Blender by `tools/make_menu_pictures.py` (into `assets/icons/`): a small diorama of each plot built from the same models, colours and photo textures the game uses, so the picture matches what gets built. The drawn icons in `scripts/icons.gd` (from `tools/make_icons.py`) are only a fallback.

## Building tools
- Press, drag to preview (with total cost), release to build; Esc cancels.
- Roads and power lines run straight with one corner. Zones and parks: drag a box; start on a road to zone both sides of every road in the box, two plots deep.
- Street grid (9): drag a box to lay streets every third tile (100 m blocks).
- Corner and through plots build along every road they touch.
- Zoned plots waiting to grow show building sites; leftover open land inside the town becomes pocket parks, allotments or car parks (looks only).

## Water and rubbish (Utilities, 7)
- Anything bigger than a first-level plot needs water. Water pumps (£800, 400 units, need power) and water towers (£300, 120 units) supply it; it travels through roads and buildings like power, nearest plots first.
- Towns over 400 people make rubbish (1 per resident, 0.5 per job). Landfill (£100 a tile, takes 800, lowers land value nearby) and recycling centres (£2,500, takes 2,500, from 1,000 people) collect it. Uncollected rubbish cuts appeal (up to -0.5).

## Leisure and landmarks (-)
- Golf course (£150 a tile, drag to lay out holes), library (from 500 people), museum (2,000), stadium (5,000, one only), marina (1,500, by the sea), town hall (1,000, one only). Each raises land value round it and the town's appeal (all together up to +0.3), and costs upkeep. They need a road (and power, except golf).

## Transport (=)
- Bus depot (from 500 people): plots within 700 m can grow 3 tiles from a road instead of 2.
- Railway station (2,000): visitors add shop demand (3% of the population each, up to two stations); raises land value.
- Harbour (1,000, by the sea): ships bring trade, +80 industry demand each.
- All the numbers for these buildings are in `Settings.BUILDINGS`.

## Services
- Services tool (0), then pick one (Tab or the buttons): police station £1,500, fire station £1,500, school £2,000, hospital £4,000. One tile each; they need a road and power (3 units) to work.
- Each covers the area round it: fully close by, fading out at its reach (police 800 m, fire 700 m, school 600 m, hospital 1 km at 100% funding). Covered areas gain land value.
- Funding (- / +, 0-150%) sets upkeep (police £60, fire £60, school £80, hospital £150 a month at 100%) and reach (50% funding reaches 70% as far; 0% closes it).
- Effects: over 800 people, homes and shops with no police grow at half speed; over 1,200, homes need a school to grow past terraces; over 2,500, homes with no hospital grow at half speed; over 500, built plots with no fire cover can burn down (rarely; industry twice as often).
- A Services map view shows how many of the four cover each area.

## Map views (overlays)
- O or the buttons bottom right: Normal, Land value, Power, Roads, Growth, Services, Water, Districts, Pollution. Each has a colour key.
- Ground and buildings take each plot's colour; trees, paving and parked cars hide so the colours read clearly.
- Land value uses the same bands as the hover text (0.2 / 0.35 / 0.5 / 0.65). Growth: green growing, yellow waiting (demand, space or land value), red stuck (road or power), blue fully built.

## Pollution
- A pollution map (0 clean to 1 heavy) is worked out every month and whenever the town changes; it isn't saved (loading works it out again).
- Sources add up where they overlap, fading out with distance: industry 0.06 per stage (200 m), coal plant 1.2 (450 m), gas plant 0.5 (300 m), harbour 0.35 (250 m), landfill 0.12 per tile (200 m), recycling 0.08 (100 m). Nuclear, wind and solar are clean. Parks soak some up (golf half as much). The total is eased into 0-1, so a coal plant is "heavy" for about 200 m.
- Effects: land value -0.2 in full pollution; homes grow up to 60% slower in polluted air (the hover text says so); the share of residents in polluted air (0.3 or more) costs up to -0.15 appeal. The old land value penalties of industry, power plants, landfill and the harbour were halved or so, as the smoke is now counted here.
- Pollution map view: clean, a little, some, polluted, heavy (green to red). Hover text mentions pollution from "some" upwards, and polluting buildings say how far their pollution reaches.
- Coal plant chimneys smoke (a few particle streams; looks only).
- For a happiness score or advisors: `pollution_at(i)`, `pollution_band(i)`, `polluted_homes_share()`, `pollution_feeling()` (already in appeal), `air_word()` in `scripts/simulation.gd`. Numbers in the Pollution section of `scripts/settings.gd`.

## Look and feel
- Trees come in kinds: broadleaf (oak, sycamore, lime), birch, columnar (poplar, leylandii), Scots pine, spruce, small ornamentals and copper beech, each with its own shape, size and colour. Canopies are clusters of lumpy blobs with leaf-clump shading.
- Natural woods and lone trees cover open land and are cleared where you build; parks (£100, £1/month) keep their trees and gain more.
- Every straight street gets trees on both sides (one kind per street, like an avenue), except beside industry and power plants. Gardens, tenement courts, landscaped courts and shop car parks get trees too.
- Cars drive on the left along the roads, more as the population grows (purely visual).
- A full day and night every 4 minutes at normal speed: the sun crosses the sky, windows and street lights come on at dusk. A "Day & night" button turns it off.

## Phases
1. **Sandbox** — map, pan and zoom, paint roads and zones, bulldoze, save and load. *Done when you can paint a city.*
2. **Living city** — simulation tick, demand, zones grow, power, taxes and upkeep. *Done when the city grows on its own.*
3. **Real game** — services (done), land value (done), overlay maps (done), taxes vs services (done), happiness (done), goals. *Done when a friend asks for more.*
4. **Polish and share** — 3D art, sound, tutorial, publish on itch.io.

## Working rules
- One small feature per session; play it before moving on.
- Keep all tuning numbers (costs, growth rates) in one settings file.
- Commit to git after each working feature.
