extends Node
## Dev tool, not part of the game: plays a new game the way a person would, with
## real mouse and keyboard events, and checks that each step did what it should.
##
## Run it with tools/playtest.sh, which starts Godot like this:
##   Godot --path . -- --playtest=<dir>
## game3d.gd adds this node when it sees --playtest=; in normal play it is never made.
##
## Every action is a real input event (Input.parse_input_event) at a point on the
## screen: a click on a Build menu row, a drag across the map, a key, the mouse
## wheel. They go through the interface first and reach the game only if no panel
## takes them, exactly as with a mouse. The checks only read the game's state.
## Prints "[play] PASS ..." or "[play] FAIL ..." for each check and saves
## pictures along the way; quits with 1 if anything failed.

const Settings = preload("res://scripts/settings.gd")
const Simulation = preload("res://scripts/simulation.gd")
const WorldView = preload("res://scripts/world3d.gd")
const CameraRig = preload("res://scripts/camera_rig.gd")
const Hud = preload("res://scripts/hud.gd")
const Companies = preload("res://scripts/companies.gd")
const Traffic = preload("res://scripts/traffic.gd")
const DevShots = preload("res://scripts/dev_shots.gd")
const Advisors = preload("res://scripts/advisors.gd")

const WATCHDOG_SECONDS := 900.0
const PLAY_DISTANCE := 650.0          # a normal zoom while building
# game3d.gd's Tool numbers.
const ROAD := 0
const HOMES := 1
const SHOPS := 2
const INDUSTRY := 3
const BULLDOZE := 4
const POWER := 5
const UTILITY := 6
const PARK := 7
const GRID := 8
const SERVICE := 9
const LEISURE := 10
const TRANSPORT := 11
const DISTRICT := 12

var game: Node3D
var sim: Simulation
var world: WorldView
var rig: CameraRig
var hud: Hud
var traffic: Traffic
var out_dir := ""
var _mouse := Vector2.ZERO
var _buttons := 0
var _passed := 0
var _failed := 0
var debug_drags := false             # print where each drag ended up
var only: PackedStringArray = []        # parts to run on their own (--playtest-only=letters,tech_zone)
var _origin := Vector2i(-1, -1)       # top left of the patch of land the town goes on


static func wanted(args: PackedStringArray) -> bool:
	for a: String in args:
		if a.begins_with("--playtest="):
			return true
	return false


