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
const Cars = preload("res://scripts/cars.gd")
const Advisors = preload("res://scripts/advisors.gd")

const MAP_FILE := "res://map/troon_map.json"
const SAVE_FILE := "user://troon_save.json"
const SAVE_VERSION := 3

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE, PARK,
	POLICE, FIRE, SCHOOL, HOSPITAL,
	WIND, SOLAR, GAS, NUCLEAR, WATER_PUMP, WATER_TOWER, LANDFILL, RECYCLING,
	GOLF, LIBRARY, MUSEUM, STADIUM, MARINA, TOWN_HALL, BUS_DEPOT, STATION, HARBOUR }   # same order as simulation.gd
enum Tool { ROAD, HOMES, SHOPS, INDUSTRY, BULLDOZE, POWER, UTILITY, PARK, GRID, SERVICE, LEISURE, TRANSPORT,
	DISTRICT }

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
}
const TOOL_KEYS := {
	Tool.ROAD: "1", Tool.HOMES: "2", Tool.SHOPS: "3", Tool.INDUSTRY: "4", Tool.BULLDOZE: "5",
	Tool.POWER: "6", Tool.UTILITY: "7", Tool.PARK: "8", Tool.GRID: "9", Tool.SERVICE: "0",
	Tool.LEISURE: "-", Tool.TRANSPORT: "=", Tool.DISTRICT: "Z",
}
# The District tool's picker, in order: CBD, conservation area, back to normal.
const DISTRICT_ORDER := [2, 1, 0]
const DISTRICT_ABOUT := [
	"Central business district: high-density plots can become skyscrapers (with 8,000 people and a station or bus depot nearby). Raises land value.",
	"Conservation area: nothing taller than four storeys, to keep the old town's character. A little extra land value.",
	"Normal: the usual height rules for each density."]
