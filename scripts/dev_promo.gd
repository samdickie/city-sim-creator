extends "res://scripts/dev_examples.gd"
## Dev tool, not part of the game: films a short promotional video of the game.
##
## Run it with tools/make_promo.sh, which starts Godot in a window like this:
##   Godot --path . --windowed -- --promo=<frame dir> [--promo-size=1920x1080] [--promo-only=skyline,night]
## and then joins the frames into an MP4 with ffmpeg. game3d.gd adds this node
## when it sees --promo=; in normal play it is never made.
##
## The film is drawn frame by frame, not in real time: every frame the camera is
## put where the shot says, the game draws, and the picture is saved (30 a
## second of film, however long each takes to draw). First the City example's
## plan is laid out on the empty map and grown with the simulation's real tick(),
## a month a frame; then the finished example (examples/city.json) is loaded for
## the fly-rounds. Nothing in the pictures is faked.

const FPS := 30
const WARM_UP := 24                   # frames drawn but not kept after a cut (shadows, trees, props settle)
# No place names in the film: it should read as a city builder set anywhere.
const OPENING := "EMPTY LAND"
const OPENING_SUB := "Nothing built yet."
const TITLE := "BUILD YOUR CITY"
const TAGLINE := "A city builder on real terrain"
const HUD_CITY_NAME := "My City"       # shown in place of the town's name in the interface

var film_size := Vector2i(1920, 1080)
var only_scenes: PackedStringArray = []
var stills := false                   # --promo-stills: pictures to go with a post, no film
var _frame_no := 0
var _last_tick := 0
var _city_loaded := false
var _layer: CanvasLayer
var _fade: ColorRect
var _counter: Label
var _counter_small: Label
var _title: Label
var _sub: Label
var _caption: Label


static func wanted_promo(args: PackedStringArray) -> bool:
	for a: String in args:
		if a.begins_with("--promo="):
			return true
	return false


func _init(game_node: Node3D, args: PackedStringArray) -> void:
	super(game_node, args)
	name = "DevPromo"
	for a: String in args:
		if a.begins_with("--promo="):
			out_dir = a.trim_prefix("--promo=")
		elif a.begins_with("--promo-size="):
			var parts := a.trim_prefix("--promo-size=").split("x")
			if parts.size() == 2:
				film_size = Vector2i(int(parts[0]), int(parts[1]))
		elif a == "--promo-stills":
			stills = true
		elif a.begins_with("--promo-only="):
			only_scenes = a.trim_prefix("--promo-only=").split(",", false)
	if out_dir.is_relative_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)


