extends Node2D
## Troon City — the game screen.
## Draws the map and the city, handles the mouse and keyboard, and runs the
## game clock. The city's rules live in simulation.gd; tuning numbers in settings.gd.

const Settings = preload("res://scripts/settings.gd")
const Simulation = preload("res://scripts/simulation.gd")

const TILE := 16                       # on-screen size of one map tile, in pixels
const MAP_FILE := "res://map/troon_map.json"
const SAVE_FILE := "user://troon_save.json"
const MIN_ZOOM := 0.25
const MAX_ZOOM := 4.0
const PAN_SPEED := 900.0               # keyboard panning, pixels per second

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

const TILE_NAMES := {
	Tile.EMPTY: "Empty",
	Tile.ROAD: "Road",
	Tile.HOMES: "Homes",
	Tile.SHOPS: "Shops",
	Tile.INDUSTRY: "Industry",
	Tile.POWER_PLANT: "Power plant",
	Tile.POWER_LINE: "Power line",
}

const TILE_COLOURS := {
	Tile.ROAD: Color(0.23, 0.23, 0.25),
	Tile.HOMES: Color(0.86, 0.36, 0.30),   # brick red: stands out on green land
	Tile.SHOPS: Color(0.26, 0.58, 0.92),
	Tile.INDUSTRY: Color(0.96, 0.70, 0.15),
	Tile.POWER_PLANT: Color(0.45, 0.32, 0.62),
	Tile.POWER_LINE: Color(0.98, 0.88, 0.25),
}
const SPARK := Color(1.0, 0.9, 0.2)

const LEVEL_FILL := [0.22, 0.55, 0.8, 1.0]   # how solid a zone looks at levels 0-3
const FLASH_SECONDS := 1.5

const WATER_COLOUR := Color(0.18, 0.42, 0.66)
const LOW_LAND := Color(0.62, 0.74, 0.46)
const HIGH_LAND := Color(0.36, 0.50, 0.28)

# --- Map (row by row, north at the top) ---
var map_w := 0
var map_h := 0
var cell_size_m := 50.0
var map_name := "Map"
var map_credits := ""
var heights := PackedFloat32Array()    # metres above sea level
var water := PackedByteArray()         # 1 = sea, 0 = land
var slope := PackedFloat32Array()      # biggest height step to a neighbour, metres

# --- The city and its clock ---
var sim := Simulation.new()
var speed := 1                         # 0 = paused, 1 = normal, Settings.FAST_SPEED = fast
var clock := 0.0

# --- Interaction state ---
var current_tool: int = Tool.ROAD
var painting := false
var panning := false
var last_paint := Vector2i(-1, -1)
var hover := Vector2i(-1, -1)

# --- Nodes created in code ---
var terrain_texture: ImageTexture
var camera: Camera2D
var tool_buttons := {}
var speed_buttons := {}
var info_label: Label
var stats_label: Label
var message_label: Label
var message_timer := 0.0
var flash_tiles := PackedInt32Array()  # plots that grew this month
var flash_time := 0.0
var confirm_new: ConfirmationDialog
var date_label: Label
var money_label: Label
var budget_label: Label
var city_label: Label
var tax_label: Label
var demand_box: Control


func _ready() -> void:
	_load_map()
	_compute_slopes()
	sim.setup(map_w, map_h, water)
	_build_terrain_texture()
	_setup_camera()
	_build_hud()
	_select_tool(Tool.ROAD)
	_set_speed(1)
	_refresh_hud()


# ---------------------------------------------------------------- map loading

func _load_map() -> void:
	var data = null
	if FileAccess.file_exists(MAP_FILE):
		data = JSON.parse_string(FileAccess.get_file_as_string(MAP_FILE))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Could not read %s — using a flat placeholder map." % MAP_FILE)
		map_w = 100
		map_h = 100
		map_name = "Flat placeholder"
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
	# For each tile, the largest height difference to the tile next to it.
	slope.resize(map_w * map_h)
	for y in map_h:
		for x in map_w:
			var h := heights[_index(x, y)]
			var steepest := 0.0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if _in_map(n) and water[_index(n.x, n.y)] == 0:
					steepest = maxf(steepest, absf(h - heights[_index(n.x, n.y)]))
			slope[_index(x, y)] = steepest


