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
const Advisors = preload("res://scripts/advisors.gd")

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
	await _launch_dialog()
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
	check(Simulation.Tile.HARBOUR == 28 and wood == 29 and Simulation.LAST_TILE == wood,
		"woodland is a new tile number on the end (old saves' tiles keep their numbers)")
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
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://troon_save.json"))
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
	var path := "user://troon_playtest_pre_woodland.json"
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
	var money := sim.money
	game.call("_set_speed", 1)
	await _open_new_city_from_menu()
	check(hud.is_modal(), "New city in the menu opens the dialog")
	check((hud.get("_new_warning") as Control).visible, "...warning that it clears the city")
	check(int(game.get("speed")) == 0, "...and pauses the clock")
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
	var path := "user://troon_playtest_old_save.json"
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
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://troon_save.json"))
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
