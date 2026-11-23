extends "res://scripts/dev_shots.gd"
## Dev tool, not part of the game: builds the example cities in the game menu
## (Settings.EXAMPLES) and saves them to examples/<id>.json.
##
## Run it with tools/make_examples.sh, which starts Godot in a window like this:
##   Godot --path . --windowed --resolution 1600x1000 -- --examples=<picture dir> [--examples-only=city]
## game3d.gd adds this node when it sees --examples=; in normal play it is never made.
##
## Each city is built like the screenshot town (dev_shots.gd, which this script
## extends): with the game's own build tools, from a fixed seed, and grown month
## by month with the simulation's real tick(). Nothing is forced: every building
## grew by the game's rules. The last two years are run on the city's own money
## (no top-ups), so the saved city is one that pays its way. Then the save is
## loaded back as a check, and pictures of it are saved to the picture dir.

const Advisors = preload("res://scripts/advisors.gd")
const Companies = preload("res://scripts/companies.gd")

const SETTLE_MONTHS := 24             # months run on the city's own money before saving

var only_examples: PackedStringArray = []
var _problems := 0


static func wanted_examples(args: PackedStringArray) -> bool:
	for a: String in args:
		if a.begins_with("--examples="):
			return true
	return false


func _init(game_node: Node3D, args: PackedStringArray) -> void:
	super(game_node, args)
	name = "DevExamples"
	for a: String in args:
		if a.begins_with("--examples="):
			out_dir = a.trim_prefix("--examples=")
		elif a.begins_with("--examples-only="):
			only_examples = a.trim_prefix("--examples-only=").split(",", false)
	if out_dir.is_relative_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)


func _plans() -> Array[Dictionary]:
	# months: how long the city grows; money: what it has when the last two years
	# (on its own money) begin; shots: pictures for checking how it looks.
	return [
		{"id": "village", "level": 1, "months": 72, "money": 20000, "build": _build_village,
			"shots": [
				{"name": "village_1_overview", "at": Vector2(52, 49), "yaw": -40.0, "pitch": 38.0, "dist": 1500.0},
				{"name": "village_2_close", "at": Vector2(47, 51), "yaw": -35.0, "pitch": 32.0, "dist": 520.0},
				{"name": "village_3_hud", "at": Vector2(50, 51), "yaw": -40.0, "pitch": 40.0, "dist": 1500.0, "hud": true},
			]},
		{"id": "town", "level": 1, "months": 108, "money": 60000, "build": _build_harbour_town,
			"shots": [
				{"name": "town_1_overview", "at": Vector2(60, 44), "yaw": -40.0, "pitch": 40.0, "dist": 2600.0},
				{"name": "town_2_old_town", "at": Vector2(50, 50), "yaw": -35.0, "pitch": 32.0, "dist": 700.0},
				{"name": "town_3_works", "at": Vector2(85, 48), "yaw": -50.0, "pitch": 32.0, "dist": 700.0},
				{"name": "town_4_hud", "at": Vector2(58, 46), "yaw": -40.0, "pitch": 42.0, "dist": 2400.0, "hud": true},
			]},
		{"id": "city", "level": 1, "months": 216, "money": 250000, "build": _build_city,
			"shots": [
				{"name": "city_1_overview", "at": Vector2(60, 64), "yaw": -40.0, "pitch": 40.0, "dist": 3700.0},
				{"name": "city_2_centre", "at": Vector2(46, 64), "yaw": -40.0, "pitch": 24.0, "dist": 1050.0},
				{"name": "city_3_north", "at": Vector2(51, 27), "yaw": -40.0, "pitch": 34.0, "dist": 1100.0},
				{"name": "city_4_works", "at": Vector2(80, 74), "yaw": -50.0, "pitch": 32.0, "dist": 900.0},
				{"name": "city_5_night", "at": Vector2(48, 64), "yaw": -40.0, "pitch": 28.0, "dist": 1500.0, "time": NIGHT},
				{"name": "city_6_hud", "at": Vector2(55, 58), "yaw": -40.0, "pitch": 38.0, "dist": 1700.0, "hud": true},
				{"name": "city_7_traffic", "at": Vector2(58, 62), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0, "hud": true,
					"prep": _prep_traffic},
				{"name": "city_8_services", "at": Vector2(58, 62), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0, "hud": true,
					"prep": _prep_services.bind(-1)},
				{"name": "city_9_pollution", "at": Vector2(58, 62), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0, "hud": true,
					"prep": _prep_view.bind(WorldView.Overlay.POLLUTION)},
			]},
		{"id": "bay", "level": 1, "months": 144, "money": 400000, "build": _build_bay,
			"shots": [
				{"name": "bay_1_overview", "at": Vector2(100, 80), "yaw": -30.0, "pitch": 42.0, "dist": 7000.0},
				{"name": "bay_2_downtown", "at": Vector2(104, 36), "yaw": -40.0, "pitch": 26.0, "dist": 1300.0},
				{"name": "bay_3_golden_gate", "at": Vector2(122, 26), "yaw": -20.0, "pitch": 24.0, "dist": 1500.0},
				{"name": "bay_4_city", "at": Vector2(88, 40), "yaw": -40.0, "pitch": 34.0, "dist": 2600.0},
				{"name": "bay_5_valley", "at": Vector2(118, 118), "yaw": -40.0, "pitch": 36.0, "dist": 2600.0},
				{"name": "bay_6_stanford", "at": Vector2(50, 108), "yaw": -40.0, "pitch": 34.0, "dist": 1200.0},
				{"name": "bay_7_night", "at": Vector2(104, 36), "yaw": -40.0, "pitch": 28.0, "dist": 1800.0, "time": NIGHT},
				{"name": "bay_8_hud", "at": Vector2(100, 70), "yaw": -30.0, "pitch": 42.0, "dist": 5000.0, "hud": true},
			]},
	]