func _build_terrain_texture() -> void:
	var max_h := 1.0
	for i in heights.size():
		if water[i] == 0:
			max_h = maxf(max_h, heights[i])
	var img := Image.create_empty(map_w, map_h, false, Image.FORMAT_RGB8)
	for y in map_h:
		for x in map_w:
			img.set_pixel(x, y, _terrain_colour(x, y, max_h))
	terrain_texture = ImageTexture.create_from_image(img)


func _terrain_colour(x: int, y: int, max_h: float) -> Color:
	var i := _index(x, y)
	if water[i] == 1:
		return WATER_COLOUR
	var h := heights[i]
	var c := LOW_LAND.lerp(HIGH_LAND, clampf(h / max_h, 0.0, 1.0))
	# Simple hill shading: slopes facing the north-west light are brighter.
	var h_west := heights[_index(maxi(x - 1, 0), y)]
	var h_north := heights[_index(x, maxi(y - 1, 0))]
	var shade := clampf(((h - h_west) + (h - h_north)) * 0.03, -0.18, 0.18)
	if shade > 0.0:
		return c.lightened(shade)
	return c.darkened(-shade)


# ------------------------------------------------------------------- drawing

func _draw() -> void:
	var map_px := Vector2(map_w, map_h) * TILE
	draw_texture_rect(terrain_texture, Rect2(Vector2.ZERO, map_px), false)

	var tiles := sim.tiles
	var levels := sim.levels
	var reach := sim.road_reach_map()
	var power := sim.power_map()
	for y in map_h:
		for x in map_w:
			var i := _index(x, y)
			var t := tiles[i]
			if t == Tile.EMPTY:
				continue
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			var c: Color = TILE_COLOURS[t]
			if t == Tile.ROAD:
				draw_rect(r, c)
				continue
			if t == Tile.POWER_PLANT:
				draw_rect(r, c)
				# A yellow lightning-bolt shape.
				var o := r.position
				draw_colored_polygon(PackedVector2Array([
					o + Vector2(10, 2), o + Vector2(4, 9), o + Vector2(9, 9)]), SPARK)
				draw_colored_polygon(PackedVector2Array([
					o + Vector2(7, 7), o + Vector2(12, 7), o + Vector2(6, 14)]), SPARK)
				continue
			if t == Tile.POWER_LINE:
				_draw_power_line(x, y, c)
				continue
			var plot := r.grow(-1.0)   # small gap so plots read as separate
			var lv := levels[i]
			# The whole plot gets bolder as it grows, so growth shows at any zoom:
			# faint outline (empty) -> light -> medium -> solid with a dark block.
			draw_rect(plot, Color(c, LEVEL_FILL[mini(lv, 3)]))
			if lv == 0:
				draw_rect(plot, Color(c, 0.9), false, 1.0)
			else:
				draw_rect(r.grow(-(7.0 - mini(lv, 3) * 2.0)), c.darkened(0.5))
			if reach[i] > Settings.ROAD_REACH:
				# No road close enough: cross it out so it's clear why it isn't growing.
				draw_line(plot.position, plot.end, Color(0, 0, 0, 0.6), 1.5)
				draw_line(Vector2(plot.end.x, plot.position.y),
					Vector2(plot.position.x, plot.end.y), Color(0, 0, 0, 0.6), 1.5)
			elif power[i] == 0:
				# Has a road but no electricity: dim it and add a small power warning.
				draw_rect(plot, Color(0, 0, 0, 0.35))
				draw_circle(plot.position + Vector2(TILE * 0.5 - 1, TILE * 0.5 - 1), 3.5, Color(0, 0, 0, 0.8))
				draw_circle(plot.position + Vector2(TILE * 0.5 - 1, TILE * 0.5 - 1), 2.0, SPARK)

	# Plots that grew this month flash white, then fade.
	if flash_time > 0.0:
		var a := flash_time / FLASH_SECONDS
		for i in flash_tiles:
			var fr := Rect2((i % map_w) * TILE, (i / map_w) * TILE, TILE, TILE)
			draw_rect(fr.grow(TILE * 0.35 * a), Color(1, 1, 1, 0.85 * a))

	# Faint grid once zoomed in enough to see individual tiles.
	if camera and camera.zoom.x >= 1.0:
		var grid := Color(0, 0, 0, 0.08)
		for x in map_w + 1:
			draw_line(Vector2(x * TILE, 0), Vector2(x * TILE, map_px.y), grid)
		for y in map_h + 1:
			draw_line(Vector2(0, y * TILE), Vector2(map_px.x, y * TILE), grid)

	draw_rect(Rect2(Vector2.ZERO, map_px), Color(0, 0, 0, 0.5), false, 2.0)

	if _in_map(hover):
		var outline := Color(1, 1, 1, 0.95)
		var why := _why_cant_build(hover)
		if why != "" and why != "-":
			outline = Color(1, 0.3, 0.3, 0.95)
		draw_rect(Rect2(Vector2(hover) * TILE, Vector2(TILE, TILE)), outline, false, 2.0)


