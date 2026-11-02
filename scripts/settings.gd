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
const TOWN_PULL := 100            # jobs-worth of pull that attracts the first residents
const SHOP_JOBS_PER_PERSON := 0.1 # shop jobs a town supports per resident
const INDUSTRY_PULL := 20         # extra industry jobs wanted beyond the workforce

# --- Taxes and upkeep ---
const DEFAULT_TAX_RATE := 0.09    # 9%
const MAX_TAX_RATE := 0.20
const TAX_DEMAND_EFFECT := 4.0    # each 1% above 9% cuts demand by 4%
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
