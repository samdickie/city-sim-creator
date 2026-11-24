# Silicon City — Game Design (one page)

Read this at the start of every build session. Keep it up to date when decisions change.

## Goal
Build a thriving town on a blank map of the Bay Area's real land and coastline. Balance money against happiness.

## Decisions
- **Engine:** Godot 4.7, GDScript. Free tools only.
- **Map:** **Palo Alto**, on the San Francisco Peninsula (the real Silicon Valley), from Nov 2026: downtown Palo Alto and the edge of Stanford to the west, East Palo Alto and the Baylands' marshes, and the open Bay to the north-east; very flat (highest 46 m), 12% water. Real heights from USGS 3DEP / NOAA via the AWS Terrain Tiles open data (`tools/make_bay_map.py`, which can make any place: `--centre LAT LON --size W H`). 50 m per tile, 140 × 130 tiles (7 × 6.5 km), the same as before. Starts entirely blank: no roads or buildings. The town's name top left is the map's name.
- **View:** Realistic 3D (Forward+ renderer): real terrain, sea, sky and sun; Californian buildings (stucco homes under clay-tile roofs, Mission revival blocks, glass offices). Free photo textures from Poly Haven drop into `assets/textures/` and are used automatically.
- **Rules live apart from drawing.** Simulation code must not depend on graphics, so 2D can become 3D later.
- **Simulate tiles and totals, not individual people.** A zone counts as connected if a road is near it. Traffic is a light model of trips a day per road tile (see Traffic), not individual cars; for now it is only shown, it doesn't hold the town back.

## Tiles
| Tile | Notes |
| --- | --- |
| Road | Connects zones. Can't go on sea. |
| Homes | Residential zone. Grows houses and people (Phase 2). |
| Shops | Commercial zone. Needs people nearby (Phase 2). |
| Industry | Jobs; causes pollution (Phase 2). |

## Money
- Every build costs money; bulldozing a built tile costs £5. With less money than something costs (or below zero) you can't build it; there's no bankruptcy or game over: taxes slowly bring money back.
- Hills cost more (+8% per metre of slope); tiles steeper than 12 m can't be built on.
- All numbers live in `scripts/settings.gd` (`DIFFICULTIES`, the loan numbers under Money).

### Difficulty (picked for each new city)
| | Easy | Normal | Hard |
| --- | --- | --- | --- |
| Starting money | £100,000 | £50,000 | £20,000 |
| Monthly upkeep (every running cost) | x0.8 | x1 | x1.25 |
| Loan interest (a year) | 4% | 6% | 9% |
| Most you can owe | £100,000 | £60,000 | £30,000 |
- Purely money: demand, happiness, growth, build prices and taxes are the same at every level.
- A "New city" dialog (three cards, Normal picked) opens when the game starts and from New city in the game menu; the game is paused behind it. 1-3 or the arrows pick, Enter starts, Esc cancels (on first launch that starts Normal; from the menu it keeps the city). It can't be changed mid-game.
- Saved with the city and shown in the City panel ("Budget · Normal"). Saves from before difficulty load as Normal (x1, as before) with their money unchanged and nothing owed. Save version 4.

### Loans
- City panel (click the status strip), Loans: what's owed, the monthly payment, Borrow £5,000 / £20,000 (greyed out, with the reason, past the level's limit), Repay £5,000 / Repay all (greyed out with nothing owed or not enough money).
- One running balance. Borrowing adds to the money and the balance. Each month you pay the interest (balance x yearly rate / 12) plus a slice of 1/120 of the most owed since it was last clear (at least £20), so a loan is paid off in about 10 years. Repaying early saves interest.
- The payment is made even when the money is below zero (it just goes further below). The budget shows Taxes / Upkeep / Loan payments / Balance, and the status strip's "last month" includes loan payments.
- Advisors: "Short of money: take a loan in the City panel" (money under £2,000 and borrowing possible); out of money suggests a loan when one is possible; a warning when loan payments are more than 25% of taxes.

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
- Made of parts in appeal points, added to 1: taxes against services (as above), services against what people expect, leisure (up to +0.3), uncollected rubbish (up to -0.5), unemployment above 5% (x2, from 400 people), housing shortage (up to -0.15), share of homes without power (up to -0.8) or water (up to -0.6). Pollution is one more part: the share of residents in polluted air (up to -0.15).
- Businesses weigh only the town-wide parts (taxes, services, leisure, rubbish), so jobs, housing, power and water problems don't stop shops and industry coming to fix them. The tax line uses the same.
- HUD: the status strip shows "72% happy" (green, amber below 60%, red below 50%); the City panel has a bar and the main complaints with their fixes. Zone hover text names the top complaint and its fix. Words: delighted (80+), happy (60+), content (50+), unhappy (33+), angry.
- Worked out from the town each month (and when taxes change), so nothing extra is saved. Numbers in `Settings` under Happiness; complaint wording in `COMPLAINTS` in `simulation.gd`.

## Abandoned buildings
- A built plot is "in decline" in any month it has no road nearby, no power, no water (anything past the first stage), far more of its kind than the town wants (homes with no jobs, shops with no customers, industry with no workers) or the town is very unpopular (appeal below 0.2, i.e. happiness below 40%; the hover text names residents' main complaint).
- Decline still trims plots back a level at a time, but never removes the last building. After 36 months in decline (each good month counts 3 back off) there's a 10% chance a month the building is abandoned: it houses nobody, has no jobs, pays no tax, uses no power or water and takes a little land value off the plots round about (0.04 on its own plot, fading out over 2 tiles).
- Abandoned buildings look run down: faded, grimy walls, mossy roofs, boarded-up windows and doors, no lights at night and no cars outside. The hover text says "Abandoned — why"; plots in decline for 18 months or more warn that they're run down.
- Once nothing's wrong and the town wants what it held again, it's done up (10% a month) and fills up again. Or bulldoze it.
- The City panel shows how many are abandoned and run down, a message pops up when buildings are abandoned, and the Growth map shows them in brown. Rules and numbers are in `scripts/settings.gd`; it should be rare in a healthy town.

## Zoning density
- Homes and shops are zoned low, medium or high density (Tab or the buttons above the toolbar). Industry has one density.
- A plot's building stage = its level + the density's head start: 1 villas, 2 terraces, 3 tenements, 4 mansion flats, 5 modern flats, 6 towers (shops: corner shops up to an office tower).
- Low: stages 1-2 (never above 2 storeys). Medium: stages 2-4 (mansion flats only when space is short). High: stages 3-6 (as high as land value allows: stage 4/5/6 need 0.35/0.5/0.65).
- Each stage holds more people/jobs (homes 20/40/60/100/150/220) and uses more power. Zoning costs more the denser you go (homes £40/60/100, shops £60/80/120).
- Each month, valuable plots that can build taller go first; then everything else grows in random order.
- Re-zone by dragging a different density over an area; buildings trim to the new maximum.

## Districts and skyscrapers
- District tool (Z) paints a rule over any land, free: CBD, Tech zone, conservation area, or back to normal. Choosing it shows the Districts map view (Tech zones in teal).
- Tech zone: offices and industry in it pay its own tax rate (see Tech layer, Tech zone); no height rule of its own. A tile is one kind of district, so a Tech zone can't also be a CBD.
- Conservation area: nothing above stage 3 (tenements, four storeys); +0.03 land value for character. Existing taller buildings are trimmed back.
- CBD: high-density homes and shops can rise two more stages, to skyscrapers: stage 7 (20-26 storeys; 350 residents or 160 jobs) and stage 8 (32-42 storey landmark that steps in twice, often with a spire; 500 residents or 260 jobs). +0.08 land value across the CBD, and tall buildings grow 1.5x faster there.
- Skyscrapers also need land value 0.72 / 0.8, a town of 8,000 people, and a working railway station or bus depot within 600 m. Each stands on a three-storey podium (glass, or classical with shopfronts) with a planted plaza behind.

## Building models
- Low-rise buildings are detailed 3D models made in Blender by `tools/make_buildings.py` (saved to `assets/models/*.glb`): villa, bungalow (dormers), terrace of three, tenements (3 and 4 storeys, canted bays, close door, cornice, chimney stacks), shop parades (one storey, or two with flats and a slate roof) and sandstone shops with flats (2-4 storeys, flat roof with lift housing and vents).
- Details are real geometry: sash windows with frames and glazing bars, stone sills, lintels and surrounds, bay windows, doors with fanlights and steps, skews, gutters, chimney pots, shopfronts with fascias and awnings.
- Variants so streets don't repeat: three villas (bay and door; hipped with a porch; twin bays with a central gable), two bungalows, two terraces (bays; flat fronts with dormers), two of each tenement (bays; flat-fronted with wallhead gables), two of each shop parade. One is picked per building by its position.
- Also modelled: an industrial shed (ribbed metal over a brick base, coloured roller doors, office, roof lights), an old brick works with a north-light sawtooth roof, and a modern distribution warehouse (loading docks, glazed office pod); and the classical sandstone block in 2-7 storeys (plain, with shopfronts, or with bays) used for mansion flats, classical offices, police station, library, museum, town hall and station.
- Colour and character: house streets share a palette per neighbourhood (red sandstone, blonde sandstone, white and cream harling under dark slate; pebbledash under red and brown tiles; modern brick), so streets read as places. High streets mix sandstone with painted render in many colours; shopfronts are painted in different colours with lettered fascia signs, and their windows stay lit in the evening. Flat roofs are dark membrane, gravel or the odd sedum roof.
- Industry grows heavier by stage: small units or an old sawtooth works; then a bigger shed, works or warehouse; then a big warehouse, a large works with a brick chimney, or a processing plant with silos and a steel stack. Sheds come in grey, green, blue, cream, rust red, silver and dark grey; only heavy works have chimneys.
- Civic buildings stand out: the police station has a navy roof, a blue band and a flag; the library and museum have copper domes; the town hall tower a copper roof and a flag; the school a flag.
- Civic models: a red sandstone fire station (three engine bays with red doors front and back, crew rooms above, flagpole) and its hose-drying tower; a Victorian board school (gabled wings, entrance porch, tall many-paned windows, bellcote, ridge ventilators); and a modern hospital (ribbon windows, glazed stair tower, red cross on a white pier, roof plant, helipad space).
- Power stations are modelled as whole sites: coal (clad turbine hall, tall boiler house in the darker second colour, precipitator on stilts, twin concrete chimneys, coal stockpile with a sloping conveyor, switchyard), gas (modern clad turbine hall with a curved roof and coloured band, glazed office, two heat-recovery boilers with slim stacks, a gasholder in its guide frame, fuel tank, pipe rack) and nuclear (domed containment, auxiliary block, two-tone turbine hall, vent stack, gatehouse, two hyperbolic cooling towers).
- Also modelled: a modern white clubhouse (glazing, set-back glass lounge with timber ends, terrace) for the golf course (one per stretch of course along a road) and the marina; the museum's glass wing (two storeys of glass on a stone plinth, oversailing roof); football stands (team-coloured seats, cantilevered roof; turned and lowered for the covered ends); and a concrete water tower.
- Modern blocks and skyscrapers are stacked storey by storey from four models, so any height looks right: a glazed ground floor with entrance canopy, upper storeys (glazed and clad bays, or punched windows in deep frames; or all-glass curtain walling for offices and the best land) and a roof with a set-back penthouse and glass-edged terrace.
- An "accent" material takes the building's second colour (fire station doors, the hospital's cross).
- The game swaps in these models wherever a matching block is planned, stretched to fit; everything else still uses the simple blocks. Materials get the game's own shader (`shaders/model.gdshader`): stone and slate photo textures, varied door and shopfront colours, windows lit at night, map overlay colours.
- Models are drawn in 400 m squares, so Godot can skip what's off screen and use simpler versions far away.