func _run() -> void:
	var started := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_skip_import(out_dir)
	var save_dir := ProjectSettings.globalize_path("res://examples")
	DirAccess.make_dir_recursive_absolute(save_dir)
	game.call("_set_speed", 0)
	game.set("day_cycle", false)
	game.set("fit_to_screen", false)
	get_window().content_scale_factor = 1.0
	get_viewport().scaling_3d_scale = 1.0
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = SHOT_SIZE
	await get_tree().process_frame

	for plan: Dictionary in _plans():
		var id: String = plan["id"]
		if not only_examples.is_empty() and not only_examples.has(id):
			continue
		print("[examples] ---- %s ----" % id)
		var t0 := Time.get_ticks_msec()
		game.call("_new_city", int(plan["level"]))
		seed(SEED)
		sim.set("_rng", _seeded_rng(SEED))
		traffic.set("_rng", _seeded_rng(SEED + 1))
		_pending.clear()
		var build: Callable = plan["build"]
		build.call()
		await _grow_for(int(plan["months"]))
		await _settle(int(plan["money"]))
		_finish_example()
		_report_example(id)
		var path := save_dir.path_join(id + ".json")
		var saved: bool = game.call("_write_save", path)
		if not saved:
			_problem("couldn't save %s" % path)
			continue
		_check_load(id)
		print("[examples] %s saved to %s in %.1f s" % [id, path, (Time.get_ticks_msec() - t0) / 1000.0])
		for shot: Dictionary in plan["shots"]:
			await _shoot(shot)
		# How fast it draws, from its first two views (the whole city, then close up).
		for shot: Dictionary in (plan["shots"] as Array).slice(0, 2):
			await _shoot(shot)
			var m := measure(get_viewport(), 30)
			print("[examples]   speed at %s: %s" % [String(shot["name"]), perf_line("", m)])
	print("[examples] done in %.1f s, %d problems" % [(Time.get_ticks_msec() - started) / 1000.0, _problems])
	get_tree().quit(1 if _problems > 0 or _failed > 0 else 0)


func _problem(text: String) -> void:
	_problems += 1
	printerr("[examples] PROBLEM: %s" % text)


# ------------------------------------------------------------------ the plans

func _build_village() -> void:
	# A few streets by the shore: villas and bungalows, a row of shops, a small
	# works behind a strip of trees, a few wind turbines. Lots of room to grow.
	sim.money = RICH
	_build("grid", Vector2i(40, 39), Vector2i(55, 57))
	_build("grid", Vector2i(55, 51), Vector2i(67, 57))
	_build("homes_0", Vector2i(41, 40), Vector2i(51, 56))
	_build("shops_0", Vector2i(53, 40), Vector2i(54, 50))
	_build("shops_0", Vector2i(53, 52), Vector2i(54, 56))
	_build("shops_0", Vector2i(50, 49), Vector2i(51, 50))
	_build("industry", Vector2i(59, 52), Vector2i(66, 56))
	_build("woodland", Vector2i(56, 52), Vector2i(57, 56))
	_build("woodland", Vector2i(56, 40), Vector2i(60, 50))
	_build("wind", Vector2i(68, 52), Vector2i(70, 55))
	_build("landfill", Vector2i(60, 58), Vector2i(66, 58))
	_build("water_tower", Vector2i(53, 55))
	_build("water_pump", Vector2i(59, 55))
	_build("school", Vector2i(47, 46))
	_build("police_office", Vector2i(50, 46))      # the small services suit a village
	_build("fire_small", Vector2i(50, 52))
	_build("clinic", Vector2i(50, 43))
	_build("police_office", Vector2i(44, 49))
	_build("park", Vector2i(47, 52), Vector2i(48, 53))
	_build("park", Vector2i(41, 49), Vector2i(42, 50))
	_build("park", Vector2i(44, 43), Vector2i(45, 44))


