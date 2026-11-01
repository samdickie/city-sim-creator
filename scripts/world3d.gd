extends Node3D
## Draws Troon in 3D: terrain from the real heights, the sea, sky and sunlight,
## and the city on top (roads, power lines, buildings).
## It only reads the simulation; it never changes the city.

const Settings = preload("res://scripts/settings.gd")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const SEA_SHADER = preload("res://shaders/sea.gdshader")
const BUILDING_SHADER = preload("res://shaders/building.gdshader")
const ROOF_SHADER = preload("res://shaders/roof.gdshader")
const ROAD_SHADER = preload("res://shaders/road.gdshader")

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE }   # same order as simulation.gd

const PADDING := 40            # tiles of scenery drawn beyond each map edge
const ROAD_HALF_WIDTH := 6.0   # metres (tarmac plus pavements)
const SEA_FLOOR := -4.0        # how far the ground dips under the sea
const KERB_HALF_WIDTH := 0.85  # pavement width at junctions, halved
const ROAD_NORMAL := Vector2(0.0, 1.0)   # road texture: pavement, tarmac, pavement
const ROAD_PLAIN := Vector2(0.5, 0.5)    # tarmac only
const ROAD_KERB := Vector2(0.0, 0.0)     # pavement only

# Optional photo textures. Drop files here and they're used automatically.
const TEXTURE_DIR := "res://assets/textures/"

const ZONE_TINTS := {
	Tile.HOMES: Color(0.86, 0.36, 0.30),
	Tile.SHOPS: Color(0.26, 0.58, 0.92),
	Tile.INDUSTRY: Color(0.96, 0.70, 0.15),
}

# Troon's building materials.
const RED_SANDSTONE := Color(0.60, 0.34, 0.27)
const BLONDE_SANDSTONE := Color(0.80, 0.69, 0.52)
const WHITE_RENDER := Color(0.90, 0.89, 0.85)
const CREAM_RENDER := Color(0.86, 0.80, 0.67)
const GREY_RENDER := Color(0.66, 0.66, 0.64)
const SLATE := Color(0.25, 0.27, 0.31)
const ROOF_TILE := Color(0.52, 0.26, 0.19)
const SHED_METAL := Color(0.55, 0.58, 0.62)
const SHED_GREEN := Color(0.36, 0.45, 0.40)
const CONCRETE := Color(0.64, 0.64, 0.62)

# Building styles understood by building.gdshader.
const STYLE_HOUSE := 0
const STYLE_SHOP := 1
const STYLE_INDUSTRY := 2
const STYLE_FLATS := 3
const STYLE_PLANT := 4

var sim                         # the Simulation (read only)
var map_w := 0
var map_h := 0
var cell := 50.0
var heights := PackedFloat32Array()   # ground height at each tile centre (sea lowered)
var water := PackedByteArray()

var terrain_material: ShaderMaterial
var zone_image: Image
var zone_texture: ImageTexture
var warn_image: Image
var warn_texture: ImageTexture

var road_instance := MeshInstance3D.new()
# Road mesh being built (kept as members so appending doesn't copy them).
var _rv := PackedVector3Array()
var _rn := PackedVector3Array()
var _ruv := PackedVector2Array()
var _ruv2 := PackedVector2Array()
var _ri := PackedInt32Array()
var road_material: ShaderMaterial
var walls := MultiMeshInstance3D.new()
var roofs := MultiMeshInstance3D.new()
var chimneys := MultiMeshInstance3D.new()
var pylons := MultiMeshInstance3D.new()
var cables := MultiMeshInstance3D.new()
var hover_box := MeshInstance3D.new()
var hover_material := StandardMaterial3D.new()
var alerts := Node3D.new()            # floating warning icons above plots
var _alert_items: Array = []          # [sprite, ground height] for resizing
var _alert_size := 30.0
var _power_icon: Texture2D
var _road_icon: Texture2D

const POWER_ICON_SVG := "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='96'><circle cx='48' cy='48' r='42' fill='#ffd21f' stroke='#16181c' stroke-width='7'/><path d='M54 14 L26 54 H45 L39 84 L70 40 H51 Z' fill='#16181c'/></svg>"
const ROAD_ICON_SVG := "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='96'><circle cx='48' cy='48' r='42' fill='#e5484d' stroke='#16181c' stroke-width='7'/><rect x='22' y='41' width='52' height='14' rx='3' fill='white'/></svg>"
var sun := DirectionalLight3D.new()


