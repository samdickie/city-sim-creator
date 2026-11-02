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

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE, PARK }   # same order as simulation.gd

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
const PAVEMENT := Color(0.66, 0.65, 0.62)
const DRIVEWAY := Color(0.58, 0.56, 0.53)
const COURT := Color(0.55, 0.54, 0.50)
const CAR_PARK := Color(0.20, 0.20, 0.21)
const BAY_LINE := Color(0.92, 0.92, 0.88)
const YARD := Color(0.50, 0.50, 0.48)
const CONTAINERS := [Color(0.62, 0.16, 0.12), Color(0.12, 0.30, 0.55), Color(0.18, 0.42, 0.26),
	Color(0.85, 0.48, 0.12), Color(0.55, 0.56, 0.58)]
const CAR_PAINT := [Color(0.92, 0.92, 0.92), Color(0.74, 0.75, 0.77), Color(0.08, 0.08, 0.09),
	Color(0.55, 0.07, 0.07), Color(0.10, 0.20, 0.45), Color(0.33, 0.35, 0.38),
	Color(0.86, 0.85, 0.80), Color(0.18, 0.28, 0.24)]

# Building styles understood by building.gdshader.
const STYLE_HOUSE := 0
const STYLE_SHOP := 1
const STYLE_INDUSTRY := 2
const STYLE_FLATS := 3
const STYLE_PLANT := 4
const STYLE_GLASS := 5         # modern glass and steel (on the most valuable land)
const STYLE_CLASSICAL := 6     # sandstone: rusticated base, sash windows, string courses
const STYLE_MODERN := 7        # storey-high glazing in light frames, with clad bays
const STYLE_CLASSICAL_SHOPS := 8   # classical with shopfronts on the ground floor
const HONEY_STONE := Color(0.84, 0.71, 0.50)
const CREAM_STONE := Color(0.88, 0.84, 0.74)
const TRIM := Color(0.93, 0.91, 0.86)          # cornices, canopies, frames
const TIMBER := Color(0.56, 0.38, 0.23)
const BRONZE := Color(0.33, 0.27, 0.21)
const CHARCOAL := Color(0.22, 0.23, 0.25)
const BALCONY_GLASS := Color(0.55, 0.66, 0.72)
const LAWN := Color(0.33, 0.52, 0.24)
const MODERN_WHITE := Color(0.92, 0.92, 0.90)
const MODERN_GREY := Color(0.55, 0.57, 0.60)
const GLASS_FRAME := Color(0.30, 0.33, 0.36)

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
var paving := MultiMeshInstance3D.new()       # driveways, pavements, car parks, yards
var props := MultiMeshInstance3D.new()        # hedges, walls, fences, containers
var parked_bodies := MultiMeshInstance3D.new()
var parked_cabins := MultiMeshInstance3D.new()
var _paving_items: Array = []
var _prop_items: Array = []
var _parked_items: Array = []
var _values := PackedFloat32Array()   # land value per tile, for building quality
var _extra_trees: Array = []          # [position (Vector2), height] planted in courts
# Leftover open land inside the town gets put to use (looks only, not simulated):
var _infill := PackedByteArray()      # 0 = none, 1 = pocket park, 2 = allotments, 3 = car park
const INFILL_PARK := 1
const INFILL_ALLOTMENTS := 2
const INFILL_CAR_PARK := 3
const HOARDING := Color(0.86, 0.87, 0.84)
const FOUNDATION := Color(0.48, 0.47, 0.45)
const SITE_CABIN := Color(0.20, 0.36, 0.62)
const CRANE_YELLOW := Color(0.95, 0.74, 0.10)
const SOIL := Color(0.32, 0.23, 0.16)
const CROPS := Color(0.30, 0.48, 0.20)
var preview := MultiMeshInstance3D.new()   # tiles a drag will build on
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
var env: Environment
var sky_material: Material
var wall_material: ShaderMaterial
var night := 0.0                       # 0 = full day, 1 = full night
var _sky_energy := 1.0

# Trees: natural woods on open land (hidden where you build), plus park and garden trees.
var trunks := MultiMeshInstance3D.new()
var crowns := MultiMeshInstance3D.new()        # broadleaf canopies
var cones := MultiMeshInstance3D.new()         # conifers
var city_trunks := MultiMeshInstance3D.new()
var city_crowns := MultiMeshInstance3D.new()
var _tree_trunk_xf: Array[Transform3D] = []
var _tree_crown_xf: Array[Transform3D] = []
var _tree_conifer := PackedByteArray()
var _tree_crown_idx := PackedInt32Array()
var _trees_in_tile := {}                       # tile index -> Array of tree numbers
var _tile_has_trees := PackedByteArray()       # 1 = that tile's trees are showing
var _hidden := Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)), Vector3(0, -500, 0))


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
	_infill.resize(map_w * map_h)
	_build_city_nodes()
	_build_trees()
	_build_preview()
	refresh_all()


func _build_environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var hdri_path := "res://assets/hdri/sky.hdr"
	if ResourceLoader.exists(hdri_path):
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(hdri_path)
		sky.sky_material = pano
		sky_material = pano
	else:
		var physical := PhysicalSkyMaterial.new()
		physical.turbidity = 8.0
		physical.ground_color = Color(0.3, 0.33, 0.3)
		sky.sky_material = physical
		sky_material = physical
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
	# Colour grading: a touch richer and punchier, like a polished city builder.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
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
	sun.shadow_blur = 1.0
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
		terrain_material.set_shader_parameter("grass_average", _average_colour(grass))
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
	wall_material = wall_mat
	wall_mat.shader = BUILDING_SHADER
	var stone := _optional_texture("sandstone")
	if stone:
		wall_mat.set_shader_parameter("use_texture", true)
		wall_mat.set_shader_parameter("wall_tex", stone)
		wall_mat.set_shader_parameter("wall_average", _average_colour(stone))
	walls.multimesh = _new_multimesh(_unit_box_mesh(), true)
	walls.material_override = wall_mat
	add_child(walls)

	var roof_mat := ShaderMaterial.new()
	roof_mat.shader = ROOF_SHADER
	var slate := _optional_texture("slate")
	if slate:
		roof_mat.set_shader_parameter("use_texture", true)
		roof_mat.set_shader_parameter("roof_tex", slate)
		roof_mat.set_shader_parameter("roof_average", _average_colour(slate))
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

	var flat := StandardMaterial3D.new()
	flat.vertex_color_use_as_albedo = true
	flat.vertex_color_is_srgb = true
	flat.roughness = 0.92
	paving.multimesh = _new_multimesh(_unit_box_mesh(), false)
	paving.material_override = flat
	paving.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paving)
	var solid := StandardMaterial3D.new()
	solid.vertex_color_use_as_albedo = true
	solid.vertex_color_is_srgb = true
	solid.roughness = 0.85
	props.multimesh = _new_multimesh(_unit_box_mesh(), false)
	props.material_override = solid
	add_child(props)
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	paint.metallic = 0.5
	paint.roughness = 0.35
	parked_bodies.multimesh = _new_multimesh(BoxMesh.new(), false)
	parked_bodies.material_override = paint
	add_child(parked_bodies)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.06, 0.08, 0.1)
	glass.metallic = 0.6
	glass.roughness = 0.1
	parked_cabins.multimesh = _new_multimesh(BoxMesh.new(), false)
	parked_cabins.material_override = glass
	parked_cabins.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(parked_cabins)

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


