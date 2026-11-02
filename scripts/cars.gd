extends Node3D
## Traffic: cars driving along the roads, on the left as in the UK.
## Purely for show; they don't affect the simulation.
## Each car crosses one road tile at a time: in from one edge, out of another,
## following the same straight runs and bends the roads are drawn with.

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE, PARK,
	POLICE, FIRE, SCHOOL, HOSPITAL }   # same order as simulation.gd

const LANE_OFFSET := 2.4        # metres left of the road's centre line
const SPEED_MIN := 11.0         # metres per second (about 25 to 35 mph)
const SPEED_MAX := 16.0
const PAINT := [
	Color(0.92, 0.92, 0.92), Color(0.74, 0.75, 0.77), Color(0.08, 0.08, 0.09),
	Color(0.55, 0.07, 0.07), Color(0.10, 0.20, 0.45), Color(0.33, 0.35, 0.38),
	Color(0.86, 0.85, 0.80), Color(0.18, 0.28, 0.24), Color(0.62, 0.62, 0.66),
]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var world                       # the 3D world (for heights and tile positions)
var sim                         # the simulation (for which tiles are roads)
var bodies := MultiMeshInstance3D.new()
var cabins := MultiMeshInstance3D.new()
var lamps := MultiMeshInstance3D.new()
var lights_on := false

# One entry per car: [tile, entry side, exit side, progress 0-1, colour, speed]
var cars: Array = []
var _road_tiles: Array[Vector2i] = []
var _rng := RandomNumberGenerator.new()


func setup(world_view, simulation) -> void:
	world = world_view
	sim = simulation
	_rng.randomize()

	var body_mat := StandardMaterial3D.new()
	body_mat.vertex_color_use_as_albedo = true
	body_mat.vertex_color_is_srgb = true
	body_mat.metallic = 0.5
	body_mat.roughness = 0.35
	bodies.multimesh = _multimesh(BoxMesh.new())
	bodies.material_override = body_mat
	add_child(bodies)

	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.06, 0.08, 0.1)
	glass.metallic = 0.6
	glass.roughness = 0.1
	cabins.multimesh = _multimesh(BoxMesh.new())
	cabins.material_override = glass
	cabins.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cabins)

	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.vertex_color_use_as_albedo = true
	lamps.multimesh = _multimesh(BoxMesh.new())
	lamps.material_override = lamp_mat
	lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lamps)