func _build_harbour_town() -> void:
	# The north half of the big city's plan: a villa suburb, terraces, an old town
	# of tenements with a shop parade (a conservation area), a civic quarter, and
	# a works out to the east behind a belt of trees.
	sim.money = RICH
	_harbour = Vector2i(39, 50)
	_build("grid", Vector2i(34, 30), Vector2i(58, 57))
	_build("grid", Vector2i(58, 30), Vector2i(73, 57))
	_build("grid", Vector2i(79, 39), Vector2i(91, 57))
	_build("road", Vector2i(73, 57), Vector2i(79, 57))
	_build("road", Vector2i(73, 45), Vector2i(79, 45))
	for z: Array in [
		["homes_0", Vector2i(35, 31), Vector2i(57, 44)],
		["shops_0", Vector2i(50, 37), Vector2i(51, 38)],
		["homes_1", Vector2i(59, 31), Vector2i(72, 44)],
		["homes_1", Vector2i(35, 46), Vector2i(51, 56)],
		["shops_1", Vector2i(53, 46), Vector2i(57, 56)],
		["shops_1", Vector2i(59, 52), Vector2i(72, 56)],
		["shops_1", Vector2i(59, 43), Vector2i(72, 44)],
		["offices_1", Vector2i(68, 52), Vector2i(72, 56)],
		["industry", Vector2i(80, 40), Vector2i(90, 56)],
	]:
		_build(z[0], z[1], z[2])
	_build("conservation", Vector2i(34, 45), Vector2i(58, 56))
	_build("woodland", Vector2i(74, 46), Vector2i(78, 56))
	_build("woodland", Vector2i(74, 34), Vector2i(78, 44))
	# Power, water, rubbish.
	_build("coal", Vector2i(89, 55))
	_build("wind", Vector2i(92, 39), Vector2i(95, 45))
	for p: Vector2i in [Vector2i(80, 55), Vector2i(83, 55), Vector2i(68, 31), Vector2i(71, 41)]:
		_build("water_pump", p)
	_build("water_tower", Vector2i(44, 44))
	_build("landfill", Vector2i(92, 46), Vector2i(93, 56))
	# Services.
	for p: Vector2i in [Vector2i(47, 41), Vector2i(65, 44)]:
		_build("police", p)
	for p: Vector2i in [Vector2i(47, 35), Vector2i(65, 53), Vector2i(83, 49)]:
		_build("fire", p)
	for p: Vector2i in [Vector2i(44, 38), Vector2i(65, 38), Vector2i(50, 53), Vector2i(71, 32)]:
		_build("school", p)
	_build("hospital", Vector2i(59, 44))
	for r: Array in [[Vector2i(53, 37), Vector2i(54, 38)], [Vector2i(62, 40), Vector2i(63, 41)],
			[Vector2i(59, 46), Vector2i(60, 47)], [Vector2i(62, 46), Vector2i(63, 47)],
			[Vector2i(65, 46), Vector2i(66, 47)], [Vector2i(68, 46), Vector2i(69, 50)],
			[Vector2i(41, 37), Vector2i(42, 38)], [Vector2i(44, 49), Vector2i(45, 50)]]:
		_build("park", r[0], r[1])
	_later("library", Vector2i(59, 50))
	_later("town_hall", Vector2i(62, 50))
	_later("painted_ladies", Vector2i(65, 50))
	_later("bus_depot", Vector2i(53, 44))
	_later("harbour", _harbour, _harbour, true)
	_later("gas", Vector2i(86, 55))
	_later("gas", Vector2i(86, 56))
	_later("recycling", Vector2i(89, 49))
	_later("station", Vector2i(56, 44))