## Tall building design
- Taller plots mix two families: classical sandstone (rusticated ground floor, sash windows in stone surrounds, bay windows, cornice, slate mansard with dormers; classical shopfronts for shops) and modern premium (glass ground floor, framed glazing with timber, bronze, stone, brick, terracotta, zinc or sage bays, staggered glass balconies, set-back glass penthouse, roof canopy; tinted glass on the best land).
- Skyscrapers each get their own design, picked by the plot: offices in tinted curtain glass (blue, green, bronze, silver, smoke), glass with coloured spandrels, art deco stone with piers and a stepped floodlit top, or a precast concrete grid; flats in bands of render with coloured panels, brick or stone, green or blue glass, or a white grid, always with balconies. Footprints vary (slab, square, block, slender, twin towers), towers may step in or step to one side, and tops differ: plant screens with aviation lights, sloping glass, deco steps with a flagpole, a landmark glass crown and needle spire.
- At night offices light up a floor at a time in cool white; homes in warm light, fewer later in the night; shop windows and signs stay lit.
- Courts between tall blocks are landscaped (lawn, path, trees) with parking underground.

## Density, land value and prices
- Plots grow freely up to stage 3 (tenements) whenever there's demand. Industry stops at 3.
- When demand is more than those plots can still take, the town is "short of space": medium-density plots may rise to mansion flats, and high-density plots build upwards (stage 4/5/6 need land value 0.35/0.5/0.65).
- Land value (0-1): base 0.3, up to +0.3 by the sea, plus parks, woodland (a little, capped) and shops nearby; minus industry, power plants and pollution nearby.
- Better land gets better buildings (glass on the best land) and pays more tax (0.6x to 1.4x).
- Home prices = £160k x (0.5 + land value) x (1 + 0.8 x housing shortage).

## Power
- Zones need electricity to grow; plots without it slowly shrink.
- Power tool (6), pick with Tab: coal plant (£3,000, £100/month, 200 units, smoky), gas plant (£5,000, 400 units, from 1,000 people), nuclear (£15,000, 1,500 units, from 5,000 people), wind turbines (£400 a tile, 25 units each, drag a wind farm), solar farm (£300 a tile, 15 units, from 300 people), power lines (£5).
- Power spreads through any touching built tiles: roads, zones, power lines (£5) and other plants.
- When a network runs short, plots furthest from the plant lose power first.

## Interface
- The town is the hero: small frosted-glass pieces hug the edges, nothing sits over the middle. Glass: the game behind blurred, drained of most colour and darkened to a cool slate (so text reads the same over grass, sea, overlays and night), rounded corners, hairline edge, soft shadow. Pieces fade in and out.
- Top left: game menu (New city, Save, Load, How to play, Example cities: Village, Town, City and Bay Area, ready-made towns to load and carry on with; Day and night), city name, date and clock, speed as pause / play / fast icons (the chosen one lit; pause in amber), and Undo.
- Undo (the arrow, or Ctrl/Cmd+Z): each drag is one step; undoing puts its tiles back exactly as they were (zone, level, density, district, kind of road) and gives back what it cost. It remembers the last 20 builds for up to a year (it's for mistakes, not free demolition later); loading or starting a city forgets them. The button's tooltip says what it would undo; greyed out when there's nothing.
- Top centre: advisors ticker (see Advisors).
- Top right: status strip: money and last month's change (green or red), people and jobs, happiness, four small meters (power, water, services, rubbish: icon and bar, red/amber/green, details on hover) and the demand meter (homes, shops, industry bars round a zero line). Clicking the strip opens the City panel: budget (with the difficulty), tax rate with - / +, loans, happiness with its complaints and fixes, services, housing and last month's growth.
- Bottom centre: a card with the picture of the tool in use, what's under the mouse (name, stage, land value, services, problems) and what building there costs (green) or why it can't (red). Messages pop up just above it.
- Bottom right: map views (see Map views).
- Works from 1280 x 720 up; the City panel scrolls if the window is too short.

## Build menu
- A dock, bottom left: a rail of category icons (All, Zones, Roads, Power, Utilities, Services, Leisure, Transport, Districts) with Bulldoze at its foot, and a flyout beside it listing the category: each item has its picture, a name, a one-line description and its price (padlock and "Needs N people" while locked; the full explanation on hover). Service funding (- / +) sits under the Services list.
- Click a category to open it, click it again (or the cross, or M) to fold the list away; the rail stays. A small blue mark on the rail shows the category of the tool in use. Number keys and Tab still pick tools, and the menu follows.
- Item pictures are rendered in Blender by `tools/make_menu_pictures.py` (into `assets/icons/`): a small diorama of each plot built from the same models, colours and photo textures the game uses, so the picture matches what gets built. The drawn icons in `scripts/icons.gd` (from `tools/make_icons.py`) are only a fallback.

## Building tools
- Press, drag to preview (with total cost), release to build; Esc cancels.
- Roads and power lines run straight with one corner. Zones and parks: drag a box; start on a road to zone both sides of every road in the box, two plots deep.
- Street grid (9): drag a box to lay streets every third tile (100 m blocks).
- Corner and through plots build along every road they touch.
- Zoned plots waiting for demand are rough grass with a surveyor's peg in the zone colour at each corner, a "plot available" board and a line in the zone colour round the edge (one line for low density, two for medium, three for high; from far away the plot takes a wash of the colour). Plots the town wants are building sites: churned earth, a track in, hoarding in the zone colour, foundations and a frame or brick walls going up, scaffold, materials, a cabin, cranes for bigger ones. Leftover open land inside the town becomes pocket parks, allotments or car parks (looks only).

## Water and rubbish (Utilities, 7)
- Anything bigger than a first-level plot needs water. Water pumps (£800, 400 units, need power) and water towers (£300, 120 units) supply it; it travels through roads and buildings like power, nearest plots first.
- Towns over 400 people make rubbish (1 per resident, 0.5 per job). Three ways to deal with it:
  - Landfill: £100 a tile, takes 2,000 (was 800: it needed far too much), lowers land value nearby and smells a little.
  - Recycling centre: £2,500, takes 6,000, clean, needs power, from 800 people.
  - Incinerator: £9,000, £160 a month, takes 25,000 on one plot, needs power, from 4,000 people; its tall chimney smokes (pollution 0.45, 300 m) and lowers land value nearby.
- The rubbish goes to recycling first, then incinerators, and landfill takes the rest. Hovering one says how full it is (a landfill counts all its joined-up tiles): "This landfill (12 tiles) takes the rubbish of 24,000 residents: 78% full, 22% to spare". The City panel's rubbish line says how much room is left. Uncollected rubbish cuts appeal (up to -0.5).

## Leisure and landmarks (-)
- Park (£100 a tile, £1 a month; the 8 key), woodland, golf course (£150 a tile, drag to lay out holes), library (from 500 people), museum (2,000), stadium (5,000, one only), marina (1,500, by the sea), town hall (1,000, one only). Golf and the landmarks raise land value round them and the town's appeal (all together up to +0.3), and cost upkeep. They need a road (and power, except golf).

### Woodland
- "Plant trees: drag out a forest". First in the Leisure list (next to Park); drag a box like a park. £20 a tile (plus the usual slope extra), no upkeep, no unlock. Goes on any buildable land (not water, not too steep), round roads and power lines like everything else; replaces zones, as parks do. Needs no road, power or water, never shows a warning icon and always counts as working. Zones don't grow on it. Like parks, power and water pass through it.
- Effects, weaker than a park tile for tile and capped so a huge cheap forest can't stand in for parks: land value +0.025 per tile fading out over 2 tiles, but all the woodland round a tile adds at most +0.05 (about one park tile's worth); it soaks up pollution like a park (0.06 per tile against a park's 0.1, over the same 2 tiles), but at most 0.25 round any one tile (a works makes 0.06-0.18; a coal plant 1.2), so a belt can screen homes from a works but not hide a coal plant. No leisure appeal (parks don't add any per tile either). Numbers under Woodland in `scripts/settings.gd`.
- Looks: the same trees as the natural woods (mostly oak, ash and sycamore; stands of pine and spruce where the clumps say; birch towards the edges), bigger and closer inside a forest and thinner at its edge, on the woods' dark floor, and the canopy painted on from afar. Woodland next to natural woods, or across a road, joins up with it without an edge. A road's verge beside it is woods floor with a mown strip by the kerb. Trees are seeded by their own spot, so building elsewhere never reshapes them; natural trees already there are kept and filled in round.
- Hover text: "Woodland (planted trees: ...)", with the land value and the air there.

