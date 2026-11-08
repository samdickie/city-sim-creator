extends RefCounted
## Every number that tunes the game lives here.
## Change these to rebalance; nothing else needs editing.

# --- Money ---
const START_MONEY := 20000        # £ at the start of a new city

# Cost to build one tile, in £.
const ROAD_COST := 10
const INDUSTRY_COST := 80         # (homes and shops cost depends on density, see below)
const BULLDOZE_COST := 5          # clearing a built tile (empty tiles are free)

# Hills: each metre of height difference to a neighbouring tile
# adds this much to the cost (0.08 = +8% per metre).
const SLOPE_COST_PER_METRE := 0.08
# Steeper than this (metres of rise across one tile) can't be built on.
const MAX_SLOPE_M := 12.0

# --- Time ---
const MONTH_SECONDS := 3.0        # real seconds per game month at normal speed
const FAST_SPEED := 3             # how much faster the fast-forward button runs
const START_YEAR := 2027

# --- Growth ---
const ROAD_REACH := 2             # a zone grows if a road is within this many tiles
const GROWTH_CHANCE := 0.25       # chance per month that a wanted zone grows
const DECLINE_CHANCE := 0.05      # chance per month that an unwanted zone shrinks

# --- Abandoned buildings ---
# A built plot is "in decline" in any month it has no road, no power, no water
# (anything past the first stage), too little demand (more homes, shops or works
# than the town needs) or the town is very unpopular (high taxes, poor services,
# rubbish). Decline only trims a plot down to its last building; after enough
# months in decline that building is abandoned: empty, boarded up, no tax.
const ABANDON_MONTHS := 36         # months in decline before a building may be abandoned
const ABANDON_WARN_MONTHS := 18    # from here the hover text warns it's run down
const ABANDON_CHANCE := 0.1        # after that, the chance each month that it's abandoned
const DECLINE_RECOVERY := 3        # each good month takes this many off a plot's decline count
const ABANDON_APPEAL := 0.2        # town appeal below this counts as decline ("stopping growth")
const ABANDON_OVERSUPPLY := 2.0    # demand below minus this many first-stage plots' worth counts as decline
const REFURBISH_CHANCE := 0.1      # chance each month an abandoned building is done up once it's wanted again
const ABANDONED_VALUE_PENALTY := 0.04   # land value an abandoned building takes off its plot (less nearby)
const ABANDONED_RADIUS := 2             # ...out to this many tiles

# --- Demand ---
const WORKER_SHARE := 0.5         # share of residents who work
# Shop and office jobs a town supports per resident (industry employs the rest of the workers).
const SHOP_JOBS_PER_PERSON := 0.2
const TOWN_PULL := 100            # people who'd like to move to even a brand-new town
const REGION_GROWTH := 0.04       # plus this share of the population, each month, from the region
const JOB_PULL := 1.5             # each spare job draws this many residents (each jobless worker deters as many)

# --- Taxes and upkeep ---
const DEFAULT_TAX_RATE := 0.09    # 9%
const MAX_TAX_RATE := 0.20
# Each 1% above 9% cuts the town's pull by 10% (each 1% below adds 10%).
# From about 19%, people and businesses start leaving.
const TAX_DEMAND_EFFECT := 10.0
# People put up with higher taxes when they can see them paying for good services:
# with every home fully covered, taxes above 9% hurt only this much as much...
const TAX_TOLERANCE_GOOD := 0.3
# ...and with no services at all, this much more.
const TAX_TOLERANCE_POOR := 1.3
# Bigger towns expect services: this many people expect full cover (up to 70%).
const SERVICES_EXPECTED_POP := 4000
const SERVICES_EFFECT := 0.6      # how much better (or worse) than expected services move appeal
const TAX_BASE := 2.0             # £ per resident or job per month at a 100% rate
const ROAD_UPKEEP := 0.5          # £ per road tile per month

# --- Happiness ---
# Happiness (0-100%) sums up how residents feel, and it is what draws people in.
# It adds up taxes against services, services against what people expect, leisure
# and rubbish (as above), plus the things below that only residents feel at home.
# Each is in "appeal" points: a normal town has appeal 1 (67% happy); appeal 0.5
# (50%) is where people stop wanting to move in, and below 0 (33%) they leave.
const JOBS_START_POP := 400       # below this, people happily work in the towns nearby
const JOBS_SLACK := 0.05          # this much unemployment is normal and nobody minds
const UNEMPLOYMENT_EFFECT := 2.0  # appeal lost per share of workers out of work (above the slack)
const HOUSING_EFFECT := 0.15      # appeal lost in a severe housing shortage (homes too dear)
const NO_POWER_EFFECT := 0.8      # appeal lost if every home were without power...
const NO_WATER_EFFECT := 0.6      # ...or without water (only homes big enough to need it)
const COMPLAINT_SIZE := 0.05      # appeal a thing must cost before residents complain about it

