extends RefCounted
## The city's rules: road access, growth, demand, land value, density, prices,
## taxes and upkeep.
## Knows nothing about drawing, so the visuals can change (2D to 3D)
## without touching any of this.

const Settings = preload("res://scripts/settings.gd")

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE, PARK,
	POLICE, FIRE, SCHOOL, HOSPITAL,
	WIND, SOLAR, GAS, NUCLEAR, WATER_PUMP, WATER_TOWER, LANDFILL, RECYCLING,
	GOLF, LIBRARY, MUSEUM, STADIUM, MARINA, TOWN_HALL, BUS_DEPOT, STATION, HARBOUR }
# Which entry in Settings.BUILDINGS describes each of the other buildings.
const BUILDING_KEYS := {
	Tile.POWER_PLANT: "coal", Tile.GAS: "gas", Tile.NUCLEAR: "nuclear", Tile.WIND: "wind",
	Tile.SOLAR: "solar", Tile.WATER_PUMP: "water_pump", Tile.WATER_TOWER: "water_tower",
	Tile.LANDFILL: "landfill", Tile.RECYCLING: "recycling", Tile.GOLF: "golf",
	Tile.LIBRARY: "library", Tile.MUSEUM: "museum", Tile.STADIUM: "stadium", Tile.MARINA: "marina",
	Tile.TOWN_HALL: "town_hall", Tile.BUS_DEPOT: "bus_depot", Tile.STATION: "station",
	Tile.HARBOUR: "harbour",
}
const LAST_TILE := Tile.HARBOUR
# What residents complain about, by happiness part: [the complaint, how to fix it].
# Kept in one place so the HUD, zone hover text and advisors all say the same thing.
const COMPLAINTS := {
	"taxes": ["taxes too high for the services", "lower the tax rate, or build services near homes"],
	"services": ["not enough police, fire, schools or hospitals", "build services near homes, or fund them more"],
	"rubbish": ["rubbish piling up", "build a landfill or recycling centre"],
	"jobs": ["not enough jobs", "zone more shops or industry"],
	"housing": ["homes too dear (housing shortage)", "zone more homes, or zone them denser"],
	"power": ["homes without power", "build another power plant, or link the homes to one"],
	"water": ["homes without water", "build a water pump or tower"],
}
# The parts businesses weigh too. The rest (jobs, housing, power and water at
# home) only residents feel, so they don't put shops and industry off.
const BUSINESS_PARTS: Array[String] = ["taxes", "services", "leisure", "rubbish"]
enum Service { POLICE, FIRE, SCHOOL, HOSPITAL }   # same order as the service tiles
enum Growth { NONE, GROWING, WAITING, BLOCKED, FULL }   # for the growth map

# --- The city ---
var w := 0
var h := 0
var water := PackedByteArray()
var tiles := PackedByteArray()        # Tile enum per map tile
var levels := PackedByteArray()       # zones: 0 = empty plot, then 1 up to the density's maximum
var density := PackedByteArray()      # zones: 0 = low, 1 = medium, 2 = high
var district := PackedByteArray()     # any tile: 0 = normal, 1 = conservation area, 2 = CBD
var money := 0
var month := 0                        # months since the city was founded
var tax_rate := Settings.DEFAULT_TAX_RATE

