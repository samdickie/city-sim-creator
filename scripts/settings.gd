extends RefCounted
## Every number that tunes the game lives here.
## Change these to rebalance; nothing else needs editing.

# --- Money ---
# Difficulty is picked when a new city starts and is saved with it. It only
# changes money: what you start with, a multiplier on every monthly running cost
# (roads, parks, services, power plants, utilities, leisure, transport), the
# yearly interest on loans and the most you can owe at once. Demand, happiness,
# growth, build prices and taxes are the same at every level.
const DIFFICULTIES := [
	{"name": "Easy", "about": "Plenty of money and cheap loans: build freely",
		"money": 100000, "upkeep": 0.8, "loan_rate": 0.04, "loan_limit": 100000},
	{"name": "Normal", "about": "A good start and fair loans: spend it wisely",
		"money": 50000, "upkeep": 1.0, "loan_rate": 0.06, "loan_limit": 60000},
	{"name": "Hard", "about": "Little money, dear running costs and loans",
		"money": 20000, "upkeep": 1.25, "loan_rate": 0.09, "loan_limit": 30000},
]
# Ready-made cities in the game menu: examples/<id>.json, made by tools/make_examples.sh.
const EXAMPLES := [
	{"id": "village", "name": "Village", "about": "A small seaside village with room to grow"},
	{"id": "town", "name": "Town", "about": "A busy harbour town with terraces, shops and a works"},
	{"id": "city", "name": "City", "about": "A large, mature city with a skyline, parks and every service"},
]
const DEFAULT_DIFFICULTY := 1     # Normal (also what saves from before difficulty load as)
const LOW_MONEY := 2000           # below this the money shows red and the advisors suggest a loan

# Loans (City panel). One running balance: borrowing adds to it and to your money.
# Each month you pay the interest (balance x yearly rate / 12) plus a fixed slice
# of what you borrowed, so a loan is paid off in about LOAN_MONTHS.
const BORROW_STEPS := [5000, 20000]   # the Borrow buttons
const REPAY_STEP := 5000              # the Repay button (there's also Repay all)
const LOAN_MONTHS := 120              # slice paid back each month = 1/120 of the most owed since the last time it was clear
const LOAN_MIN_PAYMENT := 20          # ...but never less than this much a month
const LOAN_HEAVY_SHARE := 0.25        # advisors warn when loan payments are more than this share of taxes

# Cost to build one tile, in £.
const ROAD_COST := 10
# The three kinds of road (the kind is kept per road tile: sim.road_kind).
# An avenue is wider and faster; a motorway is faster still, but plots can't
# open onto it (it doesn't count as "a road nearby") and it's noisy.
const ROAD_NAMES := ["Road", "Avenue", "Motorway"]
const ROAD_IDS := ["road", "avenue", "motorway"]
const ROAD_COSTS := [10, 40, 120]             # £ a tile
const ROAD_UPKEEPS := [0.5, 1.5, 4.0]         # £ a tile a month
const ROAD_CAPACITIES := [5000.0, 14000.0, 40000.0]   # trips a day before it's full
const ROAD_STEPS := [12, 8, 5]                # time to drive across a tile (drivers take the quickest way)
const MOTORWAY := 2
const MOTORWAY_NOISE := 0.02                  # land value lost beside each motorway tile...
const MOTORWAY_NOISE_RADIUS := 3              # ...fading out over this many tiles...
const MOTORWAY_NOISE_MAX := 0.1               # ...and at most this much in all
const INDUSTRY_COST := 80         # (homes and shops cost depends on density, see below)
const BULLDOZE_COST := 5          # clearing a built tile (empty tiles are free)

# Hills: each metre of height difference to a neighbouring tile
# adds this much to the cost (0.08 = +8% per metre).
const SLOPE_COST_PER_METRE := 0.08
# Steeper than this (metres of rise across one tile) can't be built on.
const MAX_SLOPE_M := 12.0

# --- Time ---
const UNDO_STEPS := 20            # how many builds Undo (Cmd+Z) remembers
const UNDO_MONTHS := 12           # ...for up to a year; undoing gives back what they cost
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
# than the town needs) or the town is very unpopular (happiness below 40%, see
# Happiness). Decline only trims a plot down to its last building; after enough
# months in decline that building is abandoned: empty, boarded up, no tax.
const ABANDON_MONTHS := 36         # months in decline before a building may be abandoned
const ABANDON_WARN_MONTHS := 18    # from here the hover text warns it's run down
const ABANDON_CHANCE := 0.1        # after that, the chance each month that it's abandoned
const DECLINE_RECOVERY := 3        # each good month takes this many off a plot's decline count
const ABANDON_APPEAL := 0.2        # town appeal below this counts as decline (0.2 = 40% happy)
const ABANDON_OVERSUPPLY := 2.0    # demand below minus this many first-stage plots' worth counts as decline
const REFURBISH_CHANCE := 0.1      # chance each month an abandoned building is done up once it's wanted again
const ABANDONED_VALUE_PENALTY := 0.04   # land value an abandoned building takes off its plot (less nearby)
const ABANDONED_RADIUS := 2             # ...out to this many tiles

