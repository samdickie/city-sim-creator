extends RefCounted
## Every number that tunes the game lives here.
## Change these to rebalance; nothing else needs editing.

# --- Money ---
const START_MONEY := 20000        # £ at the start of a new city

# Cost to build one tile, in £.
const ROAD_COST := 10
const HOMES_COST := 40
const SHOPS_COST := 60
const INDUSTRY_COST := 80
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
const MAX_LEVEL := 3              # zones grow in 3 steps: small, medium, dense
const PEOPLE_PER_LEVEL := 20      # residents added each time homes grow a level
const SHOP_JOBS_PER_LEVEL := 8    # jobs added each time shops grow a level
const INDUSTRY_JOBS_PER_LEVEL := 15
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