func _init(game_node: Node3D, args: PackedStringArray) -> void:
	name = "DevPlaytest"
	game = game_node
	for a: String in args:
		if a.begins_with("--playtest="):
			out_dir = a.trim_prefix("--playtest=")
		if a.begins_with("--playtest-only="):
			only = a.trim_prefix("--playtest-only=").split(",", false)
	if out_dir == "":
		out_dir = "screenshots/playtest"
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
		printerr("[play] gave up after %d seconds" % int(WATCHDOG_SECONDS))
		get_tree().quit(1))
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	DevShots._skip_import(out_dir)
	print("[play] saving to %s; window %s pixels, interface scale %.2f, 3D drawn at %d%%" % [out_dir,
		get_window().size, get_window().content_scale_factor, roundi(get_viewport().scaling_3d_scale * 100.0)])
	# The player's own save must come through untouched: the game saves to its
	# dev file while a dev tool runs it (game3d.gd DEV_SAVE_FILE).
	var players := "user://city_save.json"
	var players_time := FileAccess.get_modified_time(players) if FileAccess.file_exists(players) else 0
	check(String(game.get("save_file")) != players, "the play test saves to its own file (%s), never the player's" % game.get("save_file"))
	await _wait(1.0)
	await _launch_dialog()
	if not only.is_empty():
		# Just these parts (tools/playtest.sh --only=letters,tech_zone).
		for part: String in only:
			if has_method("_" + part):
				print("[play] only: %s" % part)
				await call("_" + part)
			else:
				check(false, "no part of the play test called %s" % part)
		_check_players_save(players, players_time)
		print("[play] done: %d passed, %d failed" % [_passed, _failed])
		get_tree().quit(1 if _failed > 0 else 0)
		return
	await _blank_start()
	await _camera_controls()
	await _build_first_streets()
	await _hud_blocks_the_map()
	await _wheel_over_panels()
	await _early_town()
	await _overlays_and_city_panel()
	await _save_and_load()
	await _keyboard_shortcuts()
	await _coast_and_slopes()
	await _woodland()
	await _new_city()
	await _loans()
	await _old_save()
	await _traffic()
	await _road_types()
	await _bridges()
	await _services()
	await _feedback_fixes()
	await _tech_zone()
	await _letters()
	await _data_centre()
	await _gigafactory()
	await _campus()
	await _launch_site()
	await _ai_data_centre()
	await _chip_factory()
	await _education()
	await _examples()
	await _new_buildings()
	_check_players_save(players, players_time)
	print("[play] done: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check_players_save(path: String, was: int) -> void:
	var now := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	check(now == was, "the player's own save (%s) was left untouched" % path)


func _new_buildings() -> void:
	# Offices, the small services, the airport and the landmarks, in the example
	# city (loaded just before): in the menu, working, and kept by a save.
	var T := Simulation.Tile
	var ids := {}
	for item: Dictionary in game.call("_menu_items"):
		ids[item["id"]] = item["locked"]
	var wanted := ["offices_0", "offices_1", "offices_2", "police_office", "fire_small", "clinic", "airport",
		"painted_ladies", "coit_tower", "ferry_building", "fine_arts", "transamerica", "salesforce_tower"]
	var missing: Array[String] = []
	for id: String in wanted:
		if not ids.has(id) or bool(ids[id]):
			missing.append(id)
	check(missing.is_empty(), "new buildings: all in the Build menu and unlocked in the city %s" % [missing])
	# Offices: jobs, demand and hover text.
	var office := -1
	for i: int in sim.w * sim.h:
		if sim.tiles[i] == T.OFFICES and sim.levels[i] > 0:
			office = i
			break
	check(office >= 0 and sim.office_jobs > 0 and sim.jobs() == sim.shop_jobs + sim.industry_jobs + sim.office_jobs,
		"offices: the city has offices (%d office jobs), counted with the other jobs" % sim.office_jobs)
	check(sim.office_share() > 0.2 and sim.demand.has(T.OFFICES), "offices: a city this size wants office work (share %.2f)" % sim.office_share())
	if office >= 0:
		var words: String = game.call("_tile_text", office)
		check(words.begins_with("Offices") and words.contains("office"), "offices: the hover text says what's there (%s)" % words.get_slice("\n", 0))
	# A clinic: a small hospital, cheaper and with less reach, placed from the menu.
	check(sim.service_of(T.CLINIC) == Simulation.Service.HOSPITAL and sim.service_small(T.CLINIC) and not sim.service_small(T.HOSPITAL)
		and sim.service_reach_m(3, 50.0, true) < sim.service_reach_m(3, 50.0),
		"small services: a clinic is a small hospital (reaches %d m, a hospital %d m)" % [
		sim.service_reach_m(3, 50.0, true), sim.service_reach_m(3, 50.0)])
	game.call("_choose_item", "clinic")
	var spot := Vector2i(-1, -1)
	for i: int in sim.w * sim.h:
		var p := Vector2i(i % sim.w, i / sim.w)
		if sim.tiles[i] == T.EMPTY and sim.near_road(i) and String(game.call("_why_cant_build", p)) == "":
			spot = p
			break
	var hospitals: int = sim.services[3]
	var upkeep := sim.service_upkeep()
	_place("clinic", spot)
	var clinic := spot.y * sim.w + spot.x
	check(spot.x >= 0 and sim.tiles[clinic] == T.CLINIC and int(sim.services[3]) == hospitals + 1 and int(sim.small_services[3]) >= 1,
		"small services: a clinic placed from the menu counts as a hospital service")
	var dearer := sim.service_upkeep() - upkeep
	check(dearer > 0 and dearer < int(Settings.SERVICE_UPKEEP[3]), "small services: it costs less to run than a hospital (+%d a month)" % dearer)
	check(String(game.call("_tile_text", clinic)).begins_with("Clinic"), "small services: its hover text names it")
	# The airport: open, with a runway and a terminal; cut the runway and it closes.
	var terminals: PackedInt32Array = sim.get("_airport_terminals")
	check(sim.airports_open == 1 and terminals.size() == 1, "airport: the city's airport is open")
	if terminals.size() == 1:
		var terminal: int = terminals[0]     # (the sim's own list is cleared when the airport closes)
		check(sim.building_status(terminal).begins_with("open") and sim.airport_role_at(terminal) == Simulation.AirportRole.TERMINAL,
			"airport: its terminal says so (%s)" % sim.building_status(terminal))
		var runway: Array[int] = []
		for i: int in sim.w * sim.h:
			if sim.tiles[i] == T.AIRPORT and sim.airport_role_at(i) == Simulation.AirportRole.RUNWAY:
				runway.append(i)
		check(runway.size() >= Settings.AIRPORT_MIN_RUNWAY, "airport: a runway of %d m" % (runway.size() * 50))
		var shops_before := sim.demand_for(T.SHOPS)
		# (Cut right across the airfield: with only one strip cut, the next becomes the runway.)
		var cut: int = runway[runway.size() / 2]
		var top := cut
		var bottom := cut
		var across: int = 1 if sim.airport_role[cut] & 8 != 0 else sim.w
		while sim.tiles[top - across] == T.AIRPORT:
			top -= across
		while sim.tiles[bottom + across] == T.AIRPORT:
			bottom += across
		_place("bulldoze", Vector2i(top % sim.w, top / sim.w), Vector2i(bottom % sim.w, bottom / sim.w))
		check(sim.airports_open == 0 and sim.building_status(terminal).contains("runway needs")
			and sim.demand_for(T.SHOPS) < shops_before,
			"airport: with the runway cut it closes and its visitors go (%s)" % sim.building_status(terminal))
		var tips: Array[Dictionary] = Advisors.tips(sim)
		var told := false
		for tip: Dictionary in tips:
			if tip["id"] == "airport":
				told = true
		check(told, "airport: the advisors say it isn't open")
		_place("airport", Vector2i(top % sim.w, top / sim.w), Vector2i(bottom % sim.w, bottom / sim.w))
		check(sim.airports_open == 1, "airport: mended, it opens again")
	# Landmarks: one of each, bringing tourists.
	var all := true
	for t: int in [T.PAINTED_LADIES, T.COIT_TOWER, T.FERRY_BUILDING, T.FINE_ARTS, T.TRANSAMERICA, T.SALESFORCE_TOWER]:
		if sim.count_of(t) != 1:
			all = false
	check(all and sim.tourism > 0.0, "landmarks: the city has all six of San Francisco's, and tourists (%.1f%% of its people)" % (sim.tourism * 100.0))
	check(sim.can_build_here(T.TRANSAMERICA, clinic).contains("only build one"), "landmarks: only one of each (%s)" % sim.can_build_here(T.TRANSAMERICA, clinic))
	# The old world landmarks are out of the menu, but an old city's still count.
	check(not ids.has("big_ben") and not ids.has("eiffel") and sim.is_landmark(T.BIG_BEN) and sim.is_landmark(T.EIFFEL),
		"landmarks: Big Ben and the Eiffel Tower are gone from the menu, but still landmarks in old cities")
	# A save keeps them all.
	var before := [sim.count_of(T.OFFICES), sim.count_of(T.CLINIC), sim.count_of(T.AIRPORT), sim.count_of(T.TRANSAMERICA),
		sim.population, sim.office_jobs, sim.airports_open]
	sim.from_save(sim.to_save())
	var after := [sim.count_of(T.OFFICES), sim.count_of(T.CLINIC), sim.count_of(T.AIRPORT), sim.count_of(T.TRANSAMERICA),
		sim.population, sim.office_jobs, sim.airports_open]
	check(before == after, "new buildings: saving and loading keeps them (%s)" % [after])
	world.refresh_all()
	await _shot("p24_new_buildings")


func _feedback_fixes() -> void:
	# From playing it (Nov 2026): undo; landfill that lasts, says how full it is,
	# and an incinerator to buy instead; an airport drag that's red until it's
	# big enough, then green.
	var T := Simulation.Tile
	await _open_new_city_from_menu()
	await _key(KEY_1)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var o := _find_land(24, 10)
	check(o.x >= 0 and _built_count() == 0, "feedback: a new city with flat land at %s" % o)
	if o.x < 0:
		return
	var undo: Button = hud.get("undo_button")
	check(undo != null and undo.disabled, "undo: nothing to undo in a new city (the button is greyed out)")
	sim.money = 500000

	# Undo: a road dragged with the mouse, a zone, part of it bulldozed; then
	# Cmd+Z, the button, Cmd+Z again, and everything is as it was.
	var money0: int = sim.money
	var map0 := _tiles_hash()
	await _pick_item("roads", "road")
	await _look_at(o + Vector2i(10, 5), PLAY_DISTANCE * 1.6, -40.0, 50.0, [o, o + Vector2i(20, 0), o + Vector2i(20, 9)])
	await _drag(_screen_of(o), _screen_of(o + Vector2i(20, 0)))
	var laid := _count(T.ROAD, o, o + Vector2i(20, 0))
	check(laid == 21 and sim.money < money0 and not undo.disabled and undo.tooltip_text.contains("21 tiles"),
		"undo: a road dragged with the mouse (%d tiles) can be undone (%s)" % [laid, undo.tooltip_text])
	_place("homes_1", o + Vector2i(0, 1), o + Vector2i(20, 2))
	var zoned := _count(T.HOMES, o + Vector2i(0, 1), o + Vector2i(20, 2))
	_place("bulldoze", o + Vector2i(0, 1), o + Vector2i(5, 2))
	check(zoned == 42 and _count(T.HOMES, o + Vector2i(0, 1), o + Vector2i(20, 2)) == 30, "undo: zoned 42 plots, bulldozed 12")
	await _key(KEY_Z, true)
	check(_count(T.HOMES, o + Vector2i(0, 1), o + Vector2i(20, 2)) == 42, "undo: Cmd+Z brings the bulldozed plots back")
	await _click(undo)
	check(_count(T.HOMES, o + Vector2i(0, 1), o + Vector2i(20, 2)) == 0 and _count(T.ROAD, o, o + Vector2i(20, 0)) == 21,
		"undo: the button then takes the zone away, leaving the road")
	await _key(KEY_Z, true)
	check(_tiles_hash() == map0 and sim.money == money0, "undo: ...and then the road, with every penny back (%s)" % Hud.money_text(sim.money))
	check(undo.disabled, "undo: nothing left to undo")
	await _key(KEY_Z, true)       # (nothing happens)
	_place("road", o, o + Vector2i(20, 0))
	sim.month += Settings.UNDO_MONTHS + 1
	game.call("_refresh_hud")
	check(undo.disabled, "undo: a build from over a year ago can't be undone")

	# Rubbish: 32 plots of tenements, a landfill beside the road; its hover says how full it is.
	_place("road", o + Vector2i(0, 4), o + Vector2i(20, 4))
	_place("homes_1", o + Vector2i(5, 1), o + Vector2i(20, 3))
	_place("coal", o + Vector2i(20, 5))
	_place("landfill", o + Vector2i(0, 5), o + Vector2i(3, 6))
	_fill_plots(o, o + Vector2i(20, 3))
	sim.call("_measure_rubbish")
	var tip := (o.y + 5) * sim.w + o.x
	var text: String = game.call("_tile_text", tip)
	var full := roundi(float(sim.rubbish_made) / (8 * 2000) * 100.0)
	check(sim.rubbish_capacity == 8 * 2000 and text.contains("This landfill (8 tiles) takes the rubbish of 16,000 residents: %d%% full" % full),
		"rubbish: a landfill of 8 tiles takes 16,000 residents' rubbish; the hover says how full (%s)" % text.get_slice("\n", 2))
	var items := {}
	for item: Dictionary in game.call("_menu_items"):
		items[item["id"]] = item["locked"]
	check(items.has("incinerator") and bool(items["incinerator"]), "rubbish: the incinerator is in the menu, for a bigger town")
	sim.population = 5000                   # (unlocked; the next recount sets it back)
	_place("incinerator", o + Vector2i(10, 5))
	var burner := (o.y + 5) * sim.w + o.x + 10
	sim.call("_measure_rubbish")
	text = game.call("_tile_text", tip)
	check(sim.tiles[burner] == T.INCINERATOR and sim.building_working(burner) and sim.rubbish_capacity == 16000 + 25000
		and text.contains("0% full, 100% to spare"),
		"rubbish: an incinerator burns 25,000 residents' worth first, so the landfill is empty (%s)" % text.get_slice("\n", 2))
	check(String(game.call("_tile_text", burner)).contains("% full") and sim.pollution_at(burner + 2 * sim.w) > 0.0,
		"rubbish: the incinerator says how full it is, and its smoke pollutes")
	game.call("_refresh_hud")
	var rubbish_line: Label = hud.get("rubbish_label")
	check(rubbish_line.text.contains("room to spare"), "rubbish: the City panel says how much room is left (%s)" % rubbish_line.text)

	# The airport: red while too small, green once big enough, and only built then.
	sim.population = 6000
	game.call("_refresh_hud")
	await _pick_item("transport", "airport")
	await _drag(_screen_of(o + Vector2i(2, 7)), _screen_of(o + Vector2i(12, 9)), MOUSE_BUTTON_LEFT, false)
	var info: Label = hud.get("info_label")
	var red: Color = world.preview.multimesh.get_instance_color(0)
	check(String(game.call("_airport_too_small")).contains("16 tiles in a line") and red.r > red.g and info.text.contains("Too small"),
		"airport: an 11 x 3 drag is red and says why (%s)" % info.text)
	await _shot("p26_airport_too_small")
	await _move(_screen_of(o + Vector2i(19, 9)))
	await _frames(3)
	var green: Color = world.preview.multimesh.get_instance_color(0)
	check(String(game.call("_airport_too_small")) == "" and green.g > green.r and info.text.contains("big enough"),
		"airport: dragged out to 18 x 3 it turns green (%s)" % info.text)
	await _shot("p27_airport_big_enough")
	await _press(_screen_of(o + Vector2i(19, 9)), MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	check(_count(T.AIRPORT, o + Vector2i(2, 7), o + Vector2i(19, 9)) == 54, "airport: released, all 54 tiles are built")
	await _key(KEY_Z, true)
	check(_count(T.AIRPORT, o + Vector2i(2, 7), o + Vector2i(19, 9)) == 0, "airport: and Cmd+Z takes it away again")
	sim.population = 6000
	await _drag(_screen_of(o + Vector2i(2, 7)), _screen_of(o + Vector2i(12, 9)))
	check(_count(T.AIRPORT, o + Vector2i(2, 7), o + Vector2i(19, 9)) == 0, "airport: let go while it's red, nothing is built")


func _tech_zone() -> void:
	# The Tech zone (tech layer step 1, Nov 2026): a district painted with the
	# mouse whose offices and industry pay their own tax, set in the City panel.
	# Below the town's rate, firms come from outside to fill it; residents
	# grumble when it's a big break for a big share of the jobs.
	var T := Simulation.Tile
	await _open_new_city_from_menu()
	await _key(KEY_2)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var o := _find_land(24, 10)
	check(o.x >= 0 and _built_count() == 0, "tech zone: a new city with flat land at %s" % o)
	if o.x < 0:
		return
	sim.money = 500000
	# Homes above a road; offices and industry below it; coal and water at the end.
	_place("road", o + Vector2i(0, 4), o + Vector2i(21, 4))
	_place("homes_1", o + Vector2i(0, 1), o + Vector2i(20, 3))
	_place("offices_1", o + Vector2i(0, 5), o + Vector2i(9, 6))
	_place("industry", o + Vector2i(11, 5), o + Vector2i(20, 6))
	_place("coal", o + Vector2i(21, 5))
	_place("water_tower", o + Vector2i(21, 3))
	var plots := _count(T.OFFICES, o + Vector2i(0, 5), o + Vector2i(20, 6)) + _count(T.INDUSTRY, o + Vector2i(0, 5), o + Vector2i(20, 6))
	check(plots == 40, "tech zone: 20 office and 20 industry plots zoned (%d)" % plots)

	# Paint it with the mouse: Districts > Tech zone, drag over the business plots.
	game.call("_refresh_hud")
	check(String(hud.get("tech_tax_label").text).contains("paint a Tech zone"),
		"tech zone: before there is one, the City panel says how to make one (%s)" % hud.get("tech_tax_label").text)
	await _pick_item("districts", "tech_zone")
	check(_tool() == DISTRICT, "tech zone: Districts > Tech zone picks the District tool")
	await _look_at(o + Vector2i(10, 5), PLAY_DISTANCE * 1.4, -40.0, 50.0, [o, o + Vector2i(21, 0), o + Vector2i(21, 7)])
	await _drag(_screen_of(o + Vector2i(0, 5)), _screen_of(o + Vector2i(20, 6)))
	var painted := 0
	for y: int in range(o.y + 5, o.y + 7):
		for x: int in range(o.x, o.x + 21):
			if sim.district[y * sim.w + x] == Settings.TECH_ZONE:
				painted += 1
	check(painted == 42 and sim.has_tech_zone(), "tech zone: dragging paints a Tech zone over 42 tiles (%d)" % painted)
	check(world.overlay == WorldView.Overlay.DISTRICTS, "tech zone: painting shows the Districts view")
	var office := (o.y + 5) * sim.w + o.x + 2
	var text: String = game.call("_tile_text", office)
	check(text.contains("Tech zone: offices and industry pay 9% tax"), "tech zone: hovering a plot says what it pays (%s)" % text.get_slice("\n", 1))
	check(String(sim.zone_status(office)).contains("only come for a tax break"),
		"tech zone: with no break, its plots say firms want one (%s)" % sim.zone_status(office))
	await _key(KEY_Z, true)
	check(not sim.has_tech_zone(), "tech zone: Cmd+Z takes the painting back")
	_place("tech_zone", o + Vector2i(0, 5), o + Vector2i(20, 6))
	await _shot("p28_tech_zone_painted")

	# The City panel's own tax row: lower it to 3% with the mouse.
	await _click(hud.get("_city_button"))
	var label: Label = hud.get("tech_tax_label")
	check(label.visible and label.text.contains("Tech zone tax 9%: no tax break"), "tech zone: the City panel has its own tax row (%s)" % label.text)
	var minus: Button = null
	for child: Node in label.get_parent().get_children():
		var b := child as Button
		if b and b.text == "–":
			minus = b
	for k: int in 6:
		await _click(minus)
	check(is_equal_approx(sim.tech_tax_rate, 0.03) and is_equal_approx(sim.tax_rate, Settings.DEFAULT_TAX_RATE),
		"tech zone: – six times sets it to 3%%, the town stays at %d%%" % roundi(sim.tax_rate * 100.0))
	check(label.text.contains("drawing firms in"), "tech zone: the panel says it's drawing firms in (%s)" % label.text)
	var incoming: Dictionary = sim.tech_incoming()
	check(float(incoming[T.OFFICES]) > 0.0 and float(incoming[T.INDUSTRY]) > 0.0,
		"tech zone: firms want to bring %d office and %d industry jobs" % [roundi(float(incoming[T.OFFICES])), roundi(float(incoming[T.INDUSTRY]))])
	await _click(hud.get("_city_button"))

	# Two years with the break, and the same two years without: the break fills the zone.
	var start := sim.to_save()
	var jobs_with := 0
	var jobs_without := 0
	for run: int in 2:
		sim.from_save(start)
		sim.money = 500000
		sim.tech_tax_rate = 0.03 if run == 0 else Settings.DEFAULT_TAX_RATE
		sim.recount()
		for m: int in 24:
			sim.tick()
		if run == 0:
			jobs_with = sim.tech_zone_jobs()
		else:
			jobs_without = sim.tech_zone_jobs()
	check(jobs_with > jobs_without + 50, "tech zone: after two years, %d jobs in it with a 3%% tax, %d without a break" % [jobs_with, jobs_without])
	sim.from_save(start)
	sim.money = 500000
	sim.recount()
	for m: int in 24:
		sim.tick()
	check(sim.last_tech_relief > 0, "tech zone: the break gave up %s of tax last month" % Hud.money_text(sim.last_tech_relief))
	var most := Settings.TECH_JOBS_BASE + sim.population * Settings.TECH_JOBS_PER_PERSON
	var wanted := float(sim.tech_incoming()[T.OFFICES]) + float(sim.tech_incoming()[T.INDUSTRY])
	check(wanted <= most + 0.5, "tech zone: incoming firms are capped by the town's size (%d of at most %d)" % [roundi(wanted), roundi(most)])

	# Fairness: at 0% with most of the jobs in the zone, residents grumble.
	sim.change_tech_tax(-1.0)
	sim.recount()
	var share := float(sim.tech_zone_jobs()) / maxi(sim.jobs(), 1)
	var part: float = sim.happiness_parts.get("fairness", 0.0)
	check(part < 0.0 and is_equal_approx(part, -share * Settings.TECH_FAIRNESS_EFFECT),
		"tech zone: at 0%%, with %d%% of jobs in it, fairness costs %.2f appeal" % [roundi(share * 100.0), part])
	if part <= -Settings.COMPLAINT_SIZE:
		check("tech_fairness" in _tip_ids(), "tech zone: the advisors say residents grumble about it")
	sim.change_tech_tax(1.0)
	sim.tech_tax_rate = sim.tax_rate
	sim.recount()
	check(float(sim.happiness_parts.get("fairness", 0.0)) == 0.0 and "tech_no_break" in _tip_ids(),
		"tech zone: at the town's rate nobody minds, and the advisors suggest a break")

	# Saved and loaded; an older save takes the town's rate.
	sim.tech_tax_rate = 0.04
	var data := sim.to_save()
	sim.from_save(data)
	check(is_equal_approx(sim.tech_tax_rate, 0.04) and sim.has_tech_zone(), "tech zone: saved and loaded with its 4% tax")
	data.erase("tech_tax_rate")
	data["tax_rate"] = 0.11
	sim.from_save(data)
	check(is_equal_approx(sim.tech_tax_rate, 0.11), "tech zone: a save from before takes the town's rate (11%)")
	sim.tech_tax_rate = 0.03
	sim.tax_rate = Settings.DEFAULT_TAX_RATE
	sim.recount()
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	sim.layout_version += 1
	game.call("_refresh_hud")
	await _frames(3)
	await _click(hud.get("_city_button"))
	await _shot("p29_tech_zone_city_panel")
	await _click(hud.get("_city_button"))


func _letters() -> void:
	# Letters from start-ups (tech layer step 2, Nov 2026): they write once the
	# town has 500 people and an empty office plot in a Tech zone; the envelope
	# counts them; a letter opens on a card that pauses the game; backing one
	# puts it on that plot; unanswered letters lapse; start-ups grow, fold or
	# are bought each year.
	var T := Simulation.Tile
	await _open_new_city_from_menu()
	await _key(KEY_2)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var o := _find_land(24, 10)
	check(o.x >= 0, "letters: a new city with flat land at %s" % o)
	if o.x < 0:
		return
	sim.money = 500000
	_place("road", o + Vector2i(0, 4), o + Vector2i(21, 4))
	_place("homes_1", o + Vector2i(0, 2), o + Vector2i(20, 3))
	_place("offices_1", o + Vector2i(0, 5), o + Vector2i(9, 6))
	_place("coal", o + Vector2i(21, 5))
	_place("water_tower", o + Vector2i(21, 3))
	_fill_plots(o + Vector2i(0, 2), o + Vector2i(20, 3))
	sim.recount()
	check(sim.population >= Settings.STARTUP_POP and sim.startup_chance() == 0.0
		and sim.interest_lines()[0].contains("want a Tech zone"),
		"letters: %d people but no Tech zone, so no start-ups write (%s)" % [sim.population, sim.interest_lines()[0]])
	_place("tech_zone", o + Vector2i(0, 5), o + Vector2i(9, 6))
	sim.recount()
	check(sim.startup_chance() > 0.0 and sim.interest_lines()[0].contains("interested"),
		"letters: with a Tech zone of empty office plots, start-ups are interested (%s)" % sim.interest_lines()[0])
	var tries := 0
	while sim.letters.is_empty() and tries < 200:
		sim.call("_update_letters")
		tries += 1
	check(sim.letters.size() == 1 and String(sim.letters[0]["kind"]) == "startup",
		"letters: a start-up writes (after %d months' worth of chances)" % tries)
	if sim.letters.is_empty():
		return
	var letter: Dictionary = sim.letters[0]
	var grant: int = letter["grant"]
	game.call("_refresh_hud")
	var badge: Label = hud.get("_inbox_badge")
	check(badge.visible and badge.text == "1", "letters: the envelope shows 1 waiting")
	check("letters" in _tip_ids(), "letters: the advisors mention the letter")

	# Open the inbox and the letter with the mouse; the clock stops while it's open.
	game.call("_set_speed", 1)
	await _click(hud.get("inbox_button"))
	await _frames(3)
	var inbox: PanelContainer = hud.get("inbox_panel")
	var row: Button = null
	for child: Node in (hud.get("_inbox_box") as VBoxContainer).get_children():
		if child is Button and (child as Button).text.contains(String(letter["company"])):
			row = child
	check(inbox.visible and row != null and row.text.contains(String(letter["company"])),
		"letters: the envelope opens the inbox with the letter in it")
	await _shot("p30_inbox")
	# (The clock runs: a new month rebuilds the inbox, so find the row just before clicking.)
	await _wait(0.2)
	for child: Node in (hud.get("_inbox_box") as VBoxContainer).get_children():
		if child is Button and not child.is_queued_for_deletion() and (child as Button).text.contains(String(letter["company"])):
			row = child
	await _click_at(row.get_global_rect().get_center())
	await _wait(0.15)
	await _frames(3)
	var body: Label = hud.get("_letter_body")
	check(hud.call("letter_open") and not inbox.visible and body.text.contains(String(letter["company"]))
		and body.text.contains(Hud.money_text(grant)), "letters: clicking it opens the letter (%s)" % letter["subject"])
	check(int(game.get("speed")) == 0, "letters: the game pauses while it's open")
	await _shot("p31_startup_letter")
	await _key(KEY_ESCAPE)
	check(not hud.call("letter_open") and int(game.get("speed")) == 1 and sim.letters.size() == 1,
		"letters: Esc puts it back in the inbox, and the clock runs again")
	game.call("_set_speed", 0)

	# Back them: they move into the best empty office plot in the Tech zone.
	hud.call("open_letter", int(letter["id"]))
	await _frames(3)
	var money0: int = sim.money
	var yes := _find_button(hud.get("letter_panel"), "Back them (%s)" % Hud.money_text(grant))
	await _click(yes)
	await _frames(2)
	check(not hud.call("letter_open") and sim.letters.is_empty() and sim.startups.size() == 1
		and sim.money == money0 - grant, "letters: Back them costs %s and closes the letter" % Hud.money_text(grant))
	var plot: int = sim.startups[0]["tile"] if not sim.startups.is_empty() else -1
	check(plot >= 0 and sim.tiles[plot] == T.OFFICES and sim.levels[plot] == 1 and sim.district[plot] == Settings.TECH_ZONE
		and String(game.call("_tile_text", plot)).contains("Start-up: %s" % letter["company"]),
		"letters: the start-up moved into an office plot in the Tech zone, and its hover says so")
	var appetite: float = sim.investor_appetite
	check(appetite > Settings.APPETITE_START, "letters: investors are keener (%.2f)" % appetite)

	# Another letter: No thanks. Another: left unanswered for 6 months, it lapses.
	sim.call("_send_letter", Companies.startup_letter(RandomNumberGenerator.new(), []))
	game.call("_refresh_hud")
	hud.call("open_letter", int(sim.letters[0]["id"]))
	await _frames(3)
	await _click(_find_button(hud.get("letter_panel"), "No thanks"))
	check(sim.letters.is_empty() and sim.investor_appetite < appetite, "letters: No thanks turns it down; investors cool a little")
	sim.call("_send_letter", Companies.startup_letter(RandomNumberGenerator.new(), []))
	sim.month += Settings.LETTER_MONTHS
	sim.call("_update_letters")
	check(sim.letters.size() <= 1 and sim.news.size() >= 1 and String(sim.news[0]).contains("gave up waiting"),
		"letters: a letter left for %d months lapses (%s)" % [Settings.LETTER_MONTHS, sim.news[0] if not sim.news.is_empty() else ""])
	sim.letters.clear()

	# No empty plot left: the letter card says why it can't be done.
	for y: int in range(o.y + 5, o.y + 7):
		for x: int in range(o.x, o.x + 10):
			if sim.levels[y * sim.w + x] == 0:
				sim.levels[y * sim.w + x] = 1
	sim.recount()
	var id: int = sim.call("_send_letter", Companies.startup_letter(RandomNumberGenerator.new(), []))
	game.call("_refresh_hud")
	hud.call("open_letter", id)
	await _frames(3)
	var ask := Hud.money_text(int(sim.letter_by_id(id)["grant"]))
	await _click(_find_button(hud.get("letter_panel"), "Back them (%s)" % ask))
	var note: Label = hud.get("_letter_note")
	check(hud.call("letter_open") and note.text.contains("needs an empty office plot") and sim.startups.size() == 1,
		"letters: with no empty plot it can't move in, and the card says so (%s)" % note.text)
	check(sim.startup_chance() == 0.0 and sim.interest_lines()[0].contains("want an empty office plot"),
		"letters: ...and no more start-ups write until there is one")
	hud.call("close_letter")

	# Saved and loaded with its letters, start-ups and investors' mood; an older save has none.
	var data := sim.to_save()
	sim.from_save(data)
	check(sim.letters.size() == 1 and int(sim.letters[0]["id"]) == id and sim.startups.size() == 1
		and int(sim.startups[0]["tile"]) == plot, "letters: saved and loaded with the letter and the start-up")
	for key: String in ["letters", "startups", "investor_appetite", "letter_count"]:
		data.erase(key)
	sim.from_save(data)
	check(sim.letters.is_empty() and sim.startups.is_empty() and is_equal_approx(sim.investor_appetite, Settings.APPETITE_START),
		"letters: an older save loads with none")

	# Each year a start-up may grow, fold or be bought: ten years of them.
	var outcomes := {}
	for n: int in 40:
		sim.startups.clear()
		sim.startups.append({"tile": plot, "name": "Testly", "grant": 2000, "founded": 0})
		sim.levels[plot] = 1
		sim.month = 12
		sim.call("_update_startups")
		var said: String = sim.news[0] if not sim.news.is_empty() else "nothing"
		var kind := "grew" if said.contains("raised") else ("folded" if said.contains("closed") else (
			"bought" if said.contains("bought") else "nothing"))
		outcomes[kind] = true
		sim.news.clear()
	check(outcomes.size() >= 3, "letters: start-ups' years go different ways (%s)" % ", ".join(outcomes.keys()))
	sim.startups.clear()
	await _records(plot)


func _records(plot: int) -> void:
	# Sam's feedback (Nov 2026): every start-up stays on the list with how it
	# ended and what it made the town; every letter is kept with the answer.
	# The inbox shows a summary and opens the Records window.
	var T := Simulation.Tile
	sim.startups.clear()
	sim.levels[plot] = 1
	sim.startups.append({"tile": plot, "name": "Goingly", "grant": 2000, "founded": 0, "status": "going",
		"ended": -1, "tax": 0.0, "payout": 0, "best": 1})
	var tax0: int = sim.money
	sim.call("_collect_taxes")
	var paid: float = sim.startups[0]["tax"]
	check(paid > 0.0, "records: a start-up's tax is added up each month (%.1f)" % paid)
	sim.money = tax0
	# Bought out: paid once, then it ends (no second payout) and stays on the list.
	var other := -1
	for k: int in sim.w * sim.h:
		if sim.tiles[k] == T.OFFICES and sim.district[k] == Settings.TECH_ZONE and k != plot:
			other = k
			break
	sim.startups.append({"tile": other, "name": "Boughtly", "grant": 1500, "founded": 0, "status": "going",
		"ended": -1, "tax": 40.0, "payout": 0, "best": 1})
	sim.levels[other] = 1
	sim.month = 12
	sim.startups[0]["founded"] = 1          # (only the second one has its yearly roll this month)
	var bought: Dictionary = sim.startups[1]
	for rolls: int in 400:
		bought["status"] = "going"
		sim.levels[other] = 1
		sim.call("_update_startups")
		if String(bought["status"]) == "bought":
			break
	var money1: int = sim.money
	sim.month = 24
	sim.call("_update_startups")
	check(String(bought["status"]) == "bought" and int(bought["payout"]) == 1500 * Settings.STARTUP_PAYOUT
		and sim.money == money1 and sim.is_startup(other) == "" and sim.startups.size() == 2,
		"records: a bought-out start-up is paid once, ends, and stays on the list")
	# One whose plot is bulldozed closes, with news (it used to vanish silently).
	sim.startups.append({"tile": other, "name": "Clearly", "grant": 1000, "founded": 13, "status": "going",
		"ended": -1, "tax": 12.0, "payout": 0, "best": 2})
	var zone_was: int = sim.tiles[other]
	sim.tiles[other] = T.EMPTY
	sim.news.clear()
	sim.call("_update_startups")
	check(String(sim.startups[2]["status"]) == "closed" and not sim.news.is_empty() and String(sim.news[0]).contains("Clearly"),
		"records: a start-up whose plot is cleared closes with a news line (%s)" % (sim.news[0] if not sim.news.is_empty() else ""))
	sim.tiles[other] = zone_was
	sim.startups.append({"tile": other, "name": "Bustly", "grant": 3000, "founded": 12, "status": "bust",
		"ended": 30, "tax": 90.0, "payout": 0, "best": 2})
	sim.month = 40
	sim.startups[0]["founded"] = 0
	sim.recount()
	var tot: Dictionary = sim.startup_totals()
	check(int(tot["backed"]) == 4 and int(tot["going"]) == 1 and int(tot["bought"]) == 1 and int(tot["bust"]) == 1
		and int(tot["closed"]) == 1 and int(tot["net"]) == int(tot["tax"]) + int(tot["payouts"]) - 7500,
		"records: the totals add up (%s)" % str(tot))
	# Some answered letters for the Letters tab.
	sim.letters.clear()
	sim.letter_log.clear()
	for n: int in 7:
		var lid: int = sim.call("_send_letter", Companies.startup_letter(RandomNumberGenerator.new(), []))
		if n == 6:
			continue                             # (one left waiting)
		if n % 3 == 0:
			sim.answer_letter(lid, false)
		elif n % 3 == 1:
			sim.letters.erase(sim.letter_by_id(lid))
			sim.call("_log_answer", lid, "lapsed")
		else:
			sim.letters.erase(sim.letter_by_id(lid))
			sim.call("_log_answer", lid, "yes", "Backed with £1,000")
	var counts: Dictionary = sim.letter_log_counts()
	check(int(counts["no"]) == 2 and int(counts["lapsed"]) == 2 and int(counts["yes"]) == 2 and int(counts[""]) == 1
		and sim.letter_log.size() == 7, "records: every letter is logged with its answer (%s)" % str(counts))

	# The inbox: a summary and a Records row, not the whole list.
	game.call("_refresh_hud")
	game.call("_set_speed", 1)
	await _click(hud.get("inbox_button"))
	await _frames(3)
	var records_row: Button = null
	var said := ""
	for child: Node in (hud.get("_inbox_box") as VBoxContainer).get_children():
		if child is Label:
			said += (child as Label).text + " | "
		if child is Button and (child as Button).text.begins_with("Records"):
			records_row = child
	check(records_row != null and said.contains("4 backed: 1 going, 1 bought out, 1 went bust, 1 closed")
		and (said.contains("Made the town") or said.contains("Cost the town")) and not said.contains("Goingly"),
		"records: the inbox sums up the start-ups in two lines and offers Records")
	if records_row == null:
		return
	await _wait(0.2)
	for child: Node in (hud.get("_inbox_box") as VBoxContainer).get_children():
		if child is Button and not child.is_queued_for_deletion() and (child as Button).text.begins_with("Records"):
			records_row = child
	await _click_at(records_row.get_global_rect().get_center())
	await _wait(0.15)
	await _frames(3)
	var panel: PanelContainer = hud.get("records_panel")
	var box: VBoxContainer = hud.get("_records_box")
	var names := ""
	for child: Node in box.get_children():
		if child is Button:
			names += _texts(child) + " | "
	check(panel.visible and int(game.get("speed")) == 0 and names.find("Goingly") >= 0
		and names.find("Goingly") < names.find("Boughtly") and names.contains("Went bust") and names.contains("Closed")
		and names.contains(Hud.money_text(1500 * Settings.STARTUP_PAYOUT)),
		"records: the Records window opens on the start-ups, going first, with how each ended (the clock stops)")
	await _shot("p48_records_startups")
	# Clicking one still going flies the camera to its office.
	var going_row: Button = null
	for child: Node in box.get_children():
		if child is Button and _texts(child).contains("Goingly"):
			going_row = child
	rig.target = Vector3.ZERO
	await _click(going_row)
	await _wait(0.3)
	var want: Vector2 = world.tile_centre(Vector2i(plot % sim.w, plot / sim.w))
	check(not panel.visible and Vector2(rig.target.x, rig.target.z).distance_to(want) < 1.0 and int(game.get("speed")) == 1,
		"records: clicking a start-up still going shows its office on the map")
	# The Letters tab and its filters.
	hud.call("open_records", "letters")
	await _frames(3)
	var no_chip: Button = null
	for child: Node in (hud.get("_records_filters") as HBoxContainer).get_children():
		if (child as Button).text.begins_with("Said no"):
			no_chip = child
	var all_rows := box.get_child_count()
	await _click(no_chip)
	await _frames(3)
	var no_rows := 0
	var only_no := true
	for child: Node in box.get_children():
		if child is Button:
			no_rows += 1
			only_no = only_no and _texts(child).contains("Turned down")
	check(all_rows == sim.letter_log.size() and no_rows == int(counts["no"]) and only_no,
		"records: the Letters tab lists every letter (%d), and Said no shows just those (%d)" % [all_rows, no_rows])
	await _shot("p49_records_letters")
	await _key(KEY_ESCAPE)
	check(not panel.visible and int(game.get("speed")) == 1, "records: Esc closes it and the clock runs again")
	game.call("_set_speed", 0)
	# Saved and loaded; an older save has no log but starts one from the letters waiting.
	var data := sim.to_save()
	sim.from_save(data)
	check(sim.startups.size() == 4 and String(sim.startups[1]["status"]) == "bought" and sim.letter_log.size() == int(counts["no"]) + int(counts["lapsed"]) + int(counts["yes"]) + int(counts[""]),
		"records: saved and loaded with every start-up and letter")
	data.erase("letter_log")
	for st: Dictionary in data["startups"]:
		for key: String in ["status", "ended", "tax", "payout", "best"]:
			st.erase(key)
	sim.from_save(data)
	check(sim.letter_log.size() == sim.letters.size() and sim.startup_going(sim.startups[3]),
		"records: an older save loads (its start-ups going, its log from the letters waiting)")
	sim.startups.clear()
	sim.letters.clear()
	sim.letter_log.clear()


func _texts(n: Node) -> String:
	# Every label's words inside a control, joined.
	var out := ""
	if n is Label:
		out += (n as Label).text + " "
	for child: Node in n.get_children():
		out += _texts(child)
	return out


func _data_centre() -> void:
	# A data centre (tech layer step 2, Nov 2026): Amazon, Microsoft or Google
	# write once the town has 1,500 people and open land in a Tech zone; you pick
	# a size on the letter card, then drag out its site in the Tech zone (red
	# until it's big enough). It draws its power and water, opens with its
	# investment, brings jobs, and on a stretched grid pushes bills up.
	var T := Simulation.Tile
	await _open_new_city_from_menu()
	await _key(KEY_2)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var o := _find_land(26, 12)
	check(o.x >= 0, "data centre: a new city with flat land at %s" % o)
	if o.x < 0:
		return
	sim.money = 500000
	_place("road", o + Vector2i(0, 4), o + Vector2i(25, 4))
	_place("homes_1", o + Vector2i(0, 2), o + Vector2i(22, 3))
	_place("coal", o + Vector2i(25, 5))
	_place("water_pump", o + Vector2i(23, 3))
	_place("water_pump", o + Vector2i(24, 3))
	_fill_plots(o + Vector2i(0, 2), o + Vector2i(22, 3))
	sim.recount()
	_place("gas", o + Vector2i(24, 5))
	_place("tech_zone", o + Vector2i(0, 5), o + Vector2i(11, 9))
	sim.recount()
	var line: String = sim.interest_lines()[1]
	check(sim.population >= Settings.DC_POP and line.contains("Data centres") and line.contains("interested"),
		"data centre: %d people and open land in a Tech zone: %s" % [sim.population, line])
	check(line.contains("Tech zone tax at least 3%"), "data centre: ...they'd like a Tech zone tax break")
	sim.change_tech_tax(-0.03)
	var tries := 0
	while not sim.call("_has_letter", "data_centre") and tries < 400:
		sim.call("_update_letters")
		tries += 1
	var id := -1
	for letter: Dictionary in sim.letters:
		if String(letter["kind"]) == "data_centre":
			id = letter["id"]
	check(id >= 0, "data centre: a data centre letter comes (after %d months' worth of chances)" % tries)
	if id < 0:
		return
	var company: String = sim.letter_by_id(id)["company"]
	game.call("_refresh_hud")
	hud.call("open_letter", id)
	await _frames(3)
	var options: VBoxContainer = hud.get("_letter_options")
	var sizes: Array[Button] = []
	for child: Node in options.get_children():
		if child is Button:
			sizes.append(child)
	check(sizes.size() == 3 and sizes[1].text.begins_with("Standard: 12 tiles") and sizes[2].text.contains("power before homes"),
		"data centre: %s's letter offers three sizes (%s)" % [company, sizes[1].text.replace("\n", " / ") if sizes.size() > 1 else ""])
	await _shot("p32_data_centre_letter")

	# Standard: say yes on the card, then drag out its site with the mouse.
	await _click(sizes[1])
	await _frames(2)
	var k: int = sim.deal_by_id(id)
	check(k >= 0 and not hud.call("letter_open") and int(game.get("_placing_deal")) == id
		and world.overlay == WorldView.Overlay.DISTRICTS, "data centre: yes to Standard: placing its site, with the Districts view on")
	await _look_at(o + Vector2i(6, 6), PLAY_DISTANCE * 1.2, -40.0, 50.0, [o + Vector2i(0, 4), o + Vector2i(12, 4), o + Vector2i(12, 10)])
	await _drag(_screen_of(o + Vector2i(0, 5)), _screen_of(o + Vector2i(1, 6)), MOUSE_BUTTON_LEFT, false)
	var info: Label = hud.get("info_label")
	check(info.text.contains("needs 12 tiles"), "data centre: a 2 x 2 drag is red and says it needs 12 tiles (%s)" % info.text)
	await _press(_screen_of(o + Vector2i(1, 6)), MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	check(_count(T.DATA_CENTRE, o + Vector2i(0, 5), o + Vector2i(11, 9)) == 0, "data centre: let go while red, nothing is built")
	await _drag(_screen_of(o + Vector2i(0, 5)), _screen_of(o + Vector2i(3, 7)))
	await _frames(2)
	check(_count(T.DATA_CENTRE, o + Vector2i(0, 5), o + Vector2i(11, 9)) == 12 and int(sim.deals[k]["count"]) == 12
		and int(game.get("_placing_deal")) == -1, "data centre: a 4 x 3 drag builds its 12 tiles, free, and placing ends")
	var dc := (o.y + 5) * sim.w + o.x
	sim.recount()
	var problem: String = sim.deal_problem(k)
	check(problem.contains("not enough power") and "deal_down" in _tip_ids(),
		"data centre: coal and gas can't run it as well as the homes (%s), and the advisors say so" % problem)
	check(String(game.call("_tile_text", dc)).contains("not running"), "data centre: its hover says it isn't running")
	sim.population = 6000
	_place("nuclear", o + Vector2i(25, 6))
	sim.recount()
	check(sim.deal_problem(k) == "" and sim.company_jobs == 40, "data centre: with a nuclear plant it runs: 40 jobs")
	var money0: int = sim.money
	sim.tick()
	var opened: bool = sim.deals[k]["opened"] if sim.deal_by_id(id) >= 0 else false
	check(opened and sim.money == money0 + 20000 + sim.last_balance() and sim.news.size() > 0 and String(sim.news[0]).contains("invested"),
		"data centre: next month it opens and invests %s (%s)" % [Hud.money_text(20000), sim.news[0] if not sim.news.is_empty() else ""])
	check(sim.company_tax() == 0 and String(game.call("_tile_text", dc)).contains("no tax for 5 more years"),
		"data centre: no tax for its first 5 years")
	k = sim.deal_by_id(id)
	sim.deals[k]["break_left"] = 0
	check(sim.company_tax() == 1500, "data centre: after that it pays %s a month" % Hud.money_text(1500))
	# Its fans hum: homes nearby are worth less, and their hover says why (Sam, Nov 2026).
	var near := (o.y + 3) * sim.w + o.x + 1
	var far := (o.y + 2) * sim.w + o.x + 20
	sim.set("_value_dirty", true)
	var near_text := String(game.call("_tile_text", near))
	check(sim.hum_at(near) > 0.08 and sim.hum_at(far) == 0.0 and sim.hum_price_drop(near) > 0.08
		and near_text.contains("less: next to a data centre") and not String(game.call("_tile_text", far)).contains("data centre"),
		"data centre: homes beside it are worth %d%% less, and say why; homes far off aren't (%s)" % [
			roundi(sim.hum_price_drop(near) * 100.0), near_text.get_slice("\n", near_text.get_slice_count("\n") - 1)])
	var dc_text := String(game.call("_tile_text", dc))
	check(dc_text.contains("homes within 200 m are worth up to"), "data centre: its hover says it lowers homes' value nearby")
	game.set("_buildings_dirty", true)
	game.call("_refresh_hud")
	await _look_at(o + Vector2i(2, 6), PLAY_DISTANCE * 0.6, -35.0, 34.0, [])
	await _shot("p33_data_centre")

	# Bills: without the nuclear plant the grid is stretched and everyone's bills go up.
	_place("bulldoze", o + Vector2i(25, 6))
	sim.recount()
	var bills: float = sim.happiness_parts.get("bills", 0.0)
	check(bills <= -Settings.COMPLAINT_SIZE, "data centre: on a stretched grid, bills cost %.2f appeal" % bills)
	# Power before homes (the Mega deal's term): its tiles all get power, homes go short.
	sim.deals[k]["priority"] = true
	sim.set("_power_dirty", true)
	sim.recount()
	var dc_on := true
	for t in sim.deals[k]["tiles"]:
		dc_on = dc_on and sim.powered[int(t)] == 1
	var homes_off := 0
	for y: int in range(o.y + 2, o.y + 4):
		for x: int in range(o.x, o.x + 23):
			if sim.powered[y * sim.w + x] == 0:
				homes_off += 1
	check(dc_on and homes_off > 0, "data centre: with power before homes it runs and %d homes go dark" % homes_off)
	sim.deals[k]["priority"] = false

	# Saved and loaded; an older save has none.
	var data := sim.to_save()
	sim.from_save(data)
	k = sim.deal_by_id(id)
	check(k >= 0 and int(sim.deals[k]["count"]) == 12 and bool(sim.deals[k]["opened"]), "data centre: saved and loaded with its deal")
	data.erase("deals")
	sim.from_save(data)
	check(sim.deals.is_empty(), "data centre: an older save loads with no deals")
	data["deals"] = [{"id": id, "company": company, "scale": 1, "month": sim.month, "tiles": [dc], "opened": true}]
	sim.from_save(data)
	# Bulldozed: the company leaves.
	_place("bulldoze", o + Vector2i(0, 5), o + Vector2i(3, 7))
	sim.call("_update_letters")
	check(sim.deals.is_empty() and String(sim.news[0]).contains("left"), "data centre: bulldozed, %s leaves (%s)" % [company, sim.news[0] if not sim.news.is_empty() else ""])
	# A deal never given a site lapses after 6 months.
	sim.deals.append({"id": 999, "company": "Google", "scale": 0, "month": sim.month, "tiles": [], "opened": false,
		"break_left": 0, "priority": false, "investment": 5000})
	sim.month += Settings.DC_PLACE_MONTHS
	sim.call("_update_letters")
	check(sim.deals.is_empty() and String(sim.news[0]).contains("gave up waiting"), "data centre: a deal with no site for 6 months lapses")
	sim.letters.clear()

	# Each company's data centre looks its own: three side by side, drawn whole.
	var lots := [["Amazon", Vector2i(0, 5)], ["Microsoft", Vector2i(4, 5)], ["Google", Vector2i(8, 5)]]
	for n: int in lots.size():
		var at: Vector2i = o + lots[n][1]
		var spots: Array[int] = []
		for y: int in 3:
			for x: int in 4:
				var ti := (at.y + y) * sim.w + at.x + x
				sim.set_tile(ti, T.DATA_CENTRE)
				spots.append(ti)
		sim.deals.append({"id": 500 + n, "company": lots[n][0], "scale": 1, "month": sim.month, "tiles": [],
			"opened": true, "break_left": 0, "priority": false, "investment": 0})
		sim.place_deal(500 + n, spots)
	sim.population = 6000
	_place("nuclear", o + Vector2i(25, 6))
	sim.recount()
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_refresh_hud")
	hud.call("set_build_open", false)
	await _look_at(o + Vector2i(6, 7), PLAY_DISTANCE * 1.1, -20.0, 40.0, [])
	await _frames(5)
	await _shot("p34_data_centres")
	await _look_at(o + Vector2i(10, 6), PLAY_DISTANCE * 0.45, 140.0, 30.0, [])
	await _shot("p35_data_centre_google_close")
	var drawn := 0
	for n: int in 3:
		drawn += 1 if sim.deals[n]["count"] == 12 else 0
	check(drawn == 3, "data centre: three companies' data centres, 12 tiles each, drawn whole")
	game.call("_refresh_hud")


func _gigafactory() -> void:
	# Tesla's Gigafactory (tech layer step 5, Nov 2026): Elon writes from 4,000
	# people, wants a motorway; you pick a size and drag out its site; "done in
	# 6 months" takes 1-3 years (a building site with cranes until then); then it
	# invests, brings hundreds of jobs and a little smoke.
	var T := Simulation.Tile
	await _open_new_city_from_menu()
	await _key(KEY_2)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var o := _find_land(30, 14)
	check(o.x >= 0, "gigafactory: a new city with flat land at %s" % o)
	if o.x < 0:
		return
	sim.money = 2000000
	_place("road", o, o + Vector2i(29, 0))
	_place("road", o + Vector2i(0, 4), o + Vector2i(29, 4))
	_place("homes_1", o + Vector2i(0, 1), o + Vector2i(26, 3))
	for n: int in 3:
		_place("water_pump", o + Vector2i(27, 1 + n))
	_fill_plots(o + Vector2i(0, 1), o + Vector2i(26, 3))
	sim.recount()
	sim.population = 6000
	_place("nuclear", o + Vector2i(28, 1))
	_place("nuclear", o + Vector2i(28, 2))
	_place("tech_zone", o + Vector2i(0, 5), o + Vector2i(14, 10))
	sim.change_tech_tax(-0.03)
	sim.recount()
	var line := ""
	for l: String in sim.interest_lines():
		if l.begins_with("Tesla"):
			line = l
	check(sim.population >= 4000 and line.contains("interested") and line.contains("motorway"),
		"gigafactory: %d people: %s" % [sim.population, line])
	_place("motorway", o + Vector2i(0, 12), o + Vector2i(29, 12))
	sim.recount()
	check(sim.has_motorway() and sim.project_chance("gigafactory") > 0.0, "gigafactory: with a motorway Tesla is keener")
	var tries := 0
	while not sim.call("_has_letter", "gigafactory") and tries < 600:
		sim.call("_update_letters")
		for letter: Dictionary in sim.letters.duplicate():
			if String(letter["kind"]) != "gigafactory":
				sim.letters.erase(letter)
		tries += 1
	var id := -1
	for letter: Dictionary in sim.letters:
		if String(letter["kind"]) == "gigafactory":
			id = letter["id"]
	check(id >= 0 and String(sim.letter_by_id(id)["body"]).contains("6 months (definitely)"),
		"gigafactory: Elon writes (after %d months' worth of chances)" % tries)
	if id < 0:
		return
	game.call("_refresh_hud")
	hud.call("open_letter", id)
	await _frames(3)
	var sizes: Array[Button] = []
	for child: Node in (hud.get("_letter_options") as VBoxContainer).get_children():
		if child is Button:
			sizes.append(child)
	check(sizes.size() == 3 and sizes[0].text.begins_with("Small: 9 tiles") and sizes[0].text.contains("600 jobs"),
		"gigafactory: three sizes (%s)" % (sizes[0].text.replace("\n", " / ") if not sizes.is_empty() else ""))
	await _shot("p36_gigafactory_letter")
	await _click(sizes[0])
	await _frames(2)
	check(int(game.get("_placing_deal")) == id, "gigafactory: yes to Small: placing its site")
	await _look_at(o + Vector2i(2, 7), PLAY_DISTANCE, -40.0, 50.0, [o + Vector2i(0, 4), o + Vector2i(6, 4), o + Vector2i(6, 10)])
	await _drag(_screen_of(o + Vector2i(0, 5)), _screen_of(o + Vector2i(2, 7)))
	await _frames(2)
	var k: int = sim.deal_by_id(id)
	var tile := (o.y + 5) * sim.w + o.x
	check(_count(T.GIGAFACTORY, o + Vector2i(0, 5), o + Vector2i(14, 10)) == 9 and k >= 0 and sim.deal_building(k),
		"gigafactory: a 3 x 3 drag lays out its site, and building starts")
	var opens: int = sim.deals[k]["opens"] - sim.month
	check(opens >= 12 and opens <= 36 and String(game.call("_tile_text", tile)).contains("Elon says six more months")
		and sim.power_use(tile) == 0, "gigafactory: \"six months\" will really be %d; its hover says six more months" % opens)
	game.set("_buildings_dirty", true)
	hud.call("set_build_open", false)
	await _look_at(o + Vector2i(1, 6), PLAY_DISTANCE * 0.6, -30.0, 32.0, [])
	await _shot("p37_gigafactory_being_built")

	# Months go by... it opens late, invests, and the jobs arrive.
	var months := 0
	var said := ""
	while said == "" and months < 40:
		sim.tick()
		months += 1
		for n: String in sim.news:
			if n.contains("Gigafactory"):
				said = n
	k = sim.deal_by_id(id)
	check(k >= 0 and bool(sim.deals[k]["opened"]) and said.contains("open at last"),
		"gigafactory: open after %d months (%s)" % [months, said])
	check(sim.company_jobs >= 600 and sim.pollution_at(tile + 3 * sim.w) > 0.0,
		"gigafactory: %d jobs, and a little smoke nearby" % sim.company_jobs)
	var data := sim.to_save()
	sim.from_save(data)
	k = sim.deal_by_id(id)
	check(k >= 0 and sim.deal_kind(sim.deals[k]) == "gigafactory" and bool(sim.deals[k]["opened"]),
		"gigafactory: saved and loaded")
	game.set("_buildings_dirty", true)
	game.call("_refresh_hud")
	await _look_at(o + Vector2i(1, 6), PLAY_DISTANCE * 0.6, -30.0, 32.0, [])
	await _shot("p38_gigafactory_open")
	sim.letters.clear()
	await _musk_threat(id, tile)


func _musk_threat(id: int, tile: int) -> void:
	# Elon threatens to move to Texas when the Tech zone tax goes up (Big Tech,
	# Nov 2026). Put it back and he's happy; keep it and he leaves (or bluffs).
	var T := Simulation.Tile
	var was: float = sim.tech_tax_rate
	sim.change_tech_tax(0.02)
	sim.call("_check_musk_tax")
	var letter: Dictionary = {}
	for l: Dictionary in sim.letters:
		if String(l["kind"]) == "musk_threat":
			letter = l
	check(not letter.is_empty() and String(letter["body"]).contains("Texas") and is_equal_approx(float(letter["rate"]), was),
		"Elon: raising the Tech zone tax brings a letter threatening to move Tesla to Texas")
	if letter.is_empty():
		return
	game.call("_refresh_hud")
	hud.call("open_letter", int(letter["id"]))
	await _frames(3)
	var back := _find_button(hud.get("letter_panel"), "Put it back to %d%%" % roundi(was * 100.0))
	check(back != null and _find_button(hud.get("letter_panel"), "Keep the tax") != null,
		"Elon: the card offers Put it back or Keep the tax")
	await _shot("p52_elon_threat")
	await _click(back)
	await _frames(2)
	check(is_equal_approx(sim.tech_tax_rate, was) and sim.deal_by_id(id) >= 0 and not hud.call("letter_open"),
		"Elon: put back, the tax is %d%% again and Tesla stays" % roundi(sim.tech_tax_rate * 100.0))
	# Keep it: he leaves, or now and then changes his mind (and accepts the new rate).
	var outcomes := {}
	for n: int in 12:
		if sim.deal_by_id(id) < 0:
			break
		sim.change_tech_tax(0.01)
		sim.call("_check_musk_tax")
		var lid := -1
		for l: Dictionary in sim.letters:
			if String(l["kind"]) == "musk_threat":
				lid = l["id"]
		if lid < 0:
			break
		var said := String(sim.answer_letter(lid, false)["text"])
		if said.contains("changed his mind"):
			outcomes["bluff"] = true
			check(sim.deal_by_id(id) >= 0 and is_equal_approx(float(sim.deals[sim.deal_by_id(id)]["tax_seen"]), sim.tech_tax_rate),
				"Elon: a bluff: Tesla stays and he puts up with the new rate (%s)" % said)
		elif said.contains("Texas"):
			outcomes["left"] = true
	var why := String(game.call("_tile_text", tile))
	check(outcomes.has("left") and sim.deal_by_id(id) < 0 and sim.tiles[tile] == T.GIGAFACTORY and why.contains("Tesla left")
		and why.contains("Tech zone tax"), "Elon: keep the tax and Tesla moves to Texas; its empty halls say why (%s)" % why)
	sim.tech_tax_rate = was
	sim.letters.clear()
	sim.empty_sites.clear()


func _campus() -> void:
	# Google's campus (tech layer step 5, Nov 2026): Sundar writes from 6,000
	# people, keener with schools near homes; it opens in exactly nine months;
	# then thousands of well-paid jobs push house prices up ("cost of living").
	var T := Simulation.Tile
	await _open_new_city_from_menu()
	await _key(KEY_2)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var o := _find_land(30, 16)
	check(o.x >= 0, "campus: a new city with flat land at %s" % o)
	if o.x < 0:
		return
	sim.money = 3000000
	for row: int in [0, 4, 8]:
		_place("road", o + Vector2i(0, row), o + Vector2i(29, row))
	_place("homes_1", o + Vector2i(0, 1), o + Vector2i(25, 3))
	_place("homes_1", o + Vector2i(0, 5), o + Vector2i(25, 7))
	for n: int in 3:
		_place("water_pump", o + Vector2i(26, 1 + n))
		_place("water_pump", o + Vector2i(26, 5 + n))
	_fill_plots(o + Vector2i(0, 1), o + Vector2i(25, 7))
	sim.population = 9000
	_place("nuclear", o + Vector2i(28, 1))
	_place("nuclear", o + Vector2i(28, 5))
	_place("tech_zone", o + Vector2i(0, 9), o + Vector2i(14, 14))
	sim.change_tech_tax(-0.03)
	sim.recount()
	var line := ""
	for l: String in sim.interest_lines():
		if l.begins_with("Campuses (Google, Apple, Meta)"):
			line = l
	check(sim.population >= 6000 and line.contains("schools near more homes"), "campus: %d people: %s" % [sim.population, line])
	var no_schools: float = sim.project_chance("campus")
	for at: Vector2i in [Vector2i(5, 3), Vector2i(13, 3), Vector2i(21, 3), Vector2i(5, 5), Vector2i(13, 5), Vector2i(21, 5)]:
		_place("school", o + at)
	sim.recount()
	check(sim.schooled_share() >= 0.6 and sim.project_chance("campus") > no_schools * 3.0,
		"campus: with schools near %d%% of homes, Google is keener" % roundi(sim.schooled_share() * 100.0))
	# (A campus letter comes about once in 150 months here, and only one in three
	# is Google's: 600 tries failed about a third of the time, so give it plenty.)
	var tries := 0
	while not sim.call("_has_letter", "campus") and tries < 6000:
		sim.call("_update_letters")
		for letter: Dictionary in sim.letters.duplicate():
			if String(letter["kind"]) != "campus" or String(letter["company"]) != "Google":   # (Google's first)
				sim.letters.erase(letter)
		tries += 1
	var id := -1
	for letter: Dictionary in sim.letters:
		if String(letter["kind"]) == "campus":
			id = letter["id"]
	check(id >= 0 and String(sim.letter_by_id(id)["from"]).contains("Sundar Pichai"),
		"campus: Google writes (after %d months' worth of chances)" % tries)
	if id < 0:
		return
	game.call("_refresh_hud")
	hud.call("open_letter", id)
	await _frames(3)
	var sizes: Array[Button] = []
	for child: Node in (hud.get("_letter_options") as VBoxContainer).get_children():
		if child is Button:
			sizes.append(child)
	check(sizes.size() == 3 and sizes[0].text.begins_with("Small: 6 tiles") and sizes[0].text.contains("800 jobs"),
		"campus: three sizes (%s)" % (sizes[0].text.replace("\n", " / ") if not sizes.is_empty() else ""))
	await _shot("p39_campus_letter")
	await _click(sizes[0])
	await _frames(2)
	await _look_at(o + Vector2i(2, 10), PLAY_DISTANCE, -40.0, 50.0, [o + Vector2i(0, 8), o + Vector2i(6, 8), o + Vector2i(6, 13)])
	await _drag(_screen_of(o + Vector2i(0, 9)), _screen_of(o + Vector2i(2, 10)))
	await _frames(2)
	var k: int = sim.deal_by_id(id)
	var tile := (o.y + 9) * sim.w + o.x
	check(_count(T.TECH_CAMPUS, o + Vector2i(0, 9), o + Vector2i(14, 14)) == 6 and k >= 0 and sim.deal_building(k)
		and int(sim.deals[k]["opens"]) - sim.month == 9 and String(game.call("_tile_text", tile)).contains("exactly, says Google"),
		"campus: a 3 x 2 drag lays out its site; it opens in exactly nine months")
	var price_before: int = sim.home_price((o.y + 2) * sim.w + o.x + 1)
	var months := 0
	var said := ""
	while said == "" and months < 15:
		sim.tick()
		months += 1
		for n: String in sim.news:
			if n.contains("campus"):
				said = n
	check(months == 9 and said.contains("open"), "campus: open after %d months (%s)" % [months, said])
	var rise: float = sim.campus_price_rise()
	var cost: float = sim.happiness_parts.get("cost", 0.0)
	var home := (o.y + 2) * sim.w + o.x + 1
	check(sim.company_jobs >= 800 and rise > 0.05 and cost < 0.0,
		"campus: %d jobs; home prices up %d%%, costing %.2f appeal" % [sim.company_jobs, roundi(rise * 100.0), cost])
	check(String(game.call("_tile_text", home)).contains("with tech salaries"), "campus: a home's hover says prices are up")
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_select_tool", ROAD)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_refresh_hud")
	hud.call("set_build_open", false)
	await _look_at(o + Vector2i(1, 10), PLAY_DISTANCE * 0.5, -30.0, 32.0, [])
	await _shot("p40_campus_small")
	# A bigger one shows the lawn quad: a Mega site, 6 x 6.
	var spots: Array[int] = []
	for y: int in 6:
		for x: int in 6:
			var ti := (o.y + 9 + y) * sim.w + o.x + 6 + x
			sim.set_tile(ti, T.TECH_CAMPUS)
			spots.append(ti)
	sim.deals.append({"id": 900, "kind": "campus", "company": "Google", "scale": 2, "month": sim.month, "tiles": [],
		"opened": true, "opens": 0, "break_left": 0, "priority": false, "investment": 0})
	sim.place_deal(900, spots)
	sim.deals[sim.deal_by_id(900)]["opens"] = 0
	sim.recount()
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_refresh_hud")
	await _look_at(o + Vector2i(9, 12), PLAY_DISTANCE * 0.9, -30.0, 40.0, [])
	await _shot("p41_campus_mega")
	# The same site as Apple's: a ring, which won't open beside dirty air.
	var mega: Dictionary = sim.deals[sim.deal_by_id(900)]
	mega["company"] = "Apple"
	sim.recount()
	check(sim.deal_problem(sim.deal_by_id(900)) == "", "campus: Apple's opens where the air is clean")
	_place("coal", o + Vector2i(13, 10))
	sim.recount()
	var why: String = sim.deal_problem(sim.deal_by_id(900))
	check(why.contains("isn't clean enough for Apple") and String(game.call("_tile_text", spots[0])).contains("clean enough"),
		"campus: with a coal plant beside it, Apple's stays shut (%s)" % why)
	_place("bulldoze", o + Vector2i(13, 10), o + Vector2i(14, 11))
	sim.recount()
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_refresh_hud")
	await _look_at(o + Vector2i(9, 12), PLAY_DISTANCE * 0.9, -30.0, 40.0, [])
	await _shot("p55_campus_apple")
	# ...and as Meta's: one long building with a park on its roof, which pivots.
	mega["company"] = "Meta"
	mega["pivot_at"] = sim.month
	mega["opened_month"] = sim.month - 1
	var jobs_before: int = sim.deal_jobs(mega)
	var power_before: int = sim.deal_power(mega)
	sim.news.clear()
	sim.call("_update_deals")
	var pivot := String(mega.get("pivot", ""))
	check((pivot == "metaverse" and sim.deal_jobs(mega) < jobs_before) or (pivot == "ai" and sim.deal_power(mega) == power_before * 3),
		"campus: Meta pivots (%s): %s" % [pivot, sim.news[0] if not sim.news.is_empty() else ""])
	var data := sim.to_save()
	sim.from_save(data)
	check(String(sim.deals[sim.deal_by_id(900)].get("pivot", "")) == pivot, "campus: the pivot is saved")
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_refresh_hud")
	await _look_at(o + Vector2i(9, 12), PLAY_DISTANCE * 0.9, -30.0, 40.0, [])
	await _shot("p56_campus_meta")
	sim.letters.clear()


func _find_coast(wide: int, high: int) -> Vector2i:
	# Flat land wide x high with the sea beside some tile below its first row
	# (where a launch site goes); nearest the camera. (-1, -1) if none.
	var water: PackedByteArray = game.get("water")
	var slope: PackedFloat32Array = game.get("slope")
	var start := Vector2i(roundi(rig.target.x / world.cell), roundi(rig.target.z / world.cell))
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y: int in range(2, sim.h - high - 2):
		for x: int in range(2, sim.w - wide - 2):
			var ok := true
			var coast := false
			for dy: int in high:
				for dx: int in wide:
					var i := (y + dy) * sim.w + x + dx
					if water[i] == 1 or slope[i] > Settings.MAX_SLOPE_M * 0.5 or sim.tiles[i] != Simulation.Tile.EMPTY:
						ok = false
						break
					if dy > 0 and dx < wide - 1 and sim.call("_beside_sea", i):   # (inside the Tech zone the test paints)
						coast = true
				if not ok:
					break
			var d := (Vector2i(x, y) - start).length_squared()
			if ok and coast and d < best_d:
				best = Vector2i(x, y)
				best_d = d
	return best


func _launch_site() -> void:
	# SpaceX's launch site (tech layer step 5, Nov 2026): Elon writes from 5,000
	# people once a Tech zone has open land on the coast; the site must touch the
	# sea; it takes years ("six months"); then tourists, jobs, launches, a safety
	# zone where homes can't grow, and now and then a rocket blows up.
	var T := Simulation.Tile
	await _open_new_city_from_menu()
	await _key(KEY_2)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var o := _find_land(30, 10)
	check(o.x >= 0, "launch site: a new city with flat land at %s" % o)
	if o.x < 0:
		return
	sim.money = 3000000
	for row: int in [0, 4, 8]:
		_place("road", o + Vector2i(0, row), o + Vector2i(29, row))
	_place("homes_1", o + Vector2i(0, 1), o + Vector2i(25, 3))
	_place("homes_1", o + Vector2i(0, 5), o + Vector2i(25, 7))
	for n: int in 3:
		_place("water_pump", o + Vector2i(26, 1 + n))
	_fill_plots(o + Vector2i(0, 1), o + Vector2i(25, 7))
	sim.population = 9000
	_place("nuclear", o + Vector2i(28, 1))
	var c := _find_coast(8, 6)
	check(c.x >= 0, "launch site: open land on the coast at %s" % c)
	if c.x < 0:
		return
	# A road along the top, a coal plant and a water pump beside the site, and a Tech zone.
	_place("road", c, c + Vector2i(7, 0))
	_place("coal", c + Vector2i(7, 1))
	_place("water_pump", c + Vector2i(7, 2))
	sim.recount()
	var line := ""
	for l: String in sim.interest_lines():
		if l.begins_with("SpaceX"):
			line = l
	check(line.contains("wants open land on the coast") or line.contains("want at least"),
		"launch site: no coastal Tech zone yet: %s" % line)
	_place("tech_zone", c + Vector2i(0, 1), c + Vector2i(6, 5))
	sim.change_tech_tax(-0.03)
	sim.recount()
	check(sim.project_chance("launch_site") > 0.0, "launch site: with a Tech zone on the coast, SpaceX is interested")
	var tries := 0
	while not sim.call("_has_letter", "launch_site") and tries < 800:
		sim.call("_update_letters")
		for letter: Dictionary in sim.letters.duplicate():
			if String(letter["kind"]) != "launch_site":
				sim.letters.erase(letter)
		tries += 1
	var id := -1
	for letter: Dictionary in sim.letters:
		if String(letter["kind"]) == "launch_site":
			id = letter["id"]
	check(id >= 0 and String(sim.letter_by_id(id)["body"]).contains("excellent data"),
		"launch site: Elon writes (after %d months' worth of chances)" % tries)
	if id < 0:
		return
	game.call("_refresh_hud")
	hud.call("open_letter", id)
	await _frames(3)
	var sizes: Array[Button] = []
	for child: Node in (hud.get("_letter_options") as VBoxContainer).get_children():
		if child is Button:
			sizes.append(child)
	await _shot("p42_launch_letter")
	await _click(sizes[0])
	await _frames(2)
	# Find a 3 x 2 box in the zone that touches the sea, and one that doesn't (if any).
	var touching := Vector2i(-1, -1)
	var inland := Vector2i(-1, -1)
	for y: int in range(1, 5):
		for x: int in range(0, 5):
			var coast := false
			for dy: int in 2:
				for dx: int in 3:
					if sim.call("_beside_sea", (c.y + y + dy) * sim.w + c.x + x + dx):
						coast = true
			if coast and touching.x < 0:
				touching = Vector2i(x, y)
			elif not coast and inland.x < 0:
				inland = Vector2i(x, y)
	await _look_at(c + Vector2i(3, 3), PLAY_DISTANCE, -40.0, 50.0, [c, c + Vector2i(7, 0), c + Vector2i(7, 5)])
	if inland.x >= 0:
		await _drag(_screen_of(c + inland), _screen_of(c + inland + Vector2i(2, 1)), MOUSE_BUTTON_LEFT, false)
		var info: Label = hud.get("info_label")
		check(info.text.contains("touch the coast"), "launch site: a drag away from the sea is red: %s" % info.text)
		await _press(_screen_of(c + inland + Vector2i(2, 1)), MOUSE_BUTTON_LEFT, false)
		await _frames(2)
	await _drag(_screen_of(c + touching), _screen_of(c + touching + Vector2i(2, 1)))
	await _frames(2)
	# A road along its top edge (and down to the coal plant), as a player would lay.
	var r := touching.y - 1
	if r >= 1:
		_place("road", c + Vector2i(0, r), c + Vector2i(6, r))
		if r >= 3:
			_place("road", c + Vector2i(7, 3), c + Vector2i(7, r))
	sim.recount()
	var k: int = sim.deal_by_id(id)
	var tile := (c.y + touching.y) * sim.w + c.x + touching.x
	check(k >= 0 and sim.deals[k]["count"] == 6 and sim.deal_building(k)
		and String(game.call("_tile_text", tile)).contains("Elon says six more months"),
		"launch site: built on the coast; \"six months\" will be %d" % (int(sim.deals[k]["opens"]) - sim.month if k >= 0 else -1))
	# Homes can't grow in its safety zone.
	var near := -1
	for ti: int in range(sim.w * sim.h):
		if near < 0 and sim.tiles[ti] == T.EMPTY and sim.in_launch_zone(ti) and sim.district[ti] == Settings.TECH_ZONE:
			near = ti
	if near >= 0:
		sim.set_tile(near, T.HOMES)
		sim.recount()
		check(String(sim.zone_status(near)).contains("safety zone"), "launch site: homes in its safety zone can't grow (%s)" % sim.zone_status(near))
		sim.set_tile(near, T.EMPTY)
	var months := 0
	var said := ""
	while said == "" and months < 60:
		sim.tick()
		months += 1
		for n: String in sim.news:
			if n.contains("launch site is open"):
				said = n
	k = sim.deal_by_id(id)
	check(said.contains("open at last") and is_equal_approx(sim.project_tourism(), 0.004) and sim.company_jobs >= 300,
		"launch site: open after %d months: %d jobs, tourists (%s)" % [months, sim.company_jobs, said])
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_select_tool", ROAD)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_refresh_hud")
	hud.call("set_build_open", false)
	await _look_at(c + touching + Vector2i(1, 0), PLAY_DISTANCE * 0.7, -30.0, 28.0, [])
	await _shot("p43_launch_site")
	# Launches: now and then one blows up, and the site stops for repairs.
	var boom := ""
	for n: int in 3000:
		sim.month += 1
		sim.call("_update_deals")
		for line2: String in sim.news:
			if line2.contains("unscheduled"):
				boom = line2
		sim.news.clear()
		if boom != "":
			break
	k = sim.deal_by_id(id)
	sim.recount()
	var launched: int = sim.deals[k].get("launches", 0) if k >= 0 else 0
	check(boom != "" and String(sim.deal_problem(k)).contains("repaired") and sim.company_jobs == 0
		and launched > 0, "launch site: after %d launches one blew up; repairs stop it (%s)" % [
		launched, sim.deal_problem(k) if k >= 0 else ""])
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	await _frames(3)
	await _shot("p44_launch_site_repairs")
	var data := sim.to_save()
	sim.from_save(data)
	k = sim.deal_by_id(id)
	check(k >= 0 and int(sim.deals[k].get("launches", 0)) > 0 and int(sim.deals[k].get("repair_until", 0)) > sim.month,
		"launch site: saved and loaded with its launches and repairs")
	sim.letters.clear()


func _ai_data_centre() -> void:
	# OpenAI's AI data centre (tech layer step 5, Nov 2026): Sam writes from
	# 10,000 people (all lowercase); each year after it opens he asks for a bit
	# more power; yes and it grows; no (or no answer) three times and it leaves.
	var T := Simulation.Tile
	await _open_new_city_from_menu()
	await _key(KEY_2)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var o := _find_land(34, 16)
	check(o.x >= 0, "AI data centre: a new city with flat land at %s" % o)
	if o.x < 0:
		return
	sim.money = 5000000
	for row: int in [0, 4, 8]:
		_place("road", o + Vector2i(0, row), o + Vector2i(33, row))
	_place("homes_1", o + Vector2i(0, 1), o + Vector2i(29, 3))
	_place("homes_1", o + Vector2i(0, 5), o + Vector2i(29, 7))
	for n: int in 3:
		_place("water_pump", o + Vector2i(30, 1 + n))
		_place("water_pump", o + Vector2i(30, 5 + n))
	_fill_plots(o + Vector2i(0, 1), o + Vector2i(29, 7))
	sim.population = 12000
	for n: int in 3:
		_place("nuclear", o + Vector2i(32, 1 + n * 2))
	_place("tech_zone", o + Vector2i(0, 9), o + Vector2i(15, 14))
	sim.change_tech_tax(-0.03)
	sim.recount()
	check(sim.population >= 10000 and sim.project_chance("ai_data_centre") > 0.0,
		"AI data centre: %d people and a Tech zone: OpenAI is interested" % sim.population)
	var tries := 0
	while not sim.call("_has_letter", "ai_data_centre") and tries < 1000:
		sim.call("_update_letters")
		for letter: Dictionary in sim.letters.duplicate():
			if String(letter["kind"]) != "ai_data_centre":
				sim.letters.erase(letter)
		tries += 1
	var id := -1
	for letter: Dictionary in sim.letters:
		if String(letter["kind"]) == "ai_data_centre":
			id = letter["id"]
	check(id >= 0 and String(sim.letter_by_id(id)["body"]).begins_with("hi mayor"),
		"AI data centre: Sam writes, all lowercase (after %d months' worth of chances)" % tries)
	if id < 0:
		return
	game.call("_refresh_hud")
	hud.call("open_letter", id)
	await _frames(3)
	var sizes: Array[Button] = []
	for child: Node in (hud.get("_letter_options") as VBoxContainer).get_children():
		if child is Button:
			sizes.append(child)
	await _click(sizes[0])
	await _frames(2)
	await _look_at(o + Vector2i(2, 11), PLAY_DISTANCE, -40.0, 50.0, [o + Vector2i(0, 8), o + Vector2i(6, 8), o + Vector2i(6, 14)])
	await _drag(_screen_of(o + Vector2i(0, 9)), _screen_of(o + Vector2i(3, 12)))
	await _frames(2)
	var k: int = sim.deal_by_id(id)
	check(k >= 0 and int(sim.deals[k]["count"]) == 16 and sim.deal_building(k), "AI data centre: a 4 x 4 site, being built")
	var months := 0
	var said := ""
	while said == "" and months < 30:
		sim.tick()
		months += 1
		for n: String in sim.news:
			if n.contains("AI data centre is open"):
				said = n
	k = sim.deal_by_id(id)
	check(said != "" and sim.company_jobs >= 60 and sim.deal_power(sim.deals[k]) == 1000,
		"AI data centre: open after %d months, using 1,000 power (%s)" % [months, said])
	# A year on: "we need a bit more power".
	var ask := -1
	for n: int in 14:
		sim.tick()
		for letter: Dictionary in sim.letters:
			if String(letter["kind"]) == "more_power":
				ask = letter["id"]
		if ask >= 0:
			break
	check(ask >= 0, "AI data centre: a year after opening, Sam asks for more power")
	if ask < 0:
		return
	game.call("_refresh_hud")
	hud.call("open_letter", ask)
	await _frames(3)
	var more := _find_button(hud.get("letter_panel"), "Give it more power")
	check(more != null and String((hud.get("_letter_body") as Label).text).contains("a bit more power"),
		"AI data centre: the letter offers Give it more power")
	await _shot("p45_more_power_letter")
	await _click(more)
	await _frames(2)
	k = sim.deal_by_id(id)
	check(sim.deal_power(sim.deals[k]) == 1250 and String(game.call("_tile_text", (o.y + 9) * sim.w + o.x)).contains("1,250 power now (x1.25"),
		"AI data centre: yes: it now uses 1,250 power")
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_select_tool", ROAD)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_refresh_hud")
	hud.call("set_build_open", false)
	await _look_at(o + Vector2i(2, 11), PLAY_DISTANCE * 0.6, -30.0, 32.0, [])
	await _shot("p46_ai_data_centre")
	# Ignored once, then no twice: OpenAI leaves, its empty halls stay.
	var first: int = sim.call("_send_letter", Companies.more_power_letter(id))
	sim.month += Settings.LETTER_MONTHS
	sim.call("_update_letters")
	k = sim.deal_by_id(id)
	check(k >= 0 and int(sim.deals[k]["refusals"]) == 1 and sim.letter_by_id(first).is_empty(),
		"AI data centre: a request left unanswered counts as a no (1 of %d)" % Settings.AI_REFUSALS)
	var second: int = sim.call("_send_letter", Companies.more_power_letter(id))
	var sulk := String(sim.answer_letter(second, false)["text"])
	check(sulk.contains("One more and OpenAI leaves"), "AI data centre: the second no warns it's the last (%s)" % sulk)
	# The last ask is marked, and opens by itself when it arrives (so it can't lapse unseen on Fast).
	k = sim.deal_by_id(id)
	sim.letters.clear()
	sim.deals[k]["opened_month"] = sim.month + 1 - 12     # (a year old next month)
	game.set("clock", Settings.MONTH_SECONDS - 0.02)
	game.call("_set_speed", 1)
	var final_id := -1
	for n: int in 120:
		await get_tree().process_frame
		if hud.call("letter_open"):
			break
	for letter: Dictionary in sim.letters:
		if String(letter["kind"]) == "more_power":
			final_id = letter["id"]
	check(final_id >= 0 and bool(sim.letter_by_id(final_id).get("last", false)),
		"AI data centre: after two no's, its next ask is its last")
	if final_id < 0:
		return
	await _frames(3)
	var note := String((hud.get("_letter_note") as Label).text)
	check(hud.call("letter_open") and int(game.get("speed")) == 0 and note.contains("last ask"),
		"AI data centre: the last ask opens on its card, the clock stops, and it says so (%s)" % note)
	await _shot("p50_last_ask")
	hud.call("close_letter")
	game.call("_set_speed", 0)
	var last := String(sim.answer_letter(final_id, false)["text"])
	var hall := (o.y + 9) * sim.w + o.x
	var why := String(game.call("_tile_text", hall))
	check(sim.deal_by_id(id) < 0 and last.contains("moved its data centre") and sim.tiles[hall] == T.AI_DATA_CENTRE
		and why.contains("OpenAI left in") and why.contains("more power"),
		"AI data centre: three no's and OpenAI leaves; its empty halls stay, and say why (%s)" % why)
	# A cloud company may take over the empty halls.
	var halls: int = (sim.empty_site_at(hall)["tiles"] as Array).size()
	check(sim.interest_lines()[-1].contains("take over OpenAI's %d empty halls" % halls),
		"empty halls: Who's interested says a cloud company may take them over")
	sim.letters.clear()
	var offer := -1
	for n: int in 600:
		sim.call("_update_letters")
		for letter: Dictionary in sim.letters:
			if String(letter["kind"]) == "takeover":
				offer = letter["id"]
		if offer >= 0:
			break
		sim.letters.clear()
	check(offer >= 0 and String(sim.letter_by_id(offer)["body"]).contains("OpenAI"),
		"empty halls: a cloud company writes to take them over")
	if offer < 0:
		return
	game.call("_refresh_hud")
	hud.call("open_letter", offer)
	await _frames(3)
	var take := _find_button(hud.get("letter_panel"), "Let them move in")
	check(take != null, "empty halls: the letter offers Let them move in")
	await _shot("p51_takeover_letter")
	var who := String(sim.letter_by_id(offer)["company"])
	await _click(take)
	await _frames(2)
	var dk: int = sim.deal_by_id(offer)
	check(dk >= 0 and sim.tiles[hall] == T.DATA_CENTRE and sim.empty_sites.is_empty()
		and String(sim.deals[dk]["company"]) == who and int(sim.deals[dk]["count"]) == halls,
		"empty halls: %s takes over all %d halls as a %s data centre" % [who, halls, String(sim.deal_scale(sim.deals[dk])["name"]).to_lower()])
	# Saved and loaded; halls with no record (an older save) are put down to OpenAI.
	var data := sim.to_save()
	sim.from_save(data)
	check(sim.deal_by_id(offer) >= 0 and sim.empty_sites.is_empty(), "empty halls: saved and loaded")
	sim.deals.remove_at(sim.deal_by_id(offer))
	sim.tiles[hall] = T.AI_DATA_CENTRE
	sim.call("_index_deals")
	sim.call("_tidy_empty_sites")
	check(String(game.call("_tile_text", hall)).contains("OpenAI left, because"),
		"empty halls: AI halls with no record are put down to OpenAI")
	sim.letters.clear()
	sim.empty_sites.clear()
	game.call("_refresh_hud")