# --- Demand ---
const WORKER_SHARE := 0.5         # share of residents who work
# Shop and office jobs a town supports per resident (industry employs the rest of the workers).
# (Was 0.2 until Nov 2026: shops then took 40% of workers and, with visitors on
# top, were always wanted while offices sat full. Sam: "always a demand for shops".)
const SHOP_JOBS_PER_PERSON := 0.16
const VISITOR_SHOP_MAX := 0.06      # all visitors' shopping (stations, tourists, the airport) adds less than this share of the population in shop jobs
                                    # (a soft cap: each source still adds something, less and less as they pile up)
# Offices (their own zone): as a town grows, more of the workers who aren't in
# shops want office work rather than industry. The share starts at OFFICE_START_POP
# and reaches OFFICE_SHARE_MAX at OFFICE_FULL_POP; part of it (OFFICE_SCHOOL_SHARE)
# only counts where homes have a school nearby (offices want schooled workers).
# Offices only take workers when they're zoned: with none, industry employs them all.
const OFFICE_START_POP := 500
const OFFICE_FULL_POP := 10000
const OFFICE_SHARE_MAX := 0.55
const OFFICE_SHARE_CAP := 0.8      # with tech workers (who all want office work) on top, at most this share
const OFFICE_SCHOOL_SHARE := 0.5   # this much of the office share depends on school cover
const OFFICE_TAX := 1.25           # an office job pays this much more tax than other jobs
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

# --- Woodland (planted trees; cost in BUILDINGS["woodland"], no upkeep) ---
# Weaker than a park tile for tile, and capped, so a huge cheap forest can't
# stand in for parks: whatever the size of the woods round a tile, it gets at
# most WOODLAND_VALUE_MAX land value and WOODLAND_CLEANING_MAX less pollution.
# (No leisure appeal: parks don't add any per tile either.)
const WOODLAND_VALUE := 0.025         # land value per woodland tile, fading out over...
const WOODLAND_VALUE_RADIUS := 2      # ...this many tiles (a park: 0.07 over 3)
const WOODLAND_VALUE_MAX := 0.05      # the most all the woodland round a tile can add (about one park tile's worth)
const WOODLAND_CLEANING := 0.06       # pollution soaked up per tile, within PARK_CLEANING_SPREAD (a park: 0.1)
const WOODLAND_CLEANING_MAX := 0.25   # the most all the woodland round a tile can soak up (a works makes 0.06-0.18)

# --- Services (in this order: police, fire, school, hospital) ---
const SERVICE_NAMES := ["Police station", "Fire station", "School", "Hospital"]
const SERVICE_WORDS := ["police", "fire", "school", "hospital"]
const SERVICE_COSTS := [1500, 1500, 2000, 4000]    # £ to build
const SERVICE_UPKEEP := [60, 60, 80, 150]           # £ per month at 100% funding
const SERVICE_RADIUS := [16, 14, 12, 20]            # tiles covered at 100% funding (16 = 800 m)
const SERVICE_POWER := 3                            # power each uses, in zone levels
# Small versions (police office, small fire station, clinic; no small school):
# cheap first cover for a village, but they reach about half as far, so a town
# covered only by small ones pays more in the end.
const SMALL_SERVICE_NAMES := ["Police office", "Small fire station", "", "Clinic"]
const SMALL_SERVICE_WORDS := ["police_office", "fire_small", "", "clinic"]
const SMALL_SERVICE_COSTS := [500, 500, 0, 1200]
const SMALL_SERVICE_UPKEEP := [22, 22, 0, 50]
const SMALL_SERVICE_RADIUS := [8, 7, 0, 10]
const SMALL_SERVICE_POWER := 1
const SERVICE_LAND_BONUS := [0.04, 0.03, 0.05, 0.04] # land value added where fully covered
const COVERED := 0.3                                # coverage that counts as "covered"
const MAX_FUNDING := 1.5                            # funding runs from 0% (closed) to 150%
const POLICE_NEEDED_POP := 800     # bigger towns: homes and shops with no police grow at half speed
const SCHOOL_NEEDED_POP := 1200    # bigger towns: homes need a school to grow past terraces
const HOSPITAL_NEEDED_POP := 2500  # bigger towns: homes with no hospital grow at half speed
const FIRE_START_POP := 500        # fires can break out once the town is this big
const FIRE_CHANCE := 0.0005        # chance per built plot per month with no fire cover (industry x2)