## Transport (=)
- Bus depot (from 500 people): plots within 700 m can grow 3 tiles from a road instead of 2.
- Railway station (2,000): visitors add shop demand (3% of the population each, up to two stations); raises land value.
- Harbour (1,000, by the sea): ships bring trade, +80 industry demand each.
- Airport (5,000): dragged out as a box, £200 a tile, £2 a tile a month. The game lays it out: the runway is the longest straight run of tiles (several as long: the one five tiles back from the road side), with a taxiway beside it, stands with airliners, and a terminal (two tiles), control tower and hangars on the tile nearest a road. It opens with a runway of 800 m, 40 tiles in all and a road within 2 tiles of the terminal (it needs no mains power); the hover text says what's missing. While dragging, the box is red until it's big enough (16 tiles in a line and 40 in all, counting any airport it joins on to), with the size and what's missing; then it turns green. Let go while it's red, or without the money for all of it, and nothing is built. Open, it adds shop demand (visitors, 3% of the population), 20% more office demand and +120 industry demand, brings half as many tourists again to the landmarks, and its noise lowers land value round it (capped) with a little pollution. Only one airport counts.
- All the numbers for these buildings are in `Settings.BUILDINGS`.

## Offices (a zone of their own)
- Low, medium and high density like shops (£70 / £90 / £140 a tile): small offices and chambers, office blocks, glass towers, skyscrapers in a CBD.
- Demand: a share of the workers who aren't in shops want office work: none under 500 people, rising to 55% at 10,000; half of that share only counts where homes have a school nearby; tech workers all want office work on top (at most 80% in all). Only offices that are built take workers from industry, so a town with no office zone runs as before (and when offices arrive, industry shrinks).
- Offices are clean, pay 25% more tax per job, add a little land value, and want police cover like shops. Shops' tall stages are now big stores and hotels.
- Visitors' shopping (stations, the airport, landmarks) is extra shop demand: it no longer takes workers from offices or industry.

## Landmarks (their own Build menu category)
- San Francisco's famous buildings, one of each, unlocked by population: the Painted Ladies (2,000; a row of six Victorian houses, each its own colour, with Alamo Square's lawn behind), Coit Tower (4,000), the Ferry Building (8,000, by the sea), the Palace of Fine Arts (12,000; rotunda, colonnade and lagoon), the Transamerica Pyramid (18,000) and Salesforce Tower (25,000; the tallest thing in town, its crown lit at night). £12,000 to £48,000.
- The eight world landmarks of before (Big Ben, Colosseum, Great Pyramid, Statue of Liberty, Taj Mahal, Sydney Opera House, Eiffel Tower, Empire State Building) are out of the Build menu but still load, draw and count in old cities.
- Not yet: the Golden Gate Bridge and Alcatraz (need building over water).
- Each raises land value round it and appeal (within the leisure cap), and brings tourists: shop demand, 0.4-0.8% of the population each, 5% at most together, half as much again with an open airport.
- Models are made by `tools/make_buildings.py` (scaled to fit one plot); looks and colours are in `LANDMARKS` in world3d.gd.

## Services
- Services tool (0), then pick one (Tab or the buttons): police station £1,500, fire station £1,500, school £2,000, hospital £4,000. One tile each; they need a road and power (3 units) to work.
- Each covers the area round it: fully close by, fading out at its reach (police 800 m, fire 700 m, school 600 m, hospital 1 km at 100% funding). Covered areas gain land value.
- Funding (- / +, 0-150%) sets upkeep (police £60, fire £60, school £80, hospital £150 a month at 100%) and reach (50% funding reaches 70% as far; 0% closes it).
- Effects: over 800 people, homes and shops with no police grow at half speed; over 1,200, homes need a school to grow past terraces; over 2,500, homes with no hospital grow at half speed; over 500, built plots with no fire cover can burn down (rarely; industry twice as often; the risk falls with the strength of cover, not just in or out).
- How cover works: each working building covers its plot fully, and the plots round it fully out to 37.5% of its reach, then less and less to nothing at its reach. A plot counts as covered from 0.3 of full cover (about 81% of the way out: a school at 100% funding counts for about 490 m). "Covered" is what growth, the hover card and the view use; the strength of cover also adds land value (up to +0.04 / 0.03 / 0.05 / 0.04), feeds happiness (homes' average cover of all four) and lowers fire risk. Funding changes the reach (see above), and a building with no road or power covers nothing.
- A Services map view shows how many of the four cover each area, or one service at a time (see Map views).
- Hovering any zone plot shows Police / Fire / School / Hospital with a tick (covered) or a cross (red when the plot needs it: police for homes and shops, fire for every plot, schools and hospitals for homes). Hovering a service building says how far it reaches at its funding, how many plots and people it covers, and how many of those no other building of its kind reaches.
- Placing a service: the Services view switches to that service (and back to the view before when you pick another tool), a soft disc round the mouse shows how far it would reach, and the card says what it would add: "would reach 14 homes with no school (420 people), 9 held back now".
- Small versions for villages: police office £500, small fire station £500, clinic £1,200 (upkeep £22 / £22 / £50; reach 400 m / 350 m / 500 m; 1 unit of power). They share the big ones' funding, cover and map view; there is no small school.
- Advisor tips about one service (a school, police, a hospital, fire) open the Services view on that service; the general "services are poor" and tax tips open it on all four.

## Map views (overlays)
- O or the row of icons bottom right: Normal, Land value, Power, Roads, Growth, Services, Water, Districts, Pollution, Traffic (names on hover). The chosen view's name, a line about it and its colour key show above the icons.
- Ground and buildings take each plot's colour; trees, paving and parked cars hide so the colours read clearly.
- Map views are always lit like early afternoon (no dark ground, lit windows, street lamps or headlights), so their colours read the same at night; the clock keeps running and the normal view goes back to the real time of day.
- Services view: chips above its key pick All (how many of the four cover each spot) or Police, Fire, Schools or Hospitals on their own. One service: dark green full cover, light green covered, red for plots held back right now without it (the same count the advisors give: police and hospitals "growing at half speed", schools "can't grow past terraces", fire "could burn down"), orange for plots that want it but aren't held back yet, its buildings blue with a pin over each (the other services' grey). Below the key: "Schools reach 62% of residents · 9 homes can't grow past terraces without one" (before the town is big enough: from how many people it matters). C (in any view) opens the Services view, then shows each service in turn. The choice resets to All when you leave the view.
- Land value uses the same bands as the hover text (0.2 / 0.35 / 0.5 / 0.65). Growth: green growing, yellow waiting (demand, space or land value), red stuck (road or power), blue fully built, brown abandoned.

## Pollution
- A pollution map (0 clean to 1 heavy) is worked out every month and whenever the town changes; it isn't saved (loading works it out again).
- Sources add up where they overlap, fading out with distance: industry 0.06 per stage (200 m), coal plant 1.2 (450 m), gas plant 0.5 (300 m), harbour 0.35 (250 m), landfill 0.12 per tile (200 m), recycling 0.08 (100 m), incinerator 0.45 (300 m). Nuclear, wind and solar are clean. Parks soak some up (golf half as much; woodland a bit over half, capped, see Woodland). The total is eased into 0-1, so a coal plant is "heavy" for about 200 m.
- Effects: land value -0.2 in full pollution; homes grow up to 60% slower in polluted air (the hover text says so); the share of residents in polluted air (0.3 or more) costs up to -0.15 appeal. The old land value penalties of industry, power plants, landfill and the harbour were halved or so, as the smoke is now counted here.
- Pollution map view: clean, a little, some, polluted, heavy (green to red). Hover text mentions pollution from "some" upwards, and polluting buildings say how far their pollution reaches.
- Coal plant chimneys smoke (a few particle streams; looks only).
- For a happiness score or advisors: `pollution_at(i)`, `pollution_band(i)`, `polluted_homes_share()`, `pollution_feeling()` (already in appeal), `air_word()` in `scripts/simulation.gd`. Numbers in the Pollution section of `scripts/settings.gd`.