func _average_colour(tex: Texture2D) -> Vector3:
	# The photo's average colour in linear light, so the shaders can use it for detail.
	var img := tex.get_image()
	if img == null:
		return Vector3(0.25, 0.25, 0.25)
	if img.is_compressed() and img.decompress() != OK:
		return Vector3(0.25, 0.25, 0.25)
	var total := Color(0, 0, 0)
	const N := 32
	for gy in N:
		for gx in N:
			total += img.get_pixel(gx * img.get_width() / N, gy * img.get_height() / N).srgb_to_linear()
	total /= float(N * N)
	return Vector3(maxf(total.r, 0.01), maxf(total.g, 0.01), maxf(total.b, 0.01))


func _optional_texture(tex_name: String) -> Texture2D:
	for ext: String in ["jpg", "png", "webp"]:
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
				# Coloured while waiting to be built on; once built, it's lawn and gardens.
				var strength: float = 0.5
				if t != Tile.INDUSTRY:
					strength = [0.28, 0.48, 0.7][sim.density[i]]
				tint = Color(c, strength) if levels[i] == 0 else Color(0, 0, 0, 0)
				if reach[i] > Settings.ROAD_REACH:
					warn.r = 1.0
				elif power[i] == 0:
					warn.g = 1.0   # (shown as a floating icon, see _build_alerts)
			elif t == Tile.POWER_PLANT:
				tint = Color(0.55, 0.55, 0.55, 0.6)
			elif t == Tile.PARK:
				tint = Color(0.40, 0.72, 0.32, 0.45)
			_infill[i] = _infill_kind(x, y) if t == Tile.EMPTY else 0
			if _infill[i] == INFILL_PARK:
				tint = Color(0.40, 0.68, 0.30, 0.35)   # mown grass
			elif _infill[i] == INFILL_ALLOTMENTS:
				tint = Color(0.36, 0.30, 0.20, 0.35)
			zone_image.set_pixel(x, y, tint)
			warn_image.set_pixel(x, y, warn)
	zone_texture.update(zone_image)
	warn_texture.update(warn_image)
	_build_roads(tiles)
	_build_power_lines(tiles)
	_build_alerts()
	_update_natural_trees(tiles)


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
	# Shadows only as far as needed, so they stay crisp when zoomed in.
	sun.directional_shadow_max_distance = clampf(distance * 2.2, 350.0, 3500.0)
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
	_paving_items.clear()
	_prop_items.clear()
	_parked_items.clear()
	_extra_trees.clear()
	_values = sim.land_value_map()
	for i in tiles.size():
		var t := tiles[i]
		var lv := levels[i]
		if t == Tile.POWER_PLANT:
			_plan_plant(i, wall_list, chimney_list)
		elif ZONE_TINTS.has(t) and lv > 0:
			_plan_zone(i, t, sim.stage(i), wall_list, roof_list, chimney_list)
		elif ZONE_TINTS.has(t) and _road_near(i):
			_plan_site(i, t, wall_list)
		elif t == Tile.EMPTY and _infill[i] > 0:
			_plan_infill(i)
	_fill(walls.multimesh, wall_list, true)
	_fill(roofs.multimesh, roof_list, false)
	_fill(chimneys.multimesh, chimney_list, false)
	_fill(paving.multimesh, _paving_items, false)
	_fill(props.multimesh, _prop_items, false)
	var bodies: Array = []
	var cabins: Array = []
	for car in _parked_items:
		bodies.append([car[0], car[1]])
		cabins.append([car[2], Color.WHITE])
	_fill(parked_bodies.multimesh, bodies, false)
	_fill(parked_cabins.multimesh, cabins, false)
	_build_city_trees(tiles, levels)


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
						# Arm into the junction, with a zebra crossing just before it.
						_road_path(_line_points(c + d * half, c + d * hw), hw, ROAD_NORMAL, 1.0, 0.0, 1.0)
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
		centre_line: float, lift: float = 0.0, crossing: float = 0.0) -> void:
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
		for s: float in [-1.0, 1.0]:
			var q: Vector2 = points[k] + side * s
			_rv.append(Vector3(q.x, maxf(height_at(q.x, q.y), 0.0) + 0.35 + lift, q.y))
			_rn.append(Vector3.UP)
			_ruv.append(Vector2(across.x if s < 0.0 else across.y, dist))
			_ruv2.append(Vector2(centre_line, crossing))
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
		if _is_road(Vector2i(x, y) + d):
			return d
	return Vector2i(0, 1)