# --- Power ---
const POWER_LINE_COST := 5
# (Power plants, wind and solar are in BUILDINGS below.)

# --- Parks ---
const PARK_COST := 100
const PARK_UPKEEP := 1.0          # £ per park tile per month

# --- Services (in this order: police, fire, school, hospital) ---
const SERVICE_NAMES := ["Police station", "Fire station", "School", "Hospital"]
const SERVICE_WORDS := ["police", "fire", "school", "hospital"]
const SERVICE_COSTS := [1500, 1500, 2000, 4000]    # £ to build
const SERVICE_UPKEEP := [60, 60, 80, 150]           # £ per month at 100% funding
const SERVICE_RADIUS := [16, 14, 12, 20]            # tiles covered at 100% funding (16 = 800 m)
const SERVICE_POWER := 3                            # power each uses, in zone levels
const SERVICE_LAND_BONUS := [0.04, 0.03, 0.05, 0.04] # land value added where fully covered
const COVERED := 0.3                                # coverage that counts as "covered"
const MAX_FUNDING := 1.5                            # funding runs from 0% (closed) to 150%
const POLICE_NEEDED_POP := 800     # bigger towns: homes and shops with no police grow at half speed
const SCHOOL_NEEDED_POP := 1200    # bigger towns: homes need a school to grow past terraces
const HOSPITAL_NEEDED_POP := 2500  # bigger towns: homes with no hospital grow at half speed
const FIRE_START_POP := 500        # fires can break out once the town is this big
const FIRE_CHANCE := 0.0005        # chance per built plot per month with no fire cover (industry x2)

# --- Districts: height rules painted over the zones ---
# 0 = normal, 1 = conservation area, 2 = central business district (CBD).
const DISTRICT_NAMES := ["Normal", "Conservation area", "CBD"]
const CONSERVATION_MAX_STAGE := 3   # tenements (4 storeys) at most
const CONSERVATION_VALUE := 0.03    # land value for the character of the old town
const CBD_EXTRA_LEVELS := 2         # high-density plots in a CBD can rise two more stages (skyscrapers)
const CBD_VALUE := 0.08             # land value added across a CBD
const CBD_TALL_BOOST := 1.5         # tall buildings grow this much faster in a CBD
const SKYSCRAPER_POP := 8000        # skyscrapers (stage 7 and up) need a town this big...
const SKYSCRAPER_TRANSIT := 12      # ...and a working station or bus depot within this many tiles