func _run() -> void:
	var started := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_skip_import(out_dir)
	game.call("_set_speed", 0)
	game.set("day_cycle", false)
	game.set("fit_to_screen", false)
	game.set_process_input(false)             # the real mouse and keys do nothing while filming
	game.set_process_unhandled_input(false)
	get_window().content_scale_factor = 1.0
	get_viewport().scaling_3d_scale = 1.0
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = SHOT_SIZE if stills else film_size
	hud.visible = false
	_rename_city(hud)
	_build_overlay()
	await get_tree().process_frame
	if stills:
		await _run_stills()
		return
	print("[promo] filming at %s, %d frames a second, to %s" % [film_size, FPS, out_dir])

	for scene: Array in [["empty", _scene_empty], ["grow", _scene_grow], ["skyline", _scene_skyline],
			["street", _scene_street], ["suburb", _scene_suburb], ["coast", _scene_coast],
			["works", _scene_works], ["views", _scene_views], ["night", _scene_night], ["title", _scene_title]]:
		var scene_name: String = scene[0]
		if not only_scenes.is_empty() and not only_scenes.has(scene_name):
			continue
		var first := _frame_no
		var t0 := Time.get_ticks_msec()
		var run: Callable = scene[1]
		await run.call()
		print("[promo] %s: frames %d-%d (%.1f s of film) in %.0f s" % [scene_name, first, _frame_no - 1,
			float(_frame_no - first) / FPS, (Time.get_ticks_msec() - t0) / 1000.0])
	Engine.time_scale = 1.0
	print("[promo] done: %d frames (%.1f s of film) in %.0f s" % [_frame_no, float(_frame_no) / FPS,
		(Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(0)


# -------------------------------------------------------------------- stills

func _run_stills() -> void:
	# Pictures to post beside the film (1600x1000), taken like the screenshots.
	# No place names: the interface's town name is already swapped.
	game.call("_new_city", 1)
	await _shoot({"name": "1_world", "at": Vector2(56, 62), "yaw": -34.0, "pitch": 32.0, "dist": 3900.0, "time": 0.58})
	game.call("_load_example", "city")
	_finish_example()
	var plain := func() -> void: game.call("_set_overlay", WorldView.Overlay.NONE)
	for shot: Dictionary in [
		{"name": "2_build_menu", "at": Vector2(50, 61), "yaw": -40.0, "pitch": 36.0, "dist": 1500.0, "hud": true,
			"prep": _prep_build_menu},
		{"name": "3_growth", "at": Vector2(47, 64), "yaw": -40.0, "pitch": 17.0, "dist": 720.0, "prep": plain},
		{"name": "3_growth_b", "at": Vector2(50, 70), "yaw": 20.0, "pitch": 15.0, "dist": 800.0, "prep": plain},
		{"name": "4_happiness", "at": Vector2(52, 60), "yaw": -40.0, "pitch": 40.0, "dist": 1500.0, "hud": true,
			"prep": _prep_city_panel},
		{"name": "5_traffic", "at": Vector2(54, 58), "yaw": -40.0, "pitch": 55.0, "dist": 2500.0, "hud": true,
			"prep": _prep_traffic},
		{"name": "5_power", "at": Vector2(58, 62), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0, "hud": true,
			"prep": _prep_view.bind(WorldView.Overlay.POWER)},
		{"name": "6_view_land_value", "at": Vector2(58, 62), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"prep": func() -> void: game.call("_set_overlay", WorldView.Overlay.LAND_VALUE)},
		{"name": "6_view_services", "at": Vector2(58, 62), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"prep": func() -> void: game.call("_set_overlay", WorldView.Overlay.SERVICES)},
		{"name": "6_view_pollution", "at": Vector2(58, 62), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"prep": func() -> void: game.call("_set_overlay", WorldView.Overlay.POLLUTION)},
		{"name": "6_view_traffic", "at": Vector2(58, 62), "yaw": -40.0, "pitch": 55.0, "dist": 3200.0,
			"prep": func() -> void: game.call("_set_overlay", WorldView.Overlay.TRAFFIC)},
		{"name": "6_night", "at": Vector2(48, 64), "yaw": -40.0, "pitch": 24.0, "dist": 1200.0, "time": 0.80, "prep": plain},
		{"name": "7_close", "at": Vector2(63, 51), "yaw": -30.0, "pitch": 30.0, "dist": 420.0, "prep": plain},
	]:
		await _shoot(shot)
	get_tree().quit(1 if _failed > 0 else 0)


func _prep_city_panel() -> void:
	# The interface with the City panel open: happiness and what it's made of, the budget.
	_hud_reset()
	game.call("_set_overlay", WorldView.Overlay.NONE)
	hud.set_build_open(false)
	game.call("_select_tool", 0)
	hud.get("_city_button").button_pressed = true


# ------------------------------------------------------------------- filming

func _frame() -> void:
	# Let the game take the frame in (redraws, time of day), draw it, keep it.
	traffic.update(1.0 / FPS, rig.target, rig.distance)
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != film_size:
		image.resize(film_size.x, film_size.y, Image.INTERPOLATE_LANCZOS)
	image.save_jpg(out_dir.path_join("f%05d.jpg" % _frame_no), 0.94)
	_frame_no += 1
	# Things that move by the engine's own clock (the sea, smoke) should move a
	# 30th of a second per frame of film, however long the frame took to draw.
	var now := Time.get_ticks_msec()
	if _last_tick > 0:
		Engine.time_scale = clampf((1000.0 / FPS) / maxf(float(now - _last_tick), 1.0), 0.01, 1.0)
	_last_tick = now


func _settle(frames: int = WARM_UP, drive_seconds: float = 0.0) -> void:
	# After a cut: draw a few frames that aren't kept, and let the cars get going.
	game.set("hover", Vector2i(-1, -1))
	world.set_hover(Vector2i(-1, -1), true)
	for k: int in roundi(drive_seconds * FPS):
		traffic.update(1.0 / FPS, rig.target, rig.distance)
	for n: int in frames:
		traffic.update(1.0 / FPS, rig.target, rig.distance)
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	_last_tick = 0


func _cam(at: Vector2, yaw: float, pitch: float, dist: float) -> void:
	# at: the tile looked at; yaw and pitch in degrees (yaw -40 = from the
	# south-west); dist in metres.
	var wx: float = (at.x + 0.5) * world.cell
	var wz: float = (at.y + 0.5) * world.cell
	rig.target = Vector3(wx, maxf(world.height_at(wx, wz), 0.0), wz)
	rig.yaw = deg_to_rad(yaw)
	rig.pitch = deg_to_rad(pitch)
	rig.distance = dist
	rig.snap()


func _pose(a: Array, b: Array, t: float) -> void:
	# Between two camera positions [at, yaw, pitch, dist]: zoom by ratio, so it
	# feels the same speed all the way.
	var at_a: Vector2 = a[0]
	var at_b: Vector2 = b[0]
	var dist_a: float = a[3]
	var dist_b: float = b[3]
	_cam(at_a.lerp(at_b, t), lerpf(float(a[1]), float(b[1]), t), lerpf(float(a[2]), float(b[2]), t),
		dist_a * pow(dist_b / dist_a, t))


func _move(seconds: float, a: Array, b: Array, ease_amount: float = 0.0, each: Callable = Callable()) -> void:
	# Film a camera move. ease_amount 0 = steady speed (lively), 1 = eased at both ends.
	var n := roundi(seconds * FPS)
	for k: int in n:
		var t := float(k) / maxf(n - 1.0, 1.0)
		_pose(a, b, lerpf(t, smoothstep(0.0, 1.0, t), ease_amount))
		if each.is_valid():
			each.call(t)
		await _frame()


func _rename_city(node: Node) -> void:
	# The interface's own name for the town (top left).
	var l := node as Label
	if l and l.text == String(game.get("map_name")):
		l.text = HUD_CITY_NAME
	for child: Node in node.get_children():
		_rename_city(child)


func _daytime(t: float) -> void:
	game.set("time_of_day", t)


# ------------------------------------------------------------------- the words

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)
	var s := film_size.y / 1080.0
	var w := float(film_size.x)
	var h := float(film_size.y)
	_counter = _text(120.0 * s, 800, HORIZONTAL_ALIGNMENT_LEFT)
	_counter.position = Vector2(70.0 * s, h - 270.0 * s)
	_counter.size = Vector2(w, 130.0 * s)
	_counter_small = _text(58.0 * s, 700, HORIZONTAL_ALIGNMENT_LEFT)
	_counter_small.position = Vector2(76.0 * s, h - 130.0 * s)
	_counter_small.size = Vector2(w, 74.0 * s)
	_title = _text(150.0 * s, 800, HORIZONTAL_ALIGNMENT_CENTER)
	_title.position = Vector2(0.0, h * 0.5 - 130.0 * s)
	_title.size = Vector2(w, 170.0 * s)
	_sub = _text(52.0 * s, 500, HORIZONTAL_ALIGNMENT_CENTER)
	_sub.position = Vector2(0.0, h * 0.5 + 50.0 * s)
	_sub.size = Vector2(w, 60.0 * s)
	_caption = _text(54.0 * s, 700, HORIZONTAL_ALIGNMENT_LEFT)
	_caption.position = Vector2(70.0 * s, h - 140.0 * s)
	_caption.size = Vector2(w, 70.0 * s)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)


func _text(font_size: float, weight: int, align: HorizontalAlignment) -> Label:
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["Helvetica Neue", "Arial"])
	base.font_weight = weight
	# (System fonts don't always come in the weight asked for: thicken the strokes too.)
	var font := FontVariation.new()
	font.base_font = base
	font.variation_embolden = 0.9 if weight >= 700 else 0.3
	var look := LabelSettings.new()
	look.font = font
	look.font_size = roundi(font_size)
	look.font_color = Color.WHITE
	look.shadow_color = Color(0, 0, 0, 0.55)
	look.shadow_size = maxi(roundi(font_size * 0.12), 2)
	look.shadow_offset = Vector2(0, font_size * 0.03)
	var l := Label.new()
	l.label_settings = look
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = ""
	_layer.add_child(l)
	return l