func _is_road(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < map_w and t.y < map_h \
		and sim.tiles[t.y * map_w + t.x] == Tile.ROAD


func _street_reach(i: int, front: Vector2i) -> float:
	# How far a plot's front can come forward into the road tile, so buildings
	# sit by the pavement instead of behind a wide strip of grass. Only where the
	# road runs straight past the plot (not on bends, where plots could collide).
	var tile := Vector2i(i % map_w, i / map_w)
	var road := tile + front
	if not _is_road(road):
		return 0.0
	var along := Vector2i(front.y, -front.x)
	if _is_road(road + along) and _is_road(road - along):
		return cell * 0.5 - ROAD_HALF_WIDTH - 1.0
	return 0.0


func _place(i: int, front: Vector2i, along: float, back: float, w: float, d: float) -> Dictionary:
	# Where something sits on its plot.
	#   along: metres left/right of the plot centre, along the street
	#   back:  metres back from the plot's front (the pavement, where there is one)
	var x := i % map_w
	var y := i / map_w
	var centre := tile_centre(Vector2i(x, y))
	var fwd := Vector2(front)                  # towards the street
	var away := -fwd
	var across := Vector2(away.y, -away.x)
	var front_edge := centre + fwd * (cell * 0.5 + _street_reach(i, front))
	var mid := front_edge + across * along + away * (back + d * 0.5)
	# Sit on the lowest corner so nothing floats on a slope.
	var base := INF
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			var q: Vector2 = mid + across * (w * sx) + away * (d * sz)
			base = minf(base, height_at(q.x, q.y))
	var top := -INF
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			var q: Vector2 = mid + across * (w * sx) + away * (d * sz)
			top = maxf(top, height_at(q.x, q.y))
	base = maxf(base, 0.3) - 0.3
	var x_axis := Vector3(away.y, 0.0, -away.x)   # along the street
	var z_axis := Vector3(away.x, 0.0, away.y)    # back from the street
	return {"pos": Vector3(mid.x, base, mid.y), "x": x_axis, "z": z_axis,
		"rise": maxf(top, 0.3) - 0.3 - base, "ground": maxf(height_at(mid.x, mid.y), 0.0)}


func _depth(i: int, front: Vector2i) -> float:
	# How deep a plot is, from its front (the pavement) to the back of the tile.
	return cell + _street_reach(i, front)


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


# --- Lot details: flat paving, small props and parked cars ---

func _slab(i: int, front: Vector2i, along: float, back: float, w: float, d: float,
		colour: Color, lift: float = 0.0) -> void:
	# A flat surface (driveway, car park, yard), 15 cm proud of the ground.
	var spot := _place(i, front, along, back, w, d)
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	# Thick enough to clear the ground on a slope (like a levelled car park).
	var b3 := Basis(x_axis * w, Vector3.UP * (float(spot["rise"]) + 0.45 + lift), z_axis * d)
	_paving_items.append([Transform3D(b3, spot["pos"]), colour])


func _prop(i: int, front: Vector2i, along: float, back: float, w: float, d: float, h: float,
		colour: Color) -> void:
	# A box standing on the plot: hedge, wall, container.
	var spot := _place(i, front, along, back, w, d)
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
	pos.y = float(spot["ground"]) - 0.1
	_prop_items.append([Transform3D(Basis(x_axis * w, Vector3.UP * h, z_axis * d), pos), colour])


func _parked_car(i: int, front: Vector2i, along: float, back: float, nose_to_street: bool,
		rng: RandomNumberGenerator) -> void:
	var spot := _place(i, front, along, back, 1.9, 4.4)
	var z_axis: Vector3 = spot["z"]
	var facing := Basis.looking_at(-z_axis if nose_to_street else z_axis, Vector3.UP)
	var base: Vector3 = spot["pos"]
	base.y = maxf(float(spot["ground"]), base.y + float(spot["rise"])) + 0.15
	var paint: Color = CAR_PAINT[rng.randi_range(0, CAR_PAINT.size() - 1)]
	_parked_items.append([
		Transform3D(facing * Basis.from_scale(Vector3(1.85, 1.1, 4.3)), base + Vector3.UP * 0.75),
		paint,
		Transform3D(facing * Basis.from_scale(Vector3(1.65, 0.7, 2.3)), base + Vector3.UP * 1.6 + facing.z * 0.35)])


func _hedge_colour(rng: RandomNumberGenerator) -> Color:
	return Color(rng.randf_range(0.13, 0.19), rng.randf_range(0.27, 0.34), rng.randf_range(0.11, 0.15))


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
	if t == Tile.INDUSTRY:
		return
	# Corner and through plots: line every other road they touch as well, in
	# that road's verge (so the rows never run into the main layout).
	for side: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if side == front or _street_reach(i, side) <= 0.0:
			continue
		_plan_frontage_row(i, t, lv, side, rng, wall_list, roof_list)


func _plan_frontage_row(i: int, t: int, lv: int, side: Vector2i, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array) -> void:
	var value := _values[i] if i < _values.size() else 0.3
	_slab(i, side, 0.0, 0.0, 48.0, 3.0, PAVEMENT)
	if t == Tile.HOMES and lv == 2 and sim.density[i] >= 1:
		# A terrace along this street too.
		var stone: Color = _house_colour(rng)
		for along: float in [-15.5, 0.0, 15.5]:
			var spot := _place(i, side, along, 4.0, 15.0, 8.5)
			_add_block(spot, 15.0, 8.5, 6.2, stone, STYLE_HOUSE, 3.2, SLATE, wall_list, roof_list)
		return
	if t == Tile.HOMES and lv <= 2:
		# A row of villas with driveways and hedges.
		var green := _hedge_colour(rng)
		for along: float in [-17.25, -5.75, 5.75, 17.25]:
			if rng.randf() < 0.1:
				continue
			var w := rng.randf_range(7.0, 7.8)
			var d := rng.randf_range(7.0, 8.5)
			var house_along: float = along - 5.3 + w * 0.5
			var spot := _place(i, side, house_along, 4.0, w, d)
			_add_block(spot, w, d, 5.6 if rng.randf() < 0.8 else 3.2, _house_colour(rng), STYLE_HOUSE,
				rng.randf_range(2.8, 3.6), SLATE if rng.randf() < 0.75 else ROOF_TILE, wall_list, roof_list)
			var drive_along: float = along - 5.3 + w + 1.5
			_slab(i, side, drive_along, 3.0, 2.6, d + 1.0, DRIVEWAY)
			if rng.randf() < 0.5:
				_parked_car(i, side, drive_along, 3.5, rng.randf() < 0.3, rng)
			_prop(i, side, house_along, 3.2, w, 0.8, 1.1, green)
		return
	if lv >= 4:
		# Tall plots: a classical block and a modern one along this street too.
		var classical_left: bool = rng.randf() < 0.5
		for along: float in [-12.5, 12.5]:
			var spot := _place(i, side, along, 3.0, 21.0, 13.0)
			if (along < 0.0) == classical_left:
				_classical_block(spot, 21.0, 13.0, rng.randi_range(5, 6), _classical_stone(rng),
					t == Tile.SHOPS, t == Tile.HOMES, wall_list, roof_list)
			else:
				_modern_block(spot, 21.0, 13.0, rng.randi_range(6, 8) + roundi(value * 2.0),
					_modern_cladding(rng), value >= 0.6, wall_list, roof_list)
		return
	# Flats or shops along the street: storeys follow the plot's level.
	var storeys := 3
	var colour := RED_SANDSTONE if rng.randf() < 0.5 else BLONDE_SANDSTONE
	var style := STYLE_FLATS
	var roof_h := 4.5
	if t == Tile.SHOPS:
		style = STYLE_SHOP
		colour = [WHITE_RENDER, BLONDE_SANDSTONE, CREAM_RENDER, GREY_RENDER][rng.randi_range(0, 3)]
		storeys = 2 if lv == 1 else 3
		roof_h = 0.0
	if lv >= 4:
		storeys = rng.randi_range(5, 6) if lv == 4 else rng.randi_range(6, 8) + roundi(value * 2.0)
		if lv >= 5:
			roof_h = 0.0
			style = STYLE_GLASS if value >= 0.6 else (STYLE_SHOP if t == Tile.SHOPS else STYLE_FLATS)
			colour = GLASS_FRAME if style == STYLE_GLASS else MODERN_WHITE
	for along: float in [-12.5, 12.5]:
		var spot := _place(i, side, along, 3.0, 22.0, 13.0)
		var height := storeys * 3.1 + 0.5
		_add_block(spot, 22.0, 13.0, height, colour, style, roof_h, SLATE, wall_list, roof_list)
		if roof_h == 0.0 and storeys >= 5:
			_add_rooftop(spot, 22.0, 13.0, height, wall_list)


func _road_near(i: int) -> bool:
	return sim.has_road_access(i)


func _plan_site(i: int, t: int, wall_list: Array) -> void:
	# A zoned plot waiting to grow: hoarding round it, foundations, a site cabin,
	# piles of materials and sometimes a tower crane.
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 4241 + t
	var front := _frontage(i)
	var depth := _depth(i, front)
	_slab(i, front, -4.0, 5.0, 30.0, 16.0, FOUNDATION)
	_prop(i, front, 0.0, 1.0, 46.0, 0.2, 2.2, HOARDING)                 # front hoarding
	_prop(i, front, -23.0, 1.0, 0.2, depth - 3.0, 2.2, HOARDING)
	_prop(i, front, 23.0, 1.0, 0.2, depth - 3.0, 2.2, HOARDING)
	var cabin := _place(i, front, 16.0, 4.0, 6.0, 2.6)
	var cx: Vector3 = cabin["x"]
	var cz: Vector3 = cabin["z"]
	wall_list.append([Transform3D(Basis(cx * 6.0, Vector3.UP * 2.7, cz * 2.6), cabin["pos"]),
		SITE_CABIN, Color(6.0, 2.7, 2.6, STYLE_PLANT)])
	for k in 3:
		_prop(i, front, rng.randf_range(-18.0, 10.0), rng.randf_range(24.0, depth - 8.0),
			rng.randf_range(2.0, 4.0), rng.randf_range(2.0, 4.0), rng.randf_range(0.8, 1.8),
			[CONCRETE, RED_SANDSTONE, Color(0.55, 0.42, 0.28)][k])
	if t != Tile.INDUSTRY and sim.density[i] >= 1 and rng.randf() < (0.4 if sim.density[i] == 1 else 0.8):
		# Tower crane: mast, jib out over the foundations, counterweight.
		var mast := _place(i, front, 8.0, 22.0, 1.8, 1.8)
		var mx: Vector3 = mast["x"]
		var mz: Vector3 = mast["z"]
		var base: Vector3 = mast["pos"]
		var top := 34.0
		_prop_items.append([Transform3D(Basis(mx * 1.8, Vector3.UP * top, mz * 1.8), base), CRANE_YELLOW])
		var jib_dir := (mx if rng.randf() < 0.5 else -mx)
		_prop_items.append([Transform3D(Basis(jib_dir * 26.0, Vector3.UP * 1.4, mz * 1.4),
			base + Vector3.UP * top + jib_dir * 9.0), CRANE_YELLOW])
		_prop_items.append([Transform3D(Basis(mx * 3.0, Vector3.UP * 2.0, mz * 2.0),
			base + Vector3.UP * (top - 1.0) - jib_dir * 6.0), CONCRETE])


func _infill_kind(x: int, y: int) -> int:
	# Open land counts as a gap in the town when most of its neighbours are built on.
	var i := y * map_w + x
	if water[i] == 1 or heights[i] < 1.0:
		return 0
	var built := 0
	var road_beside := false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n := Vector2i(x + dx, y + dy)
			if n.x < 0 or n.y < 0 or n.x >= map_w or n.y >= map_h:
				continue
			var nt: int = sim.tiles[n.y * map_w + n.x]
			if nt != Tile.EMPTY and nt != Tile.POWER_LINE:
				built += 1
			if nt == Tile.ROAD and absi(dx) + absi(dy) == 1:
				road_beside = true
	if built < 5:
		return 0
	# Mostly pocket parks; some allotments; a car park now and then by a road.
	var pick := (i * 2654435761) % 10
	if pick >= 8 and road_beside:
		return INFILL_CAR_PARK
	if pick >= 5:
		return INFILL_ALLOTMENTS
	return INFILL_PARK


func _plan_infill(i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 977
	var front := _frontage(i)
	var depth := _depth(i, front)
	match _infill[i]:
		INFILL_PARK:
			# Paths crossing the green (trees are planted with the other city trees).
			_slab(i, front, 0.0, 0.0, 2.4, depth - 1.0, PAVEMENT)
			_slab(i, front, 0.0, depth * 0.5 - 1.2, 46.0, 2.4, PAVEMENT)
		INFILL_ALLOTMENTS:
			# Rows of beds, alternating soil and crops, with a couple of sheds.
			for row in 6:
				for col in 4:
					var colour := SOIL if (row + col + rng.randi_range(0, 1)) % 2 == 0 else CROPS
					_slab(i, front, -16.5 + col * 11.0, 4.0 + row * ((depth - 10.0) / 6.0), 9.5,
						(depth - 10.0) / 6.0 - 1.2, colour)
			for k in 2:
				_prop(i, front, rng.randf_range(-18.0, 18.0), rng.randf_range(6.0, depth - 10.0),
					2.4, 3.0, 2.2, Color(0.30, 0.38, 0.30))
		INFILL_CAR_PARK:
			_slab(i, front, 0.0, 1.0, 46.0, depth - 3.0, CAR_PARK)
			var row_back := 2.0
			var facing := true
			while row_back + 5.0 <= depth - 2.5:
				for k in 15:
					var bay := -19.6 + k * 2.8
					_slab(i, front, bay - 1.4, row_back, 0.12, 4.8, BAY_LINE, 0.03)
					if rng.randf() < 0.5:
						_parked_car(i, front, bay, row_back + 0.2, facing, rng)
				row_back += 5.0 if facing else 11.0
				facing = not facing


# ---------------------------------------------------------------- preview

func _build_preview() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(cell * 0.94, 3.0, cell * 0.94)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	preview.multimesh = _new_multimesh(box, false)
	preview.material_override = mat
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)


func set_preview(items: Array, colour: Color) -> void:
	# items: [[tile, ok], ...]. OK tiles in the tool's colour, problem tiles in red.
	var list: Array = []
	for item in items:
		var p: Vector3 = ground_point(item[0])
		var c: Color = Color(colour, 0.38) if item[1] else Color(1.0, 0.25, 0.2, 0.45)
		list.append([Transform3D(Basis(), p + Vector3.UP * 1.5), c])
	_fill(preview.multimesh, list, false)
	hover_box.visible = items.is_empty() and hover_box.visible


func _house_colour(rng: RandomNumberGenerator) -> Color:
	var choices := [RED_SANDSTONE, BLONDE_SANDSTONE, WHITE_RENDER, WHITE_RENDER,
		CREAM_RENDER, GREY_RENDER, BLONDE_SANDSTONE]
	var c: Color = choices[rng.randi_range(0, choices.size() - 1)]
	return c.darkened(rng.randf_range(-0.05, 0.08))


func _plan_homes(i: int, lv: int, front: Vector2i, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array) -> void:
	var depth := _depth(i, front)
	var value := _values[i] if i < _values.size() else 0.3
	if lv >= 4:
		_plan_tall_homes(i, lv, front, depth, value, rng, wall_list, roof_list)
		return
	if lv >= 3:
		# Tenements front and back, with a shared back court between them.
		var back_row := depth - 16.0
		for row_back: float in [3.0, back_row]:
			for along: float in [-12.5, 12.5]:
				var storeys := rng.randi_range(3, 4)
				var stone := RED_SANDSTONE if rng.randf() < 0.5 else BLONDE_SANDSTONE
				var spot := _place(i, front, along, row_back, 22.0, 13.0)
				_add_block(spot, 22.0, 13.0, storeys * 3.0 + 0.5, stone, STYLE_FLATS, 4.5, SLATE,
					wall_list, roof_list)
		_slab(i, front, 0.0, 0.0, 48.0, 3.0, PAVEMENT)                       # front pavement
		_slab(i, front, 0.0, 16.5, 48.0, back_row - 17.0, COURT)            # back court
		var mid := (16.5 + back_row) * 0.5 - 2.2
		for k in 7:
			if rng.randf() < 0.6:
				_parked_car(i, front, -18.0 + k * 6.0, mid, rng.randf() < 0.5, rng)
		return

	if lv == 2 and sim.density[i] >= 1:
		_plan_terraces(i, front, depth, rng, wall_list, roof_list)
		return

	# Villas on their own lots (11.5 m wide, hedged): house, driveway down the side,
	# maybe a car. From level 2 a second row behind, reached by a lane that runs
	# in from the street where the first front lot would be.
	var rows: Array = [6.0] if lv == 1 else [6.0, depth - 17.0]
	var lane_at := depth - 25.0
	var green := _hedge_colour(rng)
	for row in rows.size():
		var back: float = rows[row]
		for along: float in [-17.25, -5.75, 5.75, 17.25]:
			if row == 0 and lv >= 2 and along < -17.0:
				continue   # this lot is the lane
			if rng.randf() < 0.1:
				continue   # the odd empty garden plot
			var w := rng.randf_range(7.0, 7.8)
			var d := rng.randf_range(7.0, 9.0)
			var h := 5.6 if rng.randf() < 0.8 else 3.2   # mostly two storeys, some bungalows
			var roof := SLATE if rng.randf() < 0.75 else ROOF_TILE
			var house_along: float = along - 5.3 + w * 0.5
			var spot := _place(i, front, house_along, back, w, d)
			_add_block(spot, w, d, h, _house_colour(rng), STYLE_HOUSE,
				rng.randf_range(2.8, 3.6), roof, wall_list, roof_list)
			var drive_along: float = along - 5.3 + w + 1.5
			var drive_from := 0.0 if row == 0 else lane_at + 3.0
			_slab(i, front, drive_along, drive_from, 2.6, back + d - drive_from, DRIVEWAY)
			if rng.randf() < 0.6:
				_parked_car(i, front, drive_along, drive_from + 0.8, rng.randf() < 0.3, rng)
			# Hedge along the front of the garden.
			_prop(i, front, house_along, drive_from + 0.3, w, 0.8, 1.1, green)
		# Hedges between neighbouring lots, front to back.
		var row_from := 0.3 if row == 0 else lane_at + 3.3
		var row_to := lane_at if (row == 0 and lv >= 2) else depth - 0.5
		for edge: float in [-11.5, 0.0, 11.5]:
			_prop(i, front, edge, row_from, 0.7, row_to - row_from, 1.4, green)
	if lv >= 2:
		_slab(i, front, -17.25, 0.0, 3.2, lane_at + 3.0, DRIVEWAY)     # lane in from the street
		_slab(i, front, 0.0, lane_at, 48.0, 3.0, DRIVEWAY)              # lane behind the front gardens


func _plan_terraces(i: int, front: Vector2i, depth: float, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array) -> void:
	# Medium density: two-storey terraces, front and back, each split into a few
	# runs of joined houses, with small front gardens and long back gardens.
	var back_row: float = depth - 13.0
	var green := _hedge_colour(rng)
	for row_back: float in [4.0, back_row]:
		var stone: Color = _house_colour(rng)
		var roof: Color = SLATE if rng.randf() < 0.7 else ROOF_TILE
		for along: float in [-15.5, 0.0, 15.5]:
			var spot := _place(i, front, along, row_back, 15.0, 8.5)
			_add_block(spot, 15.0, 8.5, 6.2, stone.darkened(rng.randf_range(-0.04, 0.06)), STYLE_HOUSE,
				3.2, roof, wall_list, roof_list)
		_prop(i, front, 0.0, row_back - 3.6, 47.0, 0.7, 1.0, green)   # front garden hedge
	_slab(i, front, 0.0, 0.0, 48.0, 3.0, PAVEMENT)
	# A back lane between the two rows of back gardens, with a few cars.
	var lane: float = (4.0 + 8.5 + back_row) * 0.5 - 1.5
	_slab(i, front, 0.0, lane, 48.0, 3.0, DRIVEWAY)
	for k in 4:
		if rng.randf() < 0.5:
			_parked_car(i, front, -18.0 + k * 12.0, lane - 0.7, rng.randf() < 0.5, rng)


func _plan_tall_homes(i: int, lv: int, front: Vector2i, depth: float, value: float,
		rng: RandomNumberGenerator, wall_list: Array, roof_list: Array) -> void:
	# Building upwards where space is short or zoned high. A mix of classical
	# sandstone (bays, cornices, mansard roofs) and modern premium (glazing,
	# timber and bronze, balconies, penthouses), around a landscaped court.
	var extra: int = roundi(value * 2.0)       # valuable land squeezes in a floor or two
	var court_back: float = depth - 17.0
	var glassy: bool = value >= 0.6
	if lv == 4:
		# Mansion flats: classical sandstone, 5-6 storeys, front and back.
		for row_back: float in [3.0, court_back]:
			for along: float in [-12.5, 12.5]:
				var spot := _place(i, front, along, row_back, 21.0, 13.0)
				_classical_block(spot, 21.0, 13.0, rng.randi_range(5, 6), _classical_stone(rng),
					false, true, wall_list, roof_list)
	elif lv == 5:
		# A street of mixed character: classical and modern side by side, 6-9 storeys.
		var first_classical: bool = rng.randf() < 0.5
		for row: int in 2:
			var row_back: float = 3.0 if row == 0 else court_back
			for k: int in 2:
				var along: float = -12.5 if k == 0 else 12.5
				var spot := _place(i, front, along, row_back, 21.0, 13.0)
				if (k == 0) == first_classical and row == 0:
					_classical_block(spot, 21.0, 13.0, rng.randi_range(6, 7), _classical_stone(rng),
						false, true, wall_list, roof_list)
				else:
					_modern_block(spot, 21.0, 13.0, rng.randi_range(7, 8) + extra, _modern_cladding(rng),
						glassy, wall_list, roof_list)
	else:
		# A slender modern tower beside a classical block, and a second tower behind,
		# set diagonally so each has views and light.
		var classical := _place(i, front, -13.0, 3.0, 20.0, 13.0)
		_classical_block(classical, 20.0, 13.0, rng.randi_range(6, 7), _classical_stone(rng),
			false, true, wall_list, roof_list)
		var tower := _place(i, front, 12.0, 3.0, 17.0, 16.0)
		_modern_block(tower, 17.0, 16.0, rng.randi_range(12, 14) + extra * 2, _modern_cladding(rng),
			glassy, wall_list, roof_list)
		var back_tower := _place(i, front, -10.0, court_back - 3.0, 17.0, 16.0)
		_modern_block(back_tower, 17.0, 16.0, rng.randi_range(10, 12) + extra, _modern_cladding(rng),
			glassy, wall_list, roof_list)
	_premium_court(i, front, 17.5, court_back - 1.0, rng)


func _classical_stone(rng: RandomNumberGenerator) -> Color:
	var stones := [HONEY_STONE, BLONDE_SANDSTONE, RED_SANDSTONE, CREAM_STONE, HONEY_STONE]
	var c: Color = stones[rng.randi_range(0, stones.size() - 1)]
	return c.darkened(rng.randf_range(-0.03, 0.05))


func _modern_cladding(rng: RandomNumberGenerator) -> Color:
	var options := [TIMBER, BRONZE, CREAM_STONE, CHARCOAL, TIMBER]
	var c: Color = options[rng.randi_range(0, options.size() - 1)]
	return c


func _classical_block(spot: Dictionary, w: float, d: float, storeys: int, stone: Color,
		shops: bool, bays: bool, wall_list: Array, roof_list: Array, mansard: bool = true) -> void:
	# Sandstone: tall rusticated ground floor, sash windows in stone surrounds,
	# full-height bay windows, a cornice and a slate mansard roof with dormers.
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
	var h: float = 4.2 + (storeys - 1) * 3.4 + 0.6
	var style: int = STYLE_CLASSICAL_SHOPS if shops else STYLE_CLASSICAL
	wall_list.append([Transform3D(Basis(x_axis * w, Vector3.UP * h, z_axis * d), pos), stone,
		Color(w, h, d, style)])
	# Cornice: a lighter projecting band along the top.
	var trim: Color = stone.lightened(0.15)
	wall_list.append([Transform3D(Basis(x_axis * (w + 1.0), Vector3.UP * 0.9, z_axis * (d + 1.0)),
		pos + Vector3.UP * h), trim, Color(w + 1.0, 0.9, d + 1.0, STYLE_PLANT)])
	if not mansard:
		return   # a podium: something else stands on top
	# Mansard roof.
	roof_list.append([Transform3D(Basis(x_axis * (w - 0.4), Vector3.UP * 4.0, z_axis * (d - 0.4)),
		pos + Vector3.UP * (h + 0.9)), SLATE])
	# Dormers along the front slope.
	var dormers: int = maxi(2, int(w / 5.5))
	for k: int in dormers:
		var along: float = -w * 0.5 + (k + 0.5) * w / dormers
		var at: Vector3 = pos + Vector3.UP * (h + 1.2) + x_axis * along - z_axis * (d * 0.5 - 2.4)
		wall_list.append([Transform3D(Basis(x_axis * 1.8, Vector3.UP * 2.0, z_axis * 1.6), at),
			GLASS_FRAME, Color(1.8, 2.0, 1.6, STYLE_GLASS)])
	if bays and not shops:
		# Two canted bays up the front, from the first floor to the cornice.
		for side: float in [-0.25, 0.25]:
			var at: Vector3 = pos + x_axis * (w * side) - z_axis * (d * 0.5 + 0.65) + Vector3.UP * 4.2
			wall_list.append([Transform3D(Basis(x_axis * 3.6, Vector3.UP * (h - 4.2), z_axis * 1.3), at),
				stone, Color(3.6, h - 4.2, 1.3, STYLE_CLASSICAL)])


func _modern_block(spot: Dictionary, w: float, d: float, storeys: int, cladding: Color,
		glassy: bool, wall_list: Array, roof_list: Array) -> void:
	# Modern premium: a glass ground floor, framed glazing with clad bays (or all
	# glass on the very best land), staggered glass balconies, a set-back
	# penthouse and a thin roof canopy.
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
	var base_h: float = 4.6
	var body_floors: int = maxi(storeys - 3, 1)
	var body_h: float = body_floors * 3.2
	wall_list.append([Transform3D(Basis(x_axis * w, Vector3.UP * base_h, z_axis * d), pos),
		GLASS_FRAME, Color(w, base_h, d, STYLE_GLASS)])
	var body_style: int = STYLE_GLASS if glassy else STYLE_MODERN
	var body_colour: Color = GLASS_FRAME if glassy else cladding
	wall_list.append([Transform3D(Basis(x_axis * w, Vector3.UP * body_h, z_axis * d), pos + Vector3.UP * base_h),
		body_colour, Color(w, body_h, d, body_style)])
	# Balconies on alternate sides, floor by floor: a slab and a glass balustrade.
	for f: int in body_floors:
		var y: float = base_h + f * 3.2
		var along: float = w * (0.22 if f % 2 == 0 else -0.22)
		var at: Vector3 = pos + Vector3.UP * y + x_axis * along - z_axis * (d * 0.5 + 0.8)
		_prop_items.append([Transform3D(Basis(x_axis * (w * 0.44), Vector3.UP * 0.22, z_axis * 1.6), at), TRIM])
		_prop_items.append([Transform3D(Basis(x_axis * (w * 0.44), Vector3.UP * 1.05, z_axis * 0.08),
			at + Vector3.UP * 0.22 - z_axis * 0.76), BALCONY_GLASS])
	# Penthouse: two floors set back, all glass, under a light canopy.
	var top: float = base_h + body_h
	var pw: float = w - 5.0
	var pd: float = d - 4.0
	var penthouse_at: Vector3 = pos + Vector3.UP * top + z_axis * 1.0
	wall_list.append([Transform3D(Basis(x_axis * pw, Vector3.UP * 6.4, z_axis * pd), penthouse_at),
		GLASS_FRAME, Color(pw, 6.4, pd, STYLE_GLASS)])
	wall_list.append([Transform3D(Basis(x_axis * (pw + 3.0), Vector3.UP * 0.45, z_axis * (pd + 2.5)),
		penthouse_at + Vector3.UP * 6.4), TRIM, Color(pw + 3.0, 0.45, pd + 2.5, STYLE_PLANT)])
	# Roof terrace edge on the main roof.
	_prop_items.append([Transform3D(Basis(x_axis * w, Vector3.UP * 1.0, z_axis * 0.1),
		pos + Vector3.UP * top - z_axis * (d * 0.5 - 0.05)), BALCONY_GLASS])


func _premium_court(i: int, front: Vector2i, from: float, to: float, rng: RandomNumberGenerator) -> void:
	# A landscaped court between the blocks (parking goes underground): lawn,
	# a path through the middle and trees.
	_slab(i, front, 0.0, 0.0, 48.0, 3.0, PAVEMENT)
	if to - from < 4.0:
		return
	_slab(i, front, 0.0, from, 46.0, to - from, LAWN)
	_slab(i, front, 0.0, from, 2.4, to - from, PAVEMENT, 0.02)
	for k: int in 6:
		var along: float = rng.randf_range(-20.0, 20.0)
		if absf(along) < 3.0:
			along += 6.0
		var back: float = rng.randf_range(from + 2.0, to - 2.0)
		var spot := _place(i, front, along, back, 1.0, 1.0)
		var at: Vector3 = spot["pos"]
		_extra_trees.append([Vector2(at.x, at.z), rng.randf_range(7.0, 10.0)])


func _add_rooftop(spot: Dictionary, w: float, d: float, h: float, wall_list: Array) -> void:
	# Lift housing and plant on a flat roof.
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
	var b3 := Basis(x_axis * (w * 0.3), Vector3.UP * 3.0, z_axis * (d * 0.35))
	wall_list.append([Transform3D(b3, pos + Vector3.UP * h), CONCRETE, Color(w * 0.3, 3.0, d * 0.35, STYLE_PLANT)])


func _plan_shops(i: int, lv: int, front: Vector2i, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array) -> void:
	var colours := [WHITE_RENDER, BLONDE_SANDSTONE, CREAM_RENDER, RED_SANDSTONE, GREY_RENDER]
	var depth := _depth(i, front)
	var value := _values[i] if i < _values.size() else 0.3
	if lv >= 4:
		# Classical commercial buildings with shopfronts; then a classical block
		# beside a modern office; then a glass office tower over a classical podium.
		var extra: int = roundi(value * 2.0)
		var glassy: bool = value >= 0.55
		if lv == 4:
			for along: float in [-12.5, 12.5]:
				var spot := _place(i, front, along, 3.0, 23.0, 18.0)
				_classical_block(spot, 23.0, 18.0, rng.randi_range(5, 6), _classical_stone(rng),
					true, false, wall_list, roof_list)
		elif lv == 5:
			var left := _place(i, front, -12.5, 3.0, 23.0, 18.0)
			_classical_block(left, 23.0, 18.0, rng.randi_range(5, 6), _classical_stone(rng),
				true, false, wall_list, roof_list)
			var right := _place(i, front, 12.5, 3.0, 23.0, 18.0)
			_modern_block(right, 23.0, 18.0, rng.randi_range(8, 9) + extra, _modern_cladding(rng),
				glassy, wall_list, roof_list)
		else:
			var podium := _place(i, front, 0.0, 3.0, 46.0, 22.0)
			_classical_block(podium, 46.0, 22.0, 3, _classical_stone(rng), true, false, wall_list, roof_list, false)
			var tower := _place(i, front, 0.0, 6.0, 24.0, 16.0)
			var tower_pos: Vector3 = tower["pos"]
			tower["pos"] = tower_pos + Vector3.UP * (4.2 + 2 * 3.4 + 0.6 + 0.9)
			_modern_block(tower, 24.0, 16.0, rng.randi_range(10, 12) + extra * 2, _modern_cladding(rng),
				true, wall_list, roof_list)
		_slab(i, front, 0.0, 0.0, 49.0, 3.0, PAVEMENT)
		# A multi-storey car park behind.
		var deck := _place(i, front, 0.0, 28.0, 40.0, depth - 31.0)
		_add_block(deck, 40.0, depth - 31.0, 9.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, roof_list)
		return
	var park_from := 17.0
	if lv >= 3:
		for along: float in [-12.5, 12.5]:
			var spot := _place(i, front, along, 3.0, 23.0, 18.0)
			_add_block(spot, 23.0, 18.0, rng.randi_range(3, 4) * 3.2 + 0.6,
				colours[rng.randi_range(0, colours.size() - 1)], STYLE_SHOP, 0.0, SLATE,
				wall_list, roof_list)
		park_from = 23.0
	else:
		# A parade of shops along the street; flats above from level 2.
		var height := 4.2 if lv == 1 else 7.0
		for along: float in [-16.5, 0.0, 16.5]:
			var spot := _place(i, front, along, 3.0, 15.5, 13.0)
			_add_block(spot, 15.5, 13.0, height + rng.randf_range(-0.2, 0.4),
				colours[rng.randi_range(0, colours.size() - 1)], STYLE_SHOP,
				3.0 if lv == 2 else 0.0, SLATE, wall_list, roof_list)
	# Wide pavement out front; a car park filling the rest of the plot.
	_slab(i, front, 0.0, 0.0, 49.0, 3.0, PAVEMENT)
	var park_depth := depth - park_from - 1.0
	_slab(i, front, 0.0, park_from, 47.0, park_depth, CAR_PARK)
	# Rows of marked bays: each double row is 2 x 5 m bays plus a 6 m aisle.
	var row_back := park_from + 1.0
	var facing_street := true
	while row_back + 5.0 <= park_from + park_depth - 0.5:
		for k in 15:
			var bay := -19.6 + k * 2.8
			_slab(i, front, bay - 1.4, row_back, 0.12, 4.8, BAY_LINE, 0.03)
			if rng.randf() < 0.55:
				_parked_car(i, front, bay, row_back + 0.2, facing_street, rng)
		row_back += 5.0 if facing_street else 11.0
		facing_street = not facing_street


func _plan_industry(i: int, lv: int, front: Vector2i, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array, chimney_list: Array) -> void:
	var cladding := SHED_METAL if rng.randf() < 0.6 else SHED_GREEN
	var depth := _depth(i, front)
	_slab(i, front, 0.0, 0.0, 49.0, depth - 1.0, YARD)
	var stack_at := Vector2(-14.0, depth - 10.0)
	if lv == 1:
		var spot := _place(i, front, 0.0, 6.0, 34.0, 28.0)
		_add_block(spot, 34.0, 28.0, 8.0, cladding, STYLE_INDUSTRY, 2.2, SHED_METAL.darkened(0.2),
			wall_list, roof_list)
	elif lv == 2:
		var a := _place(i, front, -7.0, 4.0, 32.0, 26.0)
		_add_block(a, 32.0, 26.0, 9.0, cladding, STYLE_INDUSTRY, 2.2, SHED_METAL.darkened(0.2),
			wall_list, roof_list)
		var b := _place(i, front, 14.0, depth - 22.0, 18.0, 18.0)
		_add_block(b, 18.0, 18.0, 7.0, CONCRETE, STYLE_INDUSTRY, 0.0, SLATE, wall_list, roof_list)
	else:
		var spot := _place(i, front, -3.0, 4.0, 42.0, depth - 18.0)
		_add_block(spot, 42.0, depth - 18.0, 13.0, cladding, STYLE_INDUSTRY, 3.0, SHED_METAL.darkened(0.25),
			wall_list, roof_list)
		var chimney := _place(i, front, 20.0, depth - 8.0, 4.0, 4.0)
		var pos: Vector3 = chimney["pos"]
		chimney_list.append([Transform3D(Basis.from_scale(Vector3(2.0, 34.0, 2.0)),
			pos + Vector3.UP * 17.0), RED_SANDSTONE.darkened(0.3)])
	# Shipping containers stacked in the yard.
	for k in 4:
		var colour: Color = CONTAINERS[rng.randi_range(0, CONTAINERS.size() - 1)]
		var height := 2.6 * (2 if rng.randf() < 0.35 else 1)
		_prop(i, front, stack_at.x + k * 3.0, stack_at.y, 2.5, 6.1, height, colour)
	# A few staff cars by the gate.
	for k in 4:
		if rng.randf() < 0.6:
			_parked_car(i, front, 12.0 + k * 3.0, 0.8, true, rng)


func _plan_plant(i: int, wall_list: Array, chimney_list: Array) -> void:
	var front := _frontage(i)
	var depth := _depth(i, front)
	_slab(i, front, 0.0, 0.0, 49.0, depth - 1.0, YARD)
	var spot := _place(i, front, -6.0, 6.0, 30.0, 26.0)
	_add_block(spot, 30.0, 26.0, 18.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, [])
	for along: float in [12.0, 19.0]:
		var stack := _place(i, front, along, 30.0, 5.0, 5.0)
		var pos: Vector3 = stack["pos"]
		chimney_list.append([Transform3D(Basis.from_scale(Vector3(3.0, 65.0, 3.0)),
			pos + Vector3.UP * 32.5), Color(0.75, 0.74, 0.72)])
	# Security fence round the edge.
	var fence := Color(0.35, 0.38, 0.36)
	_prop(i, front, 0.0, 0.5, 48.0, 0.15, 2.4, fence)
	_prop(i, front, 0.0, depth - 1.5, 48.0, 0.15, 2.4, fence)
	_prop(i, front, -24.0, 0.5, 0.15, depth - 2.0, 2.4, fence)
	_prop(i, front, 24.0, 0.5, 0.15, depth - 2.0, 2.4, fence)


# -------------------------------------------------------------------- trees

func _tree_multimesh(node: MultiMeshInstance3D, mesh: Mesh, shadows: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	node.multimesh = _new_multimesh(mesh, false)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _build_trees() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.35
	trunk_mesh.bottom_radius = 0.5
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.5
	crown_mesh.height = 1.0
	crown_mesh.radial_segments = 10
	crown_mesh.rings = 6
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 0.5
	cone_mesh.height = 1.0
	cone_mesh.radial_segments = 8
	cone_mesh.rings = 1
	_tree_multimesh(trunks, trunk_mesh, false)
	_tree_multimesh(crowns, crown_mesh, true)
	_tree_multimesh(cones, cone_mesh, true)
	_tree_multimesh(city_trunks, trunk_mesh, false)
	_tree_multimesh(city_crowns, crown_mesh, true)

	# Woods where the noise is high, open fields where it's low, the odd lone tree.
	var noise := FastNoiseLite.new()
	noise.seed = 1977
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var trunk_items: Array = []
	var crown_items: Array = []
	var cone_items: Array = []
	_tile_has_trees.resize(map_w * map_h)
	_tile_has_trees.fill(1)
	for y in map_h:
		for x in map_w:
			var i := y * map_w + x
			if water[i] == 1 or heights[i] < 3.0:
				continue   # no trees on the sea or the beach
			var woods := clampf((noise.get_noise_2d(x, y) - 0.08) * 2.4, 0.0, 1.0)
			var count := int(woods * 7.0 + rng.randf() * 0.6)
			if count == 0 and rng.randf() < 0.06:
				count = 1
			for k in count:
				var px := (x + rng.randf_range(0.06, 0.94)) * cell
				var pz := (y + rng.randf_range(0.06, 0.94)) * cell
				var conifer := woods > 0.55 and rng.randf() < 0.5
				var n := _tree_trunk_xf.size()
				var parts := _tree_parts(Vector2(px, pz), rng.randf_range(8.0, 16.0), conifer, rng)
				_tree_trunk_xf.append(parts[0])
				_tree_crown_xf.append(parts[1])
				_tree_conifer.append(1 if conifer else 0)
				trunk_items.append([parts[0], Color(0.30, 0.22, 0.15)])
				if conifer:
					_tree_crown_idx.append(cone_items.size())
					cone_items.append([parts[1], parts[2]])
				else:
					_tree_crown_idx.append(crown_items.size())
					crown_items.append([parts[1], parts[2]])
				if not _trees_in_tile.has(i):
					_trees_in_tile[i] = []
				_trees_in_tile[i].append(n)
	_fill(trunks.multimesh, trunk_items, false)
	_fill(crowns.multimesh, crown_items, false)
	_fill(cones.multimesh, cone_items, false)


func _tree_parts(at: Vector2, tall: float, conifer: bool, rng: RandomNumberGenerator) -> Array:
	# [trunk transform, canopy transform, canopy colour] for one tree.
	var ground := height_at(at.x, at.y)
	var spin := Basis(Vector3.UP, rng.randf() * TAU)
	var trunk_h := tall * (0.3 if conifer else 0.45)
	var trunk := Transform3D(spin.scaled(Vector3(0.7, trunk_h, 0.7)),
		Vector3(at.x, ground + trunk_h * 0.5 - 0.3, at.y))
	var crown: Transform3D
	var colour: Color
	if conifer:
		var cone_h := tall * 0.85
		crown = Transform3D(spin.scaled(Vector3(tall * 0.32, cone_h, tall * 0.32)),
			Vector3(at.x, ground + tall * 0.15 + cone_h * 0.5, at.y))
		colour = Color(rng.randf_range(0.10, 0.15), rng.randf_range(0.22, 0.30), rng.randf_range(0.12, 0.17))
	else:
		var width := tall * rng.randf_range(0.5, 0.7)
		crown = Transform3D(spin.scaled(Vector3(width, tall * 0.55, width)),
			Vector3(at.x, ground + tall * 0.68, at.y))
		colour = Color(rng.randf_range(0.18, 0.30), rng.randf_range(0.30, 0.42), rng.randf_range(0.10, 0.17))
	return [trunk, crown, colour]


func _update_natural_trees(tiles: PackedByteArray) -> void:
	# Trees stay on open land and in parks; building anything else clears them.
	for i in tiles.size():
		var show := 1 if ((tiles[i] == Tile.EMPTY and _infill[i] == 0) or tiles[i] == Tile.PARK) else 0
		if show == _tile_has_trees[i]:
			continue
		_tile_has_trees[i] = show
		if not _trees_in_tile.has(i):
			continue
		for n in _trees_in_tile[i]:
			trunks.multimesh.set_instance_transform(n, _tree_trunk_xf[n] if show == 1 else _hidden)
			var mm := cones.multimesh if _tree_conifer[n] == 1 else crowns.multimesh
			mm.set_instance_transform(_tree_crown_idx[n], _tree_crown_xf[n] if show == 1 else _hidden)


func _build_city_trees(tiles: PackedByteArray, levels: PackedByteArray) -> void:
	# Planted trees: lots in parks, a couple in the back gardens of houses.
	var trunk_items: Array = []
	var crown_items: Array = []
	for i in tiles.size():
		var t := tiles[i]
		var count := 0
		if t == Tile.PARK:
			count = 9
		elif t == Tile.EMPTY and _infill[i] == INFILL_PARK:
			count = 6
		elif t == Tile.HOMES and sim.stage(i) == 1:
			count = 4
		elif t == Tile.HOMES and sim.stage(i) == 2:
			count = 2
		if count == 0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 31 + t
		var c := tile_centre(Vector2i(i % map_w, i / map_w))
		for k in count:
			var spot := c + Vector2(rng.randf_range(-21.0, 21.0), rng.randf_range(-21.0, 21.0))
			if t == Tile.HOMES:
				# Back gardens: the far half of the plot from the street.
				var away := -Vector2(_frontage(i))
				var across := Vector2(away.y, -away.x)
				# Back gardens: the rear of the plot (the very back strip once there's a second row).
				var from: float = 2.0 if sim.stage(i) == 1 else 20.5
				spot = c + away * rng.randf_range(from, 22.5) + across * rng.randf_range(-20.0, 20.0)
			var parts := _tree_parts(spot, rng.randf_range(6.0, 11.0), false, rng)
			trunk_items.append([parts[0], Color(0.30, 0.22, 0.15)])
			crown_items.append([parts[1], parts[2]])
	# Trees planted in landscaped courts.
	var court_rng := RandomNumberGenerator.new()
	court_rng.seed = 7
	for tree in _extra_trees:
		var at: Vector2 = tree[0]
		var tall: float = tree[1]
		var parts := _tree_parts(at, tall, false, court_rng)
		trunk_items.append([parts[0], Color(0.30, 0.22, 0.15)])
		crown_items.append([parts[1], parts[2]])
	# Street trees along straight roads, on any side not taken by a building plot.
	for i in tiles.size():
		if tiles[i] != Tile.ROAD:
			continue
		var tile := Vector2i(i % map_w, i / map_w)
		for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if not (_is_road(tile + axis) and _is_road(tile - axis)):
				continue
			if _is_road(tile + Vector2i(axis.y, axis.x)) or _is_road(tile - Vector2i(axis.y, axis.x)):
				continue   # a junction, keep it clear
			var c := tile_centre(tile)
			var rng := RandomNumberGenerator.new()
			rng.seed = i * 17 + 5
			for side: int in [-1, 1]:
				var normal: Vector2i = Vector2i(axis.y, axis.x) * side
				var beside: Vector2i = tile + normal
				var open := true
				if beside.x >= 0 and beside.y >= 0 and beside.x < map_w and beside.y < map_h:
					var bt := tiles[beside.y * map_w + beside.x]
					open = bt == Tile.EMPTY or bt == Tile.PARK or bt == Tile.POWER_LINE
				if not open:
					continue
				for k in 4:
					var spot := c + Vector2(axis) * (-18.75 + k * 12.5) + Vector2(normal) * (ROAD_HALF_WIDTH + 3.5)
					var parts := _tree_parts(spot, rng.randf_range(7.0, 10.0), false, rng)
					trunk_items.append([parts[0], Color(0.30, 0.22, 0.15)])
					crown_items.append([parts[1], parts[2]])
	_fill(city_trunks.multimesh, trunk_items, false)
	_fill(city_crowns.multimesh, crown_items, false)


# -------------------------------------------------------------- day and night

func set_time_of_day(t: float) -> void:
	# t: 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
	var phase := (t - 0.25) * TAU
	var height := sin(phase)                       # above 0 = sun is up
	var daylight := smoothstep(-0.08, 0.25, height)
	night = 1.0 - smoothstep(-0.12, 0.08, height)

	if height > -0.05:
		# The sun rises in the east, crosses the south and sets in the west.
		var elevation := maxf(height, 0.02) * 42.0
		var yaw := 90.0 - 180.0 * clampf((t - 0.25) / 0.5, 0.0, 1.0)
		sun.rotation_degrees = Vector3(-elevation, yaw, 0.0)
		var warm := Color(1.0, 0.55, 0.30).lerp(Color(1.0, 0.96, 0.90), smoothstep(0.0, 0.4, height))
		sun.light_color = warm
		sun.light_energy = lerpf(0.0, 1.25, smoothstep(-0.05, 0.15, height))
	else:
		# Bright, cool moonlight from high in the south-east, so you can keep
		# building at night (as in most city builders).
		sun.rotation_degrees = Vector3(-50.0, 150.0, 0.0)
		sun.light_color = Color(0.66, 0.76, 1.0)
		sun.light_energy = 0.55

	env.ambient_light_energy = lerpf(0.65, 1.0, daylight)
	env.background_energy_multiplier = lerpf(0.35, 1.0, daylight)
	env.fog_light_color = Color(0.18, 0.23, 0.34).lerp(Color(0.72, 0.78, 0.86), daylight)
	env.tonemap_exposure = lerpf(1.0, 1.35, night)
	# Dimming the sky itself makes Godot redo its lighting, so only do it in steps.
	var sky_energy := lerpf(0.35, 1.0, daylight)
	if absf(sky_energy - _sky_energy) > 0.04 and sky_material:
		_sky_energy = sky_energy
		sky_material.set("energy_multiplier", sky_energy)

	if wall_material:
		wall_material.set_shader_parameter("night", night)
	if road_material:
		road_material.set_shader_parameter("night", night)


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
