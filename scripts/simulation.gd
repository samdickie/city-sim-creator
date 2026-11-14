extends RefCounted
## The city's rules: road access, growth, demand, land value, pollution, density,
## prices, taxes and upkeep.
## Knows nothing about drawing, so the visuals can change (2D to 3D)
## without touching any of this.

const Settings = preload("res://scripts/settings.gd")

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE, PARK,
	POLICE, FIRE, SCHOOL, HOSPITAL,
	WIND, SOLAR, GAS, NUCLEAR, WATER_PUMP, WATER_TOWER, LANDFILL, RECYCLING,
	GOLF, LIBRARY, MUSEUM, STADIUM, MARINA, TOWN_HALL, BUS_DEPOT, STATION, HARBOUR,
	WOODLAND, OFFICES, POLICE_OFFICE, FIRE_SMALL, CLINIC, AIRPORT,
	BIG_BEN, COLOSSEUM, GREAT_PYRAMID, LIBERTY, TAJ_MAHAL, OPERA_HOUSE, EIFFEL, EMPIRE_STATE }
# Which entry in Settings.BUILDINGS describes each of the other buildings.
const BUILDING_KEYS := {
	Tile.POWER_PLANT: "coal", Tile.GAS: "gas", Tile.NUCLEAR: "nuclear", Tile.WIND: "wind",
	Tile.SOLAR: "solar", Tile.WATER_PUMP: "water_pump", Tile.WATER_TOWER: "water_tower",
	Tile.LANDFILL: "landfill", Tile.RECYCLING: "recycling", Tile.GOLF: "golf",
	Tile.LIBRARY: "library", Tile.MUSEUM: "museum", Tile.STADIUM: "stadium", Tile.MARINA: "marina",
	Tile.TOWN_HALL: "town_hall", Tile.BUS_DEPOT: "bus_depot", Tile.STATION: "station",
	Tile.HARBOUR: "harbour", Tile.WOODLAND: "woodland", Tile.AIRPORT: "airport",
	Tile.BIG_BEN: "big_ben", Tile.COLOSSEUM: "colosseum", Tile.GREAT_PYRAMID: "great_pyramid", Tile.LIBERTY: "liberty",
	Tile.TAJ_MAHAL: "taj_mahal", Tile.OPERA_HOUSE: "opera_house", Tile.EIFFEL: "eiffel", Tile.EMPIRE_STATE: "empire_state",
}
const LAST_TILE := Tile.EMPIRE_STATE   # (new tiles go on the end, so saved tile numbers never change)
# What residents complain about, by happiness part: [the complaint, how to fix it].
# Kept in one place so the HUD, zone hover text and advisors all say the same thing.
const COMPLAINTS := {
	"taxes": ["taxes too high for the services", "lower the tax rate, or build services near homes"],
	"services": ["not enough police, fire, schools or hospitals", "build services near homes, or fund them more"],
	"rubbish": ["rubbish piling up", "build a landfill or recycling centre"],
	"jobs": ["not enough jobs", "zone more shops, offices or industry"],
	"housing": ["homes too dear (housing shortage)", "zone more homes, or zone them denser"],
	"power": ["homes without power", "build another power plant, or link the homes to one"],
	"water": ["homes without water", "build a water pump or tower"],
	"pollution": ["polluted air near homes", "keep homes away from industry and coal, or plant parks or woodland between"],
}
# The parts businesses weigh too. The rest (jobs, housing, power and water at
# home) only residents feel, so they don't put shops and industry off.
const BUSINESS_PARTS: Array[String] = ["taxes", "services", "leisure", "rubbish"]
enum Service { POLICE, FIRE, SCHOOL, HOSPITAL }   # same order as the service tiles
# The small service buildings, and the service each one gives.
const SMALL_SERVICES := {Tile.POLICE_OFFICE: Service.POLICE, Tile.FIRE_SMALL: Service.FIRE, Tile.CLINIC: Service.HOSPITAL}
enum Growth { NONE, GROWING, WAITING, BLOCKED, FULL, ABANDONED }   # for the growth map

# --- The city ---
var w := 0
var h := 0
var water := PackedByteArray()
var tiles := PackedByteArray()        # Tile enum per map tile
var levels := PackedByteArray()       # zones: 0 = empty plot, then 1 up to the density's maximum
var density := PackedByteArray()      # zones: 0 = low, 1 = medium, 2 = high
var district := PackedByteArray()     # any tile: 0 = normal, 1 = conservation area, 2 = CBD
var decline := PackedByteArray()      # zones: months in decline (see Settings.ABANDON_MONTHS)
var abandoned := PackedByteArray()    # zones: 1 = the building stands empty (no people, jobs or tax)
var money := 0
var month := 0                        # months since the city was founded
var tax_rate := Settings.DEFAULT_TAX_RATE
var difficulty := Settings.DEFAULT_DIFFICULTY   # index into Settings.DIFFICULTIES; set when the city starts
var debt := 0                         # what the town owes on loans (one running balance)
var debt_peak := 0                    # the most owed since the balance was last clear (sets the monthly slice)

# --- Worked out from the city ---
var population := 0
var shop_jobs := 0
var industry_jobs := 0
var office_jobs := 0
var road_tiles := 0
var plants := 0                       # anything that makes power
var park_tiles := 0
var counts := {}                      # tile type -> how many the town has
var power_supply := 0                 # zone levels the plants can power
var water_supply := 0                 # zone levels the pumps and towers can supply
var water_used := 0
var rubbish_made := 0                 # in residents' worth
var rubbish_capacity := 0
var tourism := 0.0                    # visitors the working landmarks bring, as a share of the population
var leisure_appeal := 0.0             # extra appeal from leisure buildings and landmarks
# How residents feel, 0 (furious) to 1 (delighted): the single summary of taxes,
# services, leisure, rubbish, jobs, housing, power and water. It sets how many
# people want to move in (see appeal()). Worked out again every month and
# whenever taxes change, from the town itself, so it needs no saving.
var happiness := 2.0 / 3.0
# What happiness is made of, in appeal points: part name -> amount (below 0 = a
# complaint). Names: taxes, services, leisure, rubbish, jobs, housing, power, water, pollution.
var happiness_parts := {}
var power_used := 0                   # zone levels currently built
# How many more residents / shop jobs / industry jobs the town wants.
# Negative means too many already.
var demand := {Tile.HOMES: 0.0, Tile.SHOPS: 0.0, Tile.INDUSTRY: 0.0, Tile.OFFICES: 0.0}
var last_income := 0
var last_upkeep := 0
var last_loan := 0                    # loan payment last month (interest and repayment together)
var last_interest := 0                # ...of which interest
var grew := PackedInt32Array()        # plots that grew last month
var shrank := PackedInt32Array()      # plots that shrank last month (and any abandoned)
var abandoned_now := PackedInt32Array() # plots abandoned last month (also in shrank)
var abandoned_count := 0              # abandoned buildings in town
var run_down_count := 0               # built plots in decline long enough to be at risk
var land_value := PackedFloat32Array() # 0 (worst) to 1 (best) for every tile
# How short of space each zone type is: 0 = plenty of low-rise room left,
# 1 = demand well beyond what low-rise plots can take (so plots build upwards).
var shortage := {Tile.HOMES: 0.0, Tile.SHOPS: 0.0, Tile.INDUSTRY: 0.0, Tile.OFFICES: 0.0}
var average_home_price := 0
var _sea_near := PackedFloat32Array() # 1 by the sea, fading to 0 inland
var pollution := PackedFloat32Array() # 0 (clean air) to 1 (heavy) for every tile; worked out with land value
var polluted_share := 0.0             # 0-1: share of residents living in polluted air
var _value_dirty := true
var _wood_effect := PackedFloat32Array() # scratch: woodland's land value or cleaning round each tile (capped)
var funding: Array[float] = [1.0, 1.0, 1.0, 1.0]   # per service: 0 = closed, 1 = 100%
var services := [0, 0, 0, 0]          # how many of each service the town has (big and small together)
var small_services := [0, 0, 0, 0]    # ...of which small ones
var coverage := PackedFloat32Array()  # per service, per tile: 0 (none) to 1 (fully covered)
var burned := PackedInt32Array()      # plots that burned down last month
var service_score := 0.0              # 0-1: how well services cover the town's homes, on average
var _coverage_dirty := true
# Airports: what each airport tile is (AirportRole, +8 if the runway runs north-south,
# +16 at a runway's two ends and on the taxiway beside the stands), which airport it belongs to, and each airport's
# problem ("" = open). Worked out in recount() by _update_airports().
enum AirportRole { NONE, RUNWAY, TAXIWAY, APRON, GRASS, TERMINAL, TOWER, HANGAR }
var airport_role := PackedByteArray()
var _airport_group := PackedInt32Array()
var _airport_problems: Array[String] = []
var _airport_terminals := PackedInt32Array()   # each open airport's terminal tile
var airports_open := 0
var layout_version := 0               # goes up whenever a tile changes type (roads, zones...)

var _road_dist := PackedByteArray()   # tiles to the nearest road (255 = far)
var _roads_dirty := true
var powered := PackedByteArray()      # 1 = this tile has electricity
var _net_id := PackedInt32Array()     # which power network a tile is on (-1 = none)
var _net_spare: Array[int] = []       # spare power on each network
var _power_dirty := true
var watered := PackedByteArray()      # 1 = this tile has water
var _wnet_id := PackedInt32Array()    # which water network a tile is on (-1 = none)
var _wnet_spare: Array[int] = []
var _water_dirty := true
var _bus_cover := PackedByteArray()   # 1 = within reach of a working bus depot
var _transit := PackedByteArray()     # 1 = near a working station or bus depot (for skyscrapers)
var _rng := RandomNumberGenerator.new()

# --- Traffic (see "traffic" below): worked out from the town, never saved ---
var traffic := PackedFloat32Array()   # per map tile: car trips a day along it (0 off the roads)
var traffic_trips := 0                # car trips a day in the whole town
var transit_trips := 0                # trips a day made by bus or train instead
var jammed_share := 0.0               # 0-1: share of the town's driving done on jammed roads
var traffic_ms := 0.0                 # how long the last traffic update took (for the dev tools)
var _traffic_dirty := true
var _capacity_scale := 1.0            # (dev tools only: the play test shrinks the roads to show jams change nothing else)
var _graph_version := -1              # layout_version the road graph below was built for
var _road_tile := PackedInt32Array()  # road node -> map tile
var _road_node := PackedInt32Array()  # map tile -> road node (-1 = not a road)
var _road_next := PackedInt32Array()  # 4 per road node: the next road node each way (-1 = none)
var _access := PackedInt32Array()     # map tile -> the road node its trips start and end at (-1 = none)


func setup(width: int, height: int, water_map: PackedByteArray) -> void:
	w = width
	h = height
	water = water_map
	tiles.resize(w * h)
	levels.resize(w * h)
	density.resize(w * h)
	district.resize(w * h)
	decline.resize(w * h)
	abandoned.resize(w * h)
	_transit.resize(w * h)
	powered.resize(w * h)
	_net_id.resize(w * h)
	watered.resize(w * h)
	_wnet_id.resize(w * h)
	_bus_cover.resize(w * h)
	land_value.resize(w * h)
	pollution.resize(w * h)
	coverage.resize(w * h * 4)
	_measure_sea()
	reset()


func reset(level: int = Settings.DEFAULT_DIFFICULTY) -> void:
	# A blank map at this difficulty (see Settings.DIFFICULTIES).
	tiles.fill(Tile.EMPTY)
	levels.fill(0)
	density.fill(1)
	district.fill(0)
	decline.fill(0)
	abandoned.fill(0)
	difficulty = clampi(level, 0, Settings.DIFFICULTIES.size() - 1)
	money = start_money(difficulty)
	debt = 0
	debt_peak = 0
	month = 0
	tax_rate = Settings.DEFAULT_TAX_RATE
	last_income = 0
	last_upkeep = 0
	last_loan = 0
	last_interest = 0
	grew.clear()
	shrank.clear()
	abandoned_now.clear()
	burned.clear()
	funding = [1.0, 1.0, 1.0, 1.0]
	_roads_dirty = true
	_power_dirty = true
	_value_dirty = true
	_coverage_dirty = true
	_traffic_dirty = true
	layout_version += 1
	shortage = {Tile.HOMES: 0.0, Tile.SHOPS: 0.0, Tile.INDUSTRY: 0.0, Tile.OFFICES: 0.0}
	_rng.randomize()
	recount()


# ------------------------------------------------------------- player actions

func set_tile(i: int, t: int, new_density: int = 1) -> void:
	if tiles[i] == t:
		if is_zone(t) and density[i] != new_density:
			# Re-zoning to another density keeps what's there, trimmed to the new maximum.
			density[i] = new_density
			levels[i] = mini(levels[i], max_level(i))
			_power_dirty = true
			_value_dirty = true
			_coverage_dirty = true
			_traffic_dirty = true
		return
	tiles[i] = t
	levels[i] = 0                     # a new zone starts as an empty plot
	decline[i] = 0
	abandoned[i] = 0
	density[i] = new_density if is_zone(t) else 1
	_roads_dirty = true
	_power_dirty = true
	_water_dirty = true
	_value_dirty = true
	_coverage_dirty = true
	_traffic_dirty = true
	layout_version += 1


func set_district(i: int, d: int) -> void:
	# Paint a district; anything above its new height limit is trimmed back.
	if district[i] == d:
		return
	district[i] = d
	if is_zone(tiles[i]):
		levels[i] = mini(levels[i], max_level(i))
	_power_dirty = true
	_value_dirty = true
	_coverage_dirty = true
	layout_version += 1


func district_name(i: int) -> String:
	var n: String = Settings.DISTRICT_NAMES[district[i]]
	return n


func has_road_access(i: int) -> bool:
	# A road within ROAD_REACH tiles, or one tile further where buses run.
	_update_road_distance()
	_update_coverage()
	return _connected(i)