func _chip_factory() -> void:
	# Nvidia's chip factory (Big Tech, Nov 2026): Jensen writes from 8,000 people;
	# the bigger the better the deal (the Mega one asks no tax break); it drinks
	# water and gives off a little chemical pollution.
	var T := Simulation.Tile
	await _open_new_city_from_menu()
	await _key(KEY_2)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var o := _find_land(34, 16)
	check(o.x >= 0, "chip factory: a new city with flat land at %s" % o)
	if o.x < 0:
		return
	sim.money = 5000000
	for row: int in [0, 4, 8]:
		_place("road", o + Vector2i(0, row), o + Vector2i(33, row))
	_place("homes_1", o + Vector2i(0, 1), o + Vector2i(29, 3))
	_place("homes_1", o + Vector2i(0, 5), o + Vector2i(29, 7))
	for n: int in 3:
		_place("water_pump", o + Vector2i(30, 1 + n))
		_place("water_pump", o + Vector2i(30, 5 + n))
	_fill_plots(o + Vector2i(0, 1), o + Vector2i(29, 7))
	sim.population = 9000
	_place("nuclear", o + Vector2i(32, 1))
	_place("tech_zone", o + Vector2i(0, 9), o + Vector2i(15, 14))
	sim.change_tech_tax(-0.03)
	sim.recount()
	check(sim.project_chance("chip_factory") > 0.0 and sim.interest_lines().any(func(l: String): return l.begins_with("Nvidia")),
		"chip factory: %d people and a Tech zone: Nvidia is interested" % sim.population)
	var tries := 0
	while not sim.call("_has_letter", "chip_factory") and tries < 2000:
		sim.call("_update_letters")
		for letter: Dictionary in sim.letters.duplicate():
			if String(letter["kind"]) != "chip_factory":
				sim.letters.erase(letter)
		tries += 1
	var id := -1
	for letter: Dictionary in sim.letters:
		if String(letter["kind"]) == "chip_factory":
			id = letter["id"]
	check(id >= 0 and String(sim.letter_by_id(id)["body"]).contains("the more you save"),
		"chip factory: Jensen writes (after %d months' worth of chances)" % tries)
	if id < 0:
		return
	game.call("_refresh_hud")
	hud.call("open_letter", id)
	await _frames(3)
	var sizes: Array[Button] = []
	for child: Node in (hud.get("_letter_options") as VBoxContainer).get_children():
		if child is Button:
			sizes.append(child)
	check(sizes.size() == 3 and sizes[0].text.contains("no tax for 8 years") and not sizes[2].text.contains("no tax"),
		"chip factory: the bigger the better: Small asks 8 years without tax, Mega none")
	await _shot("p53_chip_factory_letter")
	await _click(sizes[0])
	await _frames(2)
	await _look_at(o + Vector2i(2, 11), PLAY_DISTANCE, -40.0, 50.0, [o + Vector2i(0, 8), o + Vector2i(6, 8), o + Vector2i(6, 14)])
	await _drag(_screen_of(o + Vector2i(0, 9)), _screen_of(o + Vector2i(2, 11)))
	await _frames(2)
	var k: int = sim.deal_by_id(id)
	check(k >= 0 and int(sim.deals[k]["count"]) == 9 and sim.deal_building(k), "chip factory: a 3 x 3 site, being built")
	var months := 0
	while k >= 0 and not bool(sim.deals[k]["opened"]) and months < 40:
		sim.tick()
		months += 1
		k = sim.deal_by_id(id)
	var tile := (o.y + 9) * sim.w + o.x
	var drinks := 0
	if k >= 0:
		for t in sim.deals[k]["tiles"]:
			drinks += int(sim.call("_deal_share", int(t), "water"))
	check(k >= 0 and bool(sim.deals[k]["opened"]) and drinks >= 340 and sim.company_jobs >= 500,
		"chip factory: open after %d months: %d jobs, drinking %d water" % [months, sim.company_jobs, drinks])
	var text := String(game.call("_tile_text", tile))
	check(sim.pollution_at(tile + 4 * sim.w) > 0.0 and text.contains("drinks water") and text.contains("Nvidia"),
		"chip factory: a little chemical pollution nearby, and its hover says so")
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_refresh_hud")
	hud.call("set_build_open", false)
	await _look_at(o + Vector2i(1, 10), PLAY_DISTANCE * 0.5, -30.0, 32.0, [])
	await _shot("p54_chip_factory")
	var data := sim.to_save()
	sim.from_save(data)
	check(sim.deal_by_id(id) >= 0 and sim.tiles[tile] == T.CHIP_FACTORY, "chip factory: saved and loaded")
	sim.letters.clear()