func _words(counter: String = "", small: String = "", title: String = "", sub: String = "", caption: String = "") -> void:
	_counter.text = counter
	_counter_small.text = small
	_title.text = title
	_sub.text = sub
	_caption.text = caption


func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


# ------------------------------------------------------------------ the scenes

func _scene_empty() -> void:
	# The empty coast, in from black.
	game.call("_new_city", 1)
	_daytime(0.58)
	_cam(Vector2(56, 62), -34.0, 40.0, 4300.0)
	_words("", "", OPENING, OPENING_SUB)
	await _settle(40)
	await _move(1.4, [Vector2(56, 62), -34.0, 40.0, 4300.0], [Vector2(56, 62), -35.0, 40.0, 4050.0], 0.0,
		func(t: float) -> void: _fade.color.a = 1.0 - smoothstep(0.0, 0.3, t))
	_fade.color.a = 0.0


func _scene_grow() -> void:
	# Twenty years in a few seconds: the City example's plan, grown by the real
	# rules, a month (or two) a frame, as the camera comes down into the centre.
	seed(SEED)
	sim.set("_rng", _seeded_rng(SEED))
	traffic.set("_rng", _seeded_rng(SEED + 1))
	_pending.clear()
	_build_city()
	game.set("_ground_dirty", true)
	game.set("_buildings_dirty", true)
	var from := [Vector2(56, 62), -35.0, 40.0, 4050.0]
	var to := [Vector2(47, 64), -8.0, 27.0, 1250.0]
	_words()
	_pose(from, to, 0.0)
	await _settle(8)
	# Frames per month early on (when most of the building happens), then months per frame.
	var total := 0
	var plan: Array[Array] = []           # [months to run, frames to hold]
	var m := 0
	while m < 240:
		if m < 36:
			plan.append([1, 2])
			m += 1
		elif m < 120:
			plan.append([1, 1])
			m += 1
		else:
			plan.append([2, 1])
			m += 2
	for p: Array in plan:
		total += int(p[1])
	var done := 0
	for p: Array in plan:
		for k: int in int(p[0]):
			sim.money = RICH
			_build_unlocked()
			seed(SEED + sim.month)
			sim.tick()
		game.set("_ground_dirty", true)
		game.set("_buildings_dirty", true)
		for f: int in int(p[1]):
			var t := float(done) / maxf(total - 1.0, 1.0)
			_pose(from, to, smoothstep(0.0, 1.0, t))
			_words(str(Settings.START_YEAR + floori(sim.month / 12.0)), "%s people" % _thousands(sim.population))
			await _frame()
			done += 1
	print("[promo]   grown to month %d: %d people" % [sim.month, sim.population])