# --- Worked out from the city ---
var population := 0
var shop_jobs := 0
var industry_jobs := 0
var road_tiles := 0
var plants := 0                       # anything that makes power
var park_tiles := 0
var counts := {}                      # tile type -> how many the town has
var power_supply := 0                 # zone levels the plants can power
var water_supply := 0                 # zone levels the pumps and towers can supply
var water_used := 0
var rubbish_made := 0                 # in residents' worth
var rubbish_capacity := 0
var leisure_appeal := 0.0             # extra appeal from leisure buildings and landmarks
# How residents feel, 0 (furious) to 1 (delighted): the single summary of taxes,
# services, leisure, rubbish, jobs, housing, power and water. It sets how many
# people want to move in (see appeal()). Worked out again every month and
# whenever taxes change, from the town itself, so it needs no saving.
var happiness := 2.0 / 3.0
# What happiness is made of, in appeal points: part name -> amount (below 0 = a
# complaint). Names: taxes, services, leisure, rubbish, jobs, housing, power, water.
var happiness_parts := {}
var power_used := 0                   # zone levels currently built
# How many more residents / shop jobs / industry jobs the town wants.
# Negative means too many already.
var demand := {Tile.HOMES: 0.0, Tile.SHOPS: 0.0, Tile.INDUSTRY: 0.0}
var last_income := 0
var last_upkeep := 0
var grew := PackedInt32Array()        # plots that grew last month
var shrank := PackedInt32Array()      # plots that shrank last month
var land_value := PackedFloat32Array() # 0 (worst) to 1 (best) for every tile
# How short of space each zone type is: 0 = plenty of low-rise room left,
# 1 = demand well beyond what low-rise plots can take (so plots build upwards).
var shortage := {Tile.HOMES: 0.0, Tile.SHOPS: 0.0, Tile.INDUSTRY: 0.0}
var average_home_price := 0
var _sea_near := PackedFloat32Array() # 1 by the sea, fading to 0 inland
var _value_dirty := true
var funding: Array[float] = [1.0, 1.0, 1.0, 1.0]   # per service: 0 = closed, 1 = 100%
var services := [0, 0, 0, 0]          # how many of each service the town has
var coverage := PackedFloat32Array()  # per service, per tile: 0 (none) to 1 (fully covered)
var burned := PackedInt32Array()      # plots that burned down last month
var service_score := 0.0              # 0-1: how well services cover the town's homes, on average
var _coverage_dirty := true
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


func setup(width: int, height: int, water_map: PackedByteArray) -> void:
	w = width
	h = height
	water = water_map
	tiles.resize(w * h)
	levels.resize(w * h)
	density.resize(w * h)
	district.resize(w * h)
	_transit.resize(w * h)
	powered.resize(w * h)
	_net_id.resize(w * h)
	watered.resize(w * h)
	_wnet_id.resize(w * h)
	_bus_cover.resize(w * h)
	land_value.resize(w * h)
	coverage.resize(w * h * 4)
	_measure_sea()
	reset()


func reset() -> void:
	tiles.fill(Tile.EMPTY)
	levels.fill(0)
	density.fill(1)
	district.fill(0)
	money = Settings.START_MONEY
	month = 0
	tax_rate = Settings.DEFAULT_TAX_RATE
	last_income = 0
	last_upkeep = 0
	grew.clear()
	shrank.clear()
	burned.clear()
	funding = [1.0, 1.0, 1.0, 1.0]
	_roads_dirty = true
	_power_dirty = true
	_value_dirty = true
	_coverage_dirty = true
	layout_version += 1
	shortage = {Tile.HOMES: 0.0, Tile.SHOPS: 0.0, Tile.INDUSTRY: 0.0}
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
		return
	tiles[i] = t
	levels[i] = 0                     # a new zone starts as an empty plot
	density[i] = new_density if is_zone(t) else 1
	_roads_dirty = true
	_power_dirty = true
	_water_dirty = true
	_value_dirty = true
	_coverage_dirty = true
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
	return text


func growth_state(i: int) -> int:
	# For the growth map: GROWING, WAITING (demand, space or land value),
	# BLOCKED (needs a road or power), FULL, or NONE for anything but zones.
	if not is_zone(tiles[i]):
		return Growth.NONE
	var check := _zone_check(i)
	var state: int = check[0]
	return state


func _zone_check(i: int) -> Array:
	# [Growth state, reason in plain English] for a zone plot.
	var t: int = tiles[i]
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
			return [Growth.WAITING, "land value too low to build taller (the sea, parks and shops nearby raise it; industry lowers it)"]
		if density[i] < 2 and shortage_for(t) <= 0.0:
			return [Growth.WAITING, "will build taller when the town runs short of space"]
	var missing := _missing_services(i)
	if missing != "":
		return [Growth.GROWING, "growing slowly, no %s nearby" % missing]
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
	return n