# Tools that open a picker of several buildings (Tab or the buttons choose one).
const GROUPS := {
	Tool.POWER: [Tile.POWER_PLANT, Tile.GAS, Tile.NUCLEAR, Tile.WIND, Tile.SOLAR, Tile.POWER_LINE],
	Tool.UTILITY: [Tile.WATER_PUMP, Tile.WATER_TOWER, Tile.LANDFILL, Tile.RECYCLING],
	Tool.SERVICE: [Tile.POLICE, Tile.FIRE, Tile.SCHOOL, Tile.HOSPITAL],
	Tool.LEISURE: [Tile.GOLF, Tile.LIBRARY, Tile.MUSEUM, Tile.STADIUM, Tile.MARINA, Tile.TOWN_HALL],
	Tool.TRANSPORT: [Tile.BUS_DEPOT, Tile.STATION, Tile.HARBOUR],
}
const TOOL_TO_TILE := {
	Tool.ROAD: Tile.ROAD,
	Tool.HOMES: Tile.HOMES,
	Tool.SHOPS: Tile.SHOPS,
	Tool.INDUSTRY: Tile.INDUSTRY,
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
}
const TILE_NAMES := {
	Tile.EMPTY: "Open land",
	Tile.ROAD: "Road",
	Tile.HOMES: "Homes",
	Tile.SHOPS: "Shops",
	Tile.INDUSTRY: "Industry",
	Tile.POWER_PLANT: "Power plant",
	Tile.POWER_LINE: "Power line",
	Tile.PARK: "Park",
	Tile.POLICE: "Police station",
	Tile.FIRE: "Fire station",
	Tile.SCHOOL: "School",
	Tile.HOSPITAL: "Hospital",
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
var cars := Cars.new()
var speed := 1
var clock := 0.0
var time_of_day := Settings.START_TIME_OF_DAY
var day_cycle := true

# --- Interaction ---
var current_tool: int = Tool.ROAD
var current_density: int = 1          # 0 = low, 1 = medium, 2 = high (homes and shops)
var _choice := {}                      # group tool -> which of its buildings is picked
var _auto_overlay := false            # the Districts view was switched on by the District tool
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


func _ready() -> void:
	# Tile numbers are shared by several scripts; make sure they all agree.
	assert(Tile.keys() == Simulation.Tile.keys(), "game3d.gd Tile list differs from simulation.gd")
	assert(Tile.keys() == WorldView.Tile.keys(), "world3d.gd Tile list differs from simulation.gd")
	assert(Tile.keys() == Cars.Tile.keys(), "cars.gd Tile list differs from simulation.gd")
	assert(Simulation.Growth.keys() == WorldView.Growth.keys(), "world3d.gd Growth list differs from simulation.gd")
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

	add_child(cars)
	cars.setup(world, sim)

	add_child(hud)
	hud.build(BUILD_CATEGORIES, {
		Tile.HOMES: [TOOL_COLOURS[Tool.HOMES], "Homes"],
		Tile.SHOPS: [TOOL_COLOURS[Tool.SHOPS], "Shops"],
		Tile.INDUSTRY: [TOOL_COLOURS[Tool.INDUSTRY], "Industry"],
	}, sim)
	hud.tool_chosen.connect(_select_tool)
	hud.build_item_chosen.connect(_choose_item)
	hud.set_items(_menu_items())
	hud.speed_chosen.connect(_set_speed)
	hud.tax_changed.connect(_change_tax)
	hud.new_city_pressed.connect(_new_city)
	hud.save_pressed.connect(_save_game)
	hud.load_pressed.connect(_load_game)
	hud.day_cycle_toggled.connect(_set_day_cycle)
	hud.overlay_chosen.connect(_set_overlay)
	hud.funding_changed.connect(_change_funding)

	_select_tool(Tool.ROAD)
	_set_overlay(WorldView.Overlay.NONE)
	_set_speed(1)
	_refresh_hud()
	if map_credits != "":
		hud.flash(map_credits)


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

func _unhandled_input(event: InputEvent) -> void:
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


func _process(delta: float) -> void:
	# Keyboard camera: WASD / arrows to move, Q and E to turn.
	var dir := Vector2.ZERO
	if not Input.is_key_pressed(KEY_META) and not Input.is_key_pressed(KEY_CTRL):
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
	# When the camera moves, a different tile is under the (still) mouse.
	var cam_xf := rig.camera.global_transform
	if cam_xf != _camera_seen:
		_camera_seen = cam_xf
		_update_hover(get_viewport().get_mouse_position())

	# Time of day (only moves while the game is running).
	if day_cycle:
		# Nights pass about three times faster than days.
		var rate := 1.0 + world.night * 2.0
		time_of_day = fmod(time_of_day + delta * speed * rate / Settings.DAY_SECONDS, 1.0)
	world.set_time_of_day(time_of_day)
	hud.set_clock(_clock_text())
	cars.lights_on = world.night > 0.3
	cars.update(delta * speed)
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

	# Redraw at most once a frame, however many tiles changed. Roads, power lines
	# and traffic routes only change when the layout does.
	if _ground_dirty:
		_ground_dirty = false
		var layout_changed := sim.layout_version != _layout_seen
		_layout_seen = sim.layout_version
		world.refresh_ground(layout_changed)
		if layout_changed:
			cars.roads_changed()
		_update_traffic()
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
	world.set_preview(items, TOOL_COLOURS[current_tool])
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
	var built := 0
	for p in drag_plan:
		if _apply_tool(p):
			built += 1
	drag_plan.clear()
	world.set_preview([], Color.WHITE)
	if built > 0:
		sim.recount()
		_ground_dirty = true
		_buildings_dirty = true
	_refresh_hud()


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
		Tool.BULLDOZE, Tool.DISTRICT:
			return _box(a, b)
	if GROUPS.has(current_tool):
		# Power lines run like roads; farms, landfill and golf courses are dragged
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
	else:
		sim.set_tile(i, _target_tile(), current_density if _has_density() else 1)
	return true


func _why_cant_build(p: Vector2i, check_money: bool = true) -> String:
	# "" = OK to build; "-" = nothing to do (no message); otherwise the reason.
	var i := p.y * map_w + p.x
	var here := sim.tiles[i]
	if current_tool == Tool.DISTRICT:
		# Districts are free and go over anything on land.
		return "-" if water[i] == 1 or sim.district[i] == _district_choice() else ""
	if current_tool == Tool.BULLDOZE:
		if here == Tile.EMPTY:
			return "-"
	else:
		if here == _target_tile():
			# Same zone again does nothing, unless it changes the density.
			if not _has_density() or sim.density[i] == current_density:
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
			return Settings.ROAD_COST
		Tool.HOMES:
			var homes_cost: int = Settings.HOMES_COSTS[current_density]
			return homes_cost
		Tool.SHOPS:
			var shops_cost: int = Settings.SHOPS_COSTS[current_density]
			return shops_cost
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
		var service_cost: int = Settings.SERVICE_COSTS[t - Tile.POLICE]
		return service_cost
	var cost: int = sim.info(t).get("cost", 0)
	return cost


func _tool_cost(p: Vector2i) -> int:
	var base := _base_cost(current_tool)
	if current_tool == Tool.BULLDOZE:
		return base
	var hill := 1.0 + slope[p.y * map_w + p.x] * Settings.SLOPE_COST_PER_METRE
	return roundi(base * hill)


func _target_tile() -> int:
	# The tile the current tool builds.
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
	if current_tool == Tool.DISTRICT:
		var district_name: String = Settings.DISTRICT_NAMES[_district_choice()]
		return district_name + " district" if _district_choice() == 2 else district_name
	if GROUPS.has(current_tool):
		return _name_of(_target_tile())
	var tool_name: String = TOOL_NAMES[current_tool]
	return tool_name


func _set_item(index: int, announce: bool = true) -> void:
	# Pick one building from the current group (or a district type).
	if not _has_picker():
		return
	_choice[current_tool] = index
	_show_group()
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
	["transport", "Transport"], ["districts", "Districts"]]
