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
- District tool (Z) paints a height rule over any land, free: CBD, conservation area, or back to normal. Choosing it shows the Districts map view.
- Conservation area: nothing above stage 3 (tenements, four storeys); +0.03 land value for character. Existing taller buildings are trimmed back.
- CBD: high-density homes and shops can rise two more stages, to skyscrapers: stage 7 (20-26 storeys; 350 residents or 160 jobs) and stage 8 (32-42 storey landmark that steps in twice, often with a spire; 500 residents or 260 jobs). +0.08 land value across the CBD, and tall buildings grow 1.5x faster there.
- Skyscrapers also need land value 0.72 / 0.8, a town of 8,000 people, and a working railway station or bus depot within 600 m. Each stands on a three-storey podium (glass, or classical with shopfronts) with a planted plaza behind.

## Building models
- Low-rise Troon buildings are detailed 3D models made in Blender by `tools/make_buildings.py` (saved to `assets/models/*.glb`): villa, bungalow (dormers), terrace of three, tenements (3 and 4 storeys, canted bays, close door, cornice, chimney stacks), shop parades (one storey, or two with flats and a slate roof) and sandstone shops with flats (2-4 storeys, flat roof with lift housing and vents).
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
- Top left: game menu (New city, Save, Load, How to play, Day and night), city name, date and clock, and speed as pause / play / fast icons (the chosen one lit; pause in amber).
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
- Towns over 400 people make rubbish (1 per resident, 0.5 per job). Landfill (£100 a tile, takes 800, lowers land value nearby) and recycling centres (£2,500, takes 2,500, from 1,000 people) collect it. Uncollected rubbish cuts appeal (up to -0.5).

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
- All the numbers for these buildings are in `Settings.BUILDINGS`.

## Services
- Services tool (0), then pick one (Tab or the buttons): police station £1,500, fire station £1,500, school £2,000, hospital £4,000. One tile each; they need a road and power (3 units) to work.
- Each covers the area round it: fully close by, fading out at its reach (police 800 m, fire 700 m, school 600 m, hospital 1 km at 100% funding). Covered areas gain land value.
- Funding (- / +, 0-150%) sets upkeep (police £60, fire £60, school £80, hospital £150 a month at 100%) and reach (50% funding reaches 70% as far; 0% closes it).
- Effects: over 800 people, homes and shops with no police grow at half speed; over 1,200, homes need a school to grow past terraces; over 2,500, homes with no hospital grow at half speed; over 500, built plots with no fire cover can burn down (rarely; industry twice as often).
- A Services map view shows how many of the four cover each area.

## Map views (overlays)
- O or the row of icons bottom right: Normal, Land value, Power, Roads, Growth, Services, Water, Districts, Pollution (names on hover). The chosen view's name, a line about it and its colour key show above the icons.
- Ground and buildings take each plot's colour; trees, paving and parked cars hide so the colours read clearly.
- Land value uses the same bands as the hover text (0.2 / 0.35 / 0.5 / 0.65). Growth: green growing, yellow waiting (demand, space or land value), red stuck (road or power), blue fully built, brown abandoned.

## Pollution
- A pollution map (0 clean to 1 heavy) is worked out every month and whenever the town changes; it isn't saved (loading works it out again).
- Sources add up where they overlap, fading out with distance: industry 0.06 per stage (200 m), coal plant 1.2 (450 m), gas plant 0.5 (300 m), harbour 0.35 (250 m), landfill 0.12 per tile (200 m), recycling 0.08 (100 m). Nuclear, wind and solar are clean. Parks soak some up (golf half as much; woodland a bit over half, capped, see Woodland). The total is eased into 0-1, so a coal plant is "heavy" for about 200 m.
- Effects: land value -0.2 in full pollution; homes grow up to 60% slower in polluted air (the hover text says so); the share of residents in polluted air (0.3 or more) costs up to -0.15 appeal. The old land value penalties of industry, power plants, landfill and the harbour were halved or so, as the smoke is now counted here.
- Pollution map view: clean, a little, some, polluted, heavy (green to red). Hover text mentions pollution from "some" upwards, and polluting buildings say how far their pollution reaches.
- Coal plant chimneys smoke (a few particle streams; looks only).
- For a happiness score or advisors: `pollution_at(i)`, `pollution_band(i)`, `polluted_homes_share()`, `pollution_feeling()` (already in appeal), `air_word()` in `scripts/simulation.gd`. Numbers in the Pollution section of `scripts/settings.gd`.

## Advisors
- A ticker, top centre, shows the most urgent tip and a count when something needs attention (red dot urgent, amber warning, blue advice). The count opens the full list, most urgent first. Hidden when all is well.
- Every tip comes from real simulation state: why zone plots aren't growing (the same reasons as the hover text and Growth view), power and water used vs supplied, rubbish collected, buildings with no road or power, money trend, taxes vs services, missing fire station or school, skyscrapers waiting for transport.
- Tips appear and disappear as the town changes. Only urgent ones also flash a message, once, and not again for a year.
- Clicking a tip switches on the map view that shows the problem (Power, Water, Roads, Services, Growth, Land value); clicking again goes back to normal. Hover for a longer explanation.
- The rules live in `scripts/advisors.gd` (`tips(sim)` returns `[{id, text, detail, severity, overlay}]`), separate from the HUD, so new tips are one `_add()` each.

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
- Cars, buses and people walking bring the streets to life. Looks only: they don't affect the simulation. T turns them off and on (`TRAFFIC_ON` in settings to start with them off).
- Cars keep left and follow the road's own straight runs and bends, slowing for corners, junctions and dead ends (where they turn round), and queue behind the car in front. At a junction they pick a way at random, slightly preferring straight on. They tilt with the hills; after dark they have head and tail lights and a pool of light on the road ahead.
- Red buses run on the roads within reach of a working bus depot (about one vehicle in twelve).
- People walk along both pavements, a little apart, bobbing as they go.
- How busy a street is depends on the plots beside it: one car per 200 residents and jobs, one walker per 40 (shops count three times, homes a quarter), capped per street. CBD streets have 1.5x the walkers. Night has 30% of the cars and 12% of the walkers. None until the town has people or jobs.
- Only the streets round the camera are filled (cars up to 1.8 km away as you zoom out, people within 700 m); anyone who drives out of range reappears in view. At most 300 vehicles and 400 people; no people drawn beyond 1.1 km zoom and no cars beyond 3.5 km.
- Drawn with six MultiMeshes (car bodies, cabins, lamps, light pools, people, heads) filled from one buffer each frame; with a crowd, each person moves every other frame. Code in `scripts/traffic.gd`; numbers in `scripts/settings.gd`.

## Phases
1. **Sandbox** — map, pan and zoom, paint roads and zones, bulldoze, save and load. *Done when you can paint a city.*
2. **Living city** — simulation tick, demand, zones grow, power, taxes and upkeep. *Done when the city grows on its own.*
3. **Real game** — services (done), land value (done), overlay maps (done), taxes vs services (done), happiness (done), goals. *Done when a friend asks for more.*
4. **Polish and share** — 3D art, sound, tutorial, publish on itch.io.

## Working rules
- One small feature per session; play it before moving on.
- Keep all tuning numbers (costs, growth rates) in one settings file.
- Commit to git after each working feature.