func _build_city() -> void:
	sim.money = RICH
	_harbour = Vector2i(39, 85)
	_marina = Vector2i(43, 93)
	# Three more roads between the town and the works (the screenshot town has
	# one, which jams), laid first so the park and the woodland go round them.
	for y: int in [66, 78, 90]:
		_build("road", Vector2i(58, y), Vector2i(73, y))
	# The screenshot town: suburbs, terraces, old town, CBD, works, golf links.
	_build_town()
	# A second, smaller works north of the first, behind its own strip of trees.
	_build("grid", Vector2i(76, 45), Vector2i(85, 57))
	_build("industry", Vector2i(77, 46), Vector2i(84, 56))
	_build("woodland", Vector2i(74, 46), Vector2i(75, 56))
	_build("police", Vector2i(83, 52))
	# A villa suburb along the north shore.
	_build("grid", Vector2i(43, 18), Vector2i(58, 30))
	_build("homes_0", Vector2i(44, 19), Vector2i(57, 29))
	_build("shops_0", Vector2i(50, 25), Vector2i(51, 26))
	_build("park", Vector2i(47, 25), Vector2i(48, 26))
	_build("park", Vector2i(53, 22), Vector2i(54, 23))
	_build("water_pump", Vector2i(56, 19))
	# ...and terraces beside it.
	_build("grid", Vector2i(58, 18), Vector2i(67, 30))
	_build("homes_1", Vector2i(59, 19), Vector2i(66, 29))
	_build("park", Vector2i(62, 22), Vector2i(63, 23))
	_build("school", Vector2i(62, 26))
	_build("water_pump", Vector2i(65, 19))
	# More room for rubbish, and buses for the old town (its main road is the busiest).
	_build("landfill", Vector2i(86, 78), Vector2i(86, 87))
	_later("recycling", Vector2i(83, 67))
	for p: Vector2i in [Vector2i(50, 56), Vector2i(50, 34), Vector2i(65, 32), Vector2i(50, 20), Vector2i(62, 20),
			Vector2i(44, 82)]:
		_later("bus_depot", p)
	# More services than the screenshot town has, so every street is well covered.
	for p: Vector2i in [Vector2i(41, 50), Vector2i(62, 35), Vector2i(47, 79), Vector2i(50, 23)]:
		_build("police", p)
	for p: Vector2i in [Vector2i(41, 47), Vector2i(68, 35), Vector2i(56, 64), Vector2i(53, 79), Vector2i(53, 26),
			Vector2i(80, 49)]:
		_build("fire", p)
	for p: Vector2i in [Vector2i(41, 38), Vector2i(44, 53), Vector2i(47, 62), Vector2i(56, 76), Vector2i(41, 86),
			Vector2i(71, 34), Vector2i(47, 23)]:
		_build("school", p)
	for p: Vector2i in [Vector2i(47, 35), Vector2i(68, 43)]:
		_build("hospital", p)
	# A belt of woodland between the town and the works, and round the tip.
	_build("woodland", Vector2i(66, 59), Vector2i(71, 94))
	_build("woodland", Vector2i(87, 66), Vector2i(90, 96))
	_build("woodland", Vector2i(74, 97), Vector2i(90, 99))


# ------------------------------------------------------------------- growing

func _grow_for(months: int) -> void:
	# Month after month with the simulation's own tick(), money topped up (the
	# building years: the last SETTLE_MONTHS are run on the city's own money).
	for m: int in months:
		sim.money = RICH
		_build_unlocked()
		seed(SEED + sim.month)
		sim.tick()
		if sim.month % 12 == 0:
			_status()
			await get_tree().process_frame
	for item: Array in _pending:
		print("[examples]   never unlocked: %s (needs %d people)" % [item[0], int(Settings.BUILDINGS[item[0]].get("unlock", 0))])


func _settle(money: int) -> void:
	# Two years on the city's own money: it must not lose money or people.
	sim.money = money
	var people := sim.population
	var worst := 1 << 30
	for m: int in SETTLE_MONTHS:
		seed(SEED + sim.month)
		sim.tick()
		worst = mini(worst, sim.last_balance())
		if sim.month % 12 == 0:
			_status()
			await get_tree().process_frame
	print("[examples]   two years on its own money: %d -> %d, worst month %+d, people %d -> %d" % [
		money, sim.money, worst, people, sim.population])
	if worst < 0:
		_problem("the city loses money (worst month %d)" % worst)
	if sim.population < people * 0.97:
		_problem("the city is shrinking (%d -> %d people)" % [people, sim.population])


func _finish_example() -> void:
	var money := sim.money
	_finish_town()                    # (sets the screenshot town's money)
	sim.money = money
	game.call("_refresh_hud")