# One-line descriptions for the menu (the hover tooltip has the full story).
const SHORT := {
	"homes_0": "Villas and terraces", "homes_1": "Terraces up to tenements", "homes_2": "Flats and towers",
	"shops_0": "Corner shops", "shops_1": "Parades, shops with flats", "shops_2": "Offices and shopping",
	"industry": "Works and factories", "road": "Joined-up streets", "grid": "Streets in 100 m blocks",
	"bulldoze": "Clear anything", "park": "Trees and open space",
	"coal": "Cheap power, but smoky", "gas": "Cleaner, twice the power", "nuclear": "Huge output",
	"wind": "Clean power: drag a wind farm", "solar": "Quiet, clean power", "power_line": "Carries power",
	"water_pump": "Water for 400 zone levels", "water_tower": "A small water supply",
	"landfill": "Takes the town's rubbish", "recycling": "Takes rubbish, cleanly",
	"police": "Safer streets", "fire": "Stops fires spreading", "school": "Families need one",
	"hospital": "Care for a growing town", "golf": "Fairways, greens and bunkers",
	"library": "Books, and better land", "museum": "A big draw for visitors", "stadium": "A football ground",
	"marina": "Yachts by the shore", "town_hall": "The heart of the town",
	"bus_depot": "Plots can sit further from roads", "station": "Visitors arrive by train",
	"harbour": "Ships bring trade", "cbd": "Skyscrapers allowed", "conservation": "Keeps the old town low",
	"normal": "The usual height rules",
}


func _menu_entries() -> Array:
	# Everything in the Build menu: [id, category, tool, density (-1 = none), choice (-1 = none), tile].
	var out: Array = []
	for d in 3:
		out.append(["homes_%d" % d, "zones", Tool.HOMES, d, -1, Tile.HOMES])
	for d in 3:
		out.append(["shops_%d" % d, "zones", Tool.SHOPS, d, -1, Tile.SHOPS])
	out.append(["industry", "zones", Tool.INDUSTRY, -1, -1, Tile.INDUSTRY])
	out.append(["road", "roads", Tool.ROAD, -1, -1, Tile.ROAD])
	out.append(["grid", "roads", Tool.GRID, -1, -1, Tile.ROAD])
	out.append(["bulldoze", "roads", Tool.BULLDOZE, -1, -1, Tile.EMPTY])
	var group_cats := {Tool.POWER: "power", Tool.UTILITY: "utilities", Tool.SERVICE: "services",
		Tool.LEISURE: "leisure", Tool.TRANSPORT: "transport"}
	for tool_id: int in group_cats:
		if tool_id == Tool.LEISURE:
			out.append(["park", "leisure", Tool.PARK, -1, -1, Tile.PARK])
		var tiles_in_group: Array = GROUPS[tool_id]
		for k in tiles_in_group.size():
			var t: int = tiles_in_group[k]
			out.append([_item_id(t), group_cats[tool_id], tool_id, -1, k, t])
	for k in DISTRICT_ORDER.size():
		out.append([["cbd", "conservation", "normal"][k], "districts", Tool.DISTRICT, -1, k, Tile.EMPTY])
	return out