# ------------------------------------------------------------------- setup

func setup(simulation, width: int, height: int, cell_metres: float,
		ground: PackedFloat32Array, sea: PackedByteArray) -> void:
	sim = simulation
	map_w = width
	map_h = height
	cell = cell_metres
	water = sea
	heights = ground.duplicate()
	for i in heights.size():
		if water[i] == 1:
			heights[i] = minf(heights[i], SEA_FLOOR)

	_build_environment()
	_build_terrain()
	_build_sea()
	_build_city_nodes()
	refresh_all()


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var hdri_path := "res://assets/hdri/sky.hdr"
	if ResourceLoader.exists(hdri_path):
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(hdri_path)
		sky.sky_material = pano
	else:
		var physical := PhysicalSkyMaterial.new()
		physical.turbidity = 8.0
		physical.ground_color = Color(0.3, 0.33, 0.3)
		sky.sky_material = physical
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 3.0
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.86)
	env.fog_density = 0.00008
	env.fog_aerial_perspective = 0.7
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Late-afternoon sun from the south-west, over the Firth of Clyde.
	sun.rotation_degrees = Vector3(-38.0, 215.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 1800.0
	add_child(sun)


func _build_terrain() -> void:
	var gw := map_w + PADDING * 2
	var gh := map_h + PADDING * 2
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.resize(gw * gh)
	normals.resize(gw * gh)
	for gz in gh:
		for gx in gw:
			var tx := gx - PADDING
			var tz := gz - PADDING
			var h := _tile_height(tx, tz)
			verts[gz * gw + gx] = Vector3((tx + 0.5) * cell, h, (tz + 0.5) * cell)
			var dx := _tile_height(tx - 1, tz) - _tile_height(tx + 1, tz)
			var dz := _tile_height(tx, tz - 1) - _tile_height(tx, tz + 1)
			normals[gz * gw + gx] = Vector3(dx, 2.0 * cell, dz).normalized()
	for gz in gh - 1:
		for gx in gw - 1:
			var a := gz * gw + gx
			var b := a + 1
			var c := a + gw
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	zone_image = Image.create_empty(map_w, map_h, false, Image.FORMAT_RGBA8)
	zone_texture = ImageTexture.create_from_image(zone_image)
	warn_image = Image.create_empty(map_w, map_h, false, Image.FORMAT_RGBA8)
	warn_texture = ImageTexture.create_from_image(warn_image)

	terrain_material = ShaderMaterial.new()
	terrain_material.shader = TERRAIN_SHADER
	terrain_material.set_shader_parameter("map_size", Vector2(map_w, map_h) * cell)
	terrain_material.set_shader_parameter("zone_map", zone_texture)
	terrain_material.set_shader_parameter("warn_map", warn_texture)
	var grass := _optional_texture("grass")
	var sand := _optional_texture("sand")
	var rock := _optional_texture("rock")
	if grass and sand and rock:
		terrain_material.set_shader_parameter("use_textures", true)
		terrain_material.set_shader_parameter("grass_tex", grass)
		terrain_material.set_shader_parameter("sand_tex", sand)
		terrain_material.set_shader_parameter("rock_tex", rock)

	var terrain := MeshInstance3D.new()
	terrain.mesh = mesh
	terrain.material_override = terrain_material
	add_child(terrain)


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	var extent := Vector2(map_w, map_h) * cell
	plane.size = extent + Vector2(PADDING * cell * 2.0, PADDING * cell * 2.0) + Vector2(40000, 40000)
	var mat := ShaderMaterial.new()
	mat.shader = SEA_SHADER
	plane.material = mat
	var sea := MeshInstance3D.new()
	sea.mesh = plane
	sea.position = Vector3(extent.x / 2.0, 0.0, extent.y / 2.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)


func _build_city_nodes() -> void:
	road_material = ShaderMaterial.new()
	road_material.shader = ROAD_SHADER
	var tarmac := _optional_texture("tarmac")
	if tarmac:
		road_material.set_shader_parameter("use_texture", true)
		road_material.set_shader_parameter("tarmac_tex", tarmac)
	road_instance.material_override = road_material
	road_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road_instance)

	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = BUILDING_SHADER
	var stone := _optional_texture("sandstone")
	if stone:
		wall_mat.set_shader_parameter("use_texture", true)
		wall_mat.set_shader_parameter("wall_tex", stone)
	walls.multimesh = _new_multimesh(_unit_box_mesh(), true)
	walls.material_override = wall_mat
	add_child(walls)

	var roof_mat := ShaderMaterial.new()
	roof_mat.shader = ROOF_SHADER
	var slate := _optional_texture("slate")
	if slate:
		roof_mat.set_shader_parameter("use_texture", true)
		roof_mat.set_shader_parameter("roof_tex", slate)
	roofs.multimesh = _new_multimesh(_gable_mesh(), false)
	roofs.material_override = roof_mat
	add_child(roofs)

	var chimney_mesh := CylinderMesh.new()
	chimney_mesh.top_radius = 0.8
	chimney_mesh.bottom_radius = 1.0
	chimney_mesh.height = 1.0
	chimney_mesh.radial_segments = 16
	var chimney_mat := StandardMaterial3D.new()
	chimney_mat.vertex_color_use_as_albedo = true
	chimney_mat.roughness = 0.9
	chimneys.multimesh = _new_multimesh(chimney_mesh, false)
	chimneys.material_override = chimney_mat
	add_child(chimneys)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.5, 0.52, 0.55)
	metal.metallic = 0.7
	metal.roughness = 0.45
	var pylon_mesh := BoxMesh.new()
	pylons.multimesh = _new_multimesh(pylon_mesh, false)
	pylons.material_override = metal
	add_child(pylons)

	var cable_mat := StandardMaterial3D.new()
	cable_mat.albedo_color = Color(0.1, 0.1, 0.1)
	cables.multimesh = _new_multimesh(BoxMesh.new(), false)
	cables.material_override = cable_mat
	cables.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cables)

	var hover_mesh := BoxMesh.new()
	hover_mesh.size = Vector3(cell, 4.0, cell)
	hover_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hover_material.albedo_color = Color(1, 1, 1, 0.25)
	hover_box.mesh = hover_mesh
	hover_box.material_override = hover_material
	hover_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hover_box.visible = false
	add_child(hover_box)

	_power_icon = _svg_texture(POWER_ICON_SVG)
	_road_icon = _svg_texture(ROAD_ICON_SVG)
	add_child(alerts)