func _report_example(id: String) -> void:
	print("[examples] %s: %s, %d people, %d jobs, happiness %d%%, money %d, income %d, upkeep %d, balance %+d a month, tax %d%%" % [
		id, sim.date_text(), sim.population, sim.jobs(), roundi(sim.happiness * 100.0), sim.money, sim.last_income,
		sim.last_upkeep, sim.last_balance(), roundi(sim.tax_rate * 100.0)])
	var parts: Array[String] = []
	for key: Variant in sim.happiness_parts:
		parts.append("%s %.2f" % [str(key), float(sim.happiness_parts[key])])
	print("[examples]   happiness parts: %s" % ", ".join(parts))
	print("[examples]   demand: homes %.0f, shops %.0f, industry %.0f; power %d/%d, water %d/%d; abandoned %d; skyscrapers %d" % [
		float(sim.demand[Simulation.Tile.HOMES]), float(sim.demand[Simulation.Tile.SHOPS]),
		float(sim.demand[Simulation.Tile.INDUSTRY]), sim.power_used, sim.power_supply, sim.water_used,
		sim.water_supply, sim.abandoned_count, _count_tall(7)])
	for tip: Dictionary in Advisors.tips(sim):
		print("[examples]   advisor (%d): %s  %s" % [int(tip["severity"]), String(tip["text"]), String(tip["detail"])])
	var why_empty := {}
	for i: int in sim.w * sim.h:
		if sim.is_zone(sim.tiles[i]) and sim.levels[i] == 0:
			var key := "%s: %s" % [_zone_word(sim.tiles[i]), sim.zone_status(i)]
			why_empty[key] = int(why_empty.get(key, 0)) + 1
	for key: String in why_empty:
		print("[examples]   empty plots, %d x %s" % [int(why_empty[key]), key])
	print("[examples]   power networks' spare: %s; deals: %s" % [str(sim.get("_net_spare")),
		", ".join(sim.deals.map(func(d: Dictionary) -> String: return "%s %s%s" % [d["company"], sim.deal_kind(d),
			"" if sim.deal_working(sim.deal_by_id(int(d["id"]))) else " (not working: %s)" % sim.deal_problem(sim.deal_by_id(int(d["id"])))]))])
	traffic_report(sim, "[examples]")
	if sim.abandoned_count > 0:
		_problem("%d abandoned plots" % sim.abandoned_count)


func _check_load(id: String) -> void:
	# Load it back through the game menu's own code: the same city must come out.
	var before := [sim.population, sim.shop_jobs, sim.money, sim.month, sim.last_balance(),
		hash([sim.tiles, sim.levels, sim.density, sim.district])]
	game.call("_new_city", 1)
	game.call("_load_example", id)
	var after := [sim.population, sim.shop_jobs, sim.money, sim.month, sim.last_balance(),
		hash([sim.tiles, sim.levels, sim.density, sim.district])]
	if before != after:
		_problem("%s loads back differently: %s -> %s" % [id, before, after])
	else:
		print("[examples]   loads back the same (%d people, checksum %d)" % [sim.population, int(after[5])])
	game.call("_set_speed", 0)


# ------------------------------------------------- the Bay Area (SF and Silicon Valley)
# A loose San Francisco and Silicon Valley on the Menlo Park map (the Bay is to
# the north and east, with a far shore to the north-east): San Francisco on the
# north-east point, its downtown a CBD by the water with the Transamerica Pyramid
# and Salesforce Tower, the Ferry Building on the waterfront, Coit Tower on the
# point, the Painted Ladies among the row houses, the Palace of Fine Arts on the
# north shore, the Golden Gate Bridge out to the far shore and Alcatraz in the
# Bay. An airport by the Bay south of the city (SFO), then Highway 101 (a
# motorway) and El Camino (an avenue) running south through the suburbs to
# Silicon Valley: Stanford (university and research park) in the foothills, and
# a Tech zone with Google's, Apple's and Meta's campuses, Nvidia's chip factory
# and Amazon's and OpenAI's data centres. The companies come as letters the
# mayor says yes to, once the town is big enough, and their sites are dragged
# out with the game's own tool.

var _deals_pending: Array = []      # [pop, kind, company, size, from, to]
var _plants_pending: Array = []     # [pop, near, id]: plants built as the town needs them, by a road
var _bay := false                   # building the Bay Area (the other examples are left as they were)


