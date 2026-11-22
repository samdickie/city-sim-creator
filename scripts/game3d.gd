extends Node3D
## Troon City in 3D — the game.
## Loads the map, runs the game clock, turns mouse and keyboard into building,
## and keeps the 3D world and the interface up to date.
## The city's rules live in simulation.gd; tuning numbers in settings.gd.

const Settings = preload("res://scripts/settings.gd")
const Simulation = preload("res://scripts/simulation.gd")
const WorldView = preload("res://scripts/world3d.gd")
const CameraRig = preload("res://scripts/camera_rig.gd")
const Hud = preload("res://scripts/hud.gd")
const Companies = preload("res://scripts/companies.gd")
const Traffic = preload("res://scripts/traffic.gd")
const Advisors = preload("res://scripts/advisors.gd")
const DevShots = preload("res://scripts/dev_shots.gd")   # dev tool: tools/screenshots.sh
const DevExamples = preload("res://scripts/dev_examples.gd")   # dev tool: tools/make_examples.sh
const DevPromo = preload("res://scripts/dev_promo.gd")   # dev tool: tools/make_promo.sh
const DevPlaytest = preload("res://scripts/dev_playtest.gd")   # dev tool: tools/playtest.sh

const MAP_FILE := "res://map/palo_alto_map.json"     # (Troon's is still in map/: make it MAP_FILE to play there)
const SAVE_FILE := "user://troon_save.json"           # the player's own city
const DEV_SAVE_FILE := "user://dev_tools_save.json"   # what Save and Load use when a dev tool runs the game
const EXAMPLES_DIR := "res://examples"   # ready-made cities (the game menu's Example cities)
const SAVE_VERSION := 4               # 4: difficulty and loans (older saves load as Normal with no loans)

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE, PARK,
	POLICE, FIRE, SCHOOL, HOSPITAL,
	WIND, SOLAR, GAS, NUCLEAR, WATER_PUMP, WATER_TOWER, LANDFILL, RECYCLING,
	GOLF, LIBRARY, MUSEUM, STADIUM, MARINA, TOWN_HALL, BUS_DEPOT, STATION, HARBOUR,
	WOODLAND, OFFICES, POLICE_OFFICE, FIRE_SMALL, CLINIC, AIRPORT,
	BIG_BEN, COLOSSEUM, GREAT_PYRAMID, LIBERTY, TAJ_MAHAL, OPERA_HOUSE, EIFFEL, EMPIRE_STATE,
	INCINERATOR, DATA_CENTRE, GIGAFACTORY, TECH_CAMPUS, LAUNCH_SITE, AI_DATA_CENTRE,
	COLLEGE, UNIVERSITY, RESEARCH_PARK }   # same order as simulation.gd
enum Tool { ROAD, HOMES, SHOPS, INDUSTRY, BULLDOZE, POWER, UTILITY, PARK, GRID, SERVICE, LEISURE, TRANSPORT,
	DISTRICT, OFFICES, LANDMARK, DEAL, EDUCATION }   # DEAL: placing a company's data centre (not in the Build menu)

const TOOL_NAMES := {
	Tool.ROAD: "Road",
	Tool.HOMES: "Homes",
	Tool.SHOPS: "Shops",
	Tool.INDUSTRY: "Industry",
	Tool.BULLDOZE: "Bulldoze",
	Tool.POWER: "Power",
	Tool.UTILITY: "Utilities",
	Tool.PARK: "Park",
	Tool.GRID: "Street grid",
	Tool.SERVICE: "Services",
	Tool.LEISURE: "Leisure",
	Tool.TRANSPORT: "Transport",
	Tool.DISTRICT: "Districts",
	Tool.OFFICES: "Offices",
	Tool.LANDMARK: "Landmarks",
	Tool.DEAL: "Data centre",
	Tool.EDUCATION: "Education",
}
const TOOL_KEYS := {
	Tool.ROAD: "1", Tool.HOMES: "2", Tool.SHOPS: "3", Tool.INDUSTRY: "4", Tool.BULLDOZE: "5",
	Tool.POWER: "6", Tool.UTILITY: "7", Tool.PARK: "8", Tool.GRID: "9", Tool.SERVICE: "0",
	Tool.LEISURE: "-", Tool.TRANSPORT: "=", Tool.DISTRICT: "Z",
}
# The District tool's picker, in order: CBD, Tech zone, conservation area, back to normal.
const DISTRICT_ORDER := [2, 3, 1, 0]
const DISTRICT_IDS := ["cbd", "tech_zone", "conservation", "normal"]
const DISTRICT_ABOUT := [
	"Central business district: high-density plots can become skyscrapers (with 8,000 people and a station or bus depot nearby). Raises land value.",
	"Tech zone: offices and industry here pay their own tax rate (set it in the City panel). Set it below the town's and firms come from outside to fill it, bringing jobs and people; residents may grumble that it's unfair.",
	"Conservation area: nothing taller than four storeys, to keep the old town's character. A little extra land value.",
	"Normal: the usual height rules for each density."]
# Tools that open a picker of several buildings (Tab or the buttons choose one).
const GROUPS := {
	Tool.POWER: [Tile.POWER_PLANT, Tile.GAS, Tile.NUCLEAR, Tile.WIND, Tile.SOLAR, Tile.POWER_LINE],
	Tool.UTILITY: [Tile.WATER_PUMP, Tile.WATER_TOWER, Tile.LANDFILL, Tile.RECYCLING, Tile.INCINERATOR],
	Tool.SERVICE: [Tile.POLICE_OFFICE, Tile.POLICE, Tile.FIRE_SMALL, Tile.FIRE, Tile.SCHOOL, Tile.CLINIC, Tile.HOSPITAL],
	Tool.LEISURE: [Tile.WOODLAND, Tile.GOLF, Tile.LIBRARY, Tile.MUSEUM, Tile.STADIUM, Tile.MARINA, Tile.TOWN_HALL],
	Tool.TRANSPORT: [Tile.BUS_DEPOT, Tile.STATION, Tile.HARBOUR, Tile.AIRPORT],
	Tool.EDUCATION: [Tile.COLLEGE, Tile.UNIVERSITY, Tile.RESEARCH_PARK],
	Tool.LANDMARK: [Tile.BIG_BEN, Tile.COLOSSEUM, Tile.GREAT_PYRAMID, Tile.LIBERTY, Tile.TAJ_MAHAL, Tile.OPERA_HOUSE,
		Tile.EIFFEL, Tile.EMPIRE_STATE],
}
const TOOL_TO_TILE := {
	Tool.ROAD: Tile.ROAD,
	Tool.HOMES: Tile.HOMES,
	Tool.SHOPS: Tile.SHOPS,
	Tool.INDUSTRY: Tile.INDUSTRY,
	Tool.OFFICES: Tile.OFFICES,
	Tool.PARK: Tile.PARK,
	Tool.GRID: Tile.ROAD,
}
const TOOL_COLOURS := {
	Tool.ROAD: Color(0.45, 0.45, 0.48),
	Tool.HOMES: Color(0.86, 0.36, 0.30),
	Tool.SHOPS: Color(0.26, 0.58, 0.92),
	Tool.INDUSTRY: Color(0.96, 0.70, 0.15),
	Tool.BULLDOZE: Color(0.9, 0.3, 0.3),
	Tool.POWER: Color(0.98, 0.88, 0.25),
	Tool.UTILITY: Color(0.35, 0.60, 0.95),
	Tool.PARK: Color(0.40, 0.78, 0.36),
	Tool.GRID: Color(0.62, 0.62, 0.66),
	Tool.SERVICE: Color(0.30, 0.78, 0.86),
	Tool.LEISURE: Color(0.86, 0.55, 0.86),
	Tool.TRANSPORT: Color(0.95, 0.55, 0.25),
	Tool.DISTRICT: Color(0.62, 0.38, 0.92),
	Tool.OFFICES: Color(0.10, 0.72, 0.68),
	Tool.LANDMARK: Color(0.95, 0.78, 0.30),
	Tool.DEAL: Color(0.16, 0.76, 0.78),
	Tool.EDUCATION: Color(0.55, 0.45, 0.90),
}
const TILE_NAMES := {
	Tile.EMPTY: "Open land",
	Tile.ROAD: "Road",
	Tile.HOMES: "Homes",
	Tile.SHOPS: "Shops",
	Tile.INDUSTRY: "Industry",
	Tile.OFFICES: "Offices",
	Tile.POWER_PLANT: "Power plant",
	Tile.POWER_LINE: "Power line",
	Tile.PARK: "Park",
	Tile.POLICE: "Police station",
	Tile.FIRE: "Fire station",
	Tile.SCHOOL: "School",
	Tile.HOSPITAL: "Hospital",
	Tile.POLICE_OFFICE: "Police office",
	Tile.FIRE_SMALL: "Small fire station",
	Tile.CLINIC: "Clinic",
}

# --- Map ---
var map_w := 0
var map_h := 0
var cell_size_m := 50.0
var map_name := "Map"
var map_credits := ""
var heights := PackedFloat32Array()
var water := PackedByteArray()
var slope := PackedFloat32Array()

# --- City, clock and view ---
var sim := Simulation.new()
var world := WorldView.new()
var rig := CameraRig.new()
var hud := Hud.new()
var traffic := Traffic.new()
var speed := 1
var clock := 0.0
var time_of_day := Settings.START_TIME_OF_DAY
var day_cycle := true