func _svg_texture(svg: String) -> Texture2D:
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _new_multimesh(mesh: Mesh, custom_data: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom_data
	mm.mesh = mesh
	return mm


func _optional_texture(tex_name: String) -> Texture2D:
	for ext in ["jpg", "png", "webp"]:
		var path := "%s%s.%s" % [TEXTURE_DIR, tex_name, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


# ------------------------------------------------------------------ refresh

func _process(_delta: float) -> void:
	if terrain_material:
		terrain_material.set_shader_parameter("time_now", Time.get_ticks_msec() / 1000.0)


func refresh_all() -> void:
	refresh_ground()
	refresh_buildings()


func refresh_ground() -> void:
	# Zone colours and warnings on the ground, roads and power lines.
	var tiles: PackedByteArray = sim.tiles
	var levels: PackedByteArray = sim.levels
	var reach: PackedByteArray = sim.road_reach_map()
	var power: PackedByteArray = sim.power_map()
	for y in map_h:
		for x in map_w:
			var i := y * map_w + x
			var t := tiles[i]
			var tint := Color(0, 0, 0, 0)
			var warn := Color(0, 0, 0, 0)
			if ZONE_TINTS.has(t):
				var c: Color = ZONE_TINTS[t]
				tint = Color(c, 0.5 if levels[i] == 0 else 0.22)
				if reach[i] > Settings.ROAD_REACH:
					warn.r = 1.0
				elif power[i] == 0:
					warn.g = 1.0   # (shown as a floating icon, see _build_alerts)
			elif t == Tile.POWER_PLANT:
				tint = Color(0.55, 0.55, 0.55, 0.6)
			zone_image.set_pixel(x, y, tint)
			warn_image.set_pixel(x, y, warn)
	zone_texture.update(zone_image)
	warn_texture.update(warn_image)
	_build_roads(tiles)
	_build_power_lines(tiles)
	_build_alerts()


func _build_alerts() -> void:
	# A floating icon over every plot that can't grow: no road (red), no power (yellow).
	for child in alerts.get_children():
		child.queue_free()
	_alert_items.clear()
	for y in map_h:
		for x in map_w:
			var warn := warn_image.get_pixel(x, y)
			if warn.r < 0.5 and warn.g < 0.5:
				continue
			var sprite := Sprite3D.new()
			sprite.texture = _road_icon if warn.r >= 0.5 else _power_icon
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.no_depth_test = true
			sprite.render_priority = 10
			sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var ground := ground_point(Vector2i(x, y))
			alerts.add_child(sprite)
			_alert_items.append([sprite, ground])
	_place_alerts()


func set_view_distance(distance: float) -> void:
	# Keep the warning icons a readable size however far the camera is.
	var size := clampf(distance * 0.022, 12.0, 120.0)
	if absf(size - _alert_size) > _alert_size * 0.05:
		_alert_size = size
		_place_alerts()


func _place_alerts() -> void:
	for item in _alert_items:
		var sprite: Sprite3D = item[0]
		var ground: Vector3 = item[1]
		sprite.pixel_size = _alert_size / 96.0
		sprite.position = ground + Vector3.UP * (12.0 + _alert_size * 0.6)


func blink(on: bool) -> void:
	alerts.visible = on


func refresh_buildings() -> void:
	var tiles: PackedByteArray = sim.tiles
	var levels: PackedByteArray = sim.levels
	var wall_list: Array = []
	var roof_list: Array = []
	var chimney_list: Array = []
	for i in tiles.size():
		var t := tiles[i]
		var lv := levels[i]
		if t == Tile.POWER_PLANT:
			_plan_plant(i, wall_list, chimney_list)
		elif ZONE_TINTS.has(t) and lv > 0:
			_plan_zone(i, t, lv, wall_list, roof_list, chimney_list)
	_fill(walls.multimesh, wall_list, true)
	_fill(roofs.multimesh, roof_list, false)
	_fill(chimneys.multimesh, chimney_list, false)


func _fill(mm: MultiMesh, items: Array, custom: bool) -> void:
	mm.instance_count = items.size()
	for n in items.size():
		var item: Array = items[n]
		mm.set_instance_transform(n, item[0])
		mm.set_instance_color(n, item[1])
		if custom:
			mm.set_instance_custom_data(n, item[2])


# ------------------------------------------------------------------- hover

func set_hover(tile: Vector2i, ok: bool) -> void:
	if tile.x < 0 or tile.y < 0 or tile.x >= map_w or tile.y >= map_h:
		hover_box.visible = false
		return
	hover_box.visible = true
	var centre := tile_centre(tile)
	hover_box.position = Vector3(centre.x, maxf(height_at(centre.x, centre.y), 0.0) + 2.0, centre.y)
	hover_material.albedo_color = Color(1, 1, 1, 0.22) if ok else Color(1, 0.25, 0.2, 0.3)


func pick_tile(origin: Vector3, direction: Vector3) -> Vector2i:
	# Walk along the mouse ray until it goes below the ground (or the sea).
	var step := 8.0
	var p := origin
	var prev := origin
	for n in 4000:
		p = origin + direction * (step * n)
		var ground := maxf(height_at(p.x, p.z), 0.0)
		if p.y <= ground:
			# Refine between the last point above ground and this one.
			var lo := prev
			var hi := p
			for k in 12:
				var mid := (lo + hi) * 0.5
				if mid.y <= maxf(height_at(mid.x, mid.z), 0.0):
					hi = mid
				else:
					lo = mid
			return Vector2i(floori(hi.x / cell), floori(hi.z / cell))
		prev = p
		if p.y < -50.0:
			break
	return Vector2i(-1, -1)


func ground_point(tile: Vector2i) -> Vector3:
	var c := tile_centre(tile)
	return Vector3(c.x, maxf(height_at(c.x, c.y), 0.0), c.y)


# ------------------------------------------------------------------- height

func _tile_height(tx: int, tz: int) -> float:
	# Height of a tile centre; outside the map, the nearest edge tile.
	var x := clampi(tx, 0, map_w - 1)
	var z := clampi(tz, 0, map_h - 1)
	return heights[z * map_w + x]


func height_at(wx: float, wz: float) -> float:
	# Smooth ground height at any point, matching the terrain mesh.
	var gx := wx / cell - 0.5
	var gz := wz / cell - 0.5
	var x0 := floori(gx)
	var z0 := floori(gz)
	var fx := gx - x0
	var fz := gz - z0
	var h00 := _tile_height(x0, z0)
	var h10 := _tile_height(x0 + 1, z0)
	var h01 := _tile_height(x0, z0 + 1)
	var h11 := _tile_height(x0 + 1, z0 + 1)
	# Same diagonal split as the mesh triangles, so things sit exactly on it.
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


func tile_centre(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * cell, (tile.y + 0.5) * cell)


# -------------------------------------------------------------------- roads

func _build_roads(tiles: PackedByteArray) -> void:
	# Roads are drawn as joined-up streets: straight runs pass right through a tile,
	# corners become smooth bends, and junctions are open tarmac with pavements
	# only on the sides with no road. Each piece starts and ends at the middle of a
	# tile edge, so neighbouring tiles line up exactly.
	_rv.clear()
	_rn.clear()
	_ruv.clear()
	_ruv2.clear()
	_ri.clear()
	var half := cell * 0.5
	var hw := ROAD_HALF_WIDTH
	for y in map_h:
		for x in map_w:
			if tiles[y * map_w + x] != Tile.ROAD:
				continue
			var c := tile_centre(Vector2i(x, y))
			var links: Array[Vector2] = []
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < map_w and n.y < map_h \
						and tiles[n.y * map_w + n.x] == Tile.ROAD:
					links.append(Vector2(d))

			if links.is_empty():
				# A lone tile: a short stretch of road.
				_road_path(_line_points(c - Vector2(half * 0.6, 0), c + Vector2(half * 0.6, 0)),
					hw, ROAD_NORMAL, 1.0)
			elif links.size() == 1:
				# Dead end: from the tile edge to just past the middle.
				var d := links[0]
				_road_path(_line_points(c + d * half, c - d * hw), hw, ROAD_NORMAL, 1.0)
			elif links.size() == 2 and links[0] + links[1] == Vector2.ZERO:
				# Straight through.
				_road_path(_line_points(c + links[0] * half, c + links[1] * half), hw, ROAD_NORMAL, 1.0)
			elif links.size() == 2:
				# A corner: a quarter-circle bend between the two edges.
				_road_path(_bend_points(c, links[0], links[1]), hw, ROAD_NORMAL, 1.0)
			else:
				# Junction: an open square of tarmac, an arm to each road, and
				# pavement along any side without a road.
				_road_path(_line_points(c - Vector2(hw, 0), c + Vector2(hw, 0)), hw, ROAD_PLAIN, 0.0)
				for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					if d in links:
						_road_path(_line_points(c + d * half, c + d * hw), hw, ROAD_NORMAL, 1.0)
					else:
						var edge := c + d * (hw - KERB_HALF_WIDTH)
						var along := Vector2(-d.y, d.x) * hw
						_road_path(_line_points(edge - along, edge + along), KERB_HALF_WIDTH,
							ROAD_KERB, 0.0, 0.08)   # raised kerb, sits on the tarmac

	if _rv.is_empty():
		road_instance.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _rv
	arrays[Mesh.ARRAY_NORMAL] = _rn
	arrays[Mesh.ARRAY_TEX_UV] = _ruv
	arrays[Mesh.ARRAY_TEX_UV2] = _ruv2
	arrays[Mesh.ARRAY_INDEX] = _ri
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	road_instance.mesh = mesh


func _line_points(from: Vector2, to: Vector2) -> PackedVector2Array:
	# Points every few metres along a straight line, so the road follows the ground.
	var pts := PackedVector2Array()
	var steps := maxi(1, ceili(from.distance_to(to) / 4.0))
	for k in steps + 1:
		pts.append(from.lerp(to, float(k) / steps))
	return pts


func _bend_points(c: Vector2, a: Vector2, b: Vector2) -> PackedVector2Array:
	# A quarter circle from the middle of edge a to the middle of edge b,
	# curving around the tile corner between them.
	var half := cell * 0.5
	var corner := c + (a + b) * half
	var from := c + a * half - corner
	var to := c + b * half - corner
	var a0 := from.angle()
	var turn := wrapf(to.angle() - a0, -PI, PI)
	var pts := PackedVector2Array()
	const STEPS := 14
	for k in STEPS + 1:
		pts.append(corner + Vector2.from_angle(a0 + turn * float(k) / STEPS) * half)
	return pts


func _road_path(points: PackedVector2Array, half_width: float, across: Vector2,
		centre_line: float, lift: float = 0.0) -> void:
	# A ribbon of road along the points. "across" is the texture position at the
	# left and right edges: (0, 1) = full road with pavements, (0.5, 0.5) = plain
	# tarmac, (0, 0) = pavement only.
	var count := points.size()
	var start := _rv.size()
	var dist := 0.0
	for k in count:
		var dir: Vector2
		if k == 0:
			dir = points[1] - points[0]
		elif k == count - 1:
			dir = points[k] - points[k - 1]
		else:
			dir = points[k + 1] - points[k - 1]
		dir = dir.normalized()
		if k > 0:
			dist += points[k].distance_to(points[k - 1])
		var side := Vector2(-dir.y, dir.x) * half_width
		for s in [-1.0, 1.0]:
			var q: Vector2 = points[k] + side * s
			_rv.append(Vector3(q.x, maxf(height_at(q.x, q.y), 0.0) + 0.35 + lift, q.y))
			_rn.append(Vector3.UP)
			_ruv.append(Vector2(across.x if s < 0.0 else across.y, dist))
			_ruv2.append(Vector2(centre_line, 0.0))
	for k in count - 1:
		var a := start + k * 2
		_ri.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])   # clockwise from above


