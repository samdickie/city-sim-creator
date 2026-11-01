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

const MAP_FILE := "res://map/troon_map.json"
const SAVE_FILE := "user://troon_save.json"

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE }   # same order as simulation.gd
enum Tool { ROAD, HOMES, SHOPS, INDUSTRY, BULLDOZE, POWER_PLANT, POWER_LINE }

const TOOL_NAMES := {
	Tool.ROAD: "Road",
	Tool.HOMES: "Homes",
	Tool.SHOPS: "Shops",
	Tool.INDUSTRY: "Industry",
	Tool.BULLDOZE: "Bulldoze",
	Tool.POWER_PLANT: "Power plant",
	Tool.POWER_LINE: "Power line",
}
const TOOL_TO_TILE := {
	Tool.ROAD: Tile.ROAD,
	Tool.HOMES: Tile.HOMES,
	Tool.SHOPS: Tile.SHOPS,
	Tool.INDUSTRY: Tile.INDUSTRY,
	Tool.POWER_PLANT: Tile.POWER_PLANT,
	Tool.POWER_LINE: Tile.POWER_LINE,
}
const TOOL_COLOURS := {
	Tool.ROAD: Color(0.45, 0.45, 0.48),
	Tool.HOMES: Color(0.86, 0.36, 0.30),
	Tool.SHOPS: Color(0.26, 0.58, 0.92),
	Tool.INDUSTRY: Color(0.96, 0.70, 0.15),
	Tool.BULLDOZE: Color(0.9, 0.3, 0.3),
	Tool.POWER_PLANT: Color(0.62, 0.45, 0.85),
	Tool.POWER_LINE: Color(0.98, 0.88, 0.25),
}
const TILE_NAMES := {
	Tile.EMPTY: "Open land",
	Tile.ROAD: "Road",
	Tile.HOMES: "Homes",
	Tile.SHOPS: "Shops",
	Tile.INDUSTRY: "Industry",
	Tile.POWER_PLANT: "Power plant",
	Tile.POWER_LINE: "Power line",
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
var speed := 1
var clock := 0.0

# --- Interaction ---
var current_tool: int = Tool.ROAD
var painting := false
var orbiting := false
var dragging_map := false
var last_paint := Vector2i(-1, -1)
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
	hud.speed_chosen.connect(_set_speed)
	hud.tax_changed.connect(_change_tax)
	hud.new_city_pressed.connect(_new_city)
	hud.save_pressed.connect(_save_game)
	hud.load_pressed.connect(_load_game)

	_select_tool(Tool.ROAD)
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
				painting = mb.pressed
				last_paint = Vector2i(-1, -1)
				if painting:
					_paint_at(hover)
				else:
					_buildings_dirty = true
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
		if painting:
			_paint_at(hover)

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
		_update_info()


# ------------------------------------------------------------------ building

func _paint_at(t: Vector2i) -> void:
	if not _in_map(t):
		last_paint = Vector2i(-1, -1)
		return
	if _in_map(last_paint):
		for p in _line(last_paint, t):
			_apply_tool(p)
	else:
		_apply_tool(t)
	last_paint = t
	sim.recount()
	_ground_dirty = true
	_buildings_dirty = true
	_refresh_hud()


func _apply_tool(p: Vector2i) -> void:
	var problem := _why_cant_build(p)
	if problem != "":
		if problem != "-":
			hud.flash(problem)
		return
	var i := p.y * map_w + p.x
	sim.money -= _tool_cost(p)
	if current_tool == Tool.BULLDOZE:
		sim.set_tile(i, Tile.EMPTY)
	else:
		sim.set_tile(i, TOOL_TO_TILE[current_tool])


func _why_cant_build(p: Vector2i) -> String:
	# "" = OK to build; "-" = nothing to do (no message); otherwise the reason.
	var i := p.y * map_w + p.x
	var here := sim.tiles[i]
	if current_tool == Tool.BULLDOZE:
		if here == Tile.EMPTY:
			return "-"
	else:
		if here == TOOL_TO_TILE[current_tool]:
			return "-"
		if water[i] == 1:
			return "You can't build on water."
		if slope[i] > Settings.MAX_SLOPE_M:
			return "Too steep to build here."
	var cost := _tool_cost(p)
	if cost > sim.money:
		return "Not enough money: that costs %s." % _money_text(cost)
	return ""


func _base_cost(tool_id: int) -> int:
	match tool_id:
		Tool.ROAD:
			return Settings.ROAD_COST
		Tool.HOMES:
			return Settings.HOMES_COST
		Tool.SHOPS:
			return Settings.SHOPS_COST
		Tool.INDUSTRY:
			return Settings.INDUSTRY_COST
		Tool.BULLDOZE:
			return Settings.BULLDOZE_COST
		Tool.POWER_PLANT:
			return Settings.POWER_PLANT_COST
		Tool.POWER_LINE:
			return Settings.POWER_LINE_COST
	return 0


func _tool_cost(p: Vector2i) -> int:
	var base := _base_cost(current_tool)
	if current_tool == Tool.BULLDOZE:
		return base
	var hill := 1.0 + slope[p.y * map_w + p.x] * Settings.SLOPE_COST_PER_METRE
	return roundi(base * hill)


func _price_text(tool_id: int) -> String:
	return _money_text(_base_cost(tool_id))


func _line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	# Bresenham's line: every grid tile between a and b.
	var points: Array[Vector2i] = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		points.append(p)
		if p == b:
			break
		var e2 := 2 * err
		var step_x := e2 >= dy
		var step_y := e2 <= dx
		if step_x:
			err += dy
			p.x += sx
		if step_y:
			if step_x:
				points.append(p)   # fill the corner so tiles always share an edge
				if p == b:
					break
			err += dx
			p.y += sy
	return points


func _select_tool(tool_id: int) -> void:
	current_tool = tool_id
	hud.set_tool(tool_id)
	if _in_map(hover):
		var why := _why_cant_build(hover)
		world.set_hover(hover, why == "" or why == "-")
	_update_info()


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
	_refresh_hud()
	hud.flash("City loaded.")


func _new_city() -> void:
	sim.reset()
	clock = 0.0
	world.refresh_all()
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
	if not sim.is_zone(t):
		return TILE_NAMES[t]
	return "%s, level %d of %d: %s" % [TILE_NAMES[t], sim.levels[i], Settings.MAX_LEVEL, sim.zone_status(i)]


func _money_text(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-£" if amount < 0 else "£") + digits + out


func _in_map(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < map_w and t.y < map_h
