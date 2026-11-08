extends Node3D
## People and traffic: cars, buses and people walking about the streets.
## Purely for show; nothing here affects the simulation.
##
## Each car or person crosses one road tile at a time, in from one edge and out
## of another, along the same straight runs and bends the roads are drawn with:
## cars keep left (UK), people walk on the pavements. At a junction they pick a
## way at random (no real route finding). Only the streets round the camera are
## filled, and the numbers follow how busy each street is: the homes, shops and
## jobs beside it, fewer at night, none until the town has people or jobs.
## Everything is drawn with a few MultiMeshes whose buffers are rebuilt each frame.

signal message(text: String)

const Settings = preload("res://scripts/settings.gd")
const Simulation = preload("res://scripts/simulation.gd")
const WorldView = preload("res://scripts/world3d.gd")

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const LINK_COUNT: Array[int] = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4]   # roads out of a tile, by bits
const LANE := 2.3              # metres left of the road's centre line (keep left)
const PAVEMENT := 5.1          # metres from the centre line to the middle of the pavement
const JUNCTION_TURN := 6.0     # radius of a turn round the corner of a junction's open square
const ROAD_LIFT := 0.35        # road surface above the ground (as world3d.gd draws it)
const CAR_SIZE := Vector3(1.8, 1.05, 4.2)
const BUS_SIZE := Vector3(2.5, 2.9, 11.0)
const CAR_SPEED := Vector2(10.0, 14.5)   # metres per second (about 22 to 32 mph)
const BUS_SPEED := Vector2(8.0, 10.0)
const BEND_SPEED := 9.0        # round a corner
const TURN_SPEED := 5.5        # turning at a junction
const U_TURN_SPEED := 5.0      # turning round at a dead end
const WALK_SPEED := Vector2(1.1, 1.6)
const CAR_AREA_MIN := 300.0    # cars fill the streets this far round the camera...
const CAR_AREA_MAX := 1800.0   # ...growing with the zoom, up to this
const WALK_AREA := 700.0       # people only near the camera (they're tiny further off)
const CARS_SHOWN_UNTIL := 3500.0    # camera distance beyond which no cars are drawn
const PEOPLE_SHOWN_UNTIL := 1100.0  # ...and no people
const ADD_PER_FRAME := 6       # new arrivals per frame, so numbers change gently
const MEASURE_PER_FRAME := 250 # streets re-measured per frame after the town changes
const HALF_RATE_PEOPLE := 150  # above this many people, each moves every other frame
const STRIDE := 16             # floats per instance in a MultiMesh buffer: transform + colour

const PAINT: Array[Color] = [
	Color(0.92, 0.92, 0.92), Color(0.74, 0.75, 0.77), Color(0.08, 0.08, 0.09),
	Color(0.55, 0.07, 0.07), Color(0.10, 0.20, 0.45), Color(0.33, 0.35, 0.38),
	Color(0.86, 0.85, 0.80), Color(0.18, 0.28, 0.24), Color(0.62, 0.62, 0.66),
	Color(0.80, 0.80, 0.82), Color(0.15, 0.15, 0.17), Color(0.72, 0.42, 0.12),
	Color(0.40, 0.55, 0.70), Color(0.85, 0.18, 0.12),
]
const BUS_PAINT := Color(0.72, 0.12, 0.10)
const CLOTHES: Array[Color] = [
	Color(0.10, 0.12, 0.20), Color(0.08, 0.08, 0.09), Color(0.35, 0.36, 0.38), Color(0.62, 0.55, 0.42),
	Color(0.55, 0.12, 0.12), Color(0.16, 0.32, 0.20), Color(0.22, 0.32, 0.52), Color(0.78, 0.62, 0.20),
	Color(0.85, 0.84, 0.80), Color(0.42, 0.24, 0.40), Color(0.20, 0.45, 0.55),
]
const SKIN: Array[Color] = [
	Color(0.94, 0.78, 0.66), Color(0.86, 0.66, 0.52), Color(0.70, 0.50, 0.36),
	Color(0.48, 0.32, 0.22), Color(0.32, 0.21, 0.15),
]
const HEADLIGHT := Color(4.0, 3.7, 3.0)    # brighter than white, so the glow picks them up
const TAIL_LIGHT := Color(3.0, 0.15, 0.08)
const BEAM := Color(1.0, 0.9, 0.72, 0.45)

enum Part { BODY, CABIN, LAMP, BEAM, WALKER, HEAD }   # the MultiMeshes, in order

var world: WorldView
var sim: Simulation
var enabled := Settings.TRAFFIC_ON

# What's drawn: one shared buffer, a slice of it per MultiMesh.
var _parts: Array[MultiMeshInstance3D] = []
var _part_start := PackedInt32Array()   # first instance of each part in _buf
var _part_cap := PackedInt32Array()     # how many instances each part can hold
var _buf := PackedFloat32Array()