func _draw_power_line(x: int, y: int, c: Color) -> void:
	# A cable from the centre of the tile towards each built neighbour.
	var centre := Vector2(x + 0.5, y + 0.5) * TILE
	draw_circle(centre, 2.0, c)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = Vector2i(x, y) + d
		if _in_map(n) and sim.tiles[_index(n.x, n.y)] != Tile.EMPTY:
			draw_line(centre, centre + Vector2(d) * TILE * 0.5, c, 2.0)


func _draw_demand() -> void:
	# Three bars: up = the town wants more, down = it has too many.
	var size := demand_box.size
	var mid := size.y / 2.0
	var font := ThemeDB.fallback_font
	demand_box.draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.35))
	var bars := [[Tile.HOMES, "Homes"], [Tile.SHOPS, "Shops"], [Tile.INDUSTRY, "Industry"]]
	var col_w := size.x / bars.size()
	for n in bars.size():
		var t: int = bars[n][0]
		var label: String = bars[n][1]
		var value := sim.demand_bar(t)
		var bar_h := absf(value) * (mid - 14.0)
		var x := n * col_w + col_w * 0.25
		var top := mid - bar_h if value > 0 else mid
		demand_box.draw_rect(Rect2(x, top, col_w * 0.5, bar_h), TILE_COLOURS[t])
		demand_box.draw_string(font, Vector2(n * col_w, size.y - 2), label,
			HORIZONTAL_ALIGNMENT_CENTER, col_w, 11, Color(0.8, 0.8, 0.8))


