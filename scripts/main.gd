extends Node2D
## Troon City — Phase 1 sandbox.
## Loads the terrain map, lets the player paint roads and zones,
## and saves/loads the city. No simulation yet (that is Phase 2).

const TILE := 16                       # on-screen size of one map tile, in pixels
const MAP_FILE := "res://map/troon_map.json"
const SAVE_FILE := "user://troon_save.json"
const MIN_ZOOM := 0.25
const MAX_ZOOM := 4.0
const PAN_SPEED := 900.0               # keyboard panning, pixels per second

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY }
enum Tool { ROAD, HOMES, SHOPS, INDUSTRY, BULLDOZE }

const TOOL_NAMES := {
	Tool.ROAD: "Road",
	Tool.HOMES: "Homes",
	Tool.SHOPS: "Shops",
	Tool.INDUSTRY: "Industry",
	Tool.BULLDOZE: "Bulldoze",
}

const TOOL_TO_TILE := {
	Tool.ROAD: Tile.ROAD,
	Tool.HOMES: Tile.HOMES,
	Tool.SHOPS: Tile.SHOPS,
	Tool.INDUSTRY: Tile.INDUSTRY,
}

const TILE_NAMES := {
	Tile.EMPTY: "Empty",
	Tile.ROAD: "Road",
	Tile.HOMES: "Homes",
	Tile.SHOPS: "Shops",
	Tile.INDUSTRY: "Industry",
}

const TILE_COLOURS := {
	Tile.ROAD: Color(0.23, 0.23, 0.25),
	Tile.HOMES: Color(0.30, 0.72, 0.36),
	Tile.SHOPS: Color(0.26, 0.58, 0.92),
	Tile.INDUSTRY: Color(0.96, 0.70, 0.15),
}

const WATER_COLOUR := Color(0.18, 0.42, 0.66)
const LOW_LAND := Color(0.62, 0.74, 0.46)
const HIGH_LAND := Color(0.36, 0.50, 0.28)

# --- Map data (row by row, north at the top) ---
var map_w := 0
var map_h := 0
var cell_size_m := 50.0
var map_name := "Map"
var map_credits := ""
var heights := PackedFloat32Array()    # metres above sea level
var water := PackedByteArray()         # 1 = sea, 0 = land
var tiles := PackedByteArray()         # what the player has built (Tile enum)

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
var info_label: Label
var stats_label: Label
var message_label: Label
var message_timer := 0.0
var confirm_new: ConfirmationDialog


func _ready() -> void:
	_load_map()
	tiles.resize(map_w * map_h)
	tiles.fill(Tile.EMPTY)
	_build_terrain_texture()
	_setup_camera()
	_build_hud()
	_select_tool(Tool.ROAD)
	_update_stats()
	_update_info()


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

	for y in map_h:
		for x in map_w:
			var t := tiles[_index(x, y)]
			if t == Tile.EMPTY:
				continue
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			if t != Tile.ROAD:
				r = r.grow(-1.0)   # small gap so zone blocks read as separate plots
			draw_rect(r, TILE_COLOURS[t])

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
		if current_tool != Tool.BULLDOZE and water[_index(hover.x, hover.y)] == 1:
			outline = Color(1, 0.3, 0.3, 0.95)
		draw_rect(Rect2(Vector2(hover) * TILE, Vector2(TILE, TILE)), outline, false, 2.0)


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


func _process(delta: float) -> void:
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

	# Keep the camera over the map.
	var map_px := Vector2(map_w, map_h) * TILE
	camera.position = camera.position.clamp(Vector2.ZERO, map_px)

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
	_update_stats()
	_update_info()
	queue_redraw()


func _apply_tool(p: Vector2i) -> void:
	var i := _index(p.x, p.y)
	if current_tool == Tool.BULLDOZE:
		tiles[i] = Tile.EMPTY
		return
	if water[i] == 1:
		_flash("You can't build on water.")
		return
	tiles[i] = TOOL_TO_TILE[current_tool]


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
	queue_redraw()


# --------------------------------------------------------------- save / load

func _save_game() -> void:
	var f := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if f == null:
		_flash("Save failed.")
		return
	f.store_string(JSON.stringify({
		"version": 1,
		"map": map_name,
		"width": map_w,
		"height": map_h,
		"tiles": Array(tiles),
	}))
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
	var saved: Array = data["tiles"]
	for i in mini(saved.size(), tiles.size()):
		tiles[i] = int(saved[i])
	_update_stats()
	_update_info()
	queue_redraw()
	_flash("City loaded.")


func _new_city() -> void:
	tiles.fill(Tile.EMPTY)
	_update_stats()
	_update_info()
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

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

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
		+ "Scroll or pinch: zoom   ·   1-5: tools   ·   Cmd+S save, Cmd+L load"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(help)

	if map_credits != "":
		var credits := Label.new()
		credits.text = map_credits
		credits.add_theme_font_size_override("font_size", 11)
		credits.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		box.add_child(credits)

	confirm_new = ConfirmationDialog.new()
	confirm_new.title = "New city"
	confirm_new.dialog_text = "Clear everything you've built and start again?"
	confirm_new.confirmed.connect(_new_city)
	layer.add_child(confirm_new)


func _add_button(parent: Node, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)


func _update_info() -> void:
	if not _in_map(hover):
		info_label.text = "Tool: %s" % TOOL_NAMES[current_tool]
		return
	var i := _index(hover.x, hover.y)
	var ground := "Sea" if water[i] == 1 else "Land, %.0f m above sea level" % heights[i]
	info_label.text = "Tool: %s   ·   Tile %d, %d   ·   %s   ·   %s" % [
		TOOL_NAMES[current_tool], hover.x, hover.y, ground, TILE_NAMES[tiles[i]]]


func _update_stats() -> void:
	var counts := {Tile.ROAD: 0, Tile.HOMES: 0, Tile.SHOPS: 0, Tile.INDUSTRY: 0}
	for t in tiles:
		if counts.has(t):
			counts[t] += 1
	var km := map_w * cell_size_m / 1000.0
	stats_label.text = "Roads %d  ·  Homes %d  ·  Shops %d  ·  Industry %d\nMap %d × %d tiles  ·  %.1f km across  ·  %d m per tile" % [
		counts[Tile.ROAD], counts[Tile.HOMES], counts[Tile.SHOPS], counts[Tile.INDUSTRY],
		map_w, map_h, km, int(cell_size_m)]


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
