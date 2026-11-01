extends RefCounted
## The city's rules: road access, growth, demand, taxes and upkeep.
## Knows nothing about drawing, so the visuals can change (2D to 3D)
## without touching any of this.

const Settings = preload("res://scripts/settings.gd")

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE, PARK }

# --- The city ---
var w := 0
var h := 0
var water := PackedByteArray()
var tiles := PackedByteArray()        # Tile enum per map tile
var levels := PackedByteArray()       # zones: 0 = empty plot, 1-3 = how built-up
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
	powered.resize(w * h)
	_net_id.resize(w * h)
	reset()


func reset() -> void:
	tiles.fill(Tile.EMPTY)
	levels.fill(0)
	money = Settings.START_MONEY
	month = 0
	tax_rate = Settings.DEFAULT_TAX_RATE
	last_income = 0
	last_upkeep = 0
	grew.clear()
	shrank.clear()
	_roads_dirty = true
	_power_dirty = true
	_rng.randomize()
	recount()


# ------------------------------------------------------------- player actions

func set_tile(i: int, t: int) -> void:
	if tiles[i] == t:
		return
	tiles[i] = t
	levels[i] = 0                     # a new zone starts as an empty plot
	_roads_dirty = true
	_power_dirty = true


func has_road_access(i: int) -> bool:
	_update_road_distance()
	return _road_dist[i] <= Settings.ROAD_REACH


func road_reach_map() -> PackedByteArray:
	# Tiles to the nearest road for every map tile (255 = far away).
	_update_road_distance()
	return _road_dist


func zone_status(i: int) -> String:
	# A plain-English reason for what a zone plot is doing.
	var t := tiles[i]
	if not has_road_access(i):
		return "won't grow, needs a road within %d tiles" % Settings.ROAD_REACH
	_update_power()
	if powered[i] == 0:
		if _net_id[i] < 0:
			return "no power, link it to a power plant (roads, zones and power lines carry power)"
		return "no power, the power plant is full, build another"
	if levels[i] < Settings.MAX_LEVEL and _net_spare[_net_id[i]] <= 0:
		return "waiting, the power plant is full, build another"
	if levels[i] >= Settings.MAX_LEVEL:
		return "fully grown"
	if demand[t] < _capacity_per_level(t) * 0.5:
		match t:
			Tile.HOMES:
				return "waiting, the town needs more jobs first"
			Tile.SHOPS:
				return "waiting, the town needs more residents first"
			Tile.INDUSTRY:
				return "waiting, the town needs more workers first"
	return "growing"


func change_tax(step: float) -> void:
	tax_rate = clampf(snappedf(tax_rate + step, 0.01), 0.0, Settings.MAX_TAX_RATE)
	_update_demand()


# ------------------------------------------------------------ monthly update

func tick() -> void:
	month += 1
	_update_road_distance()
	_power_dirty = true
	recount()
	_grow()
	_power_dirty = true
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
	var wanted := demand.duplicate()
	for i in zones:
		var t := tiles[i]
		var lv := levels[i]
		var size := float(_capacity_per_level(t))
		var connected := _road_dist[i] <= Settings.ROAD_REACH
		var has_power := powered[i] == 1
		var spare := _net_spare[_net_id[i]] if _net_id[i] >= 0 else 0
		if connected and has_power and spare > 0 and lv < Settings.MAX_LEVEL \
				and wanted[t] >= size * 0.5 and _rng.randf() < Settings.GROWTH_CHANCE:
			levels[i] = lv + 1
			wanted[t] -= size
			_net_spare[_net_id[i]] -= 1
			grew.append(i)
		elif lv > 0 and (not connected or not has_power or wanted[t] < -size * 2.0) \
				and _rng.randf() < Settings.DECLINE_CHANCE:
			levels[i] = lv - 1
			wanted[t] += size
			shrank.append(i)


func _collect_taxes() -> void:
	last_income = roundi((population + jobs()) * tax_rate * Settings.TAX_BASE)
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
		var lv := levels[i]
		if is_zone(tiles[i]):
			power_used += lv
		match tiles[i]:
			Tile.ROAD:
				road_tiles += 1
			Tile.POWER_PLANT:
				plants += 1
			Tile.PARK:
				park_tiles += 1
			Tile.HOMES:
				population += lv * Settings.PEOPLE_PER_LEVEL
			Tile.SHOPS:
				shop_jobs += lv * Settings.SHOP_JOBS_PER_LEVEL
			Tile.INDUSTRY:
				industry_jobs += lv * Settings.INDUSTRY_JOBS_PER_LEVEL
	power_supply = plants * Settings.POWER_PER_PLANT
	_update_power()
	_update_demand()


func is_zone(t: int) -> bool:
	return t == Tile.HOMES or t == Tile.SHOPS or t == Tile.INDUSTRY


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
				if levels[i] <= left:
					left -= levels[i]
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
	match t:
		Tile.HOMES:
			return Settings.PEOPLE_PER_LEVEL
		Tile.SHOPS:
			return Settings.SHOP_JOBS_PER_LEVEL
		Tile.INDUSTRY:
			return Settings.INDUSTRY_JOBS_PER_LEVEL
	return 0


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
	}


func from_save(data: Dictionary) -> void:
	var saved_tiles: Array = data.get("tiles", [])
	var saved_levels: Array = data.get("levels", [])
	tiles.fill(Tile.EMPTY)
	levels.fill(0)
	for i in mini(saved_tiles.size(), tiles.size()):
		tiles[i] = int(saved_tiles[i])
	for i in mini(saved_levels.size(), levels.size()):
		levels[i] = int(saved_levels[i])
	money = int(data.get("money", Settings.START_MONEY))
	month = int(data.get("month", 0))
	tax_rate = float(data.get("tax_rate", Settings.DEFAULT_TAX_RATE))
	grew.clear()
	shrank.clear()
	_roads_dirty = true
	_power_dirty = true
	recount()