# --------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				painting = mb.pressed
				last_paint = Vector2i(-1, -1)
				if painting:
					_paint_at(_mouse_tile())
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(1.15, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(1.0 / 1.15, mb.position)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if panning:
			camera.position -= mm.relative / camera.zoom
		var t := _mouse_tile()
		if t != hover:
			hover = t
			_update_info()
			queue_redraw()
		if painting:
			_paint_at(t)

	elif event is InputEventMagnifyGesture:   # Mac trackpad pinch
		var mg := event as InputEventMagnifyGesture
		_zoom_at(mg.factor, mg.position)

	elif event is InputEventPanGesture:       # Mac trackpad two-finger scroll
		var pg := event as InputEventPanGesture
		camera.position += pg.delta * 12.0 / camera.zoom

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


func _process(delta: float) -> void:
	# Keyboard panning.
	var dir := Vector2.ZERO
	if not Input.is_key_pressed(KEY_META) and not Input.is_key_pressed(KEY_CTRL):
		if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir.x += 1
		if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir.y += 1
	if dir != Vector2.ZERO:
		camera.position += dir.normalized() * PAN_SPEED * delta / camera.zoom.x
	var map_px := Vector2(map_w, map_h) * TILE
	camera.position = camera.position.clamp(Vector2.ZERO, map_px)

	# The game clock: one simulation step per game month.
	if speed > 0:
		clock += delta * speed
		if clock >= Settings.MONTH_SECONDS:
			clock = 0.0
			sim.tick()
			flash_tiles = sim.grew
			flash_time = FLASH_SECONDS
			_refresh_hud()
			queue_redraw()

	if flash_time > 0.0:
		flash_time -= delta
		queue_redraw()

	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0:
			message_label.text = ""


func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	# Zoom towards the point under the mouse, like a map app.
	var centre := get_viewport_rect().size / 2.0
	var world_before := camera.position + (screen_pos - centre) / camera.zoom
	var z := clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(z, z)
	camera.position = world_before - (screen_pos - centre) / camera.zoom
	queue_redraw()


# ------------------------------------------------------------------ building

func _paint_at(t: Vector2i) -> void:
	if not _in_map(t):
		last_paint = Vector2i(-1, -1)
		return
	# Fill in every tile between the last point and this one,
	# so a fast drag doesn't leave gaps in a road.
	if _in_map(last_paint):
		for p in _line(last_paint, t):
			_apply_tool(p)
	else:
		_apply_tool(t)
	last_paint = t
	sim.recount()
	_refresh_hud()
	queue_redraw()


func _apply_tool(p: Vector2i) -> void:
	var problem := _why_cant_build(p)
	if problem != "":
		if problem != "-":
			_flash(problem)
		return
	var i := _index(p.x, p.y)
	sim.money -= _tool_cost(p)
	if current_tool == Tool.BULLDOZE:
		sim.set_tile(i, Tile.EMPTY)
	else:
		sim.set_tile(i, TOOL_TO_TILE[current_tool])


func _why_cant_build(p: Vector2i) -> String:
	# "" = OK to build; "-" = nothing to do (no message); otherwise the reason.
	var i := _index(p.x, p.y)
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


func _tool_cost(p: Vector2i) -> int:
	if current_tool == Tool.BULLDOZE:
		return Settings.BULLDOZE_COST
	var base := 0
	match current_tool:
		Tool.ROAD:
			base = Settings.ROAD_COST
		Tool.HOMES:
			base = Settings.HOMES_COST
		Tool.SHOPS:
			base = Settings.SHOPS_COST
		Tool.INDUSTRY:
			base = Settings.INDUSTRY_COST
		Tool.POWER_PLANT:
			base = Settings.POWER_PLANT_COST
		Tool.POWER_LINE:
			base = Settings.POWER_LINE_COST
	var hill := 1.0 + slope[_index(p.x, p.y)] * Settings.SLOPE_COST_PER_METRE
	return roundi(base * hill)


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
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return points


func _select_tool(tool_id: int) -> void:
	current_tool = tool_id
	for id in tool_buttons:
		(tool_buttons[id] as Button).set_pressed_no_signal(id == tool_id)
	_update_info()
	queue_redraw()


func _set_speed(new_speed: int) -> void:
	speed = new_speed
	for s in speed_buttons:
		(speed_buttons[s] as Button).set_pressed_no_signal(s == speed)


func _change_tax(step: float) -> void:
	sim.change_tax(step)
	_refresh_hud()


# --------------------------------------------------------------- save / load

func _save_game() -> void:
	var f := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if f == null:
		_flash("Save failed.")
		return
	var data := sim.to_save()
	data["version"] = 2
	data["map"] = map_name
	data["width"] = map_w
	data["height"] = map_h
	f.store_string(JSON.stringify(data))
	f.close()
	_flash("City saved.")


func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_FILE):
		_flash("No saved city yet.")
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE))
	if typeof(data) != TYPE_DICTIONARY \
			or int(data.get("width", 0)) != map_w \
			or int(data.get("height", 0)) != map_h:
		_flash("That save doesn't match this map.")
		return
	sim.from_save(data)
	_refresh_hud()
	queue_redraw()
	_flash("City loaded.")


func _new_city() -> void:
	sim.reset()
	clock = 0.0
	_refresh_hud()
	queue_redraw()
	_flash("New city — the map is blank again.")


# ----------------------------------------------------------------------- HUD