# --- Other buildings: power, utilities, leisure and transport ---
# Each one: name, cost (per tile for "area" ones you drag over), monthly upkeep,
# the population it unlocks at, and what it does:
#   power / water / rubbish   how much it supplies (power and water in zone levels,
#                             rubbish in residents' worth)
#   uses_power                power it needs to work (0 = none)
#   value, radius             land value it adds (or takes away) round about, in tiles
#   appeal                    how much it makes the whole town more appealing
#   bus                       tiles round a bus depot where plots can be 3 tiles from a road
#   visitors                  extra shop demand it brings, as a share of the population
#   port_jobs                 extra industry demand a harbour brings
#   near_sea                  must be built next to the sea
#   only_one                  the town can only have one
const BUILDINGS := {
	"coal": {"name": "Coal power plant", "cost": 3000, "upkeep": 100, "power": 200,
		"value": -0.15, "radius": 5, "about": "Cheap power, but smoky: pollutes the air and lowers land value nearby"},
	"gas": {"name": "Gas power plant", "cost": 5000, "upkeep": 150, "power": 400, "unlock": 1000,
		"value": -0.08, "radius": 4, "about": "Twice the power of coal and cleaner"},
	"nuclear": {"name": "Nuclear power plant", "cost": 15000, "upkeep": 350, "power": 1500, "unlock": 5000,
		"value": -0.20, "radius": 6, "about": "Huge output for a big town; people don't like living next to it"},
	"wind": {"name": "Wind turbine", "cost": 400, "upkeep": 8, "power": 25, "area": true,
		"value": -0.02, "radius": 1, "about": "Clean power, one turbine per tile (drag to build a wind farm)"},
	"solar": {"name": "Solar farm", "cost": 300, "upkeep": 5, "power": 15, "area": true, "unlock": 300,
		"about": "Clean, quiet power (drag over a field)"},
	"water_pump": {"name": "Water pump", "cost": 800, "upkeep": 30, "water": 400, "uses_power": 2,
		"about": "Supplies water for 400 zone levels; water travels through roads and buildings"},
	"water_tower": {"name": "Water tower", "cost": 300, "upkeep": 10, "water": 120, "uses_power": 1,
		"about": "A small, cheap water supply"},
	"landfill": {"name": "Landfill", "cost": 100, "upkeep": 5, "rubbish": 800, "area": true,
		"value": -0.06, "radius": 3, "about": "Takes the rubbish of 800 residents per tile; nobody wants to live by it"},
	"recycling": {"name": "Recycling centre", "cost": 2500, "upkeep": 70, "rubbish": 2500, "uses_power": 3,
		"unlock": 1000, "value": -0.01, "radius": 2, "about": "Takes the rubbish of 2,500 residents, cleanly"},
	"golf": {"name": "Golf course", "cost": 150, "upkeep": 2, "area": true, "value": 0.07, "radius": 3,
		"appeal": 0.004, "about": "Fairways, greens and bunkers (drag to lay out holes); raises land value"},
	"library": {"name": "Library", "cost": 1200, "upkeep": 40, "uses_power": 2, "unlock": 500,
		"value": 0.05, "radius": 6, "appeal": 0.02, "about": "Raises land value and appeal"},
	"museum": {"name": "Museum", "cost": 3500, "upkeep": 80, "uses_power": 3, "unlock": 2000,
		"value": 0.08, "radius": 8, "appeal": 0.04, "about": "A big draw: land value and appeal"},
	"stadium": {"name": "Stadium", "cost": 8000, "upkeep": 150, "uses_power": 6, "unlock": 5000,
		"value": 0.02, "radius": 8, "appeal": 0.08, "only_one": true, "about": "A football ground: a big boost to appeal"},
	"marina": {"name": "Marina", "cost": 4000, "upkeep": 60, "uses_power": 2, "unlock": 1500, "near_sea": true,
		"value": 0.12, "radius": 5, "appeal": 0.03, "about": "Yachts by the shore: land value soars nearby"},
	"town_hall": {"name": "Town hall", "cost": 5000, "upkeep": 100, "uses_power": 3, "unlock": 1000,
		"value": 0.06, "radius": 6, "appeal": 0.06, "only_one": true, "about": "The heart of the town: appeal and land value"},
	"bus_depot": {"name": "Bus depot", "cost": 2000, "upkeep": 80, "uses_power": 3, "unlock": 500,
		"value": 0.03, "radius": 6, "bus": 14, "about": "Buses let plots up to 3 tiles from a road grow (within 700 m)"},
	"station": {"name": "Railway station", "cost": 6000, "upkeep": 120, "uses_power": 4, "unlock": 2000,
		"value": 0.08, "radius": 6, "visitors": 0.03, "about": "Visitors by train: more demand for shops, higher land value"},
	"harbour": {"name": "Harbour", "cost": 7000, "upkeep": 120, "uses_power": 4, "unlock": 1000, "near_sea": true,
		"value": -0.02, "radius": 3, "port_jobs": 80, "about": "Ships bring trade: more demand for industry"},
}
const LEISURE_APPEAL_MAX := 0.3   # all the leisure buildings together add at most this much appeal
const RUBBISH_START_POP := 400    # below this the town's rubbish isn't a problem
const RUBBISH_PER_JOB := 0.5      # a job makes half as much rubbish as a resident
const RUBBISH_EFFECT := 0.5       # appeal lost when none of the rubbish is collected