func _education() -> void:
	# Education and tech workers (tech layer step 3, Nov 2026): a college, a
	# university dragged out as a campus and a research park beside it, from the
	# Build menu's Education category; tech workers rise over the years; big
	# companies are a quarter as keen without enough of them, keener with research.
	var T := Simulation.Tile
	await _open_new_city_from_menu()
	await _key(KEY_2)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var o := _find_land(30, 16)
	check(o.x >= 0, "education: a new city with flat land at %s" % o)
	if o.x < 0:
		return
	sim.money = 3000000
	for row: int in [0, 4, 8]:
		_place("road", o + Vector2i(0, row), o + Vector2i(29, row))
	_place("homes_1", o + Vector2i(0, 1), o + Vector2i(25, 3))
	_place("homes_1", o + Vector2i(0, 5), o + Vector2i(25, 7))
	for n: int in 3:
		_place("water_pump", o + Vector2i(26, 1 + n))
		_place("water_pump", o + Vector2i(26, 5 + n))
	_fill_plots(o + Vector2i(0, 1), o + Vector2i(25, 7))
	sim.population = 9000
	_place("nuclear", o + Vector2i(28, 1))
	_place("nuclear", o + Vector2i(28, 5))
	sim.recount()
	var before: float = sim.call("_tech_target")
	game.call("_refresh_hud")
	var row_label: Label = hud.get("tech_label")
	check(row_label.text.begins_with("Tech workers:"), "education: the City panel shows tech workers (%s)" % row_label.text)

	# The college: from the Build menu, clicked beside the road.
	await _pick_item("education", "college")
	check(_tool() == 16, "education: Education > College picks the Education tool")
	await _look_at(o + Vector2i(8, 11), PLAY_DISTANCE * 1.3, -40.0, 50.0, [o + Vector2i(0, 8), o + Vector2i(16, 8), o + Vector2i(16, 14)])
	await _click_at(_screen_of(o + Vector2i(1, 9)))
	check(sim.tiles[(o.y + 9) * sim.w + o.x + 1] == T.COLLEGE, "education: clicking places a college")
	# A university: drag out a 4 x 3 campus (inner tiles work through the group's road).
	await _pick_item("education", "university")
	await _drag(_screen_of(o + Vector2i(4, 9)), _screen_of(o + Vector2i(7, 11)))
	var uni := _count(T.UNIVERSITY, o + Vector2i(4, 9), o + Vector2i(7, 11))
	sim.recount()
	var inner := (o.y + 11) * sim.w + o.x + 5
	check(uni == 12 and sim.building_working(inner) and sim.students() == 12 * 150,
		"education: a 4 x 3 university, all working (%d students need homes)" % sim.students())
	# A research park: not away from the university; beside it, yes.
	await _pick_item("education", "research_park")
	var far := (o.y + 13) * sim.w + o.x + 15
	var why: String = sim.can_build_here(T.RESEARCH_PARK, far)
	check(why.contains("next to a university"), "education: a research park away from the university is refused (%s)" % why)
	await _drag(_screen_of(o + Vector2i(8, 9)), _screen_of(o + Vector2i(9, 10)))
	sim.recount()
	check(_count(T.RESEARCH_PARK, o + Vector2i(8, 9), o + Vector2i(9, 10)) == 4 and sim.research_boost() > 1.2,
		"education: a research park beside it: big companies %d%% keener" % roundi((sim.research_boost() - 1.0) * 100.0))
	var after: float = sim.call("_tech_target")
	check(after > before + 0.1, "education: the tech workers' target rises from %d%% to %d%%" % [roundi(before * 100.0), roundi(after * 100.0)])
	var share0: float = sim.tech_share
	for m: int in 24:
		sim.tick()
	check(sim.tech_share > share0 + 0.05 and sim.tech_trend() == "rising" or sim.tech_share > share0 + 0.1,
		"education: two years on, tech workers are %s (%d%%, from %d%%)" % [Hud.thousands(sim.tech_workers()),
		roundi(sim.tech_share * 100.0), roundi(share0 * 100.0)])
	# Big companies: a quarter as keen without their tech workers.
	_place("tech_zone", o + Vector2i(14, 9), o + Vector2i(29, 15))
	sim.change_tech_tax(-0.03)
	sim.recount()
	var keep: float = sim.tech_share
	sim.tech_share = 0.0
	var low: float = sim.project_chance("campus")
	var line := ""
	for l: String in sim.interest_lines():
		if l.begins_with("Campuses (Google, Apple, Meta)"):
			line = l
	sim.tech_share = 0.4
	var high: float = sim.project_chance("campus")
	sim.tech_share = keep
	check(high > low * 3.5 and line.contains("more tech workers"),
		"education: Google is 4x keener with its tech workers (%s)" % line)
	var data := sim.to_save()
	sim.from_save(data)
	check(is_equal_approx(sim.tech_share, keep), "education: tech workers saved and loaded")
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_select_tool", ROAD)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	game.call("_refresh_hud")
	await _pick_item("education", "university")
	await _look_at(o + Vector2i(5, 10), PLAY_DISTANCE * 0.8, -30.0, 36.0, [])
	await _shot("p47_education")


func _examples() -> void:
	# The game menu's Example cities (Settings.EXAMPLES, made by tools/make_examples.sh):
	# each loads with a click and is a town that pays its way. Last, as it
	# replaces the city on the map.
	var menu: PanelContainer = hud.get("_menu_panel")
	var people_before := 0
	for item: Dictionary in Settings.EXAMPLES:
		var title: String = item["name"]
		await _click(hud.get("_menu_button"))
		if people_before == 0:
			await _shot("p22_menu_examples")
		await _click(_find_button(menu, title))
		await _wait(0.5)
		check(not menu.visible, "picking the example %s closes the menu" % title)
		check(sim.population > people_before, "the example %s loads: %d people" % [title, sim.population])
		check(sim.last_balance() > 0 and sim.money > 0 and sim.debt == 0,
			"the example %s makes money (%+d a month) and owes nothing" % [title, sim.last_balance()])
		check(sim.abandoned_count == 0 and sim.happiness >= 0.55, "the example %s is a happy town (%d%%), nothing abandoned" % [
			title, roundi(sim.happiness * 100.0)])
		people_before = sim.population
	# Demand (Sam, Nov 2026: "always a demand for shops"): visitors' shopping is
	# capped, and the bars' hover gives numbers and room by density.
	var said := String((hud.get("demand_box") as Control).tooltip_text)
	check(sim.visitor_share <= Settings.VISITOR_SHOP_MAX + 0.0001 and said.contains("Offices:") and said.contains("Shops:")
		and (said.contains("low ") or said.contains("about right")) and not said.contains("steady"),
		"demand: visitors' shopping capped (%.3f), and the bars' hover gives numbers and density:\n%s" % [sim.visitor_share, said])
	# The last one is the biggest city: a year on, it's still growing richer.
	var money := sim.money
	var people := sim.population
	for m: int in 12:
		sim.tick()
	check(sim.money > money and sim.population > people * 0.97,
		"a year on, the example city has more money (%d -> %d) and has kept its people (%d -> %d)" % [
		money, sim.money, people, sim.population])
	await _shot("p23_example_city")
	# Back to the City for the checks that follow (offices, landmarks, the airport):
	# the Bay Area comes last in the menu now.
	game.call("_load_example", "city")
	await _wait(0.5)


# ------------------------------------------------------------------ checks

func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("[play] PASS %s" % what)
	else:
		_failed += 1
		printerr("[play] FAIL %s" % what)


func _tool() -> int:
	var t: int = game.get("current_tool")
	return t


func _tiles_hash() -> int:
	return hash(sim.tiles)


func _count(t: int, from: Vector2i, to: Vector2i) -> int:
	var n := 0
	for y: int in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
		for x: int in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			if sim.tiles[y * sim.w + x] == t:
				n += 1
	return n


# ------------------------------------------------------------------- input