func _load_city() -> void:
	# The finished example, as the game menu loads it.
	if _city_loaded:
		return
	_city_loaded = true
	game.call("_load_example", "city")
	_finish_example()
	hud.visible = false
	_words()


func _scene_skyline() -> void:
	# Low past the towers.
	_load_city()
	_daytime(0.6)
	var a := [Vector2(46, 65), -62.0, 15.0, 760.0]
	var b := [Vector2(47, 64), -22.0, 17.0, 700.0]
	_pose(a, b, 0.0)
	await _settle(WARM_UP, 6.0)
	await _move(2.0, a, b)


func _scene_street() -> void:
	# Down a street with the traffic.
	_load_city()
	_daytime(0.56)
	# (South down the busiest street, towards the towers.)
	var a := [Vector2(49.0, 43.0), 180.0, 13.0, 110.0]
	var b := [Vector2(49.0, 55.0), 180.0, 13.0, 110.0]
	_pose(a, b, 0.0)
	await _settle(WARM_UP, 20.0)
	await _move(2.0, a, b)


func _scene_suburb() -> void:
	# Gardens and villas.
	_load_city()
	_daytime(0.42)
	var a := [Vector2(44, 38), -30.0, 30.0, 520.0]
	var b := [Vector2(49, 36), -58.0, 26.0, 400.0]
	_pose(a, b, 0.0)
	await _settle(WARM_UP, 6.0)
	await _move(1.6, a, b)