func _setup_camera() -> void:
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	camera.position = Vector2(map_w, map_h) * TILE / 2.0
	# Start zoomed out so the whole map fits on screen.
	var view := get_viewport_rect().size
	var fit := minf(view.x / (map_w * TILE), view.y / (map_h * TILE)) * 0.95
	var z := clampf(fit, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(z, z)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_build_tools_panel(layer)
	_build_city_panel(layer)

	confirm_new = ConfirmationDialog.new()
	confirm_new.title = "New city"
	confirm_new.dialog_text = "Clear everything you've built and start again?"
	confirm_new.confirmed.connect(_new_city)
	layer.add_child(confirm_new)


func _build_tools_panel(layer: CanvasLayer) -> void:
	# Top left: tools, file buttons, tile info and help.
	var panel := _panel(layer)
	panel.position = Vector2(12, 12)
	var box := _box_of(panel)

	var title := Label.new()
	title.text = "Troon City · " + map_name
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	var tools_row := HBoxContainer.new()
	box.add_child(tools_row)
	for tool_id in TOOL_NAMES:
		var b := Button.new()
		b.text = "%d  %s" % [tool_id + 1, TOOL_NAMES[tool_id]]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_select_tool.bind(tool_id))
		tools_row.add_child(b)
		tool_buttons[tool_id] = b

	var file_row := HBoxContainer.new()
	box.add_child(file_row)
	_add_button(file_row, "New city", func(): confirm_new.popup_centered())
	_add_button(file_row, "Save", _save_game)
	_add_button(file_row, "Load", _load_game)

	info_label = Label.new()
	box.add_child(info_label)

	stats_label = Label.new()
	stats_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	box.add_child(stats_label)

	message_label = Label.new()
	message_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(message_label)

	var help := Label.new()
	help.text = "Left-drag: build   ·   Right-drag, WASD or two fingers: move\n" \
		+ "Scroll or pinch: zoom   ·   1-7: tools   ·   Space: pause   ·   F: fast\n" \
		+ "Zones fill in as they grow; crossed out = no road within %d tiles\n" % Settings.ROAD_REACH \
		+ "Yellow dot = no power: roads, zones and power lines carry power from a plant\n" \
		+ "Cmd+S save, Cmd+L load"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(help)

	if map_credits != "":
		var credits := Label.new()
		credits.text = map_credits
		credits.add_theme_font_size_override("font_size", 11)
		credits.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		box.add_child(credits)


func _build_city_panel(layer: CanvasLayer) -> void:
	# Top right: date and speed, money, population, taxes, demand.
	var panel := _panel(layer)
	var box := _box_of(panel)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -12.0
	panel.offset_right = -12.0
	panel.offset_top = 12.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.custom_minimum_size = Vector2(250, 0)

	var date_row := HBoxContainer.new()
	box.add_child(date_row)
	date_label = Label.new()
	date_label.add_theme_font_size_override("font_size", 18)
	date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	date_row.add_child(date_label)
	for s in [0, 1, Settings.FAST_SPEED]:
		var b := Button.new()
		b.text = {0: "Pause", 1: "Play", Settings.FAST_SPEED: "Fast"}[s]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_speed.bind(s))
		date_row.add_child(b)
		speed_buttons[s] = b

	money_label = Label.new()
	money_label.add_theme_font_size_override("font_size", 24)
	box.add_child(money_label)

	budget_label = Label.new()
	budget_label.add_theme_font_size_override("font_size", 12)
	budget_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	box.add_child(budget_label)

	city_label = Label.new()
	box.add_child(city_label)

	var tax_row := HBoxContainer.new()
	box.add_child(tax_row)
	tax_label = Label.new()
	tax_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tax_row.add_child(tax_label)
	_add_button(tax_row, "  -  ", _change_tax.bind(-0.01))
	_add_button(tax_row, "  +  ", _change_tax.bind(0.01))

	var demand_title := Label.new()
	demand_title.text = "Demand"
	demand_title.add_theme_font_size_override("font_size", 12)
	demand_title.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	box.add_child(demand_title)

	demand_box = Control.new()
	demand_box.custom_minimum_size = Vector2(230, 90)
	demand_box.draw.connect(_draw_demand)
	box.add_child(demand_box)