func units(i: int) -> int:
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
	_update_road_distance()
	_update_coverage()
	_update_water()
	var wanted: Dictionary = demand.duplicate()

	# How much more the plots that can grow freely (road + power) could still take.
	var room: Dictionary = {Tile.HOMES: 0.0, Tile.SHOPS: 0.0, Tile.INDUSTRY: 0.0}
	for i in zones:
		if not _connected(i) or powered[i] == 0:
			continue
		var t: int = tiles[i]
		var free_top: int = mini(stage_at(i, max_level(i)), Settings.FREE_STAGE)
		var extra: int = units_at_stage(t, free_top) - units(i)
		if extra > 0:
			room[t] = float(room[t]) + extra
	# Short of space when demand is more than that room can take.
	for t: int in [Tile.HOMES, Tile.SHOPS, Tile.INDUSTRY]:
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
				and _connected(i) and powered[i] == 1:
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
		elif lv > 0 and (not connected or not has_power or want < -down_step * 2.0) \
				and _rng.randf() < Settings.DECLINE_CHANCE * (1.6 - local_service(i)):
			levels[i] = lv - 1
			wanted[t] = want + down_step
			shrank.append(i)


func _collect_taxes() -> void:
	# Valuable land pays more: from 0.6x on the worst land to 1.4x on the best.
	_update_land_value()
	var taxable := 0.0
	for i in w * h:
		if is_zone(tiles[i]) and levels[i] > 0:
			taxable += units(i) * (0.6 + 0.8 * land_value[i])
	last_income = roundi(taxable * tax_rate * Settings.TAX_BASE)
	last_upkeep = roundi(road_tiles * Settings.ROAD_UPKEEP + park_tiles * Settings.PARK_UPKEEP
		+ service_upkeep() + building_upkeep())
	money += last_income - last_upkeep


# ------------------------------------------------------------- city numbers

func recount() -> void:
	population = 0
	shop_jobs = 0
	industry_jobs = 0
	road_tiles = 0
	plants = 0
	park_tiles = 0
	power_used = 0
	power_supply = 0
	water_supply = 0
	services = [0, 0, 0, 0]
	counts = {}
	for i in w * h:
		var t: int = tiles[i]
		counts[t] = int(counts.get(t, 0)) + 1
		power_used += power_use(i)
		if is_service(t):
			services[t - Tile.POLICE] += 1
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
	_update_power()
	_update_water()
	_measure_rubbish()
	_measure_leisure()
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
	return t == Tile.HOMES or t == Tile.SHOPS or t == Tile.INDUSTRY


func is_service(t: int) -> bool:
	return t >= Tile.POLICE and t <= Tile.HOSPITAL


func power_use(i: int) -> int:
	# Zones use one unit per stage; services and other buildings a fixed amount.
	var t: int = tiles[i]
	if is_zone(t):
		return stage(i)
	if is_service(t):
		return Settings.SERVICE_POWER
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
	# Power plants just work. Everything else needs a road, and power if it uses any.
	var t: int = tiles[i]
	if makes_power(t):
		return true
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
	for i in w * h:
		var t: int = tiles[i]
		if is_building(t):
			var a: float = info(t).get("appeal", 0.0)
			if a > 0.0 and building_working(i):
				total += a
	leisure_appeal = minf(total, Settings.LEISURE_APPEAL_MAX)


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
				var use: int = stage(i)
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
	var f: float = funding[tiles[i] - Tile.POLICE]
	return near_road(i) and powered[i] == 1 and f > 0.0


func service_status(i: int) -> String:
	var f: float = funding[tiles[i] - Tile.POLICE]
	if f <= 0.0:
		return "closed (no funding)"
	if not near_road(i):
		return "not working, needs a road within %d tiles" % Settings.ROAD_REACH
	_update_power()
	if powered[i] == 0:
		return "not working, no power"
	return "working"