# -------------------------------------------------------------- power lines

func _build_power_lines(tiles: PackedByteArray) -> void:
	var pylon_list: Array = []
	var cable_list: Array = []
	const PYLON_HEIGHT := 24.0
	for y in map_h:
		for x in map_w:
			if tiles[y * map_w + x] != Tile.POWER_LINE:
				continue
			var base := ground_point(Vector2i(x, y))
			pylon_list.append([Transform3D(Basis.from_scale(Vector3(1.6, PYLON_HEIGHT, 1.6)),
				base + Vector3(0, PYLON_HEIGHT / 2.0, 0)), Color.WHITE])
			pylon_list.append([Transform3D(Basis.from_scale(Vector3(9.0, 0.6, 0.6)),
				base + Vector3(0, PYLON_HEIGHT - 2.0, 0)), Color.WHITE])
			# Cables to the next pylon or plant to the east and south.
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= map_w or n.y >= map_h:
					continue
				var nt := tiles[n.y * map_w + n.x]
				if nt != Tile.POWER_LINE and nt != Tile.POWER_PLANT:
					continue
				var a := base + Vector3(0, PYLON_HEIGHT - 2.0, 0)
				var b := ground_point(n) + Vector3(0, PYLON_HEIGHT - 2.0, 0)
				var mid := (a + b) * 0.5
				var span := b - a
				var b3 := Basis.looking_at(span.normalized(), Vector3.UP)
				b3 = b3 * Basis.from_scale(Vector3(0.25, 0.25, span.length()))
				cable_list.append([Transform3D(b3, mid), Color.WHITE])
			# Also link west/north into a plant, so plants join the line from any side.
			for d: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x < 0 or n.y < 0 or tiles[n.y * map_w + n.x] != Tile.POWER_PLANT:
					continue
				var a := base + Vector3(0, PYLON_HEIGHT - 2.0, 0)
				var b := ground_point(n) + Vector3(0, PYLON_HEIGHT - 2.0, 0)
				var span := b - a
				var b3 := Basis.looking_at(span.normalized(), Vector3.UP)
				b3 = b3 * Basis.from_scale(Vector3(0.25, 0.25, span.length()))
				cable_list.append([Transform3D(b3, (a + b) * 0.5), Color.WHITE])
	_fill(pylons.multimesh, pylon_list, false)
	_fill(cables.multimesh, cable_list, false)