func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for k: int in n:
		await get_tree().process_frame


func _px(pos: Vector2) -> Vector2:
	# Events arrive in window pixels; the game works in points (on Retina, half).
	return pos * get_window().content_scale_factor


func _move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _px(pos)
	e.global_position = _px(pos)
	e.relative = _px(pos) - _px(_mouse)
	e.button_mask = _buttons
	Input.parse_input_event(e)
	_mouse = pos
	await _frames(2)


func _press(pos: Vector2, button: MouseButton, down: bool) -> void:
	var bit := 1 << (button - 1)
	_buttons = (_buttons | bit) if down else (_buttons & ~bit)
	var e := InputEventMouseButton.new()
	e.position = _px(pos)
	e.global_position = _px(pos)
	e.button_index = button
	e.pressed = down
	e.button_mask = _buttons
	e.factor = 1.0
	Input.parse_input_event(e)
	_mouse = pos
	await _frames(2)


func _click_at(pos: Vector2) -> void:
	await _move(pos + Vector2(4, 4))
	await _move(pos)
	await _press(pos, MOUSE_BUTTON_LEFT, true)
	await _press(pos, MOUSE_BUTTON_LEFT, false)
	await _frames(2)


func _click(c: Control) -> void:
	# Click the middle of a control (after letting its panel fade in).
	await _wait(0.2)
	await _click_at(c.get_global_rect().get_center())
	await _wait(0.15)


func _drag(from: Vector2, to: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, release: bool = true) -> void:
	# (A real mouse sends many moves on its way: the first one off a panel closes its tooltip.)
	await _move(from + Vector2(6, 6))
	await _move(from)
	await _press(from, button, true)
	for k: int in range(1, 9):
		await _move(from.lerp(to, k / 8.0))
	if release:
		await _press(to, button, false)
	await _frames(2)
	if button == MOUSE_BUTTON_LEFT and debug_drags:
		print("[play]   drag %s -> %s: hover %s, over %s, painting %s, preview %d" % [from, to, game.get("hover"),
			get_viewport().gui_get_hovered_control(), game.get("painting"), world.preview.multimesh.instance_count])


func _wheel(pos: Vector2, up: bool, times: int = 1) -> void:
	await _move(pos)
	for k: int in times:
		var b := MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		await _press(pos, b, true)
		await _press(pos, b, false)


func _key(code: Key, command: bool = false) -> void:
	for down: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		e.ctrl_pressed = command
		e.meta_pressed = command
		Input.parse_input_event(e)
		await _frames(2)


func _hold_key(code: Key, seconds: float) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await _wait(seconds)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func _screen_of(tile: Vector2i) -> Vector2:
	return rig.camera.unproject_position(world.ground_point(tile))


func _look_at(tile: Vector2i, dist: float, yaw_deg: float = -40.0, pitch_deg: float = 42.0,
		keep_clear: Array[Vector2i] = []) -> void:
	# Put the camera somewhere directly (the controls themselves are tested in
	# _camera_controls), backing off until the tiles in keep_clear aren't under a panel.
	var p := world.ground_point(tile)
	rig.target = p
	rig.distance = dist
	rig.yaw = deg_to_rad(yaw_deg)
	rig.pitch = deg_to_rad(pitch_deg)
	rig.snap()
	for attempt: int in 8:
		var hidden := false
		for t: Vector2i in keep_clear:
			hidden = hidden or _under_hud(_screen_of(t))
		if not hidden:
			break
		rig.distance *= 1.15
		rig.snap()
	await _frames(3)


func _under_hud(pos: Vector2) -> bool:
	var view := get_viewport().get_visible_rect()
	if not view.grow(-8.0).has_point(pos):
		return true
	for c: Control in [hud.build_panel, hud.get("_info_panel"), hud.get("_overlay_panel"), hud.get("_status_island"),
			hud.get("_left_island"), hud.advice_panel, hud.city_panel, hud.help_panel]:
		if c.visible and c.get_global_rect().grow(8.0).has_point(pos):
			return true
	return false


func _shot(shot_name: String) -> void:
	for n: int in 20:
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	if image.get_width() > 1600:
		image.resize(1600, roundi(1600.0 * image.get_height() / image.get_width()), Image.INTERPOLATE_LANCZOS)
	var path := out_dir.path_join(shot_name + ".png")
	if image.save_png(path) != OK:
		check(false, "saving %s" % path)
	else:
		print("[play] saved %s" % path)


func _row(id: String) -> Button:
	var rows: Dictionary = hud.get("_rows")
	var r: Dictionary = rows[id]
	var b: Button = r["button"]
	return b


func _rail(cat: String) -> Button:
	var rails: Dictionary = hud.get("_rail_buttons")
	var b: Button = rails[cat]
	return b


func _pick_item(cat: String, id: String) -> void:
	# Open a Build menu category and click one of its rows, as a player does.
	if not bool(hud.get("_build_open")) or String(hud.get("_category")) != cat:
		await _click(_rail(cat))
	var row := _row(id)
	var scroll: ScrollContainer = hud.get("_scroll")
	scroll.ensure_control_visible(row)
	await _frames(3)
	await _click(row)


func _find_button(root: Node, text: String) -> Button:
	for child: Node in root.get_children():
		var b := child as Button
		if b and b.text == text:
			return b
		var found := _find_button(child, text)
		if found:
			return found
	return null


# ------------------------------------------------------------- the play test

func _find_land(wide: int = 14, high: int = 12) -> Vector2i:
	# A flat patch of open land, 14 x 12 tiles, near where the camera starts:
	# where a player would start a town.
	var start := Vector2i(roundi(rig.target.x / world.cell), roundi(rig.target.z / world.cell))
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	var water: PackedByteArray = game.get("water")
	var slope: PackedFloat32Array = game.get("slope")
	for y: int in range(4, sim.h - high - 4):
		for x: int in range(4, sim.w - wide - 4):
			var ok := true
			for dy: int in high:
				for dx: int in wide:
					var i := (y + dy) * sim.w + x + dx
					if water[i] == 1 or slope[i] > Settings.MAX_SLOPE_M * 0.5:
						ok = false
						break
				if not ok:
					break
			var d := (Vector2i(x, y) - start).length_squared()
			if ok and d < best_d:
				best = Vector2i(x, y)
				best_d = d
	return best


func _corners() -> Array[Vector2i]:
	var o := _origin
	return [o, o + Vector2i(13, 0), o + Vector2i(0, 11), o + Vector2i(13, 11)]


func _blank_start() -> void:
	# The very first thing a player sees: no town, the Build menu, the map.
	var start := Simulation.start_money(Settings.DEFAULT_DIFFICULTY)
	check(sim.population == 0 and sim.money == start, "a new game starts blank with £%d" % start)
	var built := 0
	for i: int in sim.w * sim.h:
		if sim.tiles[i] != Simulation.Tile.EMPTY:
			built += 1
	check(built == 0, "the map is empty at the start")
	await _shot("p01_blank_start")
	var saved_t: float = game.get("time_of_day")
	game.set("time_of_day", 0.95)
	await _shot("p02_blank_start_night")
	game.set("time_of_day", saved_t)


func _camera_controls() -> void:
	var view := get_viewport().get_visible_rect().size
	var centre := view * 0.5
	# Keyboard pan.
	var before := rig.target
	await _hold_key(KEY_W, 0.4)
	check(rig.target.distance_to(before) > 20.0, "W pans the camera")
	before = rig.target
	await _hold_key(KEY_D, 0.4)
	check(rig.target.distance_to(before) > 20.0, "D pans the camera")
	var yaw := rig.yaw
	await _hold_key(KEY_Q, 0.3)
	check(absf(rig.yaw - yaw) > 0.1, "Q turns the camera")
	yaw = rig.yaw
	await _hold_key(KEY_E, 0.3)
	check(absf(rig.yaw - yaw) > 0.1, "E turns the camera")
	# Mouse: wheel zoom, right-drag orbit, middle-drag pan, trackpad gestures.
	var dist := rig.distance
	await _wheel(centre, true, 3)
	check(rig.distance < dist * 0.8, "the wheel over the map zooms in (%.0f -> %.0f m)" % [dist, rig.distance])
	dist = rig.distance
	await _wheel(centre, false, 2)
	check(rig.distance > dist * 1.2, "the wheel over the map zooms out")
	yaw = rig.yaw
	var pitch := rig.pitch
	await _drag(centre, centre + Vector2(120, -60), MOUSE_BUTTON_RIGHT)
	check(absf(rig.yaw - yaw) > 0.2 and absf(rig.pitch - pitch) > 0.1, "right-drag orbits and tilts")
	before = rig.target
	await _drag(centre, centre + Vector2(-150, 80), MOUSE_BUTTON_MIDDLE)
	check(rig.target.distance_to(before) > 50.0, "middle-drag pans")
	before = rig.target
	var pan := InputEventPanGesture.new()
	pan.position = _px(centre)
	pan.delta = Vector2(4, 2)
	Input.parse_input_event(pan)
	await _frames(3)
	check(rig.target.distance_to(before) > 10.0, "two-finger scroll pans")
	dist = rig.distance
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = _px(centre)
	pinch.factor = 1.3
	Input.parse_input_event(pinch)
	await _frames(3)
	check(rig.distance < dist, "pinch zooms")


func _build_first_streets() -> void:
	_origin = _find_land()
	check(_origin.x >= 0, "found flat land to build on at %s" % _origin)
	if _origin.x < 0:
		return
	var o := _origin
	await _click(hud.speed_buttons[0])          # (paused while building, so the money only changes by building)
	await _look_at(o + Vector2i(7, 6), PLAY_DISTANCE, -40.0, 42.0, _corners())

	# A road along the patch, picked from the Build menu.
	await _pick_item("roads", "road")
	check(_tool() == ROAD, "Build menu > Roads > Road picks the road tool")
	var a := o + Vector2i(0, 5)
	var b := o + Vector2i(13, 5)
	var money := sim.money
	# Drag, and look at the preview before letting go.
	await _drag(_screen_of(a), _screen_of(b), MOUSE_BUTTON_LEFT, false)
	var preview_n: int = world.preview.multimesh.instance_count
	check(preview_n == 14, "dragging a road shows a 14-tile preview (got %d)" % preview_n)
	var info: Label = hud.info_label
	check(info.text.contains("Release to build") and info.text.contains("£"), "the drag shows its cost: \"%s\"" % info.text)
	await _shot("p03_road_preview")
	await _press(_screen_of(b), MOUSE_BUTTON_LEFT, false)
	await _frames(3)
	check(_count(Simulation.Tile.ROAD, a, b) == 14, "the road was built on the 14 tiles dragged over")
	check(sim.money < money, "building the road cost money (£%d -> £%d)" % [money, sim.money])
	check(world.preview.multimesh.instance_count == 0, "the preview goes when the road is built")
	# A cross street.
	await _drag(_screen_of(o + Vector2i(6, 0)), _screen_of(o + Vector2i(6, 11)))
	check(_count(Simulation.Tile.ROAD, o + Vector2i(6, 0), o + Vector2i(6, 11)) == 12, "a cross street")

	# Zones, either side of the road.
	await _pick_item("zones", "homes_0")
	check(_tool() == HOMES and int(game.get("current_density")) == 0, "Zones > Low-density homes picks homes, low density")
	await _drag(_screen_of(o + Vector2i(0, 3)), _screen_of(o + Vector2i(5, 4)))
	check(_count(Simulation.Tile.HOMES, o + Vector2i(0, 3), o + Vector2i(5, 4)) == 12, "zoning homes by dragging a box")
	await _pick_item("zones", "homes_1")
	await _drag(_screen_of(o + Vector2i(0, 6)), _screen_of(o + Vector2i(5, 7)))
	check(_count(Simulation.Tile.HOMES, o + Vector2i(0, 6), o + Vector2i(5, 7)) == 12, "medium-density homes")
	await _pick_item("zones", "shops_0")
	await _drag(_screen_of(o + Vector2i(7, 3)), _screen_of(o + Vector2i(9, 4)))
	check(_count(Simulation.Tile.SHOPS, o + Vector2i(7, 3), o + Vector2i(9, 4)) == 6, "zoning shops")
	await _pick_item("zones", "industry")
	await _drag(_screen_of(o + Vector2i(7, 6)), _screen_of(o + Vector2i(12, 7)))
	check(_count(Simulation.Tile.INDUSTRY, o + Vector2i(7, 6), o + Vector2i(12, 7)) == 12, "zoning industry")
	# Homes out of reach of any road: they should get a "no road" icon.
	await _pick_item("zones", "homes_0")
	await _drag(_screen_of(o + Vector2i(10, 10)), _screen_of(o + Vector2i(12, 11)))
	await _frames(3)
	var alerts: int = world.get("_alert_count")
	check(alerts > 0, "zones without a road or power get warning icons (%d)" % alerts)
	await _look_at(o + Vector2i(7, 6), PLAY_DISTANCE, -40.0, 42.0, _corners())
	await _move(Vector2(1, 1))
	await _shot("p04_zoned_plots_no_power")

	# Power and water.
	await _pick_item("power", "coal")
	check(_tool() == POWER, "Power > Coal picks the power tool")
	money = sim.money
	await _click_at(_screen_of(o + Vector2i(13, 6)))
	check(sim.tiles[(o.y + 6) * sim.w + o.x + 13] == Simulation.Tile.POWER_PLANT, "clicking places a coal plant")
	check(money - sim.money >= 3000, "the coal plant cost £3,000 or more")
	await _pick_item("utilities", "water_tower")
	await _click_at(_screen_of(o + Vector2i(5, 2)))
	check(sim.tiles[(o.y + 2) * sim.w + o.x + 5] == Simulation.Tile.WATER_TOWER, "clicking places a water tower")


func _hud_blocks_the_map() -> void:
	# Clicks and drags on the interface must never build on the map under it.
	await _pick_item("zones", "homes_0")
	var before := _tiles_hash()
	var money := sim.money
	var panels: Array[Control] = [hud.get("_info_panel"), hud.build_panel, hud.get("_overlay_panel"),
		hud.get("_status_island"), hud.get("_left_island")]
	for c: Control in panels:
		var r := c.get_global_rect()
		var spot := r.position + Vector2(r.size.x * 0.5, 6.0)     # the panel's own glass, not a button
		var h := _tiles_hash()
		await _click_at(spot)
		await _drag(spot, spot + Vector2(0, 4))
		if _tiles_hash() != h:
			print("[play]   built through %s at %s (over %s, hover %s)" % [c.name, spot,
				get_viewport().gui_get_hovered_control(), game.get("hover")])
	if hud.city_panel.visible:
		await _click(hud.get("_city_button"))
	check(_tiles_hash() == before and sim.money == money, "clicking and dragging on HUD panels builds nothing")
	# The hover box doesn't follow the mouse over the interface.
	var o := _origin
	await _move(_screen_of(o + Vector2i(8, 8)))
	var on_map: Vector2i = game.get("hover")
	await _move(hud.build_panel.get_global_rect().get_center())
	var over_hud: Vector2i = game.get("hover")
	check(over_hud == on_map or over_hud == Vector2i(-1, -1),
		"moving onto the Build menu doesn't hover the map under it (%s, %s)" % [on_map, over_hud])
	# And with the mouse resting on a panel, moving the camera mustn't pick tiles under the panel.
	await _hold_key(KEY_W, 0.3)
	await _wait(0.3)
	over_hud = game.get("hover")
	check(over_hud == on_map or over_hud == Vector2i(-1, -1),
		"panning while the mouse is on a panel doesn't hover the map under it (%s)" % over_hud)


func _wheel_over_panels() -> void:
	# The mouse wheel over a panel scrolls the panel (if it scrolls) and never zooms the map.
	var dist := rig.distance
	await _click(_rail("all"))
	var scroll: ScrollContainer = hud.get("_scroll")
	scroll.scroll_vertical = 0
	await _frames(2)
	await _wheel(scroll.get_global_rect().get_center(), false, 3)
	await _wait(0.3)
	check(scroll.scroll_vertical > 0, "the wheel scrolls the Build list (to %d)" % scroll.scroll_vertical)
	await _wheel(scroll.get_global_rect().get_center(), true, 6)
	await _wait(0.3)
	check(absf(rig.distance - dist) < 0.5, "the wheel over the Build list doesn't zoom (%.0f -> %.0f)" % [dist, rig.distance])
	# Up past the top of the list as well (nothing left to scroll).
	await _wheel(scroll.get_global_rect().get_center(), true, 3)
	check(absf(rig.distance - dist) < 0.5, "the wheel at the top of the Build list doesn't zoom")
	# The City panel.
	await _click(hud.get("_status_island"))
	check(hud.city_panel.visible, "clicking the status strip opens the City panel")
	var city_scroll: ScrollContainer = hud.get("_city_scroll")
	await _wheel(city_scroll.get_global_rect().get_center(), false, 3)
	await _wheel(city_scroll.get_global_rect().get_center(), true, 3)
	await _wait(0.3)
	check(absf(rig.distance - dist) < 0.5, "the wheel over the City panel doesn't zoom")
	await _wheel(hud.get("_status_island").get_global_rect().get_center(), false, 2)
	check(absf(rig.distance - dist) < 0.5, "the wheel over the status strip doesn't zoom")
	await _click(hud.get("_city_button"))
	# Help.
	await _key(KEY_H)
	await _wait(0.2)
	check(hud.help_panel.visible, "H opens the help")
	var help_scroll: ScrollContainer = hud.get("_help_scroll")
	await _wheel(help_scroll.get_global_rect().get_center(), false, 3)
	await _wait(0.3)
	check(absf(rig.distance - dist) < 0.5, "the wheel over the help doesn't zoom")
	await _shot("p05_help")
	# The guide: topics down the left, one page at a time, Next and Back, Esc closes.
	var topics: Dictionary = hud.get("_guide_topics")
	check(topics.size() >= 12, "the guide has its topics down the left (%d)" % topics.size())
	await _click(topics["money"])
	await _wait(0.2)
	check(hud.help_page() == "money" and (topics["money"] as Button).button_pressed,
		"clicking a topic shows its page")
	var page_text := _texts(hud.get("_guide_box"))
	check(page_text.contains("Loans") and page_text.contains("Taxes"),
		"the Money page has its sections")
	var next_button: Button = null
	for b: Node in (hud.get("_guide_box") as Node).find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("Next:"):
			next_button = b
	check(next_button != null, "a page has a Next button")
	if next_button:
		await _click(next_button)
		await _wait(0.2)
		check(hud.help_page() == "utilities", "Next goes to the next topic (%s)" % hud.help_page())
	await _key(KEY_ESCAPE)
	await _wait(0.3)
	check(not hud.help_panel.visible, "Esc closes the guide")
	await _key(KEY_H)
	await _wait(0.2)
	check(hud.help_panel.visible and hud.help_page() == "utilities", "H opens the guide where you left off")
	await _key(KEY_H)
	await _wait(0.3)
	check(not hud.help_panel.visible, "H closes the help")
	# The info card and the map views.
	await _wheel(hud.get("_info_panel").get_global_rect().get_center(), false, 2)
	await _wheel(hud.get("_overlay_panel").get_global_rect().get_center(), false, 2)
	check(absf(rig.distance - dist) < 0.5, "the wheel over the info card and map views doesn't zoom")


func _early_town() -> void:
	# Run the clock at Fast for a year, as a player does, and look at the young town.
	var o := _origin
	var speeds: Dictionary = hud.speed_buttons
	await _click(speeds[0])
	check(int(game.get("speed")) == 0, "the pause button pauses")
	await _click(speeds[Settings.FAST_SPEED])
	check(int(game.get("speed")) == Settings.FAST_SPEED, "the fast button runs the clock fast")
	await _look_at(o + Vector2i(7, 6), PLAY_DISTANCE)
	await _move(Vector2(-10, -10))
	var month := sim.month
	var t0 := Time.get_ticks_msec()
	var drawn0 := Engine.get_frames_drawn()
	var frames := 0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	while sim.month < month + 14 and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		frames += 1
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("[play] %d months at Fast took %.1f s: %d frames (%.1f a second, the slowest %.0f ms), %d of them drawn by the window" % [
		sim.month - month, secs, frames, frames / secs, worst, Engine.get_frames_drawn() - drawn0])
	check(sim.month >= month + 12, "a year passes at Fast (%d months)" % (sim.month - month))
	check(sim.population > 0, "people move in (%d)" % sim.population)
	var grown := 0
	for i: int in sim.w * sim.h:
		if sim.is_zone(sim.tiles[i]) and sim.levels[i] > 0:
			grown += 1
	check(grown > 0, "plots get built on (%d)" % grown)
	await _click(speeds[0])
	await _shot("p06_early_town")
	await _look_at(o + Vector2i(5, 5), 300.0, -35.0, 38.0)
	await _shot("p07_early_town_close")
	game.set("time_of_day", 0.95)
	await _look_at(o + Vector2i(7, 6), PLAY_DISTANCE)
	await _shot("p08_early_town_night")
	game.set("time_of_day", 0.55)
	# Hover a built plot: the card says what's there.
	var built := Vector2i(-1, -1)
	for y: int in range(o.y, o.y + 12):
		for x: int in range(o.x, o.x + 14):
			var i := y * sim.w + x
			if sim.tiles[i] == Simulation.Tile.HOMES and sim.levels[i] > 0:
				built = Vector2i(x, y)
	if built.x >= 0:
		await _look_at(built, PLAY_DISTANCE, -40.0, 42.0, [built])
		await _move(_screen_of(built))
		await _move(_screen_of(built) + Vector2(1, 1))
		var title: Label = hud.get("_info_title")
		check(game.get("hover") == built, "the mouse over a plot hovers that plot (%s, %s)" % [game.get("hover"), built])
		check(title.visible and title.text.begins_with("Homes"), "the hover card names it: \"%s\"" % title.text)
		check(world.hover_box.visible, "the hover box shows")
		await _shot("p09_hover")
	# Real frames, as the player sees them, at this early town (if the window is drawing).
	await _speed_here("early town")


func _speed_here(label: String) -> void:
	game.call("_set_speed", 1)
	var drawn0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	var frames := 0
	while Time.get_ticks_usec() - t0 < 3_000_000:
		await get_tree().process_frame
		frames += 1
	var secs := (Time.get_ticks_usec() - t0) / 1_000_000.0
	var drawn := Engine.get_frames_drawn() - drawn0
	print("[play] %s, playing at normal speed: %.1f frames a second (%d drawn by the window)" % [
		label, frames / secs, drawn])
	game.call("_set_speed", 0)
	await DevShots.perf_table(self, label, world, hud, traffic)


func _overlays_and_city_panel() -> void:
	var buttons: Dictionary = hud.overlay_buttons
	for kind: int in buttons:
		await _click(buttons[kind])
		check(world.overlay == kind and int(hud.get("_overlay_kind")) == kind, "map view button %d (%s)" % [kind, Hud.OVERLAY_NAMES[kind]])
		if kind == WorldView.Overlay.GROWTH:
			await _shot("p10_overlay_growth")
	await _click(buttons[0])
	check(world.overlay == WorldView.Overlay.NONE, "back to the normal view")
	# The advisors' ticker: clicking a tip shows its map view, clicking again goes back.
	var tips: Array = hud.get("_advice_tips")
	var ticker: Button = hud.get("_ticker")
	if not tips.is_empty() and int(tips[0]["overlay"]) > 0 and ticker.is_visible_in_tree():
		var kind: int = tips[0]["overlay"]
		await _click(ticker)
		check(world.overlay == kind, "clicking the advisor's tip shows the %s view" % Hud.OVERLAY_NAMES[kind])
		await _click(ticker)
		check(world.overlay == WorldView.Overlay.NONE, "clicking the tip again goes back to the normal view")
	# Nothing piles up when the town is redrawn again and again (or the views switched).
	await _frames(5)
	var nodes0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var objects0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	for k: int in 40:
		world.refresh_all()
		game.call("_set_overlay", k % WorldView.Overlay.size())
		await _frames(1)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	await _frames(5)
	var grew_nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - nodes0
	var grew_objects := Performance.get_monitor(Performance.OBJECT_COUNT) - objects0
	var grew_mb := (Performance.get_monitor(Performance.MEMORY_STATIC) - mem0) / 1048576.0
	print("[play] after 40 redraws: %+d nodes, %+d objects, %+.1f MB" % [grew_nodes, grew_objects, grew_mb])
	check(grew_nodes < 20 and grew_objects < 200 and grew_mb < 8.0, "40 redraws of the town leak nothing")
	# Taxes in the City panel.
	await _click(hud.get("_status_island"))
	var plus := _find_button(hud.city_panel, "+")
	var minus := _find_button(hud.city_panel, "–")
	var tax := sim.tax_rate
	await _click(plus)
	check(is_equal_approx(sim.tax_rate, tax + 0.01), "City panel: + raises taxes (%.2f -> %.2f)" % [tax, sim.tax_rate])
	await _click(minus)
	await _click(minus)
	check(is_equal_approx(sim.tax_rate, tax - 0.01), "City panel: – lowers taxes")
	await _click(plus)
	await _shot("p11_city_panel")
	await _click(hud.get("_city_button"))
	await _wait(0.2)
	check(not hud.city_panel.visible, "the City panel closes")


