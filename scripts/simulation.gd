extends RefCounted
## The city's rules: road access, growth, demand, land value, density, prices,
## taxes and upkeep.
## Knows nothing about drawing, so the visuals can change (2D to 3D)
## without touching any of this.

const Settings = preload("res://scripts/settings.gd")

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE, PARK }

# --- The city ---
var w := 0
var h := 0
var water := PackedByteArray()
var tiles := PackedByteArray()        # Tile enum per map tile
var levels := PackedByteArray()       # zones: 0 = empty plot, then 1 up to the density's maximum
var density := PackedByteArray()      # zones: 0 = low, 1 = medium, 2 = high
var money := 0
var month := 0                        # months since the city was founded
var tax_rate := Settings.DEFAULT_TAX_RATE

# --- Worked out from the city ---
var population := 0
var shop_jobs := 0
var industry_jobs := 0
var road_tiles := 0
var plants := 0
var park_tiles := 0
var power_supply := 0                 # zone levels the plants can power
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
var layout_version := 0               # goes up whenever a tile changes type (roads, zones...)

var _road_dist := PackedByteArray()   # tiles to the nearest road (255 = far)
var _roads_dirty := true
var powered := PackedByteArray()      # 1 = this tile has electricity
var _net_id := PackedInt32Array()     # which power network a tile is on (-1 = none)
var _net_spare: Array[int] = []       # spare power on each network
var _power_dirty := true
var _rng := RandomNumberGenerator.new()


func setup(width: int, height: int, water_map: PackedByteArray) -> void:
	w = width
	h = height
	water = water_map
	tiles.resize(w * h)
	levels.resize(w * h)
	density.resize(w * h)
	powered.resize(w * h)
	_net_id.resize(w * h)
	land_value.resize(w * h)
	_measure_sea()
	reset()


func reset() -> void:
	tiles.fill(Tile.EMPTY)
	levels.fill(0)
	density.fill(1)
	money = Settings.START_MONEY
	month = 0
	tax_rate = Settings.DEFAULT_TAX_RATE
	last_income = 0
	last_upkeep = 0
	grew.clear()
	shrank.clear()
	_roads_dirty = true
	_power_dirty = true
	_value_dirty = true
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
		return
	tiles[i] = t
	levels[i] = 0                     # a new zone starts as an empty plot
	density[i] = new_density if is_zone(t) else 1
	_roads_dirty = true
	_power_dirty = true
	_value_dirty = true
	layout_version += 1


func has_road_access(i: int) -> bool:
	_update_road_distance()
	return _road_dist[i] <= Settings.ROAD_REACH


func road_reach_map() -> PackedByteArray:
	# Tiles to the nearest road for every map tile (255 = far away).
	_update_road_distance()
	return _road_dist


