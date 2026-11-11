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
const Traffic = preload("res://scripts/traffic.gd")
const DevShots = preload("res://scripts/dev_shots.gd")

const WATCHDOG_SECONDS := 600.0
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
	await _wait(1.0)
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
	await _new_city()
	print("[play] done: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


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

func _find_land() -> Vector2i:
	# A flat patch of open land, 14 x 12 tiles, near where the camera starts:
	# where a player would start a town.
	var start := Vector2i(roundi(rig.target.x / world.cell), roundi(rig.target.z / world.cell))
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	var water: PackedByteArray = game.get("water")
	var slope: PackedFloat32Array = game.get("slope")
	for y: int in range(4, sim.h - 16):
		for x: int in range(4, sim.w - 18):
			var ok := true
			for dy: int in 12:
				for dx: int in 14:
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
	check(sim.population == 0 and sim.money == Settings.START_MONEY, "a new game starts blank with £%d" % Settings.START_MONEY)
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
	await _key(KEY_H)
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
	check(FileAccess.file_exists("user://troon_save.json"), "Save writes the save file")
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
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://troon_save.json"))
	check(typeof(data) == TYPE_DICTIONARY and int((data as Dictionary).get("version", 0)) == 3, "the save file is version 3, as before")


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


func _new_city() -> void:
	await _click(hud.get("_menu_button"))
	var menu: PanelContainer = hud.get("_menu_panel")
	await _click(_find_button(menu, "New city"))
	var dialog: ConfirmationDialog = hud.confirm_new
	await _wait(0.3)
	check(dialog.visible, "New city asks first")
	# (The dialog is a window of its own: its buttons are placed within it.)
	await _click_at(Vector2(dialog.position) + dialog.get_ok_button().get_global_rect().get_center())
	await _wait(0.2)
	await _wait(0.2)
	var built := 0
	for i: int in sim.w * sim.h:
		if sim.tiles[i] != Simulation.Tile.EMPTY:
			built += 1
	check(built == 0 and sim.population == 0, "New city clears the map")