func _save_and_load() -> void:
	var o := _origin
	await _click(hud.get("_menu_button"))
	var menu: PanelContainer = hud.get("_menu_panel")
	check(menu.visible, "the ☰ button opens the game menu")
	await _shot("p12_menu")
	await _click(_find_button(menu, "Save"))
	check(FileAccess.file_exists(String(game.get("save_file"))), "Save writes the save file")
	var saved := JSON.stringify(sim.to_save())
	var money := sim.money
	# Bulldoze a corner of the town.
	await _click(hud.bulldoze_button)
	check(_tool() == BULLDOZE, "the Bulldoze button picks the bulldozer")
	await _look_at(o + Vector2i(3, 4), PLAY_DISTANCE, -40.0, 42.0, [o + Vector2i(0, 3), o + Vector2i(2, 4)])
	await _drag(_screen_of(o + Vector2i(0, 3)), _screen_of(o + Vector2i(2, 4)))
	check(_count(Simulation.Tile.EMPTY, o + Vector2i(0, 3), o + Vector2i(2, 4)) == 6, "bulldozing a box clears it")
	check(sim.money < money, "bulldozing costs money")
	await _click(hud.get("_menu_button"))
	await _click(_find_button(menu, "Load"))
	check(_count(Simulation.Tile.HOMES, o + Vector2i(0, 3), o + Vector2i(2, 4)) == 6, "Load brings the bulldozed homes back")
	check(JSON.stringify(sim.to_save()) == saved, "save then load gives back exactly the same city")
	# The save file itself loads (with the same reader as an old save).
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(game.get("save_file"))))
	check(typeof(data) == TYPE_DICTIONARY and int((data as Dictionary).get("version", 0)) == 4, "the save file is version 4")


func _keyboard_shortcuts() -> void:
	# Everything the help lists.
	var o := _origin
	var keys := [[KEY_1, ROAD], [KEY_2, HOMES], [KEY_3, SHOPS], [KEY_4, INDUSTRY], [KEY_5, BULLDOZE],
		[KEY_B, BULLDOZE], [KEY_6, POWER], [KEY_7, UTILITY], [KEY_8, PARK], [KEY_9, GRID], [KEY_0, SERVICE],
		[KEY_MINUS, LEISURE], [KEY_EQUAL, TRANSPORT], [KEY_Z, DISTRICT]]
	for pair: Array in keys:
		var code: Key = pair[0]
		await _key(code)
		check(_tool() == int(pair[1]), "key %s picks tool %d" % [OS.get_keycode_string(code), int(pair[1])])
	check(world.overlay == WorldView.Overlay.DISTRICTS, "Z also shows the Districts view")
	await _key(KEY_2)
	check(world.overlay == WorldView.Overlay.NONE, "leaving the District tool hides the Districts view again")
	var density: int = game.get("current_density")
	await _key(KEY_TAB)
	check(int(game.get("current_density")) == (density + 1) % 3, "Tab changes the density")
	await _key(KEY_6)
	var choice: Dictionary = game.get("_choice")
	var item: int = choice.get(POWER, 0)
	await _key(KEY_TAB)
	check(int(choice.get(POWER, 0)) == (item + 1) % 6, "Tab picks the next power building")
	var open: bool = hud.get("_build_open")
	await _key(KEY_M)
	check(bool(hud.get("_build_open")) != open, "M hides or shows the Build menu")
	await _key(KEY_M)
	game.call("_set_speed", 0)
	await _key(KEY_SPACE)
	check(int(game.get("speed")) == 1, "Space plays")
	await _key(KEY_SPACE)
	check(int(game.get("speed")) == 0, "Space pauses")
	await _key(KEY_F)
	check(int(game.get("speed")) == Settings.FAST_SPEED, "F runs fast")
	await _key(KEY_SPACE)
	var ov := world.overlay
	await _key(KEY_O)
	check(world.overlay == (ov + 1) % WorldView.Overlay.size(), "O shows the next map view")
	await _key(KEY_O)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	var cars := traffic.enabled
	await _key(KEY_T)
	check(traffic.enabled != cars, "T turns the traffic off or on")
	await _key(KEY_T)
	# Esc cancels a drag: nothing is built on release.
	await _key(KEY_1)
	await _look_at(o + Vector2i(7, 6), PLAY_DISTANCE, -40.0, 42.0, _corners())
	var before := _tiles_hash()
	await _drag(_screen_of(o + Vector2i(0, 9)), _screen_of(o + Vector2i(5, 9)), MOUSE_BUTTON_LEFT, false)
	check(world.preview.multimesh.instance_count > 0, "a road drag shows its preview")
	await _key(KEY_ESCAPE)
	check(world.preview.multimesh.instance_count == 0, "Esc clears the preview")
	await _press(_screen_of(o + Vector2i(5, 9)), MOUSE_BUTTON_LEFT, false)
	await _frames(3)
	check(_tiles_hash() == before, "after Esc, letting go builds nothing")
	# Ctrl/Cmd + S and L.
	await _key(KEY_S, true)
	var saved := JSON.stringify(sim.to_save())
	await _key(KEY_8)
	await _click_at(_screen_of(o + Vector2i(1, 9)))
	check(sim.tiles[(o.y + 9) * sim.w + o.x + 1] == Simulation.Tile.PARK, "8 then a click lays a park")
	await _key(KEY_L, true)
	check(JSON.stringify(sim.to_save()) == saved, "Cmd+S then Cmd+L restores the city")


func _coast_and_slopes() -> void:
	# The tile under the mouse must be the tile drawn there, on the curved coast
	# and on hills: send the mouse to the middle of each tile as drawn and see
	# which tile the game picks.
	var water: PackedByteArray = game.get("water")
	var slope: PackedFloat32Array = game.get("slope")
	var coastal: Array[Vector2i] = []
	var steep: Array[Vector2i] = []
	for y: int in range(2, sim.h - 2):
		for x: int in range(2, sim.w - 2):
			var i := y * sim.w + x
			if water[i] == 0 and (water[i - 1] == 1 or water[i + 1] == 1 or water[i - sim.w] == 1 or water[i + sim.w] == 1):
				coastal.append(Vector2i(x, y))
			elif water[i] == 0 and slope[i] > 6.0:
				steep.append(Vector2i(x, y))
	var wrong: Array[String] = []
	var tried := 0
	for group: Array[Vector2i] in [coastal, steep]:
		var step := maxi(1, group.size() / 40)
		for k: int in range(0, group.size(), step):
			var t: Vector2i = group[k]
			await _look_at(t, PLAY_DISTANCE, -40.0 + 90.0 * (k % 4), 30.0 + 10.0 * (k % 3))
			var pos := _screen_of(t)
			var picked: Vector2i = world.pick_tile(rig.camera.project_ray_origin(pos), rig.camera.project_ray_normal(pos))
			tried += 1
			if picked != t:
				wrong.append("%s->%s" % [t, picked])
			# Its middle is dry land, where the game says it's land.
			var c := world.tile_centre(t)
			if world.height_at(c.x, c.y) <= 0.0:
				wrong.append("%s under water" % t)
	check(wrong.is_empty(), "picking agrees with the drawing on %d coastal and hillside tiles %s" % [tried, ", ".join(wrong)])
	# Build on a coastal tile with the mouse: that tile gets it.
	var spot := Vector2i(-1, -1)
	for t: Vector2i in coastal:
		var i := t.y * sim.w + t.x
		if sim.tiles[i] == Simulation.Tile.EMPTY and slope[i] < Settings.MAX_SLOPE_M:
			spot = t
			break
	if spot.x >= 0:
		await _key(KEY_8)
		await _look_at(spot, 400.0, -60.0, 35.0, [spot])
		await _move(_screen_of(spot))
		await _click_at(_screen_of(spot) + Vector2(0, 1))
		check(sim.tiles[spot.y * sim.w + spot.x] == Simulation.Tile.PARK, "a click on coastal tile %s builds on that tile" % spot)
		await _shot("p13_coast_park")
	# Nothing the town planted stands in the sea (except on harbour and marina tiles).
	var wet := 0
	var total := 0
	for node: MultiMeshInstance3D in [world.props, world.city_trunks, world.city_crowns, world.paving, world.parked_bodies]:
		for piece: Node in node.get_children():
			var mm := (piece as MultiMeshInstance3D).multimesh
			for n: int in mm.instance_count:
				var p := mm.get_instance_transform(n).origin
				total += 1
				var tx := floori(p.x / world.cell)
				var tz := floori(p.z / world.cell)
				if tx < 0 or tz < 0 or tx >= sim.w or tz >= sim.h:
					continue
				var t: int = sim.tiles[tz * sim.w + tx]
				if t == Simulation.Tile.HARBOUR or t == Simulation.Tile.MARINA:
					continue
				if world.coast_at(p.x, p.z) < WorldView.SHORE_LEVEL:
					wet += 1
	check(wet == 0, "none of %d planted things stand in the sea (%d do)" % [total, wet])


# ----------------------------------------------------------------- woodland

func _woodland() -> void:
	# Plant a strip of woodland between the works and the homes with no road, with
	# the Build menu and a drag; then its hover card, no warnings, cleaner air and
	# better land, bulldozing, saving and loading, and a big forest's cost.
	var o := _origin
	var wood := Simulation.Tile.WOODLAND
	check(Simulation.Tile.HARBOUR == 28 and wood == 29 and Simulation.Tile.OFFICES == 30 and Simulation.LAST_TILE > wood,
		"woodland and the tiles added since are new numbers on the end (old saves' tiles keep their numbers)")
	game.call("_set_speed", 0)
	var a := o + Vector2i(7, 8)
	var b := o + Vector2i(12, 9)
	var home := o + Vector2i(11, 10)
	var hi := home.y * sim.w + home.x
	await _look_at(o + Vector2i(9, 9), PLAY_DISTANCE * 0.8, -40.0, 42.0, [a, b, home])
	var free := _count(Simulation.Tile.EMPTY, a, b)
	var smoke0 := sim.pollution_at(hi)
	var value0: float = sim.land_value_map()[hi]
	var trees0: int = world.planted_total()
	await _pick_item("leisure", "woodland")
	check(_tool() == LEISURE and int(game.call("_target_tile")) == wood, "Build menu > Leisure > Woodland picks woodland")
	var rows: Dictionary = hud.get("_rows")
	var row_name: Label = (rows["woodland"] as Dictionary)["name"]
	check(String((rows["woodland"] as Dictionary)["cat"]) == "leisure" and row_name.text == "Woodland",
		"the Woodland row is in the Leisure list")
	var expected := 0
	for p: Vector2i in game.call("_box", a, b):
		if sim.tiles[p.y * sim.w + p.x] == Simulation.Tile.EMPTY:
			expected += int(game.call("_tool_cost", p))
	var money := sim.money
	await _drag(_screen_of(a), _screen_of(b), MOUSE_BUTTON_LEFT, false)
	var info: Label = hud.info_label
	check(world.preview.multimesh.instance_count == 12 and info.text.begins_with("Woodland") and info.text.contains("£"),
		"dragging woodland previews 12 tiles with the cost: \"%s\"" % info.text)
	await _press(_screen_of(b), MOUSE_BUTTON_LEFT, false)
	await _frames(3)
	check(_count(wood, a, b) == free and free >= 10, "woodland planted on the %d open tiles dragged over" % free)
	check(money - sim.money == expected and expected > 0 and expected <= free * 30,
		"it cost %s (about £20 a tile; %s expected)" % [Hud.money_text(money - sim.money), Hud.money_text(expected)])
	var trees1: int = world.planted_total()
	check(trees1 > trees0, "its trees appear straight away (%d tree parts)" % (trees1 - trees0))
	# No warnings, never "not working", no upkeep.
	var warn_image: Image = world.get("warn_image")
	var warned := 0
	var idle := 0
	for p: Vector2i in game.call("_box", a, b):
		var i := p.y * sim.w + p.x
		if sim.tiles[i] != wood:
			continue
		if warn_image.get_pixelv(p) != Color(0, 0, 0, 0):
			warned += 1
		if not sim.building_working(i):
			idle += 1
	check(warned == 0 and idle == 0, "woodland gets no warning icons and always counts as working (%d, %d)" % [warned, idle])
	var survey: Dictionary = Advisors._survey(sim)
	var broken: Array = survey["broken"]
	check(not broken.any(func(k: int) -> bool: return sim.tiles[k] == wood), "the advisors don't count woodland as not working")
	check(int(sim.info(wood).get("upkeep", 0)) == 0, "woodland has no upkeep")
	# Cleaner air and better land for the homes beside it.
	var smoke1 := sim.pollution_at(hi)
	var value1: float = sim.land_value_map()[hi]
	check(smoke1 < smoke0, "the air beside it is cleaner (pollution %.2f -> %.2f)" % [smoke0, smoke1])
	check(value1 > value0, "land beside it is worth more (%.3f -> %.3f)" % [value0, value1])
	# The hover card.
	var spot := o + Vector2i(9, 8)
	await _move(_screen_of(spot))
	await _move(_screen_of(spot) + Vector2(1, 1))
	var title: Label = hud.get("_info_title")
	check(game.get("hover") == spot and title.text.begins_with("Woodland"), "the hover card says \"%s\"" % title.text)
	check(not title.text.contains("road") and not title.text.contains("not working"), "...and nothing about roads")
	await _move(Vector2(1, 1))
	await _shot("p15_woodland")
	game.call("_set_overlay", WorldView.Overlay.POLLUTION)
	await _shot("p16_woodland_pollution")
	game.call("_set_overlay", WorldView.Overlay.NONE)
	# Save, bulldoze a row, load: it all comes back.
	await _key(KEY_S, true)
	var saved := JSON.stringify(sim.to_save())
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(game.get("save_file"))))
	var saved_tiles: Array = (data as Dictionary).get("tiles", [])
	check(int(saved_tiles[spot.y * sim.w + spot.x]) == wood, "the save file holds the woodland")
	await _click(hud.bulldoze_button)
	await _drag(_screen_of(o + Vector2i(7, 9)), _screen_of(o + Vector2i(12, 9)))
	await _frames(3)
	check(_count(wood, o + Vector2i(7, 9), o + Vector2i(12, 9)) == 0, "bulldozing clears woodland")
	check(world.planted_total() < trees1, "...and its trees go (%d -> %d)" % [trees1, world.planted_total()])
	await _key(KEY_L, true)
	await _frames(3)
	check(_count(wood, a, b) == free and JSON.stringify(sim.to_save()) == saved, "save then load brings the woodland back")
	check(world.planted_total() == trees1, "...with exactly the same trees (%d)" % world.planted_total())
	# A save from before woodland (no tile 29 anywhere) still loads.
	var old := sim.to_save()
	var old_tiles: Array = old["tiles"]
	for k: int in old_tiles.size():
		if int(old_tiles[k]) == wood:
			old_tiles[k] = Simulation.Tile.EMPTY
	old["version"] = 3
	old["map"] = game.get("map_name")
	old["width"] = sim.w
	old["height"] = sim.h
	var path := "user://playtest_pre_woodland.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	game.call("_load_game", path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await _frames(3)
	check(sim.count_of(wood) == 0 and world.planted_total() == trees0, "a save from before woodland loads, with none")
	await _key(KEY_L, true)
	await _frames(3)
	await _big_forest()


func _big_forest() -> void:
	# What a 20 x 20 forest costs to draw: tree parts and the time to plant it.
	var water: PackedByteArray = game.get("water")
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y: int in range(2, sim.h - 22, 2):
		for x: int in range(2, sim.w - 22, 2):
			var ok := true
			for dy: int in 20:
				for dx: int in 20:
					var i := (y + dy) * sim.w + x + dx
					if water[i] == 1 or sim.tiles[i] != Simulation.Tile.EMPTY:
						ok = false
						break
				if not ok:
					break
			var d := (Vector2i(x, y) - _origin).length_squared()
			if ok and d < best_d:
				best = Vector2i(x, y)
				best_d = d
	if best.x < 0:
		check(false, "found open land for a 20 x 20 forest")
		return
	var centre := best + Vector2i(10, 10)
	var ci := centre.y * sim.w + centre.x
	var value0: float = sim.land_value_map()[ci]
	var smoke0 := sim.pollution_at(ci)
	var parts0: int = world.planted_total()
	print("[play] woods before the 20 x 20 forest: %s" % world.woods_report())
	await _look_at(centre, 1400.0, -40.0, 40.0)
	await _speed_here("before a 20 x 20 forest")
	var money := sim.money
	sim.money = 100000
	game.call("_choose_item", "woodland")
	game.set("drag_start", best)
	game.set("drag_plan", game.call("_plan_tiles", best, best + Vector2i(19, 19)))
	var t0 := Time.get_ticks_usec()
	game.call("_finish_drag")
	var sim_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	world.refresh_ground(true)
	var ground_ms := (Time.get_ticks_usec() - t0) / 1000.0
	game.set("_layout_seen", sim.layout_version)
	var planted := _count(Simulation.Tile.WOODLAND, best, best + Vector2i(19, 19))
	print("[play] planted %d woodland tiles at %s: the build %.0f ms, redrawing the ground %.0f ms (of which the trees %.0f ms); %s" % [
		planted, best, sim_ms, ground_ms, float(world.get("planted_refresh_ms")), world.woods_report()])
	check(planted >= 350 and world.planted_total() > parts0, "a 20 x 20 forest is planted (%d tiles)" % planted)
	# However big the forest, the land value it adds is capped (and it's clean air here already).
	var gain: float = sim.land_value_map()[ci] - value0
	print("[play] land value in the middle of the forest %.3f -> %.3f, pollution %.2f -> %.2f" % [value0,
		sim.land_value_map()[ci], smoke0, sim.pollution_at(ci)])
	check(gain <= Settings.WOODLAND_VALUE_MAX + 0.001 + Settings.POLLUTION_VALUE_EFFECT * smoke0,
		"a big forest adds at most %.2f land value (%.3f)" % [Settings.WOODLAND_VALUE_MAX, gain])
	await _frames(5)
	await _speed_here("with a 20 x 20 forest in view")
	# Bulldoze it again.
	game.call("_choose_item", "bulldoze")
	game.set("drag_start", best)
	game.set("drag_plan", game.call("_plan_tiles", best, best + Vector2i(19, 19)))
	game.call("_finish_drag")
	world.refresh_ground(true)
	game.set("_layout_seen", sim.layout_version)
	check(world.planted_total() == parts0, "bulldozing the forest takes all its trees away (%d)" % world.planted_total())
	sim.money = money
	game.call("_refresh_hud")


# ------------------------------------------------------ difficulty and loans

func _built_count() -> int:
	var built := 0
	for i: int in sim.w * sim.h:
		if sim.tiles[i] != Simulation.Tile.EMPTY:
			built += 1
	return built


func _launch_dialog() -> void:
	# The game opens on the New city dialog, paused, with Normal picked.
	check(hud.is_modal() and hud.new_city_panel.visible, "the game opens with the New city dialog")
	check(int(game.get("speed")) == 0, "the clock is paused behind the dialog")
	check(hud.new_city_level() == Settings.DEFAULT_DIFFICULTY, "Normal is picked to start with")
	check(not (hud.get("_new_warning") as Control).visible, "no \"clears everything\" warning on a fresh game")
	await _shot("p00_new_city_dialog")
	# Keys pick a card, and nothing reaches the game behind it (tools, camera).
	var tool_before := _tool()
	var target := rig.target
	await _key(KEY_3)
	check(hud.new_city_level() == 2, "3 picks Hard")
	await _key(KEY_LEFT)
	check(hud.new_city_level() == 1, "left arrow picks the card before")
	await _key(KEY_1)
	check(hud.new_city_level() == 0, "1 picks Easy")
	await _hold_key(KEY_RIGHT, 0.3)
	check(hud.new_city_level() == 1, "right arrow picks the next card")
	check(_tool() == tool_before and rig.target.distance_to(target) < 1.0,
		"keys in the dialog don't pick tools or move the camera")
	# A click on a card picks it; a click on the dimmed town around does nothing.
	var cards: Array[PanelContainer] = hud.new_city_cards
	await _click(cards[2])
	check(hud.new_city_level() == 2, "clicking the Hard card picks it")
	await _click(cards[1])
	check(hud.new_city_level() == 1 and hud.new_city_start.text.ends_with("Normal"), "clicking Normal picks it")
	await _click_at(Vector2(30, get_viewport().get_visible_rect().size.y * 0.5))
	check(hud.is_modal() and _built_count() == 0, "clicking the town behind the dialog does nothing")
	await _key(KEY_ENTER)
	await _wait(0.2)
	check(not hud.is_modal(), "Enter starts the city")
	check(sim.difficulty == 1 and sim.money == Simulation.start_money(1), "...on Normal, with %s" % Hud.money_text(sim.money))
	check(int(game.get("speed")) == 1, "the clock runs once the city has started")
	game.call("_set_speed", 0)


func _open_new_city_from_menu() -> void:
	await _click(hud.get("_menu_button"))
	var menu: PanelContainer = hud.get("_menu_panel")
	await _click(_find_button(menu, "New city"))
	await _wait(0.2)


func _one_month() -> Dictionary:
	# Run the real clock (at Fast) until the next month, then pause. Returns the
	# money and loan just before that month's bills.
	var month := sim.month
	var before := {}
	game.call("_set_speed", Settings.FAST_SPEED)
	var t0 := Time.get_ticks_msec()
	while sim.month == month and Time.get_ticks_msec() - t0 < 15000:
		before = {"money": sim.money, "debt": sim.debt, "peak": sim.debt_peak}
		await get_tree().process_frame
	game.call("_set_speed", 0)
	await _frames(2)
	return before


func _new_city() -> void:
	# New city from the menu asks for a difficulty; Esc keeps the city.
	var built := _built_count()
	game.call("_set_speed", 1)
	await _open_new_city_from_menu()
	check(hud.is_modal(), "New city in the menu opens the dialog")
	check((hud.get("_new_warning") as Control).visible, "...warning that it clears the city")
	check(int(game.get("speed")) == 0, "...and pauses the clock")
	var money := sim.money          # (read once paused: a month may tick while the menu opens)
	await _key(KEY_ESCAPE)
	await _wait(0.2)
	check(not hud.is_modal() and _built_count() == built and sim.money == money,
		"Esc in the dialog keeps the city as it was")
	check(int(game.get("speed")) == 1, "...and the clock runs again")
	game.call("_set_speed", 0)
	# Each level: starting money, and upkeep x0.8 / x1 / x1.25 in a real month.
	var o := _origin
	var coal_upkeep: int = Settings.BUILDINGS["coal"]["upkeep"]
	for level: int in [0, 2, 1]:
		await _open_new_city_from_menu()
		await _click(hud.new_city_cards[level])
		await _click(hud.new_city_start)
		await _wait(0.2)
		var info: Dictionary = Settings.DIFFICULTIES[level]
		var level_name: String = info["name"]
		check(not hud.is_modal() and _built_count() == 0 and sim.population == 0, "%s: New city clears the map" % level_name)
		check(sim.difficulty == level and sim.money == int(info["money"]) and sim.debt == 0,
			"%s: starts with %s" % [level_name, Hud.money_text(sim.money)])
		game.call("_set_speed", 0)
		await _look_at(o + Vector2i(7, 6), PLAY_DISTANCE, -40.0, 42.0, _corners())
		await _pick_item("power", "coal")
		await _click_at(_screen_of(o + Vector2i(7, 6)))
		check(sim.count_of(Simulation.Tile.POWER_PLANT) == 1, "%s: a coal plant is built" % level_name)
		var before := await _one_month()
		var scale: float = info["upkeep"]
		var want := roundi(coal_upkeep * scale)
		check(sim.last_upkeep == want, "%s: a month's upkeep for one coal plant is %s (x%.2f; got %s)" % [
			level_name, Hud.money_text(want), scale, Hud.money_text(sim.last_upkeep)])
		check(sim.money == int(before["money"]) + sim.last_income - sim.last_upkeep - sim.last_loan,
			"%s: the month's bills come off the money" % level_name)