func zone_status(i: int) -> String:
	# A plain-English reason for what a zone plot is doing.
	var t: int = tiles[i]
	if not has_road_access(i):
		return "won't grow, needs a road within %d tiles" % Settings.ROAD_REACH
	_update_power()
	if powered[i] == 0:
		if _net_id[i] < 0:
			return "no power, link it to a power plant (roads, zones and power lines carry power)"
		return "no power, the power plant is full, build another"
	var lv: int = levels[i]
	if lv < max_level(i) and _net_spare[_net_id[i]] <= 0:
		return "waiting, the power plant is full, build another"
	if lv >= max_level(i):
		if t != Tile.INDUSTRY and density[i] < 2:
			return "fully built for %s density (zone it higher to let it grow more)" % density_name(i)
		return "fully built up"
	var next_stage: int = stage_at(i, lv + 1)
	if demand_for(t) < step_size(i) * 0.5:
		match t:
			Tile.HOMES:
				return "waiting, the town needs more jobs first"
			Tile.SHOPS:
				return "waiting, the town needs more residents first"
			Tile.INDUSTRY:
				return "waiting, the town needs more workers first"
	if next_stage > Settings.FREE_STAGE:
		_update_land_value()
		var needed: float = Settings.TALL_VALUE_NEEDED[next_stage]
		if land_value[i] < needed:
			return "land value too low to build taller (the sea, parks and shops nearby raise it; industry lowers it)"
		if density[i] < 2 and shortage_for(t) <= 0.0:
			return "will build taller when the town runs short of space"
	return "growing"


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
	if tiles[i] == Tile.INDUSTRY:
		return 3
	var m: int = Settings.DENSITY_MAX_LEVEL[density[i]]
	return m


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
	if not grew.is_empty() or not shrank.is_empty():
		_power_dirty = true
		_value_dirty = true       # taller shops and industry change the land around them
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
	var wanted: Dictionary = demand.duplicate()

	# How much more the plots that can grow freely (road + power) could still take.
	var room: Dictionary = {Tile.HOMES: 0.0, Tile.SHOPS: 0.0, Tile.INDUSTRY: 0.0}
	for i in zones:
		if _road_dist[i] > Settings.ROAD_REACH or powered[i] == 0:
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
				and _road_dist[i] <= Settings.ROAD_REACH and powered[i] == 1:
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
		var allowed: bool = density[i] == 2 or short > 0.0
		if allowed and spare > 0 and want >= step * 0.5 and land_value[i] >= needed \
				and _rng.randf() < Settings.TALL_GROWTH_CHANCE * (0.5 + short):
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
		var connected: bool = _road_dist[i] <= Settings.ROAD_REACH
		var has_power: bool = powered[i] == 1
		var spare: int = _net_spare[_net_id[i]] if _net_id[i] >= 0 else 0
		var want: float = wanted[t]
		var can_rise: bool = lv < max_level(i)
		var next_stage: int = stage_at(i, lv + 1) if can_rise else 0
		var step: int = step_size(i)
		var down_step: int = units(i) - units_at_stage(t, stage_at(i, lv - 1)) if lv > 0 else 0
		if connected and has_power and spare > 0 and can_rise and next_stage <= Settings.FREE_STAGE \
				and want >= step * 0.5 and _rng.randf() < Settings.GROWTH_CHANCE:
			levels[i] = lv + 1
			wanted[t] = want - step
			_net_spare[_net_id[i]] -= 1
			grew.append(i)
		elif lv > 0 and (not connected or not has_power or want < -down_step * 2.0) \
				and _rng.randf() < Settings.DECLINE_CHANCE:
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
	last_upkeep = roundi(road_tiles * Settings.ROAD_UPKEEP + plants * Settings.POWER_PLANT_UPKEEP
		+ park_tiles * Settings.PARK_UPKEEP)
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
	for i in w * h:
		if is_zone(tiles[i]):
			power_used += stage(i)
		match tiles[i]:
			Tile.ROAD:
				road_tiles += 1
			Tile.POWER_PLANT:
				plants += 1
			Tile.PARK:
				park_tiles += 1
			Tile.HOMES:
				population += units(i)
			Tile.SHOPS:
				shop_jobs += units(i)
			Tile.INDUSTRY:
				industry_jobs += units(i)
	power_supply = plants * Settings.POWER_PER_PLANT
	_update_power()
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
			Tile.POWER_PLANT:
				_spread(i, 5, -Settings.PLANT_PENALTY)
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
	powered.fill(0)
	_net_id.fill(-1)
	_net_spare.clear()
	for start in w * h:
		if tiles[start] != Tile.POWER_PLANT or _net_id[start] != -1:
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
			if tiles[i] == Tile.POWER_PLANT:
				left += Settings.POWER_PER_PLANT
		for i in members:
			if is_zone(tiles[i]):
				var use: int = stage(i)
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


func _update_demand() -> void:
	var workers := population * Settings.WORKER_SHARE
	# People move in when there are jobs (plus a pull to get the town started).
	var homes := (jobs() + Settings.TOWN_PULL) / Settings.WORKER_SHARE - population
	# Shops follow residents.
	var shops := population * Settings.SHOP_JOBS_PER_PERSON - shop_jobs
	# Industry soaks up workers that shops don't employ.
	var industry := workers + Settings.INDUSTRY_PULL - jobs()

	# Taxes above the default put people and businesses off (and below, attract them).
	var tax_effect := maxf(0.0, 1.0 - (tax_rate - Settings.DEFAULT_TAX_RATE) * Settings.TAX_DEMAND_EFFECT)
	demand[Tile.HOMES] = homes * tax_effect if homes > 0 else homes
	demand[Tile.SHOPS] = shops * tax_effect if shops > 0 else shops
	demand[Tile.INDUSTRY] = industry * tax_effect if industry > 0 else industry


func demand_bar(t: int) -> float:
	# Demand scaled to -1..1 for the on-screen bars.
	var scale := float(_capacity_per_level(t)) * 10.0
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
		if d >= Settings.ROAD_REACH:
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
	}


func from_save(data: Dictionary) -> void:
	var saved_tiles: Array = data.get("tiles", [])
	var saved_levels: Array = data.get("levels", [])
	tiles.fill(Tile.EMPTY)
	levels.fill(0)
	for i in mini(saved_tiles.size(), tiles.size()):
		var t: int = int(saved_tiles[i])
		tiles[i] = t if t >= Tile.EMPTY and t <= Tile.PARK and water[i] == 0 else Tile.EMPTY
	for i in mini(saved_levels.size(), levels.size()):
		levels[i] = clampi(int(saved_levels[i]), 0, 6) if is_zone(tiles[i]) else 0
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
	grew.clear()
	shrank.clear()
	_roads_dirty = true
	_power_dirty = true
	_value_dirty = true
	layout_version += 1
	recount()