func _build_bay() -> void:
	_bay = true
	sim.money = RICH
	# --- Roads: San Francisco's grids, Highway 101 and El Camino, the suburbs.
	_build("grid", Vector2i(62, 26), Vector2i(88, 62))       # the Richmond, the Haight, the Sunset
	_build("grid", Vector2i(88, 18), Vector2i(117, 46))      # downtown and North Beach
	_build("grid", Vector2i(88, 46), Vector2i(117, 62))      # SoMa and the Mission
	_build("motorway", Vector2i(100, 62), Vector2i(100, 150))   # Highway 101
	_build("road", Vector2i(100, 46), Vector2i(100, 62))
	_build("avenue", Vector2i(76, 62), Vector2i(76, 150))    # El Camino Real
	_build("grid", Vector2i(60, 63), Vector2i(99, 96))       # the Peninsula's suburbs
	_build("grid", Vector2i(101, 74), Vector2i(121, 94))     # the works by the Bay (South City)
	_build("grid", Vector2i(56, 97), Vector2i(99, 139))      # Palo Alto, Mountain View, Cupertino
	# The Valley by the Bay: office parks and East Palo Alto on streets, then big
	# blocks (8 x 7 tiles inside) with room for the companies' sites.
	_build("grid", Vector2i(101, 97), Vector2i(119, 137))
	for x: int in [128, 137, 146]:
		_build("road", Vector2i(x, 97), Vector2i(x, 137))
	for y: int in [97, 105, 113, 121, 129, 137]:
		_build("road", Vector2i(119, y), Vector2i(146, y))
	# Cupertino: one big block for Apple.
	_build("road", Vector2i(57, 139), Vector2i(57, 147))
	_build("road", Vector2i(66, 139), Vector2i(66, 147))
	_build("road", Vector2i(57, 147), Vector2i(76, 147))
	_build("road", Vector2i(71, 139), Vector2i(71, 147))
	for y: int in [70, 84, 104, 120, 136]:
		_build("road", Vector2i(99, y), Vector2i(101, y))    # on and off 101
	# The Golden Gate: a long bridge east from the point to the far shore.
	_build("road", Vector2i(107, 24), Vector2i(142, 24))
	_build("road", Vector2i(142, 24), Vector2i(150, 24))
	# Stanford's road up into the foothills.
	_build("road", Vector2i(40, 102), Vector2i(56, 102))
	_build("road", Vector2i(40, 102), Vector2i(40, 116))
	_build("road", Vector2i(40, 116), Vector2i(56, 116))

	# --- Zones.
	for z: Array in [
		["homes_1", Vector2i(63, 27), Vector2i(87, 50)],       # row houses
		["homes_0", Vector2i(63, 57), Vector2i(87, 61)],       # the Sunset
		["homes_2", Vector2i(89, 19), Vector2i(99, 39)],       # North Beach, Nob Hill
		["offices_2", Vector2i(101, 27), Vector2i(116, 40)],   # the Financial District
		["shops_2", Vector2i(89, 40), Vector2i(116, 45)],      # Union Square, Market Street
		["homes_2", Vector2i(101, 19), Vector2i(112, 26)],
		["shops_1", Vector2i(89, 47), Vector2i(116, 50)],      # the Mission's shops
		["offices_1", Vector2i(101, 51), Vector2i(116, 61)],   # SoMa's offices
		["homes_1", Vector2i(89, 51), Vector2i(99, 61)],
		["homes_0", Vector2i(61, 64), Vector2i(98, 95)],       # Daly City to San Mateo
		["shops_0", Vector2i(77, 64), Vector2i(78, 95)],       # strip malls along El Camino
		["industry", Vector2i(102, 75), Vector2i(120, 93)],    # South City's works
		["homes_0", Vector2i(57, 98), Vector2i(98, 138)],      # Palo Alto to Cupertino
		["homes_0", Vector2i(67, 140), Vector2i(75, 146)],
		["shops_0", Vector2i(77, 98), Vector2i(78, 138)],
		["shops_1", Vector2i(80, 112), Vector2i(91, 114)],     # University Avenue
		["offices_0", Vector2i(102, 98), Vector2i(118, 112)],  # office parks along 101
		["offices_1", Vector2i(102, 114), Vector2i(118, 120)],
		["homes_1", Vector2i(102, 122), Vector2i(118, 136)],   # East Palo Alto
	]:
		_build(z[0], z[1], z[2])
	_build("cbd", Vector2i(88, 18), Vector2i(117, 46))
	# The Tech zone: the office parks and open land kept for the big companies.
	_build("tech_zone", Vector2i(101, 97), Vector2i(146, 121))
	_build("tech_zone", Vector2i(119, 121), Vector2i(146, 137))
	_build("tech_zone", Vector2i(57, 139), Vector2i(66, 147))
	# Parks: Golden Gate Park, the Presidio, Dolores Park, and the Baylands.
	_build("park", Vector2i(63, 51), Vector2i(87, 56))
	_build("park", Vector2i(63, 27), Vector2i(66, 32))
	_build("park", Vector2i(93, 53), Vector2i(95, 56))
	_build("woodland", Vector2i(101, 64), Vector2i(119, 64))
	_build("woodland", Vector2i(101, 94), Vector2i(121, 95))
	# The Baylands (woodland by the water) and a golf course in the Valley's spare blocks.
	_build("woodland", Vector2i(138, 98), Vector2i(145, 112))
	_build("woodland", Vector2i(138, 114), Vector2i(145, 128))
	_build("woodland", Vector2i(120, 122), Vector2i(136, 128))
	_build("park", Vector2i(129, 98), Vector2i(132, 103))

	# --- Power, water, rubbish: by the works.
	_build("coal", Vector2i(117, 90))
	_build("coal", Vector2i(117, 87))
	for p: Vector2i in [Vector2i(103, 76), Vector2i(106, 76), Vector2i(109, 76), Vector2i(103, 79), Vector2i(106, 79),
			Vector2i(109, 79), Vector2i(70, 30), Vector2i(95, 30), Vector2i(70, 66), Vector2i(90, 66), Vector2i(70, 90),
			Vector2i(90, 90), Vector2i(60, 110), Vector2i(90, 120), Vector2i(60, 135), Vector2i(90, 135),
			Vector2i(104, 112), Vector2i(138, 112), Vector2i(104, 130), Vector2i(120, 136)]:
		var at := _nearest_spot("water_pump", p, 3)
		if at.x >= 0:
			_build("water_pump", at)
	_build("landfill", Vector2i(112, 76), Vector2i(119, 80))
	_later("recycling", Vector2i(112, 83))
	_later("gas", Vector2i(114, 90))
	_later("gas", Vector2i(114, 87))
	_later("nuclear", Vector2i(110, 90))
	_later("nuclear", Vector2i(106, 90))
	_later("nuclear", Vector2i(108, 87))
	_later("nuclear", Vector2i(104, 87))
	for p: Vector2i in [Vector2i(138, 130), Vector2i(145, 130), Vector2i(138, 136), Vector2i(145, 136)]:
		_later("nuclear", p)                                 # the Valley's own power, by the Bay
	for item: Array in [[16000, Vector2i(105, 82)], [16000, Vector2i(111, 81)], [24000, Vector2i(106, 92)],
			[24000, Vector2i(118, 92)]]:
		_plants_pending.append([item[0], item[1], "nuclear"])   # more as OpenAI asks for more
	# Water for the companies: a pump on a corner of each big block.
	for bx: int in [127, 136]:
		for by: int in [104, 112, 120, 136]:
			_build("water_pump", Vector2i(bx, by))
	_later("incinerator", Vector2i(119, 83))
	for p: Vector2i in [Vector2i(116, 80), Vector2i(104, 84), Vector2i(126, 103), Vector2i(105, 96), Vector2i(115, 96)]:
		_plants_pending.append([4000, p, "incinerator"])
	_later("solar", Vector2i(120, 130), Vector2i(135, 135))      # solar farms in the Valley
	for p: Vector2i in [Vector2i(62, 70), Vector2i(62, 82), Vector2i(62, 94), Vector2i(62, 104), Vector2i(62, 116),
			Vector2i(62, 128), Vector2i(98, 104), Vector2i(98, 116), Vector2i(98, 128), Vector2i(64, 40), Vector2i(86, 58)]:
		var at := _nearest_spot("water_pump", p, 3)
		if at.x >= 0:
			_build("water_pump", at)

	# --- Services, spread over every neighbourhood.
	# (Services are added as the homes are built: see _build_unlocked.)
	_build("college", _nearest_spot("college", Vector2i(86, 120), 4))
	_later("university", Vector2i(41, 103), Vector2i(48, 110))   # Stanford
	_later("research_park", Vector2i(49, 103), Vector2i(55, 108))
	_later("bus_depot", Vector2i(92, 47))
	_later("bus_depot", Vector2i(80, 33))
	_later("station", Vector2i(99, 43))                      # Caltrain, downtown
	_later("station", Vector2i(80, 116))                     # ...and Palo Alto
	_later("bus_depot", Vector2i(80, 80))
	_later("airport", Vector2i(102, 65), Vector2i(120, 72))  # SFO

	# --- San Francisco's landmarks, as soon as the city is big enough for each.
	_later("painted_ladies", Vector2i(75, 38))               # Alamo Square
	_later("coit_tower", Vector2i(95, 20))                   # on the point
	_later("ferry_building", Vector2i(117, 38), Vector2i(117, 38), true)
	_later("fine_arts", Vector2i(70, 29))                    # by the north shore
	_later("alcatraz", Vector2i(76, 15))                     # out in the Bay
	_later("transamerica", Vector2i(105, 32))
	_later("salesforce_tower", Vector2i(109, 38))
	_later("golden_gate", Vector2i(125, 24))
	_later("library", Vector2i(95, 44))
	_later("museum", Vector2i(80, 54))                       # in Golden Gate Park
	_later("town_hall", Vector2i(92, 44))
	_later("stadium", Vector2i(113, 53))

	# --- Silicon Valley's companies: letters the mayor says yes to, sites dragged out.
	_deals_pending = [
		[5000, "campus", "Meta", 1, Vector2i(120, 98), Vector2i(124, 101)],           # Menlo Park, by the Bay
		[9000, "campus", "Google", 1, Vector2i(120, 106), Vector2i(124, 109)],        # Mountain View
		[12000, "data_centre", "Amazon", 1, Vector2i(129, 106), Vector2i(132, 108)],
		[16000, "chip_factory", "Nvidia", 1, Vector2i(120, 114), Vector2i(124, 117)], # Santa Clara
		[20000, "campus", "Apple", 0, Vector2i(58, 140), Vector2i(60, 142)],          # Cupertino
		[25000, "ai_data_centre", "OpenAI", 0, Vector2i(129, 114), Vector2i(132, 117)],
	]