func _item_id(t: int) -> String:
	if sim.is_building(t):
		var key: String = Simulation.BUILDING_KEYS[t]
		return key
	if sim.is_service(t):
		var word: String = Settings.SERVICE_WORDS[t - Tile.POLICE]
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
		if tool_id == Tool.HOMES or tool_id == Tool.SHOPS:
			var level_word: String = ["Low-density", "Medium-density", "High-density"][density]
			item_name = "%s %s" % [level_word, "homes" if tool_id == Tool.HOMES else "shops"]
			about = ["Villas and corner shops; never more than 2 storeys",
				"Terraces and tenements; mansion flats when space runs short",
				"Flats, towers and offices, as high as land value allows (skyscrapers in a CBD)"][density]
			var costs: Array = Settings.HOMES_COSTS if tool_id == Tool.HOMES else Settings.SHOPS_COSTS
			price = Hud.money_text(costs[density])
		elif tool_id == Tool.DISTRICT:
			item_name = ["CBD", "Conservation area", "Normal district"][e[4]]
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
					"Hospitals: in a bigger town, homes without one grow at half speed"][t - Tile.POLICE]
			else:
				about = "Carries power across open land (roads and buildings carry it too)"
				price += " / tile"
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
	var s := _target_tile() - Tile.POLICE
	sim.set_funding(s, sim.funding[s] + step)
	_show_group()
	_ground_dirty = true          # coverage and land value change
	_refresh_hud()


func _funding_text() -> String:
	var s := _target_tile() - Tile.POLICE
	var word: String = Settings.SERVICE_WORDS[s]
	var upkeep: float = Settings.SERVICE_UPKEEP[s]
	return "%s funding %d%%  ·  %s a month each  ·  reaches %d m" % [word.capitalize(),
		roundi(sim.funding[s] * 100.0), Hud.money_text(roundi(upkeep * sim.funding[s])),
		sim.service_reach_m(s, cell_size_m)]


func _has_density() -> bool:
	return current_tool == Tool.HOMES or current_tool == Tool.SHOPS


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
	# Painting districts is easier with the Districts view on.
	if tool_id == Tool.DISTRICT and world.overlay == WorldView.Overlay.NONE:
		_set_overlay(WorldView.Overlay.DISTRICTS)
		_auto_overlay = true
	elif tool_id != Tool.DISTRICT and _auto_overlay:
		_set_overlay(WorldView.Overlay.NONE)
		_auto_overlay = false
	if _in_map(hover):
		var why := _why_cant_build(hover)
		world.set_hover(hover, why == "" or why == "-")
	_update_info()


func _set_overlay(kind: int) -> void:
	_auto_overlay = false
	world.set_overlay(kind)
	hud.set_overlay(kind, world.overlay_legend(kind))


func _set_day_cycle(on: bool) -> void:
	day_cycle = on
	if not on:
		time_of_day = Settings.START_TIME_OF_DAY + 0.06   # late morning


func _update_traffic() -> void:
	# More people, more cars (but always a few once there are roads).
	var wanted := sim.population / Settings.PEOPLE_PER_CAR
	if sim.road_tiles > 0:
		wanted = maxi(wanted, mini(10, sim.road_tiles))
	cars.set_count(mini(wanted, Settings.MAX_CARS))


func _clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func _change_tax(step: float) -> void:
	sim.change_tax(step)
	_refresh_hud()


func _set_speed(new_speed: int) -> void:
	speed = new_speed
	hud.set_speed(speed)


