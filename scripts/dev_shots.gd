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
const WANT_OFFICES := [0, 3, 3, 3, 3, 3, 3, 3, 1]
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
var perf := false                     # --shots-perf: a table of what each part of the picture costs
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
		elif a == "--shots-perf":
			perf = true
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
	_skip_import(out_dir)
	print("[shots] saving to %s" % out_dir)
	# The same town every run: fix every random number generator the town uses.
	seed(SEED)
	sim.set("_rng", _seeded_rng(SEED))
	traffic.set("_rng", _seeded_rng(SEED + 1))
	game.call("_set_speed", 0)        # the game clock stays still; months are run below
	game.set("day_cycle", false)
	# Pictures in pixels, as the shots always were: no Retina interface or 3D scaling.
	game.set("fit_to_screen", false)
	get_window().content_scale_factor = 1.0
	get_viewport().scaling_3d_scale = 1.0
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
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
	if perf:
		await _perf_report()
		get_tree().quit(0)
		return

	for shot: Dictionary in _shot_list():
		var shot_name: String = shot["name"]
		if not _included(shot_name):
			continue
		await _shoot(shot)
	print("[shots] done in %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	get_tree().quit(1 if _failed > 0 else 0)


static func _skip_import(dir: String) -> void:
	# Pictures saved inside the project would be imported by the Godot editor as
	# game textures (slow, and clutter): a .gdignore file in the folder stops that.
	if dir.begins_with(ProjectSettings.globalize_path("res://")):
		var f := FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE)
		if f:
			f.close()


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
	_build("road", Vector2i(58, 100), Vector2i(66, 100))  # ...and on to the airport

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
		["shops_2", Vector2i(41, 58), Vector2i(45, 69)],     # ...round big stores...
		["offices_2", Vector2i(47, 58), Vector2i(51, 69)],   # ...and an office core
		["offices_1", Vector2i(53, 52), Vector2i(57, 56)],   # office chambers at the foot of the high street
		["offices_0", Vector2i(71, 58), Vector2i(72, 66)],   # small offices facing the works
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
	# The small ones, side by side in the north suburb.
	_build("police_office", Vector2i(44, 34))
	_build("fire_small", Vector2i(45, 34))
	_build("clinic", Vector2i(47, 34))

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
	_later("airport", Vector2i(60, 102), Vector2i(84, 108))
	# San Francisco's landmarks: two in the civic quarter, two in the seafront park,
	# the Ferry Building by the sea and Salesforce Tower in the CBD's office core.
	_later("painted_ladies", Vector2i(71, 53))
	_later("coit_tower", Vector2i(71, 50))
	_later("fine_arts", Vector2i(38, 74))
	_later("transamerica", Vector2i(38, 62))
	_later("salesforce_tower", Vector2i(50, 64))
	_later("ferry_building", Vector2i(36, 70), Vector2i(36, 70), true)


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
		best = _coast_with_road(id, near)
	if best.x < 0:
		print("[shots]   no seaside spot for %s near %s" % [id, near])
	return best


func _coast_with_road(id: String, near: Vector2i) -> Vector2i:
	# No seaside spot by the town's roads (the layouts were drawn for Troon, with
	# the sea to the west): take the seaside spot nearest `near` anywhere, and lay
	# a road to it from the nearest road, as a player would.
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	game.call("_choose_item", id)
	for y: int in sim.h:
		for x: int in sim.w:
			var p := Vector2i(x, y)
			var here: int = sim.tiles[y * sim.w + x]
			if here != Simulation.Tile.EMPTY or not sim.call("_beside_sea", y * sim.w + x):
				continue
			if String(game.call("_why_cant_build", p, false)) != "":
				continue
			var d := (p - near).length_squared()
			if d < best_d:
				best = p
				best_d = d
	if best.x < 0:
		return best
	var road := Vector2i(-1, -1)
	var road_d := 1 << 30
	for i: int in sim.w * sim.h:
		if sim.tiles[i] == Simulation.Tile.ROAD:
			var r := Vector2i(i % sim.w, i / sim.w)
			var d := (r - best).length_squared()
			if d < road_d:
				road = r
				road_d = d
	if road.x >= 0:
		var step := Vector2i(signi(road.x - best.x), signi(road.y - best.y))
		var beside := best + (Vector2i(step.x, 0) if step.x != 0 else Vector2i(0, step.y))
		_build("road", road, beside)
		print("[shots]   laid a road from %s to the shore at %s for the %s" % [road, beside, id])
	game.call("_choose_item", id)
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
	for t: int in [Simulation.Tile.HOMES, Simulation.Tile.SHOPS, Simulation.Tile.INDUSTRY, Simulation.Tile.OFFICES]:
		var want: Array = WANT_INDUSTRY if t == Simulation.Tile.INDUSTRY else (
			WANT_HOMES if t == Simulation.Tile.HOMES else (WANT_SHOPS if t == Simulation.Tile.SHOPS else WANT_OFFICES))
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
	return {Simulation.Tile.HOMES: "homes", Simulation.Tile.SHOPS: "shops", Simulation.Tile.INDUSTRY: "industry",
		Simulation.Tile.OFFICES: "offices"}[t]


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
		if sim.count_of(t) == 0 and t != Simulation.Tile.WOODLAND \
				and not Simulation.PROJECT_TILES.values().has(t):
			# (woodland is planted by the 37-41 shots; company projects only come with a deal)
			have.append(String(Simulation.BUILDING_KEYS[t]))
	if not have.is_empty():
		print("[shots]   missing buildings: %s" % ", ".join(have))
	traffic_report(sim, "[shots]")
	# Why the zone plots still empty haven't been built on (the most common reasons).
	var why_empty := {}
	for i: int in sim.w * sim.h:
		if sim.is_zone(sim.tiles[i]) and sim.levels[i] == 0:
			var key := "%s: %s" % [_zone_word(sim.tiles[i]), sim.zone_status(i)]
			why_empty[key] = int(why_empty.get(key, 0)) + 1
	for key: String in why_empty:
		print("[shots]   empty plots, %d x %s" % [int(why_empty[key]), key])
	# What drawing the town costs: one more re-plan of every plot, timed, and the
	# number of things in each of the town's MultiMeshes.
	var t0 := Time.get_ticks_usec()
	world.refresh_buildings()
	var counts: Array[String] = []
	for node_name: String in ["walls", "roofs", "chimneys", "paving", "props", "parked_bodies",
			"city_trunks", "city_crowns", "city_cones"]:
		var node: MultiMeshInstance3D = world.get(node_name)
		counts.append("%s %d" % [node_name, world.call("instance_total", node) if world.has_method("instance_total")
			else node.multimesh.instance_count])
	var model_items: Array = world.get("_model_items")
	counts.append("model parts %d" % model_items.size())
	print("[shots]   refresh_buildings %.0f ms; instances: %s" % [(Time.get_ticks_usec() - t0) / 1000.0,
		", ".join(counts)])
	print("[shots]   %s" % world.woods_report())
	var wind := 46 * sim.w + 92
	if sim.tiles[wind] == Simulation.Tile.WIND:
		print("[shots]   wind farm on the town's power network: %s" % ("yes" if sim.power_map()[wind] == 1 and
			sim.get("_net_id")[wind] == sim.get("_net_id")[79 * sim.w + 83] else "NO"))