func _build_unlocked() -> void:
	super()
	if not _bay:
		return
	# Every few months, services where the built homes are least covered (as a
	# player would, with the Services view), while there's power to spare.
	if sim.month % 3 == 0:
		_cover_homes("police", 0, 0.75)
		_cover_homes("fire", 1, 0.75)
		_cover_homes("school", 2, 0.8)
		_cover_homes("hospital", 3, 0.7)
	# The mayor's post: yes when OpenAI asks for more power, no to everything else.
	for letter: Dictionary in sim.letters.duplicate():
		sim.answer_letter(int(letter["id"]), String(letter.get("kind", "")) == "more_power")
	var later_plants: Array = []
	for item: Array in _plants_pending:
		if sim.population >= int(item[0]):
			var what: String = item[2]
			var at := _nearest_spot(what, item[1], 5)
			if at.x >= 0:
				_build(what, at)
				print("[examples]   month %d: %s at %s" % [sim.month, what, at])
		else:
			later_plants.append(item)
	_plants_pending = later_plants
	var still: Array = []
	for item: Array in _deals_pending:
		if sim.population >= int(item[0]):
			_company(item[1], item[2], item[3], item[4], item[5])
		else:
			still.append(item)
	_deals_pending = still


func _company(kind: String, company: String, size: int, from: Vector2i, to: Vector2i) -> void:
	# The company writes, the mayor says yes (size: Small, Standard or Mega), and
	# its site is dragged out in the Tech zone, as a player would.
	var busy: Array = []
	for c: String in ["Amazon", "Microsoft", "Google", "Apple", "Meta"]:
		if c != company:
			busy.append(c)
	var letter: Dictionary = Companies.project_letter(kind, sim.get("_rng"), busy)
	if letter.is_empty() or String(letter["company"]) != company:
		_problem("no %s letter from %s" % [kind, company])
		return
	var id: int = sim.call("_send_letter", letter)
	var said: Dictionary = sim.answer_letter(id, true, size)
	if not bool(said["ok"]):
		_problem("%s: %s" % [company, said["text"]])
		return
	game.call("_start_placing", id)
	game.set("drag_start", from)
	var plan: Array[Vector2i] = game.call("_plan_tiles", from, to)
	game.set("drag_plan", plan)
	var short: String = game.call("_too_small")
	game.call("_finish_drag")
	var k: int = sim.deal_by_id(id)
	if short != "" or k < 0 or (sim.deals[k]["tiles"] as Array).is_empty():
		_problem("%s's %s didn't go at %s: %s" % [company, kind, from, short])
		return
	print("[examples]   month %d, %d people: %s's %s at %s" % [sim.month, sim.population, company, kind, from])