# --- Districts: height rules painted over the zones ---
# 0 = normal, 1 = conservation area, 2 = central business district (CBD), 3 = Tech zone.
const DISTRICT_NAMES := ["Normal", "Conservation area", "CBD", "Tech zone"]
# Tech zone: offices and industry inside it pay their own tax rate (the City
# panel). Set below the town's rate, firms come from outside to fill it.
const TECH_ZONE := 3
const TECH_PULL_GAP := 0.06         # a Tech zone tax this far below the town's draws firms to fill the whole zone
const TECH_JOBS_PER_PERSON := 0.25  # ...but at most this many incoming jobs per resident
const TECH_JOBS_BASE := 60          # (plus this many, so a village gets a few start-ups)
const TECH_FAIRNESS_EFFECT := 0.3   # appeal lost when every job is in a Tech zone with the full tax break
# --- Letters (the tech layer): companies write to the mayor (simulation.gd, Letters) ---
const LETTER_MONTHS := 6            # a letter not answered in this many months lapses: the company goes elsewhere
const MAX_LETTERS := 3              # at most this many unanswered letters at once
const APPETITE_START := 0.5         # investor appetite, 0-1: how keen companies are on the town
const APPETITE_YES := 0.06          # saying yes raises it this much...
const APPETITE_NO := 0.03           # ...saying no, or letting a letter lapse, lowers it this much
const APPETITE_FOLD := 0.02         # ...and a start-up the town backed folding, this much
const STARTUP_POP := 500            # start-ups write from a town this big,
const STARTUP_CHANCE := 0.2         # at best this chance a month (x investor appetite, Tech zone tax break, town size)
const STARTUP_GRANTS := [1000, 1500, 2000, 2500, 3000]   # what they ask for
const STARTUP_GROW := 0.25          # each year a start-up the town backed may grow a level,
const STARTUP_FOLD := 0.15          # fold (its plot empties),
const STARTUP_ACQUIRED := 0.04      # or be bought by a big firm, paying out the town's stake:
const STARTUP_PAYOUT := 8           # this many times the grant
const TAKEOVER_CHANCE := 0.04       # a month, empty company halls get an offer from a cloud company (x investor appetite)
const TAKEOVER_INVESTMENT := 0.5    # ...which invests this share of a new data centre's investment (the halls are there)
const LETTER_LOG_MAX := 200         # the Records window keeps this many letters (the oldest answered ones go first)
# Data centres: Amazon, Microsoft or Google write from DC_POP people once a Tech
# zone has open land for the smallest; you pick a size, then drag out its site
# in the Tech zone within DC_PLACE_MONTHS. Power and water in the same units as
# the plants (zone levels); jobs come from outside, on top of the town's own.
const DC_POP := 1500
const DC_CHANCE := 0.08             # at best this chance a month (x investor appetite, spare power, the Tech zone's tax)
const DC_PLACE_MONTHS := 6          # months to find a site before the company gives up
const DC_SCALES := [
	{"name": "Small", "tiles": 4, "power": 160, "water": 80, "jobs": 12, "tax": 400, "investment": 5000,
		"break_years": 0, "priority": false},
	{"name": "Standard", "tiles": 12, "power": 480, "water": 240, "jobs": 40, "tax": 1500, "investment": 20000,
		"break_years": 5, "priority": false},
	{"name": "Mega", "tiles": 30, "power": 1200, "water": 600, "jobs": 120, "tax": 4000, "investment": 60000,
		"break_years": 10, "priority": true},
]
# Tesla's Gigafactory (Elon Musk): thousands of factory jobs (from outside: they
# draw people in), heavy power, some smoke. "Done in 6 months" takes 1-3 years.
const GIGA_SCALES := [
	{"name": "Small", "tiles": 9, "power": 500, "water": 150, "jobs": 600, "tax": 2000, "investment": 40000,
		"break_years": 5, "priority": false},
	{"name": "Standard", "tiles": 20, "power": 1200, "water": 350, "jobs": 1500, "tax": 5000, "investment": 120000,
		"break_years": 10, "priority": false},
	{"name": "Mega", "tiles": 42, "power": 3000, "water": 800, "jobs": 4000, "tax": 12000, "investment": 300000,
		"break_years": 15, "priority": true},
]
# Google's campus (Sundar Pichai): thousands of well-paid office jobs (from
# outside: they draw people in), and big tech salaries push house prices up
# (CAMPUS_PRICE_EFFECT: "cost of living" in happiness). Reliable: it opens in
# exactly nine months.
const CAMPUS_SCALES := [
	{"name": "Small", "tiles": 6, "power": 150, "water": 80, "jobs": 800, "tax": 3000, "investment": 30000,
		"break_years": 0, "priority": false},
	{"name": "Standard", "tiles": 15, "power": 400, "water": 200, "jobs": 2500, "tax": 8000, "investment": 100000,
		"break_years": 3, "priority": false},
	{"name": "Mega", "tiles": 36, "power": 900, "water": 450, "jobs": 7000, "tax": 20000, "investment": 250000,
		"break_years": 6, "priority": false},
]
const CAMPUS_PRICE_EFFECT := 1.5    # home prices rise by this x campus jobs per resident (at most COST_MAX_RISE)
const COST_MAX_RISE := 1.0          # (so at most double)
const COST_EFFECT := 0.3            # appeal lost when campus salaries have doubled home prices
# SpaceX's launch site (Elon Musk): on the coast. Brings jobs and tourists (shop
# demand, as a share of the population, like the landmarks); no homes can grow
# within its safety zone (tiles); it launches some months, and now and then a
# rocket blows up (LAUNCH_FAIL): the site stops for LAUNCH_REPAIR_MONTHS.
const LAUNCH_SCALES := [
	{"name": "Small", "tiles": 6, "power": 100, "water": 60, "jobs": 300, "tax": 1500, "investment": 40000,
		"break_years": 0, "priority": false, "tourism": 0.004, "launches": 0.15, "zone": 3},
	{"name": "Standard", "tiles": 12, "power": 250, "water": 150, "jobs": 900, "tax": 4000, "investment": 120000,
		"break_years": 5, "priority": false, "tourism": 0.01, "launches": 0.3, "zone": 4},
	{"name": "Mega", "tiles": 30, "power": 600, "water": 400, "jobs": 2500, "tax": 10000, "investment": 300000,
		"break_years": 10, "priority": false, "tourism": 0.02, "launches": 0.5, "zone": 6},
]
const LAUNCH_FAIL := 0.05           # each launch: the chance the rocket blows up
const LAUNCH_REPAIR_MONTHS := 6
const LAUNCH_NEWS_EVERY := 5        # a news line every this many launches (and every failure)
# OpenAI's AI data centre (Sam Altman): power like a city, few jobs, huge money.
# Each year after it opens Sam asks for AI_POWER_STEP more power (a letter): yes
# and it uses more (and pays AI_TAX_STEP more tax), up to AI_POWER_MAX x; say no
# AI_REFUSALS times (or leave the letter) and OpenAI leaves.
const AI_SCALES := [
	{"name": "Small", "tiles": 16, "power": 1000, "water": 500, "jobs": 60, "tax": 6000, "investment": 100000,
		"break_years": 5, "priority": false},
	{"name": "Standard", "tiles": 36, "power": 2500, "water": 1200, "jobs": 150, "tax": 15000, "investment": 300000,
		"break_years": 10, "priority": true},
	{"name": "Mega", "tiles": 64, "power": 6000, "water": 3000, "jobs": 400, "tax": 40000, "investment": 1000000,
		"break_years": 15, "priority": true},
]
const AI_POWER_STEP := 0.25
const AI_TAX_STEP := 0.15
const AI_POWER_MAX := 3.0
const AI_REFUSALS := 3
const DC_HUM_RADIUS := 4           # homes within this many tiles of a working data centre (or AI one) are worth less:
const DC_HUM_VALUE := 0.15          # its cooling fans hum day and night. Land value off a home right beside one (less further off)
const PROJECT_VALUE_MAX := 0.15     # a company project's land value effect round about, however big it is
# --- Tech workers: residents with tech skills (simulation.gd, Tech workers) ---
# Each month the share moves TECH_SETTLE of the way to its target: schools (x the
# share of residents with one nearby), colleges and university tiles (capped),
# plus tech jobs drawing people in; kept by a happy town (0.6 + 0.4 x happiness).
const TECH_SCHOOLS := 0.05          # share from schools, when every home has one nearby
const TECH_COLLEGES_MAX := 0.09     # colleges together (three's worth)
const TECH_UNIVERSITY_MAX := 0.24   # university tiles together (20 tiles' worth)
const TECH_JOB_PULL := 0.5          # each tech job (company projects, Tech zone offices) draws this many tech workers
const TECH_SHARE_MAX := 0.5
const TECH_SETTLE := 0.08           # a month (graduates take years to come through)
const RESEARCH_MAX := 1.0           # research parks make big companies at most this much keener (+100%)
const STUDENT_HOMES := 0.5          # homes wanted per student
const NEAR_TILES := 3
# Company projects: what each kind of company asks to build in your Tech zone.
#   name           in sentences ("Amazon data centre (small)")
#   pop, chance    they write from this many people, at best this chance a month
#                  (x investor appetite; less without spare power, a Tech zone tax
#                  3 points below the town's, or a motorway if wants_motorway)
#   scales         the sizes on the letter card
#   build_months   [shortest, longest] from placing it to opening
#   wants_schools  (if set) much less keen until this share of residents has a school nearby
#   near_sea       (if set) the site has to touch the coast
#   tech_workers   a quarter as keen until the town has this many tech workers
# Who writes and what they say: companies.gd. The tile each is: simulation.gd PROJECT_TILES.
const PROJECTS := {
	"data_centre": {"name": "data centre", "pop": DC_POP, "chance": DC_CHANCE, "scales": DC_SCALES,
		"build_months": [0, 0], "wants_motorway": false, "tech_workers": 0},
	"gigafactory": {"name": "Gigafactory", "pop": 4000, "chance": 0.05, "scales": GIGA_SCALES,
		"build_months": [12, 36], "wants_motorway": true, "tech_workers": 400},
	"campus": {"name": "campus", "pop": 6000, "chance": 0.05, "scales": CAMPUS_SCALES,
		"build_months": [9, 9], "wants_motorway": false, "wants_schools": 0.6, "tech_workers": 1500},
	"launch_site": {"name": "launch site", "pop": 5000, "chance": 0.04, "scales": LAUNCH_SCALES,
		"build_months": [18, 48], "wants_motorway": false, "near_sea": true, "tech_workers": 600},
	"ai_data_centre": {"name": "AI data centre", "pop": 10000, "chance": 0.03, "scales": AI_SCALES,
		"build_months": [12, 18], "wants_motorway": false, "tech_workers": 1000},
}
const BILLS_EFFECT := 0.4           # appeal lost when data centres take all the power on a grid that's full
const BILLS_FROM := 0.6             # bills start rising once the town uses this share of its power
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
#   no_road                   works without a road (woodland)
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
	"landfill": {"name": "Landfill", "cost": 100, "upkeep": 5, "rubbish": 2000, "area": true,
		"value": -0.06, "radius": 3, "about": "Takes the rubbish of 2,000 residents per tile; nobody wants to live by it"},
	"recycling": {"name": "Recycling centre", "cost": 2500, "upkeep": 70, "rubbish": 6000, "uses_power": 3,
		"unlock": 800, "value": -0.01, "radius": 2, "about": "Takes the rubbish of 6,000 residents, cleanly"},
	"incinerator": {"name": "Incinerator", "cost": 9000, "upkeep": 160, "rubbish": 25000, "uses_power": 4,
		"unlock": 4000, "value": -0.08, "radius": 4,
		"about": "Burns the rubbish of 25,000 residents on one plot, but its chimney smokes"},
	"woodland": {"name": "Woodland", "cost": 20, "area": true, "no_road": true,
		"about": "Plant trees: drag out a forest. Cleans the air a little and raises land value nearby; no upkeep, needs no road"},
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
	# Landmarks: famous buildings, one of each. They raise land value and appeal
	# and bring tourists ("visitors": shop demand, as a share of the population).
	"big_ben": {"name": "Big Ben", "cost": 12000, "upkeep": 40, "uses_power": 2, "unlock": 2000, "only_one": true,
		"landmark": true, "value": 0.08, "radius": 6, "appeal": 0.03, "visitors": 0.004,
		"about": "The great clock tower. Tourists come to see it: more demand for shops, higher land value and appeal"},
	"colosseum": {"name": "Colosseum", "cost": 18000, "upkeep": 50, "uses_power": 2, "unlock": 4000, "only_one": true,
		"landmark": true, "value": 0.08, "radius": 7, "appeal": 0.03, "visitors": 0.005,
		"about": "The ancient amphitheatre. Tourists come to see it: more demand for shops, higher land value and appeal"},
	"great_pyramid": {"name": "Great Pyramid", "cost": 20000, "upkeep": 30, "uses_power": 1, "unlock": 6000, "only_one": true,
		"landmark": true, "value": 0.06, "radius": 7, "appeal": 0.03, "visitors": 0.005,
		"about": "A wonder of the ancient world. Tourists come to see it: more demand for shops, higher land value and appeal"},
	"liberty": {"name": "Statue of Liberty", "cost": 22000, "upkeep": 50, "uses_power": 2, "unlock": 8000, "only_one": true,
		"landmark": true, "near_sea": true, "value": 0.10, "radius": 7, "appeal": 0.04, "visitors": 0.006,
		"about": "Torch held high over the harbour. Tourists come to see it: more demand for shops, higher land value and appeal"},
	"taj_mahal": {"name": "Taj Mahal", "cost": 28000, "upkeep": 70, "uses_power": 2, "unlock": 10000, "only_one": true,
		"landmark": true, "value": 0.12, "radius": 8, "appeal": 0.04, "visitors": 0.006,
		"about": "White marble domes and minarets. Tourists come to see it: more demand for shops, higher land value and appeal"},
	"opera_house": {"name": "Sydney Opera House", "cost": 32000, "upkeep": 110, "uses_power": 5, "unlock": 14000, "only_one": true,
		"landmark": true, "near_sea": true, "value": 0.12, "radius": 8, "appeal": 0.05, "visitors": 0.006,
		"about": "White sails by the water. A night out and a sight to see: shop demand, land value and appeal"},
	"eiffel": {"name": "Eiffel Tower", "cost": 36000, "upkeep": 90, "uses_power": 4, "unlock": 18000, "only_one": true,
		"landmark": true, "value": 0.12, "radius": 9, "appeal": 0.05, "visitors": 0.008,
		"about": "The iron tower, seen from all over town. The biggest draw for tourists: shop demand, land value and appeal"},
	"empire_state": {"name": "Empire State Building", "cost": 45000, "upkeep": 120, "uses_power": 8, "unlock": 25000, "only_one": true,
		"landmark": true, "value": 0.10, "radius": 8, "appeal": 0.04, "visitors": 0.006,
		"about": "The art deco skyscraper, the tallest thing in town. Tourists come to see it: shop demand, land value and appeal"},
	# San Francisco's landmarks (the Build menu's; the eight above stay for old cities).
	"painted_ladies": {"name": "Painted Ladies", "cost": 12000, "upkeep": 40, "uses_power": 2, "unlock": 2000, "only_one": true,
		"landmark": true, "value": 0.08, "radius": 6, "appeal": 0.03, "visitors": 0.004,
		"about": "A row of Victorian houses, each painted its own colour, on the edge of a park. Tourists come to take the photo: more demand for shops, higher land value and appeal"},
	"coit_tower": {"name": "Coit Tower", "cost": 18000, "upkeep": 50, "uses_power": 2, "unlock": 4000, "only_one": true,
		"landmark": true, "value": 0.08, "radius": 7, "appeal": 0.03, "visitors": 0.005,
		"about": "The white column on Telegraph Hill, with murals inside and a view from the top. Tourists come to see it: more demand for shops, higher land value and appeal"},
	"ferry_building": {"name": "Ferry Building", "cost": 24000, "upkeep": 70, "uses_power": 3, "unlock": 8000, "only_one": true,
		"landmark": true, "near_sea": true, "value": 0.10, "radius": 7, "appeal": 0.04, "visitors": 0.006,
		"about": "The clock tower on the waterfront, a food hall inside. Tourists and shoppers come: more demand for shops, higher land value and appeal"},
	"fine_arts": {"name": "Palace of Fine Arts", "cost": 28000, "upkeep": 70, "uses_power": 2, "unlock": 12000, "only_one": true,
		"landmark": true, "value": 0.12, "radius": 8, "appeal": 0.05, "visitors": 0.006,
		"about": "A domed rotunda and colonnade by a lagoon. Tourists and wedding photos: more demand for shops, higher land value and appeal"},
	"transamerica": {"name": "Transamerica Pyramid", "cost": 38000, "upkeep": 100, "uses_power": 6, "unlock": 18000, "only_one": true,
		"landmark": true, "value": 0.12, "radius": 9, "appeal": 0.05, "visitors": 0.008,
		"about": "The white pyramid, seen from all over town. A big draw for tourists: shop demand, land value and appeal"},
	"salesforce_tower": {"name": "Salesforce Tower", "cost": 48000, "upkeep": 130, "uses_power": 8, "unlock": 25000, "only_one": true,
		"landmark": true, "value": 0.10, "radius": 8, "appeal": 0.04, "visitors": 0.007,
		"about": "The tallest tower in town, its crown lit up at night. Tourists come to see it: shop demand, land value and appeal"},
	# A company's data centre (the tech layer): never in the Build menu, only
	# placed for a deal (see DC_SCALES); its power, water, jobs and tax come from the deal.
	"data_centre": {"name": "Data centre", "cost": 0, "uses_power": 1, "area": true, "value": -0.05, "radius": 3,
		"about": "A company's data centre: rows of servers, cooled day and night. It hums: lowers land value nearby"},
	"gigafactory": {"name": "Gigafactory", "cost": 0, "uses_power": 1, "area": true, "value": -0.06, "radius": 4,
		"about": "Tesla's battery and car factory: thousands of jobs, round-the-clock lorries, a little smoke"},
	"tech_campus": {"name": "Tech campus", "cost": 0, "uses_power": 1, "area": true, "value": 0.05, "radius": 4,
		"about": "A big tech campus: glass pavilions round lawns, thousands of well-paid jobs. Pushes house prices up"},
	"launch_site": {"name": "Launch site", "cost": 0, "uses_power": 1, "area": true, "value": -0.03, "radius": 6,
		"about": "SpaceX's rockets: tourists come to watch, but it's loud and nobody may live close by"},
	"ai_data_centre": {"name": "AI data centre", "cost": 0, "uses_power": 1, "area": true, "value": -0.04, "radius": 4,
		"about": "OpenAI's AI data centre: power like a city, a few hundred jobs, and it always wants more"},
	# Education (the tech layer): they turn residents into tech workers (see Tech workers).
	#   tech       share of residents it makes tech workers (a university: per tile)
	#   students   residents' worth of students per tile (they need homes)
	#   research   how much keener big companies are, per tile (a research park)
	#   near       must be built within NEAR_TILES of this building
	"college": {"name": "College", "cost": 6000, "upkeep": 150, "uses_power": 3, "unlock": 1500, "value": 0.04,
		"radius": 5, "tech": 0.03, "about": "Coding and engineering courses: more residents become tech workers"},
	"university": {"name": "University", "cost": 400, "upkeep": 40, "uses_power": 2, "area": true, "unlock": 5000,
		"value": 0.06, "radius": 5, "tech": 0.012, "students": 150,
		"about": "Drag out a campus of colleges and quads: graduates for tech firms, students who need homes, and land value. Costly to run"},
	"research_park": {"name": "Research park", "cost": 300, "upkeep": 20, "uses_power": 2, "area": true, "unlock": 5000,
		"value": 0.04, "radius": 4, "research": 0.06, "near": "university",
		"about": "Labs beside a university (within 3 tiles): big tech companies are keener to come"},
	"airport": {"name": "Airport", "cost": 200, "upkeep": 2, "area": true, "unlock": 5000,
		"about": "Drag out a box at least 16 tiles long (an 800 m runway) and 40 tiles in all, e.g. 16 x 3; it shows green once it's big enough. Leave room beside the runway and a road at one side for the terminal. Flights bring visitors (shops), business (offices) and freight (industry). Noisy: lowers land value round about"},
}
# --- Airport (dragged out like a golf course; the layout is worked out from its shape) ---
# The runway is the longest straight run of airport tiles; the terminal goes on
# the tile nearest a road. It opens once it has the runway, the room and the road.
const AIRPORT_MIN_RUNWAY := 16      # tiles in a straight line (800 m)
const AIRPORT_MIN_TILES := 40       # in all, so there's room for a terminal and apron
const AIRPORT_APRON_ROWS := 5       # the runway likes to be this many tiles from the road side (terminal, stands, taxiway)
const AIRPORT_VISITORS := 0.03      # extra shop demand, as a share of the population
const AIRPORT_OFFICE_BOOST := 0.2   # this much more demand for offices
const AIRPORT_FREIGHT := 120        # extra demand for industry, in jobs
const AIRPORT_NOISE := 0.03         # land value lost per airport tile within AIRPORT_NOISE_RADIUS...
const AIRPORT_NOISE_RADIUS := 4
const AIRPORT_NOISE_MAX := 0.15     # ...up to this much, however big the airport
const AIRPORT_TRIPS := 2.0          # car trips a day per visitor (there and back), from the terminal
const TOURISM_MAX := 0.05         # all the landmarks together bring at most this share of the population as visitors
const AIRPORT_TOURISM := 1.5      # an open airport brings this many times the landmarks' visitors
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
	"incinerator": [0.45, 6],             # a tall chimney: less than coal, more than gas nearby
	"harbour": [0.35, 5],                 # ships' engines
	"airport": [0.012, 4],                # per tile: jet fumes round a working airport
	"gigafactory": [0.02, 4],             # per tile: paint shops and lorries
}
const PARK_CLEANING := 0.1                # each park tile soaks up this much within its spread (golf half)
const PARK_CLEANING_SPREAD := 2
# Bands for the map and hover text: clean · a little · some · polluted · heavy.
const POLLUTION_BANDS := [0.05, 0.15, 0.3, 0.5]
const POLLUTED := 0.3                     # from here a plot counts as "polluted"
const POLLUTION_VALUE_EFFECT := 0.2       # land value lost in full pollution
const POLLUTION_GROWTH_EFFECT := 0.6      # homes in full pollution grow this much slower (0.6 = 60%)
const POLLUTION_APPEAL_EFFECT := 0.15     # appeal lost if every resident lived in polluted air