# --- Interaction ---
var current_tool: int = Tool.ROAD
var current_density: int = 1          # 0 = low, 1 = medium, 2 = high (homes and shops)
var _choice := {}                      # group tool -> which of its buildings is picked
var _auto_overlay := false            # the view was switched on by the tool (Districts, or Services while placing one)
var _view_before := [0, -1]            # [map view, service filter] to go back to when that tool is put down
var painting := false
var orbiting := false
var dragging_map := false
var drag_start := Vector2i(-1, -1)     # where the current drag began
var drag_plan: Array[Vector2i] = []    # tiles the current drag would build on
var hover := Vector2i(-1, -1)
var _ground_dirty := false
var _buildings_dirty := false
var _layout_seen := -1                 # sim.layout_version last drawn
var _camera_seen := Transform3D()      # camera position last used to pick the hovered tile
var _mouse_at := Vector2(-1, -1)       # where the mouse last moved to (map or interface)
var fit_to_screen := true              # scale the interface and 3D picture to the screen (the screenshot tool turns it off)
var _speed_before_dialog := 1          # the speed to go back to when the New city dialog closes
var save_file := SAVE_FILE             # Save and Load (DEV_SAVE_FILE under the dev tools, so they never touch the player's)
var _speed_before_letter := 1
var _placing_deal := -1                # the deal whose data centre is being placed (Tool.DEAL)
var _tool_before_deal := 0             # the tool to go back to once it's placed          # the speed to go back to when the letter card closes
# Undo: one step per drag, newest last: {"what", "month", "spent", "tiles": {tile index: sim.tile_state}}.
var _undo: Array[Dictionary] = []


func _ready() -> void:
	# Tile numbers are shared by several scripts; make sure they all agree.
	assert(Tile.keys() == Simulation.Tile.keys(), "game3d.gd Tile list differs from simulation.gd")
	assert(Tile.keys() == WorldView.Tile.keys(), "world3d.gd Tile list differs from simulation.gd")
	assert(Simulation.Growth.keys() == WorldView.Growth.keys(), "world3d.gd Growth list differs from simulation.gd")
	assert(Hud.OVERLAY_NAMES.size() == WorldView.Overlay.size() and Hud.OVERLAY_TIPS.size() == WorldView.Overlay.size(),
		"hud.gd OVERLAY_NAMES / OVERLAY_TIPS don't match world3d.gd's Overlay list")
	_load_map()
	_compute_slopes()
	sim.setup(map_w, map_h, water)

	add_child(world)
	world.setup(sim, map_w, map_h, cell_size_m, heights, water)
	_layout_seen = sim.layout_version

	rig.bounds = Rect2(Vector2.ZERO, Vector2(map_w, map_h) * cell_size_m)
	rig.ground_height = world.height_at
	rig.target = Vector3(map_w * cell_size_m * 0.45, 0.0, map_h * cell_size_m * 0.5)
	add_child(rig)

	add_child(traffic)
	traffic.setup(world, sim)
	traffic.message.connect(hud.flash)

	add_child(hud)
	hud.build(BUILD_CATEGORIES, {
		Tile.HOMES: [TOOL_COLOURS[Tool.HOMES], "Homes"],
		Tile.SHOPS: [TOOL_COLOURS[Tool.SHOPS], "Shops"],
		Tile.OFFICES: [TOOL_COLOURS[Tool.OFFICES], "Offices"],
		Tile.INDUSTRY: [TOOL_COLOURS[Tool.INDUSTRY], "Industry"],
	}, sim)
	hud.set_city_name(map_name)
	hud.tool_chosen.connect(_select_tool)
	hud.build_item_chosen.connect(_choose_item)
	hud.set_items(_menu_items())
	hud.speed_chosen.connect(_set_speed)
	hud.tax_changed.connect(_change_tax)
	hud.tech_tax_changed.connect(_change_tech_tax)
	hud.letter_answered.connect(_answer_letter)
	hud.letter_shown.connect(_letter_shown)
	hud.place_deal_pressed.connect(_start_placing)
	hud.new_city_pressed.connect(_ask_new_city.bind(false))
	hud.new_city_chosen.connect(_new_city_chosen)
	hud.new_city_cancelled.connect(_new_city_cancelled)
	hud.borrow_pressed.connect(_borrow)
	hud.repay_pressed.connect(_repay)
	hud.save_pressed.connect(_save_game)
	hud.undo_pressed.connect(_undo_last)
	hud.load_pressed.connect(_load_game)
	hud.example_chosen.connect(_load_example)
	hud.day_cycle_toggled.connect(_set_day_cycle)
	hud.overlay_chosen.connect(_set_overlay)
	hud.service_filter_chosen.connect(_set_service_filter)
	hud.funding_changed.connect(_change_funding)

	get_viewport().size_changed.connect(_fit_to_screen)
	_fit_to_screen()
	_select_tool(Tool.ROAD)
	_set_overlay(WorldView.Overlay.NONE)
	_set_speed(1)
	_refresh_hud()
	if map_credits != "":
		hud.flash(map_credits)
	# Dev tools only: `-- --shots=<dir>` builds a demo town and saves screenshots;
	# `-- --playtest=<dir>` plays a new game with mouse and keyboard events.
	var user_args := OS.get_cmdline_user_args()
	if DevPromo.wanted_promo(user_args) or DevExamples.wanted_examples(user_args) or DevShots.wanted(user_args) \
			or DevPlaytest.wanted(user_args):
		save_file = DEV_SAVE_FILE      # (the play test presses Save: that must never overwrite the player's city)
	if DevPromo.wanted_promo(user_args):
		add_child(DevPromo.new(self, user_args))
		return
	if DevExamples.wanted_examples(user_args):
		add_child(DevExamples.new(self, user_args))
		return
	if DevShots.wanted(user_args):
		add_child(DevShots.new(self, user_args))
		return
	# Every game opens on a blank map: first, pick how much money to start with.
	_ask_new_city(true)
	if DevPlaytest.wanted(user_args):
		add_child(DevPlaytest.new(self, user_args))


func _fit_to_screen() -> void:
	# On a Retina screen, lay the interface out in points, not pixels (otherwise
	# its text is half the size it was designed at), and draw the 3D picture at
	# about Settings.RENDER_PIXELS, scaled up to the window with Apple's upscaler
	# on a Mac (AMD's elsewhere). See settings.gd.
	if not fit_to_screen:
		return
	var win := get_window()
	var px := Vector2(win.size)
	var ui := Settings.INTERFACE_SCALE if Settings.INTERFACE_SCALE > 0.0 else DisplayServer.screen_get_scale(win.current_screen)
	ui = clampf(minf(ui, minf(px.x / 1280.0, px.y / 720.0)), 1.0, 4.0)   # (room for the whole interface)
	if not is_equal_approx(win.content_scale_factor, ui):
		win.content_scale_factor = ui
	var vp := get_viewport()
	var factor := 1.0
	if Settings.RENDER_PIXELS > 0 and px.x * px.y > Settings.RENDER_PIXELS * 1.1:
		factor = clampf(sqrt(Settings.RENDER_PIXELS / (px.x * px.y)), 0.5, 1.0)
	vp.scaling_3d_scale = factor
	if factor >= 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR   # (no scaling at all)
	elif RenderingServer.get_current_rendering_driver_name() == "metal":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR


# --------------------------------------------------------------- map loading

func _load_map() -> void:
	var data = null
	if FileAccess.file_exists(MAP_FILE):
		data = JSON.parse_string(FileAccess.get_file_as_string(MAP_FILE))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Could not read %s — using a flat placeholder map." % MAP_FILE)
		map_w = 100
		map_h = 100
		heights.resize(map_w * map_h)
		heights.fill(5.0)
		water.resize(map_w * map_h)
		water.fill(0)
		return
	map_w = int(data["width"])
	map_h = int(data["height"])
	cell_size_m = float(data.get("cell_size_m", 50.0))
	map_name = str(data.get("name", "Map"))
	map_credits = str(data.get("credits", ""))
	var h: Array = data["heights"]
	var w: Array = data["water"]
	heights.resize(map_w * map_h)
	water.resize(map_w * map_h)
	for i in map_w * map_h:
		heights[i] = float(h[i])
		water[i] = int(w[i])


func _compute_slopes() -> void:
	slope.resize(map_w * map_h)
	for y in map_h:
		for x in map_w:
			var h := heights[y * map_w + x]
			var steepest := 0.0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if _in_map(n) and water[n.y * map_w + n.x] == 0:
					steepest = maxf(steepest, absf(h - heights[n.y * map_w + n.x]))
			slope[y * map_w + x] = steepest


# --------------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	# Remember where the mouse is, even over the interface (see _process).
	var mm := event as InputEventMouseMotion
	if mm:
		_mouse_at = mm.position


