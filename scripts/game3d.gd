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

const MAP_FILE := "res://map/troon_map.json"
const SAVE_FILE := "user://troon_save.json"

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE, PARK }   # same order as simulation.gd
enum Tool { ROAD, HOMES, SHOPS, INDUSTRY, BULLDOZE, POWER_PLANT, POWER_LINE, PARK, GRID }

const TOOL_NAMES := {
	Tool.ROAD: "Road",
	Tool.HOMES: "Homes",
	Tool.SHOPS: "Shops",
	Tool.INDUSTRY: "Industry",
	Tool.BULLDOZE: "Bulldoze",
	Tool.POWER_PLANT: "Power plant",
	Tool.POWER_LINE: "Power line",
	Tool.PARK: "Park",
	Tool.GRID: "Street grid",
}
const TOOL_TO_TILE := {
	Tool.ROAD: Tile.ROAD,
	Tool.HOMES: Tile.HOMES,
	Tool.SHOPS: Tile.SHOPS,
	Tool.INDUSTRY: Tile.INDUSTRY,
	Tool.POWER_PLANT: Tile.POWER_PLANT,
	Tool.POWER_LINE: Tile.POWER_LINE,
	Tool.PARK: Tile.PARK,
	Tool.GRID: Tile.ROAD,
}
const TOOL_COLOURS := {
	Tool.ROAD: Color(0.45, 0.45, 0.48),
	Tool.HOMES: Color(0.86, 0.36, 0.30),
	Tool.SHOPS: Color(0.26, 0.58, 0.92),
	Tool.INDUSTRY: Color(0.96, 0.70, 0.15),
	Tool.BULLDOZE: Color(0.9, 0.3, 0.3),
	Tool.POWER_PLANT: Color(0.62, 0.45, 0.85),
	Tool.POWER_LINE: Color(0.98, 0.88, 0.25),
	Tool.PARK: Color(0.40, 0.78, 0.36),
	Tool.GRID: Color(0.62, 0.62, 0.66),
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
var painting := false
var orbiting := false
var dragging_map := false
var drag_start := Vector2i(-1, -1)     # where the current drag began
var drag_plan: Array[Vector2i] = []    # tiles the current drag would build on
var hover := Vector2i(-1, -1)
var _ground_dirty := false
var _buildings_dirty := false


func _ready() -> void:
	_load_map()
	_compute_slopes()
	sim.setup(map_w, map_h, water)

	add_child(world)
	world.setup(sim, map_w, map_h, cell_size_m, heights, water)

	rig.bounds = Rect2(Vector2.ZERO, Vector2(map_w, map_h) * cell_size_m)
	rig.ground_height = world.height_at
	rig.target = Vector3(map_w * cell_size_m * 0.45, 0.0, map_h * cell_size_m * 0.5)
	add_child(rig)

	add_child(cars)
	cars.setup(world, sim)

	var tools := []
	for id in TOOL_NAMES:
		tools.append([id, TOOL_NAMES[id], str(id + 1), _price_text(id), TOOL_COLOURS[id]])
	add_child(hud)
	hud.build(tools, {
		Tile.HOMES: [TOOL_COLOURS[Tool.HOMES], "Homes"],
		Tile.SHOPS: [TOOL_COLOURS[Tool.SHOPS], "Shops"],
		Tile.INDUSTRY: [TOOL_COLOURS[Tool.INDUSTRY], "Industry"],
	}, sim)
	hud.tool_chosen.connect(_select_tool)
	hud.density_chosen.connect(_set_density)
	hud.speed_chosen.connect(_set_speed)
	hud.tax_changed.connect(_change_tax)
	hud.new_city_pressed.connect(_new_city)
	hud.save_pressed.connect(_save_game)
	hud.load_pressed.connect(_load_game)
	hud.day_cycle_toggled.connect(_set_day_cycle)

	_select_tool(Tool.ROAD)
	hud.set_density(current_density)
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
				_select_tool(Tool.POWER_PLANT)
			KEY_7:
				_select_tool(Tool.POWER_LINE)
			KEY_8:
				_select_tool(Tool.PARK)
			KEY_9:
				_select_tool(Tool.GRID)
			KEY_TAB:
				_set_density((current_density + 1) % 3)
			KEY_ESCAPE:
				_cancel_drag()
			KEY_SPACE:
				_set_speed(1 if speed == 0 else 0)
			KEY_F:
				_set_speed(Settings.FAST_SPEED)
			KEY_H:
				hud.help_panel.visible = not hud.help_panel.visible


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
			_buildings_dirty = true
			_refresh_hud()

	# Redraw at most once a frame, however many tiles changed.
	if _ground_dirty:
		_ground_dirty = false
		world.refresh_ground()
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
	var tool_name: String = TOOL_NAMES[current_tool]
	if _has_density():
		var dn: String = Settings.DENSITY_NAMES[current_density]
		tool_name += " (%s density)" % dn
	var what := "%s: %d %s" % [tool_name, count, "tile" if count == 1 else "tiles"]
	if current_tool == Tool.BULLDOZE:
		hud.show_info("%s to clear, %s. Release to clear, Esc to cancel." % [what, _money_text(total)])
	elif total > sim.money:
		hud.show_info("%s, %s. You have %s: it will build as far as the money goes." % [
			what, _money_text(total), _money_text(sim.money)])
	else:
		hud.show_info("%s, %s. Release to build, Esc to cancel." % [what, _money_text(total)])


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
		Tool.ROAD, Tool.POWER_LINE:
			return _l_path(a, b)
		Tool.POWER_PLANT:
			return [b]
		Tool.GRID:
			return _grid_tiles(a, b)
		Tool.BULLDOZE:
			return _box(a, b)
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
	var ring1: Array[Vector2i] = []
	var ring2: Array[Vector2i] = []
	var seen := {}
	for r in _box(a, b):
		if sim.tiles[r.y * map_w + r.x] != Tile.ROAD:
			continue
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var p := r + Vector2i(dx, dy)
				if not _in_map(p) or seen.has(p):
					continue
				if sim.tiles[p.y * map_w + p.x] == Tile.ROAD:
					continue
				seen[p] = true
				if maxi(absi(dx), absi(dy)) == 1:
					ring1.append(p)
				else:
					ring2.append(p)
	var out: Array[Vector2i] = []
	for p in ring1:
		out.append(p)
	for p in ring2:
		if not ring1.has(p):
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
	else:
		sim.set_tile(i, TOOL_TO_TILE[current_tool], current_density if _has_density() else 1)
	return true


func _why_cant_build(p: Vector2i, check_money: bool = true) -> String:
	# "" = OK to build; "-" = nothing to do (no message); otherwise the reason.
	var i := p.y * map_w + p.x
	var here := sim.tiles[i]
	if current_tool == Tool.BULLDOZE:
		if here == Tile.EMPTY:
			return "-"
	else:
		if here == TOOL_TO_TILE[current_tool]:
			# Same zone again does nothing, unless it changes the density.
			if not _has_density() or sim.density[i] == current_density:
				return "-"
		# Zones and parks go round roads, power and plants rather than replacing
		# them; the street grid only goes on open land. (Bulldoze first to replace.)
		var infrastructure := here == Tile.ROAD or here == Tile.POWER_LINE or here == Tile.POWER_PLANT
		if current_tool in [Tool.HOMES, Tool.SHOPS, Tool.INDUSTRY, Tool.PARK] and infrastructure:
			return "-"
		if current_tool == Tool.GRID and here != Tile.EMPTY:
			return "-"
		if water[i] == 1:
			return "You can't build on water."
		if slope[i] > Settings.MAX_SLOPE_M:
			return "Too steep to build here."
	var cost := _tool_cost(p)
	if check_money and cost > sim.money:
		return "Not enough money: that costs %s." % _money_text(cost)
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
		Tool.POWER_PLANT:
			return Settings.POWER_PLANT_COST
		Tool.POWER_LINE:
			return Settings.POWER_LINE_COST
		Tool.PARK:
			return Settings.PARK_COST
		Tool.GRID:
			return Settings.ROAD_COST
	return 0


func _tool_cost(p: Vector2i) -> int:
	var base := _base_cost(current_tool)
	if current_tool == Tool.BULLDOZE:
		return base
	var hill := 1.0 + slope[p.y * map_w + p.x] * Settings.SLOPE_COST_PER_METRE
	return roundi(base * hill)


func _price_text(tool_id: int) -> String:
	if tool_id == Tool.HOMES or tool_id == Tool.SHOPS:
		return "from " + _money_text(Settings.HOMES_COSTS[0] if tool_id == Tool.HOMES else Settings.SHOPS_COSTS[0])
	return _money_text(_base_cost(tool_id))


func _has_density() -> bool:
	return current_tool == Tool.HOMES or current_tool == Tool.SHOPS


func _set_density(d: int) -> void:
	current_density = d
	hud.set_density(d)
	var density_word: String = Settings.DENSITY_NAMES[d]
	hud.flash("Zoning %s density" % density_word)
	if painting:
		_update_drag()


func _select_tool(tool_id: int) -> void:
	current_tool = tool_id
	hud.set_tool(tool_id)
	hud.show_density(_has_density())
	if _in_map(hover):
		var why := _why_cant_build(hover)
		world.set_hover(hover, why == "" or why == "-")
	_update_info()


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
	data["version"] = 3
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
	sim.from_save(data)
	world.refresh_all()
	cars.roads_changed()
	_update_traffic()
	_refresh_hud()
	hud.flash("City loaded.")


func _new_city() -> void:
	sim.reset()
	clock = 0.0
	world.refresh_all()
	cars.roads_changed()
	_update_traffic()
	_refresh_hud()
	hud.flash("New city: the map is blank again.")


# ----------------------------------------------------------------------- HUD

func _refresh_hud() -> void:
	var net := sim.last_income - sim.last_upkeep
	hud.show_city(sim, _money_text(sim.money), ("+" if net >= 0 else "") + _money_text(net),
		_money_text(sim.last_income), _money_text(sim.last_upkeep))
	_update_info()


func _update_info() -> void:
	if hud.info_label == null:
		return
	if not _in_map(hover):
		hud.show_info("%s selected. Point at the map to see what's there." % TOOL_NAMES[current_tool])
		return
	var i := hover.y * map_w + hover.x
	var ground := "Sea" if water[i] == 1 else "%.0f m above sea level" % heights[i]
	var problem := _why_cant_build(hover)
	var action := "%s here costs %s" % [TOOL_NAMES[current_tool], _money_text(_tool_cost(hover))]
	if problem == "-":
		action = "Nothing to clear" if current_tool == Tool.BULLDOZE else "Already built"
	elif problem != "":
		action = problem
	hud.show_info("%s   ·   %s\n%s" % [_tile_text(i), ground, action])


func _tile_text(i: int) -> String:
	var t := sim.tiles[i]
	if t == Tile.POWER_PLANT:
		return "Power plant (powers %d zone levels)" % Settings.POWER_PER_PLANT
	if t == Tile.PARK:
		return "Park (trees and open space; costs £%d a month to look after)" % roundi(Settings.PARK_UPKEEP)
	if not sim.is_zone(t):
		if t == Tile.EMPTY and water[i] == 0:
			return "Open land (land value %s)" % sim.land_value_word(i)
		return TILE_NAMES[t]
	var kind: String = TILE_NAMES[t]
	if t != Tile.INDUSTRY:
		kind += " (%s density)" % sim.density_name(i)
	var text := "%s, level %d of %d%s: %s" % [kind, sim.levels[i], sim.max_level(i),
		_stage_words(t, sim.stage(i)), sim.zone_status(i)]
	text += "\nLand value %s" % sim.land_value_word(i)
	if t == Tile.HOMES:
		text += "   ·   homes here worth about %s" % _money_text(sim.home_price(i))
	return text


func _stage_words(t: int, s: int) -> String:
	# What the buildings on a plot are, for the hover text.
	var homes := ["", "villas", "villas and terraces", "tenements", "mansion flats", "modern flats", "towers"]
	var shops := ["", "corner shops", "shop parade", "shops with flats", "offices over shops", "office blocks", "office tower"]
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


func _money_text(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-£" if amount < 0 else "£") + digits + out


func _in_map(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < map_w and t.y < map_h