# --- Traffic (a light model: tiles and totals, no individual cars) ---
# Worked out each month (and after loading or building) from the town itself, so
# nothing is saved. For now it is only shown (Traffic map view, hover text, City
# panel, advisors, the cars on the streets): congestion does not yet affect
# growth, happiness, land value or pollution.
# Trips are journeys a day by car, there and back counted separately. Residents
# drive to work and to the shops; each trip picks a place to go by how big it is
# and how far away (nearer places far more likely), and takes a shortest way
# along the roads. Plots with no road make no trips.
const TRAFFIC_WORK_TRIPS := 2.0       # trips a day per working resident (there and back)
const TRAFFIC_SHOP_TRIPS := 0.6       # trips a day per resident to the shops (0.3 round trips)
const TRAFFIC_WORK_REACH := 30.0      # tiles: a job this far away is half as likely as one next door (1.5 km)
const TRAFFIC_SHOP_REACH := 12.0      # ...and shops (600 m): people shop locally
const TRAFFIC_LORRY_REACH := 40.0     # ...and the harbour's lorries to the works
const TRAFFIC_VISITOR_TRIPS := 2.0    # a railway station's visitors (BUILDINGS "visitors" x population) each drive there and back
const TRAFFIC_HARBOUR_LORRIES := 6.0  # lorry trips a day per port job ("port_jobs") between the harbour and the works
# Public transport takes trips off the roads: the share of a home's trips made by
# bus within reach of a working bus depot (the "bus" radius), and by train near a
# working station (SKYSCRAPER_TRANSIT radius). They add up.
const TRAFFIC_BUS_SHARE := 0.25
const TRAFFIC_RAIL_SHARE := 0.15
# Places of work and shops are grouped into squares this many tiles across (doubled
# until there are at most TRAFFIC_MAX_GROUPS), which keeps the model quick in a big town.
const TRAFFIC_GROUP_TILES := 8
const TRAFFIC_MAX_GROUPS := 16
# (How much a road tile carries before it's full: ROAD_CAPACITIES, by kind of road.)
# Congestion = trips / capacity. Bands for the map and hover text:
# free-flowing · busy (from 0.5) · heavy (0.8) · jammed (1.0 and over).
const TRAFFIC_BANDS := [0.5, 0.8, 1.0]
const TRAFFIC_QUIET := 0.1            # free-flowing roads under this are "quiet" (drawn paler on the map)
const TRAFFIC_JAM_TIP := 0.08         # advisors mention jams once this share of trips is in them...
const TRAFFIC_JAM_WARN := 0.2         # ...and warn from this share