# ---------------------------------------------------------------- buildings

func _frontage(i: int) -> Vector2i:
	# Which side of the plot faces a road (buildings face the street).
	var x := i % map_w
	var y := i / map_w
	for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = Vector2i(x, y) + d
		if n.x >= 0 and n.y >= 0 and n.x < map_w and n.y < map_h \
				and sim.tiles[n.y * map_w + n.x] == Tile.ROAD:
			return d
	return Vector2i(0, 1)


func _place(i: int, front: Vector2i, along: float, back: float, w: float, d: float) -> Dictionary:
	# Where a building sits on its plot.
	#   along: metres left/right of the plot centre, along the street
	#   back:  metres back from the street edge to the building's front
	var x := i % map_w
	var y := i / map_w
	var centre := tile_centre(Vector2i(x, y))
	var fwd := Vector2(front)                  # towards the street
	var away := -fwd
	var across := Vector2(away.y, -away.x)
	var front_edge := centre + fwd * (cell * 0.5)
	var mid := front_edge + across * along + away * (back + d * 0.5)
	# Sit on the lowest corner so nothing floats on a slope.
	var base := INF
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var q: Vector2 = mid + across * (w * sx) + away * (d * sz)
			base = minf(base, height_at(q.x, q.y))
	base = maxf(base, 0.3) - 0.3
	var x_axis := Vector3(away.y, 0.0, -away.x)   # along the street
	var z_axis := Vector3(away.x, 0.0, away.y)    # back from the street
	return {"pos": Vector3(mid.x, base, mid.y), "x": x_axis, "z": z_axis}