func _loans() -> void:
	# On Normal (from _new_city): borrow, the limit, repay, monthly payments,
	# running out of money, the advisors, and saving and loading.
	var limit := sim.loan_limit()
	var rate := sim.loan_rate()
	await _click(hud.get("_status_island"))
	await _wait(0.2)
	var scroll: ScrollContainer = hud.get("_city_scroll")
	var b5: Button = hud.borrow_buttons[0]
	var b20: Button = hud.borrow_buttons[1]
	scroll.ensure_control_visible(hud.repay_all_button)
	await _frames(3)
	var owed: Label = hud.get("_debt_label")
	check(owed.text == "Nothing" and hud.repay_button.disabled and hud.repay_all_button.disabled,
		"Loans: nothing owed, so Repay is greyed out")
	check(not b5.disabled and not b20.disabled, "Loans: both Borrow buttons work")
	var money := sim.money
	await _click(b20)
	check(sim.debt == 20000 and sim.money == money + 20000, "Borrow £20,000 adds it to the money and what's owed")
	check(owed.text == "£20,000", "the City panel shows £20,000 owed")
	while not b20.disabled and sim.debt < limit:
		await _click(b20)
	check(sim.debt == limit and b20.disabled and b5.disabled, "at the %s limit both Borrow buttons are greyed out" % Hud.money_text(limit))
	check(b5.tooltip_text.contains("most allowed"), "...and say why: \"%s\"" % b5.tooltip_text)
	money = sim.money
	await _click(b5)
	check(sim.debt == limit and sim.money == money, "clicking a greyed-out Borrow does nothing")
	await _click(hud.repay_button)
	check(sim.debt == limit - Settings.REPAY_STEP and sim.money == money - Settings.REPAY_STEP,
		"Repay £5,000 pays £5,000 back")
	check(not b5.disabled and b20.disabled, "after repaying £5,000, £5,000 can be borrowed again but not £20,000")
	scroll.ensure_control_visible(hud.repay_all_button)
	await _shot("p14_loans")
	# Monthly payments: interest on the balance plus 1/120 of the most owed.
	for m: int in 3:
		var before := await _one_month()
		var debt0: int = before["debt"]
		var peak: int = before["peak"]
		var interest := roundi(debt0 * rate / 12.0)
		var slice := mini(maxi(ceili(peak / float(Settings.LOAN_MONTHS)), Settings.LOAN_MIN_PAYMENT), debt0)
		check(sim.last_interest == interest and sim.last_loan == interest + slice and sim.debt == debt0 - slice,
			"month %d: paid %s interest + %s back (got %s + %s), owe %s" % [m + 1, Hud.money_text(interest),
			Hud.money_text(slice), Hud.money_text(sim.last_interest), Hud.money_text(sim.last_loan - sim.last_interest),
			Hud.money_text(sim.debt)])
		check(sim.money == int(before["money"]) + sim.last_income - sim.last_upkeep - sim.last_loan,
			"month %d: the payment comes off the money" % (m + 1))
	var loan_line: Label = hud.get("_loan_label")
	var net_line: Label = hud.get("_net_label")
	check(loan_line.text == Hud.money_text(sim.last_loan), "the budget shows last month's loan payments (%s)" % loan_line.text)
	check(net_line.text.begins_with(Hud.money_text(sim.last_balance())),
		"the status strip's last month includes them: \"%s\"" % net_line.text)
	var ids := _tip_ids()
	check("loan_heavy" in ids, "advisors warn when loan payments are a big share of taxes")
	# Out of money: the payment still happens, and nothing can be built.
	sim.money = -1000
	game.call("_refresh_hud")
	var before := await _one_month()
	check(sim.money == int(before["money"]) + sim.last_income - sim.last_upkeep - sim.last_loan and sim.last_loan > 0,
		"with no money the loan is still paid (money %s)" % Hud.money_text(sim.money))
	ids = _tip_ids()
	check("debt" in ids, "advisors: out of money")
	var why: String = game.call("_why_cant_build", _origin + Vector2i(2, 2))
	check(why.begins_with("Not enough money"), "nothing can be built with no money (\"%s\")" % why)
	check(hud.repay_button.disabled and hud.repay_all_button.disabled, "Repay is greyed out with no money")
	sim.money = 1000
	game.call("_refresh_hud")
	check("loan" in _tip_ids(), "advisors: short of money, take a loan")
	sim.money = 200000
	game.call("_refresh_hud")
	await _click(hud.repay_all_button)
	check(sim.debt == 0 and sim.debt_peak == 0 and hud.repay_all_button.disabled, "Repay all clears the loan")
	# Save and load keep the difficulty and the loan.
	await _click(b20)
	var saved_debt := sim.debt
	await _click(hud.get("_city_button"))
	await _key(KEY_S, true)
	var saved := JSON.stringify(sim.to_save())
	await _open_new_city_from_menu()
	await _key(KEY_3)
	await _key(KEY_ENTER)
	await _wait(0.2)
	check(sim.difficulty == 2 and sim.debt == 0, "a new Hard city")
	await _key(KEY_L, true)
	check(sim.difficulty == 1 and sim.debt == saved_debt and JSON.stringify(sim.to_save()) == saved,
		"loading brings back Normal and the %s owed" % Hud.money_text(saved_debt))


func _tip_ids() -> Array[String]:
	var ids: Array[String] = []
	for tip: Dictionary in Advisors.tips(sim):
		ids.append(String(tip["id"]))
	return ids