func _connected(i: int) -> bool:
	# (Road distances and bus cover must be up to date.)
	return _road_dist[i] <= Settings.ROAD_REACH \
		or (_road_dist[i] == Settings.ROAD_REACH + 1 and _bus_cover[i] == 1)


func near_road(i: int) -> bool:
	# Plain road access, without buses (what buildings themselves need).
	_update_road_distance()
	return _road_dist[i] <= Settings.ROAD_REACH


func road_reach_map() -> PackedByteArray:
	# Tiles to the nearest road for every map tile (255 = far away).
	_update_road_distance()
	return _road_dist


func zone_status(i: int) -> String:
	# A plain-English reason for what a zone plot is doing.
	var check := _zone_check(i)
	var text: String = check[1]
	if abandoned[i] == 0 and levels[i] > 0 and decline[i] >= Settings.ABANDON_WARN_MONTHS:
		var why := _decline_reason(i, demand_for(tiles[i]))
		if why != "":
			text += "   ·   run down (%s), may be abandoned soon" % why
	return text


func is_abandoned(i: int) -> bool:
	return abandoned[i] == 1


func abandoned_reason(i: int) -> String:
	# Why an abandoned building is still empty, in plain English.
	_update_road_distance()
	_update_coverage()
	var t: int = tiles[i]
	var why := _decline_reason(i, demand_for(t))
	if why != "":
		return why
	if demand_for(t) < units_at_stage(t, stage(i)) * 0.5:
		match t:
			Tile.HOMES:
				return "waiting for more people to want to move in"
			Tile.SHOPS:
				return "waiting for more customers (the town needs more residents)"
			Tile.INDUSTRY:
				return "waiting for more workers (the town needs more residents)"
			Tile.OFFICES:
				return "waiting for more office workers (a bigger town with schools near homes)"
	return "it should be done up soon"


func growth_state(i: int) -> int:
	# For the growth map: GROWING, WAITING (demand, space or land value),
	# BLOCKED (needs a road or power), FULL, ABANDONED, or NONE for anything but zones.
	if not is_zone(tiles[i]):
		return Growth.NONE
	var check := _zone_check(i)
	var state: int = check[0]
	return state


func _zone_check(i: int) -> Array:
	# [Growth state, reason in plain English] for a zone plot.
	var t: int = tiles[i]
	if abandoned[i] == 1:
		return [Growth.ABANDONED, "abandoned, " + abandoned_reason(i)]
	if not has_road_access(i):
		return [Growth.BLOCKED, "won't grow, needs a road within %d tiles" % Settings.ROAD_REACH]
	_update_power()
	if powered[i] == 0:
		if _net_id[i] < 0:
			return [Growth.BLOCKED, "no power, link it to a power plant (roads, zones and power lines carry power)"]
		return [Growth.BLOCKED, "no power, the power plant is full, build another"]
	var lv: int = levels[i]
	if lv < max_level(i) and _net_spare[_net_id[i]] <= 0:
		return [Growth.BLOCKED, "waiting, the power plant is full, build another"]
	if lv < max_level(i) and _needs_water(i, stage_at(i, lv + 1)):
		_update_water()
		if _wnet_id[i] < 0:
			return [Growth.BLOCKED, "needs water to grow any bigger: build a water pump or tower (water travels through roads and buildings)"]
		return [Growth.BLOCKED, "needs more water to grow: build another water pump or tower"]
	if lv >= max_level(i):
		if district[i] == 1 and t != Tile.INDUSTRY:
			return [Growth.FULL, "fully built: height capped in the conservation area"]
		if district[i] == 2 and density[i] < 2 and t != Tile.INDUSTRY:
			return [Growth.FULL, "fully built for %s density (zone it high to build skyscrapers in the CBD)" % density_name(i)]
		if t != Tile.INDUSTRY and density[i] < 2:
			return [Growth.FULL, "fully built for %s density (zone it higher to let it grow more)" % density_name(i)]
		return [Growth.FULL, "fully built up"]
	var next_stage: int = stage_at(i, lv + 1)
	if demand_for(t) < step_size(i) * 0.5:
		# Too unhappy (or, for businesses, too put off) to come: say what's wrong.
		var homes: bool = t == Tile.HOMES
		if (appeal() if homes else business_appeal()) < 0.5:
			var who := "people" if homes else "businesses"
			var keys := complaint_keys(1, not homes)
			if keys.is_empty():
				return [Growth.WAITING, "waiting, %s won't move in" % who]
			return [Growth.WAITING, "waiting, %s won't move in: %s (%s)" \
				% [who, complaint_text(keys[0]), complaint_fix(keys[0])]]
		match t:
			Tile.HOMES:
				return [Growth.WAITING, "waiting, the town needs more jobs first"]
			Tile.SHOPS:
				return [Growth.WAITING, "waiting, the town needs more residents first"]
			Tile.INDUSTRY:
				return [Growth.WAITING, "waiting, the town needs more workers first"]
			Tile.OFFICES:
				return [Growth.WAITING, _office_wait()]
	if next_stage >= 7:
		var sky_why := _skyscraper_problem(i)
		if sky_why != "":
			return [Growth.WAITING, sky_why]
	if _needs_school(i, next_stage):
		return [Growth.WAITING, "waiting for a school nearby (families won't move into bigger homes without one)"]
	if next_stage > Settings.FREE_STAGE:
		_update_land_value()
		var needed: float = Settings.TALL_VALUE_NEEDED[next_stage]
		if land_value[i] < needed:
			return [Growth.WAITING, "land value too low to build taller (the sea, parks and shops nearby raise it; industry and pollution lower it)"]
		if density[i] < 2 and shortage_for(t) <= 0.0:
			return [Growth.WAITING, "will build taller when the town runs short of space"]
	var missing := _missing_services(i)
	var smoky := t == Tile.HOMES and pollution_at(i) >= Settings.POLLUTED
	if missing != "":
		return [Growth.GROWING, "growing slowly, no %s nearby%s" % [missing,
			", and the air is polluted" if smoky else ""]]
	if smoky:
		return [Growth.GROWING, "growing slowly, the air here is polluted"]
	return [Growth.GROWING, "growing"]


func demand_for(t: int) -> float:
	var d: float = demand[t]
	return d


func shortage_for(t: int) -> float:
	var v: float = shortage[t]
	return v


func housing_shortage() -> float:
	return shortage_for(Tile.HOMES)


func density_name(i: int) -> String:
	var n: String = Settings.DENSITY_NAMES[density[i]]
	return n


# ------------------------------------------------------------- stages and sizes

func max_level(i: int) -> int:
	# The density sets how far a plot can grow; districts raise or cap it.
	if tiles[i] == Tile.INDUSTRY:
		return mini(3, Settings.CONSERVATION_MAX_STAGE) if district[i] == 1 else 3
	var m: int = Settings.DENSITY_MAX_LEVEL[density[i]]
	var start: int = Settings.DENSITY_START[density[i]]
	if district[i] == 2 and density[i] == 2:
		m += Settings.CBD_EXTRA_LEVELS
	elif district[i] == 1:
		m = mini(m, Settings.CONSERVATION_MAX_STAGE - start)
	return maxi(m, 1)


func stage_at(i: int, level: int) -> int:
	# What kind of building a plot has at a given level (see settings.gd).
	if level <= 0:
		return 0
	if tiles[i] == Tile.INDUSTRY:
		return level
	var start: int = Settings.DENSITY_START[density[i]]
	return level + start


func stage(i: int) -> int:
	return stage_at(i, levels[i])


func units_at_stage(t: int, s: int) -> int:
	# Residents (homes) or jobs (shops, industry) a plot holds at a stage.
	var n: int = 0
	match t:
		Tile.HOMES:
			n = Settings.HOMES_AT_STAGE[s]
		Tile.SHOPS:
			n = Settings.SHOP_JOBS_AT_STAGE[s]
		Tile.INDUSTRY:
			n = Settings.INDUSTRY_JOBS_AT_STAGE[s]
		Tile.OFFICES:
			n = Settings.OFFICE_JOBS_AT_STAGE[s]
	return n


func units(i: int) -> int:
	# (An abandoned building houses nobody and has no jobs.)
	if abandoned[i] == 1:
		return 0
	return units_at_stage(tiles[i], stage(i))


func step_size(i: int) -> int:
	# How many more residents/jobs the next level adds (or the last one added).
	var lv: int = levels[i]
	if lv < max_level(i):
		return units_at_stage(tiles[i], stage_at(i, lv + 1)) - units(i)
	return units(i) - units_at_stage(tiles[i], stage_at(i, lv - 1))


func change_tax(step: float) -> void:
	tax_rate = clampf(snappedf(tax_rate + step, 0.01), 0.0, Settings.MAX_TAX_RATE)
	_update_demand()


# ------------------------------------------------------------ monthly update

func tick() -> void:
	month += 1
	_update_road_distance()
	_power_dirty = true
	_value_dirty = true               # land value and pollution are worked out afresh each month
	_traffic_dirty = true             # ...and traffic, when it's next asked for (it changes nothing else)
	recount()
	_update_land_value()
	_grow()
	_fires()
	if not grew.is_empty() or not shrank.is_empty():
		# Power is shared out again, which can switch services on or off, and
		# taller shops and industry change the land around them.
		_power_dirty = true
		_coverage_dirty = true
		_value_dirty = true
	recount()
	_collect_taxes()


func _grow() -> void:
	var zones: Array[int] = []
	for i in w * h:
		if is_zone(tiles[i]):
			zones.append(i)
	zones.shuffle()                   # no corner of the map gets first pick

	grew.clear()
	shrank.clear()
	abandoned_now.clear()
	_update_road_distance()
	_update_coverage()
	_update_water()
	var wanted: Dictionary = demand.duplicate()

	# Count the months each built plot has been in decline (good months count it back down).
	for i in zones:
		if levels[i] == 0 or abandoned[i] == 1:
			decline[i] = 0
		elif _decline_reason(i, demand_for(tiles[i])) != "":
			decline[i] = mini(decline[i] + 1, 255)
		else:
			decline[i] = maxi(decline[i] - Settings.DECLINE_RECOVERY, 0)

	# How much more the plots that can grow freely (road + power) could still take.
	var room: Dictionary = {Tile.HOMES: 0.0, Tile.SHOPS: 0.0, Tile.INDUSTRY: 0.0, Tile.OFFICES: 0.0}
	for i in zones:
		if not _connected(i) or powered[i] == 0 or abandoned[i] == 1:
			continue
		var t: int = tiles[i]
		var free_top: int = mini(stage_at(i, max_level(i)), Settings.FREE_STAGE)
		var extra: int = units_at_stage(t, free_top) - units(i)
		if extra > 0:
			room[t] = float(room[t]) + extra
	# Short of space when demand is more than that room can take.
	for t: int in [Tile.HOMES, Tile.SHOPS, Tile.INDUSTRY, Tile.OFFICES]:
		var unit: float = float(_capacity_per_level(t))
		var gap: float = float(wanted[t]) - float(room[t])
		shortage[t] = clampf(gap / (unit * 20.0), 0.0, 1.0)

	# Pass 1: building taller, most valuable plots first (developers go where land
	# is worth most). High-density plots rise whenever there's demand and the land
	# is valuable enough; medium-density plots only take the step up to mansion
	# flats when the town is short of space.
	var tall_candidates: Array[int] = []
	for i in zones:
		if levels[i] < max_level(i) and stage_at(i, levels[i] + 1) > Settings.FREE_STAGE \
				and _connected(i) and powered[i] == 1 and abandoned[i] == 0:
			tall_candidates.append(i)
	tall_candidates.sort_custom(func(a: int, b: int) -> bool: return land_value[a] > land_value[b])
	var grown := {}
	for i in tall_candidates:
		var t: int = tiles[i]
		var lv: int = levels[i]
		var step: int = step_size(i)
		var want: float = wanted[t]
		var short: float = shortage[t]
		var spare: int = _net_spare[_net_id[i]] if _net_id[i] >= 0 else 0
		var needed: float = Settings.TALL_VALUE_NEEDED[stage_at(i, lv + 1)]
		var next: int = stage_at(i, lv + 1)
		var allowed: bool = (density[i] == 2 or short > 0.0) and not _needs_school(i, next) \
			and not _needs_water(i, next) and (next < 7 or _skyscraper_problem(i) == "")
		var boost: float = Settings.CBD_TALL_BOOST if district[i] == 2 else 1.0
		if allowed and spare > 0 and want >= step * 0.5 and land_value[i] >= needed \
				and _rng.randf() < Settings.TALL_GROWTH_CHANCE * (0.5 + short) * _service_factor(i) * boost:
			levels[i] = lv + 1
			wanted[t] = want - step
			_net_spare[_net_id[i]] -= 1
			grew.append(i)
			grown[i] = true

	# Pass 2: free growth (up to tenements) and decline, in random order.
	for i in zones:
		if grown.has(i):
			continue
		var t: int = tiles[i]
		var lv: int = levels[i]
		if abandoned[i] == 1:
			# Done up again once nothing's wrong and the town wants what it holds.
			var need: int = units_at_stage(t, stage(i))
			var wanting: float = wanted[t]
			if _decline_reason(i, wanting) == "" and wanting >= need * 0.5 \
					and _rng.randf() < Settings.REFURBISH_CHANCE:
				abandoned[i] = 0
				wanted[t] = wanting - need
				_net_spare[_net_id[i]] -= stage(i)
				grew.append(i)
			continue
		if lv > 0 and decline[i] >= Settings.ABANDON_MONTHS and _rng.randf() < Settings.ABANDON_CHANCE \
				and _decline_reason(i, float(wanted[t])) != "":
			# Too long in decline: everyone leaves and the building is boarded up.
			wanted[t] = float(wanted[t]) + units(i)
			abandoned[i] = 1
			decline[i] = 0
			shrank.append(i)
			abandoned_now.append(i)
			continue
		var connected: bool = _connected(i)
		var has_power: bool = powered[i] == 1
		var spare: int = _net_spare[_net_id[i]] if _net_id[i] >= 0 else 0
		var want: float = wanted[t]
		var can_rise: bool = lv < max_level(i)
		var next_stage: int = stage_at(i, lv + 1) if can_rise else 0
		var step: int = step_size(i)
		var down_step: int = units(i) - units_at_stage(t, stage_at(i, lv - 1)) if lv > 0 else 0
		if connected and has_power and spare > 0 and can_rise and next_stage <= Settings.FREE_STAGE \
				and want >= step * 0.5 and not _needs_school(i, next_stage) and not _needs_water(i, next_stage) \
				and _rng.randf() < Settings.GROWTH_CHANCE * _service_factor(i):
			levels[i] = lv + 1
			wanted[t] = want - step
			_net_spare[_net_id[i]] -= 1
			grew.append(i)
		elif lv > 1 and (not connected or not has_power or want < -down_step * 2.0) \
				and _rng.randf() < Settings.DECLINE_CHANCE * (1.6 - local_service(i)):
			# (Decline stops at the last building: that one is abandoned instead.)
			levels[i] = lv - 1
			wanted[t] = want + down_step
			shrank.append(i)