func _multimesh(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	return mm


# ------------------------------------------------------------------ the fleet

func roads_changed() -> void:
	# Call after roads are built or bulldozed.
	_road_tiles.clear()
	var tiles: PackedByteArray = sim.tiles
	for i in tiles.size():
		if tiles[i] == Tile.ROAD:
			_road_tiles.append(Vector2i(i % world.map_w, i / world.map_w))
	for car in cars:
		if not _is_road(car[0]):
			_respawn(car)


func set_count(target: int) -> void:
	if _road_tiles.is_empty():
		target = 0
	target = mini(target, _road_tiles.size() * 2)
	while cars.size() < target:
		var car := [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, 0.0, Color.WHITE, 0.0]
		_respawn(car)
		cars.append(car)
	while cars.size() > target:
		cars.pop_back()
	bodies.multimesh.instance_count = cars.size()
	cabins.multimesh.instance_count = cars.size()
	lamps.multimesh.instance_count = cars.size() * 2
	for n in cars.size():
		bodies.multimesh.set_instance_color(n, cars[n][4])
		lamps.multimesh.set_instance_color(n * 2, Color(1.0, 0.95, 0.8))
		lamps.multimesh.set_instance_color(n * 2 + 1, Color(0.9, 0.08, 0.05))


func _respawn(car: Array) -> void:
	if _road_tiles.is_empty():
		return
	var tile: Vector2i = _road_tiles[_rng.randi_range(0, _road_tiles.size() - 1)]
	var links := _links(tile)
	var entry: Vector2i = links[_rng.randi_range(0, links.size() - 1)] if not links.is_empty() else Vector2i(-1, 0)
	car[0] = tile
	car[1] = entry
	car[2] = _choose_exit(tile, entry)
	car[3] = _rng.randf()
	car[4] = PAINT[_rng.randi_range(0, PAINT.size() - 1)]
	car[5] = _rng.randf_range(SPEED_MIN, SPEED_MAX)


func _is_road(t: Vector2i) -> bool:
	if t.x < 0 or t.y < 0 or t.x >= world.map_w or t.y >= world.map_h:
		return false
	return sim.tiles[t.y * world.map_w + t.x] == Tile.ROAD


func _links(t: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in DIRS:
		if _is_road(t + d):
			out.append(d)
	return out


func _choose_exit(tile: Vector2i, entry: Vector2i) -> Vector2i:
	# Any road out except straight back; a dead end means turning round.
	var options: Array[Vector2i] = []
	for d in _links(tile):
		if d != entry:
			options.append(d)
	if options.is_empty():
		return entry
	return options[_rng.randi_range(0, options.size() - 1)]


# ------------------------------------------------------------------- driving

func update(delta: float) -> void:
	if cars.is_empty():
		return
	lamps.visible = lights_on
	for n in cars.size():
		var car: Array = cars[n]
		if delta > 0.0:
			car[3] += car[5] * delta / _path_length(car[1], car[2])
			var hops := 0
			while car[3] >= 1.0 and hops < 4:
				hops += 1
				car[3] -= 1.0
				var next: Vector2i = car[0] + car[2]
				if not _is_road(next):
					_respawn(car)
					break
				car[1] = -car[2]
				car[0] = next
				car[2] = _choose_exit(next, car[1])
		_place(n, car)


func _path_length(entry: Vector2i, exit: Vector2i) -> float:
	var half: float = world.cell * 0.5
	if exit == -entry or exit == entry:
		return half * 2.0
	return half * PI * 0.5


func _place(n: int, car: Array) -> void:
	var tile: Vector2i = car[0]
	var entry: Vector2i = car[1]
	var exit: Vector2i = car[2]
	var t: float = car[3]
	var half: float = world.cell * 0.5
	var c: Vector2 = world.tile_centre(tile)
	var p0 := c + Vector2(entry) * half
	var p1 := c + Vector2(exit) * half
	var pos: Vector2
	var dir: Vector2
	if exit == -entry:
		pos = p0.lerp(p1, t)
		dir = (p1 - p0).normalized()
	elif exit == entry:
		# Dead end: drive to the middle and come back.
		if t < 0.5:
			pos = p0.lerp(c, t * 2.0)
			dir = (c - p0).normalized()
		else:
			pos = c.lerp(p0, (t - 0.5) * 2.0)
			dir = (p0 - c).normalized()
	else:
		# Round the bend, the same quarter circle the road is drawn with.
		var corner := c + Vector2(entry + exit) * half
		var a0 := (p0 - corner).angle()
		var turn := wrapf((p1 - corner).angle() - a0, -PI, PI)
		var ang := a0 + turn * t
		pos = corner + Vector2.from_angle(ang) * half
		dir = Vector2.from_angle(ang + signf(turn) * PI * 0.5)
	# Keep left.
	pos += Vector2(dir.y, -dir.x) * LANE_OFFSET

	var ground: float = maxf(world.height_at(pos.x, pos.y), 0.0) + 0.35
	var facing := Basis.looking_at(Vector3(dir.x, 0.0, dir.y), Vector3.UP)
	var base := Vector3(pos.x, ground, pos.y)
	bodies.multimesh.set_instance_transform(n,
		Transform3D(facing * Basis.from_scale(Vector3(1.85, 1.1, 4.3)), base + Vector3.UP * 0.75))
	cabins.multimesh.set_instance_transform(n,
		Transform3D(facing * Basis.from_scale(Vector3(1.65, 0.7, 2.3)), base + Vector3.UP * 1.6 + facing.z * 0.35))
	# Headlights at the front (-z), tail lights at the back (+z).
	lamps.multimesh.set_instance_transform(n * 2,
		Transform3D(facing * Basis.from_scale(Vector3(1.6, 0.25, 0.1)), base + Vector3.UP * 0.9 - facing.z * 2.17))
	lamps.multimesh.set_instance_transform(n * 2 + 1,
		Transform3D(facing * Basis.from_scale(Vector3(1.6, 0.25, 0.1)), base + Vector3.UP * 0.95 + facing.z * 2.17))
