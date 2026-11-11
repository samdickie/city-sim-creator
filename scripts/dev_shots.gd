extends Node
## Dev tool, not part of the game: builds a demo town and saves screenshots of it.
##
## Run it with tools/screenshots.sh, which starts Godot in a window like this:
##   Godot --path . --windowed --resolution 1600x1000 -- --shots=<dir> [--shots-only=04_cbd,09_night]
## game3d.gd adds this node when it sees --shots=; in normal play it is never made.
##
## The town is built with the game's own build tools (the same code a mouse drag
## runs), from a fixed random seed, then fast-forwarded month by month with the
## simulation's real tick(). Afterwards a few plots may be pushed to building
## stages the run didn't reach, so every model appears somewhere ("showcase").
## Nothing here changes the game's rules: the hacks only touch this demo town.

const Settings = preload("res://scripts/settings.gd")
const Simulation = preload("res://scripts/simulation.gd")
const WorldView = preload("res://scripts/world3d.gd")
const CameraRig = preload("res://scripts/camera_rig.gd")
const Hud = preload("res://scripts/hud.gd")
const Traffic = preload("res://scripts/traffic.gd")

const SEED := 20261111
const SHOT_SIZE := Vector2i(1600, 1000)  # pixels (on a Retina screen the window looks half this size)
const RICH := 50_000_000              # money topped up to before every build and month
const SHOWN_MONEY := 1_284_350        # what the HUD shows in the shots (looks like a real town)
const MIN_MONTHS := 120               # fast-forward at least this long...
const MAX_MONTHS := 300               # ...and at most this long
const SETTLE_FRAMES := 40             # frames to wait after moving the camera (shadows, MultiMeshes)
const WATCHDOG_SECONDS := 900.0       # give up (and quit) if a run takes longer than this
const DAY := 0.6                      # time of day for the daylight shots (early afternoon)
const NIGHT := 0.95

# Minimum plots of each building stage wanted in the shots (stage 1 to 8).
const WANT_HOMES := [0, 3, 3, 3, 3, 3, 3, 4, 2]
const WANT_SHOPS := [0, 3, 3, 3, 3, 3, 3, 4, 2]
const WANT_INDUSTRY := [0, 3, 3, 3]

# The street grids, [from, to]: streets every third tile, all lined up (so plots
# sit at x % 3 != 1 and y % 3 != 0).
const GRIDS := [[Vector2i(34, 30), Vector2i(58, 96)], [Vector2i(58, 30), Vector2i(73, 57)],
	[Vector2i(73, 57), Vector2i(85, 96)]]

var game: Node3D                      # game3d.gd (its helpers are reached with call/get/set)
var sim: Simulation
var world: WorldView
var rig: CameraRig
var hud: Hud
var traffic: Traffic
var out_dir := ""
var only: PackedStringArray = []
var _pending: Array = []              # [id, from, to, near_sea] waiting for the town to unlock them
var _forced: Array[String] = []       # what the showcase step changed
var _harbour := Vector2i(39, 85)
var _marina := Vector2i(43, 93)
var _failed := 0


static func wanted(args: PackedStringArray) -> bool:
	for a: String in args:
		if a.begins_with("--shots="):
			return true
	return false


func _init(game_node: Node3D, args: PackedStringArray) -> void:
	name = "DevShots"
	game = game_node
	for a: String in args:
		if a.begins_with("--shots="):
			out_dir = a.trim_prefix("--shots=")
		elif a.begins_with("--shots-only="):
			only = a.trim_prefix("--shots-only=").split(",", false)
	if out_dir == "":
		out_dir = "screenshots"
	if out_dir.is_relative_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)


func _ready() -> void:
	sim = game.get("sim")
	world = game.get("world")
	rig = game.get("rig")
	hud = game.get("hud")
	traffic = game.get("traffic")
	var watchdog := get_tree().create_timer(WATCHDOG_SECONDS)
	watchdog.timeout.connect(func() -> void:
		printerr("[shots] gave up after %d seconds" % int(WATCHDOG_SECONDS))
		get_tree().quit(1))
	_run()