func _nearest_spot(id: String, near: Vector2i, reach: int) -> Vector2i:
	game.call("_choose_item", id)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y: int in range(near.y - reach, near.y + reach + 1):
		for x: int in range(near.x - reach, near.x + reach + 1):
			if x < 0 or y < 0 or x >= sim.w or y >= sim.h:
				continue
			var i := y * sim.w + x
			var here: int = sim.tiles[i]
			if not (here == Simulation.Tile.EMPTY or (sim.is_zone(here) and sim.levels[i] == 0)) or not sim.near_road(i):
				continue
			# Touching a street, so power reaches it as well as the road.
			var touches := false
			for n: Vector2i in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]:
				if n.x >= 0 and n.y >= 0 and n.x < sim.w and n.y < sim.h \
						and sim.tiles[n.y * sim.w + n.x] == Simulation.Tile.ROAD:
					touches = true
			if not touches:
				continue
			if String(game.call("_why_cant_build", Vector2i(x, y), false)) != "":
				continue
			var d := (Vector2i(x, y) - near).length_squared()
			if d < best_d:
				best = Vector2i(x, y)
				best_d = d
	return best


func _cover_homes(id: String, service: int, want: float) -> void:
	# Put this service where the homes are least covered, again and again,
	# until every home zone has at least `want` cover.
	var skip := {}
	var placed := 0
	var size: int = sim.w * sim.h
	for n: int in 6:
		var spare := 0
		for left: int in sim.get("_net_spare"):
			spare += left
		if spare < 60:
			break
		sim.set("_coverage_dirty", true)
		sim.call("_update_coverage")
		var worst := -1
		var worst_c := want
		for i: int in size:
			if sim.tiles[i] == Simulation.Tile.HOMES and sim.levels[i] > 0 and not skip.has(i):
				var c: float = sim.coverage[service * size + i]
				if c < worst_c:
					worst_c = c
					worst = i
		if worst < 0:
			break
		var spot := _nearest_spot(id, Vector2i(worst % sim.w, worst / sim.w), 4)
		if spot.x < 0 or _build(id, spot) == 0:
			skip[worst] = true
			continue
		placed += 1
	if placed > 0:
		print("[examples]   month %d: %d x %s where homes were least covered" % [sim.month, placed, id])