# The road network.
var _w := 0
var _h := 0
var _steps := PackedInt32Array()        # tile index change for each of DIRS
var _links := PackedByteArray()         # per tile: bit d = road carries on towards DIRS[d] (0 = no road)
var _roads := PackedInt32Array()        # every road tile joined to another
var _depots := PackedInt32Array()       # bus depot tiles
var _bus_area := PackedByteArray()      # 1 = road within reach of a working bus depot
var _car_weight := PackedFloat32Array() # per road tile: cars it draws in the daytime
var _walk_weight := PackedFloat32Array()# ...and people walking
var _layout_seen := -1
var _month_seen := -1
var _measure_at := -1                   # next road to re-measure (-1 = all up to date)

# The streets round the camera.
var _focus := Vector2(INF, INF)
var _radius := 0.0
var _area_dirty := true
var _cars_shown := false
var _people_shown := false
var _car_tiles := PackedInt32Array()
var _car_cum := PackedFloat32Array()    # running total of weights, to pick busy streets more often
var _car_total := 0.0
var _walk_tiles := PackedInt32Array()
var _walk_cum := PackedFloat32Array()
var _walk_total := 0.0
var _bus_tiles := PackedInt32Array()
var _car_target := 0
var _bus_target := 0
var _walk_target := 0

# Cars and buses: tile, the side they came in and go out, metres along the way
# across the tile, its length, usual speed, speed limit here, speed now.
var _v_tile := PackedInt32Array()
var _v_entry := PackedByteArray()
var _v_exit := PackedByteArray()
var _v_dist := PackedFloat32Array()
var _v_len := PackedFloat32Array()
var _v_cruise := PackedFloat32Array()
var _v_limit := PackedFloat32Array()
var _v_speed := PackedFloat32Array()
var _v_paint := PackedColorArray()
var _v_bus := PackedByteArray()
var _buses := 0

# People: as above, plus which side of the street (signed offset) and looks.
var _p_tile := PackedInt32Array()
var _p_entry := PackedByteArray()
var _p_exit := PackedByteArray()
var _p_dist := PackedFloat32Array()
var _p_len := PackedFloat32Array()
var _p_speed := PackedFloat32Array()
var _p_offset := PackedFloat32Array()
var _p_scale := PackedFloat32Array()
var _p_clothes := PackedColorArray()
var _p_skin := PackedColorArray()

var _rng := RandomNumberGenerator.new()
var _frame := 0
var _lights := false
var _redraw := false                    # someone jumped to a new street (redraw even when paused)
var _out_pos := Vector2.ZERO            # results of _locate()
var _out_dir := Vector2.ZERO


func setup(world_view: WorldView, simulation: Simulation) -> void:
	world = world_view
	sim = simulation
	_rng.randomize()
	_w = world.map_w
	_h = world.map_h
	_steps = PackedInt32Array([1, -1, _w, -_w])
	visible = enabled

	# Cars: a box for the body and a smaller dark one for the cabin windows.
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	paint.metallic = 0.5
	paint.roughness = 0.35
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.06, 0.08, 0.1)
	glass.metallic = 0.6
	glass.roughness = 0.1
	# Head and tail lights glow (colours above 1 bloom); only shown after dark.
	var lamp := StandardMaterial3D.new()
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.vertex_color_use_as_albedo = true
	# A soft pool of light on the road ahead of each car at night.
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var pool := GradientTexture2D.new()
	pool.gradient = fade
	pool.fill = GradientTexture2D.FILL_RADIAL
	pool.fill_from = Vector2(0.5, 1.0)     # the end nearest the car
	pool.fill_to = Vector2(0.5, 0.5)
	pool.width = 64
	pool.height = 64
	var beam := StandardMaterial3D.new()
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.albedo_texture = pool
	beam.vertex_color_use_as_albedo = true
	var beam_mesh := PlaneMesh.new()
	beam_mesh.size = Vector2(1.0, 1.0)
	# People: a coat (a capsule) and a head.
	var cloth := StandardMaterial3D.new()
	cloth.vertex_color_use_as_albedo = true
	cloth.vertex_color_is_srgb = true
	cloth.roughness = 0.9
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.21
	body_mesh.height = 1.45
	body_mesh.radial_segments = 6
	body_mesh.rings = 1
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.12
	head_mesh.height = 0.24
	head_mesh.radial_segments = 6
	head_mesh.rings = 3

	var cars: int = Settings.MAX_CARS
	var people: int = Settings.MAX_PEOPLE
	_add_part(BoxMesh.new(), paint, cars, true)       # Part.BODY
	_add_part(BoxMesh.new(), glass, cars, false)      # Part.CABIN
	_add_part(BoxMesh.new(), lamp, cars * 2, false)   # Part.LAMP
	_add_part(beam_mesh, beam, cars, false)           # Part.BEAM
	_add_part(body_mesh, cloth, people, true)         # Part.WALKER
	_add_part(head_mesh, cloth, people, false)        # Part.HEAD
	_buf.resize(_part_start[Part.HEAD] * STRIDE + people * STRIDE)
	_buf.fill(0.0)