static func traffic_report(s: Simulation, tag: String) -> void:
	# The traffic model on this town: how long it takes, and how the roads come out.
	var times: Array[String] = []
	for k: int in 3:
		s.set("_traffic_dirty", true)
		if k == 0:
			s.set("_graph_version", -1)        # the first time also builds the road graph
		s.traffic_map()
		times.append("%.1f" % s.traffic_ms)
	var roads := [0, 0, 0, 0]
	var volume := [0.0, 0.0, 0.0, 0.0]
	var busiest := 0.0
	var busiest_at := -1
	var quiet := 0
	for i: int in s.w * s.h:
		var band := s.traffic_band(i)
		if band < 0:
			continue
		var v := s.traffic_at(i)
		roads[band] += 1
		volume[band] += v
		if v < 100.0:
			quiet += 1
		if v > busiest:
			busiest = v
			busiest_at = i
	var n: int = roads[0] + roads[1] + roads[2] + roads[3]
	var total: float = volume[0] + volume[1] + volume[2] + volume[3]
	print("%s traffic model: %s ms (first with the road graph), %d car trips a day, %d by bus or train, %d%% of trips in jams" % [
		tag, " / ".join(times), s.traffic_trips, s.transit_trips, roundi(s.traffic_jammed_share() * 100.0)])
	if n > 0:
		print("%s   road tiles: %d free-flowing, %d busy, %d heavy, %d jammed (%d%% / %d%% / %d%% / %d%%); %d carry under 100 trips; busiest %d trips at (%d, %d); capacity %d" % [
			tag, roads[0], roads[1], roads[2], roads[3], roundi(100.0 * roads[0] / n), roundi(100.0 * roads[1] / n),
			roundi(100.0 * roads[2] / n), roundi(100.0 * roads[3] / n), quiet, roundi(busiest), busiest_at % s.w,
			busiest_at / s.w, roundi(s.road_capacity())])
		print("%s   share of driving: free-flowing %d%%, busy %d%%, heavy %d%%, jammed %d%%" % [tag,
			roundi(100.0 * volume[0] / total), roundi(100.0 * volume[1] / total), roundi(100.0 * volume[2] / total),
			roundi(100.0 * volume[3] / total)])
		var all := PackedFloat32Array()
		for i: int in s.w * s.h:
			if s.tiles[i] == Simulation.Tile.ROAD:
				all.append(s.traffic_at(i))
		all.sort()
		var marks: Array[String] = []
		for p: int in [25, 50, 75, 90, 95, 99]:
			marks.append("%d%% under %d" % [p, roundi(all[mini(all.size() - 1, all.size() * p / 100)])])
		print("%s   trips a day per road tile: %s" % [tag, ", ".join(marks)])


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
	var ferry := Vector2(108, 86)           # (wherever the Ferry Building found the shore)
	for i: int in sim.tiles.size():
		if sim.tiles[i] == Simulation.Tile.FERRY_BUILDING:
			ferry = Vector2(i % sim.w, i / sim.w)
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
		{"name": "17b_hud_help_controls", "at": Vector2(55, 58), "yaw": -40.0, "pitch": 38.0, "dist": 1700.0,
			"hud": true, "prep": _prep_help.bind("controls")},
		{"name": "17c_hud_help_tech", "at": Vector2(55, 58), "yaw": -40.0, "pitch": 38.0, "dist": 1700.0,
			"hud": true, "prep": _prep_help.bind("tech")},
		{"name": "17d_hud_help_small", "at": Vector2(55, 58), "yaw": -40.0, "pitch": 38.0, "dist": 1700.0,
			"hud": true, "prep": _prep_help.bind("zones"), "size": SMALL_SIZE},
		{"name": "18_hud_query", "at": Vector2(52, 50), "yaw": -35.0, "pitch": 32.0, "dist": 480.0,
			"hud": true, "prep": _prep_query, "hover": true},
		# Money: the New city dialog (from the menu; and on a small window, as when
		# the game opens) and the City panel's Loans with a loan taken out.
		{"name": "34_hud_new_city", "at": Vector2(55, 58), "yaw": -40.0, "pitch": 38.0, "dist": 1700.0,
			"hud": true, "prep": _prep_new_city},
		{"name": "35_hud_new_city_small", "at": Vector2(55, 58), "yaw": -40.0, "pitch": 38.0, "dist": 1700.0,
			"hud": true, "prep": _prep_new_city_small, "size": SMALL_SIZE},
		{"name": "36_hud_loans", "at": Vector2(52, 60), "yaw": -40.0, "pitch": 40.0, "dist": 1500.0,
			"hud": true, "prep": _prep_loans},
		# Traffic (they don't change the town): the Traffic view of the whole town,
		# close up with a busy road hovered, in the smallest window (10 map view
		# icons), and the normal view where a busy road meets quiet streets, after
		# the cars have driven for a while (they follow the traffic model).
		{"name": "42_traffic_overview", "at": Vector2(60, 66), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"hud": true, "prep": _prep_traffic},
		{"name": "43_traffic_close", "at": TRAFFIC_CLOSE, "yaw": -40.0, "pitch": 45.0, "dist": 900.0,
			"hud": true, "prep": _prep_traffic, "hover_road": true},
		{"name": "44_traffic_small", "at": Vector2(60, 66), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"hud": true, "prep": _prep_traffic_small, "size": SMALL_SIZE},
		{"name": "45_traffic_cars", "at": TRAFFIC_CARS, "yaw": -40.0, "pitch": 36.0, "dist": 420.0,
			"prep": _prep_traffic_cars, "drive": 25.0},
		# The Services view (they don't change the town): all four, then each service
		# on its own; a home hovered (which services reach it); placing a school (the
		# disc it would reach, the view showing schools); map views at night (lit by
		# day); and the smallest window (chips, key and the 10 icons).
		{"name": "46_services_all", "at": SERVICES_AT, "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"hud": true, "prep": _prep_services.bind(-1)},
		{"name": "47_services_police", "at": SERVICES_AT, "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"hud": true, "prep": _prep_services.bind(0)},
		{"name": "48_services_fire", "at": SERVICES_AT, "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"hud": true, "prep": _prep_services.bind(1)},
		{"name": "49_services_schools", "at": SERVICES_AT, "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"hud": true, "prep": _prep_services.bind(2)},
		{"name": "50_services_hospitals", "at": SERVICES_AT, "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"hud": true, "prep": _prep_services.bind(3)},
		{"name": "51_services_hover", "at": Vector2(52, 50), "yaw": -35.0, "pitch": 40.0, "dist": 700.0,
			"hud": true, "prep": _prep_services.bind(2), "hover": true},
		{"name": "52_services_place_school", "at": SERVICES_AT, "yaw": -40.0, "pitch": 50.0, "dist": 2000.0,
			"hud": true, "prep": _prep_place_school, "point_at_spot": true},
		{"name": "53_night_services", "at": SERVICES_AT, "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"time": NIGHT, "hud": true, "prep": _prep_services.bind(2)},
		{"name": "54_night_traffic", "at": Vector2(60, 66), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"time": NIGHT, "hud": true, "prep": _prep_traffic},
		{"name": "55_night_pollution", "at": Vector2(60, 66), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"time": NIGHT, "hud": true, "prep": _prep_view.bind(WorldView.Overlay.POLLUTION)},
		{"name": "56_night_land_value", "at": Vector2(60, 66), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"time": NIGHT, "hud": true, "prep": _prep_view.bind(WorldView.Overlay.LAND_VALUE)},
		{"name": "57_services_small", "at": SERVICES_AT, "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"hud": true, "prep": _prep_services_small, "size": SMALL_SIZE},
		# The natural surroundings: a beach close up, the hills, and the edge of the map.
		{"name": "19_beach", "at": Vector2(44, 108), "yaw": -70.0, "pitch": 34.0, "dist": 320.0},
		{"name": "20_hills", "at": Vector2(112, 40), "yaw": -40.0, "pitch": 30.0, "dist": 1500.0},
		{"name": "21_map_edge", "at": Vector2(132, 112), "yaw": -55.0, "pitch": 32.0, "dist": 2400.0},
		# The ground of the town close up: gardens, a park, works yards, tenement
		# back courts, shops' car parks, and (last, as it zones a few plots) empty
		# plots and building sites.
		{"name": "22_gardens", "at": Vector2(44, 39), "yaw": -40.0, "pitch": 42.0, "dist": 190.0},
		{"name": "23_park", "at": Vector2(37, 64), "yaw": -40.0, "pitch": 40.0, "dist": 260.0},
		{"name": "24_yards", "at": Vector2(78, 65), "yaw": -50.0, "pitch": 38.0, "dist": 240.0},
		{"name": "25_back_courts", "at": Vector2(41, 50), "yaw": -35.0, "pitch": 45.0, "dist": 210.0},
		{"name": "26_shops", "at": Vector2(55, 52), "yaw": -35.0, "pitch": 40.0, "dist": 230.0},
		# Buildings close up (before 27, which must stay last): skyscrapers, works, the
		# high street, civic buildings, the towers at night.
		{"name": "28_towers", "at": Vector2(46, 63), "yaw": -40.0, "pitch": 22.0, "dist": 520.0},
		{"name": "29_works", "at": Vector2(80, 70), "yaw": -50.0, "pitch": 34.0, "dist": 330.0},
		{"name": "30_high_street", "at": Vector2(54, 50), "yaw": -60.0, "pitch": 18.0, "dist": 170.0},
		{"name": "31_civic_close", "at": Vector2(62, 51), "yaw": -30.0, "pitch": 32.0, "dist": 260.0},
		# Offices: the CBD's office core, the chambers by the high street, the small
		# offices by the works, and the Build menu's Zones list with the demand bars.
		{"name": "60_offices_core", "at": Vector2(49, 63), "yaw": -40.0, "pitch": 26.0, "dist": 520.0},
		{"name": "61_offices_chambers", "at": Vector2(55, 54), "yaw": -35.0, "pitch": 36.0, "dist": 230.0},
		{"name": "62_offices_small", "at": Vector2(71, 62), "yaw": -50.0, "pitch": 38.0, "dist": 260.0},
		# The small services in the north suburb: police office, small fire station, clinic.
		{"name": "63_small_services", "at": Vector2(46, 34.5), "yaw": -40.0, "pitch": 36.0, "dist": 190.0},
		{"name": "64_small_services_view", "at": Vector2(44, 38), "yaw": -40.0, "pitch": 55.0, "dist": 1500.0,
			"hud": true, "prep": _prep_services.bind(0)},
		# The airport south-east of the links: all of it, the terminal and stands, the Build menu's card.
		{"name": "65_airport", "at": Vector2(72, 105), "yaw": -40.0, "pitch": 38.0, "dist": 1300.0},
		{"name": "66_airport_terminal", "at": Vector2(64, 103.5), "yaw": -60.0, "pitch": 30.0, "dist": 330.0},
		# Landmarks: the seafront (Eiffel Tower, Taj Mahal, Great Pyramid and the two by
		# the sea), the civic quarter (Big Ben, Colosseum), the skyline with the Empire State.
		{"name": "67_landmarks_seafront", "at": Vector2(39, 70), "yaw": -70.0, "pitch": 28.0, "dist": 1100.0},
		{"name": "67b_ferry_building", "at": ferry, "yaw": -50.0, "pitch": 24.0, "dist": 380.0},
		{"name": "68_landmarks_civic", "at": Vector2(70, 51.5), "yaw": -30.0, "pitch": 30.0, "dist": 330.0},
		{"name": "69_landmarks_skyline", "at": Vector2(47, 64), "yaw": -20.0, "pitch": 16.0, "dist": 900.0},
		{"name": "70_landmarks_night", "at": Vector2(42, 66), "yaw": -60.0, "pitch": 22.0, "dist": 1000.0, "time": NIGHT},
		{"name": "32_towers_night", "at": Vector2(46, 63), "yaw": -40.0, "pitch": 22.0, "dist": 620.0,
			"time": NIGHT},
		{"name": "33_abandoned", "at": Vector2(54, 51), "yaw": -35.0, "pitch": 38.0, "dist": 230.0,
			"prep": _prep_abandoned},
		# Planted woodland (the prep plants it, so these come after the standard
		# shots): a forest between the terraces, the works and the natural woods to
		# the east; close up, at its edge by the houses, from afar, with the
		# Pollution view, and at night.
		{"name": "37_woodland", "at": Vector2(80, 41), "yaw": -40.0, "pitch": 34.0, "dist": 560.0,
			"prep": _prep_woodland},
		{"name": "38_woodland_edge", "at": Vector2(73, 36), "yaw": -65.0, "pitch": 30.0, "dist": 230.0,
			"prep": _prep_woodland},
		{"name": "39_woodland_far", "at": Vector2(78, 46), "yaw": -40.0, "pitch": 40.0, "dist": 2400.0,
			"prep": _prep_woodland},
		{"name": "40_woodland_overlay", "at": Vector2(76, 52), "yaw": -40.0, "pitch": 55.0, "dist": 2000.0,
			"hud": true, "prep": _prep_woodland_overlay},
		{"name": "41_woodland_night", "at": Vector2(80, 41), "yaw": -40.0, "pitch": 34.0, "dist": 560.0,
			"time": NIGHT, "prep": _prep_woodland},
		# A school closed (this changes the town, so after the standard shots; far
		# from 27's plots): the homes it served turn red in the Services view, and
		# placing a school shows where it would help.
		{"name": "58_services_school_gone", "at": Vector2(SCHOOL_GONE), "yaw": -40.0, "pitch": 50.0, "dist": 1500.0,
			"hud": true, "prep": _prep_school_gone},
		{"name": "59_services_school_gap", "at": Vector2(SCHOOL_GONE), "yaw": -40.0, "pitch": 50.0, "dist": 1500.0,
			"hud": true, "prep": _prep_place_school, "point_at_spot": true},
		# Kinds of road (the prep widens two streets into avenues and lays a motorway
		# round the east and south of the town, so these come after the standard shots;
		# clear of 27's plots): an avenue through the old town, two avenues crossing,
		# the motorway and where an avenue joins it, the Traffic view, night, the menu.
		{"name": "71_avenue", "at": Vector2(52, 51), "yaw": -35.0, "pitch": 34.0, "dist": 260.0,
			"prep": _prep_road_types, "drive": 20.0},
		{"name": "72_avenue_crossing", "at": Vector2(52, 57), "yaw": -40.0, "pitch": 42.0, "dist": 190.0,
			"prep": _prep_road_types, "drive": 20.0},
		{"name": "73_motorway", "at": Vector2(90, 70), "yaw": -55.0, "pitch": 30.0, "dist": 420.0,
			"prep": _prep_road_types, "drive": 20.0},
		{"name": "74_motorway_junction", "at": Vector2(90, 57), "yaw": -40.0, "pitch": 42.0, "dist": 220.0,
			"prep": _prep_road_types, "drive": 20.0},
		{"name": "75_roads_traffic", "at": Vector2(64, 64), "yaw": -40.0, "pitch": 55.0, "dist": 3400.0,
			"hud": true, "prep": _prep_road_types_traffic},
		{"name": "76_roads_night", "at": Vector2(52, 57), "yaw": -40.0, "pitch": 36.0, "dist": 300.0,
			"time": NIGHT, "prep": _prep_road_types, "drive": 10.0},
		{"name": "77_roads_menu", "at": Vector2(88, 60), "yaw": -40.0, "pitch": 40.0, "dist": 700.0,
			"hud": true, "prep": _prep_road_types_menu},
		{"name": "27_empty_plots", "at": Vector2(43, 29), "yaw": -40.0, "pitch": 38.0, "dist": 230.0,
			"prep": _prep_empty_plots},
	]


const SMALL_SIZE := Vector2i(1280, 720)   # the smallest window the interface is laid out for
const TRAFFIC_CLOSE := Vector2(68, 58)    # the link between the town and the works (the busiest road)
const TRAFFIC_CARS := Vector2(66, 57)
const SERVICES_AT := Vector2(58, 64)      # the whole town, for the Services view
const SCHOOL_GONE := Vector2i(53, 67)     # the school 58 closes (in the CBD)
var _spot := Vector2i(-1, -1)             # where 52 and 59 point the mouse: the best place for a school


var _woodland_done := false


func _prep_woodland() -> void:
	# Plant a forest with the real build tool (once): 11 x 26 tiles east of the
	# terraces' last street, from the north edge of town down to the works, with
	# the natural woods beyond it. Far from 27's plots, so that shot is unchanged.
	_hud_reset()
	hud.set_build_open(false)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	if _woodland_done:
		return
	_woodland_done = true
	var probe := 55 * sim.w + 79       # in the forest's south end, by the works
	var smoke0 := sim.pollution_at(probe)
	print("[shots]   woods before planting: %s" % world.woods_report())
	var t0 := Time.get_ticks_usec()
	var n := _build("woodland", Vector2i(74, 31), Vector2i(84, 56))
	world.refresh_ground(true)
	game.set("_layout_seen", sim.layout_version)
	game.set("_ground_dirty", false)
	print("[shots]   planted %d woodland tiles (build and redraw %.0f ms); %s" % [n,
		(Time.get_ticks_usec() - t0) / 1000.0, world.woods_report()])
	print("[shots]   pollution at (79, 55), by the works: %.2f -> %.2f" % [smoke0, sim.pollution_at(probe)])
	sim.money = SHOWN_MONEY
	game.call("_select_tool", 0)
	game.call("_refresh_hud")


var _road_types_done := false


func _prep_road_types() -> void:
	# Widen two streets into avenues and lay a motorway round the town, with the
	# real Road tool (once). Far from 27's plots, so that shot is unchanged.
	_hud_reset()
	hud.set_build_open(false)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	traffic.set_enabled(true)
	if _road_types_done:
		return
	_road_types_done = true
	var busiest0 := 0.0
	for i: int in sim.w * sim.h:
		busiest0 = maxf(busiest0, sim.traffic_congestion_at(i) if sim.tiles[i] == Simulation.Tile.ROAD else 0.0)
	var jams0 := sim.traffic_jammed_share()
	var avenue := _build("avenue", Vector2i(52, 30), Vector2i(52, 96))
	avenue += _build("avenue", Vector2i(34, 57), Vector2i(90, 57))
	var motorway := _build("motorway", Vector2i(90, 28), Vector2i(90, 98))
	motorway += _build("motorway", Vector2i(90, 98), Vector2i(67, 98))
	_build("road", Vector2i(67, 99), Vector2i(67, 100))     # down to the airport road
	_build("road", Vector2i(86, 72), Vector2i(89, 72))      # the works
	_build("road", Vector2i(74, 28), Vector2i(89, 28))      # and round the north of the terraces
	_build("road", Vector2i(73, 28), Vector2i(73, 30))
	world.refresh_ground(true)
	game.set("_layout_seen", sim.layout_version)
	game.set("_ground_dirty", false)
	var busiest := 0.0
	var by_kind: Array[float] = [0.0, 0.0, 0.0]
	for i: int in sim.w * sim.h:
		if sim.tiles[i] == Simulation.Tile.ROAD:
			busiest = maxf(busiest, sim.traffic_congestion_at(i))
			by_kind[sim.road_kind[i]] = maxf(by_kind[sim.road_kind[i]], sim.traffic_at(i))
	print("[shots]   kinds of road: %d avenue and %d motorway tiles; fullest road %.0f%% -> %.0f%% full; in jams %.0f%% -> %.0f%%; busiest road %d, avenue %d, motorway %d trips a day; %.1f ms" % [
		avenue, motorway, busiest0 * 100.0, busiest * 100.0, jams0 * 100.0, sim.traffic_jammed_share() * 100.0,
		roundi(by_kind[0]), roundi(by_kind[1]), roundi(by_kind[2]), sim.traffic_ms])
	sim.money = SHOWN_MONEY
	game.call("_select_tool", 0)
	game.call("_refresh_hud")


func _prep_road_types_traffic() -> void:
	_prep_road_types()
	game.call("_set_overlay", WorldView.Overlay.TRAFFIC)


func _prep_road_types_menu() -> void:
	_prep_road_types()
	hud.set_build_open(true)
	game.call("_choose_item", "motorway")


func _prep_woodland_overlay() -> void:
	_prep_woodland()
	hud.set_build_open(false)
	game.call("_set_overlay", WorldView.Overlay.POLLUTION)


func _prep_abandoned() -> void:
	# Board up a few built plots (tenements and shops) to show the run-down look.
	# Far from 27's plots, so that shot is unchanged.
	for y: int in range(49, 54):
		for x: int in range(52, 57):
			var i := y * sim.w + x
			if sim.is_zone(sim.tiles[i]) and sim.levels[i] > 0 and (x + y) % 2 == 0:
				sim.abandoned[i] = 1
	world.refresh_buildings()


func _prep_empty_plots() -> void:
	# Zone a row of plots on the open land north of the suburb, by its top street:
	# homes at each density (no demand for homes, so they wait: empty plots) then
	# shops and industry (wanted, so they become building sites). This changes
	# the town, so it must stay the last shot.
	var kinds := [Simulation.Tile.HOMES, Simulation.Tile.HOMES, Simulation.Tile.HOMES, Simulation.Tile.SHOPS,
		Simulation.Tile.SHOPS, Simulation.Tile.INDUSTRY]
	for k: int in kinds.size():
		var i := 29 * sim.w + 40 + k
		if sim.tiles[i] == Simulation.Tile.EMPTY:
			sim.set_tile(i, kinds[k], [0, 1, 2, 1, 2, 0][k])
	world.refresh_all()


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
	hud.new_city_panel.visible = false
	hud.get("_new_dim").visible = false


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
	# The normal view: map views are always lit by day. (A service would switch
	# to the Services view, so a park is picked.)
	_hud_reset()
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_choose_item", "park")
	hud.call("_show_category", "leisure")
	hud.flash("Advisor: a message, to see how it looks")
	hud.set("_message_time", 60.0)      # (still showing when the picture is taken)


func _prep_small() -> void:
	_hud_reset()
	get_window().size = SMALL_SIZE
	game.call("_set_overlay", WorldView.Overlay.GROWTH)
	game.call("_choose_item", "road")
	hud.call("_show_category", "all")
	hud.get("_city_button").button_pressed = true


func _prep_help(page: String = "start") -> void:
	_hud_reset()
	hud.set_build_open(false)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	hud.show_help_page(page)
	hud.help_panel.visible = true


func _prep_new_city() -> void:
	_hud_reset()
	hud.set_build_open(false)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_ask_new_city", false)      # (as from the game menu: warns that it clears the city)


func _prep_new_city_small() -> void:
	_hud_reset()
	get_window().size = SMALL_SIZE
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_ask_new_city", true)       # (as when the game opens)
	hud.call("_pick_level", 0)


func _prep_loans() -> void:
	# A loan taken out on Normal, with £20,000 more than the limit allows: the
	# £20,000 button greyed out and the limit explained.
	_hud_reset()
	hud.set_build_open(false)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_select_tool", 0)
	sim.difficulty = Settings.DEFAULT_DIFFICULTY
	sim.debt = 0
	sim.debt_peak = 0
	for amount: int in [20000, 20000, 5000]:
		sim.borrow(amount)
	sim.money = SHOWN_MONEY
	sim.last_interest = sim.loan_interest()
	sim.last_loan = sim.loan_payment()
	game.call("_refresh_hud")
	hud.get("_city_button").button_pressed = true


func _prep_traffic() -> void:
	_hud_reset()
	hud.set_build_open(false)
	game.call("_select_tool", 0)
	game.call("_set_overlay", WorldView.Overlay.TRAFFIC)


func _prep_traffic_small() -> void:
	_prep_traffic()
	get_window().size = SMALL_SIZE


func _prep_traffic_cars() -> void:
	_hud_reset()
	game.call("_set_overlay", WorldView.Overlay.NONE)
	traffic.set_enabled(true)


func _prep_view(kind: int) -> void:
	_hud_reset()
	hud.set_build_open(false)
	game.call("_select_tool", 0)
	game.call("_set_overlay", kind)


func _prep_services(filter: int) -> void:
	# The Services view showing all four (-1) or one service, as its chip does.
	_prep_view(WorldView.Overlay.SERVICES)
	game.call("_set_service_filter", filter)
	print("[shots]   Services view, %s: %s" % ["all" if filter < 0 else Settings.SERVICE_WORDS[filter],
		hud.legend_note.text if filter >= 0 else "-"])


func _prep_services_small() -> void:
	_prep_services(2)
	get_window().size = SMALL_SIZE


func _prep_place_school() -> void:
	# The School picked in the Build menu: the Services view shows schools on its
	# own, and the mouse goes where a school would reach the most homes without one.
	_hud_reset()
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_choose_item", "school")
	_spot = _best_school_spot()
	var p := world.ground_point(_spot)
	rig.target = p
	rig.snap()
	print("[shots]   best place for a school: %s (%s)" % [_spot, sim.service_gain(2, _spot.y * sim.w + _spot.x)])


func _best_school_spot() -> Vector2i:
	# The home plot with no school whose neighbours (within 6 tiles) most lack one too.
	var best := Vector2i(-1, -1)
	var most := -1
	for i: int in sim.w * sim.h:
		if sim.tiles[i] != Simulation.Tile.HOMES or sim.covered(2, i):
			continue
		var x := i % sim.w
		var y := i / sim.w
		var n := 0
		for dy: int in range(-6, 7):
			for dx: int in range(-6, 7):
				var k := (y + dy) * sim.w + x + dx
				if k >= 0 and k < sim.w * sim.h and sim.tiles[k] == Simulation.Tile.HOMES and not sim.covered(2, k):
					n += 2 if sim.service_holds_back(2, k) else 1
		if n > most:
			most = n
			best = Vector2i(x, y)
	return best


func _prep_school_gone() -> void:
	# Bulldoze the CBD's school, as the Bulldoze tool does.
	var i := SCHOOL_GONE.y * sim.w + SCHOOL_GONE.x
	if sim.tiles[i] == Simulation.Tile.SCHOOL:
		_build("bulldoze", SCHOOL_GONE)
		# Some of the flats it served are still young (one level built), as in a
		# growing town: without the school they can't grow any further.
		var young := 0
		for y: int in range(SCHOOL_GONE.y - 9, SCHOOL_GONE.y + 10):
			for x: int in range(SCHOOL_GONE.x - 9, SCHOOL_GONE.x + 10):
				var k := y * sim.w + x
				if sim.tiles[k] == Simulation.Tile.HOMES and sim.density[k] >= 1 and sim.levels[k] > 1 \
						and not sim.covered(2, k) and (x + y) % 3 != 0:
					sim.levels[k] = 1
					young += 1
		sim.recount()
		print("[shots]   closed the school at %s; %d flats set back to their first level" % [SCHOOL_GONE, young])
		sim.money = SHOWN_MONEY
		world.refresh_all()
		game.set("_layout_seen", sim.layout_version)
		game.call("_refresh_hud")
	_prep_services(2)


func _point_at(at: Vector2) -> void:
	# Point the mouse (as far as the game knows) at a tile, as moving it there does.
	var tile := Vector2i(at)
	game.set("hover", tile)
	world.set_hover(tile, true)
	game.call("_update_reach_preview")
	game.call("_update_info")
	for n: int in 3:
		await get_tree().process_frame
		RenderingServer.force_draw(false)


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


func _show_road_hover(at: Vector2) -> void:
	# Point the mouse (as far as the game knows) at the busiest road near `at`.
	var best := Vector2i(-1, -1)
	var most := -1.0
	for y: int in range(int(at.y) - 6, int(at.y) + 7):
		for x: int in range(int(at.x) - 6, int(at.x) + 7):
			var i := y * sim.w + x
			if sim.tiles[i] == Simulation.Tile.ROAD and sim.traffic_at(i) > most:
				most = sim.traffic_at(i)
				best = Vector2i(x, y)
	print("[shots]   hovering the road at %s: %d trips a day" % [best, roundi(most)])
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
	if int(game.get("current_tool")) == 9:     # (Services: put down, so its view and disc go)
		game.call("_select_tool", 0)
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
	if shot_name.begins_with("04"):
		await _measure_speed()
	# No hover box or hover text from wherever the mouse happens to be.
	game.set("hover", Vector2i(-1, -1))
	world.set_hover(Vector2i(-1, -1), true)
	game.call("_update_info")
	for n: int in 3:
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	if shot.has("drive"):
		# Let the cars drive (the game clock is stopped in the shots), so queues form.
		var steps := roundi(float(shot["drive"]) * 30.0)
		for k: int in steps:
			traffic.update(1.0 / 30.0, rig.target, rig.distance)
		for n: int in 3:
			await get_tree().process_frame
			RenderingServer.force_draw(false)
	if shot.get("hover", false):
		await _show_hover(at)
	if shot.get("hover_road", false):
		await _show_road_hover(at)
	if shot.get("point_at_spot", false):
		await _point_at(Vector2(_spot))
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


const SPEED_FRAMES := 60
const SPEED_WARM_UP := 90

func _measure_speed() -> void:
	# Average drawing time over SPEED_FRAMES frames at this view, drawn back to
	# back by hand (so neither vsync nor macOS throttling a hidden window counts).
	# The GPU keeps at most a couple of frames queued, so this is roughly the
	# real cost of a frame: CPU and GPU together.
	for n: int in SPEED_WARM_UP:
		RenderingServer.force_draw(false)   # lets the GPU reach full speed first
	var start := Time.get_ticks_usec()
	for n: int in SPEED_FRAMES:
		RenderingServer.force_draw(false)
	var ms := (Time.get_ticks_usec() - start) / 1000.0 / SPEED_FRAMES
	print("[shots] speed at this view: %.2f ms per frame (%.0f fps) over %d frames"
		% [ms, 1000.0 / maxf(ms, 0.01), SPEED_FRAMES])
	await get_tree().process_frame


# ------------------------------------------------------- speed (--shots-perf)

static func measure(viewport: Viewport, frames: int = 30) -> Dictionary:
	# Draw `frames` frames back to back and average: wall time, the renderer's own
	# CPU and GPU time, and how many draw calls, triangles and objects a frame has.
	var vp := viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for n: int in 8:
		RenderingServer.force_draw(false)
	var cpu := 0.0
	var gpu := 0.0
	var start := Time.get_ticks_usec()
	for n: int in frames:
		RenderingServer.force_draw(false)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var wall := (Time.get_ticks_usec() - start) / 1000.0 / frames
	return {"wall": wall, "cpu": cpu / frames, "gpu": gpu / frames,
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))}


static func perf_line(label: String, m: Dictionary, base: Dictionary = {}) -> String:
	var saved := ""
	if not base.is_empty():
		saved = "  (%+.1f ms)" % (float(m["wall"]) - float(base["wall"]))
	return "%-22s wall %6.1f ms  cpu %5.1f  gpu %6.1f  draws %5d  tris %9d  objects %6d%s" % [label,
		float(m["wall"]), float(m["cpu"]), float(m["gpu"]), int(m["draws"]), int(m["prims"]), int(m["objects"]), saved]


static func perf_parts(w: WorldView, h: Hud, t: Traffic) -> Array:
	# [label, nodes to hide] for the cost table.
	var models: Array = []
	for key: String in w.get("_model_nodes"):
		models.append(w.get("_model_nodes")[key])
	var sea: Array = []
	for child: Node in w.get_children():
		var mi := child as MeshInstance3D
		if mi and mi.mesh is PlaneMesh:
			sea.append(mi)
	return [
		["terrain + far land", [w.terrain_root]],
		["sea", sea],
		["woods", [w.woods]],
		["city trees", [w.city_trunks, w.city_crowns, w.city_cones]],
		["props + parked cars", [w.props, w.parked_bodies, w.parked_cabins]],
		["paving", [w.paving]],
		["models", models],
		["box buildings", [w.walls, w.roofs, w.chimneys]],
		["roads", [w.road_instance]],
		["pylons + cables", [w.pylons, w.cables]],
		["alerts + smoke", [w.alerts, w.smoke]],
		["traffic", [t]],
		["HUD", [h]],
	]


func _perf_report() -> void:
	print("[perf] window %s, %d frames each" % [get_window().size, 30])
	for view: Array in [["04_cbd", Vector2(46, 64), -40.0, 24.0, 1050.0], ["02_suburb", Vector2(47, 37), -40.0, 34.0, 520.0],
			["01_overview", Vector2(60, 66), -40.0, 40.0, 3500.0]]:
		if not _included(String(view[0])):
			continue
		var at: Vector2 = view[1]
		var wx: float = (at.x + 0.5) * world.cell
		var wz: float = (at.y + 0.5) * world.cell
		rig.target = Vector3(wx, maxf(world.height_at(wx, wz), 0.0), wz)
		rig.yaw = deg_to_rad(float(view[2]))
		rig.pitch = deg_to_rad(float(view[3]))
		rig.distance = float(view[4])
		rig.snap()
		game.set("time_of_day", DAY)
		hud.visible = true
		for n: int in SETTLE_FRAMES:
			await get_tree().process_frame
			RenderingServer.force_draw(false)
		await perf_table(self, String(view[0]), world, hud, traffic)


static func perf_table(node: Node, title: String, w: WorldView, h: Hud, t: Traffic) -> void:
	var vp := node.get_viewport()
	print("[perf] --- %s (window %s, 3D drawn at %d%%) ---" % [title, vp.get_visible_rect().size, roundi(vp.scaling_3d_scale * 100.0)])
	var base := measure(vp)
	print("[perf] " + perf_line("everything", base))
	for part: Array in perf_parts(w, h, t):
		var nodes: Array = part[1]
		var was: Array[bool] = []
		for n: Node in nodes:
			was.append(n.get("visible"))
			n.set("visible", false)
		print("[perf] " + perf_line("- " + String(part[0]), measure(vp), base))
		for k: int in nodes.size():
			nodes[k].set("visible", was[k])
	var models: Array = perf_parts(w, h, t)[6][1]
	for m: GeometryInstance3D in models:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("[perf] " + perf_line("- models' shadows", measure(vp), base))
	var plain := StandardMaterial3D.new()
	for m: GeometryInstance3D in models:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		m.material_override = plain
	print("[perf] " + perf_line("models plain material", measure(vp), base))
	for m: GeometryInstance3D in models:
		m.material_override = null
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	print("[perf] " + perf_line("shadow map 4096", measure(vp), base))
	RenderingServer.directional_shadow_atlas_set_size(
		int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")), true)
	w.sun.shadow_enabled = false
	print("[perf] " + perf_line("- sun shadows", measure(vp), base))
	w.sun.shadow_enabled = true
	w.env.ssao_enabled = false
	print("[perf] " + perf_line("- SSAO", measure(vp), base))
	w.env.ssao_enabled = true
	w.env.glow_enabled = false
	print("[perf] " + perf_line("- glow", measure(vp), base))
	w.env.glow_enabled = true
	var msaa := vp.msaa_3d
	vp.msaa_3d = Viewport.MSAA_DISABLED
	print("[perf] " + perf_line("- MSAA", measure(vp), base))
	vp.msaa_3d = msaa
	var scaled := vp.scaling_3d_scale
	if scaled < 1.0:
		vp.scaling_3d_scale = 1.0
		print("[perf] " + perf_line("3D at every pixel", measure(vp), base))
	vp.scaling_3d_scale = 0.5
	print("[perf] " + perf_line("3D at half size", measure(vp), base))
	vp.scaling_3d_scale = scaled
	var hidden: Array[Node3D] = []
	for child: Node in w.get_children():
		if child is Node3D and (child as Node3D).visible and not child is DirectionalLight3D:
			hidden.append(child)
			(child as Node3D).visible = false
	t.visible = false
	print("[perf] " + perf_line("only sky + HUD", measure(vp), base))
	for n: Node3D in hidden:
		n.visible = true
	t.visible = t.enabled
	await node.get_tree().process_frame