## Kinds of road (Roads in the Build menu)
- Three kinds, laid with the same drag as a road; dragging one kind over another changes it (you pay the new kind's full price). The kind is kept per road tile (`sim.road_kind`: 0 road, 1 avenue, 2 motorway; numbers in `Settings.ROAD_*`). Old saves load as ordinary roads.

| | Road | Avenue | Motorway |
| --- | --- | --- | --- |
| Cost a tile | £10 | £40 | £120 |
| Upkeep a tile a month | £0.50 | £1.50 | £4 |
| Trips a day before it's full | 5,000 | 14,000 | 40,000 |
| Time to cross a tile (drivers take the quickest way) | 12 | 8 | 5 |
| Width drawn | 12 m | 20 m | 28 m |

- **Avenue**: two lanes each way, a planted strip with trees down the middle, wide pavements. Plots open onto it as onto a road, but keep to their own tile (they don't reach into its verge).
- **Motorway**: three lanes each way, hard shoulders, a barrier and tall lamps down the middle; no pavements, trees, bus shelters or people. **Nothing opens onto it**: it doesn't count as "a road within 2 tiles" (the reason text says "a motorway doesn't count"), buildings don't face it and plots' trips don't start on it. It joins any road it touches (a flat junction: no slip roads or bridges yet). Noise: land value falls by up to 0.1 within 3 tiles.
- At a junction of two kinds the bigger road has the right of way (give-way lines on the smaller arms only).
- Cars keep to their lanes, go faster on avenues (x1.3) and motorways (x2.1), and wider roads show more of them.
- Not done yet: slip roads and bridges, one-way streets, roundabouts, a speed or noise cost for avenues, bus lanes.

## Traffic
- A light model, worked out each month and whenever the town changes (it takes about 20 ms in a town of 28,000); never saved (loading works it out again). No individual cars: just how many car trips a day use each road tile.
- Trips: every working resident drives to work and back (2 trips a day), and everyone makes 0.6 trips a day to the shops. A station's visitors (3% of the population each, as for shop demand) drive between it and the shops, and a harbour's lorries (6 a day per port job) to the works. Plots with no road make no trips. Homes within reach of a working bus depot make 25% of their trips by bus, and near a station (600 m) 15% by train (together 40%).
- Where to: shops and works are grouped into squares (8 tiles, doubled until there are at most 16 groups). Each home splits its trips between the groups by size x 1 / (1 + (distance / reach)^2), distance counted along the roads: work reach 30 tiles (1.5 km), shops 12 (600 m), lorries 40. So most people work and shop nearby, but a big estate across town still draws commuters.
- Which way: always the quickest way along the roads (a tile of avenue takes two thirds of the time of a tile of road, a motorway under half; see Kinds of road), split evenly where two ways are equally quick (like water draining downhill). A plot's trips start and end on the roads it fronts. So the roads between homes and jobs are busiest, back streets and dead ends quiet, and a single link between two parts of town carries everything between them. Drivers don't yet avoid jams.
- A road tile takes 5,000 trips a day (an avenue 14,000, a motorway 40,000). Congestion = trips / what it takes: free-flowing (below 0.5; "quiet" below 0.1), busy (0.5), heavy (0.8), jammed (1 and over). In the demo town (28,000 people, about 38,000 car trips a day and 7,000 by bus or train) 96% of road tiles are free-flowing, 3% busy, 1% heavy and the link from town to the works jams (about 2% of driving is in jams).
- Traffic map view: roads only, coloured quiet (pale green), free-flowing (green), busy (yellow), heavy (orange), jammed (red); the road surface itself takes the colour and its whole tile is tinted (busier ones more strongly) so it reads from afar; everything else greyed out.
- Hover a road: "Road — Busy: about 2,600 trips a day (it takes 5,000)"; on heavy and jammed roads also what to do ("make it an avenue, add parallel roads, or a bus depot nearby"). The map key gives the bands as how full the road is. City panel (Services): "Traffic: 2% of trips in jams · 37,800 car trips a day, 7,000 by bus or train". Advisors: from 8% of trips in jams (a warning from 20%); clicking it shows the Traffic view.
- View only, for now: congestion doesn't affect growth, happiness, land value or pollution (a later decision). Hooks in `scripts/simulation.gd`: `traffic_at(i)`, `traffic_congestion_at(i)`, `traffic_band(i)`, `traffic_word(i)`, `traffic_fix(i)`, `traffic_jammed_share()`, `traffic_trips`, `transit_trips`. Numbers under Traffic in `scripts/settings.gd`.
- Known weaknesses: no through traffic from beyond the map and no trips to schools, hospitals or landmarks; inside a group of shops or works the last stretch isn't routed (arrivals are shared out to each plot's own road); drivers always take a shortest way, so a jam never sends anyone round another way; trips stop at the edge of a road network that has no jobs.

## Advisors
- A ticker, top centre, shows the most urgent tip and a count when something needs attention (red dot urgent, amber warning, blue advice). The count opens the full list, most urgent first. Hidden when all is well.
- Every tip comes from real simulation state: why zone plots aren't growing (the same reasons as the hover text and Growth view), power and water used vs supplied, rubbish collected, buildings with no road or power, money trend, taxes vs services, missing fire station or school, skyscrapers waiting for transport.
- Tips appear and disappear as the town changes. Only urgent ones also flash a message, once, and not again for a year.
- Clicking a tip switches on the map view that shows the problem (Power, Water, Roads, Services, Growth, Land value); a tip about one service opens the Services view on just that service. Clicking again goes back to normal. Hover for a longer explanation.
- The rules live in `scripts/advisors.gd` (`tips(sim)` returns `[{id, text, detail, severity, overlay, filter}]`; filter = the one service a tip is about, or -1), separate from the HUD, so new tips are one `_add()` each.

## Look and feel
- The land, aiming for SimCity 4: lush green low ground, paler dry slopes and hilltops, darker damp hollows, rough hill grazing with heather, rock on steep faces. Slopes are lit a little more strongly than they really are so the low hills read (looks only; the ground keeps its real shape).
- The coast is a smooth natural curve (not tile steps): sand beaches with wet sand at the water's edge and dune grass behind. Gameplay stays tile by tile: every land tile's middle is dry land and every sea tile's middle is water.
- The sea is clear pale turquoise over the sand in the shallows, deepening to blue offshore, with moving ripples, a sheen of sky and soft surf lines on the beach.
- Open country is a patchwork of fields (pasture, cut silage, rough grazing, barley, the odd ploughed field) with hedges and hedgerow trees, a few dark conifer plantations on the hills, natural woods and gorse. Fields, woods and hedges give way where you build.
- The land carries on beyond the map edge (fields, woods, the coast) and fades into the haze; a faint line close up shows where building stops.
- Trees come in kinds: broadleaf (oak, sycamore, lime), birch, columnar (poplar, leylandii), Scots pine, spruce, small ornamentals, copper beech and gorse bushes (flecked yellow), each with its own shape, size and colour. Canopies are clusters of lumpy blobs with leaf-clump shading.
- Natural woods (dense, bigger trees inside, thinning at the edges), hedgerow trees, plantations, gorse and lone trees cover open land and are cleared where you build; parks (£100, £1/month) keep their trees and gain more; woodland (£20) plants a forest that looks like the natural woods.
- Every straight street gets trees on both sides (one kind per street, like an avenue), except beside industry and power plants, and lamp posts every 25 m; by shops, offices and flats, bus shelters, bins and the odd post box. Zebra crossings only where it's busy (by shops, flats, public buildings); quiet suburbs get give-way lines.
- Every plot is a little scene (looks only, picked by position so it never changes): houses have front gardens with borders, hedges or low walls and a path to the door, and back gardens with a patio, borders, vegetable patches, stepping stones, sheds, greenhouses, washing lines and fences, long ones running to meadow at the end; terraces have strip gardens with fences and sheds; tenements share a back court with drying greens, clothes poles, bin stores and side walls; shops have a paved frontage with planters and benches, a service yard with bins and a lorry, and a car park with planted islands and a trolley shelter; offices and towers stand in paving; works have concrete yards with stains, scrub by the chain-link fence, pallets, skips, tanks and lorries. Civic buildings get their own: a painted playground and marked pitch at schools, ambulance bays at hospitals, a statue and benches in the town hall square.
- Parks are laid out tile by tile (a pond, a formal garden with a fountain, a playground, a football pitch, a bandstand, or open lawn with a meadow), with railings, a shrub border and a path inside them on the street sides, and long paths running on into the next tile of the same park, so a big park reads as one. Golf courses have striped fairways and rough along their edges.
- Gardens, tenement courts, landscaped courts, shop car parks and parks get trees too.
- Cars, buses and people fill the streets (see People and traffic).
- A full day and night every 4 minutes at normal speed: the sun crosses the sky, windows and street lights come on at dusk. "Day and night" in the game menu turns it off.

## People and traffic
- Cars, buses and people walking bring the streets to life. Looks only: they don't affect the simulation. T turns them off and on (`TRAFFIC_ON` in settings to start with them off). The cars tell the same story as the Traffic map view (see Traffic).
- Cars keep left and follow the road's own straight runs and bends, slowing for corners, junctions and dead ends (where they turn round), and queue behind the car in front. At a junction they pick a way as likely as the traffic model's trips on it (quiet streets a little too), slightly preferring straight on, so busy roads stay busy. On heavy roads they slow to 6 m/s and on jammed ones crawl at 2.5 m/s, so queues build up. They tilt with the hills; after dark they have head and tail lights and a pool of light on the road ahead.
- Red buses run on the roads within reach of a working bus depot (about one vehicle in twelve).
- People walk along both pavements, a little apart, bobbing as they go.
- How many cars a street gets follows the traffic model: one car per 1,500 trips a day, at most 3 per road tile. Walkers follow the plots beside it: one per 40 residents and jobs (shops count three times, homes a quarter), capped per street. CBD streets have 1.5x the walkers. Night has 30% of the cars and 12% of the walkers. None until the town has people or jobs.
- Only the streets round the camera are filled (cars up to 1.8 km away as you zoom out, people within 700 m); anyone who drives out of range reappears in view. At most 300 vehicles and 400 people; no people drawn beyond 1.1 km zoom and no cars beyond 3.5 km.
- Drawn with six MultiMeshes (car bodies, cabins, lamps, light pools, people, heads) filled from one buffer each frame; with a crowd, each person moves every other frame. Code in `scripts/traffic.gd`; numbers in `scripts/settings.gd`.

## Tech layer (planned Nov 2026; step 1, the Tech zone, built)
The next direction: blend town planning with today's big-tech issues. You're the mayor; tech companies write asking to build, at a scale you pick, and you live with what follows: data centres eating power and water, campuses pushing up house prices, gigafactories filling the roads. Tongue-in-cheek throughout. Every number below is a first guess, to be tuned in play.

### The map moves to Palo Alto — built (Nov 2026), not yet played by Sam
- Sam chose a real place over a generated map: **Palo Alto** (see Decisions, Map). The same file format, so the game works as before; `MAP_FILE` in game3d.gd says which map.
- Saves keep the map's name; a save from another map is refused ("That city was built on another map, so it can't be loaded here").
- **Bay Area example (Nov 2026):** a loose San Francisco and Silicon Valley on the Menlo Park map, about 101,000 people, 69% happy, about +£40,000 a month. San Francisco on the north-east point: a CBD downtown by the water (57 skyscrapers) with the Transamerica Pyramid and Salesforce Tower, the Ferry Building on the waterfront, Coit Tower on the point, the Painted Ladies among the row houses, the Palace of Fine Arts by the north shore, the Golden Gate Bridge east to the far shore, Alcatraz in the Bay, Golden Gate Park. Then an airport (SFO), Highway 101 (a motorway) and El Camino (an avenue) south through the suburbs to Silicon Valley: Stanford (university and research park) in the foothills, office parks, East Palo Alto, and a Tech zone with Meta's, Google's and Apple's campuses, Amazon's data centre, Nvidia's chip factory and OpenAI's AI data centre (each a letter said yes to once the town was big enough, its site dragged out with the game's tool; OpenAI is given more power each year). Nuclear power by the works and in the Valley, Baylands woodland and solar farms. It draws about a quarter slower than the City example.
- The example cities were rebuilt on Palo Alto (Village 2,720 people, Town 14,780, City 43,580, all paying their way). Their layouts, drawn for the first map with the sea to the west, all sit on land here; seaside buildings (harbour, marina, Statue of Liberty, Opera House) go to the nearest shore on the Bay, with a road laid to them (dev_shots.gd `_coast_with_road`). The screenshot town does the same.
- Still the old look: the countryside (fields, hedges, woods), the sandstone buildings and the light. Making it look Californian is on the to-consider list.

### Real companies, real founders, as satire
- Real company and founder names, so people recognise them. Names in text only: **no logos**.
- Letters are cliché parodies of each founder's **public persona** (catchphrases, posting style, famous habits). No invented facts, scandals or private lives: that keeps it satire.
- A line on the title screen and in the credits: "This is satire. None of these people or companies are involved, and they didn't write any of this."
- Each founder has a **gameplay quirk**, not just a voice:

| Founder | Voice | Quirk |
| --- | --- | --- |
| Elon Musk (Tesla, SpaceX) | memes, "hardcore", 2am energy | promises 6 months, takes 3 years; threatens to leave if taxes rise |
| Sam Altman (OpenAI) | all lowercase, calm, "benefit all of humanity" | asks for more power every year |
| Jensen Huang (Nvidia) | leather jacket, huge enthusiasm | the bigger the scale, the better the deal |
| Mark Zuckerberg (Meta) | "bringing the community closer together" | pivots: the campus changes purpose halfway |
| Jeff Bezos (Amazon) | "it's still Day 1" | makes you bid against rival cities |
| Alex Karp (Palantir) | philosophy-professor intensity | a deal, not a building: police cover up, privacy complaints |
| Palmer Luckey (Anduril) | Hawaiian shirt, flip-flops | won't take no: writes again a year later |
| Sundar Pichai (Google) | extremely polite, corporate | reliable, never any trouble; mentions AI eleven times |

### Letters and the inbox
- A letter: who it's from, what they want to build, and buttons **Small / Standard / Mega / Decline**. Each scale lists what they offer (jobs, a one-off investment, tax) and what they need (land, power, water, a road or rail link, a tax break).
- Say yes and you **pick the site**: drag out its footprint (like the airport), inside the Tech zone, within 6 months, or the deal lapses.
- Say no and they go elsewhere; investor appetite (below) drops.
- Letters go to an **inbox** with a count badge, like the advisors. Only big ones pause the game.

### Letters, inbox and start-ups — built (Nov 2026), not yet played by Sam
- **The envelope** (top left, after Undo) shows how many letters are waiting (a red count). It opens the **inbox**: each letter (subject, who from, months left to answer), **Who's interested** (each kind of company and what it's waiting for, e.g. "Start-ups: want an empty office plot with a road and power in your Tech zone") with how keen investors are (keen / warm / wary / cold), and the start-ups the town backed.
- Clicking a letter opens it on a **card** in the middle over a dimmed town; the clock stops while it's open. Buttons: Later (or Esc: back to the inbox), No thanks, and the offer. If the offer can't be done right now (not enough money, no empty plot), the card says why in red and stays open.
- A new letter flashes a message ("A letter from Leo and Amara (Sproutio): open it from the envelope, top left") and an advisor tip says how many are waiting (a warning when one lapses this month).
- Letters lapse after **6 months** unanswered ("... went to a town that answers its post"). At most 3 wait at once.
- **Investor appetite** (0-1, starts 0.5): +0.06 for a yes, -0.03 for a no or a lapsed letter, -0.02 when a backed start-up folds. More appetite, more letters.
- **Start-ups** (made-up names, pitches and founders from `scripts/companies.gd`, e.g. "Sproutio: Airbnb for garden sheds") write from **500 people**, once there's an empty office plot with a road and power in a Tech zone: at best 20% a month x (0.5 + appetite) x (0.6 + 0.4 x the Tech zone's pull) x town size (0.75 at 500 people up to 1.5 at 3,000), so roughly every 4-8 months. They ask a grant of £1,000-£3,000. **Back them** and they move into the best such plot (the most valuable land) at level 1; the plot no longer grows or shrinks by itself. Hover: "Start-up: Sproutio, backed by the town".
- Each year a start-up may **fold** (15%: its plot empties), be **bought** by a big firm (4%: the town's stake pays out 8x the grant) or **grow** a level (25%). Each is a message.
- Saved (`letters`, `startups`, `investor_appetite`, `letter_count`); older saves have none. Numbers under Letters in `scripts/settings.gd`; rules under Letters in `scripts/simulation.gd`; words in `scripts/companies.gd`.

### Data centres — built (Nov 2026), not yet played by Sam
- **Amazon (Jeff Bezos), Microsoft (Satya Nadella) or Google (Sundar Pichai)** write from **1,500 people**, once a Tech zone has 4 tiles of open land: at best 8% a month x (0.5 + investor appetite), x0.4 without 160 spare power, x0.6 without a Tech zone tax 3 points below the town's. One data centre letter or unplaced deal at a time; a company already building here doesn't write again. Who's interested says what they're waiting for ("interested, but would like more spare power (160 at least)").
- The letter card has a button per size (the numbers come from `Settings.DC_SCALES`, so the words never drift from them):

| | Small | Standard | Mega |
| --- | --- | --- | --- |
| Tiles | 4 | 12 | 30 |
| Power / water | 160 / 80 | 480 / 240 | 1,200 / 600 |
| Jobs (from outside) | 12 | 40 | 120 |
| Tax a month | £400 | £1,500 | £4,000 |
| Invested when it opens | £5,000 | £20,000 | £60,000 |
| Asks for | nothing | no tax for 5 years | no tax for 10 years, power before homes |

- Saying yes needs that much open land in the Tech zone (or the card says so). Then you **drag out its site** (the game switches to placing it, with the Districts view): free, open land in the Tech zone only, between the size and twice it; red until it's right, then green; let go while red and nothing is built. Picking another tool leaves it waiting: the inbox shows "needs a site · N months left" with **Place it**, and an advisor tip counts down. No site in **6 months** and the company goes elsewhere.
- It runs once it has a road beside any of its tiles and all its power and water (shared over its tiles; it takes water like zones do). Running, it brings its jobs (counted with the town's: spare jobs draw people in) and, the next month, its investment; tax starts after its tax-free years. Not running, the hover text and an advisor tip say why ("not enough power (it needs 480)").
- **Power before homes** (Mega): on its grid its tiles get power first, so homes at the far end go dark when it runs short.
- **Bills**, a new happiness part: data centres' share of the town's power x how stretched the grid is (nothing below 60% used, full when it's all used) x 0.4. "electricity bills up: data centres are straining the grid".
- It hums: land value -0.05 within 3 tiles. Drawn whole, as one site (when its tiles fill a rectangle; otherwise a hall per tile): one or two long windowless halls with a band along the top, an entrance block and car park on the road side, a yard behind, and a fence. Each company looks its own, with no logos (`DC_LOOKS` in world3d.gd): **Amazon** sand-coloured precast with a dark band, rows of air handlers on the roof and a long yard of generators; **Microsoft** pale grey with a glass entrance and a roof of solar panels; **Google** white with pipes painted red, yellow, green and blue on the roof and a row of round cooling towers.
- Bulldoze it and the company leaves (investors cool, 3x a no). Saved (`deals`); older saves have none. Tile `DATA_CENTRE` (on the end of the list); it's never in the Build menu (the `Tool.DEAL` placing tool).

### Company projects, and Tesla's Gigafactory — built (Nov 2026), not yet played by Sam
- Data centres are now one kind of **company project** (`Settings.PROJECTS`): each kind has its building tile (`PROJECT_TILES` in simulation.gd), its town size and chance of writing, its sizes, how long it takes to build after it's placed (`build_months`) and whether it wants a motorway. Everything else (the letter card's sizes, placing the site, power and water, jobs, investment, tax-free years, power before homes, bills, the inbox and advisors) works the same for every kind. Older saves' deals load as data centres.
- **Tesla's Gigafactory** (Elon Musk): writes from **4,000 people** (at best 5% a month; half as keen without a motorway: "would like a motorway for its lorries").

| | Small | Standard | Mega |
| --- | --- | --- | --- |
| Tiles | 9 | 20 | 42 |
| Power / water | 500 / 150 | 1,200 / 350 | 3,000 / 800 |
| Jobs (from outside) | 600 | 1,500 | 4,000 |
| Tax a month | £2,000 | £5,000 | £12,000 |
| Invested when it opens | £40,000 | £120,000 | £300,000 |
| Asks for | no tax for 5 years | 10 years | 15 years, power before homes |

- **Elon's quirk:** the letter says "Construction done in 6 months (definitely)". Once placed it takes **12 to 36 months**; until then it's a building site (a concrete frame, yellow cranes, cabins, hoarding), uses no power, and its hover always says "being built: Elon says six more months". When it opens: "Tesla's Gigafactory is open at last, 25 months after \"six months\": £40,000 invested in the town."
- Running, it's a huge white factory with a black band, solar panels over the roof, rows of new cars out front and lorries at the loading bays. A little smoke (pollution 0.02 a tile, 200 m) and lower land value nearby (-0.06 within 4 tiles).
- Still to come for Elon: threatening to leave if the Tech zone's tax goes up.

### Google's campus — built (Nov 2026), not yet played by Sam
- **Google (Sundar Pichai)** writes from **6,000 people** (at best 5% a month), only a third as keen until **60% of residents have a school nearby** (Who's interested: "would like schools near more homes"). Very polite; mentions AI.

| | Small | Standard | Mega |
| --- | --- | --- | --- |
| Tiles | 6 | 15 | 36 |
| Power / water | 150 / 80 | 400 / 200 | 900 / 450 |
| Jobs (well paid, from outside) | 800 | 2,500 | 7,000 |
| Tax a month | £3,000 | £8,000 | £20,000 |
| Invested when it opens | £30,000 | £100,000 | £250,000 |
| Asks for | nothing | no tax for 3 years | 6 years |

- **Google's quirk:** the one company that's on time. It opens in **exactly nine months** ("being built, opens in 5 months (exactly, says Google)").
- **Cost of living**, a new happiness part: campus jobs per resident x 1.5 is how much **home prices rise across town** (at most double), shown on every home's hover ("homes here worth about £230,000 (up 16% with tech salaries)") and the campus's. Residents feel it: up to -0.3 appeal when prices have doubled ("homes priced out of reach: big tech salaries push prices up"; the advisor opens the Land value view). The jobs also draw newcomers in, so homes are wanted too.
- Drawn as low glass pavilions (3 or 4 storeys) with green roofs, in 55 m squares on mown lawns with winding paths (the middle squares of a big one left as a lawn quad), trees, and racks of bikes in bright colours by the doors. It raises land value nearby (+0.05 within 4 tiles).
- Not modelled yet: commuter traffic to it.

### SpaceX's launch site — built (Nov 2026), not yet played by Sam
- **SpaceX (Elon Musk)** writes from **5,000 people** (at best 4% a month), once a Tech zone has open land **on the coast**. The site has to touch the sea (the drag says "it has to touch the coast" until it does). "Done in 6 months" takes **18 to 48 months** (Elon's quirk, as for Tesla).

| | Small | Standard | Mega |
| --- | --- | --- | --- |
| Tiles | 6 | 12 | 30 |
| Power / water | 100 / 60 | 250 / 150 | 600 / 400 |
| Jobs (from outside) | 300 | 900 | 2,500 |
| Tourists (shop demand, share of the population) | 0.4% | 1% | 2% |
| Safety zone (no homes grow) | 3 tiles | 4 | 6 |
| Launches (chance a month) | 15% | 30% | 50% |
| Tax a month / invested | £1,500 / £40,000 | £4,000 / £120,000 | £10,000 / £300,000 |
| Asks for | nothing | no tax for 5 years | 10 years |

- **Safety zone:** homes inside it can't grow ("can't grow: inside the launch site's safety zone") and slowly move out (they count as in decline, so they're boarded up in time).
- **Launches:** a news line every 5th ("SpaceX has launched 10 rockets from your coast. Tourists line the beach to watch."). Each launch has a **5% chance of blowing up**: "SpaceX's rocket underwent a \"rapid unscheduled disassembly\" over the launch site. Elon says the data is excellent. No launches for 6 months." While it's repaired it brings no jobs, tax or tourists (no warnings: it isn't the player's doing).
- Drawn as a white assembly hangar by the road, a tank farm, and a concrete pad with a dark launch tower and a stainless rocket (all bigger for bigger sites); after an explosion, a scorched pad and no rocket.
- **Company projects' land value is now capped** (all kinds): every tile counts, but the effect round about is at most 0.15 either way, however big the site (before, a 36-tile campus maxed out land value and a big data centre flattened it).

### OpenAI's AI data centre — built (Nov 2026), not yet played by Sam
- **OpenAI (Sam Altman)** writes from **10,000 people** (at best 3% a month), in all lowercase: "a big one. to benefit all of humanity... if you have room for a nuclear plant or three, that would be amazing." It takes 12-18 months to build.

| | Small | Standard | Mega |
| --- | --- | --- | --- |
| Tiles | 16 | 36 | 64 |
| Power / water | 1,000 / 500 | 2,500 / 1,200 | 6,000 / 3,000 |
| Jobs (from outside) | 60 | 150 | 400 |
| Tax a month | £6,000 | £15,000 | £40,000 |
| Invested when it opens | £100,000 | £300,000 | £1,000,000 |
| Asks for | no tax for 5 years | 10 years, power before homes | 15 years, power before homes |

- **Sam's quirk: it always wants more.** Every year after it opens, a letter: "we need a bit more power. maybe a quarter more. then probably a quarter more after that." **Give it more power**: it uses a quarter more (of what it started with; up to 3x) and pays 15% more tax. **No thanks**, or no answer within 6 months, is a no ("Sam Altman says that's totally fine. (That's 2 no's now. OpenAI has noticed.)"). **Three no's and OpenAI moves** "to a town with more power"; its empty halls stay (no company, no power used, no warnings) for you to bulldoze.
- Drawn as vast near-black halls with a pale band, roofs packed with cooling units, and a yard of its own gas turbines (with stacks) and transformers.

### The company ladder
How often letters come, and how big the companies are, grows with the town:

| Stage | Who writes | How often | Wants |
| --- | --- | --- | --- |
| Start-ups (from ~500 people) | small made-up start-ups ("a two-person drone start-up") | every few months | a cheap office plot in the Tech zone |
| Scale-ups | Stripe, Figma, Discord, Revolut | every couple of months | office space, some tech workers |
| Big Tech | Google, Apple, Microsoft, Amazon, Meta, Nvidia | monthly at a real tech hub | lots of tech workers, schools, transport |
| Mega projects | Tesla, SpaceX, OpenAI, Palantir, Anduril | rare | everything: power, land, talent, tax breaks |

- A start-up you backed early can grow into a scale-up.
- Each month the town's **interest** sets the odds of a letter and its stage. Interest comes from: the Tech zone (size, empty land ready, tax rate), **tech workers**, infrastructure (spare power and water, transport) and **investor appetite** (your record of saying yes, and companies doing well).
- Each company has a **wishlist**: Amazon and Microsoft want low tax, spare power and water, cheap land; Google wants schools, parks and good housing; Tesla wants a motorway or rail, power and workers; SpaceX wants empty coast; Palantir and Anduril want low tax, a big town and police. A "Who's interested" list in the City panel shows each one and what they're waiting for ("Amazon: interested. Wants 500 more spare power").

### What they build
| Proposal | Upside | Catch | Hooks into |
| --- | --- | --- | --- |
| Data centre (Amazon, Microsoft) | big tax, one-off investment | power and cooling water like a small town, few jobs, a hum lowers land value, bills rise if the grid is stretched | power, water, land value, a "bills" complaint |
| Mega AI data centre (OpenAI, late) | enormous investment | needs its own power plant or drains yours | power |
| Tech campus (Google, Apple, Meta) | thousands of well-paid office jobs | house prices soar, locals priced out, commuter traffic | offices, home prices, housing, traffic, schools |
| Gigafactory (Tesla) | thousands of factory jobs | heavy power, lorries, some pollution, wants a motorway | industry, pollution, traffic |
| Launch site (SpaceX, coast only) | tourists, prestige | launch noise, a no-build zone, a rare explosion | coast, tourism, land value |
| Chip factory (Nvidia) | high-skill jobs | heavy water use, chemical pollution | water, pollution |
| Drone factory and test range (Anduril) | defence money, skilled jobs | noise, protests, lower land value | land value, happiness |
| City data deal (Palantir, no building) | police cover up town-wide | a monthly fee, a privacy complaint | services, happiness |
| Robotaxi trial (Waymo, no building) | less traffic | taxi and bus jobs lost | traffic, jobs |

Data centre scales, as an example:

| | Small | Standard | Mega |
| --- | --- | --- | --- |
| Footprint | 4 tiles | 12 tiles | 30 tiles |
| Power | 150 units | 500 | 1,200 (nearly a nuclear plant) |
| Water | 80 | 250 | 600 |
| Jobs | 10 | 40 | 120 |
| Tax a month | £400 | £1,500 | £4,000 |
| Asks for | nothing | 5 years' tax break | 10 years' tax break and grid priority (homes lose power first) |

### Tech zone (a district) — built (Nov 2026), not yet played by Sam
- A fourth kind of district (Districts > Tech zone, after CBD), painted with the District tool, free. **Its own tax rate** in the City panel, under the town's (– / +, 0-20%, starts at 9%): offices and industry inside pay it; homes and shops there pay the town's. The panel says how it's going ("no tax break, so no pull", "drawing a few firms in", "drawing firms in"), the jobs there and what the break cost last month.
- **Pull** = how far its rate is below the town's, out of 6 points (0 at the same rate, full at 6 below). Firms from outside want to bring jobs to fill that share of what its reachable office and industry plots hold (up to tenement size), at most 60 + a quarter of a job per resident. These jobs come **on top** of what the town's own workers want: they don't take workers from industry, and spare jobs bring people in. With any pull, the zone's plots grow first.
- With no break, its plots wait: "firms from outside only come for a tax break". Hover text: "Tech zone: offices and industry pay 3% tax".
- **Fairness**, a new happiness part: pull x the share of the town's jobs in the zone x 0.3 ("firms in the Tech zone pay less tax than everyone else"). So a small zone or a small break costs little; a whole town's jobs at 0% costs 0.3 appeal (about 10% happiness).
- Advisors: "Residents grumble that Tech zone firms pay less tax" (when fairness costs 0.05 or more), or "The Tech zone has no tax break, so no firms are drawn to it". Both open the Districts view.
- Saved (`tech_tax_rate`); older saves take the town's rate. Numbers under Districts in `scripts/settings.gd` (`TECH_*`).
- Still to come: companies that came for a low rate threatening to leave if it's raised (with the letters); the zone feeding how often letters come.
- Real-world cousins: Enterprise Zones and Freeports (UK), Opportunity Zones (US).
- Later, perhaps: separate tax rates for homes, shops, industry and offices, as SimCity 4 does.

### Tech workers
- A new key number: the share of residents with tech skills. It sets which stages of the ladder can write.
- Grown by schools (the base), a **college** (new, small, early), a **university** (new, a big multi-tile campus, mid-game: graduates, land value and student housing demand, but costly to run and students pay no tax) and a **research park** (new, next to the university: makes Big Tech and mega letters likelier). Parks, landmarks and transport help keep graduates.
- It feeds itself: tech jobs bring in tech workers, who bring more companies.
- Say yes to a big company without enough tech workers and it brings its own staff: more housing demand, higher prices, more people priced out.

### Education and tech workers — built (Nov 2026), not yet played by Sam
- A new **Education** category in the Build menu (after Transport):
  - **College** (£6,000, £150 a month, from 1,500 people, one plot): +3% of residents become tech workers (colleges together at most +9%). Drawn as a sandstone college with a glass wing.
  - **University** (£400 a tile, £40 a tile a month, from 5,000 people): dragged out as a campus; works as one site (a road beside any tile, and power). Each tile +1.2% tech workers (at most +24%, 20 tiles' worth) and **150 students** who want homes (0.5 a student). Land value +0.06. Drawn as old colleges round quads (honey or red sandstone, some with a tower) on lawns with paths and trees.
  - **Research park** (£300 a tile, £20 a tile a month, from 5,000 people): only within 3 tiles of a university. Each tile makes big companies 6% keener (at most twice as keen). Drawn as low glass labs on lawns.
- **Tech workers**: a share of residents. Its target: schools (5% when every home has one nearby) + colleges + university + tech jobs drawing people in (half a tech worker per job at company projects and Tech zone offices and industry), times how happy the town is (0.6 + 0.4 x happiness), at most 50%. Each month it moves 8% of the way there, so graduates take a few years to come through. City panel (Services): "Tech workers: 589 (9% of residents), rising". Saved; older cities start where they already are.
- **Big companies want them** (`tech_workers` in `Settings.PROJECTS`): the Gigafactory 400, the launch site 600, OpenAI 1,000, Google's campus 1,500 (data centres none). Without enough they're a quarter as keen; Who's interested says "would like more tech workers (you have 589, they want 1,500)", and an advisor suggests a college or university. Start-ups write more often in a town with more tech workers (up to twice as often at 50%).
- Not done: big companies bringing their own staff (more housing pressure) when you say yes without enough tech workers.

### New town problems
- **Cost of living**: a happiness complaint when home prices rise faster than wages; this is where gentrification shows.
- **Bills**: electricity bills rise when big users stretch the grid.
- **Boom and bust**: companies can shrink or leave, leaving an empty campus (drawn like abandoned buildings). It hurts most after years of tax breaks. Deals can carry claw-back if they leave early.
- **Community fund**: a deal can have the company pay for a park or school.

### Ideas, not yet decided
- Approval rating and elections every 4 years; interest groups (tech workers, long-time residents, unions, environmentalists, small businesses) who each like or hate a decision; protests on the map.
- Rival cities bidding for a company (like Amazon's HQ2 contest), or poaching yours.
- A policies panel: rent control, affordable housing quota, data centre water cap, launch noise curfew, a jobs tax on big employers.
- A tech market that booms and crashes (a flood of letters, then layoffs and empty offices); remote-work swings.
- Broadband as a utility to the Tech zone; 5G masts; power deals (Microsoft restarting a nuclear plant for its data centre); droughts.
- Gentrification seen on the map (corner shops turning into coffee shops near the Tech zone); private tech shuttle buses; automation cutting shop and office jobs; tents in parks when prices run away.
- A satirical headline ticker reacting to your choices.

### Build order (one at a time, played before the next)
1. **Tech zone** with its own tax rate. *Built Nov 2026, not yet played.*
2. **Letters and inbox**: start-ups and the data centre, with interest setting how often letters come. *Built Nov 2026 (letters, inbox, start-ups and the data centre), not yet played.*
3. **College, university, research park** and tech workers. *Built Nov 2026, not yet played.*
4. **The map: Palo Alto** (Sam chose a real place over a generated map); rebuild the examples. *Built Nov 2026, not yet played.*
5. **Big Tech and mega projects** (Google, Tesla, SpaceX, OpenAI...) with their wishlists and quirks. *Built Nov 2026: company projects, Tesla's Gigafactory, Google's campus, SpaceX's launch site and OpenAI's AI data centre. Still to do: Elon threatening to leave if the Tech zone tax goes up; Apple, Meta and Nvidia.*
6. **Deals** (Palantir, Waymo), companies leaving, headlines, goals; then whichever undecided ideas earn a place.

### To consider next (Sam, Nov 2026; not started)
- *Started Nov 2026:* **Californian homes** (Blender models `ranch`, `mission` (Spanish bungalow with an arcaded porch), `ca_villa` (two-storey Spanish revival with a balcony), `ca_modern` (flat-roofed, big glass)) replace the sandstone villas and bungalows (`MODEL_VARIANTS` in world3d.gd); street colours are stucco (white, cream, sand, peach, sage, pale yellow) under clay-tile or shingle roofs (`HOUSE_PALETTES`; the old ones kept as `SANDSTONE_HOUSE_PALETTES`). **Palms** line half the streets (`TreeKind.PALM`). **Golden hills**: open grass and fields are dry gold (`GOLDEN` in world3d.gd, `sunburnt()` in terrain.gdshader; lawns on plots stay green) and hedges are rare (`FIELD_HEDGE` 0.15). Still the old look: terraces and tenements (recoloured), shops, the light. **Strip malls** (small shops, stages 1-2: `strip_mall`/`_b`, a stucco row of six shopfronts under a canopy, with a Spanish tower or an anchor store) and **office parks** (small offices, stages 1-2: `glass_office2/3`, low glass offices with white floor bands) are set back behind a car park with palms (`_plan_strip_mall`, `_plan_office_park`); offices have more parking behind. Not done: the Build menu's pictures and one-liners still show the sandstone versions.
- **Make it feel like Silicon Valley.** Buildings, style and geography: Californian homes (low stucco ranch houses, Spanish-revival bungalows) in place of the sandstone villas and tenements; glass mid-rise offices, strip malls and big car parks; palm trees and dry golden hills; warmer, sunnier light. For the land, a bay with hills behind it (fits step 4, the generated map: a "Bay" kind of land). A big job: the whole building set and the countryside's look.
- *Done Nov 2026:* six of San Francisco's buildings replace the world landmarks in the menu (see Landmarks). Still to do: the Golden Gate Bridge and Alcatraz. The original idea: **San Francisco's famous buildings as landmarks**, alongside or instead of today's eight: e.g. the Golden Gate Bridge (needs a way to build over water), Transamerica Pyramid, Salesforce Tower, Coit Tower, the Painted Ladies (a row of Victorian houses), Alcatraz (an island), the Ferry Building, the Palace of Fine Arts.
- *Started Nov 2026:* SpaceX's lattice launch tower (with its "chopstick" arms) and stainless two-stage rocket, and Google's glass pavilions (3 and 4 storeys: frames, floor bands, columns, door canopy, planted roof) are Blender models now (`launch_tower`, `rocket`, `google_pavilion3/4` in tools/make_buildings.py), with the boxes kept as the fallback. Since then, also the halls: data centres, OpenAI and Tesla's factory are drawn as rows of model bays (`dc_hall` 30 m, `ai_hall` 30 m with ribbed fins, louvre bands and stair towers, `gigafactory_bay` 40 m with tall glazing strips and a black band), each in its company's colours, so a hall of any length keeps its details.
- **Proper Blender models for the company buildings**, in place of today's boxes and cylinders: glass pavilions with real window frames for Google, a lattice launch tower and a stainless rocket for SpaceX, Tesla's factory, and more detailed halls for the data centres and OpenAI. The box versions stay as the fallback (the usual rule), and the menu and letter pictures come from the same models.

## To do, in recommended order (Sam's feedback, Nov 2026)
Fixes and clear gaps first (they change how every game plays), then new features.

1. **Play the `tech-layer` branch, merge it into `main`, push.** Nothing since the Tech zone has been played. Pushing needs Sam to sign in once (`gh auth login`, `gh auth setup-git`).
2. **Start-ups: say what you get and keep the list.** *Sam: "What do I get by investing? Just jobs? Do I know how well they succeed? They disappear from the list after a while."*
   - What the code does now: backing one costs £1,000-3,000 and fills an empty Tech zone office plot at level 1 straight away (jobs and office tax). Each year it may grow a level (25%), fold (15%, its plot empties), or be bought by a big firm (4%, paying the town 8x its grant); backing them also makes investors keener (more letters).
   - Why they vanish: a fold is removed from the list (with one news line), and one whose plot declines to nothing, is bulldozed or rezoned is dropped silently. There's no limit on how many, but the inbox doesn't scroll, so a long list would run off the screen.
   - **Done (Nov 2026), not yet played by Sam.** Rather than a scrolling inbox, the inbox stays short (letters waiting, who's interested, two lines on start-ups: "4 backed: 1 going, 1 bought out, 1 went bust, 1 closed" and what they've made the town) and a **Records** window (from the inbox) keeps everything, with a summary at the top so it rarely needs scrolling:
     - Start-ups tab: totals (put in, tax paid, buy-outs, made or lost), the odds, then each start-up, going ones first (click one to fly to its office), then ended ones (bought out, went bust, closed), each with when it was backed, its level and jobs, its tax so far, any payout, and what it made the town (green or red).
     - Letters tab: every letter (up to 200) with the answer: backed / agreed (and the size) / turned down / no answer, and chips to filter them (All, Waiting, Said yes, Said no, No answer). A waiting one opens its card.
     - A bought-out start-up is paid once and then ends (it stays in town as an ordinary office); one whose plot is cleared or runs down closes with a news line; nothing is dropped. The start-up letter says what backing it gets you, with the odds; the hover over its office says when it was backed and its tax so far.
     - What the numbers show: one start-up's tax is small (a few pounds a month at level 1); the buy-out (about a 1 in 5 chance over its life) is the real prize. Worth looking at in the demand and money check (step 3).
3. **Demand check: shops against offices, and by density.** *Sam: "There's always demand for shops over offices"; "we don't know the demand by density"; "does a tech office need a particular density?"*
   - What the code does now: shop demand follows residents and also gets every visitor (stations, landmarks, the airport, launches), while offices get only a share of the workers not in shops, starting at 800 people, reaching half at 12,000, and halved where homes have no school. So shops lead for most of a game. The bars are scaled differently too (each against its own jobs).
   - Demand is per zone, not per density: density only sets how tall plots can grow, and the game never says which density is wanted.
   - Tech zone: any office or industry plot in it, at any density, pays its tax rate and draws outside firms; start-ups want an empty office plot there, any density. Nothing says so in the game.
   - To do: check the balance with numbers from the example cities and rebalance (offices may need their own pull, e.g. from tech workers and the Tech zone); show demand by density (or which density is wanted) on the bars' hover; say the Tech zone's rules in its menu text.
   - **Done (Nov 2026), not yet played by Sam.** Measured in the example City (43,000 people): shops were 41% of jobs and still wanted 6,200 more, because visitors (station, tourists, airport) added 57% on top of residents' shopping, while offices were full. Now: shops serve 16% of residents (was 20%; about a third of workers), all visitors' shopping is softly capped below 6% of the population (each source still adds a little: the City gets 5.1% with its airport, 4.0% without), offices start at 500 people and reach 55% of the non-shop workers at 10,000, and tech workers all want office work. In the old examples shops come out about right and offices are wanted; the examples were rebuilt.
   - Demand by density: demand is still per zone (in SimCity 4 the split is by wealth, not height). The bars' hover now says how many people or jobs each zone wants, the room left on its zoned plots by density, and roughly how many more low, medium or high density plots would take the rest (high only builds tall on valuable land).
   - The Tech zone's menu line, its picker text and the help now say it covers offices and industry at any density, start-ups want its empty office plots and big companies its open land.
4. **Homes near data centres lose value, and the hover says why.** *Sam: "Homes within a certain distance should be worth less, and the hover should say that's the reason."*
   - What the code does now: data centres already lower land value round them (-0.05 within 3 tiles; Gigafactory -0.06 and AI data centre -0.04 within 4), but it's small, capped with the other company effects, and the hover text doesn't name it.
   - To do: a clearer drop in home value near data centres (noise, humming fans, big sheds), and a hover line such as "Worth less: next to a data centre".
   - **Done (Nov 2026), not yet played by Sam.** Homes within 4 tiles (200 m) of a working data centre or AI data centre lose up to 0.15 land value (full right beside one, fading out; the nearest one counts, so two don't add up), on top of the small effect on all land. That's up to about a sixth off a home's price. Only homes (where people sleep); empty halls and ones still being built are quiet. A home's hover says "Worth 14% less: next to a data centre, whose cooling fans hum day and night"; a data centre's says homes within 200 m are worth up to 17% less. Numbers: `DC_HUM_RADIUS`, `DC_HUM_VALUE`.
5. **Data centres' power and water: realistic?** *Sam: "It seems a lot of both for the mega data centres."*
   - What the code does now (power in zone levels, roughly one per home plot level): data centre Small 160 / Standard 480 / Mega 1,200 power, water half that; AI data centre 1,000 / 2,500 / 6,000, and up to 3x more if you keep saying yes. A nuclear plant gives 1,500, so a Mega AI data centre needs four.
   - First look: power is about right or even low against real ones (a big AI site uses as much as a city of a million; the game's Mega uses several times a 40,000 town), so it's the point of the dilemma. Water looks high: real data centres use far less water than their power would suggest next to homes. To do: check against real figures, probably cut water by half or more, and show both against the town's own use in the letter ("as much power as 3 towns like yours").
   - **Done (Nov 2026), not yet played by Sam.** Checked against published figures: real hyperscale data centres now draw 200-600 MW and the biggest AI campuses about a gigawatt (OpenAI's Stargate plans about 7 GW in all), while a town of 40,000 uses about 60 MW. One unit of the game's power or water is what about 12 residents use (11-15 in the example towns), so the game's Mega data centre (1,200 power) is like 20 MW and its Mega AI one (6,000) like 100 MW: scaled down with everything else, but still bigger than most of a town, which is the dilemma. Power stays. Water was half the power; evaporative cooling uses about 2 litres a kWh (US average about 0.4), which comes to about 0.15 of the power in game units, so water is cut by 70% (data centre 24 / 72 / 180, AI 150 / 375 / 900). Gigafactory, campus and launch site water left as they were. The letter's sizes now say "1,200 power (as much as 14,000 people use) · 180 water (2,200 people's)" (`Settings.PEOPLE_PER_UNIT`).

6. **Finish Big Tech (step 5):** Elon threatening to move Tesla and SpaceX if the Tech zone tax goes up; letters from Apple, Meta and Nvidia.
   - **Elon's threat: done (Nov 2026), not yet played by Sam.** Each Tesla/SpaceX deal remembers the Tech zone tax when it was agreed (`tax_seen`). Raise the tax above it and next month Elon writes ("Put it back or Tesla moves to Texas... You have 6 months. Real ones, not my ones."); the card opens by itself. Put it back to X% (the tax goes back down) or Keep the tax: then, or if the letter runs out, he moves his companies out (their buildings stay empty, the hover says why) unless he bluffs (30%: "Never said we'd leave." He accepts the new rate). Empty Gigafactory halls can be taken over by a cloud company; an empty launch site can't.
   - **Nvidia's chip factory: done (Nov 2026), not yet played by Sam.** Jensen writes from 8,000 people (wants 1,200 tech workers): "the more you buy, the more you save". Sizes (`CHIP_SCALES`): Small 9 tiles, 400 power, 350 water, 500 jobs, asks 8 years without tax; Standard 20 tiles, 1,000 power, 900 water, 1,400 jobs, 3 years; Mega 42 tiles, 2,400 power, 2,200 water, 3,600 jobs, no tax break and the most tax per tile (the bigger the better). Takes 18-30 months to build. Water is the catch (a real fab rinses wafers in millions of litres of ultra-pure water a day), plus a little chemical pollution and lower land value nearby. Drawn as a white clean-room fab with exhaust stacks and scrubbers on the roof, a green entrance and a yard of water and chemical tanks.
   - **Apple's and Meta's campuses: done (Nov 2026), not yet played by Sam.** A campus letter now comes from Google, Apple or Meta (whoever isn't building one here yet), same sizes and the same house-price effect. Google: opens in exactly nine months. **Apple** (Tim Cook: "We can't tell you what it's for. We can tell you it's a circle."): takes 24-36 months, and stays shut while the air round it is dirtier than "a little" pollution (keep industry and coal away; the hover says so). Drawn as a ring of curved glass with a dark solar roof and an orchard inside. **Meta** (Mark: "We'll probably change what it's for at some point. We move fast."): 9-15 months; one to three years after opening it pivots once, to the metaverse (half the jobs, 70% of the tax: "legless avatars") or to AI (three times the power). Drawn as one long white building with a blue band and a park on its roof. Numbers: `CAMPUS_BUILD_MONTHS`, `APPLE_CLEAN_AIR`, `META_PIVOT_MONTHS`, `META_PIVOTS`.
7. **Deals and drama (step 6):** Palantir and Waymo deals, companies leaving town, a headline ticker, goals.
8. **The rest of the Californian look:** medium and high density (terraces, tenements, sandstone shops and offices still have the old look) and warmer light.
   - **Done (Nov 2026), not yet played by Sam.** New Blender models in the same sizes, so they fit the same plots:
     - Terraces are now **townhouses**: rows of three in stucco, either Spanish (one low clay-tile roof, arched doors, iron balconettes, the middle house stepped forward) or modern (flat roofs at two heights, big dark-framed windows, a coloured panel by each door).
     - Tenements are now **garden apartments**: Spanish (low tile roof, a stair tower with an arched entry and its own tiled top, a balcony for every flat) or mid-century (flat roof with a deep white edge, an open walkway along each floor, coloured panels, parking under the ground floor). Their shared back court is now a **pool courtyard**: a paved deck, a pool, loungers and parasols, palms in the corners.
     - Shops with flats are now **main-street blocks**: Spanish revival (arched shopfronts under a tiled hood, iron balconettes, a tiled parapet and a little corner tower) or modern mixed use (glass ground floor, glass balconies, coloured panels).
     - The grand sandstone block (mansion flats, offices, big shops, the town hall, library, police station, college and university) is now **Mediterranean revival**: stucco, round-arched ground floor, deep windows, timber corbels under deep eaves, a low clay-tile roof, and an arched belvedere on the taller ones (like Stanford's or Palo Alto's own).
     - Colours: stucco whites, creams, sand, peach and pale yellow under clay tiles. Flat roofs are pale "cool roofs". Downtown towers lose their red sandstone and brick (pale granite and buff instead).
     - Warmer sunlight (`SUN_DAY_COLOUR`, `SUN_ENERGY`).
     - The Build menu's pictures were re-rendered to match.
     - The sandstone models are kept: set `CALIFORNIA` false in world3d.gd and put the old `MODEL_VARIANTS` back for the old look.
9. **The Golden Gate Bridge and Alcatraz** (need building over water).
   - **The map moved to Menlo Park (Nov 2026), not yet played by Sam.** San Francisco itself is 50 km from Palo Alto, too far for one map, so Sam chose Menlo Park and East Palo Alto by the Bay (9 x 8 km, 28% water), with the Dumbarton crossing (about 1.1 km of water) to land on the far side at the top right. Palo Alto saves don't load on it (the old map is kept in map/).
   - **Reclaim land: done (Nov 2026), not yet played by Sam.** Roads > Reclaim land (£500 a tile): drag a box out from the shore over the water and the water in it that joins land becomes new land, level with the shore it grows from. Open water away from the shore says "New land has to join land". Bridges and Alcatraz stay on the water. The new land is plain ground (no fields) and its hover says "Reclaimed land"; build on it as on any land. Undo puts the water back; a new city has the map's own coast.
   - **Bridges: done.** Drag a road (or avenue, or motorway) straight across the water from shore to shore: the water part is a bridge, a deck 8 m up on piers, with the road ramping up at each end. 25 times the cost a tile and 6 times the upkeep; at most 40 tiles (2 km). A drag that stops in the water, turns, or is too long says why and builds no bridge. Traffic uses it like any road.
   - **The Golden Gate Bridge: done (Nov 2026), not yet played by Sam.** In Landmarks (unlocked at 15,000 people, £60,000, £150 a month): point at one of your bridges at least 400 m long and click. The whole bridge turns International Orange, with two tall towers a fifth of the way in from each end, main cables sagging between them and down to the ends, and hangers to the deck (no piers but the towers). Tourists come (more shop demand, like the other landmarks) and it adds appeal. One per town. It's the bridge it was made from: bulldoze the bridge and it's gone.
   - **Alcatraz: done (Nov 2026), not yet played by Sam.** In Landmarks (10,000 people, £30,000, £80 a month): built out on the water, at least 100 m from any shore, on its own rock (drawn bigger than its tile: stepped ledges with scrub, the pale cell house, the lighthouse, a water tower on legs and the dock building). Visitors come by ferry: it needs no road, power or water, and draws half as many visitors again if the town has the Ferry Building.

## Phases
1. **Sandbox** — map, pan and zoom, paint roads and zones, bulldoze, save and load. *Done when you can paint a city.*
2. **Living city** — simulation tick, demand, zones grow, power, taxes and upkeep. *Done when the city grows on its own.*
3. **Real game** — services (done), land value (done), overlay maps (done), taxes vs services (done), happiness (done), goals. *Done when a friend asks for more.*
4. **Polish and share** — 3D art, sound, tutorial, publish on itch.io.
5. **Tech layer** — company letters, the Tech zone, tech workers, a generated map (see Tech layer). *Done when every letter feels like a real dilemma.*

## Working rules
- One small feature per session; play it before moving on.
- Keep all tuning numbers (costs, growth rates) in one settings file.
- Commit to git after each working feature.