func _unhandled_input(event: InputEvent) -> void:
	# The wheel and trackpad gestures over the interface scroll it (the Build list,
	# the City panel, help); they must never also zoom or move the map.
	var wheel := event is InputEventMouseButton and (event as InputEventMouseButton).button_index in [
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
	if (wheel or event is InputEventGesture) and get_viewport().gui_get_hovered_control() != null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				# Press, drag to see a preview and the cost, release to build.
				if mb.pressed:
					if _in_map(hover):
						painting = true
						drag_start = hover
						_update_drag()
				elif painting:
					painting = false
					_finish_drag()
			MOUSE_BUTTON_RIGHT:
				orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				dragging_map = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					rig.zoom(0.88, _mouse_ground())
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					rig.zoom(1.0 / 0.88)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if orbiting:
			rig.orbit(mm.relative.x, mm.relative.y)
		elif dragging_map:
			rig.pan_pixels(mm.relative)
		_update_hover(mm.position)

	elif event is InputEventMagnifyGesture:       # trackpad pinch
		var mg := event as InputEventMagnifyGesture
		rig.zoom(1.0 / mg.factor, _mouse_ground())

	elif event is InputEventPanGesture:           # trackpad two-finger scroll
		var pg := event as InputEventPanGesture
		if pg.shift_pressed:
			rig.orbit(pg.delta.x * 6.0, pg.delta.y * 6.0)
		else:
			rig.pan_pixels(-pg.delta * 9.0)

	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.is_command_or_control_pressed():
			if k.keycode == KEY_S:
				_save_game()
			elif k.keycode == KEY_L:
				_load_game()
			elif k.keycode == KEY_Z:
				_undo_last()
			return
		match k.keycode:
			KEY_1:
				_select_tool(Tool.ROAD)
			KEY_2:
				_select_tool(Tool.HOMES)
			KEY_3:
				_select_tool(Tool.SHOPS)
			KEY_4:
				_select_tool(Tool.INDUSTRY)
			KEY_5, KEY_B:
				_select_tool(Tool.BULLDOZE)
			KEY_6:
				_select_tool(Tool.POWER)
			KEY_7:
				_select_tool(Tool.UTILITY)
			KEY_8:
				_select_tool(Tool.PARK)
			KEY_9:
				_select_tool(Tool.GRID)
			KEY_0:
				_select_tool(Tool.SERVICE)
			KEY_MINUS:
				_select_tool(Tool.LEISURE)
			KEY_EQUAL:
				_select_tool(Tool.TRANSPORT)
			KEY_Z:
				_select_tool(Tool.DISTRICT)
			KEY_TAB:
				if _has_picker():
					_set_item((_item_index() + 1) % _picker_size())
				else:
					_set_density((current_density + 1) % 3)
			KEY_M:
				hud.toggle_build_menu()
			KEY_ESCAPE:
				_cancel_drag()
			KEY_SPACE:
				_set_speed(1 if speed == 0 else 0)
			KEY_F:
				_set_speed(Settings.FAST_SPEED)
			KEY_H:
				hud.help_panel.visible = not hud.help_panel.visible
			KEY_O:
				_set_overlay((world.overlay + 1) % WorldView.Overlay.size())
			KEY_C:
				# The Services view, then each service in turn: all, police, fire, schools, hospitals.
				if world.overlay != WorldView.Overlay.SERVICES:
					_set_overlay(WorldView.Overlay.SERVICES)
				else:
					_set_service_filter((world.service_filter + 2) % 5 - 1)


func _process(delta: float) -> void:
	# Keyboard camera: WASD / arrows to move, Q and E to turn.
	var dir := Vector2.ZERO
	if not Input.is_key_pressed(KEY_META) and not Input.is_key_pressed(KEY_CTRL) and not hud.is_modal():
		if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir.x += 1
		if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir.y += 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir.y -= 1
		if Input.is_physical_key_pressed(KEY_Q):
			rig.turn(-1.6 * delta)
		if Input.is_physical_key_pressed(KEY_E):
			rig.turn(1.6 * delta)
	if dir != Vector2.ZERO:
		rig.pan_direction(dir.normalized(), delta)
	world.set_view_distance(rig.distance)

	# A button let go over the toolbar never reaches _unhandled_input: catch it here.
	if painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		painting = false
		_finish_drag()
	if orbiting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		orbiting = false
	if dragging_map and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		dragging_map = false
	# When the camera moves, a different tile is under the (still) mouse; unless
	# the mouse is on the interface, which hides the map under it.
	var cam_xf := rig.camera.global_transform
	if cam_xf != _camera_seen:
		_camera_seen = cam_xf
		if _mouse_at.x >= 0.0 and get_viewport().gui_get_hovered_control() == null:
			_update_hover(_mouse_at)

	# Time of day (only moves while the game is running).
	if day_cycle:
		# Nights pass about three times faster than days.
		var rate := 1.0 + world.clock_night * 2.0
		time_of_day = fmod(time_of_day + delta * speed * rate / Settings.DAY_SECONDS, 1.0)
	world.set_time_of_day(time_of_day)
	hud.set_clock(_clock_text())
	traffic.update(delta * speed, rig.target, rig.distance)
	world.blink(fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.7)

	# The game clock: one simulation step per game month.
	if speed > 0:
		clock += delta * speed
		if clock >= Settings.MONTH_SECONDS:
			clock = 0.0
			sim.tick()
			_ground_dirty = true
			# Only rebuild the buildings when something actually grew or shrank.
			if not sim.grew.is_empty() or not sim.shrank.is_empty():
				_buildings_dirty = true
			_refresh_hud()
			if not sim.burned.is_empty():
				var n := sim.burned.size()
				hud.flash("Fire! %d %s burned down. A fire station nearby would stop that." % [
					n, "building" if n == 1 else "buildings"])
			elif not sim.abandoned_now.is_empty():
				var gone := sim.abandoned_now.size()
				hud.flash("%d %s abandoned. Point at one to see why, or bulldoze it." % [
					gone, "building was" if gone == 1 else "buildings were"])
			elif not sim.new_letters.is_empty():
				var letter := sim.letter_by_id(sim.new_letters[0])
				hud.flash("A letter from %s (%s): open it from the envelope, top left." % [
					String(letter.get("from", "")), String(letter.get("company", ""))])
			elif not sim.news.is_empty():
				hud.flash(sim.news[0])

	# Redraw at most once a frame, however many tiles changed. Roads, power lines
	# and woods only change when the layout does. (Traffic watches for itself.)
	if _ground_dirty:
		_ground_dirty = false
		var layout_changed := sim.layout_version != _layout_seen
		_layout_seen = sim.layout_version
		world.refresh_ground(layout_changed)
	if _buildings_dirty and not painting:
		_buildings_dirty = false
		world.refresh_buildings()


func _mouse_ground() -> Vector3:
	var t := hover
	if not _in_map(t):
		return Vector3.INF
	return world.ground_point(t)


func _update_hover(screen_pos: Vector2) -> void:
	var cam := rig.camera
	var t := world.pick_tile(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	if t != hover:
		hover = t
		var why := _why_cant_build(hover) if _in_map(hover) else "-"
		world.set_hover(hover, why == "" or why == "-")
		_update_reach_preview()
		if painting:
			_update_drag()
		else:
			_update_info()


# ------------------------------------------------------------------ building

# Every tool works the same way: press, drag to see the preview and the total
# cost, release to build. What the drag covers depends on the tool:
#   Road, power line   a straight run, turning one corner (L-shaped)
#   Zones and parks    a box; or, if the drag starts on a road, both sides of
#                      every road in the box, two plots deep
#   Street grid        a box filled with streets every third tile (100 m blocks)
#   Bulldoze           a box
#   Power plant        the tile under the mouse

func _update_drag() -> void:
	var end := hover if _in_map(hover) else drag_start
	drag_plan = _plan_tiles(drag_start, end)
	var items: Array = []
	var total := 0
	var count := 0
	for p in drag_plan:
		var why := _why_cant_build(p, false)
		if why == "-":
			continue
		var ok := why == ""
		items.append([p, ok])
		if ok:
			total += _tool_cost(p)
			count += 1
	# An airport (or a data centre) has a minimum size: the whole drag is red
	# until it's big enough, then green.
	var airport_short := _too_small()
	var colour: Color = TOOL_COLOURS[current_tool]
	if _sized_drag():
		colour = AIRPORT_OK_COLOUR
		if airport_short != "":
			for item: Array in items:
				item[1] = false
	world.set_preview(items, colour)
	if current_tool == Tool.DEAL and not drag_plan.is_empty():
		var dsize := drag_plan[drag_plan.size() - 1] - drag_plan[0] + Vector2i.ONE
		var dbox := "%s: %d x %d tiles" % [_tool_label(), dsize.x, dsize.y]
		if airport_short != "":
			hud.show_info("%s, but %s. Keep dragging (Esc to cancel)." % [dbox, airport_short])
		else:
			hud.show_info("%s, %d tiles: big enough. Release to build (the company pays)." % [dbox, count])
		return
	if _dragging_airport() and count > 0:
		var size := drag_plan[drag_plan.size() - 1] - drag_plan[0] + Vector2i.ONE   # (a box: first and last corners)
		var box := "Airport: %d x %d tiles" % [size.x, size.y]
		if airport_short != "":
			hud.show_info("%s. Too small: %s. Keep dragging (Esc to cancel)." % [box, airport_short])
		elif total > sim.money:
			hud.show_info("%s, big enough. %s, but you have %s." % [box, Hud.money_text(total), Hud.money_text(sim.money)])
		else:
			hud.show_info("%s, big enough. %s. Release to build, Esc to cancel." % [box, Hud.money_text(total)])
		return
	var tool_name := _tool_label()
	if _has_density():
		var dn: String = Settings.DENSITY_NAMES[current_density]
		tool_name += " (%s density)" % dn
	var what := "%s: %d %s" % [tool_name, count, "tile" if count == 1 else "tiles"]
	if current_tool == Tool.BULLDOZE:
		hud.show_info("%s to clear, %s. Release to clear, Esc to cancel." % [what, Hud.money_text(total)])
	elif total > sim.money:
		hud.show_info("%s, %s. You have %s: it will build as far as the money goes." % [
			what, Hud.money_text(total), Hud.money_text(sim.money)])
	else:
		hud.show_info("%s, %s. Release to build, Esc to cancel." % [what, Hud.money_text(total)])


func _finish_drag() -> void:
	var too_small := _too_small()
	if too_small != "":
		hud.flash("%s: %s. Nothing built." % ["Not right for the data centre" if current_tool == Tool.DEAL
			else "Too small for an airport", too_small])
		_cancel_drag()
		return
	if _dragging_airport() and _plan_cost() > sim.money:
		# Half an airport is no use: build all of it or none.
		hud.flash("Not enough money for the whole airport: it costs %s." % Hud.money_text(_plan_cost()))
		_cancel_drag()
		return
	var built := 0
	var before := {}                   # what each changed tile was, for undo
	var money_before := sim.money
	var what := _tool_label()
	var spots: Array[int] = []
	for p in drag_plan:
		var i := p.y * map_w + p.x
		var state := sim.tile_state(i)
		if _apply_tool(p):
			built += 1
			before[i] = state
			spots.append(i)
	drag_plan.clear()
	world.set_preview([], Color.WHITE)
	if built > 0:
		_remember(what, before, money_before - sim.money)
		if current_tool == Tool.DEAL:
			sim.place_deal(_placing_deal, spots)
			var k := sim.deal_by_id(_placing_deal)
			var problem := sim.deal_problem(k) if k >= 0 else ""
			if k >= 0 and sim.deal_building(k):
				hud.flash("%s: building has started. %s" % [what, "Elon says it'll be done in six months."
					if Companies.is_musk(sim.deals[k]) else "It opens in %d months." % (int(sim.deals[k]["opens"]) - sim.month)])
			else:
				hud.flash("%s built. %s" % [what, "It opens next month." if problem == "" else
					"It won't run yet: %s." % problem])
			_placing_deal = -1
			_select_tool(_tool_before_deal)
		sim.recount()
		_ground_dirty = true
		_buildings_dirty = true
	_refresh_hud()


# ---------------------------------------------------------------------- undo

# Each drag is one step. Undo puts its tiles back as they were and gives the
# money back. Steps are kept for UNDO_MONTHS (it's for mistakes, not a free
# demolition later on); loading or starting a city forgets them.

func _remember(what: String, before: Dictionary, spent: int) -> void:
	_undo.append({"what": what, "month": sim.month, "spent": spent, "tiles": before})
	while _undo.size() > Settings.UNDO_STEPS:
		_undo.pop_front()
	_show_undo()


func _forget_old_undo() -> void:
	while not _undo.is_empty() and sim.month - int(_undo[0]["month"]) > Settings.UNDO_MONTHS:
		_undo.pop_front()


func _undo_last() -> void:
	if painting:
		_cancel_drag()
	_forget_old_undo()
	if _undo.is_empty():
		hud.flash("Nothing to undo.")
		_show_undo()
		return
	var step: Dictionary = _undo.pop_back()
	var before: Dictionary = step["tiles"]
	for i: int in before:
		sim.restore_tile(i, before[i])
	var spent: int = step["spent"]
	sim.money += spent
	sim.recount()
	_ground_dirty = true
	_buildings_dirty = true
	_refresh_hud()
	var n := before.size()
	var back := ", %s back" % Hud.money_text(spent) if spent > 0 else ""
	hud.flash("Undone: %s, %d %s%s." % [String(step["what"]), n, "tile" if n == 1 else "tiles", back])
	_show_undo()


func _show_undo() -> void:
	# The Undo button: what it would undo, or greyed out.
	_forget_old_undo()
	if _undo.is_empty():
		hud.set_undo("")
	else:
		var step: Dictionary = _undo.back()
		var n: int = (step["tiles"] as Dictionary).size()
		hud.set_undo("Undo %s, %d %s (Cmd+Z)" % [String(step["what"]), n, "tile" if n == 1 else "tiles"])


const AIRPORT_OK_COLOUR := Color(0.25, 0.85, 0.35)   # the drag once it's big enough


func _dragging_airport() -> bool:
	return current_tool == Tool.TRANSPORT and _target_tile() == Tile.AIRPORT


func _sized_drag() -> bool:
	# Drags that build all or nothing, red until they're the right size.
	return _dragging_airport() or current_tool == Tool.DEAL


func _too_small() -> String:
	return _deal_too_small() if current_tool == Tool.DEAL else _airport_too_small()


func _deal_too_small() -> String:
	# "" if the data centre being dragged out has room: at least the deal's
	# tiles, at most twice that, all in the Tech zone. Otherwise what's wrong.
	if current_tool != Tool.DEAL or drag_plan.is_empty():
		return ""
	var k := sim.deal_by_id(_placing_deal)
	if k < 0:
		return "the deal has gone"
	var need: int = sim.deal_scale(sim.deals[k])["tiles"]
	var n := 0
	for p in drag_plan:
		if _why_cant_build(p, false) == "":
			n += 1
	if n < need:
		return "it needs %d tiles of open land in your Tech zone (you have %d)" % [need, n]
	if bool(Settings.PROJECTS[sim.deal_kind(sim.deals[k])].get("near_sea", false)):
		var by_sea := false
		for p in drag_plan:
			if _why_cant_build(p, false) == "" and sim._beside_sea(p.y * map_w + p.x):
				by_sea = true
				break
		if not by_sea:
			return "it has to touch the coast"
	if n > need * 2:
		return "that's too big: at most %d tiles" % (need * 2)
	return ""


func _start_placing(id: int) -> void:
	# After saying yes to a data centre (or Place it in the inbox): drag out its site.
	var k := sim.deal_by_id(id)
	if k < 0:
		return
	_cancel_drag()
	if current_tool != Tool.DEAL:
		_tool_before_deal = current_tool
	_placing_deal = id
	_select_tool(Tool.DEAL)
	hud.flash("Drag out %d tiles in your Tech zone (teal) for the %s." % [
		int(sim.deal_scale(sim.deals[k])["tiles"]), sim.deal_name(k)])


func _plan_cost() -> int:
	# What the tiles of the current drag that can be built would cost.
	var total := 0
	for p in drag_plan:
		if _why_cant_build(p, false) == "":
			total += _tool_cost(p)
	return total


func _airport_too_small() -> String:
	# "" if the airport being dragged out (with any airport it joins on to) is big
	# enough: a runway of AIRPORT_MIN_RUNWAY tiles in a line and AIRPORT_MIN_TILES
	# in all. Otherwise what's missing, e.g. "the runway needs 16 tiles in a line (you have 9)".
	if not _dragging_airport() or drag_plan.is_empty():
		return ""
	var spots := {}
	for p in drag_plan:
		if _why_cant_build(p, false) == "":
			spots[p.y * map_w + p.x] = true
	if spots.is_empty():
		return ""      # (nothing can be built here at all: the usual reasons show)
	# Airport already built next to the drag counts too (making one bigger).
	var queue: Array = spots.keys()
	var head := 0
	while head < queue.size():
		var c: int = queue[head]
		head += 1
		var x := c % map_w
		for n: int in [c - 1 if x > 0 else -1, c + 1 if x < map_w - 1 else -1, c - map_w, c + map_w]:
			if n >= 0 and n < map_w * map_h and not spots.has(n) and sim.tiles[n] == Tile.AIRPORT:
				spots[n] = true
				queue.append(n)
	# The longest straight run, across or down.
	var longest := 0
	for c: int in spots:
		var x := c % map_w
		if x == 0 or not spots.has(c - 1):
			var n := 0
			while x + n < map_w and spots.has(c + n):
				n += 1
			longest = maxi(longest, n)
		if c < map_w or not spots.has(c - map_w):
			var n := 0
			while spots.has(c + n * map_w):
				n += 1
			longest = maxi(longest, n)
	var need_run: int = Settings.AIRPORT_MIN_RUNWAY
	var need_tiles: int = Settings.AIRPORT_MIN_TILES
	var missing: Array[String] = []
	if longest < need_run:
		missing.append("the runway needs %d tiles in a line (you have %d)" % [need_run, longest])
	if spots.size() < need_tiles:
		missing.append("it needs %d tiles in all (you have %d)" % [need_tiles, spots.size()])
	return " and ".join(missing)


func _cancel_drag() -> void:
	painting = false
	drag_plan.clear()
	world.set_preview([], Color.WHITE)
	_update_info()


func _plan_tiles(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	match current_tool:
		Tool.ROAD:
			return _l_path(a, b)
		Tool.GRID:
			return _grid_tiles(a, b)
		Tool.BULLDOZE, Tool.DISTRICT, Tool.DEAL:
			return _box(a, b)
	if GROUPS.has(current_tool):
		# Power lines run like roads; farms, landfill, woodland and golf courses are dragged
		# as a box; everything else is one building on the tile under the mouse.
		var t := _target_tile()
		if t == Tile.POWER_LINE:
			return _l_path(a, b)
		if bool(sim.info(t).get("area", false)):
			return _box(a, b)
		return [b]
	# Zones and parks.
	if sim.tiles[a.y * map_w + a.x] == Tile.ROAD:
		return _roadside(a, b)
	return _box(a, b)


func _box(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			out.append(Vector2i(x, y))
	return out


func _l_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	# Straight along the longer direction first, then one turn to the end point.
	var corner := Vector2i(b.x, a.y) if absi(b.x - a.x) >= absi(b.y - a.y) else Vector2i(a.x, b.y)
	var out: Array[Vector2i] = []
	for p in _straight(a, corner):
		out.append(p)
	for p in _straight(corner, b):
		if p != corner:
			out.append(p)
	return out


func _straight(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var p := a
	out.append(p)
	while p != b:
		p += step
		out.append(p)
	return out


func _grid_tiles(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	# Streets on every third row and column (two 50 m plots between them),
	# plus the far edges, so every plot inside touches a road.
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	var out: Array[Vector2i] = []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if (x - x0) % 3 == 0 or (y - y0) % 3 == 0 or x == x1 or y == y1:
				out.append(Vector2i(x, y))
	return out


func _roadside(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	# Land on both sides of every road in the box, nearest the road first
	# (so if money runs out, the frontages get built first).
	var ring := {}                      # tile -> 1 (beside a road) or 2 (one plot back)
	for r in _box(a, b):
		if sim.tiles[r.y * map_w + r.x] != Tile.ROAD:
			continue
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var p := r + Vector2i(dx, dy)
				if not _in_map(p) or sim.tiles[p.y * map_w + p.x] == Tile.ROAD:
					continue
				var d: int = maxi(absi(dx), absi(dy))
				if d == 0:
					continue
				if not ring.has(p) or int(ring[p]) > d:
					ring[p] = d
	var out: Array[Vector2i] = []
	for want: int in [1, 2]:
		for p: Vector2i in ring:
			if int(ring[p]) == want:
				out.append(p)
	return out


func _apply_tool(p: Vector2i) -> bool:
	var problem := _why_cant_build(p)
	if problem != "":
		if problem != "-":
			hud.flash(problem)
		return false
	var i := p.y * map_w + p.x
	sim.money -= _tool_cost(p)
	if current_tool == Tool.BULLDOZE:
		sim.set_tile(i, Tile.EMPTY)
	elif current_tool == Tool.DISTRICT:
		sim.set_district(i, _district_choice())
	elif current_tool == Tool.ROAD:
		sim.set_road(i, _road_choice())
	elif current_tool == Tool.GRID:
		sim.set_road(i, 0)
	else:
		sim.set_tile(i, _target_tile(), current_density if _has_density() else 1)
	return true


func _why_cant_build(p: Vector2i, check_money: bool = true) -> String:
	# "" = OK to build; "-" = nothing to do (no message); otherwise the reason.
	var i := p.y * map_w + p.x
	var here := sim.tiles[i]
	if current_tool == Tool.DEAL and here != _target_tile() and water[i] == 0 \
			and sim.district[i] != Settings.TECH_ZONE:
		return "It has to go in your Tech zone."
	if current_tool == Tool.DISTRICT:
		# Districts are free and go over anything on land.
		return "-" if water[i] == 1 or sim.district[i] == _district_choice() else ""
	if current_tool == Tool.BULLDOZE:
		if here == Tile.EMPTY:
			return "-"
	else:
		if here == _target_tile():
			# Same zone again does nothing, unless it changes the density
			# (or, for a road, makes it another kind of road).
			if current_tool == Tool.ROAD:
				if sim.road_kind[i] == _road_choice():
					return "-"
			elif not _has_density() or sim.density[i] == current_density:
				return "-"
		# Everything but roads goes round roads, power lines and power plants
		# rather than replacing them; the street grid only goes on open land.
		# (Bulldoze first to replace.)
		var infrastructure := here == Tile.ROAD or here == Tile.POWER_LINE or sim.makes_power(here)
		if current_tool != Tool.ROAD and infrastructure:
			return "-"
		if current_tool == Tool.GRID and here != Tile.EMPTY:
			return "-"
		if water[i] == 1:
			return "You can't build on water."
		if slope[i] > Settings.MAX_SLOPE_M:
			return "Too steep to build here."
		if sim.is_building(_target_tile()):
			var why := sim.can_build_here(_target_tile(), i)
			if why != "":
				return why
	var cost := _tool_cost(p)
	if check_money and cost > sim.money:
		return "Not enough money: that costs %s." % Hud.money_text(cost)
	return ""


func _base_cost(tool_id: int) -> int:
	match tool_id:
		Tool.ROAD:
			var road_cost: int = Settings.ROAD_COSTS[_road_choice()]
			return road_cost
		Tool.HOMES:
			var homes_cost: int = Settings.HOMES_COSTS[current_density]
			return homes_cost
		Tool.SHOPS:
			var shops_cost: int = Settings.SHOPS_COSTS[current_density]
			return shops_cost
		Tool.OFFICES:
			var offices_cost: int = Settings.OFFICES_COSTS[current_density]
			return offices_cost
		Tool.INDUSTRY:
			return Settings.INDUSTRY_COST
		Tool.BULLDOZE:
			return Settings.BULLDOZE_COST
		Tool.PARK:
			return Settings.PARK_COST
		Tool.GRID:
			return Settings.ROAD_COST
	if GROUPS.has(tool_id):
		return _cost_of(_target_tile())
	return 0


func _cost_of(t: int) -> int:
	# What one tile of a group building costs.
	if t == Tile.POWER_LINE:
		return Settings.POWER_LINE_COST
	if sim.is_service(t):
		var service_cost: int = Settings.SMALL_SERVICE_COSTS[sim.service_of(t)] if sim.service_small(t) \
			else Settings.SERVICE_COSTS[sim.service_of(t)]
		return service_cost
	var cost: int = sim.info(t).get("cost", 0)
	return cost


func _tool_cost(p: Vector2i) -> int:
	var base := _base_cost(current_tool)
	if current_tool == Tool.BULLDOZE:
		return base
	var hill := 1.0 + slope[p.y * map_w + p.x] * Settings.SLOPE_COST_PER_METRE
	return roundi(base * hill)


func _road_choice() -> int:
	# The kind of road the Road tool lays: 0 road, 1 avenue, 2 motorway.
	var kind: int = _choice.get(Tool.ROAD, 0)
	return kind


func _target_tile() -> int:
	# The tile the current tool builds.
	if current_tool == Tool.DEAL:
		var k := sim.deal_by_id(_placing_deal)
		return sim.project_tile(sim.deal_kind(sim.deals[k])) if k >= 0 else Tile.DATA_CENTRE
	if GROUPS.has(current_tool):
		var items: Array = GROUPS[current_tool]
		var picked: int = items[_item_index()]
		return picked
	var t: int = TOOL_TO_TILE.get(current_tool, Tile.EMPTY)
	return t


func _has_picker() -> bool:
	return GROUPS.has(current_tool) or current_tool == Tool.DISTRICT


func _picker_size() -> int:
	if current_tool == Tool.DISTRICT:
		return DISTRICT_ORDER.size()
	var items: Array = GROUPS[current_tool]
	return items.size()


func _district_choice() -> int:
	var d: int = DISTRICT_ORDER[_item_index()]
	return d


func _item_index() -> int:
	var n: int = _choice.get(current_tool, 0)
	return n


func _name_of(t: int) -> String:
	if sim.is_building(t):
		return sim.building_name(t)
	var n: String = TILE_NAMES.get(t, "")
	return n


func _tool_label() -> String:
	if current_tool == Tool.DEAL:
		var k := sim.deal_by_id(_placing_deal)
		return sim.deal_name(k) if k >= 0 else "Data centre"
	if current_tool == Tool.DISTRICT:
		var district_name: String = Settings.DISTRICT_NAMES[_district_choice()]
		return district_name + " district" if _district_choice() == 2 else district_name
	if GROUPS.has(current_tool):
		return _name_of(_target_tile())
	if current_tool == Tool.ROAD:
		var road_name: String = Settings.ROAD_NAMES[_road_choice()]
		return road_name
	var tool_name: String = TOOL_NAMES[current_tool]
	return tool_name


func _set_item(index: int, announce: bool = true) -> void:
	# Pick one building from the current group (or a district type).
	if not _has_picker():
		return
	_choice[current_tool] = index
	_show_group()
	_auto_view()
	_update_reach_preview()
	if announce:
		hud.flash("Painting: %s" % _tool_label() if current_tool == Tool.DISTRICT \
			else "Building: %s" % _name_of(_target_tile()).to_lower())
	if painting:
		_update_drag()
	else:
		_update_info()


# ------------------------------------------------------------- build menu

# Categories down the side of the Build menu: [id, name].
const BUILD_CATEGORIES := [["all", "All"], ["zones", "Zones"], ["roads", "Roads"], ["power", "Power"],
	["utilities", "Utilities"], ["services", "Services"], ["leisure", "Leisure"],
	["transport", "Transport"], ["education", "Education"], ["landmarks", "Landmarks"], ["districts", "Districts"]]
# One-line descriptions for the menu (the hover tooltip has the full story).
const SHORT := {
	"homes_0": "Ranch houses and villas", "homes_1": "Terraces up to tenements", "homes_2": "Flats and towers",
	"shops_0": "Strip malls", "shops_1": "Strip malls up to shops with flats", "shops_2": "Big stores and hotels",
	"offices_0": "Office parks", "offices_1": "Office blocks", "offices_2": "Office towers",
	"industry": "Works and factories", "road": "Joined-up streets", "grid": "Streets in 100 m blocks",
	"avenue": "Wide and tree-lined: more traffic", "motorway": "Fast, for traffic across town",
	"bulldoze": "Clear anything", "park": "Trees and open space",
	"coal": "Cheap power, but smoky", "gas": "Cleaner, twice the power", "nuclear": "Huge output",
	"wind": "Clean power: drag a wind farm", "solar": "Quiet, clean power", "power_line": "Carries power",
	"water_pump": "Water for 400 zone levels", "water_tower": "A small water supply",
	"landfill": "Cheap: drag out a tip", "recycling": "Takes rubbish, cleanly",
	"incinerator": "Burns lots of rubbish; smoky",
	"police": "Safer streets", "fire": "Stops fires spreading", "school": "Families need one",
	"hospital": "Care for a growing town", "police_office": "A village bobby", "fire_small": "One engine, close by",
	"clinic": "A doctor nearby", "golf": "Fairways, greens and bunkers",
	"woodland": "Plant trees: drag out a forest",
	"library": "Books, and better land", "museum": "A big draw for visitors", "stadium": "A football ground",
	"marina": "Yachts by the shore", "town_hall": "The heart of the town",
	"bus_depot": "Plots can sit further from roads", "station": "Visitors arrive by train",
	"harbour": "Ships bring trade", "airport": "Drag out a runway: visitors and trade",
	"big_ben": "The great clock tower", "colosseum": "The ancient amphitheatre", "great_pyramid": "A wonder of the ancient world",
	"liberty": "Torch held high, by the sea", "taj_mahal": "White marble domes", "opera_house": "White sails by the water",
	"eiffel": "The iron tower", "empire_state": "The art deco skyscraper", "college": "Turns residents into tech workers", "university": "Graduates, students and land value",
	"research_park": "Labs that draw big companies", "cbd": "Skyscrapers allowed", "tech_zone": "Its own tax rate, to draw firms", "conservation": "Keeps the old town low",
	"normal": "The usual height rules",
}


func _menu_entries() -> Array:
	# Everything in the Build menu: [id, category, tool, density (-1 = none), choice (-1 = none), tile].
	var out: Array = []
	for d in 3:
		out.append(["homes_%d" % d, "zones", Tool.HOMES, d, -1, Tile.HOMES])
	for d in 3:
		out.append(["shops_%d" % d, "zones", Tool.SHOPS, d, -1, Tile.SHOPS])
	for d in 3:
		out.append(["offices_%d" % d, "zones", Tool.OFFICES, d, -1, Tile.OFFICES])
	out.append(["industry", "zones", Tool.INDUSTRY, -1, -1, Tile.INDUSTRY])
	for k in Settings.ROAD_IDS.size():
		out.append([Settings.ROAD_IDS[k], "roads", Tool.ROAD, -1, k, Tile.ROAD])
	out.append(["grid", "roads", Tool.GRID, -1, -1, Tile.ROAD])
	out.append(["bulldoze", "roads", Tool.BULLDOZE, -1, -1, Tile.EMPTY])
	var group_cats := {Tool.POWER: "power", Tool.UTILITY: "utilities", Tool.SERVICE: "services",
		Tool.LEISURE: "leisure", Tool.TRANSPORT: "transport", Tool.LANDMARK: "landmarks", Tool.EDUCATION: "education"}
	for tool_id: int in group_cats:
		if tool_id == Tool.LEISURE:
			out.append(["park", "leisure", Tool.PARK, -1, -1, Tile.PARK])
		var tiles_in_group: Array = GROUPS[tool_id]
		for k in tiles_in_group.size():
			var t: int = tiles_in_group[k]
			out.append([_item_id(t), group_cats[tool_id], tool_id, -1, k, t])
	for k in DISTRICT_ORDER.size():
		out.append([DISTRICT_IDS[k], "districts", Tool.DISTRICT, -1, k, Tile.EMPTY])
	return out


func _item_id(t: int) -> String:
	if sim.is_building(t):
		var key: String = Simulation.BUILDING_KEYS[t]
		return key
	if sim.is_service(t):
		var word: String = Settings.SMALL_SERVICE_WORDS[sim.service_of(t)] if sim.service_small(t) \
			else Settings.SERVICE_WORDS[sim.service_of(t)]
		return word
	return "power_line" if t == Tile.POWER_LINE else ""


func _menu_items() -> Array:
	# What the Build menu shows: name, one-liner, price, and whether it's locked yet.
	var items: Array = []
	for e: Array in _menu_entries():
		var id: String = e[0]
		var tool_id: int = e[2]
		var density: int = e[3]
		var t: int = e[5]
		var item_name := ""
		var about := ""
		var price := ""
		var locked := false
		if tool_id == Tool.HOMES or tool_id == Tool.SHOPS or tool_id == Tool.OFFICES:
			var level_word: String = ["Low-density", "Medium-density", "High-density"][density]
			item_name = "%s %s" % [level_word, "homes" if tool_id == Tool.HOMES else (
				"shops" if tool_id == Tool.SHOPS else "offices")]
			about = ["Ranch houses, villas and strip malls; never more than 2 storeys",
				"Terraces and tenements; mansion flats when space runs short",
				"Flats, towers and big stores, as high as land value allows (skyscrapers in a CBD)"][density]
			var costs: Array = Settings.HOMES_COSTS if tool_id == Tool.HOMES else Settings.SHOPS_COSTS
			if tool_id == Tool.OFFICES:
				about = ["Office parks, two storeys at most",
					"Office blocks; taller when space runs short",
					"Office towers, as high as land value allows (skyscrapers in a CBD)"][density] \
					+ ". Clean, well-paid jobs for a bigger town with schools near its homes; offices take workers from industry"
				costs = Settings.OFFICES_COSTS
			price = Hud.money_text(costs[density])
		elif tool_id == Tool.DISTRICT:
			item_name = ["CBD", "Tech zone", "Conservation area", "Normal district"][e[4]]
			about = DISTRICT_ABOUT[e[4]]
			price = "Free"
		elif sim.is_building(t) or sim.is_service(t) or t == Tile.POWER_LINE:
			item_name = _name_of(t)
			price = Hud.money_text(_cost_of(t))
			if sim.is_building(t):
				about = sim.info(t).get("about", "")
				var unlock: int = sim.info(t).get("unlock", 0)
				if sim.population < unlock:
					locked = true
				if bool(sim.info(t).get("area", false)):
					price += " / tile"
			elif sim.is_service(t):
				about = ["Police: in a bigger town, homes and shops without police grow at half speed",
					"Fire: stops buildings nearby burning down",
					"Schools: in a bigger town, families need one nearby to move into anything bigger than terraces",
					"Hospitals: in a bigger town, homes without one grow at half speed"][sim.service_of(t)]
				if sim.service_small(t):
					about += ". A small one: cheap, but it reaches about half as far"
			else:
				about = "Carries power across open land (roads and buildings carry it too)"
				price += " / tile"
		elif tool_id == Tool.ROAD:
			item_name = Settings.ROAD_NAMES[e[4]]
			about = ["Roads run straight and can turn one corner",
				"Two lanes each way with trees down the middle: takes nearly three times the traffic of a road, and drivers prefer it. Drag over a road to widen it",
				"Three lanes each way: takes eight times the traffic of a road and is the quickest way across town. Plots can't open onto it, so join it to ordinary roads; it's noisy to live beside"][e[4]]
			price = Hud.money_text(Settings.ROAD_COSTS[e[4]]) + " / tile"
		else:
			item_name = TOOL_NAMES[tool_id]
			about = {Tool.INDUSTRY: "Jobs, but it lowers land value nearby",
				Tool.ROAD: "Roads run straight and can turn one corner",
				Tool.GRID: "Drag a box to lay streets every third tile",
				Tool.BULLDOZE: "Clears anything you drag over",
				Tool.PARK: "Keeps its trees and gains more; raises land value"}[tool_id]
			price = Hud.money_text(_base_cost(tool_id))
			if tool_id != Tool.INDUSTRY:
				price += " / tile"
		var desc: String = SHORT.get(id, "")
		if locked:
			desc = "Needs %s people" % Hud.thousands(int(sim.info(t).get("unlock", 0)))
		items.append({"id": id, "cat": e[1], "name": item_name, "desc": desc, "about": about,
			"price": price, "locked": locked})
	return items


func _current_item_id() -> String:
	for e: Array in _menu_entries():
		if e[2] != current_tool:
			continue
		if e[3] >= 0 and e[3] != current_density:
			continue
		if e[4] >= 0 and e[4] != _item_index():
			continue
		var id: String = e[0]
		return id
	return ""


func _choose_item(id: String) -> void:
	# Something picked in the Build menu: switch to its tool, density or building.
	for e: Array in _menu_entries():
		if e[0] != id:
			continue
		var tool_id: int = e[2]
		if e[3] >= 0:
			current_density = e[3]
		if e[4] >= 0:
			_choice[tool_id] = e[4]
		_select_tool(tool_id)
		hud.flash("%s: %s" % ["Painting" if tool_id == Tool.DISTRICT else "Building", _menu_name(id)])
		return


func _menu_name(id: String) -> String:
	for item: Dictionary in _menu_items():
		if item["id"] == id:
			var n: String = item["name"]
			return n.to_lower()
	return id


func _show_group() -> void:
	# Keep the Build menu in step: the chosen item lit, and funding for a service.
	hud.set_selected(_current_item_id())
	hud.set_funding(_funding_text() if current_tool == Tool.SERVICE else "")


func _change_funding(step: float) -> void:
	if current_tool != Tool.SERVICE:
		return
	var s := sim.service_of(_target_tile())
	sim.set_funding(s, sim.funding[s] + step)
	_show_group()
	_update_reach_preview()
	_ground_dirty = true          # coverage and land value change
	_refresh_hud()


func _funding_text() -> String:
	var s := sim.service_of(_target_tile())
	var small := sim.service_small(_target_tile())
	var word: String = Settings.SERVICE_WORDS[s]
	var upkeep: float = Settings.SMALL_SERVICE_UPKEEP[s] if small else Settings.SERVICE_UPKEEP[s]
	return "%s funding %d%%  ·  %s a month each  ·  reaches %d m" % [word.capitalize(),
		roundi(sim.funding[s] * 100.0), Hud.money_text(roundi(upkeep * sim.funding[s] * sim.upkeep_scale())),
		sim.service_reach_m(s, cell_size_m, small)]


func _has_density() -> bool:
	return current_tool == Tool.HOMES or current_tool == Tool.SHOPS or current_tool == Tool.OFFICES


func _set_density(d: int) -> void:
	current_density = d
	_show_group()
	var density_word: String = Settings.DENSITY_NAMES[d]
	hud.flash("Zoning %s density" % density_word)
	if painting:
		_update_drag()


func _select_tool(tool_id: int) -> void:
	current_tool = tool_id
	_show_group()
	_auto_view()
	_update_reach_preview()
	if _in_map(hover):
		var why := _why_cant_build(hover)
		world.set_hover(hover, why == "" or why == "-")
	_update_info()


func _auto_view() -> void:
	# Painting districts shows the Districts view (if no other view is on); placing
	# a service shows the Services view with just that service, so you can see
	# where it's missing. Picking another tool goes back to the view before.
	var want := -1
	var filter := -1
	if current_tool == Tool.DISTRICT or current_tool == Tool.DEAL:
		want = WorldView.Overlay.DISTRICTS
	elif current_tool == Tool.SERVICE:
		want = WorldView.Overlay.SERVICES
		filter = sim.service_of(_target_tile())
	if _auto_overlay:
		if want == world.overlay:
			if filter != world.service_filter:
				_set_service_filter(filter)
			return
		_restore_view()
	if want < 0 or (want == WorldView.Overlay.DISTRICTS and world.overlay != WorldView.Overlay.NONE):
		return
	if world.overlay == want and world.service_filter == filter:
		return                        # (already showing it: the player's own choice, so it stays)
	_view_before = [world.overlay, world.service_filter]
	_set_overlay(want)
	if filter >= 0:
		_set_service_filter(filter)
	_auto_overlay = true


func _restore_view() -> void:
	var kind: int = _view_before[0]
	var filter: int = _view_before[1]
	_set_overlay(kind)
	if kind == WorldView.Overlay.SERVICES and filter >= 0:
		_set_service_filter(filter)
	_auto_overlay = false


func _set_overlay(kind: int) -> void:
	_auto_overlay = false
	world.set_overlay(kind)
	_show_overlay_key()


func _set_service_filter(s: int) -> void:
	# The Services view showing one service (0-3: police, fire, school, hospital) or all four (-1).
	if world.overlay != WorldView.Overlay.SERVICES:
		world.set_overlay(WorldView.Overlay.SERVICES)
	world.set_service_filter(s)
	_show_overlay_key()


const SERVICE_PLURAL := ["Police", "Fire stations", "Schools", "Hospitals"]


func _show_overlay_key() -> void:
	# The map view's key in the HUD; for one service, its own title, line and numbers.
	var kind := world.overlay
	var s := world.service_filter
	if kind != WorldView.Overlay.SERVICES or s < 0:
		hud.set_overlay(kind, world.overlay_legend(kind), s)
		return
	var word: String = Settings.SERVICE_WORDS[s]
	# (The distance that counts as covered: a little short of where the cover fades out.)
	var counts_m := roundi(sim.service_cover_tiles(s) * cell_size_m / 10.0) * 10
	var tip := "Where %s reach: each covers %d m round it at %d%% funding (more funding, further)." % [
		"the police" if s == 0 else ("fire stations" if s == 1 else word + "s"), counts_m,
		roundi(sim.funding[s] * 100.0)]
	hud.set_overlay(kind, world.overlay_legend(kind), s, "Services: %s" % SERVICE_PLURAL[s], tip, _service_note(s))


func _service_note(s: int) -> String:
	# "Schools reach 62% of residents · 9 homes can't grow past terraces without one":
	# the same count the advisors give (simulation.gd service_holds_back).
	var r := sim.service_report(s)
	var built: int = r["built"]
	var working: int = r["working"]
	var share: float = r["share"]
	var held: int = r["held"]
	var plural: String = ["Police stations", "Fire stations", "Schools", "Hospitals"][s]
	var first := ""
	if built == 0:
		first = "No %s yet" % plural.to_lower()
	elif share < 0.0:
		first = "Nobody lives in town yet"
	else:
		first = "%s reach %d%% of residents" % [plural, roundi(share * 100.0)]
	if built > working:
		first += " (%d not working)" % (built - working)
	var second := ""
	var from := sim.service_needed_from(s)
	if sim.population < from:
		second = ["homes and shops need police", "fires can start", "homes need a school to grow past terraces",
			"homes need a hospital to grow at full speed"][s] + " from %s people" % Hud.thousands(from)
	else:
		var what: String = ["%d %s at half speed without one" % [held, "plot grows" if held == 1 else "plots grow"],
			"%d %s no fire cover (%s burn down)" % [held, "building has" if held == 1 else "buildings have",
				"it could" if held == 1 else "they could"],
			"%d %s past terraces without one" % [held, "home can't grow" if held == 1 else "homes can't grow"],
			"%d %s at half speed without one" % [held, "home grows" if held == 1 else "homes grow"]][s]
		second = what
	return "%s  ·  %s" % [first, second]


func _update_reach_preview() -> void:
	# Placing a service: a disc round the mouse shows how far it would reach.
	if current_tool == Tool.SERVICE and _in_map(hover):
		world.show_reach(hover, sim.service_cover_tiles(sim.service_of(_target_tile()), sim.service_small(_target_tile())))
	else:
		world.hide_reach()


func _set_day_cycle(on: bool) -> void:
	day_cycle = on
	if not on:
		time_of_day = Settings.START_TIME_OF_DAY + 0.06   # late morning


func _clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func _change_tax(step: float) -> void:
	sim.change_tax(step)
	_refresh_hud()


func _change_tech_tax(step: float) -> void:
	sim.change_tech_tax(step)
	_refresh_hud()


func _answer_letter(id: int, yes: bool, choice: int) -> void:
	# The mayor's answer to a letter (the letter card's buttons).
	var result: Dictionary = sim.answer_letter(id, yes, choice)
	var ok: bool = result.get("ok", false)
	hud.letter_result(ok, String(result.get("text", "")))
	if ok:
		_buildings_dirty = true
		_ground_dirty = true
		_refresh_hud()
		hud.flash(String(result.get("text", "")))
		if result.has("deal"):
			_start_placing(int(result["deal"]))


func _letter_shown(open: bool) -> void:
	# The clock stops while a letter is open on its card.
	if open:
		_cancel_drag()
		_speed_before_letter = speed
		_set_speed(0)
	else:
		_set_speed(_speed_before_letter)


func _set_speed(new_speed: int) -> void:
	speed = new_speed
	hud.set_speed(speed)


# --------------------------------------------------------------- save / load

func _save_game() -> void:
	hud.flash("City saved." if _write_save(save_file) else "Save failed.")


func _write_save(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var data := sim.to_save()
	data["version"] = SAVE_VERSION
	data["map"] = map_name
	data["width"] = map_w
	data["height"] = map_h
	f.store_string(JSON.stringify(data))
	f.close()
	return true


func _load_game(path: String = "", done_text: String = "City loaded.") -> void:
	if path == "":
		path = save_file
	if not FileAccess.file_exists(path):
		hud.flash("No saved city yet.")
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY \
			or int(data.get("width", 0)) != map_w \
			or int(data.get("height", 0)) != map_h:
		hud.flash("That save doesn't match this map.")
		return
	var saved_map := str(data.get("map", map_name))
	if saved_map != map_name:
		hud.flash("That city was built on %s's map, not %s's, so it can't be loaded here." % [saved_map, map_name])
		return
	_cancel_drag()
	hud.close_letter()
	hud.close_inbox()
	sim.from_save(data)
	_undo.clear()
	clock = 0.0
	world.refresh_all()
	_layout_seen = sim.layout_version
	_refresh_hud()
	hud.flash(done_text)


func _load_example(id: String) -> void:
	# A ready-made city from the examples folder (Settings.EXAMPLES; made by
	# tools/make_examples.sh). It replaces the city on the map, like Load; your
	# own save file is only changed if you then press Save.
	for item: Dictionary in Settings.EXAMPLES:
		if String(item["id"]) == id:
			_load_game(EXAMPLES_DIR.path_join(id + ".json"), "Loaded %s." % String(item["name"]))


func _ask_new_city(first: bool) -> void:
	# Open the New city dialog (pick a difficulty), with the clock paused behind it.
	# first: the game has just opened on a blank map.
	if hud.is_modal():
		return
	_cancel_drag()
	_speed_before_dialog = 1 if first else speed
	_set_speed(0)
	hud.open_new_city(first)


func _new_city_chosen(level: int) -> void:
	_new_city(level)
	_set_speed(_speed_before_dialog)


func _new_city_cancelled() -> void:
	# On the first launch the map is already blank on Normal, so that's what you get.
	_set_speed(_speed_before_dialog)


func _new_city(level: int = Settings.DEFAULT_DIFFICULTY) -> void:
	_cancel_drag()
	hud.close_inbox()
	sim.reset(level)
	_undo.clear()
	clock = 0.0
	world.refresh_all()
	_layout_seen = sim.layout_version
	_refresh_hud()
	hud.flash("New city on %s: %s to start with." % [sim.difficulty_name(), Hud.money_text(sim.money)])


func _borrow(amount: int) -> void:
	var why := sim.borrow_problem(amount)
	if why != "":
		hud.flash("Can't borrow %s: %s." % [Hud.money_text(amount), why])
		return
	sim.borrow(amount)
	_refresh_hud()
	hud.flash("Borrowed %s. You owe %s, paid back %s a month." % [Hud.money_text(amount),
		Hud.money_text(sim.debt), Hud.money_text(sim.loan_payment())])


func _repay(amount: int) -> void:
	var why := sim.repay_problem(amount)
	if why != "":
		hud.flash("Can't repay: %s." % why)
		return
	var paid := sim.repay(amount)
	_refresh_hud()
	if sim.debt > 0:
		hud.flash("Repaid %s. You still owe %s." % [Hud.money_text(paid), Hud.money_text(sim.debt)])
	else:
		hud.flash("Repaid %s. The loan is cleared." % Hud.money_text(paid))


# ----------------------------------------------------------------------- HUD

func _refresh_hud() -> void:
	var net := sim.last_balance()          # taxes - upkeep - loan payments
	hud.show_city(sim, Hud.money_text(sim.money), ("+" if net >= 0 else "") + Hud.money_text(net),
		Hud.money_text(sim.last_income), Hud.money_text(sim.last_upkeep))
	hud.set_items(_menu_items())      # prices and locks change as the town grows
	hud.set_advice(Advisors.tips(sim), sim.month)
	_show_group()
	if world.overlay == WorldView.Overlay.SERVICES and world.service_filter >= 0:
		_show_overlay_key()         # (its numbers change as the town does)
	_show_undo()                    # (steps run out after a year)
	_update_info()


func _update_info() -> void:
	if hud.info_label == null:
		return
	if not _in_map(hover):
		hud.show_info("%s selected. Point at the map to see what's there." % _tool_label())
		return
	var i := hover.y * map_w + hover.x
	var ground := "Sea" if water[i] == 1 else "%.0f m above sea level" % heights[i]
	var problem := _why_cant_build(hover)
	var action := "%s here costs %s" % [_tool_label(), Hud.money_text(_tool_cost(hover))]
	var state := 0                     # (for the HUD: 0 can build, 1 can't, 2 nothing to do)
	if problem == "-":
		action = "Nothing to clear" if current_tool == Tool.BULLDOZE else "Already built"
		state = 2
	elif problem != "":
		action = problem
		state = 1
	elif current_tool == Tool.SERVICE:
		action += "  ·  " + _service_gain_text(sim.service_of(_target_tile()), i, sim.service_small(_target_tile()))
	# Which services reach a zone plot (red: missing, and the plot needs it).
	var marks: Array = []
	if sim.is_zone(sim.tiles[i]):
		for s: int in 4:
			marks.append(2 if sim.covered(s, i) else (0 if sim.service_matters(s, i) else 1))
	hud.show_query(_tile_text(i), ground, action, state, marks)


func _service_gain_text(s: int, i: int, small: bool = false) -> String:
	# What a new service building here would add: "would reach 14 homes with no school (420 people), 9 held back now".
	var g := sim.service_gain(s, i, small)
	var plots: int = g["plots"]
	var people: int = g["people"]
	var held: int = g["held"]
	var noun: String = ["homes and shops", "plots", "homes", "homes"][s]
	var word: String = ["police", "fire cover", "school", "hospital"][s]
	if plots == 0:
		return "would reach no %s without %s" % [noun, "fire cover" if s == 1 else ("police" if s == 0 else "a " + word)]
	var text := "would reach %d %s with no %s" % [plots, noun, word]
	if people > 0:
		text += " (%s people)" % Hud.thousands(people)
	if held > 0:
		text += ", %d held back now" % held
	return text


func _tile_text(i: int) -> String:
	var t := sim.tiles[i]
	if t == Tile.WOODLAND:
		return "Woodland (planted trees: cleans the air a little and raises land value nearby; no upkeep)\nLand value %s   ·   %s" % [
			sim.land_value_word(i), sim.pollution_word(i)]
	if sim.is_project_tile(t):
		return _project_text(i)
	if sim.is_building(t):
		var about: String = sim.info(t).get("about", "")
		var reach := sim.pollution_reach_m(t, cell_size_m)
		if reach > 0:
			about += " (pollutes the air up to %d m away)" % reach
		var text := "%s: %s\n%s" % [sim.building_name(t), sim.building_status(i), about]
		if Simulation.RUBBISH_ORDER.has(t) and sim.building_working(i):
			text += "\n" + _rubbish_text(i)
		if t == Tile.COLLEGE or t == Tile.UNIVERSITY or t == Tile.RESEARCH_PARK:
			text += "\nTech workers: %s (%d%% of residents), %s" % [Hud.thousands(sim.tech_workers()),
				roundi(maxf(sim.tech_share, 0.0) * 100.0), sim.tech_trend()]
			if t == Tile.UNIVERSITY:
				text += " · %s students need homes" % Hud.thousands(sim.students())
			elif t == Tile.RESEARCH_PARK:
				text += " · big companies %d%% keener" % roundi((sim.research_boost() - 1.0) * 100.0)
		return text
	if t == Tile.PARK:
		return "Park (trees and open space; costs £%d a month to look after)" % roundi(Settings.PARK_UPKEEP * sim.upkeep_scale())
	if sim.is_service(t):
		var s: int = sim.service_of(t)
		var text := "%s: %s\nReaches %d m at %d%% funding" % [TILE_NAMES[t], sim.service_status(i),
			sim.service_reach_m(s, cell_size_m, sim.service_small(t)), roundi(sim.funding[s] * 100.0)]
		var r := sim.service_reach(i)
		var plots: int = r["plots"]
		if plots > 0:
			var people: int = r["people"]
			var alone: int = r["alone"]
			text += "  ·  covers %d %s%s" % [plots, "plot" if plots == 1 else "plots",
				" (%s people)" % Hud.thousands(people) if people > 0 else ""]
			var word: String = Settings.SERVICE_WORDS[s]
			if alone < plots:
				text += ", %d of them no other %s reaches" % [alone, "police station" if s == 0 else (
					"fire station" if s == 1 else word)]
		return text
	if t == Tile.ROAD:
		return _road_text(i)
	if not sim.is_zone(t):
		if t == Tile.EMPTY and water[i] == 0:
			var where := "" if sim.district[i] == 0 else ", %s" % sim.district_name(i).to_lower()
			if sim.pollution_band(i) >= 2:
				where += ", %s" % sim.pollution_word(i)
			return "Open land (land value %s%s)" % [sim.land_value_word(i), where]
		return TILE_NAMES[t]
	var kind: String = TILE_NAMES[t]
	if t != Tile.INDUSTRY:
		kind += " (%s density)" % sim.density_name(i)
	var text := "%s, level %d of %d%s: %s" % [kind, sim.levels[i], sim.max_level(i),
		_stage_words(t, sim.stage(i)), sim.zone_status(i)]
	if sim.is_abandoned(i):
		# Boarded up: nobody lives or works here and it pays no tax.
		text = "Abandoned — %s\n%s, level %d of %d%s: empty and boarded up, pays no tax (bulldoze it, or it's done up once things improve)" % [
			sim.abandoned_reason(i), kind, sim.levels[i], sim.max_level(i), _stage_words(t, sim.stage(i))]
	text += "\nLand value %s" % sim.land_value_word(i)
	if sim.district[i] != 0:
		text += "   ·   %s" % sim.district_name(i)
	var startup := sim.is_startup(i)
	if startup != "":
		text += "\nStart-up: %s, backed by the town" % startup
	if t != Tile.INDUSTRY and sim.pollution_band(i) >= 2:
		text += "   ·   %s" % sim.pollution_word(i)
	if t == Tile.HOMES:
		text += "   ·   homes here worth about %s" % Hud.money_text(sim.home_price(i))
		if sim.campus_price_rise() >= 0.01:
			text += " (up %d%% with tech salaries)" % roundi(sim.campus_price_rise() * 100.0)
	return text


func _project_text(i: int) -> String:
	# "Amazon data centre (standard): running, servers humming" and its terms.
	var k := -1
	for d: int in sim.deals.size():
		for t in sim.deals[d]["tiles"]:
			if int(t) == i:
				k = d
	if k < 0:
		return "%s: %s" % [sim.building_name(sim.tiles[i]), sim.building_status(i)]
	var deal: Dictionary = sim.deals[k]
	var scale: Dictionary = sim.deal_scale(deal)
	var text := "%s: %s\nUses %s power and %s water · %s jobs" % [sim.deal_name(k), sim.building_status(i),
		Hud.thousands(sim.deal_power(deal)), Hud.thousands(int(scale["water"])), Hud.thousands(int(scale["jobs"]))]
	var years_left: int = ceili(int(deal.get("break_left", 0)) / 12.0)
	if not bool(deal.get("opened", false)):
		text += " · pays %s when it opens" % Hud.money_text(int(deal.get("investment", 0)))
	elif years_left > 0:
		text += " · no tax for %d more %s" % [years_left, "year" if years_left == 1 else "years"]
	else:
		text += " · pays %s tax a month" % Hud.money_text(int(scale["tax"]))
	if bool(deal.get("priority", false)):
		text += "\nGets power before homes when the grid runs short"
	if sim.tiles[i] == Tile.DATA_CENTRE:
		text += "\nIt hums: lowers land value nearby"
	elif sim.tiles[i] == Tile.LAUNCH_SITE:
		text += "\nTourists come to watch (%d launches so far) · nobody may live within %d tiles: homes there can't grow" % [
			int(deal.get("launches", 0)), int(scale.get("zone", 0))]
	elif sim.tiles[i] == Tile.AI_DATA_CENTRE:
		text += "\nIt hums, and it always wants more: uses %s power now (x%.2f since it opened; no's so far: %d of %d)" % [
			Hud.thousands(sim.deal_power(deal)), float(deal.get("power_x", 1.0)), int(deal.get("refusals", 0)), Settings.AI_REFUSALS]
	elif sim.tiles[i] == Tile.TECH_CAMPUS:
		text += "\nWell-paid staff push house prices up across town (up %d%% now)" % roundi(sim.campus_price_rise() * 100.0)
	else:
		text += "\nLorries and a little smoke: lowers land value nearby"
	return text


func _rubbish_text(i: int) -> String:
	# How full a landfill (all its joined-up tiles), recycling centre or incinerator is:
	# "This landfill (12 tiles) takes 24,000: 78% full, 22% to spare".
	var t := sim.tiles[i]
	var plots := 1
	if t == Tile.LANDFILL:
		plots = 0
		for n in _joined_tiles(i):
			if sim.building_working(n):    # (tiles too far from a road take nothing)
				plots += 1
	var per: int = sim.info(t).get("rubbish", 0)
	var used := sim.rubbish_use_of(t)
	var full := roundi(used * 100.0)
	var what := "This landfill (%d %s)" % [plots, "tile" if plots == 1 else "tiles"] if t == Tile.LANDFILL else "It"
	var text := "%s takes the rubbish of %s residents: %d%% full, %d%% to spare" % [
		what, Hud.thousands(per * plots), full, 100 - full]
	if full >= 100 and sim.rubbish_shortfall() > 0.0:
		text += " (the town needs more)"
	return text


func _joined_tiles(i: int) -> Array[int]:
	# The tiles of the same kind joined to this one (side by side), this one included.
	var t := sim.tiles[i]
	var seen := {i: true}
	var out: Array[int] = [i]
	var head := 0
	while head < out.size():
		var c := out[head]
		head += 1
		var x := c % map_w
		for n: int in [c - 1 if x > 0 else -1, c + 1 if x < map_w - 1 else -1, c - map_w, c + map_w]:
			if n >= 0 and n < map_w * map_h and not seen.has(n) and sim.tiles[n] == t:
				seen[n] = true
				out.append(n)
	return out


func _road_text(i: int) -> String:
	# "Road — busy: about 1,200 trips a day", and what to do about heavy traffic.
	var trips := sim.traffic_at(i)
	var word := sim.traffic_word(i)
	var text := "%s — %s%s" % [sim.road_name(i), word.left(1).to_upper(), word.substr(1)]
	if trips < 50.0:
		text += ": hardly any traffic"
	else:
		text += ": about %s trips a day (it takes %s)" % [Hud.thousands(_rounded_trips(trips)),
			Hud.thousands(roundi(sim.road_capacity(sim.road_kind[i])))]
	var fix := sim.traffic_fix(i)
	if fix != "":
		text += "\n%s traffic: %s" % ["Jammed" if sim.traffic_band(i) >= 3 else "Heavy", fix]
	return text


static func _rounded_trips(n: float) -> int:
	# Two significant figures at most: 1,234 -> 1,200; 87 -> 90; 23,456 -> 23,000.
	var step := 10.0
	while n >= step * 100.0:
		step *= 10.0
	return roundi(n / step) * roundi(step)


func _stage_words(t: int, s: int) -> String:
	# What the buildings on a plot are, for the hover text.
	var homes := ["", "houses", "houses and terraces", "tenements", "mansion flats", "modern flats", "towers",
		"skyscraper apartments", "landmark tower"]
	var shops := ["", "strip mall", "strip mall", "shops with flats", "big stores", "department stores",
		"shopping centre and hotel", "hotel skyscraper", "landmark hotel tower"]
	var offices := ["", "office park", "office park", "office chambers", "office blocks", "modern offices",
		"office tower", "office skyscraper", "landmark office tower"]
	var works := ["", "small works", "factory", "large factory"]
	var words: String = ""
	match t:
		Tile.HOMES:
			words = homes[s]
		Tile.SHOPS:
			words = shops[s]
		Tile.INDUSTRY:
			words = works[s]
		Tile.OFFICES:
			words = offices[s]
	return "" if words == "" else " (" + words + ")"


func _in_map(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < map_w and t.y < map_h