func _decline_reason(i: int, want: float) -> String:
	# Why a built plot is going downhill, in plain English ("" = it isn't).
	# want = how much more of this zone the town wants. An abandoned building uses
	# no power or water, so for one of those, check there's enough to reopen it.
	# (Road distances and bus cover must be up to date.)
	var t: int = tiles[i]
	if not _connected(i):
		return "no road nearby"
	_update_water()
	var s: int = stage(i)
	if abandoned[i] == 1:
		if _net_id[i] < 0 or _net_spare[_net_id[i]] < s:
			return "no power"
		if s >= 2 and (_wnet_id[i] < 0 or _wnet_spare[_wnet_id[i]] < s):
			return "no water"
	else:
		if powered[i] == 0:
			return "no power"
		if s >= 2 and watered[i] == 0:
			return "no water"
	if appeal() < Settings.ABANDON_APPEAL:
		# Appeal is happiness now, so name whatever residents mind most.
		var keys := complaint_keys(1)
		if keys.is_empty():
			return "the town is unpopular"
		return "the town is unpopular: %s" % complaint_text(keys[0])
	if want < -_capacity_per_level(t) * Settings.ABANDON_OVERSUPPLY:
		match t:
			Tile.HOMES:
				return "more homes than people want (the town needs more jobs)"
			Tile.SHOPS:
				return "too few customers for all the shops"
			Tile.INDUSTRY:
				return "too few workers for all the industry"
			Tile.OFFICES:
				return "too few office workers for all the offices"
	return ""


func _collect_taxes() -> void:
	# Valuable land pays more: from 0.6x on the worst land to 1.4x on the best.
	_update_land_value()
	var taxable := 0.0
	for i in w * h:
		if is_zone(tiles[i]) and levels[i] > 0:
			taxable += units(i) * (0.6 + 0.8 * land_value[i]) * (Settings.OFFICE_TAX if tiles[i] == Tile.OFFICES else 1.0)
	last_income = roundi(taxable * tax_rate * Settings.TAX_BASE)
	# Every running cost is scaled by the difficulty (x1 on Normal).
	last_upkeep = roundi((road_tiles * Settings.ROAD_UPKEEP + park_tiles * Settings.PARK_UPKEEP
		+ service_upkeep() + building_upkeep()) * upkeep_scale())
	money += last_income - last_upkeep
	_pay_loan()


# ------------------------------------------------------- difficulty and loans

static func level_info(level: int) -> Dictionary:
	var info: Dictionary = Settings.DIFFICULTIES[clampi(level, 0, Settings.DIFFICULTIES.size() - 1)]
	return info


static func start_money(level: int) -> int:
	var amount: int = level_info(level)["money"]
	return amount


func difficulty_name() -> String:
	var n: String = level_info(difficulty)["name"]
	return n


func upkeep_scale() -> float:
	# Multiplies every monthly running cost: 0.8 on Easy, 1 on Normal, 1.25 on Hard.
	var scale: float = level_info(difficulty)["upkeep"]
	return scale


func loan_rate() -> float:
	# Yearly interest on loans, e.g. 0.06 = 6%.
	var rate: float = level_info(difficulty)["loan_rate"]
	return rate


func loan_limit() -> int:
	# The most the town can owe at once.
	var limit: int = level_info(difficulty)["loan_limit"]
	return limit


func last_balance() -> int:
	# Last month's money in minus money out: taxes - upkeep - loan payments.
	return last_income - last_upkeep - last_loan


func loan_interest() -> int:
	# Interest charged next month on what's owed now.
	return roundi(debt * loan_rate() / 12.0)


func loan_repayment() -> int:
	# The slice of the loan paid back next month (on top of the interest).
	if debt <= 0:
		return 0
	var slice := maxi(ceili(debt_peak / float(Settings.LOAN_MONTHS)), Settings.LOAN_MIN_PAYMENT)
	return mini(slice, debt)


func loan_payment() -> int:
	# Next month's loan payment: interest plus repayment.
	return loan_interest() + loan_repayment()


func borrow_problem(amount: int) -> String:
	# "" if the town can borrow this much now; otherwise why not, in a few words.
	if amount <= 0:
		return "nothing to borrow"
	if debt + amount > loan_limit():
		var room := loan_limit() - debt
		if room <= 0:
			return "you already owe the most allowed (%s)" % _pounds(loan_limit())
		return "only %s more can be borrowed" % _pounds(room)
	return ""


func borrow(amount: int) -> bool:
	if borrow_problem(amount) != "":
		return false
	money += amount
	debt += amount
	debt_peak = maxi(debt_peak, debt)
	return true


func repay_problem(amount: int) -> String:
	# "" if the town can pay back this much now (amount < 0: everything owed).
	if debt <= 0:
		return "nothing owed"
	var paying := debt if amount < 0 else mini(amount, debt)
	if money < paying:
		return "not enough money (that takes %s)" % _pounds(paying)
	return ""


func repay(amount: int) -> int:
	# Pay back early, from the town's money (amount < 0: everything owed).
	# Returns how much was paid.
	if repay_problem(amount) != "":
		return 0
	var paying := debt if amount < 0 else mini(amount, debt)
	money -= paying
	debt -= paying
	if debt == 0:
		debt_peak = 0
	return paying


func _pay_loan() -> void:
	# Each month: the interest plus a slice of the loan. It's paid even if the
	# money has run out (the money just goes further below zero).
	last_interest = loan_interest()
	var slice := loan_repayment()
	last_loan = last_interest + slice
	debt -= slice
	money -= last_loan
	if debt <= 0:
		debt = 0
		debt_peak = 0