# --- Pollution ---
# Pollution runs from 0 (clean air) to 1 (heavy). Each source adds its strength on
# its own tile, fading to nothing at the edge of its spread (in tiles; 1 tile = 50 m).
# Overlapping sources add up, so a big industrial estate is far worse than one works.
# Land value penalties in BUILDINGS (and INDUSTRY_PENALTY) are only the eyesore and
# noise; the smoke is counted here.
const INDUSTRY_POLLUTION := 0.06          # per stage of industry: small works 0.06, large factory 0.18
const INDUSTRY_POLLUTION_SPREAD := 4      # 200 m
# Other buildings that pollute (only while working): [strength, spread in tiles].
# Nuclear, wind and solar are clean.
const POLLUTION_SOURCES := {
	"coal": [1.2, 9],                     # heavy, reaches 450 m
	"gas": [0.5, 6],
	"landfill": [0.12, 4],                # per tile, so a big tip smells more
	"recycling": [0.08, 2],
	"harbour": [0.35, 5],                 # ships' engines
}
const PARK_CLEANING := 0.1                # each park tile soaks up this much within its spread (golf half)
const PARK_CLEANING_SPREAD := 2
# Bands for the map and hover text: clean · a little · some · polluted · heavy.
const POLLUTION_BANDS := [0.05, 0.15, 0.3, 0.5]
const POLLUTED := 0.3                     # from here a plot counts as "polluted"
const POLLUTION_VALUE_EFFECT := 0.2       # land value lost in full pollution
const POLLUTION_GROWTH_EFFECT := 0.6      # homes in full pollution grow this much slower (0.6 = 60%)
const POLLUTION_APPEAL_EFFECT := 0.15     # appeal lost if every resident lived in polluted air

# --- Look (no effect on the simulation) ---
const DAY_SECONDS := 240.0        # real seconds for a full day and night at normal speed
const START_TIME_OF_DAY := 0.38   # 0 = midnight, 0.5 = noon

# --- People and traffic (looks only; T turns them off and on) ---
const TRAFFIC_ON := true          # cars and people on the streets when the game starts
const MAX_CARS := 300             # most cars and buses drawn at once (only round the camera)
const MAX_PEOPLE := 400           # most people walking at once (only round the camera)
const PEOPLE_PER_CAR := 200       # residents and jobs on the plots beside a street, per car on it
const PEOPLE_PER_WALKER := 40     # the same, per person walking (shops count 3x, homes 0.25x)
const CARS_PER_STREET := 2.0      # the busiest streets: at most this many cars per road tile
const WALKERS_PER_STREET := 4.0   # ...and people per road tile
const NIGHT_TRAFFIC := 0.3        # share of the daytime cars still out at night
const NIGHT_WALKERS := 0.12       # share of the daytime people still out at night

# --- Density, land value and prices ---
# Once demand for homes (or shops) is more than the low-rise plots can still take,
# the most valuable plots build upwards: level 4, 5 and 6 need at least this land value.
const TALL_VALUE_NEEDED := [0.0, 0.0, 0.0, 0.0, 0.35, 0.5, 0.65, 0.72, 0.8]
const TALL_GROWTH_CHANCE := 0.15  # chance per month that a valuable plot builds taller
const BASE_LAND_VALUE := 0.30     # land value runs from 0 (worst) to 1 (best)
const SEA_BONUS := 0.30           # right by the sea (fades out over SEA_VIEW_TILES)
const SEA_VIEW_TILES := 6
const PARK_BONUS := 0.07          # per park tile within 3 tiles
const SHOP_BONUS := 0.012         # per level of shops within 3 tiles
const INDUSTRY_PENALTY := 0.015   # per level of industry within 4 tiles (its smoke is in Pollution above)
const BASE_HOME_PRICE := 160000   # £ for a home on average land with no shortage
const SHORTAGE_PRICE_EFFECT := 0.8 # a severe shortage pushes prices up by this much

# --- Zoning density ---
# A plot's building "stage" = its level + the density's head start:
#   stage 1 villas · 2 two rows of villas / terraces · 3 tenements
#   stage 4 mansion flats · 5 modern flats · 6 towers   (shops: parades up to an office tower)
# Low density: levels 1-2 (stages 1-2). Medium: levels 1-3 (stages 2-4).
# High: levels 1-4 (stages 3-6). Industry has one density (stages 1-3).
const DENSITY_NAMES := ["low", "medium", "high"]
const DENSITY_START := [0, 1, 2]          # stage = level + this
const DENSITY_MAX_LEVEL := [2, 3, 4]
const FREE_STAGE := 3                     # up to here, plots grow whenever there's demand
# How many residents / jobs a plot holds at each stage (0 to 6).
# Stages 7 and 8 are skyscrapers, only in a CBD district (see below).
const HOMES_AT_STAGE := [0, 20, 40, 60, 100, 150, 220, 350, 500]
const SHOP_JOBS_AT_STAGE := [0, 8, 16, 24, 40, 60, 90, 160, 260]
const INDUSTRY_JOBS_AT_STAGE := [0, 15, 30, 45]
# Zoning cost per tile for low / medium / high density.
const HOMES_COSTS := [40, 60, 100]
const SHOPS_COSTS := [60, 80, 120]
