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
	_build("police", Vector2i(50, 46))
	_build("fire", Vector2i(50, 52))
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
		id, sim.date_text(), sim.population, sim.shop_jobs + sim.industry_jobs, roundi(sim.happiness * 100.0), sim.money, sim.last_income,
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