static func _pounds(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-£" if amount < 0 else "£") + digits + out


# ------------------------------------------------------------- city numbers

func recount() -> void:
	population = 0
	shop_jobs = 0
	industry_jobs = 0
	office_jobs = 0
	road_tiles = 0
	plants = 0
	park_tiles = 0
	power_used = 0
	power_supply = 0
	water_supply = 0
	services = [0, 0, 0, 0]
	small_services = [0, 0, 0, 0]
	counts = {}
	abandoned_count = 0
	run_down_count = 0
	for i in w * h:
		var t: int = tiles[i]
		counts[t] = int(counts.get(t, 0)) + 1
		if abandoned[i] == 1:
			abandoned_count += 1
		elif decline[i] >= Settings.ABANDON_WARN_MONTHS:
			run_down_count += 1
		power_used += power_use(i)
		if is_service(t):
			services[service_of(t)] += 1
			if service_small(t):
				small_services[service_of(t)] += 1
		if is_building(t):
			var made: int = info(t).get("power", 0)
			if made > 0:
				plants += 1
				power_supply += made
			var supplied: int = info(t).get("water", 0)
			water_supply += supplied
		match t:
			Tile.ROAD:
				road_tiles += 1
			Tile.PARK:
				park_tiles += 1
			Tile.HOMES:
				population += units(i)
			Tile.SHOPS:
				shop_jobs += units(i)
			Tile.INDUSTRY:
				industry_jobs += units(i)
			Tile.OFFICES:
				office_jobs += units(i)
	_update_power()
	_update_water()
	var open_before := airports_open
	_update_airports()
	if airports_open != open_before:
		_value_dirty = true           # (an airport opening or closing changes noise and fumes)
	_measure_rubbish()
	_measure_leisure()
	_measure_polluted_homes()
	_update_demand()
	_update_land_value()
	var price_total := 0.0
	var homes := 0
	for i in w * h:
		if tiles[i] == Tile.HOMES and levels[i] > 0:
			price_total += home_price(i) * units(i)
			homes += units(i)
	average_home_price = roundi(price_total / homes) if homes > 0 else 0


func is_zone(t: int) -> bool:
	return t == Tile.HOMES or t == Tile.SHOPS or t == Tile.INDUSTRY or t == Tile.OFFICES


func is_service(t: int) -> bool:
	return service_of(t) >= 0


func service_of(t: int) -> int:
	# Which service (Service.POLICE...) a tile gives, big or small; -1 for anything else.
	if t >= Tile.POLICE and t <= Tile.HOSPITAL:
		return t - Tile.POLICE
	var s: int = SMALL_SERVICES.get(t, -1)
	return s


func service_small(t: int) -> bool:
	return SMALL_SERVICES.has(t)


func service_name(t: int) -> String:
	var names: Array = Settings.SMALL_SERVICE_NAMES if service_small(t) else Settings.SERVICE_NAMES
	var n: String = names[service_of(t)]
	return n


func power_use(i: int) -> int:
	# Zones use one unit per stage; services and other buildings a fixed amount.
	var t: int = tiles[i]
	if is_zone(t):
		return 0 if abandoned[i] == 1 else stage(i)
	if is_service(t):
		return Settings.SMALL_SERVICE_POWER if service_small(t) else Settings.SERVICE_POWER
	if is_building(t):
		var use: int = info(t).get("uses_power", 0)
		return use
	return 0


# ------------------------------------------------------------- other buildings

func is_building(t: int) -> bool:
	# Power plants, utilities, leisure and transport (everything in Settings.BUILDINGS).
	return BUILDING_KEYS.has(t)


func info(t: int) -> Dictionary:
	# This building's entry in Settings.BUILDINGS ({} for anything else).
	if not BUILDING_KEYS.has(t):
		return {}
	var d: Dictionary = Settings.BUILDINGS[BUILDING_KEYS[t]]
	return d


func building_name(t: int) -> String:
	var n: String = info(t).get("name", "")
	return n


func count_of(t: int) -> int:
	var n: int = counts.get(t, 0)
	return n


func makes_power(t: int) -> bool:
	return int(info(t).get("power", 0)) > 0


func needs_nothing(t: int) -> bool:
	# Woodland: no road, power or water, and never "not working".
	return bool(info(t).get("no_road", false))


func can_build_here(t: int, i: int) -> String:
	# "" if this building may go on this tile; otherwise why not.
	var d := info(t)
	var unlock: int = d.get("unlock", 0)
	if population < unlock:
		return "%s needs a town of %d people (you have %d)." % [d["name"], unlock, population]
	if bool(d.get("only_one", false)) and count_of(t) > 0:
		return "The town already has a %s." % String(d["name"]).to_lower()
	if bool(d.get("near_sea", false)) and not _beside_sea(i):
		return "A %s has to be built right by the sea." % String(d["name"]).to_lower()
	return ""


func _beside_sea(i: int) -> bool:
	var x := i % w
	var y := i / w
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx := x + d.x
		var ny := y + d.y
		if nx >= 0 and ny >= 0 and nx < w and ny < h and water[ny * w + nx] == 1:
			return true
	return false


func building_working(i: int) -> bool:
	# Power plants and woodland just work. Everything else needs a road, and power if it uses any.
	var t: int = tiles[i]
	if makes_power(t) or needs_nothing(t):
		return true
	if t == Tile.AIRPORT:
		return airport_problem(i) == ""
	if not near_road(i):
		return false
	if int(info(t).get("uses_power", 0)) > 0:
		_update_power()
		return powered[i] == 1
	return true


func building_status(i: int) -> String:
	var t: int = tiles[i]
	if makes_power(t):
		return "making %d units of power" % int(info(t)["power"])
	if needs_nothing(t):
		return "growing"
	if t == Tile.AIRPORT:
		var why := airport_problem(i)
		return "open, flights coming and going" if why == "" else "not open, " + why
	if not near_road(i):
		return "not working, needs a road within %d tiles" % Settings.ROAD_REACH
	if int(info(t).get("uses_power", 0)) > 0:
		_update_power()
		if powered[i] == 0:
			return "not working, no power"
	return "working"


func building_upkeep() -> int:
	var total := 0
	for t: int in BUILDING_KEYS:
		var each: int = info(t).get("upkeep", 0)
		total += each * count_of(t)
	return total


func _measure_rubbish() -> void:
	# Rubbish made by residents and jobs, against what working landfills and
	# recycling centres can take.
	rubbish_made = roundi(population + jobs() * Settings.RUBBISH_PER_JOB)
	rubbish_capacity = 0
	for i in w * h:
		var t: int = tiles[i]
		if t == Tile.LANDFILL or t == Tile.RECYCLING:
			if building_working(i):
				var cap: int = info(t).get("rubbish", 0)
				rubbish_capacity += cap


func rubbish_shortfall() -> float:
	# 0 = all collected, 1 = none of it.
	if population < Settings.RUBBISH_START_POP or rubbish_made <= 0:
		return 0.0
	return clampf(float(rubbish_made - rubbish_capacity) / rubbish_made, 0.0, 1.0)


func rubbish_word() -> String:
	var r := rubbish_shortfall()
	if population < Settings.RUBBISH_START_POP:
		return "not a problem yet"
	if r <= 0.0:
		return "all collected"
	if r < 0.3:
		return "some piling up"
	return "piling up"


func _measure_leisure() -> void:
	# Leisure buildings and landmarks that are working add appeal (up to a limit).
	var total := 0.0
	var tourists := 0.0
	for i in w * h:
		var t: int = tiles[i]
		if is_building(t):
			var a: float = info(t).get("appeal", 0.0)
			if a > 0.0 and building_working(i):
				total += a
				if is_landmark(t):
					var v: float = info(t).get("visitors", 0.0)
					tourists += v
	leisure_appeal = minf(total, Settings.LEISURE_APPEAL_MAX)
	tourism = minf(tourists, Settings.TOURISM_MAX)


func is_landmark(t: int) -> bool:
	return bool(info(t).get("landmark", false))


# ------------------------------------------------------------- airport

func airport_problem(i: int) -> String:
	# Why the airport this tile belongs to isn't open ("" = it is).
	if i >= _airport_group.size() or _airport_group[i] < 0 or _airport_group[i] >= _airport_problems.size():
		return "not laid out yet"
	return _airport_problems[_airport_group[i]]


func airport_role_at(i: int) -> int:
	# AirportRole of a tile (0 for anything that isn't airport), without the direction bits.
	return airport_role[i] & 7 if i < airport_role.size() else 0


func _update_airports() -> void:
	# Group the airport tiles, lay each group out (runway, taxiway, apron,
	# terminal, tower, hangars, grass) and say whether it can open.
	# (Power must be up to date.)
	airport_role.resize(w * h)
	airport_role.fill(0)
	_airport_group.resize(w * h)
	_airport_group.fill(-1)
	_airport_problems.clear()
	_airport_terminals.clear()
	airports_open = 0
	if not tiles.has(Tile.AIRPORT):
		return
	_update_road_distance()
	for start in w * h:
		if tiles[start] != Tile.AIRPORT or _airport_group[start] >= 0:
			continue
		var g := _airport_problems.size()
		var members: Array[int] = [start]
		_airport_group[start] = g
		var head := 0
		while head < members.size():
			var i := members[head]
			head += 1
			var x := i % w
			for n: int in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
				if n >= 0 and n < w * h and tiles[n] == Tile.AIRPORT and _airport_group[n] < 0:
					_airport_group[n] = g
					members.append(n)
		_airport_problems.append(_lay_out_airport(g, members))
		if _airport_problems[g] == "":
			airports_open += 1


func _lay_out_airport(g: int, members: Array[int]) -> String:
	# The longest straight run of tiles is the runway. Of several as long, the one
	# AIRPORT_APRON_ROWS back from the landside (the tile nearest a road), so
	# there's room for the stands between the terminal and the runway.
	var landside: int = members[0]
	for i in members:
		if _road_dist[i] < _road_dist[landside]:
			landside = i
	var best_len := 0
	var best_start := -1
	var best_off := 0
	var vertical := false
	var ideal: int = Settings.AIRPORT_APRON_ROWS
	for i in members:
		var x := i % w
		if x == 0 or _airport_group[i - 1] != g:
			var n := 0
			while x + n < w and _airport_group[i + n] == g:
				n += 1
			var off := absi(absi(i / w - landside / w) - ideal)
			if n > best_len or (n == best_len and off < best_off):
				best_len = n
				best_start = i
				best_off = off
				vertical = false
		if i < w or _airport_group[i - w] != g:
			var n := 0
			while i + n * w < w * h and _airport_group[i + n * w] == g:
				n += 1
			var off := absi(absi(i % w - landside % w) - ideal)
			if n > best_len or (n == best_len and off < best_off):
				best_len = n
				best_start = i
				best_off = off
				vertical = true
	var step := w if vertical else 1
	var side := 1 if vertical else w          # one tile across the runway
	var turn := 8 if vertical else 0
	for i in members:
		airport_role[i] = AirportRole.GRASS + turn
	for k in best_len:
		var end := 16 if (k == 0 or k == best_len - 1) else 0
		airport_role[best_start + k * step] = AirportRole.RUNWAY + turn + end
	# The terminal: the tile off the runway nearest a road (then nearest the middle of the runway).
	var mid := Vector2((best_start % w), (best_start / w)) + Vector2(step % w, step / w) * (best_len - 1) * 0.5
	var terminal := -1
	var terminal_score := INF
	var powered_any := false
	for i in members:
		if powered[i] == 1:
			powered_any = true
		if airport_role[i] & 7 == AirportRole.RUNWAY:
			continue
		var score: float = _road_dist[i] * 1000.0 + Vector2(i % w, i / w).distance_to(mid)
		if score < terminal_score:
			terminal_score = score
			terminal = i
	if terminal >= 0:
		# How far the terminal is from the runway, along it (u) and across it (v).
		var tu: int = (terminal / w - best_start / w) if vertical else (terminal % w - best_start % w)
		var tv: int = (terminal % w - best_start % w) if vertical else (terminal / w - best_start / w)
		var toward := 1 if tv > 0 else -1
		# A taxiway along the runway on the terminal's side.
		for k in best_len:
			var n: int = best_start + k * step + toward * side
			if _airport_inside(n, g, best_start + k * step, vertical):
				airport_role[n] = AirportRole.TAXIWAY + turn
		# The terminal's row: tower, terminal (two tiles), hangars; apron from there to the taxiway.
		var row_roles: Array[int] = [AirportRole.TOWER, AirportRole.TERMINAL, AirportRole.TERMINAL, AirportRole.HANGAR, AirportRole.HANGAR]
		for d in range(-1, 4):
			var u := tu + d
			if u < 0 or u >= best_len:
				continue
			# (The taxiway beside the stands is concrete too: +16.)
			var link: int = best_start + u * step + toward * side
			if airport_role[link] & 7 == AirportRole.TAXIWAY:
				airport_role[link] = AirportRole.TAXIWAY + turn + 16
			for across in range(2, absi(tv) + 1):
				var n: int = best_start + u * step + toward * across * side
				if not _airport_inside(n, g, best_start + u * step, vertical):
					continue
				airport_role[n] = (row_roles[d + 1] if across == absi(tv) else AirportRole.APRON) + turn
		airport_role[terminal] = AirportRole.TERMINAL + turn
	# Can it open?
	if best_len < Settings.AIRPORT_MIN_RUNWAY:
		return "the runway needs a straight run of %d m (the longest here is %d m)" % [
			Settings.AIRPORT_MIN_RUNWAY * 50, best_len * 50]
	if members.size() < Settings.AIRPORT_MIN_TILES or terminal < 0:
		return "it needs more room beside the runway for the terminal (%d tiles in all; it has %d)" % [
			Settings.AIRPORT_MIN_TILES, members.size()]
	if _road_dist[terminal] > Settings.ROAD_REACH:
		return "it needs a road within %d tiles of one side, for the terminal" % Settings.ROAD_REACH
	if not powered_any:
		return "no power"
	if airports_open == 0:
		_airport_terminals.append(terminal)
	return ""


func _airport_inside(n: int, g: int, beside: int, vertical: bool) -> bool:
	# Is tile n on the map, in airport g, and in line with runway tile `beside`
	# (same row or column, so a step across never wraps round the map's edge)?
	if n < 0 or n >= w * h or _airport_group[n] != g or airport_role[n] & 7 == AirportRole.RUNWAY:
		return false
	return n / w == beside / w if vertical else n % w == beside % w


func _working_count(t: int) -> int:
	var n := 0
	for i in w * h:
		if tiles[i] == t and building_working(i):
			n += 1
	return n


# ------------------------------------------------------------- water

func water_map() -> PackedByteArray:
	_update_water()
	return watered


func needs_water_to_grow(i: int) -> bool:
	# A zone plot that would grow if it had (more) water.
	var lv: int = levels[i]
	return is_zone(tiles[i]) and lv < max_level(i) and _needs_water(i, stage_at(i, lv + 1))


func _needs_water(i: int, next_stage: int) -> bool:
	# Anything bigger than the first stage (villas, corner shops, small works) needs water.
	if next_stage < 2:
		return false
	_update_water()
	return watered[i] == 0 or _wnet_spare[_wnet_id[i]] <= 0


func _update_water() -> void:
	# Like power: water spreads from each working pump or tower through every
	# touching built tile, and plots nearest the supply get it first.
	_update_power()
	if not _water_dirty:
		return
	_water_dirty = false
	watered.fill(0)
	_wnet_id.fill(-1)
	_wnet_spare.clear()
	water_used = 0
	for start in w * h:
		var st: int = tiles[start]
		if (st != Tile.WATER_PUMP and st != Tile.WATER_TOWER) or _wnet_id[start] != -1:
			continue
		var net := _wnet_spare.size()
		var members: Array[int] = [start]
		_wnet_id[start] = net
		var head := 0
		while head < members.size():
			var i := members[head]
			head += 1
			var x := i % w
			if x > 0:
				_join_water(i - 1, net, members)
			if x < w - 1:
				_join_water(i + 1, net, members)
			if i >= w:
				_join_water(i - w, net, members)
			if i < w * (h - 1):
				_join_water(i + w, net, members)
		var left := 0
		for i in members:
			var t: int = tiles[i]
			if (t == Tile.WATER_PUMP or t == Tile.WATER_TOWER) and building_working(i):
				var supplied: int = info(t).get("water", 0)
				left += supplied
		for i in members:
			if is_zone(tiles[i]):
				var use: int = 0 if abandoned[i] == 1 else stage(i)
				if use <= left:
					left -= use
					water_used += use
					watered[i] = 1
			else:
				watered[i] = 1 if left > 0 else 0
		_wnet_spare.append(left)


func _join_water(n: int, net: int, members: Array[int]) -> void:
	if tiles[n] != Tile.EMPTY and _wnet_id[n] == -1:
		_wnet_id[n] = net
		members.append(n)


func home_price(i: int) -> int:
	# What a home on this plot would sell for: land value times the housing shortage.
	_update_land_value()
	var price: float = Settings.BASE_HOME_PRICE * (0.5 + land_value[i]) \
		* (1.0 + Settings.SHORTAGE_PRICE_EFFECT * shortage[Tile.HOMES])
	return roundi(price / 1000.0) * 1000


func land_value_word(i: int) -> String:
	_update_land_value()
	var v := land_value[i]
	if v >= 0.65:
		return "very high"
	if v >= 0.5:
		return "high"
	if v >= 0.35:
		return "average"
	if v >= 0.2:
		return "low"
	return "very low"


# ------------------------------------------------------------- services

func service_working(i: int) -> bool:
	# A service needs a road and power to do anything (and some funding).
	_update_power()
	var f: float = funding[service_of(tiles[i])]
	return near_road(i) and powered[i] == 1 and f > 0.0


func service_status(i: int) -> String:
	var f: float = funding[service_of(tiles[i])]
	if f <= 0.0:
		return "closed (no funding)"
	if not near_road(i):
		return "not working, needs a road within %d tiles" % Settings.ROAD_REACH
	_update_power()
	if powered[i] == 0:
		return "not working, no power"
	return "working"


func service_reach_m(s: int, cell_m: float, small: bool = false) -> int:
	# How far a service reaches at its current funding, in metres.
	return roundi(_service_radius(s, small) * cell_m)


func _service_radius(s: int, small: bool = false) -> float:
	var r: float = Settings.SMALL_SERVICE_RADIUS[s] if small else Settings.SERVICE_RADIUS[s]
	return r * (0.4 + 0.6 * funding[s])     # 50% funding reaches 70% as far


func coverage_at(s: int, i: int) -> float:
	_update_coverage()
	return coverage[s * w * h + i]


func covered(s: int, i: int) -> bool:
	return coverage_at(s, i) >= Settings.COVERED


func services_covering(i: int) -> int:
	var n := 0
	for s in 4:
		if covered(s, i):
			n += 1
	return n


func set_funding(s: int, value: float) -> void:
	funding[s] = clampf(snappedf(value, 0.1), 0.0, Settings.MAX_FUNDING)
	_coverage_dirty = true
	_value_dirty = true


func service_upkeep() -> int:
	var total := 0.0
	for s in 4:
		var each: float = Settings.SERVICE_UPKEEP[s]
		var small_each: float = Settings.SMALL_SERVICE_UPKEEP[s]
		var small: int = small_services[s]
		total += (each * (int(services[s]) - small) + small_each * small) * funding[s]
	return roundi(total)


func _update_coverage() -> void:
	# Each working service covers the tiles around it: fully close by, fading
	# out to nothing at the edge of its reach.
	if not _coverage_dirty:
		return
	_coverage_dirty = false
	coverage.fill(0.0)
	_bus_cover.fill(0)
	_transit.fill(0)
	for i in w * h:
		if (tiles[i] == Tile.BUS_DEPOT or tiles[i] == Tile.STATION) and building_working(i):
			var tr: int = Settings.SKYSCRAPER_TRANSIT
			var tx := i % w
			var ty := i / w
			for y in range(maxi(ty - tr, 0), mini(ty + tr, h - 1) + 1):
				for x in range(maxi(tx - tr, 0), mini(tx + tr, w - 1) + 1):
					if Vector2(x - tx, y - ty).length() <= tr:
						_transit[y * w + x] = 1
		if tiles[i] == Tile.BUS_DEPOT and building_working(i):
			var r: int = info(Tile.BUS_DEPOT).get("bus", 0)
			var bx := i % w
			var by := i / w
			for y in range(maxi(by - r, 0), mini(by + r, h - 1) + 1):
				for x in range(maxi(bx - r, 0), mini(bx + r, w - 1) + 1):
					if Vector2(x - bx, y - by).length() <= r:
						_bus_cover[y * w + x] = 1
	for i in w * h:
		if not is_service(tiles[i]) or not service_working(i):
			continue
		var s: int = service_of(tiles[i])
		var radius := _service_radius(s, service_small(tiles[i]))
		var reach := ceili(radius)
		var cx := i % w
		var cy := i / w
		var offset := s * w * h
		for y in range(maxi(cy - reach, 0), mini(cy + reach, h - 1) + 1):
			for x in range(maxi(cx - reach, 0), mini(cx + reach, w - 1) + 1):
				var d := Vector2(x - cx, y - cy).length()
				var c := clampf((1.0 - d / radius) * 1.6, 0.0, 1.0)
				var k := offset + y * w + x
				if c > coverage[k]:
					coverage[k] = c


func _service_factor(i: int) -> float:
	# Bigger towns grow slowly where there's no police (homes and shops) or
	# no hospital (homes). Homes also grow slowly in polluted air.
	var f := 1.0
	var t: int = tiles[i]
	if t == Tile.HOMES:
		f *= _pollution_factor(i)
	if (t == Tile.HOMES or t == Tile.SHOPS or t == Tile.OFFICES) and population >= Settings.POLICE_NEEDED_POP \
			and not covered(Service.POLICE, i):
		f *= 0.5
	if t == Tile.HOMES and population >= Settings.HOSPITAL_NEEDED_POP \
			and not covered(Service.HOSPITAL, i):
		f *= 0.5
	return f


func _missing_services(i: int) -> String:
	# Which services are slowing this plot down, in words ("" = none).
	var t: int = tiles[i]
	var words: Array[String] = []
	if (t == Tile.HOMES or t == Tile.SHOPS or t == Tile.OFFICES) and population >= Settings.POLICE_NEEDED_POP \
			and not covered(Service.POLICE, i):
		words.append("police station")
	if t == Tile.HOMES and population >= Settings.HOSPITAL_NEEDED_POP \
			and not covered(Service.HOSPITAL, i):
		words.append("hospital")
	return " or ".join(words)


func _skyscraper_problem(i: int) -> String:
	# Skyscrapers need a big town and transport to bring the people in ("" = fine).
	if population < Settings.SKYSCRAPER_POP:
		return "waiting to build a skyscraper: needs a town of %d people" % Settings.SKYSCRAPER_POP
	_update_coverage()
	if _transit[i] == 0:
		return "waiting to build a skyscraper: needs a railway station or bus depot within %d m" \
			% (Settings.SKYSCRAPER_TRANSIT * 50)
	return ""


func _needs_school(i: int, next_stage: int) -> bool:
	# In a bigger town, families won't move into anything bigger than terraces
	# without a school nearby.
	return tiles[i] == Tile.HOMES and next_stage > 2 and population >= Settings.SCHOOL_NEEDED_POP \
		and not covered(Service.SCHOOL, i)


# --- Each service on its own (the Services view's filter, the hover card, the advisors) ---
# The words _zone_check() uses when a missing service holds a plot back (police,
# fire, school, hospital). Fire has no growth rule: its risk is buildings burning
# down. advisors.gd's REASONS counts the same phrases.
const SERVICE_HELD_PHRASES := ["no police station", "", "waiting for a school", "hospital nearby"]


func service_full_tiles(s: int, small: bool = false) -> float:
	# Tiles round a service building that it covers fully (coverage 1): the
	# first 37.5% of its reach, at its current funding.
	return _service_radius(s, small) * (1.0 - 1.0 / 1.6)


func service_cover_tiles(s: int, small: bool = false) -> float:
	# Tiles round a service building that it covers enough to count (coverage at
	# least Settings.COVERED), at its current funding.
	return _service_radius(s, small) * (1.0 - Settings.COVERED / 1.6)


func cover_strength(s: int, i: int) -> int:
	# 0 no cover, 1 the faint edge of a reach (too weak to count), 2 covered, 3 full cover.
	var c := coverage_at(s, i)
	if c >= 0.999:
		return 3
	if c >= Settings.COVERED:
		return 2
	return 1 if c > 0.0 else 0


func service_matters(s: int, i: int) -> bool:
	# Whether the rules ask for this service at this zone plot: police for homes
	# and shops, fire for every plot, schools and hospitals for homes. (Cover
	# anywhere also adds a little land value, and homes' cover adds to happiness.)
	var t: int = tiles[i]
	if not is_zone(t):
		return false
	match s:
		Service.POLICE:
			return t == Tile.HOMES or t == Tile.SHOPS or t == Tile.OFFICES
		Service.FIRE:
			return true
	return t == Tile.HOMES


func service_needed_from(s: int) -> int:
	# The town size from which missing this service holds plots back (fire: from
	# when fires can break out).
	return [Settings.POLICE_NEEDED_POP, Settings.FIRE_START_POP, Settings.SCHOOL_NEEDED_POP,
		Settings.HOSPITAL_NEEDED_POP][s]


func service_holds_back(s: int, i: int) -> bool:
	# This zone plot is held back right now for want of service s: the reason its
	# hover text gives (police and hospital: growing at half speed; school: can't
	# grow past terraces), or for fire, a building that could burn down.
	if not service_matters(s, i) or covered(s, i):
		return false
	if s == Service.FIRE:
		return levels[i] > 0 and population >= Settings.FIRE_START_POP
	var check := _zone_check(i)
	var why: String = check[1]
	var phrase: String = SERVICE_HELD_PHRASES[s]
	return why.contains(phrase)


func service_report(s: int) -> Dictionary:
	# Town-wide, for the Services view's key: residents within reach of service s
	# (share 0-1, or -1 with nobody living here yet), plots held back for want of
	# it, and how many of its buildings there are and work.
	var people := 0
	var reached := 0
	var held := 0
	var working := 0
	for i in w * h:
		var t: int = tiles[i]
		if t == Tile.HOMES and levels[i] > 0:
			var n := units(i)
			people += n
			if covered(s, i):
				reached += n
		if is_zone(t) and service_holds_back(s, i):
			held += 1
		if service_of(t) == s and service_working(i):
			working += 1
	var built: int = services[s]
	return {"share": float(reached) / people if people > 0 else -1.0, "held": held,
		"built": built, "working": working}


func _reach_of(s: int, at: int, small: bool = false) -> PackedInt32Array:
	# The tiles a building of service s at `at` would cover enough to count.
	var out := PackedInt32Array()
	var radius := _service_radius(s, small)
	var reach := ceili(radius)
	var cx := at % w
	var cy := at / w
	for y in range(maxi(cy - reach, 0), mini(cy + reach, h - 1) + 1):
		for x in range(maxi(cx - reach, 0), mini(cx + reach, w - 1) + 1):
			var d := Vector2(x - cx, y - cy).length()
			if (1.0 - d / radius) * 1.6 >= Settings.COVERED:
				out.append(y * w + x)
	return out


func service_reach(i: int) -> Dictionary:
	# What the service building at i covers by itself: zone plots and residents
	# within the reach that counts ("alone": plots no other building of its kind
	# covers). Nothing while it isn't working.
	var s: int = service_of(tiles[i])
	var plots := 0
	var people := 0
	var alone := 0
	if service_working(i):
		var others: Array[Vector3] = []     # (x, y, reach) of every other building of this service
		for j in w * h:
			if j != i and service_of(tiles[j]) == s and service_working(j):
				others.append(Vector3(j % w, j / w, _service_radius(s, service_small(tiles[j]))))
		for k: int in _reach_of(s, i, service_small(tiles[i])):
			if not is_zone(tiles[k]):
				continue
			plots += 1
			if tiles[k] == Tile.HOMES:
				people += units(k)
			# Covered by another building of the same kind too?
			var spot := Vector2(k % w, k / w)
			var shared := false
			for o: Vector3 in others:
				if (1.0 - spot.distance_to(Vector2(o.x, o.y)) / o.z) * 1.6 >= Settings.COVERED:
					shared = true
					break
			if not shared:
				alone += 1
	return {"plots": plots, "people": people, "alone": alone}


func service_gain(s: int, at: int, small: bool = false) -> Dictionary:
	# What a new building of service s at `at` would add: zone plots that want it
	# and have none now (and their residents), and how many of those are held
	# back right now.
	var plots := 0
	var people := 0
	var held := 0
	for k: int in _reach_of(s, at, small):
		if not service_matters(s, k) or covered(s, k):
			continue
		plots += 1
		if tiles[k] == Tile.HOMES:
			people += units(k)
		if service_holds_back(s, k):
			held += 1
	return {"plots": plots, "people": people, "held": held}


func _fires() -> void:
	# Now and then a building with no fire station nearby burns down.
	burned.clear()
	if population < Settings.FIRE_START_POP:
		return
	for i in w * h:
		if not is_zone(tiles[i]) or levels[i] == 0:
			continue
		var risk: float = Settings.FIRE_CHANCE * (1.0 - coverage_at(Service.FIRE, i))
		if tiles[i] == Tile.INDUSTRY:
			risk *= 2.0
		if _rng.randf() < risk:
			levels[i] = 0
			abandoned[i] = 0
			decline[i] = 0
			burned.append(i)
			shrank.append(i)


# ------------------------------------------------------------- land value

func _measure_sea() -> void:
	# How close each tile is to the sea: 1 on the shore, fading to 0 inland.
	_sea_near.resize(w * h)
	_sea_near.fill(0.0)
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(9999)
	var queue: Array[int] = []
	for i in w * h:
		if water[i] == 1:
			dist[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var d := dist[i]
		if d >= Settings.SEA_VIEW_TILES:
			continue
		var x := i % w
		for n: int in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
			if n >= 0 and n < w * h and dist[n] > d + 1:
				dist[n] = d + 1
				queue.append(n)
	for i in w * h:
		if water[i] == 0 and dist[i] <= Settings.SEA_VIEW_TILES:
			_sea_near[i] = 1.0 - float(dist[i] - 1) / Settings.SEA_VIEW_TILES


func land_value_map() -> PackedFloat32Array:
	_update_land_value()
	return land_value


func _update_land_value() -> void:
	# Start from a base value plus the sea, then let nearby things raise or lower it.
	if not _value_dirty:
		return
	_value_dirty = false
	_measure_pollution()
	for i in w * h:
		land_value[i] = Settings.BASE_LAND_VALUE + Settings.SEA_BONUS * _sea_near[i] \
			- Settings.POLLUTION_VALUE_EFFECT * pollution[i]   # nobody wants to breathe smoke
	for i in w * h:
		var t := tiles[i]
		if abandoned[i] == 1:
			# Boarded-up buildings drag the area down a little (and no longer
			# bring in shoppers or smoke).
			_spread(i, Settings.ABANDONED_RADIUS, -Settings.ABANDONED_VALUE_PENALTY)
			continue
		match t:
			Tile.PARK:
				_spread(i, 3, Settings.PARK_BONUS)
			Tile.WOODLAND:
				pass    # (added up below, with a cap)
			Tile.SHOPS:
				if levels[i] > 0:
					_spread(i, 3, Settings.SHOP_BONUS * stage(i))
			Tile.INDUSTRY:
				_spread(i, 4, -Settings.INDUSTRY_PENALTY * maxi(stage(i), 1))
			Tile.OFFICES:
				if levels[i] > 0:
					_spread(i, 3, Settings.OFFICE_BONUS * stage(i))
			_:
				if is_building(t):
					var amount: float = info(t).get("value", 0.0)
					var radius: int = info(t).get("radius", 0)
					if amount != 0.0:
						_spread(i, radius, amount)
	# Woodland: a little land value from the trees round about, never more than
	# WOODLAND_VALUE_MAX however big the forest (so it can't replace parks).
	_sum_woodland(Settings.WOODLAND_VALUE_RADIUS, Settings.WOODLAND_VALUE)
	for i in w * h:
		land_value[i] += minf(_wood_effect[i], Settings.WOODLAND_VALUE_MAX)
	# Airport noise: worse the more of the airport is near, up to a limit.
	if airports_open > 0:
		_sum_woodland(Settings.AIRPORT_NOISE_RADIUS, Settings.AIRPORT_NOISE, Tile.AIRPORT)
		for i in w * h:
			land_value[i] -= minf(_wood_effect[i], Settings.AIRPORT_NOISE_MAX)
	# Districts: a CBD is where everyone wants to be; the old town has character.
	for i in w * h:
		if district[i] == 2:
			land_value[i] += Settings.CBD_VALUE
		elif district[i] == 1:
			land_value[i] += Settings.CONSERVATION_VALUE
	# Being covered by police, fire, schools and hospitals adds value too.
	_update_coverage()
	for s in 4:
		var bonus: float = Settings.SERVICE_LAND_BONUS[s]
		var offset := s * w * h
		for i in w * h:
			land_value[i] += bonus * coverage[offset + i]
	for i in w * h:
		land_value[i] = clampf(land_value[i], 0.0, 1.0)


func _sum_woodland(radius: int, amount: float, kind: int = Tile.WOODLAND) -> void:
	# Into _wood_effect: every woodland tile's amount, fading out over radius tiles
	# (as _spread does), added up round each tile. (Also used for airport noise.)
	if _wood_effect.size() != w * h:
		_wood_effect.resize(w * h)
	_wood_effect.fill(0.0)
	if not tiles.has(kind):
		return
	for i in w * h:
		if tiles[i] != kind or (kind == Tile.AIRPORT and not building_working(i)):
			continue
		var cx := i % w
		var cy := i / w
		for y in range(maxi(cy - radius, 0), mini(cy + radius, h - 1) + 1):
			for x in range(maxi(cx - radius, 0), mini(cx + radius, w - 1) + 1):
				var d := Vector2(x - cx, y - cy).length()
				if d <= radius + 0.5:
					_wood_effect[y * w + x] += amount * (1.0 - d / (radius + 1.0))


func _spread(i: int, radius: int, amount: float) -> void:
	# Add an effect to every tile within the radius, strongest close by.
	var cx := i % w
	var cy := i / w
	for y in range(maxi(cy - radius, 0), mini(cy + radius, h - 1) + 1):
		for x in range(maxi(cx - radius, 0), mini(cx + radius, w - 1) + 1):
			var d := Vector2(x - cx, y - cy).length()
			if d <= radius + 0.5:
				land_value[y * w + x] += amount * (1.0 - d / (radius + 1.0))


# ------------------------------------------------------------- pollution
# Hooks for other features (a happiness score, advisors):
#   pollution_at(i)          0 (clean air) to 1 (heavy) on map tile i (y * w + x)
#   pollution_band(i)        0 clean, 1 a little, 2 some, 3 polluted, 4 heavy
#   pollution_word(i)        that band in words, for hover text
#   polluted_homes_share()   0-1: share of residents living in polluted air
#   pollution_feeling()      appeal lost to pollution (happiness's "pollution" part,
#                            so it's already in appeal(); don't take it off again)
#   air_word()               the town's air overall, in words
#   pollution_reach_m(t, m)  how far a building type's pollution reaches (0 = clean)
# The map is worked out along with land value (whenever the town changes, and
# every month), so it is never saved: loading a city works it out again.

func pollution_at(i: int) -> float:
	_update_land_value()
	return pollution[i]


func pollution_map() -> PackedFloat32Array:
	_update_land_value()
	return pollution


func pollution_band(i: int) -> int:
	var p := pollution_at(i)
	var band := 0
	for limit: float in Settings.POLLUTION_BANDS:
		if p >= limit:
			band += 1
	return band


func pollution_word(i: int) -> String:
	const WORDS := ["clean air", "a little pollution", "some pollution", "polluted air", "heavy pollution"]
	var word: String = WORDS[pollution_band(i)]
	return word


func polluted_homes_share() -> float:
	return polluted_share


func pollution_feeling() -> float:
	# How much appeal the town loses because people live in polluted air.
	return polluted_share * Settings.POLLUTION_APPEAL_EFFECT


func air_word() -> String:
	if polluted_share <= 0.0:
		return "clean"
	if polluted_share < 0.1:
		return "mostly clean"
	if polluted_share < 0.3:
		return "smoky in places"
	return "polluted"


func pollution_reach_m(t: int, cell_m: float) -> int:
	# How far a kind of building's pollution reaches, in metres (0 = it's clean).
	if t == Tile.INDUSTRY:
		return roundi(Settings.INDUSTRY_POLLUTION_SPREAD * cell_m)
	if not BUILDING_KEYS.has(t):
		return 0
	var key: String = BUILDING_KEYS[t]
	if not Settings.POLLUTION_SOURCES.has(key):
		return 0
	var src: Array = Settings.POLLUTION_SOURCES[key]
	var spread: int = src[1]
	return roundi(spread * cell_m)


func _pollution_source(i: int) -> Vector2:
	# x = how much this tile pollutes, y = how far it spreads in tiles (0, 0 = clean).
	var t: int = tiles[i]
	if t == Tile.INDUSTRY:
		if levels[i] == 0 or abandoned[i] == 1:   # (boarded-up works make no smoke)
			return Vector2.ZERO
		return Vector2(Settings.INDUSTRY_POLLUTION * stage(i), Settings.INDUSTRY_POLLUTION_SPREAD)
	if not BUILDING_KEYS.has(t):
		return Vector2.ZERO
	var key: String = BUILDING_KEYS[t]
	if not Settings.POLLUTION_SOURCES.has(key) or not building_working(i):
		return Vector2.ZERO
	var src: Array = Settings.POLLUTION_SOURCES[key]
	var strength: float = src[0]
	var spread: int = src[1]
	return Vector2(strength, spread)


func _measure_pollution() -> void:
	# Each source adds its strength on its own tile, fading out at the edge of its
	# spread; parks (and golf courses, half as much; woodland, capped) soak a little up. Overlapping
	# sources add up, then the total is eased into 0-1 (1 - e^-total), so a few
	# sources together get close to 1 but never past it.
	pollution.fill(0.0)
	for i: int in w * h:
		var t: int = tiles[i]
		if t == Tile.PARK:
			_spread_pollution(i, Settings.PARK_CLEANING_SPREAD, -Settings.PARK_CLEANING)
		elif t == Tile.GOLF:
			_spread_pollution(i, Settings.PARK_CLEANING_SPREAD, -Settings.PARK_CLEANING * 0.5)
		else:
			var src := _pollution_source(i)
			if src.x > 0.0:
				_spread_pollution(i, int(src.y), src.x)
	# Woodland soaks up a little too, but however big the forest, no more than
	# WOODLAND_CLEANING_MAX round any one tile.
	_sum_woodland(Settings.PARK_CLEANING_SPREAD, Settings.WOODLAND_CLEANING)
	for i: int in w * h:
		pollution[i] = 1.0 - exp(-maxf(pollution[i] - minf(_wood_effect[i], Settings.WOODLAND_CLEANING_MAX), 0.0))


func _spread_pollution(i: int, radius: int, amount: float) -> void:
	var cx := i % w
	var cy := i / w
	for y: int in range(maxi(cy - radius, 0), mini(cy + radius, h - 1) + 1):
		for x: int in range(maxi(cx - radius, 0), mini(cx + radius, w - 1) + 1):
			var d := Vector2(x - cx, y - cy).length()
			if d <= radius + 0.5:
				pollution[y * w + x] += amount * (1.0 - d / (radius + 1.0))


func _measure_polluted_homes() -> void:
	# Share of residents who live where the air counts as polluted.
	_update_land_value()
	var people := 0
	var polluted := 0
	for i: int in w * h:
		if tiles[i] == Tile.HOMES and levels[i] > 0:
			var n := units(i)
			people += n
			if pollution[i] >= Settings.POLLUTED:
				polluted += n
	polluted_share = float(polluted) / people if people > 0 else 0.0


func _pollution_factor(i: int) -> float:
	# Homes grow more slowly in polluted air (1 = clean, full speed).
	return 1.0 - Settings.POLLUTION_GROWTH_EFFECT * pollution_at(i)


func power_map() -> PackedByteArray:
	_update_power()
	return powered


func _update_power() -> void:
	# Power spreads from each plant through every touching built tile:
	# roads, zones, power lines and other plants. Each joined-up group is a
	# network. Plots nearest the plant get power first; if a network runs
	# out, the plots furthest away go dark.
	if not _power_dirty:
		return
	_power_dirty = false
	_water_dirty = true               # pumps need power, so water follows
	powered.fill(0)
	_net_id.fill(-1)
	_net_spare.clear()
	for start in w * h:
		if not makes_power(tiles[start]) or _net_id[start] != -1:
			continue
		var net := _net_spare.size()
		var members: Array[int] = [start]
		_net_id[start] = net
		var head := 0
		while head < members.size():
			var i := members[head]
			head += 1
			var x := i % w
			if x > 0:
				_join_network(i - 1, net, members)
			if x < w - 1:
				_join_network(i + 1, net, members)
			if i >= w:
				_join_network(i - w, net, members)
			if i < w * (h - 1):
				_join_network(i + w, net, members)
		var left := 0
		for i in members:
			var made: int = info(tiles[i]).get("power", 0)
			left += made
		for i in members:
			var use: int = power_use(i)
			if use > 0:
				if use <= left:
					left -= use
					powered[i] = 1
			else:
				powered[i] = 1
		_net_spare.append(left)


func _join_network(n: int, net: int, members: Array[int]) -> void:
	if tiles[n] != Tile.EMPTY and _net_id[n] == -1:
		_net_id[n] = net
		members.append(n)


func jobs() -> int:
	return shop_jobs + industry_jobs + office_jobs


func appeal() -> float:
	# How keen people are to move here (1 = normal, below 0 = they leave). It is
	# just happiness on another scale: 0% happy = -1, 33% = 0, 67% = 1, 100% = 2.
	return happiness * 3.0 - 1.0


func business_appeal() -> float:
	# How keen shops and industry are to come here, on the same scale: the parts
	# of happiness businesses care about too (taxes, services, leisure, rubbish).
	return clampf(1.0 + _sum_parts(BUSINESS_PARTS), -1.0, 2.0)


func _measure_happiness() -> void:
	# Add up everything residents care about, each in appeal points (0 = no effect).
	# (Needs services, rubbish and leisure measured first.)
	_update_water()                   # (and power) so cut-off homes are up to date
	var parts := {}
	# Taxes: low taxes please people. High taxes upset them, but much less when
	# they can see them paying for good services. Only high taxes AND poor
	# services drive people away.
	var pain := (tax_rate - Settings.DEFAULT_TAX_RATE) * Settings.TAX_DEMAND_EFFECT
	if pain > 0.0:
		pain *= lerpf(Settings.TAX_TOLERANCE_POOR, Settings.TAX_TOLERANCE_GOOD, service_score)
	parts["taxes"] = -pain
	parts["services"] = services_feeling()
	parts["leisure"] = leisure_appeal
	parts["rubbish"] = -rubbish_shortfall() * Settings.RUBBISH_EFFECT
	# Jobs: a little unemployment is normal; more than that and people get fed up.
	# (Spare jobs or jobless workers also pull people in or put them off directly,
	# in _update_demand, so this mostly explains why.)
	var out_of_work := 0.0
	if population >= Settings.JOBS_START_POP:
		out_of_work = maxf(unemployment() - Settings.JOBS_SLACK, 0.0)
	parts["jobs"] = -out_of_work * Settings.UNEMPLOYMENT_EFFECT
	# Housing: a shortage pushes prices up, and dear homes put people off coming.
	parts["housing"] = -housing_shortage() * Settings.HOUSING_EFFECT
	# Power and water: the share of residents whose homes are cut off.
	var people := 0
	var no_power := 0
	var no_water := 0
	for i in w * h:
		if tiles[i] == Tile.HOMES and levels[i] > 0:
			var n := units(i)
			people += n
			if powered[i] == 0:
				no_power += n
			elif stage(i) >= 2 and watered[i] == 0:   # villas manage without mains water
				no_water += n
	if people > 0:
		parts["power"] = -float(no_power) / people * Settings.NO_POWER_EFFECT
		parts["water"] = -float(no_water) / people * Settings.NO_WATER_EFFECT
	else:
		parts["power"] = 0.0
		parts["water"] = 0.0
	# Pollution: the share of residents breathing polluted air (see pollution_feeling).
	parts["pollution"] = -pollution_feeling()
	happiness_parts = parts
	happiness = (clampf(1.0 + _sum_parts(parts.keys()), -1.0, 2.0) + 1.0) / 3.0


func _sum_parts(names: Array) -> float:
	var total := 0.0
	for key: String in names:
		var v: float = happiness_parts.get(key, 0.0)
		total += v
	return total


func unemployment() -> float:
	# Share of workers without a job, 0 to 1.
	var workers := population * Settings.WORKER_SHARE
	if workers <= 0.0:
		return 0.0
	return clampf((workers - jobs()) / workers, 0.0, 1.0)


func happiness_word() -> String:
	# 50% is where people stop moving in; below 33% they start to leave.
	if happiness >= 0.8:
		return "delighted"
	if happiness >= 0.6:
		return "happy"
	if happiness >= 0.5:
		return "content"
	if happiness >= 1.0 / 3.0:
		return "unhappy, few want to move in"
	return "angry, people are leaving"


func complaint_keys(count: int = 2, business_only: bool = false) -> Array[String]:
	# The biggest things dragging happiness down, worst first (part names, see
	# COMPLAINTS). Only things that cost at least Settings.COMPLAINT_SIZE count.
	var found: Array[String] = []
	for key: String in happiness_parts:
		if business_only and not BUSINESS_PARTS.has(key):
			continue
		var v: float = happiness_parts[key]
		if v <= -Settings.COMPLAINT_SIZE and COMPLAINTS.has(key):
			found.append(key)
	found.sort_custom(func(a: String, b: String) -> bool:
		return float(happiness_parts[a]) < float(happiness_parts[b]))
	var top: Array[String] = []
	for key: String in found:
		if top.size() >= count:
			break
		top.append(key)
	return top


func unhappy_reasons(count: int = 2) -> Array[String]:
	# The top complaints in plain words, worst first, e.g. ["not enough jobs"].
	# Empty when nothing much is wrong.
	var words: Array[String] = []
	for key: String in complaint_keys(count):
		words.append(complaint_text(key))
	return words


func complaint_text(key: String) -> String:
	var entry: Array = COMPLAINTS.get(key, ["", ""])
	var text: String = entry[0]
	return text


func complaint_fix(key: String) -> String:
	# What the player can do about a complaint, in plain words.
	var entry: Array = COMPLAINTS.get(key, ["", ""])
	var text: String = entry[1]
	return text


func services_expected() -> float:
	# A village doesn't expect much; a town expects good cover.
	return clampf(float(population) / Settings.SERVICES_EXPECTED_POP, 0.0, 0.7)


func services_feeling() -> float:
	# Above 0 when services are better than people expect, below when worse.
	return (service_score - services_expected()) * Settings.SERVICES_EFFECT


func local_service(i: int) -> float:
	# Average cover of the four services at one plot, 0 to 1.
	_update_coverage()
	var total := 0.0
	for s in 4:
		total += coverage[s * w * h + i]
	return total / 4.0


func _measure_services() -> void:
	# How well the town's homes are covered, weighted by how many live in each.
	var people := 0
	var covered_total := 0.0
	for i in w * h:
		if tiles[i] == Tile.HOMES and levels[i] > 0:
			var n := units(i)
			people += n
			covered_total += n * local_service(i)
	service_score = covered_total / people if people > 0 else 0.0


func _update_demand() -> void:
	_measure_services()
	_measure_happiness()
	var a := appeal()
	var workers := population * Settings.WORKER_SHARE
	var spare_jobs := jobs() - workers          # below 0 = people out of work
	# Homes: people from the region who'd like to move here (more for a bigger,
	# happier town), plus people coming for spare jobs (or put off by unemployment).
	var homes := (Settings.TOWN_PULL + population * Settings.REGION_GROWTH) * a \
		+ spare_jobs * Settings.JOB_PULL
	# Shops and offices follow residents; industry employs the workers they don't.
	var shop_target := population * Settings.SHOP_JOBS_PER_PERSON
	demand[Tile.HOMES] = homes
	# Railway stations bring visitors (shop demand); harbours bring trade (industry).
	var stations := mini(_working_count(Tile.STATION), 2)
	var visitors: float = info(Tile.STATION).get("visitors", 0.0)
	shop_target += population * visitors * stations
	var port_jobs: int = info(Tile.HARBOUR).get("port_jobs", 0)
	var trade := port_jobs * _working_count(Tile.HARBOUR)
	# Landmarks bring tourists (more of them with an airport to fly in to).
	shop_target += population * tourism * (Settings.AIRPORT_TOURISM if airports_open > 0 else 1.0)
	# An airport brings visitors, business and freight.
	var office_boost := 1.0
	if airports_open > 0:
		shop_target += population * Settings.AIRPORT_VISITORS
		office_boost += Settings.AIRPORT_OFFICE_BOOST
		trade += Settings.AIRPORT_FREIGHT
	var b := business_appeal()
	demand[Tile.SHOPS] = _business_demand(shop_target - shop_jobs, shop_jobs, b)
	# Offices: a share of the workers who aren't in shops (see office_share). Only
	# offices that are built take workers from industry, so a town with no office
	# zone runs exactly as before.
	var office_target := maxf(workers - shop_target, 0.0) * minf(office_share() * office_boost, 1.0)
	demand[Tile.OFFICES] = _business_demand(office_target - office_jobs, office_jobs, b)
	demand[Tile.INDUSTRY] = _business_demand(workers - shop_target - office_jobs - industry_jobs + trade,
		industry_jobs, b)


func office_share() -> float:
	# The share of non-shop workers who want office work: none in a village, up
	# to OFFICE_SHARE_MAX in a city, and less where homes have no school nearby.
	var size := clampf(float(population - Settings.OFFICE_START_POP)
		/ float(Settings.OFFICE_FULL_POP - Settings.OFFICE_START_POP), 0.0, 1.0)
	return Settings.OFFICE_SHARE_MAX * size * lerpf(1.0 - Settings.OFFICE_SCHOOL_SHARE, 1.0, schooled_share())


func schooled_share() -> float:
	# 0-1: the share of residents with a school nearby.
	_update_coverage()
	var people := 0
	var schooled := 0
	for i in w * h:
		if tiles[i] == Tile.HOMES and levels[i] > 0:
			var n := units(i)
			people += n
			if covered(Service.SCHOOL, i):
				schooled += n
	return float(schooled) / people if people > 0 else 0.0


func _office_wait() -> String:
	# Why offices aren't wanted yet, in plain English.
	if population < Settings.OFFICE_START_POP:
		return "waiting, offices need a town of %d people" % Settings.OFFICE_START_POP
	if schooled_share() < 0.5:
		return "waiting, the town needs more office workers first (schools near homes bring them)"
	return "waiting, the town needs more office workers first (more residents)"


func _business_demand(gap: float, jobs_now: int, a: float) -> float:
	# Businesses expand into a gap only as keenly as taxes allow; with very high
	# taxes they start closing down.
	var d := gap * clampf(a, 0.0, 1.5) if gap > 0.0 else gap
	if a < 0.0:
		d += a * jobs_now * 0.2
	return d


func tax_word() -> String:
	# How the tax rate is going down, for the HUD. Only the town-wide things
	# (taxes, services, leisure, rubbish), so jobs or power cuts don't show up as
	# a tax problem; the happiness line covers those.
	var a := business_appeal()
	var high := tax_rate > Settings.DEFAULT_TAX_RATE + 0.005
	if a >= 1.3:
		return "attracting people"
	if a >= 0.7:
		return "worth it for the services" if high else "about right"
	if a >= 0.3:
		return "putting people off"
	if a >= 0.0:
		return "stopping growth"
	return "people are leaving" if not high else "people are leaving (high taxes, poor services)"


func services_built() -> int:
	# How many police, fire, school and hospital buildings the town has.
	var total := 0
	for n in services:
		total += int(n)
	return total


func services_needed() -> bool:
	# The town is big enough for missing services to matter (fires, or police).
	return population >= mini(Settings.FIRE_START_POP, Settings.POLICE_NEEDED_POP)


func services_word() -> String:
	# Honest words first for the cases the cover % can't explain; otherwise how
	# cover compares with what residents expect (the same gap services_feeling uses).
	if services_built() == 0:
		return "none yet" if services_needed() else "not needed yet"
	if population == 0:
		return "not needed yet"
	if service_score < 0.005:
		return "not reaching homes"
	var gap := service_score - services_expected()
	if gap >= 0.15:
		return "excellent"
	if gap >= 0.0:
		return "good"
	if gap >= -0.25:
		return "patchy"
	return "poor"


func demand_bar(t: int) -> float:
	# Demand scaled to -1..1 for the on-screen bars (relative to the town's size,
	# so a big town needs a big demand to fill a bar).
	var size := float(population) * 0.5
	if t == Tile.SHOPS:
		size = shop_jobs
	elif t == Tile.OFFICES:
		size = office_jobs
	elif t == Tile.INDUSTRY:
		size = industry_jobs
	var scale := float(_capacity_per_level(t)) * 10.0 + size * 0.1
	return clampf(float(demand[t]) / scale, -1.0, 1.0)


func _capacity_per_level(t: int) -> int:
	# A typical step of growth (the first stage), used to scale demand and shortage.
	return units_at_stage(t, 1)


func date_text() -> String:
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %d" % [MONTHS[month % 12], Settings.START_YEAR + floori(month / 12.0)]


# ------------------------------------------------------------- traffic
# A light model: no individual cars, just how many trips a day use each road tile.
#   1. Trip ends. Each home plot with a road sends its working residents to work
#      (TRAFFIC_WORK_TRIPS each) and everyone to the shops (TRAFFIC_SHOP_TRIPS);
#      a working station sends its visitors to the shops and a harbour its lorries
#      to the works. Homes near a bus depot or station make some trips by bus or
#      train instead. A plot's trips start and end at its nearest road tile.
#   2. Where they go. Shops and works are grouped into squares (at most
#      TRAFFIC_MAX_GROUPS). From each group the road network is flooded outwards
#      (steps along the roads). Each origin splits its trips between the groups by
#      size x 1 / (1 + (steps / reach)^2), so near places get most of them.
#   3. Which way. Every trip goes by a shortest way: flowing "downhill" in each
#      group's flood, split evenly wherever two ways are equally short (as water
#      drains), adding to every road tile it passes. Arriving trips are shared out
#      to the group's plots' own roads by their size.
# So spines between homes and jobs are busy, dead ends quiet, and a single link
# between two parts of town carries everything between them. Drivers don't yet
# avoid jams. Deterministic: no random numbers, everything in tile order.
#
# View only, for now: nothing here changes growth, happiness, land value or
# pollution. Hooks for later:
#   traffic_at(i)               car trips a day on map tile i (0 off the roads)
#   traffic_congestion_at(i)    trips / road capacity (1 = full)
#   traffic_band(i)             -1 not a road, 0 free-flowing, 1 busy, 2 heavy, 3 jammed
#   traffic_word(i), traffic_fix(i)   in words, for hover text ("quiet" below TRAFFIC_QUIET)
#   traffic_jammed_share()      0-1: share of the town's driving done in jams
#   traffic_trips, transit_trips   trips a day by car, and by bus or train instead
# Worked out when first asked for after anything changed (every month, after
# building or loading); never saved.

const TRAFFIC_WORDS := ["free-flowing", "busy", "heavy", "jammed"]


func traffic_map() -> PackedFloat32Array:
	_update_traffic()
	return traffic


func traffic_at(i: int) -> float:
	_update_traffic()
	return traffic[i]


func road_capacity() -> float:
	return Settings.ROAD_CAPACITY * _capacity_scale


func traffic_congestion_at(i: int) -> float:
	return traffic_at(i) / road_capacity()


func traffic_band(i: int) -> int:
	if tiles[i] != Tile.ROAD:
		return -1
	return _band_of(traffic_congestion_at(i))


func _band_of(congestion: float) -> int:
	var band := 0
	for limit: float in Settings.TRAFFIC_BANDS:
		if congestion >= limit:
			band += 1
	return band


func traffic_word(i: int) -> String:
	# "quiet", "free-flowing", "busy", "heavy" or "jammed" ("" if not a road).
	var band := traffic_band(i)
	if band < 0:
		return ""
	if traffic_quiet(i):
		return "quiet"
	var word: String = TRAFFIC_WORDS[band]
	return word


func traffic_quiet(i: int) -> bool:
	# A free-flowing road with hardly any traffic (a dead end, a back street).
	return tiles[i] == Tile.ROAD and traffic_congestion_at(i) < Settings.TRAFFIC_QUIET


func traffic_fix(i: int) -> String:
	# Honest, general advice for a heavy or jammed road ("" when it's fine).
	if traffic_band(i) < 2:
		return ""
	return "add parallel roads, or a bus depot nearby"


func traffic_jammed_share() -> float:
	_update_traffic()
	return jammed_share


func _update_traffic() -> void:
	if not _traffic_dirty:
		return
	_traffic_dirty = false
	var t0 := Time.get_ticks_usec()
	_update_road_distance()
	_update_coverage()
	_update_power()
	_build_road_graph()
	traffic.resize(w * h)
	traffic.fill(0.0)
	traffic_trips = 0
	transit_trips = 0
	jammed_share = 0.0
	var n := _road_tile.size()
	if n == 0:
		traffic_ms = (Time.get_ticks_usec() - t0) / 1000.0
		return

	# --- 1. Places to go: shops and works, grouped into squares.
	var plot_node := PackedInt32Array()     # every working shop or works plot: its road node...
	var plot_group := PackedInt32Array()    # ...its group...
	var plot_shop := PackedFloat32Array()   # ...its shop jobs (customers go by these)...
	var plot_works := PackedFloat32Array()  # ...its works jobs (the harbour's lorries go by these)...
	var plot_office := PackedFloat32Array() # ...and its office jobs
	var plot_tile := PackedInt32Array()
	for i: int in w * h:
		var t: int = tiles[i]
		if (t == Tile.SHOPS or t == Tile.INDUSTRY or t == Tile.OFFICES) and _access[i] >= 0 and _connected(i):
			var u := units(i)
			if u > 0:
				# (One entry per road the plot fronts, sharing its jobs.)
				var ways := _plot_roads(i)
				for a: int in ways:
					plot_node.append(a)
					plot_tile.append(i)
					plot_shop.append(float(u) / ways.size() if t == Tile.SHOPS else 0.0)
					plot_works.append(float(u) / ways.size() if t == Tile.INDUSTRY else 0.0)
					plot_office.append(float(u) / ways.size() if t == Tile.OFFICES else 0.0)
	var size: int = Settings.TRAFFIC_GROUP_TILES
	var group_of := {}
	while true:
		group_of.clear()
		for k: int in plot_tile.size():
			var key := (plot_tile[k] % w) / size * 4096 + (plot_tile[k] / w) / size
			if not group_of.has(key):
				group_of[key] = group_of.size()
		if group_of.size() <= Settings.TRAFFIC_MAX_GROUPS:
			break
		size *= 2
	var groups := group_of.size()
	plot_group.resize(plot_tile.size())
	var g_jobs := PackedFloat32Array()
	var g_shop := PackedFloat32Array()
	var g_works := PackedFloat32Array()
	g_jobs.resize(groups)
	g_shop.resize(groups)
	g_works.resize(groups)
	g_jobs.fill(0.0)
	g_shop.fill(0.0)
	g_works.fill(0.0)
	for k: int in plot_tile.size():
		var g: int = group_of[(plot_tile[k] % w) / size * 4096 + (plot_tile[k] / w) / size]
		plot_group[k] = g
		g_shop[g] += plot_shop[k]
		g_works[g] += plot_works[k]
		g_jobs[g] += plot_shop[k] + plot_works[k] + plot_office[k]

	# --- 2. Flood the roads from each group: steps to it from every road node.
	var dist := PackedInt32Array()
	var order := PackedInt32Array()
	var reached := PackedInt32Array()
	dist.resize(groups * n)
	dist.fill(-1)
	order.resize(groups * n)
	reached.resize(groups)
	var next := _road_next
	for g: int in groups:
		var base := g * n
		var tail := base
		for k: int in plot_node.size():
			if plot_group[k] == g and dist[base + plot_node[k]] < 0:
				dist[base + plot_node[k]] = 0
				order[tail] = plot_node[k]
				tail += 1
		var head := base
		while head < tail:
			var v := order[head]
			head += 1
			var dv := dist[base + v] + 1
			var e := v * 4
			for s: int in 4:
				var u := next[e + s]
				if u >= 0 and dist[base + u] < 0:
					dist[base + u] = dv
					order[tail] = u
					tail += 1
		reached[g] = tail - base

	# --- 3. Trips from homes (and the station and harbour), split between the groups.
	var workers: float = population * Settings.WORKER_SHARE
	var employed := clampf(float(jobs()) / workers, 0.0, 1.0) if workers > 0.0 else 0.0
	var rail := _near_station()
	var work_from := PackedFloat32Array()   # per road node: car trips to work, to the shops, lorries
	var shop_from := PackedFloat32Array()
	var lorry_from := PackedFloat32Array()
	work_from.resize(n)
	shop_from.resize(n)
	lorry_from.resize(n)
	work_from.fill(0.0)
	shop_from.fill(0.0)
	lorry_from.fill(0.0)
	var by_transit := 0.0
	for i: int in w * h:
		var t: int = tiles[i]
		var a: int = _access[i]
		if a < 0:
			continue
		if t == Tile.HOMES:
			var people := units(i)
			if people <= 0 or not _connected(i):
				continue
			var work := people * Settings.WORKER_SHARE * employed * Settings.TRAFFIC_WORK_TRIPS
			var shop := people * Settings.TRAFFIC_SHOP_TRIPS
			var share := 0.0
			if _bus_cover[i] == 1:
				share += Settings.TRAFFIC_BUS_SHARE
			if rail[i] == 1:
				share += Settings.TRAFFIC_RAIL_SHARE
			by_transit += (work + shop) * share
			var ways := _plot_roads(i)       # (split between the roads the plot fronts)
			var part := (1.0 - share) / ways.size()
			for r: int in ways:
				work_from[r] += work * part
				shop_from[r] += shop * part
		elif t == Tile.STATION and building_working(i):
			var visitors: float = info(t).get("visitors", 0.0)
			shop_from[a] += population * visitors * Settings.TRAFFIC_VISITOR_TRIPS
		elif t == Tile.HARBOUR and building_working(i):
			var port: float = info(t).get("port_jobs", 0)
			lorry_from[a] += port * Settings.TRAFFIC_HARBOUR_LORRIES
		elif t == Tile.AIRPORT and _airport_terminals.has(i):
			shop_from[a] += population * Settings.AIRPORT_VISITORS * Settings.AIRPORT_TRIPS
			lorry_from[a] += Settings.AIRPORT_FREIGHT * Settings.TRAFFIC_HARBOUR_LORRIES
	transit_trips = roundi(by_transit)

	var flow := PackedFloat32Array()        # per group, per road node: trips setting off from there
	flow.resize(groups * n)
	flow.fill(0.0)
	var arrive_shop := PackedFloat32Array() # per group: trips arriving for its shops, its works
	var arrive_works := PackedFloat32Array()
	arrive_shop.resize(groups)
	arrive_works.resize(groups)
	arrive_shop.fill(0.0)
	arrive_works.fill(0.0)
	var pull_work := PackedFloat32Array()
	var pull_shop := PackedFloat32Array()
	var pull_lorry := PackedFloat32Array()
	pull_work.resize(groups)
	pull_shop.resize(groups)
	pull_lorry.resize(groups)
	var work_r2 := 1.0 / (Settings.TRAFFIC_WORK_REACH * Settings.TRAFFIC_WORK_REACH)
	var shop_r2 := 1.0 / (Settings.TRAFFIC_SHOP_REACH * Settings.TRAFFIC_SHOP_REACH)
	var lorry_r2 := 1.0 / (Settings.TRAFFIC_LORRY_REACH * Settings.TRAFFIC_LORRY_REACH)
	var cars := 0.0
	for v: int in n:
		var work := work_from[v]
		var shop := shop_from[v]
		var lorry := lorry_from[v]
		if work <= 0.0 and shop <= 0.0 and lorry <= 0.0:
			continue
		var sum_work := 0.0
		var sum_shop := 0.0
		var sum_lorry := 0.0
		for g: int in groups:
			var d := dist[g * n + v]
			if d < 0:
				pull_work[g] = 0.0
				pull_shop[g] = 0.0
				pull_lorry[g] = 0.0
				continue
			var d2 := float(d * d)
			pull_work[g] = g_jobs[g] / (1.0 + d2 * work_r2)
			pull_shop[g] = g_shop[g] / (1.0 + d2 * shop_r2)
			pull_lorry[g] = g_works[g] / (1.0 + d2 * lorry_r2)
			sum_work += pull_work[g]
			sum_shop += pull_shop[g]
			sum_lorry += pull_lorry[g]
		# (Nowhere to go along the roads from here: those trips go out of town, off the map.)
		var kw := work / sum_work if sum_work > 0.0 else 0.0
		var ks := shop / sum_shop if sum_shop > 0.0 else 0.0
		var kl := lorry / sum_lorry if sum_lorry > 0.0 else 0.0
		for g: int in groups:
			var to_works := pull_work[g] * kw * g_works[g] / g_jobs[g] if g_jobs[g] > 0.0 else 0.0
			var to_shop := pull_work[g] * kw - to_works + pull_shop[g] * ks
			to_works += pull_lorry[g] * kl
			if to_shop + to_works > 0.0:
				flow[g * n + v] += to_shop + to_works
				arrive_shop[g] += to_shop
				arrive_works[g] += to_works
				cars += to_shop + to_works
	traffic_trips = roundi(cars)

	# --- 4. Each group's trips flow downhill to it, split evenly between equally short ways.
	var volume := PackedFloat32Array()
	volume.resize(n)
	volume.fill(0.0)
	for g: int in groups:
		var base := g * n
		for idx: int in range(base + reached[g] - 1, base - 1, -1):
			var v := order[idx]
			var f := flow[base + v]
			if f <= 0.0:
				continue
			var dv := dist[base + v]
			if dv == 0:
				continue                    # arrived (shared out to the plots below)
			volume[v] += f
			var e := v * 4
			var ways := 0
			for s: int in 4:
				var u := next[e + s]
				if u >= 0 and dist[base + u] == dv - 1:
					ways += 1
			var part := f / ways
			for s: int in 4:
				var u := next[e + s]
				if u >= 0 and dist[base + u] == dv - 1:
					flow[base + u] += part
	# Arrivals end on each plot's own road, shared by its size.
	for k: int in plot_node.size():
		var g := plot_group[k]
		var arriving := 0.0
		if g_shop[g] > 0.0:
			arriving += arrive_shop[g] * plot_shop[k] / g_shop[g]
		if g_works[g] > 0.0:
			arriving += arrive_works[g] * plot_works[k] / g_works[g]
		volume[plot_node[k]] += arriving

	var total := 0.0
	var jammed := 0.0
	var jam_level: float = Settings.TRAFFIC_BANDS[Settings.TRAFFIC_BANDS.size() - 1]
	var full := road_capacity() * jam_level
	for v: int in n:
		traffic[_road_tile[v]] = volume[v]
		total += volume[v]
		if volume[v] >= full:
			jammed += volume[v]
	jammed_share = jammed / total if total > 0.0 else 0.0
	traffic_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _plot_roads(i: int) -> PackedInt32Array:
	# The road nodes a plot's trips use: every road beside it, or else its nearest road.
	var out := PackedInt32Array()
	var x := i % w
	if x < w - 1 and _road_node[i + 1] >= 0:
		out.append(_road_node[i + 1])
	if x > 0 and _road_node[i - 1] >= 0:
		out.append(_road_node[i - 1])
	if i < w * (h - 1) and _road_node[i + w] >= 0:
		out.append(_road_node[i + w])
	if i >= w and _road_node[i - w] >= 0:
		out.append(_road_node[i - w])
	if out.is_empty() and _access[i] >= 0:
		out.append(_access[i])
	return out


func _near_station() -> PackedByteArray:
	# 1 = within SKYSCRAPER_TRANSIT tiles of a working railway station.
	var near := PackedByteArray()
	near.resize(w * h)
	near.fill(0)
	var r: int = Settings.SKYSCRAPER_TRANSIT
	for i: int in w * h:
		if tiles[i] != Tile.STATION or not building_working(i):
			continue
		var cx := i % w
		var cy := i / w
		for y: int in range(maxi(cy - r, 0), mini(cy + r, h - 1) + 1):
			for x: int in range(maxi(cx - r, 0), mini(cx + r, w - 1) + 1):
				if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
					near[y * w + x] = 1
	return near


func _build_road_graph() -> void:
	# Road tiles as a network (each joined to the roads beside it), and for every
	# tile the nearest road tile within reach (ties go to the first found, in tile order).
	if _graph_version == layout_version and _access.size() == w * h:
		return
	_graph_version = layout_version
	_road_node.resize(w * h)
	_road_node.fill(-1)
	_road_tile.clear()
	for i: int in w * h:
		if tiles[i] == Tile.ROAD:
			_road_node[i] = _road_tile.size()
			_road_tile.append(i)
	var n := _road_tile.size()
	_road_next.resize(n * 4)
	_road_next.fill(-1)
	for v: int in n:
		var i := _road_tile[v]
		var x := i % w
		if x < w - 1:
			_road_next[v * 4] = _road_node[i + 1]
		if x > 0:
			_road_next[v * 4 + 1] = _road_node[i - 1]
		if i < w * (h - 1):
			_road_next[v * 4 + 2] = _road_node[i + w]
		if i >= w:
			_road_next[v * 4 + 3] = _road_node[i - w]
	_access.resize(w * h)
	_access.fill(-1)
	var steps := PackedByteArray()
	steps.resize(w * h)
	steps.fill(255)
	var queue := PackedInt32Array()
	queue.resize(w * h)
	var tail := 0
	for v: int in n:
		var i := _road_tile[v]
		_access[i] = v
		steps[i] = 0
		queue[tail] = i
		tail += 1
	var head := 0
	while head < tail:
		var i := queue[head]
		head += 1
		var d := steps[i] + 1
		if d > Settings.ROAD_REACH + 1:      # (one further for plots reached by bus)
			continue
		var x := i % w
		for k: int in [i + 1 if x < w - 1 else -1, i - 1 if x > 0 else -1, i + w if i < w * (h - 1) else -1,
				i - w if i >= w else -1]:
			if k >= 0 and steps[k] == 255:
				steps[k] = d
				_access[k] = _access[i]
				queue[tail] = k
				tail += 1


# ------------------------------------------------------------- road reach

func _update_road_distance() -> void:
	# Spread outwards from every road tile, counting steps (up to ROAD_REACH).
	if not _roads_dirty:
		return
	_roads_dirty = false
	_road_dist.resize(w * h)
	_road_dist.fill(255)
	var queue: Array[int] = []
	for i in w * h:
		if tiles[i] == Tile.ROAD:
			_road_dist[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var d := _road_dist[i]
		if d >= Settings.ROAD_REACH + 1:      # one further, for bus routes
			continue
		var x := i % w
		if x > 0:
			_reach(i - 1, d + 1, queue)
		if x < w - 1:
			_reach(i + 1, d + 1, queue)
		if i >= w:
			_reach(i - w, d + 1, queue)
		if i < w * (h - 1):
			_reach(i + w, d + 1, queue)


func _reach(n: int, d: int, queue: Array[int]) -> void:
	if _road_dist[n] > d:
		_road_dist[n] = d
		queue.append(n)


# ------------------------------------------------------------- save / load

func to_save() -> Dictionary:
	return {
		"money": money,
		"difficulty": difficulty,
		"debt": debt,
		"debt_peak": debt_peak,
		"month": month,
		"tax_rate": tax_rate,
		"tiles": Array(tiles),
		"levels": Array(levels),
		"density": Array(density),
		"district": Array(district),
		"decline": Array(decline),
		"abandoned": Array(abandoned),
		"funding": funding.duplicate(),
		# Last month's budget, so a loaded city shows its balance straight away.
		"last_income": last_income,
		"last_upkeep": last_upkeep,
		"last_loan": last_loan,
		"last_interest": last_interest,
	}


func from_save(data: Dictionary) -> void:
	var saved_tiles: Array = data.get("tiles", [])
	var saved_levels: Array = data.get("levels", [])
	tiles.fill(Tile.EMPTY)
	levels.fill(0)
	for i in mini(saved_tiles.size(), tiles.size()):
		var t: int = int(saved_tiles[i])
		tiles[i] = t if t >= Tile.EMPTY and t <= LAST_TILE and water[i] == 0 else Tile.EMPTY
	for i in mini(saved_levels.size(), levels.size()):
		levels[i] = clampi(int(saved_levels[i]), 0, 8) if is_zone(tiles[i]) else 0
	var saved_district: Array = data.get("district", [])
	district.fill(0)
	for i in mini(saved_district.size(), district.size()):
		district[i] = clampi(int(saved_district[i]), 0, 2)
	var saved_density: Array = data.get("density", [])
	if saved_density.size() == density.size():
		for i in density.size():
			density[i] = clampi(int(saved_density[i]), 0, 2) if is_zone(tiles[i]) else 1
			levels[i] = mini(levels[i], max_level(i)) if is_zone(tiles[i]) else 0
	else:
		# A save from before density zoning: pick the density that matches what's built.
		for i in density.size():
			var old: int = levels[i]
			density[i] = 1
			if tiles[i] == Tile.HOMES or tiles[i] == Tile.SHOPS:   # (offices came long after)
				if old >= 1 and old <= 2:
					density[i] = 0                    # villas / small shops: low
				elif old >= 5:
					density[i] = 2                    # modern flats, towers: high
				var start: int = Settings.DENSITY_START[density[i]]
				levels[i] = maxi(old - start, 1) if old > 0 else 0
	# Abandoned buildings and decline (saves from before them have none).
	var saved_decline: Array = data.get("decline", [])
	var saved_abandoned: Array = data.get("abandoned", [])
	decline.fill(0)
	abandoned.fill(0)
	for i in mini(saved_decline.size(), decline.size()):
		if is_zone(tiles[i]) and levels[i] > 0:
			decline[i] = clampi(int(saved_decline[i]), 0, 255)
	for i in mini(saved_abandoned.size(), abandoned.size()):
		if is_zone(tiles[i]) and levels[i] > 0 and int(saved_abandoned[i]) == 1:
			abandoned[i] = 1
			decline[i] = 0
	# Saves from before difficulty and loans load as Normal (running costs x1, as
	# they always were) with nothing owed; their money is left exactly as saved.
	difficulty = clampi(int(data.get("difficulty", Settings.DEFAULT_DIFFICULTY)), 0, Settings.DIFFICULTIES.size() - 1)
	money = int(data.get("money", start_money(difficulty)))
	debt = maxi(int(data.get("debt", 0)), 0)
	debt_peak = maxi(int(data.get("debt_peak", debt)), debt) if debt > 0 else 0
	last_income = int(data.get("last_income", 0))     # (older saves: no balance until a month has passed)
	last_upkeep = int(data.get("last_upkeep", 0))
	last_loan = int(data.get("last_loan", 0))
	last_interest = int(data.get("last_interest", 0))
	month = int(data.get("month", 0))
	tax_rate = float(data.get("tax_rate", Settings.DEFAULT_TAX_RATE))
	var saved_funding: Array = data.get("funding", [])
	for s in 4:
		funding[s] = clampf(float(saved_funding[s]), 0.0, Settings.MAX_FUNDING) \
			if s < saved_funding.size() else 1.0
	grew.clear()
	shrank.clear()
	abandoned_now.clear()
	burned.clear()
	_roads_dirty = true
	_power_dirty = true
	_value_dirty = true
	_coverage_dirty = true
	_traffic_dirty = true             # (traffic isn't saved: it's worked out again from the town)
	layout_version += 1
	recount()