func _add_part(mesh: Mesh, material: Material, cap: int, shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	# They're always near the camera; a fixed box saves working one out every frame.
	mm.custom_aabb = AABB(Vector3(-500.0, -100.0, -500.0),
		Vector3(_w * world.cell + 1000.0, 1000.0, _h * world.cell + 1000.0))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	if not shadows:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var start := 0
	if not _parts.is_empty():
		start = _part_start[_parts.size() - 1] + _part_cap[_parts.size() - 1]
	_parts.append(node)
	_part_start.append(start)
	_part_cap.append(cap)


# ------------------------------------------------------------- on and off

func _unhandled_input(event: InputEvent) -> void:
	# T turns the traffic and people on and off.
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.is_command_or_control_pressed():
		return
	if k.keycode == KEY_T:
		set_enabled(not enabled)
		message.emit("Cars and people on the streets: %s (T to turn them %s)." % [
			"on" if enabled else "off", "off" if enabled else "back on"])
		get_viewport().set_input_as_handled()


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	_clear()
	_area_dirty = true


func _clear() -> void:
	_resize_vehicles(0)
	_resize_people(0)
	_buses = 0
	for node: MultiMeshInstance3D in _parts:
		node.multimesh.visible_instance_count = 0


func _resize_vehicles(n: int) -> void:
	_v_tile.resize(n)
	_v_entry.resize(n)
	_v_exit.resize(n)
	_v_dist.resize(n)
	_v_len.resize(n)
	_v_cruise.resize(n)
	_v_limit.resize(n)
	_v_speed.resize(n)
	_v_paint.resize(n)
	_v_bus.resize(n)


func _resize_people(n: int) -> void:
	_p_tile.resize(n)
	_p_entry.resize(n)
	_p_exit.resize(n)
	_p_dist.resize(n)
	_p_len.resize(n)
	_p_speed.resize(n)
	_p_offset.resize(n)
	_p_scale.resize(n)
	_p_clothes.resize(n)
	_p_skin.resize(n)


# ------------------------------------------------------------- each frame

func update(delta: float, focus: Vector3, view_distance: float) -> void:
	# delta is game time (0 when paused); focus is the point the camera looks at.
	if not enabled or world == null:
		return
	_frame += 1
	if sim.layout_version != _layout_seen:
		_read_roads()
	if sim.month != _month_seen:
		_month_seen = sim.month
		_measure_at = 0                 # the town has grown or shrunk: re-measure the streets
	if _measure_at >= 0:
		_measure_some()
	_follow_camera(Vector2(focus.x, focus.z), view_distance)
	_set_targets()

	var lights: bool = world.night > 0.3
	var changed := delta > 0.0 or lights != _lights or _redraw
	_redraw = false
	_lights = lights
	changed = _fleet_size() or changed
	changed = _crowd_size() or changed
	if not changed:
		return                          # paused and nothing new: the last frame still stands
	_drive(delta)
	_walk(delta)
	_upload()


# ------------------------------------------------------------ the streets

func _read_roads() -> void:
	# Which tiles are roads and which way each one goes. Only after the layout changes.
	_layout_seen = sim.layout_version
	var tiles: PackedByteArray = sim.tiles
	var size := _w * _h
	if _links.size() != size:
		_links.resize(size)
		_bus_area.resize(size)
		_car_weight.resize(size)
		_walk_weight.resize(size)
	_roads.clear()
	_depots.clear()
	for y: int in _h:
		for x: int in _w:
			var i := y * _w + x
			var t: int = tiles[i]
			if t == Simulation.Tile.BUS_DEPOT:
				_depots.append(i)
			var m := 0
			if t == Simulation.Tile.ROAD:
				if x + 1 < _w and tiles[i + 1] == Simulation.Tile.ROAD:
					m |= 1
				if x > 0 and tiles[i - 1] == Simulation.Tile.ROAD:
					m |= 2
				if y + 1 < _h and tiles[i + _w] == Simulation.Tile.ROAD:
					m |= 4
				if y > 0 and tiles[i - _w] == Simulation.Tile.ROAD:
					m |= 8
			_links[i] = m
			if m != 0:
				_roads.append(i)
			else:
				_car_weight[i] = 0.0
				_walk_weight[i] = 0.0
	# The streets round the camera are worked out again (see _follow_camera);
	# until then anyone whose way ahead has gone starts again on any road.
	_car_tiles.clear()
	_car_cum.clear()
	_walk_tiles.clear()
	_walk_cum.clear()
	_bus_tiles.clear()
	for n: int in _v_tile.size():
		if ((_links[_v_tile[n]] >> _v_exit[n]) & 1) == 0:
			_respawn_vehicle(n)
	for n: int in _p_tile.size():
		if ((_links[_p_tile[n]] >> _p_exit[n]) & 1) == 0:
			_respawn_person(n)
	_measure_at = 0
	_area_dirty = true


func _measure_some() -> void:
	# A few hundred streets a frame: how many cars and people each one draws.
	if _measure_at == 0:
		_mark_bus_area()
	var end := mini(_measure_at + MEASURE_PER_FRAME, _roads.size())
	for n: int in range(_measure_at, end):
		_measure(_roads[n])
	_measure_at = end
	if _measure_at >= _roads.size():
		_measure_at = -1
		_area_dirty = true


func _measure(i: int) -> void:
	# Residents and jobs on the plots round a street; shops bring the most people on foot.
	var tiles: PackedByteArray = sim.tiles
	var levels: PackedByteArray = sim.levels
	var x := i % _w
	var y := i / _w
	var cars := 0.0
	var walk := 0.0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var nx := x + dx
			var ny := y + dy
			if (dx == 0 and dy == 0) or nx < 0 or ny < 0 or nx >= _w or ny >= _h:
				continue
			var k := ny * _w + nx
			var t: int = tiles[k]
			if t == Simulation.Tile.HOMES or t == Simulation.Tile.SHOPS or t == Simulation.Tile.INDUSTRY:
				if levels[k] == 0:
					continue
				var u := float(sim.units(k))
				cars += u
				if t == Simulation.Tile.HOMES:
					walk += u * 0.25
				elif t == Simulation.Tile.SHOPS:
					walk += u * 3.0
				else:
					walk += u * 0.2
			elif t == Simulation.Tile.PARK or t == Simulation.Tile.GOLF:
				walk += 6.0
			elif sim.is_service(t) or t >= Simulation.Tile.LIBRARY:
				# Schools, hospitals, landmarks, stations: staff and visitors.
				cars += 30.0
				walk += 30.0
			elif sim.is_building(t) and t != Simulation.Tile.WIND and t != Simulation.Tile.SOLAR:
				cars += 10.0            # power plants and utilities: a few staff
	if sim.district[i] == 2:
		walk *= 1.5                     # the centre is busier on foot
	_car_weight[i] = minf(cars / Settings.PEOPLE_PER_CAR, Settings.CARS_PER_STREET)
	_walk_weight[i] = minf(walk / Settings.PEOPLE_PER_WALKER, Settings.WALKERS_PER_STREET)


func _mark_bus_area() -> void:
	# Buses run on the roads round each working bus depot.
	_bus_area.fill(0)
	var reach: int = int(Settings.BUILDINGS["bus_depot"].get("bus", 14))
	for d: int in _depots:
		if sim.tiles[d] != Simulation.Tile.BUS_DEPOT or not sim.building_working(d):
			continue
		var dx0 := d % _w
		var dy0 := d / _w
		for y: int in range(maxi(dy0 - reach, 0), mini(dy0 + reach + 1, _h)):
			for x: int in range(maxi(dx0 - reach, 0), mini(dx0 + reach + 1, _w)):
				if (x - dx0) * (x - dx0) + (y - dy0) * (y - dy0) <= reach * reach \
						and _links[y * _w + x] != 0:
					_bus_area[y * _w + x] = 1


func _follow_camera(focus: Vector2, view_distance: float) -> void:
	# Fill the streets round where the camera is looking; refresh when it moves on.
	_cars_shown = view_distance < CARS_SHOWN_UNTIL
	_people_shown = view_distance < PEOPLE_SHOWN_UNTIL
	var r := clampf(view_distance * 1.1, CAR_AREA_MIN, CAR_AREA_MAX)
	if _focus.distance_to(focus) > _radius * 0.2 or absf(r - _radius) > _radius * 0.2:
		_area_dirty = true
	if not _area_dirty:
		return
	_area_dirty = false
	_focus = focus
	_radius = r
	var walk_r := minf(r, WALK_AREA)
	var cell: float = world.cell
	_car_tiles.clear()
	_car_cum.clear()
	_walk_tiles.clear()
	_walk_cum.clear()
	_bus_tiles.clear()
	_car_total = 0.0
	_walk_total = 0.0
	var car_sum := 0.0
	var walk_sum := 0.0
	var x0 := clampi(floori((focus.x - r) / cell), 0, _w - 1)
	var x1 := clampi(floori((focus.x + r) / cell), 0, _w - 1)
	var y0 := clampi(floori((focus.y - r) / cell), 0, _h - 1)
	var y1 := clampi(floori((focus.y + r) / cell), 0, _h - 1)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var i := y * _w + x
			if _links[i] == 0:
				continue
			var d := Vector2((x + 0.5) * cell, (y + 0.5) * cell).distance_to(focus)
			if d > r:
				continue
			var cw := _car_weight[i]
			if cw > 0.0:
				_car_total += cw
				car_sum += cw * (1.0 - 0.5 * d / r)    # a little busier towards the middle
				_car_tiles.append(i)
				_car_cum.append(car_sum)
			if _bus_area[i] == 1:
				_bus_tiles.append(i)
			var ww := _walk_weight[i]
			if ww > 0.0 and d <= walk_r:
				_walk_total += ww
				walk_sum += ww * (1.0 - 0.5 * d / walk_r)
				_walk_tiles.append(i)
				_walk_cum.append(walk_sum)
	# Anyone left far behind reappears in view.
	for n: int in _v_tile.size():
		if _tile_distance(_v_tile[n]) > r * 1.15:
			_respawn_vehicle(n)
	for n: int in _p_tile.size():
		if _tile_distance(_p_tile[n]) > walk_r * 1.15:
			_respawn_person(n)


func _tile_distance(i: int) -> float:
	var cell: float = world.cell
	return Vector2((i % _w + 0.5) * cell, (i / _w + 0.5) * cell).distance_to(_focus)


func _set_targets() -> void:
	# How many cars and people there should be now: more for a bigger, busier
	# town, fewer at night, none at all on an empty map.
	var night: float = world.night
	var town: int = sim.population + sim.shop_jobs + sim.industry_jobs
	_car_target = 0
	_bus_target = 0
	_walk_target = 0
	if town <= 0:
		return
	if _cars_shown and not _car_tiles.is_empty():
		_car_target = mini(Settings.MAX_CARS,
			roundi(_car_total * lerpf(1.0, Settings.NIGHT_TRAFFIC, night)))
		if not _bus_tiles.is_empty():
			_bus_target = mini(clampi(_car_target / 12, 1, 10), _car_target)
	if _people_shown and not _walk_tiles.is_empty():
		_walk_target = mini(Settings.MAX_PEOPLE,
			roundi(_walk_total * lerpf(1.0, Settings.NIGHT_WALKERS, night)))


func _pick(tiles: PackedInt32Array, cum: PackedFloat32Array) -> int:
	# A street, busy ones more often.
	var r := _rng.randf() * cum[cum.size() - 1]
	return tiles[mini(cum.bsearch(r), tiles.size() - 1)]


func _random_link(tile: int) -> int:
	var m: int = _links[tile]
	var options: Array[int] = []
	for d: int in 4:
		if ((m >> d) & 1) == 1:
			options.append(d)
	return options[_rng.randi_range(0, options.size() - 1)]


func _choose_exit(tile: int, entry: int, bus: bool, straight_bias: bool) -> int:
	# Any road out except straight back; a dead end means turning round.
	# Buses keep to the roads round their depot when they can.
	var m: int = _links[tile]
	var options: Array[int] = []
	var fallback: Array[int] = []
	for d: int in 4:
		if d == entry or ((m >> d) & 1) == 0:
			continue
		if bus and _bus_area[tile + _steps[d]] == 0:
			fallback.append(d)
			continue
		options.append(d)
		if straight_bias and d == (entry ^ 1):
			options.append(d)           # going straight on is a bit more likely
	if options.is_empty():
		options = fallback
	if options.is_empty():
		return entry
	return options[_rng.randi_range(0, options.size() - 1)]


# ------------------------------------------------------- paths across a tile

func _turn_radius(tile: int) -> float:
	# Corners follow the road's own quarter circle; junctions turn round the open square.
	if LINK_COUNT[_links[tile]] >= 3:
		return JUNCTION_TURN
	return world.cell * 0.5


func _path_length(tile: int, entry: int, exit: int, offset: float) -> float:
	var half: float = world.cell * 0.5
	if exit == entry:
		return half * 2.0 + PI * maxf(absf(offset), 1.0)
	if exit == (entry ^ 1):
		return half * 2.0
	var r := _turn_radius(tile)
	var e := DIRS[entry]
	var left := Vector2i(-e.y, e.x)    # left of the way in (which is -e)
	var arc_r := r - offset if DIRS[exit] == left else r + offset
	return (half - r) * 2.0 + maxf(arc_r, 0.5) * PI * 0.5


func _locate(tile: int, entry: int, exit: int, s: float, offset: float) -> void:
	# Where something is (_out_pos) and which way it faces (_out_dir), s metres
	# along its way across the tile, offset metres to its left of the centre line.
	var cell: float = world.cell
	var half := cell * 0.5
	var c := Vector2((tile % _w + 0.5) * cell, (tile / _w + 0.5) * cell)
	var e := Vector2(DIRS[entry])
	var way_in := -e
	var p0 := c + e * half
	var pos: Vector2
	var dir: Vector2
	if exit == entry:
		# Dead end: into the middle, round in a tight U, and back out.
		var a := maxf(absf(offset), 1.0)
		var sgn := 1.0 if offset >= 0.0 else -1.0
		if s < half:
			pos = p0 + way_in * s
			dir = way_in
		elif s < half + PI * a:
			var start := Vector2(way_in.y, -way_in.x) * a * sgn
			var ang := start.angle() + sgn * (s - half) / a
			_out_pos = c + Vector2.from_angle(ang) * a
			_out_dir = Vector2.from_angle(ang + sgn * PI * 0.5)
			return
		else:
			pos = c + e * (s - half - PI * a)
			dir = e
	elif exit == (entry ^ 1):
		pos = p0 + way_in * s
		dir = way_in
	else:
		var r := _turn_radius(tile)
		var xv := Vector2(DIRS[exit])
		var run := half - r
		var ei := DIRS[entry]
		var arc_r := r - offset if DIRS[exit] == Vector2i(-ei.y, ei.x) else r + offset
		var arc := maxf(arc_r, 0.5) * PI * 0.5
		if s < run:
			pos = p0 + way_in * s
			dir = way_in
		elif s < run + arc:
			# Round the corner on the centre line's quarter circle (the offset
			# below makes it tighter or wider).
			var corner := c + (e + xv) * r
			var a0 := (-xv).angle()
			var turn := wrapf((-e).angle() - a0, -PI, PI)
			var ang := a0 + turn * (s - run) / arc
			pos = corner + Vector2.from_angle(ang) * r
			dir = Vector2.from_angle(ang + signf(turn) * PI * 0.5)
		else:
			pos = c + xv * (r + s - run - arc)
			dir = xv
	_out_pos = pos + Vector2(dir.y, -dir.x) * offset
	_out_dir = dir


func _limit_for(tile: int, entry: int, exit: int) -> float:
	if exit == entry:
		return U_TURN_SPEED
	if exit == (entry ^ 1):
		return 100.0
	return TURN_SPEED if LINK_COUNT[_links[tile]] >= 3 else BEND_SPEED


# ---------------------------------------------------------------- vehicles

func _fleet_size() -> bool:
	# Add or take away a few cars towards the target. True if anything changed.
	var n := _v_tile.size()
	if not _cars_shown or _car_target == 0:
		if n > 0:
			_resize_vehicles(0)
			_buses = 0
			return true
		return false
	var changed := false
	# Too many buses (say a depot closed): take one away.
	if _buses > _bus_target:
		for k: int in n:
			if _v_bus[k] == 1:
				_remove_vehicle(k)
				changed = true
				break
	n = _v_tile.size()
	if n > _car_target:
		for _k: int in mini(n - _car_target, 3):
			_remove_vehicle(_v_tile.size() - 1)
		changed = true
	elif n < _car_target:
		for _k: int in mini(_car_target - n, ADD_PER_FRAME):
			_add_vehicle(_buses < _bus_target)
		changed = true
	return changed


func _add_vehicle(bus: bool) -> void:
	var n := _v_tile.size()
	_resize_vehicles(n + 1)
	_v_bus[n] = 1 if bus else 0
	if bus:
		_buses += 1
		_v_paint[n] = BUS_PAINT
		_v_cruise[n] = _rng.randf_range(BUS_SPEED.x, BUS_SPEED.y)
	else:
		_v_paint[n] = PAINT[_rng.randi_range(0, PAINT.size() - 1)]
		_v_cruise[n] = _rng.randf_range(CAR_SPEED.x, CAR_SPEED.y)
	_respawn_vehicle(n)


func _respawn_vehicle(n: int) -> void:
	# Start again on a street round the camera (busy streets more likely).
	var bus := _v_bus[n] == 1
	var tile: int
	if bus and not _bus_tiles.is_empty():
		tile = _bus_tiles[_rng.randi_range(0, _bus_tiles.size() - 1)]
	elif not _car_tiles.is_empty():
		tile = _pick(_car_tiles, _car_cum)
	elif not _roads.is_empty():
		tile = _roads[_rng.randi_range(0, _roads.size() - 1)]
	else:
		tile = _v_tile[n]
		if _links[tile] == 0:
			return                      # no roads at all; it'll be cleared away
	var entry := _random_link(tile)
	var exit := _choose_exit(tile, entry, bus, true)
	_v_tile[n] = tile
	_v_entry[n] = entry
	_v_exit[n] = exit
	_v_len[n] = _path_length(tile, entry, exit, LANE)
	_v_dist[n] = _rng.randf() * _v_len[n]
	_v_limit[n] = _limit_for(tile, entry, exit)
	_v_speed[n] = minf(_v_cruise[n], _v_limit[n])
	_redraw = true


func _remove_vehicle(n: int) -> void:
	var last := _v_tile.size() - 1
	if _v_bus[n] == 1:
		_buses -= 1
	if n != last:
		_v_tile[n] = _v_tile[last]
		_v_entry[n] = _v_entry[last]
		_v_exit[n] = _v_exit[last]
		_v_dist[n] = _v_dist[last]
		_v_len[n] = _v_len[last]
		_v_cruise[n] = _v_cruise[last]
		_v_limit[n] = _v_limit[last]
		_v_speed[n] = _v_speed[last]
		_v_paint[n] = _v_paint[last]
		_v_bus[n] = _v_bus[last]
	_resize_vehicles(last)


func _drive(delta: float) -> void:
	var n := _v_tile.size()
	if delta > 0.0 and n > 0:
		# Who's in each lane: cars on the same tile that came in the same side.
		var lane_head := {}
		var lane_next := PackedInt32Array()
		lane_next.resize(n)
		for k: int in n:
			var key := _v_tile[k] * 4 + _v_entry[k]
			var first: int = lane_head.get(key, -1)
			lane_next[k] = first
			lane_head[key] = k
		for k: int in n:
			_move_vehicle(k, delta, lane_head, lane_next)
	for k: int in n:
		_draw_vehicle(k)


func _move_vehicle(k: int, delta: float, lane_head: Dictionary, lane_next: PackedInt32Array) -> void:
	# Follow the car in front (on this tile, or just into the next), never into it.
	var my_half := _half_length(k)
	var gap := 1.0e9
	var leader_half := 0.0
	var j: int = lane_head.get(_v_tile[k] * 4 + _v_entry[k], -1)
	while j != -1:
		var g := _v_dist[j] - _v_dist[k]
		if j != k and g > 0.0 and g < gap:
			gap = g
			leader_half = _half_length(j)
		j = lane_next[j]
	var limit := minf(_v_cruise[k], _v_limit[k])
	var remain := _v_len[k] - _v_dist[k]
	if remain < 25.0 and ((_links[_v_tile[k]] >> _v_exit[k]) & 1) == 1:
		var ahead := _v_tile[k] + _steps[_v_exit[k]]
		j = lane_head.get(ahead * 4 + (_v_exit[k] ^ 1), -1)
		while j != -1:
			var g := remain + _v_dist[j]
			if g < gap:
				gap = g
				leader_half = _half_length(j)
			j = lane_next[j]
		# Ease off coming up to a junction, a bend or a dead end.
		limit = minf(limit, _approach_speed(ahead) + remain * 0.6)
	var v := _v_speed[k]
	v = minf(v + 3.5 * delta, limit) if v < limit else maxf(v - 7.0 * delta, limit)
	if gap < 40.0:
		var room := gap - my_half - leader_half - 2.5
		v = minf(v, maxf(room, 0.0) * 1.6)    # brake for the car ahead
	_v_speed[k] = v
	_v_dist[k] += v * delta

	var hops := 0
	while _v_dist[k] >= _v_len[k] and hops < 3:
		hops += 1
		var tile := _v_tile[k]
		var exit: int = _v_exit[k]
		_v_dist[k] -= _v_len[k]
		if ((_links[tile] >> exit) & 1) == 0:
			_respawn_vehicle(k)
			return
		var next := tile + _steps[exit]
		if _links[next] == 0 or _tile_distance(next) > _radius * 1.15:
			_respawn_vehicle(k)         # out of sight: reappear near the camera
			return
		var entry := exit ^ 1
		var out := _choose_exit(next, entry, _v_bus[k] == 1, true)
		_v_tile[k] = next
		_v_entry[k] = entry
		_v_exit[k] = out
		_v_len[k] = _path_length(next, entry, out, LANE)
		_v_limit[k] = _limit_for(next, entry, out)


func _approach_speed(tile: int) -> float:
	var m: int = _links[tile]
	match LINK_COUNT[m]:
		0:
			return 100.0
		1:
			return U_TURN_SPEED
		2:
			return 100.0 if m == 3 or m == 12 else BEND_SPEED   # straight on, or a corner
	return TURN_SPEED + 2.0                                 # a junction (some go straight on)


func _half_length(k: int) -> float:
	return BUS_SIZE.z * 0.5 if _v_bus[k] == 1 else CAR_SIZE.z * 0.5


func _draw_vehicle(k: int) -> void:
	_locate(_v_tile[k], _v_entry[k], _v_exit[k], _v_dist[k], LANE)
	var pos := _out_pos
	var dir := _out_dir
	var bus := _v_bus[k] == 1
	var size := BUS_SIZE if bus else CAR_SIZE
	# Tilt with the slope: ground under the front and back wheels.
	var reach := size.z * 0.4
	var hf := maxf(world.height_at(pos.x + dir.x * reach, pos.y + dir.y * reach), 0.0)
	var hb := maxf(world.height_at(pos.x - dir.x * reach, pos.y - dir.y * reach), 0.0)
	var fwd := Vector3(dir.x * reach * 2.0, hf - hb, dir.y * reach * 2.0).normalized()
	var facing := Basis.looking_at(fwd, Vector3.UP)   # -z forward
	var up := facing.y
	var back := facing.z
	var base := Vector3(pos.x, (hf + hb) * 0.5 + ROAD_LIFT, pos.y)
	var paint := _v_paint[k]
	_put(Part.BODY, k, facing * Basis.from_scale(size), base + up * (0.22 + size.y * 0.5), paint)
	if bus:
		# A dark band of windows all round.
		_put(Part.CABIN, k, facing * Basis.from_scale(Vector3(size.x + 0.04, 0.85, size.z - 0.5)),
			base + up * (0.22 + size.y * 0.66), Color.WHITE)
	else:
		_put(Part.CABIN, k, facing * Basis.from_scale(Vector3(1.6, 0.68, 2.2)),
			base + up * (0.22 + size.y + 0.32) + back * 0.35, Color.WHITE)
	if _lights:
		var lamp := facing * Basis.from_scale(Vector3(size.x * 0.8, 0.2, 0.08))
		var lamp_up := up * (0.22 + 0.45)
		_put(Part.LAMP, k * 2, lamp, base + lamp_up - back * (size.z * 0.5 + 0.02), HEADLIGHT)
		_put(Part.LAMP, k * 2 + 1, lamp, base + lamp_up + back * (size.z * 0.5 + 0.02), TAIL_LIGHT)
		# Pool of light: a 6 x 20 m square ahead, on the road, brightest at the car
		# end (its +z edge) and fading out 10 m ahead.
		_put(Part.BEAM, k, facing * Basis.from_scale(Vector3(6.0, 1.0, 20.0)),
			base + up * 0.12 - back * (size.z * 0.5 + 10.0), BEAM)


# ------------------------------------------------------------------ people

func _crowd_size() -> bool:
	var n := _p_tile.size()
	if not _people_shown or _walk_target == 0:
		if n > 0:
			_resize_people(0)
			return true
		return false
	if n > _walk_target:
		for _k: int in mini(n - _walk_target, 4):
			_resize_people(_p_tile.size() - 1)
		return true
	if n < _walk_target:
		for _k: int in mini(_walk_target - n, ADD_PER_FRAME):
			_add_person()
		return true
	return false


func _add_person() -> void:
	var n := _p_tile.size()
	_resize_people(n + 1)
	_p_speed[n] = _rng.randf_range(WALK_SPEED.x, WALK_SPEED.y)
	_p_scale[n] = _rng.randf_range(0.88, 1.06)
	_p_clothes[n] = CLOTHES[_rng.randi_range(0, CLOTHES.size() - 1)]
	_p_skin[n] = SKIN[_rng.randi_range(0, SKIN.size() - 1)]
	_respawn_person(n)
	_draw_person(n)


func _respawn_person(n: int) -> void:
	var tile: int
	if not _walk_tiles.is_empty():
		tile = _pick(_walk_tiles, _walk_cum)
	elif not _roads.is_empty():
		tile = _roads[_rng.randi_range(0, _roads.size() - 1)]
	else:
		tile = _p_tile[n]
		if _links[tile] == 0:
			return
	var entry := _random_link(tile)
	var exit := _choose_exit(tile, entry, false, false)
	# Either pavement, not quite single file.
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	_p_offset[n] = side * (PAVEMENT + _rng.randf_range(-0.5, 0.5))
	_p_tile[n] = tile
	_p_entry[n] = entry
	_p_exit[n] = exit
	_p_len[n] = _path_length(tile, entry, exit, _p_offset[n])
	_p_dist[n] = _rng.randf() * _p_len[n]
	_redraw = true


func _walk(delta: float) -> void:
	# With a crowd, each person moves (twice as far) every other frame, to save time.
	var n := _p_tile.size()
	var half_rate := n > HALF_RATE_PEOPLE and delta > 0.0
	var parity := _frame & 1
	for k: int in n:
		var dt := delta
		if half_rate:
			if (k & 1) != parity:
				continue
			dt = delta * 2.0
		if dt > 0.0:
			_p_dist[k] += _p_speed[k] * dt
			var hops := 0
			while _p_dist[k] >= _p_len[k] and hops < 3:
				hops += 1
				_p_dist[k] -= _p_len[k]
				var tile := _p_tile[k]
				var exit: int = _p_exit[k]
				var next := tile + _steps[exit]
				if ((_links[tile] >> exit) & 1) == 0 or _links[next] == 0 \
						or _tile_distance(next) > minf(_radius, WALK_AREA) * 1.15:
					_respawn_person(k)
					break
				var entry := exit ^ 1
				var out := _choose_exit(next, entry, false, false)
				_p_tile[k] = next
				_p_entry[k] = entry
				_p_exit[k] = out
				_p_len[k] = _path_length(next, entry, out, _p_offset[k])
		_draw_person(k)


func _draw_person(k: int) -> void:
	_locate(_p_tile[k], _p_entry[k], _p_exit[k], _p_dist[k], _p_offset[k])
	var pos := _out_pos
	var s := _p_scale[k]
	var ground := maxf(world.height_at(pos.x, pos.y), 0.0) + ROAD_LIFT + 0.02
	var bob := absf(sin(_p_dist[k] * 4.2)) * 0.05     # a little bounce in each step
	var body := Basis.from_scale(Vector3(1.0, s, 1.0))
	_put(Part.WALKER, k, body, Vector3(pos.x, ground + 0.725 * s + bob, pos.y), _p_clothes[k])
	_put(Part.HEAD, k, Basis.IDENTITY, Vector3(pos.x, ground + 1.45 * s + 0.11 + bob, pos.y), _p_skin[k])


# ----------------------------------------------------------------- drawing

func _put(part: int, slot: int, b: Basis, origin: Vector3, colour: Color) -> void:
	# One instance into the shared buffer: a 3 x 4 transform (row by row), then its colour.
	var o := (_part_start[part] + slot) * STRIDE
	_buf[o] = b.x.x
	_buf[o + 1] = b.y.x
	_buf[o + 2] = b.z.x
	_buf[o + 3] = origin.x
	_buf[o + 4] = b.x.y
	_buf[o + 5] = b.y.y
	_buf[o + 6] = b.z.y
	_buf[o + 7] = origin.y
	_buf[o + 8] = b.x.z
	_buf[o + 9] = b.y.z
	_buf[o + 10] = b.z.z
	_buf[o + 11] = origin.z
	_buf[o + 12] = colour.r
	_buf[o + 13] = colour.g
	_buf[o + 14] = colour.b
	_buf[o + 15] = colour.a


func _upload() -> void:
	var cars := _v_tile.size()
	var people := _p_tile.size()
	var counts: Array[int] = [cars, cars, cars * 2 if _lights else 0, cars if _lights else 0, people, people]
	for p: int in _parts.size():
		var mm := _parts[p].multimesh
		if counts[p] > 0:
			var start := _part_start[p] * STRIDE
			mm.buffer = _buf.slice(start, start + _part_cap[p] * STRIDE)
		mm.visible_instance_count = counts[p]