func _scene_coast() -> void:
	# Along the shore from the sea: the seafront park and the skyline behind.
	_load_city()
	_daytime(0.62)
	var a := [Vector2(39, 84), -112.0, 13.0, 900.0]
	var b := [Vector2(39, 66), -98.0, 15.0, 820.0]
	_pose(a, b, 0.0)
	await _settle(WARM_UP, 4.0)
	await _move(1.8, a, b)


func _scene_works() -> void:
	# The works and the power stations.
	_load_city()
	_daytime(0.6)
	var a := [Vector2(80, 78), -35.0, 24.0, 620.0]
	var b := [Vector2(81, 75), -75.0, 20.0, 520.0]
	_pose(a, b, 0.0)
	await _settle(WARM_UP, 6.0)
	await _move(1.6, a, b)


func _scene_views() -> void:
	# The game itself: the interface, flicking through the map views.
	_load_city()
	_daytime(0.6)
	get_window().content_scale_factor = film_size.y / 720.0     # the interface at a readable size
	_hud_reset()
	hud.set_build_open(false)
	hud.visible = true
	game.call("_select_tool", 0)
	var a := [Vector2(57, 60), -40.0, 52.0, 3300.0]
	var b := [Vector2(56, 61), -30.0, 50.0, 2900.0]
	_pose(a, b, 0.0)
	var views := [WorldView.Overlay.NONE, WorldView.Overlay.LAND_VALUE, WorldView.Overlay.TRAFFIC,
		WorldView.Overlay.SERVICES, WorldView.Overlay.POLLUTION]
	game.call("_set_overlay", views[0])
	await _settle(WARM_UP)
	var shown := [0]
	await _move(3.0, a, b, 0.0, func(t: float) -> void:
		var want := mini(int(t * views.size()), views.size() - 1)
		if want != int(shown[0]):
			shown[0] = want
			game.call("_set_overlay", views[want]))
	game.call("_set_overlay", WorldView.Overlay.NONE)
	hud.visible = false
	get_window().content_scale_factor = 1.0


func _scene_night() -> void:
	# The sun goes down over the centre and the lights come on.
	_load_city()
	var a := [Vector2(48, 64), -72.0, 20.0, 1500.0]
	var b := [Vector2(48, 64), -30.0, 22.0, 1150.0]
	_pose(a, b, 0.0)
	_daytime(0.715)
	await _settle(WARM_UP, 6.0)
	await _move(3.2, a, b, 0.0, func(t: float) -> void: _daytime(lerpf(0.715, 0.80, t)))


func _scene_title() -> void:
	# Pull back over the lit city; the name; out to black.
	_load_city()
	_daytime(0.80)
	var a := [Vector2(48, 64), -30.0, 22.0, 1150.0]
	var b := [Vector2(54, 62), -42.0, 36.0, 3600.0]
	_pose(a, b, 0.0)
	await _settle(8)
	await _move(3.2, a, b, 0.6, func(t: float) -> void:
		_daytime(lerpf(0.80, 0.86, t))
		var show := smoothstep(0.25, 0.45, t)
		_words("", "", TITLE if show > 0.0 else "", TAGLINE if show > 0.0 else "")
		_title.modulate.a = show
		_sub.modulate.a = smoothstep(0.35, 0.55, t)
		_fade.color.a = smoothstep(0.88, 1.0, t))