# --- Look (no effect on the simulation) ---
const DAY_SECONDS := 240.0        # real seconds for a full day and night at normal speed
const START_TIME_OF_DAY := 0.38   # 0 = midnight, 0.5 = noon
# The 3D picture is drawn at about this many pixels and scaled up to fill the
# window (the interface is always drawn sharp, at full size). A maximized window
# on a Retina Mac is about 4.6 million pixels: drawing all of them more than
# halved the frame rate on a base M1. 1600 x 1000 is what the screenshots use.
# 0 = always draw every pixel.
const RENDER_PIXELS := 1600 * 1000
const INTERFACE_SCALE := 0.0      # interface size: 0 = follow the screen (2 on Retina), or e.g. 1.5

# --- People and traffic (looks only; T turns them off and on) ---
const TRAFFIC_ON := true          # cars and people on the streets when the game starts
const MAX_CARS := 300             # most cars and buses drawn at once (only round the camera)
const MAX_PEOPLE := 400           # most people walking at once (only round the camera)
const TRIPS_PER_CAR := 1500.0     # cars drawn on a street: one per this many trips a day (the traffic model)
const PEOPLE_PER_WALKER := 40     # residents and jobs beside a street per person walking (shops count 3x, homes 0.25x)
const CARS_PER_STREET := 3.0      # the busiest streets: at most this many cars per road tile
const QUEUE_SPEED := 2.5          # metres per second on jammed roads (cars queue), ...
const HEAVY_SPEED := 6.0          # ...and on heavy ones
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
const OFFICE_BONUS := 0.005       # per level of offices within 3 tiles (smart, but less of a draw than shops)
const INDUSTRY_PENALTY := 0.015   # per level of industry within 4 tiles (its smoke is in Pollution above)
const BASE_HOME_PRICE := 160000   # £ for a home on average land with no shortage
const SHORTAGE_PRICE_EFFECT := 0.8 # a severe shortage pushes prices up by this much

# --- Zoning density ---
# A plot's building "stage" = its level + the density's head start:
#   stage 1 villas · 2 two rows of villas / terraces · 3 tenements
#   stage 4 mansion flats · 5 modern flats · 6 towers   (shops: parades up to big stores and hotels;
#   offices: small offices up to an office tower)
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
const OFFICE_JOBS_AT_STAGE := [0, 10, 20, 32, 55, 85, 130, 240, 400]
const INDUSTRY_JOBS_AT_STAGE := [0, 15, 30, 45]
# Zoning cost per tile for low / medium / high density.
const HOMES_COSTS := [40, 60, 100]
const SHOPS_COSTS := [60, 80, 120]
const OFFICES_COSTS := [70, 90, 140]