func _old_save() -> void:
	# A save from before difficulty and loans: no new fields, version 3. It loads
	# as Normal with nothing owed, and its money is left alone.
	var data := sim.to_save()
	data.erase("difficulty")
	data.erase("debt")
	data.erase("debt_peak")
	data["money"] = 12345
	data["version"] = 3
	data["map"] = game.get("map_name")
	data["width"] = sim.w
	data["height"] = sim.h
	var path := "user://playtest_old_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	# Start from a Hard city with a loan, so anything left over would show.
	await _open_new_city_from_menu()
	await _key(KEY_3)
	await _key(KEY_ENTER)
	await _wait(0.2)
	sim.borrow(5000)
	game.call("_load_game", path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(sim.money == 12345, "an old save keeps its money (%s)" % Hud.money_text(sim.money))
	check(sim.difficulty == Settings.DEFAULT_DIFFICULTY and sim.debt == 0 and sim.debt_peak == 0,
		"an old save loads as Normal with nothing owed")
	check(is_equal_approx(sim.upkeep_scale(), 1.0), "an old save's running costs are as before (x1)")
	var budget: Label = hud.get("_budget_caption")
	check(budget.text.ends_with("NORMAL"), "the City panel's budget says \"%s\"" % budget.text)
	# A city built on another map (Palo Alto's, before the map was Menlo Park) is refused.
	var other := sim.to_save()
	other["map"] = "Palo Alto"
	other["width"] = sim.w
	other["height"] = sim.h
	other["money"] = 999
	var other_path := "user://playtest_other_map.json"
	var fo := FileAccess.open(other_path, FileAccess.WRITE)
	fo.store_string(JSON.stringify(other))
	fo.close()
	var money_now: int = sim.money
	game.call("_load_game", other_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(other_path))
	var toast: Label = hud.get("message_label")
	check(sim.money == money_now and toast.text.contains("built on Palo Alto's map"),
		"a city from another map isn't loaded (%s)" % toast.text)


# ------------------------------------------------------------------ traffic

func _place(id: String, from: Vector2i, to: Vector2i = Vector2i(-1, -1)) -> void:
	# Exactly what a mouse drag from `from` to `to` does with this Build menu item
	# (for the bulk of a layout; the drags that matter are made with the mouse).
	game.call("_choose_item", id)
	game.set("drag_start", from)
	game.set("drag_plan", game.call("_plan_tiles", from, to if to.x >= 0 else from))
	game.call("_finish_drag")


func _fill_plots(from: Vector2i, to: Vector2i) -> void:
	# Every zone plot in the box built up (so the traffic is the same every run):
	# works and shops fully, homes to tenements (stage 3, 60 people), so there are
	# more jobs than workers and the one link road jams but two don't.
	for y: int in range(from.y, to.y + 1):
		for x: int in range(from.x, to.x + 1):
			var i := y * sim.w + x
			if sim.is_zone(sim.tiles[i]):
				sim.levels[i] = sim.max_level(i)
				if sim.tiles[i] == Simulation.Tile.HOMES:
					while sim.levels[i] > 1 and sim.stage(i) > 3:
						sim.levels[i] -= 1
	sim.set("_power_dirty", true)
	sim.set("_value_dirty", true)
	sim.set("_coverage_dirty", true)
	sim.set("_traffic_dirty", true)
	sim.recount()
	game.call("_refresh_hud")
	world.refresh_all()
	game.set("_layout_seen", sim.layout_version)


func _trips(p: Vector2i) -> float:
	return sim.traffic_at(p.y * sim.w + p.x)


func _road_trips(from: Vector2i, to: Vector2i) -> float:
	var total := 0.0
	for y: int in range(from.y, to.y + 1):
		for x: int in range(from.x, to.x + 1):
			total += _trips(Vector2i(x, y))
	return total


func _busiest(from: Vector2i, to: Vector2i) -> float:
	var most := 0.0
	for y: int in range(from.y, to.y + 1):
		for x: int in range(from.x, to.x + 1):
			most = maxf(most, _trips(Vector2i(x, y)))
	return most


func _town_state() -> int:
	# Everything the rules decide, except traffic.
	return hash([sim.tiles, sim.levels, sim.decline, sim.abandoned, sim.money, sim.population,
		sim.land_value_map(), sim.happiness, sim.demand, sim.pollution_map()])


func _find_crossing(min_run: int = 3) -> Array[Vector2i]:
	# A straight way across the water: [land tile, far land tile], each with
	# another land tile behind it, water all the way between (3 to
	# BRIDGE_MAX_TILES tiles); the one nearest the camera. [] if none.
	var water: PackedByteArray = game.get("water")
	var start := Vector2i(roundi(rig.target.x / world.cell), roundi(rig.target.z / world.cell))
	var best: Array[Vector2i] = []
	var best_d := 1 << 30
	for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		for y: int in range(2, sim.h - 2):
			for x: int in range(2, sim.w - 2):
				var a := Vector2i(x, y)
				if water[y * sim.w + x] == 1 or water[(y + step.y) * sim.w + x + step.x] == 0:
					continue
				var back := a - step
				if water[back.y * sim.w + back.x] == 1:
					continue
				var p := a + step
				var run := 0
				while p.x < sim.w - 2 and p.y < sim.h - 2 and water[p.y * sim.w + p.x] == 1:
					p += step
					run += 1
				var beyond := p + step
				if run < min_run or run > Settings.BRIDGE_MAX_TILES or p.x >= sim.w - 2 or p.y >= sim.h - 2 \
						or water[beyond.y * sim.w + beyond.x] == 1:
					continue
				var d := (a - start).length_squared() + run * run * 40
				if d < best_d:
					best_d = d
					best = [a, p]
	return best


func _bridges() -> void:
	# Bridges (Nov 2026): drag a road straight across the water, from shore to
	# shore, and the water part becomes a bridge (25 times the cost a tile); a
	# drag that stops in the water builds no bridge.
	var T := Simulation.Tile
	await _open_new_city_from_menu()
	await _key(KEY_1)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var ends := _find_crossing(Settings.GOLDEN_GATE_MIN_TILES)    # (long enough to become the Golden Gate)
	check(ends.size() == 2, "bridges: the map has water to bridge (%s)" % str(ends))
	if ends.size() < 2:
		return
	var a: Vector2i = ends[0]
	var b: Vector2i = ends[1]
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var run := (b - a).length() - 1.0
	sim.money = 500000
	await _pick_item("roads", "road")
	var mid := a + step * roundi(run * 0.5)
	await _look_at(mid, PLAY_DISTANCE * (0.6 + run / 30.0), -35.0, 45.0, [a, b])
	# Stop in the water: it says why, and no bridge.
	await _drag(_screen_of(a), _screen_of(mid), MOUSE_BUTTON_LEFT, false)
	var info: Label = hud.get("info_label")
	check(info.text.contains("reach land on both sides"), "bridges: a drag ending in the water says so (%s)" % info.text)
	await _press(_screen_of(mid), MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	var built := 0
	for k: int in range(1, int(run) + 1):
		var p := a + step * k
		if sim.tiles[p.y * sim.w + p.x] == T.ROAD:
			built += 1
	check(built == 0, "bridges: ...and builds no bridge")
	# Shore to shore: a bridge.
	var money0: int = sim.money
	await _drag(_screen_of(a), _screen_of(b))
	await _frames(2)
	built = 0
	for k: int in range(1, int(run) + 1):
		var p := a + step * k
		if sim.is_bridge(p.y * sim.w + p.x):
			built += 1
	var spent: int = money0 - sim.money
	check(built == int(run) and spent >= int(run) * Settings.ROAD_COSTS[0] * Settings.BRIDGE_COST_X,
		"bridges: shore to shore, %d tiles of bridge for %s" % [built, Hud.money_text(spent)])
	var on := a + step * roundi(run * 0.5)
	var on_i := on.y * sim.w + on.x
	var text := String(game.call("_tile_text", on_i))
	check(text.begins_with("Bridge") and sim.road_upkeep > 0.0, "bridges: its hover says Bridge (%s)" % text.get_slice("\n", 0))
	var deck: float = world.road_ground(world.tile_centre(on).x, world.tile_centre(on).y)
	check(deck >= 7.9, "bridges: the deck is %.1f m above the water" % deck)
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_refresh_hud")
	hud.call("set_build_open", false)
	await _look_at(mid, PLAY_DISTANCE * (0.35 + run / 60.0), -60.0, 28.0, [])
	await _shot("p57_bridge")
	var data := sim.to_save()
	sim.from_save(data)
	check(sim.is_bridge(on_i), "bridges: saved and loaded")

	# The Golden Gate: picked from Landmarks, it turns a bridge red, with towers.
	sim.population = 20000                       # (it's unlocked at 15,000)
	await _pick_item("landmarks", "golden_gate")
	await _move(_screen_of(a - step * 2))
	var info2: Label = hud.get("_info_action")
	check(info2.text.contains("Point at one of your bridges"), "golden gate: on land it says to point at a bridge (%s)" % info2.text)
	var money1: int = sim.money
	await _click_at(_screen_of(on))
	await _frames(2)
	check(sim.golden_gate.size() == int(run) and sim.money <= money1 - 60000 and sim.road_name(on_i) == "Golden Gate Bridge"
		and sim.tourism > 0.0, "golden gate: the whole %d-tile bridge becomes the Golden Gate, and tourists come (%.3f)" % [
		sim.golden_gate.size(), sim.tourism])
	sim.population = 20000
	check(sim.golden_gate_problem(on_i).contains("only build one"), "golden gate: only one")
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_select_tool", ROAD)
	game.call("_refresh_hud")
	hud.call("set_build_open", false)
	await _look_at(mid, PLAY_DISTANCE * (0.45 + run / 50.0), -55.0, 22.0, [])
	await _shot("p58_golden_gate")
	data = sim.to_save()
	sim.from_save(data)
	check(sim.golden_gate.size() == int(run), "golden gate: saved and loaded")

	# Alcatraz: out on the water, on its own rock.
	var water: PackedByteArray = game.get("water")
	var near_shore := -1
	var offshore := -1
	var best_d := 1 << 30
	for i: int in sim.w * sim.h:
		if water[i] == 0 or sim.tiles[i] != T.EMPTY:
			continue
		var p := Vector2i(i % sim.w, i / sim.w)
		var d := (p - mid).length_squared()
		if near_shore < 0 and sim.call("_within_land", i, 1):
			near_shore = i
		if not sim.call("_within_land", i, Settings.ALCATRAZ_OFFSHORE + 1) and d < best_d:
			best_d = d
			offshore = i
	check(offshore >= 0, "alcatraz: there's open water out in the Bay")
	if offshore < 0:
		return
	var rock := Vector2i(offshore % sim.w, offshore / sim.w)
	await _pick_item("landmarks", "alcatraz")
	hud.call("set_build_open", false)
	await _look_at(rock, PLAY_DISTANCE * 0.5, -40.0, 35.0, [])
	sim.population = 20000                       # (it's unlocked at 10,000)
	if near_shore >= 0:
		check(sim.can_build_here(T.ALCATRAZ, near_shore).contains("further out"),
			"alcatraz: too near the shore it says so (%s)" % sim.can_build_here(T.ALCATRAZ, near_shore))
	var tourism0: float = sim.tourism
	sim.population = 20000                       # (it's unlocked at 10,000)
	await _click_at(_screen_of(rock))
	await _frames(2)
	check(sim.tiles[offshore] == T.ALCATRAZ and sim.building_working(offshore) and sim.tourism > tourism0
		and String(game.call("_tile_text", offshore)).contains("by ferry"),
		"alcatraz: built out on the water; tourists come by ferry (%.3f)" % sim.tourism)
	game.set("_buildings_dirty", true)
	game.set("_ground_dirty", true)
	game.call("_select_tool", ROAD)
	game.call("_refresh_hud")
	await _look_at(rock, PLAY_DISTANCE * 0.3, -40.0, 30.0, [])
	await _shot("p59_alcatraz")
	data = sim.to_save()
	sim.from_save(data)
	check(sim.tiles[offshore] == T.ALCATRAZ, "alcatraz: saved and loaded, still on the water")


func _road_types() -> void:
	# Roads, avenues and motorways: the same two districts as the traffic test,
	# joined by one road that jams. Widened into an avenue (with the mouse) it no
	# longer does; with a second link beside it, drivers take the avenue; nothing
	# opens onto a motorway; a save keeps the kinds and an old save has only roads.
	var kinds := {}
	for item: Dictionary in game.call("_menu_items"):
		kinds[item["id"]] = item["price"]
	check(kinds.has("avenue") and kinds.has("motorway") and String(kinds.get("motorway", "")).contains("120"),
		"roads: avenue and motorway are in the Build menu (%s, %s)" % [kinds.get("avenue", "-"), kinds.get("motorway", "-")])
	await _open_new_city_from_menu()
	await _key(KEY_1)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	var o := _find_land(28, 13)
	check(o.x >= 0 and _built_count() == 0, "roads: a new city with flat land for two districts at %s" % o)
	if o.x < 0:
		return
	sim.money = 500000
	for side: int in [0, 19]:
		_place("road", o + Vector2i(side + 4, 1), o + Vector2i(side + 4, 11))
		for y: int in [1, 4, 7, 10]:
			_place("road", o + Vector2i(side, y), o + Vector2i(side + 8, y))
	for x: int in [24, 25, 26, 27]:
		_place("coal", o + Vector2i(x, 12))
	_place("homes_1", o + Vector2i(0, 0), o + Vector2i(8, 12))
	_place("industry", o + Vector2i(19, 0), o + Vector2i(27, 8))
	_place("shops_1", o + Vector2i(19, 9), o + Vector2i(27, 12))
	_place("road", o + Vector2i(9, 4), o + Vector2i(18, 4))
	_fill_plots(o, o + Vector2i(27, 12))
	var link := o + Vector2i(13, 4)
	var li := link.y * sim.w + link.x
	var trips0 := _trips(link)
	check(sim.traffic_band(li) == 3 and sim.road_kind_at(li) == 0 and String(game.call("_tile_text", li)).begins_with("Road — Jammed")
		and sim.traffic_fix(li).contains("avenue"),
		"roads: the one link road is jammed, and the advice is to widen it (%s)" % String(game.call("_tile_text", li)).replace("\n", " / "))

	# Widen it into an avenue, with the mouse.
	var money0: int = sim.money
	var upkeep0: float = sim.road_upkeep
	await _pick_item("roads", "avenue")
	await _look_at(o + Vector2i(14, 6), PLAY_DISTANCE * 1.6, -40.0, 50.0, [o + Vector2i(8, 4), o + Vector2i(19, 4)])
	await _drag(_screen_of(o + Vector2i(9, 4)), _screen_of(o + Vector2i(18, 4)))
	var avenues := 0
	for x: int in range(9, 19):
		avenues += 1 if sim.road_kind_at((o.y + 4) * sim.w + o.x + x) == 1 else 0
	check(avenues == 10 and _count(Simulation.Tile.ROAD, o + Vector2i(9, 4), o + Vector2i(18, 4)) == 10,
		"roads: dragging the avenue over the road widened all 10 tiles (%d)" % avenues)
	var paid: int = money0 - sim.money
	check(paid >= 10 * int(Settings.ROAD_COSTS[1]) and paid < 14 * int(Settings.ROAD_COSTS[1]),
		"roads: ...at the avenue's price (%s)" % Hud.money_text(paid))
	sim.recount()
	check(is_equal_approx(sim.road_upkeep - upkeep0, 10.0 * (float(Settings.ROAD_UPKEEPS[1]) - float(Settings.ROAD_UPKEEPS[0]))),
		"roads: ...and it costs more to keep (%.1f -> %.1f a month for all the roads)" % [upkeep0, sim.road_upkeep])
	var text: String = game.call("_tile_text", li)
	print("[play] roads: the link as a road %d trips a day (jammed), as an avenue %d (%s)" % [roundi(trips0),
		roundi(_trips(link)), sim.traffic_word(li)])
	check(sim.traffic_band(li) < 3 and is_equal_approx(_trips(link), trips0),
		"roads: the avenue takes the same traffic without jamming (%s)" % sim.traffic_word(li))
	check(text.begins_with("Avenue — ") and text.contains("it takes 14,000"), "roads: its hover text (%s)" % text.replace("\n", " / "))
	await _wait(1.0)
	await _shot("p24_avenue")

	# A second link, an ordinary road: most drivers still take the avenue.
	_place("road", o + Vector2i(9, 10), o + Vector2i(18, 10))
	var link2 := o + Vector2i(13, 10)
	var avenue_share := _trips(link) / maxf(_trips(link) + _trips(link2), 1.0)
	_place("road", o + Vector2i(9, 4), o + Vector2i(18, 4))          # (both ordinary roads, to compare)
	var road_share := _trips(link) / maxf(_trips(link) + _trips(link2), 1.0)
	_place("avenue", o + Vector2i(9, 4), o + Vector2i(18, 4))
	check(sim.road_kind_at(li) == 1 and avenue_share > road_share + 0.05,
		"roads: with a road beside it, more drivers take the avenue (%d%% of the two; %d%% when both are roads)" % [
		roundi(avenue_share * 100.0), roundi(road_share * 100.0)])

	# A motorway: quicker still, but nothing opens onto it.
	var corner := o + Vector2i(0, 12)
	var ci := corner.y * sim.w + corner.x
	check(sim.has_road_access(ci), "roads: a home two plots from a side street has a road")
	_place("motorway", o + Vector2i(0, 10), o + Vector2i(3, 10))
	var blocked: Array = sim.call("_zone_check", ci)
	var why: String = blocked[1]
	check(sim.road_kind_at((o.y + 10) * sim.w + o.x) == 2 and not sim.has_road_access(ci) and why.contains("a motorway doesn't count"),
		"roads: ...but not once that street is a motorway (%s)" % why)
	check("road" in _tip_ids(), "roads: ...and the advisor counts it as a plot with no road")
	_place("road", o + Vector2i(0, 10), o + Vector2i(3, 10))
	check(sim.has_road_access(ci) and sim.road_kind_at((o.y + 10) * sim.w + o.x) == 0, "roads: back to a road, the home has its street again")
	_place("motorway", o + Vector2i(9, 10), o + Vector2i(18, 10))
	var motorway_share := _trips(link2) / maxf(_trips(link) + _trips(link2), 1.0)
	check(motorway_share > 1.0 - avenue_share + 0.05 and String(game.call("_tile_text", link2.y * sim.w + link2.x)).begins_with("Motorway — "),
		"roads: the second link as a motorway takes more than it did as a road (%d%% of the two, from %d%%)" % [
		roundi(motorway_share * 100.0), roundi((1.0 - avenue_share) * 100.0)])
	await _wait(1.0)
	await _shot("p25_motorway")

	# Saved and loaded; an old save (no kinds) has only ordinary roads; bulldozed and rebuilt it's a road.
	var data := sim.to_save()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(data))
	sim.from_save(saved)
	check(sim.road_kind_at(li) == 1 and sim.road_kind_at(link2.y * sim.w + link2.x) == 2,
		"roads: a save keeps the avenue and the motorway")
	saved.erase("road_kind")
	sim.from_save(saved)
	check(sim.road_kind_at(li) == 0 and sim.road_kind_at(link2.y * sim.w + link2.x) == 0 and sim.traffic_band(li) < 3,
		"roads: a save from before road kinds loads with ordinary roads")
	sim.from_save(JSON.parse_string(JSON.stringify(data)))
	_place("bulldoze", link, link)
	_place("road", link, link)
	check(sim.road_kind_at(li) == 0 and sim.road_kind_at(li + 1) == 1, "roads: a bulldozed avenue tile rebuilt with the Road tool is a road")


func _traffic() -> void:
	# Two districts, homes to the west and works and shops to the east, joined by a
	# single road: that link is the busiest road and jams, a dead end is quiet. A
	# second link takes traffic off the first; a plot with no road adds no trips; a
	# bus depot takes cars off the roads near the homes. Then the Traffic view (icon
	# and O), the legend, the hover card, the City panel and the advisor; the same
	# town always gives the same traffic, also after saving and loading; and jams
	# change nothing else in the town (for now they're only shown).
	await _open_new_city_from_menu()
	await _key(KEY_1)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	check(sim.difficulty == 0 and _built_count() == 0, "traffic: a new city (Easy) for the traffic test")
	var o := _find_land(28, 13)
	check(o.x >= 0, "traffic: found flat land for two districts at %s" % o)
	if o.x < 0:
		return
	sim.money = 500000
	# West: homes on a spine with four side streets. East: the same, with works and shops.
	for side: int in [0, 19]:
		_place("road", o + Vector2i(side + 4, 1), o + Vector2i(side + 4, 11))
		for y: int in [1, 4, 7, 10]:
			_place("road", o + Vector2i(side, y), o + Vector2i(side + 8, y))
	for x: int in [24, 25, 26, 27]:
		_place("coal", o + Vector2i(x, 12))
	_place("homes_1", o + Vector2i(0, 0), o + Vector2i(8, 12))
	_place("industry", o + Vector2i(19, 0), o + Vector2i(27, 8))
	_place("shops_1", o + Vector2i(19, 9), o + Vector2i(27, 12))
	# The link between them, with the mouse.
	await _pick_item("roads", "road")
	await _look_at(o + Vector2i(14, 6), PLAY_DISTANCE * 1.6, -40.0, 50.0, [o + Vector2i(8, 4), o + Vector2i(19, 4)])
	await _drag(_screen_of(o + Vector2i(9, 4)), _screen_of(o + Vector2i(18, 4)))
	check(_count(Simulation.Tile.ROAD, o + Vector2i(9, 4), o + Vector2i(18, 4)) == 10, "traffic: a link road joins the two districts")
	_fill_plots(o, o + Vector2i(27, 12))
	check(sim.population > 3000 and sim.jobs() > sim.population * Settings.WORKER_SHARE,
		"traffic: both districts built up (%d people, %d jobs)" % [sim.population, sim.jobs()])

	# A couple of months on the real clock: worked out again each month.
	var t_before: int = sim.traffic_trips
	await _one_month()
	await _one_month()
	check(not bool(sim.get("_traffic_dirty")) and sim.traffic_trips > 0,
		"traffic: worked out each month (%d -> %d car trips a day, %.1f ms)" % [t_before, sim.traffic_trips, sim.traffic_ms])
	_fill_plots(o, o + Vector2i(27, 12))           # (back to fully built, whatever the months did)

	var link := o + Vector2i(13, 4)
	var dead_end := o + Vector2i(0, 1)
	var town_most := _busiest(o, o + Vector2i(27, 12))
	var link_most := _busiest(o + Vector2i(9, 4), o + Vector2i(18, 4))
	print("[play] traffic: link %d trips a day (%s), dead end %d (%s), busiest road %d; %d car trips a day, %d%% in jams, %.1f ms" % [
		roundi(_trips(link)), sim.traffic_word(link.y * sim.w + link.x), roundi(_trips(dead_end)),
		sim.traffic_word(dead_end.y * sim.w + dead_end.x), roundi(town_most), sim.traffic_trips,
		roundi(sim.traffic_jammed_share() * 100.0), sim.traffic_ms])
	check(link_most >= town_most * 0.9, "traffic: the link carries the most traffic (%d of the busiest %d)" % [
		roundi(link_most), roundi(town_most)])
	check(_trips(link) > _trips(dead_end) * 5.0 and sim.traffic_band(link.y * sim.w + link.x) > sim.traffic_band(dead_end.y * sim.w + dead_end.x),
		"traffic: the link (%d) is in a higher band than a dead end (%d)" % [roundi(_trips(link)), roundi(_trips(dead_end))])
	check(sim.traffic_band(link.y * sim.w + link.x) == 3, "traffic: the only link is jammed")
	check(sim.traffic_jammed_share() >= Settings.TRAFFIC_JAM_TIP and "traffic" in _tip_ids(),
		"traffic: the advisors mention the jams (%d%% of trips)" % roundi(sim.traffic_jammed_share() * 100.0))
	for tip: Dictionary in Advisors.tips(sim):
		if tip["id"] == "traffic":
			check(int(tip["overlay"]) == WorldView.Overlay.TRAFFIC, "traffic: the tip shows the Traffic view: \"%s\"" % tip["text"])

	# The same town always gives the same traffic.
	var first: PackedFloat32Array = sim.traffic_map().duplicate()
	sim.set("_traffic_dirty", true)
	sim.set("_graph_version", -1)
	check(sim.traffic_map() == first, "traffic: the same town gives exactly the same traffic")

	# The Traffic view: its icon, its key and the O key.
	hud.set_build_open(false)
	await _look_at(o + Vector2i(14, 6), PLAY_DISTANCE * 1.6, -40.0, 50.0, [o, o + Vector2i(27, 0), o + Vector2i(0, 12),
		o + Vector2i(27, 12)])
	var buttons: Dictionary = hud.overlay_buttons
	await _click(buttons[WorldView.Overlay.TRAFFIC])
	check(world.overlay == WorldView.Overlay.TRAFFIC and Hud.OVERLAY_NAMES[WorldView.Overlay.TRAFFIC] == "Traffic",
		"traffic: the Traffic view's icon shows it")
	var legend: VBoxContainer = hud.legend_box
	await _frames(2)
	var rows: Array[String] = []
	for row: Node in legend.get_children():
		if row.is_queued_for_deletion():
			continue
		for c: Node in row.get_children():
			if c is Label:
				rows.append((c as Label).text)
	check(rows.size() == 5 and rows[0] == "Quiet" and rows[1] == "Free-flowing" and rows[2].begins_with("Busy")
		and rows[3].begins_with("Heavy") and rows[4].begins_with("Jammed"), "traffic: the key: %s" % " / ".join(rows))
	var link_colour: Color = world.overlay_image.get_pixel(link.x, link.y)
	var red := WorldView.OV_RED
	check(absf(link_colour.r - red.r) + absf(link_colour.g - red.g) + absf(link_colour.b - red.b) < 0.03,
		"traffic: the jammed link is red on the map (%s)" % link_colour)
	# Hover the link: the card says how busy it is and what to do.
	await _move(_screen_of(link))
	await _move(_screen_of(link) + Vector2(1, 1))
	var title: Label = hud.get("_info_title")
	var details: Label = hud.info_label
	check(game.get("hover") == link and title.text.begins_with("Road — Jammed") and title.text.contains("trips a day")
		and details.text.contains("parallel roads"), "traffic: hovering the link: \"%s / %s\"" % [title.text, details.text])
	await _move(_screen_of(dead_end) + Vector2(1, 1))
	check(game.get("hover") == dead_end and (title.text.begins_with("Road — Quiet") or title.text.begins_with("Road — Free")),
		"traffic: hovering the dead end: \"%s\"" % title.text)
	await _move(Vector2(1, 1))
	await _shot("p17_traffic_view")
	game.call("_set_overlay", WorldView.Overlay.POLLUTION)
	await _key(KEY_O)
	check(world.overlay == WorldView.Overlay.TRAFFIC, "traffic: O after Pollution shows Traffic")
	await _key(KEY_O)
	check(world.overlay == WorldView.Overlay.NONE, "traffic: O after Traffic goes back to normal")
	# The City panel.
	await _click(hud.get("_status_island"))
	var line: Label = hud.traffic_label
	check(hud.city_panel.visible and line.text.contains("% of trips in jams"), "traffic: the City panel says \"%s\"" % line.text)
	await _click(hud.get("_city_button"))

	# A second link takes traffic off the first.
	var a_before := _trips(link)
	await _pick_item("roads", "road")
	await _look_at(o + Vector2i(14, 6), PLAY_DISTANCE * 1.6, -40.0, 50.0, [o + Vector2i(8, 10), o + Vector2i(19, 10)])
	await _drag(_screen_of(o + Vector2i(9, 10)), _screen_of(o + Vector2i(18, 10)))
	check(_count(Simulation.Tile.ROAD, o + Vector2i(9, 10), o + Vector2i(18, 10)) == 10, "traffic: a second link road")
	var link2 := o + Vector2i(13, 10)
	print("[play] traffic: with a second link: first %d -> %d trips a day, second %d" % [roundi(a_before),
		roundi(_trips(link)), roundi(_trips(link2))])
	check(_trips(link) < a_before * 0.8 and _trips(link2) > 0.0,
		"traffic: the second link takes traffic off the first (%d -> %d; the second %d)" % [roundi(a_before),
		roundi(_trips(link)), roundi(_trips(link2))])
	check(sim.traffic_band(link.y * sim.w + link.x) < 3, "traffic: ...so the first link is no longer jammed (%s)" % sim.traffic_word(link.y * sim.w + link.x))

	# A plot with no road makes no trips.
	var trips0: int = sim.traffic_trips
	var lone := o + Vector2i(13, 0)
	_place("homes_1", lone)
	_fill_plots(lone, lone)
	check(sim.tiles[lone.y * sim.w + lone.x] == Simulation.Tile.HOMES and sim.units(lone.y * sim.w + lone.x) > 0
		and not sim.has_road_access(lone.y * sim.w + lone.x), "traffic: homes with no road within reach (%d people)" % sim.units(lone.y * sim.w + lone.x))
	check(sim.traffic_trips == trips0, "traffic: ...add no trips (%d, %d)" % [trips0, sim.traffic_trips])

	# A bus depot near the homes takes cars off their roads.
	var west0 := _road_trips(o, o + Vector2i(8, 12))
	var transit0: int = sim.transit_trips
	await _pick_item("transport", "bus_depot")
	await _look_at(o + Vector2i(4, 6), PLAY_DISTANCE, -40.0, 42.0, [o + Vector2i(2, 6)])
	await _click_at(_screen_of(o + Vector2i(2, 6)))
	var depot := (o.y + 6) * sim.w + o.x + 2
	check(sim.tiles[depot] == Simulation.Tile.BUS_DEPOT and sim.building_working(depot), "traffic: a working bus depot among the homes")
	var west1 := _road_trips(o, o + Vector2i(8, 12))
	print("[play] traffic: the bus depot: the homes' roads %d -> %d trips a day; %d -> %d by bus" % [roundi(west0),
		roundi(west1), transit0, sim.transit_trips])
	check(west1 < west0 * 0.85 and sim.transit_trips > transit0, "traffic: the bus depot takes trips off the roads near it (%d -> %d)" % [
		roundi(west0), roundi(west1)])

	# Saving and loading: traffic isn't saved, it's worked out again, the same.
	await _key(KEY_S, true)
	var saved_traffic: PackedFloat32Array = sim.traffic_map().duplicate()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(game.get("save_file"))))
	check(typeof(data) == TYPE_DICTIONARY and not (data as Dictionary).has("traffic"), "traffic: nothing about traffic in the save")
	await _click(hud.bulldoze_button)
	await _drag(_screen_of(o + Vector2i(4, 5)), _screen_of(o + Vector2i(4, 6)))
	check(sim.traffic_map() != saved_traffic, "traffic: bulldozing a road changes the traffic")
	await _key(KEY_L, true)
	await _frames(2)
	check(sim.traffic_map() == saved_traffic, "traffic: after loading it's worked out again, exactly the same")

	# View only: jams change nothing else. The same months twice, the second time
	# with tiny roads (everything jammed) and the traffic worked out every month.
	var snapshot := sim.to_save()
	var runs: Array[int] = []
	var jam_seen := 0.0
	for squeeze: bool in [false, true]:
		sim.from_save(snapshot)
		sim.set("_capacity_scale", 0.02 if squeeze else 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		sim.set("_rng", rng)
		for m: int in 6:
			seed(777 + m)
			sim.tick()
			if squeeze:
				jam_seen = maxf(jam_seen, sim.traffic_jammed_share())
		runs.append(_town_state())
	sim.set("_capacity_scale", 1.0)
	check(jam_seen > 0.5, "traffic: with tiny roads most trips are in jams (%d%%)" % roundi(jam_seen * 100.0))
	check(runs[0] == runs[1], "traffic: ...and growth, happiness, land value, money and pollution come out exactly the same")
	sim.from_save(snapshot)
	game.call("_refresh_hud")
	world.refresh_all()
	game.set("_layout_seen", sim.layout_version)


# ----------------------------------------------------------------- services

func _legend_rows() -> Array[String]:
	var rows: Array[String] = []
	for row: Node in hud.legend_box.get_children():
		if row.is_queued_for_deletion():
			continue
		for c: Node in row.get_children():
			if c is Label:
				rows.append((c as Label).text)
	return rows


func _near_colour(c: Color, want: Color) -> bool:
	return absf(c.r - want.r) + absf(c.g - want.g) + absf(c.b - want.b) < 0.03


func _school_tip() -> Dictionary:
	for tip: Dictionary in Advisors.tips(sim):
		if tip["id"] == "school":
			return tip
	return {}


func _services() -> void:
	# The Services view one service at a time. Homes in two places with works and
	# shops between, all built up past the size where homes need a school; a school
	# placed with the mouse in the west covers only the west. Then: the chips (by
	# clicking), the colours on the map, the hover card's row of ticks and crosses,
	# the school advisor's tip opening the view on Schools, the School tool's disc
	# and view (and going back), C, and map views lit by day at night.
	await _open_new_city_from_menu()
	await _key(KEY_1)
	await _key(KEY_ENTER)
	await _wait(0.2)
	game.call("_set_speed", 0)
	game.call("_set_overlay", WorldView.Overlay.NONE)
	rig.target = Vector3(sim.w * world.cell * 0.45, 0.0, sim.h * world.cell * 0.5)   # (from the middle, as a new game starts)
	var o := _find_land(36, 13)
	check(o.x >= 0 and _built_count() == 0, "services: a new city with flat land for two estates at %s" % o)
	if o.x < 0:
		return
	sim.money = 500000
	# Streets: an estate each side (x 0-8 and 27-35), works and shops between, one road along y = 7.
	for side: int in [0, 13, 27]:
		_place("road", o + Vector2i(side + 4, 1), o + Vector2i(side + 4, 11))
		for y: int in [1, 4, 10]:
			_place("road", o + Vector2i(side, y), o + Vector2i(side + 8 + (1 if side == 13 else 0), y))
	_place("road", o + Vector2i(0, 7), o + Vector2i(35, 7))
	for x: int in [14, 15, 16, 17]:
		_place("coal", o + Vector2i(x, 12))
	_place("water_pump", o + Vector2i(19, 12))
	_place("water_pump", o + Vector2i(20, 12))
	_place("homes_1", o + Vector2i(0, 0), o + Vector2i(8, 12))
	_place("homes_1", o + Vector2i(27, 0), o + Vector2i(35, 12))
	_place("industry", o + Vector2i(13, 0), o + Vector2i(22, 8))
	_place("shops_1", o + Vector2i(13, 9), o + Vector2i(22, 11))
	# Works and shops fully built; homes one level up (terraces), so their next step is tenements.
	for y: int in range(o.y, o.y + 13):
		for x: int in range(o.x, o.x + 36):
			var i := y * sim.w + x
			if sim.is_zone(sim.tiles[i]):
				sim.levels[i] = 1 if sim.tiles[i] == Simulation.Tile.HOMES else sim.max_level(i)
	sim.set("_power_dirty", true)
	sim.set("_value_dirty", true)
	sim.set("_coverage_dirty", true)
	sim.recount()
	game.call("_refresh_hud")
	world.refresh_all()
	game.set("_layout_seen", sim.layout_version)
	var west := o + Vector2i(3, 5)          # a west home, near where the school goes
	var east := o + Vector2i(33, 5)         # an east home, far from it (x 31 is the street)
	var wi := west.y * sim.w + west.x
	var ei := east.y * sim.w + east.x
	print("[play] services: %d people, %d jobs, home demand %.0f; west home: %s; east home: %s" % [sim.population,
		sim.jobs(), sim.demand_for(Simulation.Tile.HOMES), sim.zone_status(wi), sim.zone_status(ei)])
	check(sim.population >= Settings.SCHOOL_NEEDED_POP and sim.tiles[ei] == Simulation.Tile.HOMES
		and sim.service_holds_back(2, ei), "services: a town of %d people whose homes wait for a school" % sim.population)
	var tip := _school_tip()
	check(not tip.is_empty() and int(tip["overlay"]) == WorldView.Overlay.SERVICES and int(tip["filter"]) == 2,
		"services: the advisor asks for a school (\"%s\") and points at the Services view on Schools" % tip.get("text", ""))

	# Placing the school with the mouse: the Services view shows schools, a disc
	# shows how far it would reach, and the card says how many homes it would reach.
	hud.set_build_open(false)
	await _look_at(o + Vector2i(17, 6), PLAY_DISTANCE * 2.0, -40.0, 55.0, [o, o + Vector2i(35, 0), o + Vector2i(0, 12),
		o + Vector2i(35, 12)])
	await _pick_item("services", "school")
	check(world.overlay == WorldView.Overlay.SERVICES and world.service_filter == 2 and bool(game.get("_auto_overlay")),
		"services: picking the School shows the Services view on Schools")
	hud.set_build_open(false)                     # (so the menu isn't over the west estate)
	await _frames(2)
	var spot := o + Vector2i(2, 5)
	await _move(_screen_of(spot))
	await _move(_screen_of(spot) + Vector2(1, 1))
	var decal: Decal = world.reach_decal
	var want_r: float = sim.service_cover_tiles(2) * world.cell
	check(game.get("hover") == spot and decal.visible and absf(decal.size.x - want_r * 2.0) < 1.0
		and decal.position.distance_to(world.ground_point(spot)) < 1.0,
		"services: a disc of %d m round the mouse shows where the school would reach" % roundi(want_r))
	var action: Label = hud.get("_info_action")
	check(action.text.contains("would reach") and action.text.contains("homes with no school"),
		"services: the card says what it would reach: \"%s\"" % action.text)
	await _shot("p18_services_place_school")
	await _click_at(_screen_of(spot) + Vector2(1, 1))
	var school := spot.y * sim.w + spot.x
	check(sim.tiles[school] == Simulation.Tile.SCHOOL and sim.service_working(school), "services: a working school in the west")
	await _move(_screen_of(spot + Vector2i(1, 0)))
	await _pick_item("roads", "road")
	check(world.overlay == WorldView.Overlay.NONE and not decal.visible and not bool(game.get("_auto_overlay")),
		"services: picking the Road puts the view back to normal and the disc away")
	# From another view: the Police shows the Services view, and putting it down goes back.
	game.call("_set_overlay", WorldView.Overlay.POLLUTION)
	await _key(KEY_0)
	check(world.overlay == WorldView.Overlay.SERVICES and world.service_filter == sim.service_of(int(game.call("_target_tile"))),
		"services: the Services tool (0) shows its own service (%d)" % world.service_filter)
	await _key(KEY_TAB)
	check(world.service_filter == sim.service_of(int(game.call("_target_tile"))),
		"services: Tab to the next service shows that one (%d)" % world.service_filter)
	await _key(KEY_1)
	check(world.overlay == WorldView.Overlay.POLLUTION, "services: ...and the Road goes back to the Pollution view")
	game.call("_set_overlay", WorldView.Overlay.NONE)
	sim.recount()
	game.call("_refresh_hud")
	var held: int = sim.service_report(2)["held"]
	check(sim.covered(2, wi) and not sim.covered(2, ei) and not sim.service_holds_back(2, wi) and held > 0,
		"services: the school covers the west homes, not the east ones (%d held back)" % held)
	tip = _school_tip()
	check(not tip.is_empty() and String(tip["text"]).begins_with("%d plot" % held),
		"services: the advisor counts the same homes: \"%s\"" % tip.get("text", ""))

	# The Services view by its icon, then each chip by clicking.
	await _look_at(o + Vector2i(17, 6), PLAY_DISTANCE * 2.0, -40.0, 55.0, [o, o + Vector2i(35, 0), o + Vector2i(0, 12),
		o + Vector2i(35, 12)])
	await _click(hud.overlay_buttons[WorldView.Overlay.SERVICES])
	var chips: Dictionary = hud.service_chips
	check(world.overlay == WorldView.Overlay.SERVICES and world.service_filter == -1 and (chips[-1] as Button).button_pressed
		and (chips[2] as Button).is_visible_in_tree(), "services: the Services view's icon shows all four, with the chips")
	var rows := _legend_rows()
	check(rows.size() == 5 and rows[0] == "All four services", "services: All's key: %s" % " / ".join(rows))
	for s: int in [0, 1, 2, 3, -1]:
		await _click(chips[s])
		await _frames(2)
		rows = _legend_rows()
		var title: Label = hud.get("_legend_title")
		var ok := world.service_filter == s and int(hud.get("_service_filter")) == s and (chips[s] as Button).button_pressed
		if s >= 0:
			ok = ok and rows.size() == 5 and rows[0].begins_with("Full cover") and title.text.begins_with("Services: ") \
				and hud.legend_note.visible and world.pin_count() == sim.services[s]
		else:
			ok = ok and rows[0] == "All four services" and not hud.legend_note.visible and world.pin_count() == 0
		check(ok, "services: the %s chip: \"%s\" / %s / \"%s\"" % [["all", "police", "fire", "school", "hospital"][s + 1],
			title.text, " / ".join(rows), hud.legend_note.text])
	await _click(chips[2])
	var note := hud.legend_note.text
	check(note.contains("%d homes can't grow past townhouses" % held) and note.begins_with("Schools reach"),
		"services: the Schools key counts them: \"%s\"" % note)
	check(_legend_rows()[2].contains("no school") and _legend_rows()[4].begins_with("School"),
		"services: the Schools key: %s" % " / ".join(_legend_rows()))
	var west_colour: Color = world.overlay_image.get_pixel(west.x, west.y)
	var east_colour: Color = world.overlay_image.get_pixel(east.x, east.y)
	check(_near_colour(west_colour, WorldView.OV_GREEN) or _near_colour(west_colour, WorldView.OV_LIGHT_GREEN),
		"services: a west home is green (covered) on the map (%s)" % west_colour)
	check(_near_colour(east_colour, WorldView.OV_RED), "services: an east home is red (held back, no school) (%s)" % east_colour)
	check(_near_colour(world.overlay_image.get_pixel(spot.x, spot.y), WorldView.OV_BLUE) and world.pin_count() == 1,
		"services: the school is blue, with a pin")
	await _shot("p19_services_schools")
	# C: the next service; and from the normal view, the Services view.
	await _key(KEY_C)
	check(world.service_filter == 3 and (chips[3] as Button).button_pressed, "services: C shows the next service (hospitals)")
	await _key(KEY_C)
	check(world.service_filter == -1, "services: ...and after hospitals, all four")
	game.call("_set_overlay", WorldView.Overlay.NONE)
	await _key(KEY_C)
	check(world.overlay == WorldView.Overlay.SERVICES and world.service_filter == -1, "services: C from the normal view opens the Services view")
	await _click(hud.overlay_buttons[WorldView.Overlay.GROWTH])
	await _click(hud.overlay_buttons[WorldView.Overlay.SERVICES])
	check(world.service_filter == -1, "services: leaving the view and coming back starts on All again")

	# Hover: which services reach a plot (any view).
	game.call("_set_overlay", WorldView.Overlay.NONE)
	var marks: HFlowContainer = hud.service_marks
	var labels: Array[Label] = hud.get("_service_mark_labels")
	var icons: Array[TextureRect] = hud.get("_service_mark_icons")
	var tick: Texture2D = hud.call("_line_icon", "tick", 26)
	var cross: Texture2D = hud.call("_line_icon", "cross", 26)
	await _move(_screen_of(east))
	await _move(_screen_of(east) + Vector2(1, 1))
	var details: Label = hud.info_label
	var title2: Label = hud.get("_info_title")
	check(game.get("hover") == east and marks.is_visible_in_tree() and labels[2].text == "School" and icons[2].texture == cross
		and _near_colour(icons[2].modulate, Hud.BAD) and title2.text.contains("waiting for a school"),
		"services: hovering an east home: \"%s\", School crossed in red" % title2.text)
	await _move(_screen_of(west))
	await _move(_screen_of(west) + Vector2(1, 1))
	check(game.get("hover") == west and icons[2].texture == tick and _near_colour(icons[2].modulate, Hud.GOOD)
		and icons[0].texture == cross, "services: hovering a west home: School ticked, Police crossed")
	await _shot("p20_services_hover")
	await _move(_screen_of(spot))
	await _move(_screen_of(spot) + Vector2(1, 1))
	check(not marks.visible and title2.text.begins_with("School: working") and details.text.contains("covers")
		and details.text.contains("people"), "services: hovering the school: \"%s / %s\"" % [title2.text, details.text])

	# The school advisor's tip opens the Services view on Schools; again goes back.
	var tips: Array = hud.get("_advice_tips")
	var row_n := -1
	for n: int in tips.size():
		if tips[n]["id"] == "school":
			row_n = n
	check(row_n >= 0, "services: the school tip is in the advisors' list (%d of %d)" % [row_n + 1, tips.size()])
	if row_n >= 0:
		var rows_b: Array[Button] = hud.get("_advice_rows")
		if row_n == 0:
			await _click(hud.get("_ticker"))
		else:
			await _click(hud.get("_advice_count"))
			await _click(rows_b[row_n])
		check(world.overlay == WorldView.Overlay.SERVICES and world.service_filter == 2 and (chips[2] as Button).button_pressed,
			"services: clicking it shows the Services view on Schools")
		if hud.get("_advice_list").visible:
			await _click(rows_b[row_n])
		else:
			await _click(hud.get("_ticker"))
		check(world.overlay == WorldView.Overlay.NONE, "services: clicking it again goes back to the normal view")
		if hud.get("_advice_list").visible:
			await _click(hud.get("_advice_count"))

	# Map views at night are lit by day; the normal view follows the clock.
	game.set("time_of_day", 0.95)
	await _frames(3)
	check(world.night > 0.9, "services: night in the normal view (night %.2f)" % world.night)
	await _click(hud.overlay_buttons[WorldView.Overlay.SERVICES])
	await _frames(3)
	var env: Environment = world.get("env")
	check(world.night < 0.01 and world.clock_night > 0.9 and env.ambient_light_energy < 0.5,
		"services: a map view at night is lit by day (night %.2f, clock %.2f, ambient %.2f)" % [world.night, world.clock_night,
		env.ambient_light_energy])
	await _shot("p21_services_night")
	await _click(hud.overlay_buttons[WorldView.Overlay.NONE])
	await _frames(3)
	check(world.night > 0.9, "services: back to the normal view, it's night again")
	game.set("time_of_day", 0.55)
	await _frames(2)