func _run() -> void:
	var started := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("[shots] saving to %s" % out_dir)
	# The same town every run: fix every random number generator the town uses.
	seed(SEED)
	sim.set("_rng", _seeded_rng(SEED))
	traffic.set("_rng", _seeded_rng(SEED + 1))
	game.call("_set_speed", 0)        # the game clock stays still; months are run below
	game.set("day_cycle", false)
	# A fixed size in pixels, whatever the screen's scaling (--resolution is in
	# points on a Retina Mac, and gets squeezed to fit the screen).
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = SHOT_SIZE
	await get_tree().process_frame

	_build_town()
	await _fast_forward()
	_showcase()
	_finish_town()
	print("[shots] town ready in %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	_report()

	for shot: Dictionary in _shot_list():
		var shot_name: String = shot["name"]
		if not _included(shot_name):
			continue
		await _shoot(shot)
	print("[shots] done in %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	get_tree().quit(1 if _failed > 0 else 0)


func _seeded_rng(s: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


func _included(shot_name: String) -> bool:
	if only.is_empty():
		return true
	for f: String in only:
		if shot_name == f or shot_name.begins_with(f):
			return true
	return false


# ------------------------------------------------------------ the demo town

func _build_town() -> void:
	sim.money = RICH
	# Streets: three grids on the flat land by the coast (water and cliffs are
	# skipped, as with the mouse): the town, the terraces and civic quarter to its
	# north-east, and the works to the east, with open country left between.
	for g: Array in GRIDS:
		_build("grid", g[0], g[1])
	# The golf links' lane and a road along them.
	_build("road", Vector2i(49, 96), Vector2i(49, 102))
	_build("road", Vector2i(45, 100), Vector2i(58, 100))

	# Zones, west to east and north to south. Later ones paint over earlier ones.
	# Each box starts on a plot, not a street (a drag that starts on a road zones
	# both sides of every road instead). Sized so the jobs fill most of them.
	for z: Array in [
		["homes_0", Vector2i(35, 31), Vector2i(57, 44)],     # north suburb: villas and bungalows
		["shops_0", Vector2i(50, 37), Vector2i(51, 38)],     # ...with a few corner shops
		["homes_1", Vector2i(59, 31), Vector2i(72, 44)],     # terraces
		["homes_1", Vector2i(35, 46), Vector2i(51, 56)],     # old town: tenements
		["shops_1", Vector2i(53, 46), Vector2i(57, 56)],     # ...and its shop parade
		["shops_1", Vector2i(59, 52), Vector2i(72, 56)],     # civic quarter (buildings go on top)
		["homes_2", Vector2i(35, 58), Vector2i(57, 72)],     # CBD: high-density homes...
		["shops_2", Vector2i(41, 58), Vector2i(51, 69)],     # ...round an office core
		["homes_0", Vector2i(35, 73), Vector2i(57, 81)],
		["homes_0", Vector2i(35, 82), Vector2i(57, 95)],     # south suburb by the links
		["park", Vector2i(35, 58), Vector2i(40, 83)],        # seafront park (there are jobs for fewer homes)
		["shops_0", Vector2i(47, 85), Vector2i(48, 86)],
		["industry", Vector2i(74, 58), Vector2i(84, 87)],    # works by the power stations
	]:
		_build(z[0], z[1], z[2])

	# Districts.
	_build("conservation", Vector2i(34, 45), Vector2i(58, 56))
	_build("cbd", Vector2i(34, 57), Vector2i(57, 72))

	# Power: coal by the works, a wind farm on the hill with a line down to the works.
	_build("coal", Vector2i(83, 79))
	_build("coal", Vector2i(80, 79))
	_build("wind", Vector2i(90, 44), Vector2i(95, 48))
	_build("power_line", Vector2i(90, 49), Vector2i(86, 57))

	# Water and rubbish.
	for p: Vector2i in [Vector2i(74, 61), Vector2i(77, 61), Vector2i(74, 64), Vector2i(77, 64),
			Vector2i(68, 31), Vector2i(44, 94), Vector2i(44, 79), Vector2i(71, 41)]:
		_build("water_pump", p)
	_build("water_tower", Vector2i(44, 44))
	_build("water_tower", Vector2i(53, 82))
	_build("landfill", Vector2i(74, 89), Vector2i(84, 95))
	_build("landfill", Vector2i(86, 88), Vector2i(87, 95))

	# Services, spread so every street is covered.
	for p: Vector2i in [Vector2i(44, 41), Vector2i(65, 53), Vector2i(42, 61), Vector2i(56, 85), Vector2i(77, 70)]:
		_build("police", p)
	for p: Vector2i in [Vector2i(53, 35), Vector2i(68, 53), Vector2i(42, 70), Vector2i(44, 88), Vector2i(80, 67)]:
		_build("fire", p)
	for p: Vector2i in [Vector2i(50, 41), Vector2i(65, 38), Vector2i(59, 53), Vector2i(53, 67), Vector2i(50, 91),
			Vector2i(41, 77)]:
		_build("school", p)
	for p: Vector2i in [Vector2i(62, 53), Vector2i(53, 94), Vector2i(44, 76)]:
		_build("hospital", p)

	# Parks and the golf links.
	for r: Array in [[Vector2i(53, 37), Vector2i(54, 38)], [Vector2i(62, 40), Vector2i(63, 41)],
			[Vector2i(59, 46), Vector2i(60, 47)], [Vector2i(62, 46), Vector2i(63, 47)],
			[Vector2i(65, 46), Vector2i(66, 47)], [Vector2i(68, 46), Vector2i(69, 50)],
			[Vector2i(44, 64), Vector2i(45, 65)], [Vector2i(59, 58), Vector2i(63, 66)],
			[Vector2i(41, 91), Vector2i(42, 92)], [Vector2i(47, 79), Vector2i(48, 80)]]:
		_build("park", r[0], r[1])
	_build("golf", Vector2i(45, 97), Vector2i(58, 102))

	# Landmarks and transport: built as soon as the town is big enough for each.
	_later("library", Vector2i(59, 50))
	_later("town_hall", Vector2i(62, 50))
	_later("bus_depot", Vector2i(47, 71))
	_later("bus_depot", Vector2i(56, 91))
	_later("solar", Vector2i(86, 60), Vector2i(89, 64))
	_later("harbour", _harbour, _harbour, true)
	_later("gas", Vector2i(77, 79))
	_later("recycling", Vector2i(80, 73))
	_later("marina", _marina, _marina, true)
	_later("museum", Vector2i(65, 50))
	_later("station", Vector2i(53, 61))
	_later("stadium", Vector2i(59, 68))
	_later("nuclear", Vector2i(83, 73))


func _build(id: String, from: Vector2i, to: Vector2i = Vector2i(-1, -1)) -> int:
	# Exactly what a mouse drag from `from` to `to` does with this Build menu item.
	if to.x < 0:
		to = from
	sim.money = RICH
	game.call("_choose_item", id)
	game.set("drag_start", from)
	var plan: Array[Vector2i] = game.call("_plan_tiles", from, to)
	var ok := 0
	var why_not := ""
	for p: Vector2i in plan:
		var why: String = game.call("_why_cant_build", p)
		if why == "":
			ok += 1
		elif why != "-" and why_not == "":
			why_not = why
	game.set("drag_plan", plan)
	game.call("_finish_drag")
	if ok == 0:
		print("[shots]   couldn't build %s at %s: %s" % [id, from, why_not if why_not != "" else "nothing to do"])
	return ok


func _later(id: String, from: Vector2i, to: Vector2i = Vector2i(-1, -1), near_sea: bool = false) -> void:
	_pending.append([id, from, to if to.x >= 0 else from, near_sea])


func _build_unlocked() -> void:
	var still: Array = []
	for item: Array in _pending:
		var id: String = item[0]
		var unlock: int = Settings.BUILDINGS[id].get("unlock", 0)
		if sim.population < unlock:
			still.append(item)
			continue
		var from: Vector2i = item[1]
		var to: Vector2i = item[2]
		var near_sea: bool = item[3]
		if near_sea:
			from = _coast_spot(id, from)
			to = from
			if id == "harbour":
				_harbour = from
			elif id == "marina":
				_marina = from
		if from.x >= 0:
			_build(id, from, to)
			print("[shots]   month %d, %d people: built %s at %s" % [sim.month, sim.population, id, from])
	_pending = still


func _coast_spot(id: String, near: Vector2i) -> Vector2i:
	# The nearest tile to `near` where this seaside building may go and has a road.
	game.call("_choose_item", id)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y: int in range(near.y - 10, near.y + 11):
		for x: int in range(near.x - 10, near.x + 11):
			var p := Vector2i(x, y)
			if x < 0 or y < 0 or x >= sim.w or y >= sim.h:
				continue
			var i := y * sim.w + x
			var here: int = sim.tiles[i]
			if sim.is_service(here) or sim.is_building(here) or not sim.near_road(i):
				continue
			var why: String = game.call("_why_cant_build", p)
			var d := (p - near).length_squared()
			if why == "" and d < best_d:
				best = p
				best_d = d
	if best.x < 0:
		print("[shots]   no seaside spot for %s near %s" % [id, near])
	return best


func _fast_forward() -> void:
	# Month after month with the simulation's own tick(), as the game clock does.
	var t0 := Time.get_ticks_msec()
	for m: int in MAX_MONTHS:
		sim.money = RICH
		_build_unlocked()
		# The engine draws from the global generator too (smoke particles), and
		# tick() shuffles with it, so reseed it each month.
		seed(SEED + sim.month)
		sim.tick()
		if sim.month % 12 == 0:
			_status()
			await get_tree().process_frame      # keep the window alive
		if sim.month >= MIN_MONTHS and _pending.is_empty() and _count_stage(Simulation.Tile.HOMES, 8) \
				+ _count_stage(Simulation.Tile.SHOPS, 8) >= 2:
			break
	_status()
	print("[shots] %d months in %.1f s" % [sim.month, (Time.get_ticks_msec() - t0) / 1000.0])
	for item: Array in _pending:
		print("[shots]   never unlocked: %s (needs %d people)" % [item[0], int(Settings.BUILDINGS[item[0]].get("unlock", 0))])


func _status() -> void:
	var stages := ""
	for t: int in [Simulation.Tile.HOMES, Simulation.Tile.SHOPS, Simulation.Tile.INDUSTRY]:
		var top := 3 if t == Simulation.Tile.INDUSTRY else 8
		var parts: Array[String] = []
		for s: int in range(1, top + 1):
			parts.append(str(_count_stage(t, s)))
		stages += " %s[%s]" % [["", "", "homes", "shops", "industry"][t], " ".join(parts)]
	print("[shots]   month %3d  pop %6d  happy %2d%%  power %d/%d  water %d/%d  empty plots %d  abandoned %d %s" % [
		sim.month, sim.population, roundi(sim.happiness * 100.0), sim.power_used, sim.power_supply,
		sim.water_used, sim.water_supply, _count_stage(-1, 0), sim.abandoned_count, stages])


func _count_stage(t: int, s: int) -> int:
	# Built plots of zone type t at stage s (t = -1: empty zone plots of any kind).
	var n := 0
	for i: int in sim.w * sim.h:
		var here: int = sim.tiles[i]
		if not sim.is_zone(here):
			continue
		if t < 0:
			if sim.levels[i] == 0:
				n += 1
		elif here == t and sim.levels[i] > 0 and sim.stage(i) == s:
			n += 1
	return n


func _showcase() -> void:
	# Push a few plots to any building stage the run didn't reach (or reached too
	# rarely), so every kind of building shows up. Tallest first, most valuable
	# land first, from plots that could legally grow that tall.
	var values := sim.land_value_map()
	var taken := {}
	for t: int in [Simulation.Tile.HOMES, Simulation.Tile.SHOPS, Simulation.Tile.INDUSTRY]:
		var want: Array = WANT_INDUSTRY if t == Simulation.Tile.INDUSTRY else (
			WANT_HOMES if t == Simulation.Tile.HOMES else WANT_SHOPS)
		for s: int in range(want.size() - 1, 0, -1):
			var need: int = want[s]
			var have := _count_stage(t, s)
			while have < need:
				var best := -1
				var best_score := -INF
				for i: int in sim.w * sim.h:
					if sim.tiles[i] != t or taken.has(i) or sim.is_abandoned(i) or sim.levels[i] == 0:
						continue
					if sim.stage_at(i, sim.max_level(i)) < s or sim.stage(i) == s:
						continue
					# Close to the stage it should become; taller ones on the best land.
					var score: float = -absf(sim.stage(i) - s) + (values[i] * 4.0 if s >= 4 else 0.0)
					if score > best_score:
						best_score = score
						best = i
				if best < 0:
					_forced.append("no plot can become %s stage %d" % [_zone_word(t), s])
					break
				var start: int = 0 if t == Simulation.Tile.INDUSTRY else Settings.DENSITY_START[sim.density[best]]
				_forced.append("%s at (%d, %d): stage %d -> %d" % [_zone_word(t), best % sim.w, best / sim.w,
					sim.stage(best), s])
				sim.levels[best] = s - start
				taken[best] = true
				have += 1


func _zone_word(t: int) -> String:
	return {Simulation.Tile.HOMES: "homes", Simulation.Tile.SHOPS: "shops", Simulation.Tile.INDUSTRY: "industry"}[t]


func _finish_town() -> void:
	# Bring the drawing and the HUD up to date, as the game does after a month.
	sim.set("_power_dirty", true)
	sim.set("_value_dirty", true)
	sim.set("_coverage_dirty", true)
	sim.recount()
	sim.money = SHOWN_MONEY
	game.call("_select_tool", 0)      # (Tool.ROAD)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	world.refresh_all()
	game.set("_layout_seen", sim.layout_version)
	game.set("_ground_dirty", false)
	game.set("_buildings_dirty", false)
	game.call("_refresh_hud")


func _report() -> void:
	print("[shots] town: month %d (%s), %d people, %d skyscrapers" % [sim.month, sim.date_text(), sim.population,
		_count_tall(7)])
	print("[shots]   town checksum %d (the same every run unless the rules or this script change)" % [
		hash([sim.tiles, sim.levels, sim.density, sim.district])])
	for line: String in _forced:
		print("[shots]   showcase: %s" % line)
	var have: Array[String] = []
	for t: int in Simulation.BUILDING_KEYS:
		if sim.count_of(t) == 0:
			have.append(String(Simulation.BUILDING_KEYS[t]))
	if not have.is_empty():
		print("[shots]   missing buildings: %s" % ", ".join(have))
	# Why the zone plots still empty haven't been built on (the most common reasons).
	var why_empty := {}
	for i: int in sim.w * sim.h:
		if sim.is_zone(sim.tiles[i]) and sim.levels[i] == 0:
			var key := "%s: %s" % [_zone_word(sim.tiles[i]), sim.zone_status(i)]
			why_empty[key] = int(why_empty.get(key, 0)) + 1
	for key: String in why_empty:
		print("[shots]   empty plots, %d x %s" % [int(why_empty[key]), key])
	var wind := 46 * sim.w + 92
	if sim.tiles[wind] == Simulation.Tile.WIND:
		print("[shots]   wind farm on the town's power network: %s" % ("yes" if sim.power_map()[wind] == 1 and
			sim.get("_net_id")[wind] == sim.get("_net_id")[79 * sim.w + 83] else "NO"))


func _count_tall(from_stage: int) -> int:
	var n := 0
	for s: int in range(from_stage, 9):
		n += _count_stage(Simulation.Tile.HOMES, s) + _count_stage(Simulation.Tile.SHOPS, s)
	return n


# ------------------------------------------------------------------ the shots

func _shot_list() -> Array[Dictionary]:
	# at: the tile the camera looks at; yaw/pitch in degrees (yaw -45 = from the
	# south-west, with the afternoon sun behind); dist in metres.
	var hp := Vector2(_harbour)
	var mp := Vector2(_marina)
	var low_pitch: float = rad_to_deg(CameraRig.MIN_PITCH)
	return [
		{"name": "01_overview", "at": Vector2(60, 66), "yaw": -40.0, "pitch": 40.0, "dist": 3500.0},
		{"name": "02_suburb", "at": Vector2(47, 37), "yaw": -40.0, "pitch": 34.0, "dist": 520.0},
		{"name": "03_tenements_shops", "at": Vector2(52, 50), "yaw": -35.0, "pitch": 32.0, "dist": 480.0},
		{"name": "04_cbd", "at": Vector2(46, 64), "yaw": -40.0, "pitch": 24.0, "dist": 1050.0},
		{"name": "05_industry_power", "at": Vector2(81, 77), "yaw": -50.0, "pitch": 32.0, "dist": 650.0},
		{"name": "06_civic", "at": Vector2(63, 51), "yaw": -30.0, "pitch": 38.0, "dist": 560.0},
		{"name": "07_coast", "at": (hp + mp) * 0.5 + Vector2(4, 4), "yaw": -60.0, "pitch": 30.0, "dist": 800.0},
		{"name": "08_countryside", "at": Vector2(72, 118), "yaw": -75.0, "pitch": 26.0, "dist": 1600.0},
		{"name": "09_night", "at": Vector2(48, 64), "yaw": -40.0, "pitch": 28.0, "dist": 1500.0, "time": NIGHT},
		{"name": "10_street_level", "at": Vector2(52, 48), "yaw": -90.0, "pitch": low_pitch,
			"dist": CameraRig.MIN_DISTANCE},
		{"name": "11_hud_build_menu", "at": Vector2(52, 60), "yaw": -40.0, "pitch": 40.0, "dist": 1500.0,
			"hud": true, "prep": _prep_build_menu},
		{"name": "12_hud_overlay", "at": Vector2(58, 62), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"hud": true, "prep": _prep_overlay},
		{"name": "13_hud_plain", "at": Vector2(55, 58), "yaw": -40.0, "pitch": 38.0, "dist": 1700.0,
			"hud": true, "prep": _prep_plain},
		# More of the interface: the drop-downs, at night, a small window, help,
		# and the card for whatever is under the mouse.
		{"name": "14_hud_panels", "at": Vector2(52, 60), "yaw": -40.0, "pitch": 40.0, "dist": 1500.0,
			"hud": true, "prep": _prep_panels},
		{"name": "15_hud_night", "at": Vector2(48, 64), "yaw": -40.0, "pitch": 28.0, "dist": 1500.0,
			"time": NIGHT, "hud": true, "prep": _prep_night},
		{"name": "16_hud_small", "at": Vector2(58, 62), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"hud": true, "prep": _prep_small, "size": SMALL_SIZE},
		{"name": "17_hud_help", "at": Vector2(55, 58), "yaw": -40.0, "pitch": 38.0, "dist": 1700.0,
			"hud": true, "prep": _prep_help},
		{"name": "18_hud_query", "at": Vector2(52, 50), "yaw": -35.0, "pitch": 32.0, "dist": 480.0,
			"hud": true, "prep": _prep_query, "hover": true},
	]


const SMALL_SIZE := Vector2i(1280, 720)   # the smallest window the interface is laid out for


func _hud_reset() -> void:
	# Every HUD shot starts from the same state: drop-downs shut, Build menu open.
	hud.help_panel.visible = false
	hud.city_panel.visible = false
	hud.get("_city_button").set_pressed_no_signal(false)
	hud.get("_advice_list").visible = false
	hud.get("_advice_count").set_pressed_no_signal(false)
	hud.get("_menu_panel").visible = false
	hud.get("_menu_button").set_pressed_no_signal(false)
	hud.set_build_open(true)
	hud.message_label.text = ""


func _prep_build_menu() -> void:
	_hud_reset()
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_choose_item", "shops_2")


func _prep_overlay() -> void:
	_hud_reset()
	hud.set_build_open(false)
	game.call("_select_tool", 0)
	game.call("_set_overlay", WorldView.Overlay.LAND_VALUE)


func _prep_plain() -> void:
	_hud_reset()
	game.call("_set_overlay", WorldView.Overlay.NONE)
	hud.set_build_open(false)
	game.call("_select_tool", 0)


func _prep_panels() -> void:
	_hud_reset()
	game.call("_set_overlay", WorldView.Overlay.NONE)
	hud.set_build_open(false)
	game.call("_select_tool", 0)
	hud.get("_city_button").button_pressed = true
	hud.get("_advice_count").button_pressed = true
	hud.get("_menu_button").button_pressed = true


func _prep_night() -> void:
	_hud_reset()
	game.call("_set_overlay", WorldView.Overlay.GROWTH)
	game.call("_choose_item", "police")
	hud.call("_show_category", "services")
	hud.flash("Advisor: a message, to see how it looks")
	hud.set("_message_time", 60.0)      # (still showing when the picture is taken)


func _prep_small() -> void:
	_hud_reset()
	get_window().size = SMALL_SIZE
	game.call("_set_overlay", WorldView.Overlay.GROWTH)
	game.call("_choose_item", "road")
	hud.call("_show_category", "all")
	hud.get("_city_button").button_pressed = true


func _prep_help() -> void:
	_hud_reset()
	hud.set_build_open(false)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	hud.help_panel.visible = true


func _prep_query() -> void:
	_hud_reset()
	hud.set_build_open(false)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_choose_item", "bulldoze")


func _show_hover(at: Vector2) -> void:
	# Point the mouse (as far as the game knows) at the nearest built-up home plot.
	var best := Vector2i(-1, -1)
	var best_d := INF
	for i: int in sim.w * sim.h:
		if sim.tiles[i] == Simulation.Tile.HOMES and sim.levels[i] >= 2:
			var p := Vector2i(i % sim.w, floori(float(i) / sim.w))
			var d := Vector2(p).distance_to(at)
			if d < best_d:
				best_d = d
				best = p
	game.set("hover", best)
	world.set_hover(best, true)
	game.call("_update_info")
	for n: int in 3:
		await get_tree().process_frame
		RenderingServer.force_draw(false)


func _shoot(shot: Dictionary) -> void:
	var shot_name: String = shot["name"]
	var at: Vector2 = shot["at"]
	var wx: float = (at.x + 0.5) * world.cell
	var wz: float = (at.y + 0.5) * world.cell
	rig.target = Vector3(wx, maxf(world.height_at(wx, wz), 0.0), wz)
	rig.yaw = deg_to_rad(float(shot["yaw"]))
	rig.pitch = deg_to_rad(float(shot["pitch"]))
	rig.distance = float(shot["dist"])
	rig.snap()
	game.set("time_of_day", float(shot.get("time", DAY)))
	hud.visible = bool(shot.get("hud", false))
	hud.help_panel.visible = false
	if shot.has("prep"):
		var prep: Callable = shot["prep"]
		prep.call()
	elif world.overlay != WorldView.Overlay.NONE:
		game.call("_set_overlay", WorldView.Overlay.NONE)
	# macOS stops drawing a window that's hidden behind others, so every frame is
	# also drawn by hand (otherwise the shots would wait for ever).
	for n: int in SETTLE_FRAMES:
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	# No hover box or hover text from wherever the mouse happens to be.
	game.set("hover", Vector2i(-1, -1))
	world.set_hover(Vector2i(-1, -1), true)
	game.call("_update_info")
	for n: int in 3:
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	if shot.get("hover", false):
		await _show_hover(at)
	var want: Vector2i = shot.get("size", SHOT_SIZE)
	var image := get_viewport().get_texture().get_image()
	if want != SHOT_SIZE:
		get_window().size = SHOT_SIZE          # (back to normal for the next shot)
	if image.get_size() != want:
		print("[shots]   window is %s, not %s: scaling the picture" % [image.get_size(), want])
		image.resize(want.x, want.y, Image.INTERPOLATE_LANCZOS)
	var path := out_dir.path_join(shot_name + ".png")
	var err := image.save_png(path)
	if err != OK:
		_failed += 1
		printerr("[shots] couldn't save %s (error %d)" % [path, err])
	else:
		print("[shots] saved %s (%dx%d)" % [path, image.get_width(), image.get_height()])