# --------------------------------------------------------------- save / load

func _save_game() -> void:
	var f := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if f == null:
		hud.flash("Save failed.")
		return
	var data := sim.to_save()
	data["version"] = SAVE_VERSION
	data["map"] = map_name
	data["width"] = map_w
	data["height"] = map_h
	f.store_string(JSON.stringify(data))
	f.close()
	hud.flash("City saved.")


func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_FILE):
		hud.flash("No saved city yet.")
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE))
	if typeof(data) != TYPE_DICTIONARY \
			or int(data.get("width", 0)) != map_w \
			or int(data.get("height", 0)) != map_h:
		hud.flash("That save doesn't match this map.")
		return
	_cancel_drag()
	sim.from_save(data)
	clock = 0.0
	world.refresh_all()
	_layout_seen = sim.layout_version
	cars.roads_changed()
	_update_traffic()
	_refresh_hud()
	hud.flash("City loaded.")


func _new_city() -> void:
	_cancel_drag()
	sim.reset()
	clock = 0.0
	world.refresh_all()
	_layout_seen = sim.layout_version
	cars.roads_changed()
	_update_traffic()
	_refresh_hud()
	hud.flash("New city: the map is blank again.")


# ----------------------------------------------------------------------- HUD

func _refresh_hud() -> void:
	var net := sim.last_income - sim.last_upkeep
	hud.show_city(sim, Hud.money_text(sim.money), ("+" if net >= 0 else "") + Hud.money_text(net),
		Hud.money_text(sim.last_income), Hud.money_text(sim.last_upkeep))
	hud.set_items(_menu_items())      # prices and locks change as the town grows
	hud.set_advice(Advisors.tips(sim), sim.month)
	_show_group()
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
	if problem == "-":
		action = "Nothing to clear" if current_tool == Tool.BULLDOZE else "Already built"
	elif problem != "":
		action = problem
	hud.show_info("%s   ·   %s\n%s" % [_tile_text(i), ground, action])


func _tile_text(i: int) -> String:
	var t := sim.tiles[i]
	if sim.is_building(t):
		var about: String = sim.info(t).get("about", "")
		var reach := sim.pollution_reach_m(t, cell_size_m)
		if reach > 0:
			about += " (pollutes the air up to %d m away)" % reach
		return "%s: %s\n%s" % [sim.building_name(t), sim.building_status(i), about]
	if t == Tile.PARK:
		return "Park (trees and open space; costs £%d a month to look after)" % roundi(Settings.PARK_UPKEEP)
	if sim.is_service(t):
		var s: int = t - Tile.POLICE
		return "%s: %s\nReaches %d m at %d%% funding" % [TILE_NAMES[t], sim.service_status(i),
			sim.service_reach_m(s, cell_size_m), roundi(sim.funding[s] * 100.0)]
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
	text += "\nLand value %s   ·   %s" % [sim.land_value_word(i), _services_text(i)]
	if sim.district[i] != 0:
		text += "   ·   %s" % sim.district_name(i)
	if t != Tile.INDUSTRY and sim.pollution_band(i) >= 2:
		text += "   ·   %s" % sim.pollution_word(i)
	if t == Tile.HOMES:
		text += "   ·   homes here worth about %s" % Hud.money_text(sim.home_price(i))
	return text


func _services_text(i: int) -> String:
	# Which services cover this plot, e.g. "nearby: police, school".
	var near: Array[String] = []
	for s in 4:
		if sim.covered(s, i):
			var word: String = Settings.SERVICE_WORDS[s]
			near.append(word)
	if near.is_empty():
		return "no services nearby"
	return "nearby: " + ", ".join(near)


func _stage_words(t: int, s: int) -> String:
	# What the buildings on a plot are, for the hover text.
	var homes := ["", "villas", "villas and terraces", "tenements", "mansion flats", "modern flats", "towers",
		"skyscraper apartments", "landmark tower"]
	var shops := ["", "corner shops", "shop parade", "shops with flats", "offices over shops", "office blocks",
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
	return "" if words == "" else " (" + words + ")"


func _in_map(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < map_w and t.y < map_h