func service_reach_m(s: int, cell_m: float) -> int:
	# How far a service reaches at its current funding, in metres.
	return roundi(_service_radius(s) * cell_m)


func _service_radius(s: int) -> float:
	var r: float = Settings.SERVICE_RADIUS[s]
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
		total += each * funding[s] * int(services[s])
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
		var s: int = tiles[i] - Tile.POLICE
		var radius := _service_radius(s)
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
	# no hospital (homes).
	var f := 1.0
	var t: int = tiles[i]
	if (t == Tile.HOMES or t == Tile.SHOPS) and population >= Settings.POLICE_NEEDED_POP \
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
	if (t == Tile.HOMES or t == Tile.SHOPS) and population >= Settings.POLICE_NEEDED_POP \
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
	for i in w * h:
		land_value[i] = Settings.BASE_LAND_VALUE + Settings.SEA_BONUS * _sea_near[i]
	for i in w * h:
		var t := tiles[i]
		match t:
			Tile.PARK:
				_spread(i, 3, Settings.PARK_BONUS)
			Tile.SHOPS:
				if levels[i] > 0:
					_spread(i, 3, Settings.SHOP_BONUS * stage(i))
			Tile.INDUSTRY:
				_spread(i, 4, -Settings.INDUSTRY_PENALTY * maxi(stage(i), 1))
			_:
				if is_building(t):
					var amount: float = info(t).get("value", 0.0)
					var radius: int = info(t).get("radius", 0)
					if amount != 0.0:
						_spread(i, radius, amount)
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


func _spread(i: int, radius: int, amount: float) -> void:
	# Add an effect to every tile within the radius, strongest close by.
	var cx := i % w
	var cy := i / w
	for y in range(maxi(cy - radius, 0), mini(cy + radius, h - 1) + 1):
		for x in range(maxi(cx - radius, 0), mini(cx + radius, w - 1) + 1):
			var d := Vector2(x - cx, y - cy).length()
			if d <= radius + 0.5:
				land_value[y * w + x] += amount * (1.0 - d / (radius + 1.0))


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
	return shop_jobs + industry_jobs


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
	# Pollution can feed in here later as one more part, e.g.
	#   parts["pollution"] = -(share of residents in polluted air) * Settings.POLLUTION_EFFECT
	# plus a "pollution" entry in COMPLAINTS (and in BUSINESS_PARTS if firms mind it too).
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
	var b := business_appeal()
	demand[Tile.SHOPS] = _business_demand(shop_target - shop_jobs, shop_jobs, b)
	demand[Tile.INDUSTRY] = _business_demand(workers - shop_target - industry_jobs + trade, industry_jobs, b)


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
		"month": month,
		"tax_rate": tax_rate,
		"tiles": Array(tiles),
		"levels": Array(levels),
		"density": Array(density),
		"district": Array(district),
		"funding": funding.duplicate(),
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
			if tiles[i] == Tile.HOMES or tiles[i] == Tile.SHOPS:
				if old >= 1 and old <= 2:
					density[i] = 0                    # villas / small shops: low
				elif old >= 5:
					density[i] = 2                    # modern flats, towers: high
				var start: int = Settings.DENSITY_START[density[i]]
				levels[i] = maxi(old - start, 1) if old > 0 else 0
	money = int(data.get("money", Settings.START_MONEY))
	month = int(data.get("month", 0))
	tax_rate = float(data.get("tax_rate", Settings.DEFAULT_TAX_RATE))
	var saved_funding: Array = data.get("funding", [])
	for s in 4:
		funding[s] = clampf(float(saved_funding[s]), 0.0, Settings.MAX_FUNDING) \
			if s < saved_funding.size() else 1.0
	grew.clear()
	shrank.clear()
	burned.clear()
	_roads_dirty = true
	_power_dirty = true
	_value_dirty = true
	_coverage_dirty = true
	layout_version += 1
	recount()