func _add_block(spot: Dictionary, w: float, d: float, h: float, colour: Color, style: int,
		roof_h: float, roof_colour: Color, wall_list: Array, roof_list: Array) -> void:
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
	var b3 := Basis(x_axis * w, Vector3.UP * h, z_axis * d)
	wall_list.append([Transform3D(b3, pos), colour, Color(w, h, d, style)])
	if roof_h > 0.0:
		# Pitched roof with a small overhang, ridge running along the street.
		var roof_b3 := Basis(x_axis * (w + 0.8), Vector3.UP * roof_h, z_axis * (d + 1.0))
		roof_list.append([Transform3D(roof_b3, pos + Vector3.UP * h), roof_colour])


func _plan_zone(i: int, t: int, lv: int, wall_list: Array, roof_list: Array, chimney_list: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 7919 + lv * 104729 + t
	var front := _frontage(i)
	match t:
		Tile.HOMES:
			_plan_homes(i, lv, front, rng, wall_list, roof_list)
		Tile.SHOPS:
			_plan_shops(i, lv, front, rng, wall_list, roof_list)
		Tile.INDUSTRY:
			_plan_industry(i, lv, front, rng, wall_list, roof_list, chimney_list)


func _house_colour(rng: RandomNumberGenerator) -> Color:
	var choices := [RED_SANDSTONE, BLONDE_SANDSTONE, WHITE_RENDER, WHITE_RENDER,
		CREAM_RENDER, GREY_RENDER, BLONDE_SANDSTONE]
	var c: Color = choices[rng.randi_range(0, choices.size() - 1)]
	return c.darkened(rng.randf_range(-0.05, 0.08))


func _plan_homes(i: int, lv: int, front: Vector2i, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array) -> void:
	if lv >= 3:
		# Sandstone tenements, three or four storeys.
		for along in [-12.5, 12.5]:
			var storeys := rng.randi_range(3, 4)
			var stone := RED_SANDSTONE if rng.randf() < 0.5 else BLONDE_SANDSTONE
			var spot := _place(i, front, along, 5.0, 22.0, 13.0)
			_add_block(spot, 22.0, 13.0, storeys * 3.0 + 0.5, stone, STYLE_FLATS, 4.5, SLATE,
				wall_list, roof_list)
		return
	# Detached and semi-detached villas: a front row, plus a back row at level 2.
	var rows := [8.0] if lv == 1 else [7.0, 28.0]
	for back in rows:
		for along in [-17.0, -5.5, 5.5, 17.0]:
			if rng.randf() < 0.15:
				continue   # the odd garden plot
			var w := rng.randf_range(8.0, 10.0)
			var d := rng.randf_range(7.0, 9.0)
			var h := 5.6 if rng.randf() < 0.8 else 3.2   # mostly two storeys, some bungalows
			var roof := SLATE if rng.randf() < 0.75 else ROOF_TILE
			var spot := _place(i, front, along + rng.randf_range(-0.8, 0.8), back, w, d)
			_add_block(spot, w, d, h, _house_colour(rng), STYLE_HOUSE,
				rng.randf_range(2.8, 3.6), roof, wall_list, roof_list)


func _plan_shops(i: int, lv: int, front: Vector2i, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array) -> void:
	var colours := [WHITE_RENDER, BLONDE_SANDSTONE, CREAM_RENDER, RED_SANDSTONE, GREY_RENDER]
	if lv >= 3:
		for along in [-12.5, 12.5]:
			var spot := _place(i, front, along, 2.0, 23.0, 16.0)
			_add_block(spot, 23.0, 16.0, rng.randi_range(3, 4) * 3.2 + 0.6,
				colours[rng.randi_range(0, colours.size() - 1)], STYLE_SHOP, 0.0, SLATE,
				wall_list, roof_list)
		return
	# A parade of shops along the street; flats above from level 2.
	var height := 4.2 if lv == 1 else 7.0
	for along in [-16.5, 0.0, 16.5]:
		var spot := _place(i, front, along, 2.0, 15.5, 12.0)
		_add_block(spot, 15.5, 12.0, height + rng.randf_range(-0.2, 0.4),
			colours[rng.randi_range(0, colours.size() - 1)], STYLE_SHOP,
			3.0 if lv == 2 else 0.0, SLATE, wall_list, roof_list)


func _plan_industry(i: int, lv: int, front: Vector2i, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array, chimney_list: Array) -> void:
	var cladding := SHED_METAL if rng.randf() < 0.6 else SHED_GREEN
	if lv == 1:
		var spot := _place(i, front, 0.0, 8.0, 30.0, 22.0)
		_add_block(spot, 30.0, 22.0, 8.0, cladding, STYLE_INDUSTRY, 2.2, SHED_METAL.darkened(0.2),
			wall_list, roof_list)
	elif lv == 2:
		var a := _place(i, front, -9.0, 4.0, 28.0, 20.0)
		_add_block(a, 28.0, 20.0, 9.0, cladding, STYLE_INDUSTRY, 2.2, SHED_METAL.darkened(0.2),
			wall_list, roof_list)
		var b := _place(i, front, 13.0, 28.0, 18.0, 16.0)
		_add_block(b, 18.0, 16.0, 7.0, CONCRETE, STYLE_INDUSTRY, 0.0, SLATE, wall_list, roof_list)
	else:
		var spot := _place(i, front, -3.0, 4.0, 40.0, 32.0)
		_add_block(spot, 40.0, 32.0, 13.0, cladding, STYLE_INDUSTRY, 3.0, SHED_METAL.darkened(0.25),
			wall_list, roof_list)
		var stack := _place(i, front, 19.0, 38.0, 4.0, 4.0)
		var pos: Vector3 = stack["pos"]
		chimney_list.append([Transform3D(Basis.from_scale(Vector3(2.0, 34.0, 2.0)),
			pos + Vector3.UP * 17.0), RED_SANDSTONE.darkened(0.3)])


func _plan_plant(i: int, wall_list: Array, chimney_list: Array) -> void:
	var front := _frontage(i)
	var spot := _place(i, front, -6.0, 6.0, 30.0, 26.0)
	_add_block(spot, 30.0, 26.0, 18.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, [])
	for along in [12.0, 19.0]:
		var stack := _place(i, front, along, 30.0, 5.0, 5.0)
		var pos: Vector3 = stack["pos"]
		chimney_list.append([Transform3D(Basis.from_scale(Vector3(3.0, 65.0, 3.0)),
			pos + Vector3.UP * 32.5), Color(0.75, 0.74, 0.72)])


# ----------------------------------------------------------- simple shapes

func _unit_box_mesh() -> ArrayMesh:
	# A 1 x 1 x 1 box standing on the ground (y from 0 to 1), for walls.
	var box := BoxMesh.new()
	var arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for k in verts.size():
		verts[k] += Vector3(0, 0.5, 0)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _gable_mesh() -> ArrayMesh:
	# A pitched roof 1 wide, 1 deep and 1 high, ridge along x, sitting on y = 0.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l0 := Vector3(-0.5, 0, -0.5)
	var l1 := Vector3(-0.5, 0, 0.5)
	var r0 := Vector3(0.5, 0, -0.5)
	var r1 := Vector3(0.5, 0, 0.5)
	var lt := Vector3(-0.5, 1, 0)
	var rt := Vector3(0.5, 1, 0)
	for tri in [[l0, lt, rt], [l0, rt, r0], [l1, r1, rt], [l1, rt, lt], [l0, l1, lt], [r0, rt, r1]]:
		for v in tri:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()
