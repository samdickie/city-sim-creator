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

# --- Power ---
const POWER_PLANT_COST := 3000
const POWER_LINE_COST := 5
const POWER_PER_PLANT := 200      # one plant powers this many zone levels
const POWER_PLANT_UPKEEP := 100   # £ per plant per month

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

# --- Look (no effect on the simulation) ---
const DAY_SECONDS := 240.0        # real seconds for a full day and night at normal speed
const START_TIME_OF_DAY := 0.38   # 0 = midnight, 0.5 = noon
const PEOPLE_PER_CAR := 25        # one car on the roads per this many residents
const MAX_CARS := 400

# --- Density, land value and prices ---
# Once demand for homes (or shops) is more than the low-rise plots can still take,
# the most valuable plots build upwards: level 4, 5 and 6 need at least this land value.
const TALL_VALUE_NEEDED := [0.0, 0.0, 0.0, 0.0, 0.35, 0.5, 0.65]
const TALL_GROWTH_CHANCE := 0.15  # chance per month that a valuable plot builds taller
const BASE_LAND_VALUE := 0.30     # land value runs from 0 (worst) to 1 (best)
const SEA_BONUS := 0.30           # right by the sea (fades out over SEA_VIEW_TILES)
const SEA_VIEW_TILES := 6
const PARK_BONUS := 0.07          # per park tile within 3 tiles
const SHOP_BONUS := 0.012         # per level of shops within 3 tiles
const INDUSTRY_PENALTY := 0.03    # per level of industry within 4 tiles
const PLANT_PENALTY := 0.30       # a power plant within 5 tiles
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
const HOMES_AT_STAGE := [0, 20, 40, 60, 100, 150, 220]
const SHOP_JOBS_AT_STAGE := [0, 8, 16, 24, 40, 60, 90]
const INDUSTRY_JOBS_AT_STAGE := [0, 15, 30, 45]
# Zoning cost per tile for low / medium / high density.
const HOMES_COSTS := [40, 60, 100]
const SHOPS_COSTS := [60, 80, 120]