func _panel(layer: CanvasLayer) -> PanelContainer:
	var panel := PanelContainer.new()
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	return panel


func _box_of(panel: PanelContainer) -> VBoxContainer:
	return panel.get_child(0).get_child(0) as VBoxContainer


func _add_button(parent: Node, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)


func _refresh_hud() -> void:
	date_label.text = sim.date_text()
	money_label.text = _money_text(sim.money)
	var low := sim.money * 10 < Settings.START_MONEY
	money_label.add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.4) if low else Color(0.55, 0.9, 0.55))
	var net := sim.last_income - sim.last_upkeep
	budget_label.text = "%s%s last month   (taxes %s, upkeep %s)" % [
		"+" if net >= 0 else "", _money_text(net),
		_money_text(sim.last_income), _money_text(sim.last_upkeep)]
	city_label.text = "Population %d   ·   Jobs %d\nLast month: %d plots grew, %d shrank\nPower: %d of %d used" % [
		sim.population, sim.jobs(), sim.grew.size(), sim.shrank.size(),
		sim.power_used, sim.power_supply]
	if sim.plants == 0:
		city_label.text += "   (build a power plant!)"
	tax_label.text = "Tax rate %d%%" % roundi(sim.tax_rate * 100.0)
	demand_box.queue_redraw()
	_update_stats()
	_update_info()


func _update_info() -> void:
	if info_label == null:
		return
	if not _in_map(hover):
		info_label.text = "Tool: %s" % TOOL_NAMES[current_tool]
		return
	var i := _index(hover.x, hover.y)
	var ground := "Sea" if water[i] == 1 else "Land, %.0f m above sea level" % heights[i]
	var problem := _why_cant_build(hover)
	var cost_text := "Cost %s" % _money_text(_tool_cost(hover))
	if problem == "-":
		cost_text = "Nothing to clear" if current_tool == Tool.BULLDOZE else "Already built"
	elif problem != "":
		cost_text = problem
	info_label.text = "Tool: %s   ·   %s\nTile %d, %d   ·   %s   ·   %s" % [
		TOOL_NAMES[current_tool], cost_text, hover.x, hover.y, ground, _tile_text(i)]


func _tile_text(i: int) -> String:
	var t := sim.tiles[i]
	if not sim.is_zone(t):
		if t == Tile.POWER_PLANT:
			return "Power plant, powers %d zone levels" % Settings.POWER_PER_PLANT
		return TILE_NAMES[t]
	var lv := sim.levels[i]
	return "%s, level %d of %d: %s" % [TILE_NAMES[t], lv, sim.max_level(i), sim.zone_status(i)]


func _update_stats() -> void:
	var counts := {Tile.ROAD: 0, Tile.HOMES: 0, Tile.SHOPS: 0, Tile.INDUSTRY: 0}
	for t in sim.tiles:
		if counts.has(t):
			counts[t] += 1
	var km_w := map_w * cell_size_m / 1000.0
	var km_h := map_h * cell_size_m / 1000.0
	stats_label.text = "Roads %d  ·  Homes %d  ·  Shops %d  ·  Industry %d tiles\nMap %d × %d tiles  ·  %.1f × %.1f km  ·  %d m per tile" % [
		counts[Tile.ROAD], counts[Tile.HOMES], counts[Tile.SHOPS], counts[Tile.INDUSTRY],
		map_w, map_h, km_w, km_h, int(cell_size_m)]


func _money_text(amount: int) -> String:
	# 12345 -> "£12,345"
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-£" if amount < 0 else "£") + digits + out


func _flash(text: String) -> void:
	message_label.text = text
	message_timer = 2.5


# ------------------------------------------------------------------- helpers

func _index(x: int, y: int) -> int:
	return y * map_w + x


func _in_map(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < map_w and t.y < map_h


func _mouse_tile() -> Vector2i:
	var p := get_global_mouse_position()
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))
