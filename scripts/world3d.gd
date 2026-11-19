extends Node3D
## Draws Troon in 3D: terrain from the real heights, the sea, sky and sunlight,
## and the city on top (roads, power lines, buildings).
## It only reads the simulation; it never changes the city.

const Settings = preload("res://scripts/settings.gd")
const Icons = preload("res://scripts/icons.gd")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const SEA_SHADER = preload("res://shaders/sea.gdshader")
const BUILDING_SHADER = preload("res://shaders/building.gdshader")
const ROOF_SHADER = preload("res://shaders/roof.gdshader")
const FOLIAGE_SHADER = preload("res://shaders/foliage.gdshader")
const MODEL_SHADER = preload("res://shaders/model.gdshader")

# Detailed building models (made by tools/make_buildings.py). Where a block of the
# right kind is planned, the model is used instead, stretched to the block's size.
# Each entry: width, depth, wall height, roof rise (metres).
const MODEL_DIR := "res://assets/models/"
const MODEL_DIMS := {
	"villa": Vector4(7.4, 8.0, 5.8, 3.4), "bungalow": Vector4(8.0, 8.0, 3.2, 3.6),
	"terrace": Vector4(15.0, 8.5, 6.2, 3.2), "tenement3": Vector4(22.0, 13.0, 9.9, 4.8),
	"tenement4": Vector4(22.0, 13.0, 12.9, 4.8), "shop1": Vector4(15.5, 13.0, 5.0, 0.0),
	"shop2": Vector4(15.5, 13.0, 7.0, 3.0), "shopflats2": Vector4(23.0, 18.0, 8.0, 0.0),
	"shopflats3": Vector4(23.0, 18.0, 11.1, 0.0), "shopflats4": Vector4(23.0, 18.0, 14.2, 0.0),
	"shed": Vector4(34.0, 28.0, 8.0, 2.2),
	"classical2": Vector4(21.0, 13.0, 9.1, 4.0), "classical3": Vector4(21.0, 13.0, 12.5, 4.0),
	"classical4": Vector4(21.0, 13.0, 15.9, 4.0), "classical5": Vector4(21.0, 13.0, 19.3, 4.0),
	"classical6": Vector4(21.0, 13.0, 22.7, 4.0), "classical7": Vector4(21.0, 13.0, 26.1, 4.0),
	"fire_station": Vector4(34.0, 18.0, 11.5, 0.0), "fire_tower": Vector4(6.0, 6.0, 23.0, 0.0),
	"school": Vector4(38.0, 13.0, 9.0, 4.5), "hospital": Vector4(34.0, 22.0, 20.8, 0.0),
	# Whole sites (power stations) and the remaining landmarks, placed at their built size.
	"coal_plant": Vector4(44.0, 44.0, 66.0, 0.0), "gas_plant": Vector4(44.0, 44.0, 46.0, 0.0),
	"nuclear_plant": Vector4(46.0, 46.0, 47.5, 0.0), "clubhouse": Vector4(18.0, 11.0, 7.3, 0.0),
	"museum_wing": Vector4(12.0, 16.0, 9.0, 0.0), "stand": Vector4(42.0, 6.0, 11.5, 0.0),
	"water_tower": Vector4(16.0, 16.0, 35.8, 0.0),
	# Modern blocks are stacked: a glazed ground floor, upper storeys, then the roof.
	"modern_base": Vector4(21.0, 13.0, 4.6, 0.0), "modern_floor": Vector4(21.0, 13.0, 3.2, 0.0),
	"glass_floor": Vector4(21.0, 13.0, 3.2, 0.0), "modern_top": Vector4(21.0, 13.0, 6.85, 0.0),
	# Skyscraper storeys (stone and deco, concrete grid, bands of flats) and tops.
	"tower_stone": Vector4(21.0, 13.0, 3.2, 0.0), "tower_grid": Vector4(21.0, 13.0, 3.2, 0.0),
	"tower_band": Vector4(21.0, 13.0, 3.2, 0.0), "crown_plant": Vector4(21.0, 13.0, 5.6, 0.0),
	"crown_deco": Vector4(21.0, 13.0, 20.9, 0.0), "crown_spire": Vector4(21.0, 13.0, 33.5, 0.0),
	"crown_slope": Vector4(21.0, 13.0, 10.6, 0.0),
	# More industry: an old works with a sawtooth roof, and a modern warehouse.
	"works": Vector4(34.0, 28.0, 6.0, 3.2), "warehouse": Vector4(40.0, 30.0, 11.75, 0.0),
	# Landmarks (tools/make_buildings.py), placed at their built size.
	"eiffel": Vector4(44.0, 44.0, 139.7, 0.0), "big_ben": Vector4(36.0, 16.0, 98.0, 0.0),
	"empire_state": Vector4(40.0, 28.0, 196.7, 0.0), "liberty": Vector4(34.0, 34.0, 85.6, 0.0),
	"opera_house": Vector4(46.0, 38.0, 24.4, 0.0), "taj_mahal": Vector4(46.0, 46.0, 39.2, 0.0),
	"colosseum": Vector4(46.0, 38.0, 19.6, 0.0), "great_pyramid": Vector4(46.0, 46.0, 29.8, 0.0),
}
# Other designs with the same size as a model above; one is picked for each building.
const MODEL_VARIANTS := {
	"villa": ["villa", "villa_b", "villa_c"], "bungalow": ["bungalow", "bungalow_b"],
	"terrace": ["terrace", "terrace_b"], "tenement3": ["tenement3", "tenement3_b"],
	"tenement4": ["tenement4", "tenement4_b"], "shop1": ["shop1", "shop1_b"], "shop2": ["shop2", "shop2_b"],
	"modern_floor": ["modern_floor", "modern_floor_b"],
}
const MODEL_PARTS := ["stone", "roof", "glass", "frame", "door", "metal", "pot", "fascia", "render",
	"awning", "lead", "cladding", "sheet", "accent", "curtain", "display", "beacon", "lamp", "office", "green"]
const MODEL_CHUNK := 400.0              # models are drawn in 400 m squares (for culling and detail levels)
const ROAD_SHADER = preload("res://shaders/road.gdshader")
const PAVING_SHADER = preload("res://shaders/paving.gdshader")

enum Tile { EMPTY, ROAD, HOMES, SHOPS, INDUSTRY, POWER_PLANT, POWER_LINE, PARK,
	POLICE, FIRE, SCHOOL, HOSPITAL,
	WIND, SOLAR, GAS, NUCLEAR, WATER_PUMP, WATER_TOWER, LANDFILL, RECYCLING,
	GOLF, LIBRARY, MUSEUM, STADIUM, MARINA, TOWN_HALL, BUS_DEPOT, STATION, HARBOUR,
	WOODLAND, OFFICES, POLICE_OFFICE, FIRE_SMALL, CLINIC, AIRPORT,
	BIG_BEN, COLOSSEUM, GREAT_PYRAMID, LIBERTY, TAJ_MAHAL, OPERA_HOUSE, EIFFEL, EMPIRE_STATE,
	INCINERATOR, DATA_CENTRE, GIGAFACTORY, TECH_CAMPUS, LAUNCH_SITE, AI_DATA_CENTRE }   # same order as simulation.gd

const PADDING := 40            # tiles of scenery drawn beyond each map edge
const ROAD_HALF_WIDTH := 6.0   # metres (tarmac plus pavements)
# By kind of road (sim.road_kind): road, avenue (two lanes each way, trees down the
# middle), motorway (three lanes each way and hard shoulders). road.gdshader
# paints each kind's lanes from the same widths.
const ROAD_HALF_WIDTHS: Array[float] = [6.0, 10.0, 14.0]
const ROAD_LAMP_OFFSETS: Array[float] = [5.4, 9.4, 0.0]   # lamp posts, metres from the middle
const ROAD_ARM_END := 19.0     # metres along a junction's arm where it meets the open square (the give-way line)
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
	Tile.OFFICES: Color(0.10, 0.72, 0.68),
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
const DC_CLADDING := Color(0.60, 0.64, 0.68)   # a data centre's blue-grey cladding
const DC_ROOF := Color(0.46, 0.48, 0.50)
const DC_CHILLER := Color(0.34, 0.37, 0.40)    # the cooling units on its roof
const PAVEMENT := Color(0.66, 0.65, 0.62)
const DRIVEWAY := Color(0.58, 0.56, 0.53)
const COURT := Color(0.55, 0.54, 0.50)
const CAR_PARK := Color(0.30, 0.30, 0.31)
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
const STYLE_PAINT := 9         # plain painted panels: doors, signs (no windows, no stone)
const POLICE_BLUE := Color(0.10, 0.20, 0.50)
const FIRE_RED := Color(0.72, 0.08, 0.06)
const CROSS_RED := Color(0.82, 0.06, 0.06)
const AMBULANCE_YELLOW := Color(0.92, 0.84, 0.16)
const PATROL_WHITE := Color(0.95, 0.95, 0.95)
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
var lot_image: Image                  # per map tile: what the terrain shader paints on the plot (see _plan_lots)
var lot_texture: ImageTexture
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
var _models := {}                     # model name -> Mesh (with our materials)
var _model_materials: Array[ShaderMaterial] = []
var _model_items: Array = []          # [name, transform, colour, custom, owner] planned this refresh
var _model_nodes := {}                # "name|x|y" -> MultiMeshInstance3D
var _model_groups := {}               # "name|x|y" -> {owners, base} for overlay recolouring
var _current_owner := -1              # the plot being planned
var _spire_items: Array = []          # skyscraper spires, drawn with the chimneys
var _extra_trees: Array = []          # [position (Vector2), height, kind] planted on plots
# Leftover open land inside the town gets put to use (looks only, not simulated):
var _infill := PackedByteArray()      # 0 = none, 1 = pocket park, 2 = allotments, 3 = car park
const INFILL_PARK := 1
const INFILL_ALLOTMENTS := 2
const INFILL_CAR_PARK := 3

# The ground of every plot is painted by the terrain shader (shaders/lots.gdshaderinc)
# from lot_image, one pixel per tile, worked out in _plan_lots:
#   R = kind (LOT_...)
#   G = bits 0-1 the side facing the street (0 = +y, 1 = -y, 2 = +x, 3 = -x, as
#       _frontage), bits 3-7 a detail (building stage; park layout)
#   B = bits 0-3 which neighbours are the same kind (+x, -x, +y, -y); on empty
#       zoned plots bits 4-5 the zone (1 homes, 2 shops, 3 industry, 0 offices), bits 6-7 density
#   A = bit 0 abandoned, bit 1 in the CBD, bits 4-7 the sides whose road verge the
#       plot reaches into (+x, -x, +y, -y; see _street_reach)
# Keep the kinds and layouts in step with the shader.
const LOT_NONE := 0
const LOT_ROAD := 1          # its verges belong to the plots beside it
const LOT_VILLAS := 2
const LOT_TERRACES := 3
const LOT_TENEMENTS := 4
const LOT_COURT := 5         # tall homes round a landscaped court
const LOT_SHOPS := 6
const LOT_PLAZA := 7         # offices and skyscrapers: paved all over
const LOT_INDUSTRY := 8
const LOT_EMPTY := 9         # zoned, nothing happening yet
const LOT_SITE := 10         # zoned and being built on
const LOT_PARK := 11
const LOT_ALLOTMENTS := 12
const LOT_CAR_PARK := 13
const LOT_CIVIC := 14        # paved forecourts: town hall, library, museum, police, station
const LOT_SCHOOL := 15
const LOT_GOLF := 16
const LOT_YARD := 17         # concrete and gravel: fire station, depots, utilities, power stations
const LOT_HOSPITAL := 18
const LOT_MEADOW := 19       # rough grass under wind turbines and solar panels
const LOT_AIRPORT := 21      # runway, taxiway, apron or grass: the detail is sim.airport_role
const LOT_WOODS := 20        # planted woodland: the terrain paints its floor; a road's verge beside it is woods floor too
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
var _lot_kind := PackedByteArray()
var _lot_detail := PackedByteArray()
const HOARDING := Color(0.86, 0.87, 0.84)
const FOUNDATION := Color(0.48, 0.47, 0.45)
const SITE_CABIN := Color(0.20, 0.36, 0.62)
const CRANE_YELLOW := Color(0.95, 0.74, 0.10)
const SOIL := Color(0.32, 0.23, 0.16)
const BRICK := Color(0.58, 0.30, 0.22)
const SCAFFOLD := Color(0.62, 0.64, 0.66)
const SCAFFOLD_BOARD := Color(0.62, 0.50, 0.34)
const SAND_PILE := Color(0.78, 0.68, 0.48)
const CROPS := Color(0.30, 0.48, 0.20)
var preview := MultiMeshInstance3D.new()   # tiles a drag will build on
var hover_box := MeshInstance3D.new()
var hover_material := StandardMaterial3D.new()
var alerts := Node3D.new()            # floating warning icons above plots
var _alert_items: Array = []          # [sprite, ground point]; reused between refreshes
var _alert_count := 0                 # how many of them are showing
var _alert_size := 30.0
# Smoke drifting from coal plant chimneys (looks only; a handful of particle streams).
const MAX_SMOKE := 24
var smoke := Node3D.new()
var _smoke_points: Array[Vector3] = []          # chimney tops, gathered while planning buildings
var _smoke_items: Array[CPUParticles3D] = []    # reused between refreshes
var _smoke_mesh := QuadMesh.new()
var _power_icon: Texture2D
var _water_icon: Texture2D
var _road_icon: Texture2D

const WATER_ICON_SVG := "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='96'><circle cx='48' cy='48' r='42' fill='#3d8bff' stroke='#16181c' stroke-width='7'/><path d='M48 16 C40 32 28 44 28 58 A20 20 0 0 0 68 58 C68 44 56 32 48 16 Z' fill='white'/></svg>"
const POWER_ICON_SVG := "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='96'><circle cx='48' cy='48' r='42' fill='#ffd21f' stroke='#16181c' stroke-width='7'/><path d='M54 14 L26 54 H45 L39 84 L70 40 H51 Z' fill='#16181c'/></svg>"
const ROAD_ICON_SVG := "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='96'><circle cx='48' cy='48' r='42' fill='#e5484d' stroke='#16181c' stroke-width='7'/><rect x='22' y='41' width='52' height='14' rx='3' fill='white'/></svg>"
var sun := DirectionalLight3D.new()
var env: Environment
var sky_material: Material
var wall_material: ShaderMaterial
var night := 0.0                       # 0 = full day, 1 = full night
var _sky_energy := 1.0

# Trees: natural woods on open land (hidden where you build), plus park and garden trees.
var woods := Node3D.new()                      # natural trees, in squares (TREE_CHUNK_TILES)
var _wood_meshes: Array[Mesh] = []             # trunk, canopy blob, cone
var _wood_mms: Array[MultiMesh] = []           # per square: trunks, canopies, cones
var _wood_nodes: Array[MultiMeshInstance3D] = []
var _tree_range := 0.0                         # how far away the woods are drawn
var city_trunks := MultiMeshInstance3D.new()
var city_crowns := MultiMeshInstance3D.new()
var city_cones := MultiMeshInstance3D.new()
# Natural trees are built once; building on a tile hides its trees. Each tree is
# a trunk plus a few canopy pieces ("parts"), remembered so they can be hidden.
var _part_xf: Array[Transform3D] = []
var _part_mesh := PackedInt32Array()           # which MultiMesh in _wood_mms
var _part_index := PackedInt32Array()          # instance number in that MultiMesh
var _parts_in_tile := {}                       # tile index -> Array of part numbers
enum TreeKind { BROADLEAF, BIRCH, COLUMNAR, PINE, SPRUCE, ORNAMENTAL, COPPER, GARDEN, GORSE }
const GORSE_ALPHA := 0.5                       # canopy colour alpha that tells the foliage shader "gorse"
const BARK := Color(0.30, 0.22, 0.15)
const BIRCH_BARK := Color(0.80, 0.78, 0.72)
const PINE_BARK := Color(0.45, 0.28, 0.17)
var _tile_has_trees := PackedByteArray()       # 1 = that tile's trees are showing
var _clumps: FastNoiseLite                     # glades and thickets inside woods (natural and planted)
var _wood_per_row := 1                         # woods squares across the padded map
var _wood_bark: Material
var _wood_leaves: Material
var _natural_tree_parts := 0                   # instances in the natural woods (for the dev tools)
# Planted woodland: drawn like the natural woods, in the same squares, filled
# again only where woodland (or the woods round it) changed.
var _forest := PackedByteArray()               # per map tile: 0 open, 1 woodland, 2 untouched natural woods, 3 road or power line
var _natural_woods := PackedByteArray()        # per map tile: 1 = thick natural woods (land map)
var _planted_nodes := {}                       # woods square -> [trunks, canopies, cones] MultiMeshInstance3D
var _planted_parts := {}                       # woods square -> instances in it
var planted_refresh_ms := 0.0                  # how long the last change to the planted woods took (dev tools)
# --- Map overlays (land value, power, roads, growth...) ---
# (New views go on the end; hud.gd's OVERLAY_NAMES / OVERLAY_TIPS / OVERLAY_ICONS follow this order.)
enum Overlay { NONE, LAND_VALUE, POWER, ROADS, GROWTH, SERVICES, WATER, DISTRICTS, POLLUTION, TRAFFIC }
enum Growth { NONE, GROWING, WAITING, BLOCKED, FULL, ABANDONED }   # same order as simulation.gd
const OV_RED := Color(0.88, 0.24, 0.18)
const OV_ORANGE := Color(0.96, 0.52, 0.18)
const OV_YELLOW := Color(0.97, 0.80, 0.22)
const OV_LIGHT_GREEN := Color(0.58, 0.84, 0.32)
const OV_GREEN := Color(0.18, 0.70, 0.30)
const OV_BLUE := Color(0.30, 0.56, 0.95)
const OV_GREY := Color(0.55, 0.56, 0.58)
const OV_DARK_YELLOW := Color(0.62, 0.52, 0.16)
const OV_DARK_BLUE := Color(0.16, 0.30, 0.58)
const OV_CBD := Color(0.62, 0.38, 0.92)
const OV_CONSERVATION := Color(0.80, 0.56, 0.28)
const OV_TECH := Color(0.16, 0.76, 0.78)
const OV_ABANDONED := Color(0.45, 0.30, 0.24)
# Traffic view: quiet, free-flowing, busy, heavy, jammed (simulation.gd traffic_band, plus traffic_quiet).
const OV_QUIET := Color(0.42, 0.58, 0.46)
const TRAFFIC_COLOURS: Array[Color] = [OV_QUIET, OV_GREEN, OV_YELLOW, OV_ORANGE, OV_RED]
const TRAFFIC_GROUND_ALPHA: Array[float] = [0.3, 0.45, 0.65, 0.8, 0.92]   # the road tile's ground round the road
# Abandoned buildings: their instance colour's alpha is set to this, and the
# building, roof and model shaders draw them run down (alpha below 0.75).
const ABANDONED_ALPHA := 0.5
var overlay: int = Overlay.NONE
# The Services view on its own: -1 = all four (how many cover each spot), or one
# service (simulation.gd Service: police, fire, school, hospital): where it reaches,
# the plots that want it and don't have it, and its buildings with a pin.
var service_filter := -1
var service_pins := Node3D.new()
var _pin_items: Array = []                # [Sprite3D, ground point]
var _pin_count := 0
var _pin_textures := {}                   # service -> Texture2D
var reach_decal: Decal                    # where a service building would reach, under the mouse
# Map views are lit like early afternoon whatever the clock says, so their
# colours read true at night too (no dark ground, lit windows or street lamps).
const MAP_VIEW_TIME := 0.55
var clock_night := 0.0                    # night at the clock's real time (`night` is 0 in map views)
var _clock_time := 0.5
var overlay_image: Image
var overlay_texture: ImageTexture
var roof_material: ShaderMaterial
var _wall_owner := PackedInt32Array()     # which plot each wall belongs to
var _wall_base := PackedColorArray()      # each wall's own colour
var _roof_owner := PackedInt32Array()
var _roof_base := PackedColorArray()
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
	_build_terrain(ground)
	_build_sea()
	_infill.resize(map_w * map_h)
	_build_city_nodes()
	_build_trees()
	_build_preview()
	refresh_all()


# --- Light, colour and air (the "look"), aiming for SimCity 4: crisp, sunny,
# strong shadows, rich but natural colour, a properly dark night. ---
const LOOK_WHITE := 6.0                 # tone mapping: brightness that turns pure white
const LOOK_EXPOSURE_DAY := 0.6
const LOOK_EXPOSURE_NIGHT := 1.25
const LOOK_CONTRAST := 1.12             # colour grade on top of the tone mapping
const LOOK_SATURATION := 1.0
const SUN_ENERGY := 2.0                 # the warm key light
const SUN_DAY_COLOUR := Color(1.0, 0.94, 0.84)
const SUN_LOW_COLOUR := Color(1.0, 0.52, 0.26)   # at sunrise and sunset
const SUN_MAX_ELEVATION := 46.0         # degrees, at noon
const AMBIENT_DAY := 0.38               # cool fill from the sky (lower = deeper shadows)
const AMBIENT_NIGHT := 0.85              # night: lifted so roads, roofs and the coast still read
const MOON_ENERGY := 0.45
const MOON_COLOUR := Color(0.48, 0.60, 1.0)
const MOON_ANGLE := Vector3(-50.0, 150.0, 0.0)
const SUN_FOLLOWS_VIEW := true          # light from a fixed side of the screen (see _view_yaw)
const SUN_VIEW_ANGLE := -70.0           # degrees round from behind the camera (minus = from the left)
const MOON_VIEW_ANGLE := -35.0
const SKY_ENERGY_NIGHT := 0.3
const SHADOW_REACH := 3.4               # shadows drawn out to this many camera distances
const SHADOW_SPLITS := Vector3(0.06, 0.18, 0.45)   # where the 4 shadow cascades end
const SSAO_RADIUS := 5.0                # metres: contact shading where walls meet the ground
const SSAO_INTENSITY := 2.4
const SSAO_POWER := 1.6
const SSAO_LIGHT_AFFECT := 0.25         # also darkens sunlit corners a little
const HAZE_START := 1.6                 # camera distances before the haze begins...
const HAZE_END := 9.0                   # ...and where it is thickest
const HAZE_MAX := 0.55                  # how thick the far haze gets (0-1)
const HAZE_DAY := Color(0.70, 0.78, 0.90)
const HAZE_DUSK := Color(0.95, 0.62, 0.42)
const HAZE_NIGHT := Color(0.06, 0.09, 0.17)
const GLOW_THRESHOLD := 1.1             # only lit windows and lamps bloom
const GLOW_DAY := 0.15
const GLOW_NIGHT := 1.0
var _view_distance := 1400.0


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
	# ACES tone mapping: punchier and more saturated than AgX, which looked milky.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = LOOK_WHITE
	env.tonemap_exposure = LOOK_EXPOSURE_DAY
	env.ambient_light_energy = AMBIENT_DAY
	# Contact shading, so buildings sit on the ground instead of floating.
	env.ssao_enabled = true
	env.ssao_radius = SSAO_RADIUS
	env.ssao_intensity = SSAO_INTENSITY
	env.ssao_power = SSAO_POWER
	env.ssao_light_affect = SSAO_LIGHT_AFFECT
	# Glow only from things brighter than white: lit windows and street lamps.
	env.glow_enabled = true
	env.glow_intensity = GLOW_DAY
	env.glow_hdr_threshold = GLOW_THRESHOLD
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_scale = 1.6
	for level: int in 7:
		env.set_glow_level(level, 1.0 if level >= 1 and level <= 4 else 0.0)   # tight halo plus a soft one
	# Colour grading: a little extra contrast and colour.
	env.adjustment_enabled = true
	env.adjustment_saturation = LOOK_SATURATION
	env.adjustment_contrast = LOOK_CONTRAST
	# Haze only far away (it starts a couple of camera distances out, see
	# set_view_distance), taking the sky's colour: aerial perspective.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = HAZE_DAY
	env.fog_density = HAZE_MAX
	env.fog_depth_curve = 1.6
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Afternoon sun from the south-west, over the Firth of Clyde (set_time_of_day moves it).
	sun.rotation_degrees = Vector3(-38.0, 215.0, 0.0)
	sun.light_energy = SUN_ENERGY
	sun.light_color = SUN_DAY_COLOUR
	sun.shadow_enabled = true
	sun.shadow_blur = 0.4
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = SHADOW_SPLITS.x
	sun.directional_shadow_split_2 = SHADOW_SPLITS.y
	sun.directional_shadow_split_3 = SHADOW_SPLITS.z
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_max_distance = 1800.0
	add_child(sun)
	env.fog_depth_begin = _view_distance * HAZE_START
	env.fog_depth_end = _view_distance * HAZE_END


# --- The ground. Heights are drawn from a smooth field four times finer than the
# tiles, so the coast is a natural curve instead of 50 m steps. Gameplay is still
# tile by tile: the middle of every land tile stays dry and the middle of every
# sea tile stays wet, and height_at() reads the very same field the terrain is
# drawn from, so buildings, roads and trees sit exactly on it. ---
const TERRAIN_SUB := 4                  # height samples per tile each way (12.5 m apart)
const TERRAIN_CHUNK := 64               # samples along one side of a terrain piece (800 m)
const SHORE_LEVEL := 0.36               # where the smoothed land mask (0 = sea, 1 = land) meets the water
const LAND_MARGIN := 0.14               # land tile middles stay at least this far above the shore level...
const SEA_MARGIN := 0.08                # ...and sea tile middles this far below it
const BEACH_RISE := 0.32                # mask units from the waterline up to the full land height
const SEABED_FALL := 0.3                # mask units from the waterline down to the full sea depth
const SEA_SHELF := 1.0                  # metres of water just off the beach
const SEA_SLOPE := 1.5                  # the seabed gets this much deeper per tile out to sea
const SEA_DEEP := 18.0                  # the deepest seabed drawn
const LAND_MIN := 0.6                   # the lowest land, in metres above the sea
const COAST_WIDE_TILES := 3             # "near the sea" (dunes, salt-bitten grass) reaches about this far inland
var _fine := PackedFloat32Array()       # ground height at every sample
var _fine_coast := PackedFloat32Array() # smoothed land mask at every sample
var _fine_w := 0
var _fine_h := 0
var _fine_origin := Vector2.ZERO        # world position (x, z) of sample (0, 0)
var _fine_step := 12.5
var _land_info := PackedFloat32Array()  # per padded tile, 4 values: damp, woods, near the sea, spare
var height_map_texture: ImageTexture    # R = height, G = land mask (the terrain shader's vertices)
var land_map_image: Image               # per padded tile: R = damp hollows, G = woods, B = near the sea
var land_map_texture: ImageTexture
var built_image: Image                  # per map tile: R = built on (so fields and wild ground give way)
var built_texture: ImageTexture
var _noise_tex: ImageTexture            # four smooth noises (terrain, paving)
var terrain_root := Node3D.new()
var sea_material: ShaderMaterial


func _build_terrain(ground: PackedFloat32Array) -> void:
	_build_height_field(ground)
	var gw := map_w + PADDING * 2
	var gh := map_h + PADDING * 2

	lot_image = Image.create_empty(map_w, map_h, false, Image.FORMAT_RGBA8)
	lot_texture = ImageTexture.create_from_image(lot_image)
	warn_image = Image.create_empty(map_w, map_h, false, Image.FORMAT_RGBA8)
	warn_texture = ImageTexture.create_from_image(warn_image)
	overlay_image = Image.create_empty(map_w, map_h, false, Image.FORMAT_RGBA8)
	overlay_texture = ImageTexture.create_from_image(overlay_image)

	terrain_material = ShaderMaterial.new()
	terrain_material.shader = TERRAIN_SHADER
	terrain_material.set_shader_parameter("map_size", Vector2(map_w, map_h) * cell)
	terrain_material.set_shader_parameter("lot_map", lot_texture)
	terrain_material.set_shader_parameter("tile_metres", cell)
	terrain_material.set_shader_parameter("street_reach", cell * 0.5 - ROAD_HALF_WIDTH - 1.0)
	terrain_material.set_shader_parameter("zone_homes", ZONE_TINTS[Tile.HOMES])
	terrain_material.set_shader_parameter("zone_shops", ZONE_TINTS[Tile.SHOPS])
	terrain_material.set_shader_parameter("zone_industry", ZONE_TINTS[Tile.INDUSTRY])
	terrain_material.set_shader_parameter("zone_offices", ZONE_TINTS[Tile.OFFICES])
	terrain_material.set_shader_parameter("warn_map", warn_texture)
	terrain_material.set_shader_parameter("overlay_map", overlay_texture)
	var grass := _optional_texture("grass")
	var sand := _optional_texture("sand")
	var rock := _optional_texture("rock")
	if grass and sand and rock:
		terrain_material.set_shader_parameter("use_textures", true)
		terrain_material.set_shader_parameter("grass_average", _average_colour(grass))
		terrain_material.set_shader_parameter("grass_tex", grass)
		terrain_material.set_shader_parameter("sand_tex", sand)
		terrain_material.set_shader_parameter("rock_tex", rock)
		terrain_material.set_shader_parameter("sand_average", _average_colour(sand))
		terrain_material.set_shader_parameter("rock_average", _average_colour(rock))
	terrain_material.set_shader_parameter("height_map", height_map_texture)
	terrain_material.set_shader_parameter("grid_origin", _fine_origin)
	terrain_material.set_shader_parameter("grid_step", _fine_step)
	terrain_material.set_shader_parameter("grid_size", Vector2i(_fine_w, _fine_h))
	terrain_material.set_shader_parameter("shore_level", SHORE_LEVEL)
	terrain_material.set_shader_parameter("land_map", land_map_texture)
	terrain_material.set_shader_parameter("land_origin", Vector2(-PADDING, -PADDING) * cell)
	terrain_material.set_shader_parameter("land_size", Vector2(gw, gh) * cell)
	built_image = Image.create_empty(map_w, map_h, false, Image.FORMAT_RG8)
	built_texture = ImageTexture.create_from_image(built_image)
	terrain_material.set_shader_parameter("built_map", built_texture)
	_noise_tex = _noise_texture()
	terrain_material.set_shader_parameter("noise_tex", _noise_tex)
	_set_field_uniforms(terrain_material)

	# The ground is drawn as square pieces sharing one flat grid mesh; the shader
	# lifts each corner to its height, so building it is quick and pieces off
	# screen are skipped.
	add_child(terrain_root)
	var grid := _grid_mesh(TERRAIN_CHUNK, _fine_step)
	var span := TERRAIN_CHUNK * _fine_step
	var across := ceili(float(_fine_w - 1) / TERRAIN_CHUNK)
	var down := ceili(float(_fine_h - 1) / TERRAIN_CHUNK)
	for cz in down:
		for cx in across:
			var lo := INF
			var hi := -INF
			for k in range(cz * TERRAIN_CHUNK, mini((cz + 1) * TERRAIN_CHUNK + 1, _fine_h)):
				for j in range(cx * TERRAIN_CHUNK, mini((cx + 1) * TERRAIN_CHUNK + 1, _fine_w)):
					var h: float = _fine[k * _fine_w + j]
					lo = minf(lo, h)
					hi = maxf(hi, h)
			var piece := MeshInstance3D.new()
			piece.mesh = grid
			piece.material_override = terrain_material
			piece.position = Vector3(_fine_origin.x + cx * span, 0.0, _fine_origin.y + cz * span)
			piece.custom_aabb = AABB(Vector3(0.0, lo - 2.0, 0.0), Vector3(span, hi - lo + 4.0, span))
			terrain_root.add_child(piece)
	_build_far_land()


func _build_height_field(ground: PackedFloat32Array) -> void:
	# Works on the tiles plus the scenery beyond the map edge (the padding), then
	# smooths up to the fine samples. Beyond the edge the coastline carries
	# straight on and the hills are mirrored, so the land looks like it goes on.
	var gw := map_w + PADDING * 2
	var gh := map_h + PADDING * 2
	var n := gw * gh
	var land := PackedFloat32Array()       # 1 = land, 0 = sea
	var lift := PackedFloat32Array()       # land height (carried a little out over the sea)
	land.resize(n)
	lift.resize(n)
	for gz in gh:
		for gx in gw:
			var tx := clampi(gx - PADDING, 0, map_w - 1)
			var tz := clampi(gz - PADDING, 0, map_h - 1)
			var g := gz * gw + gx
			land[g] = 0.0 if water[tz * map_w + tx] == 1 else 1.0
			var mx := _mirror(gx - PADDING, map_w)
			var mz := _mirror(gz - PADDING, map_h)
			lift[g] = maxf(ground[mz * map_w + mx], LAND_MIN)
	# Over the sea, the land height of the nearest shore (so beaches aren't dragged down).
	var known := land.duplicate()
	for _pass in 3:
		var next := known.duplicate()
		for gz in gh:
			for gx in gw:
				var g := gz * gw + gx
				if known[g] > 0.5:
					continue
				var total := 0.0
				var count := 0
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var x := gx + dx
						var z := gz + dz
						if x < 0 or z < 0 or x >= gw or z >= gh or known[z * gw + x] < 0.5:
							continue
						total += lift[z * gw + x]
						count += 1
				if count > 0:
					lift[g] = total / count
					next[g] = 1.0
		known = next
	for g in n:
		if known[g] < 0.5:
			lift[g] = LAND_MIN
	# Sea depth: shallow by the shore, deeper further out.
	var reach := _distance_to(land, gw, gh, 1.0)
	var deep := PackedFloat32Array()
	deep.resize(n)
	for g in n:
		deep[g] = minf(SEA_SHELF + maxf(reach[g] - 1.0, 0.0) * SEA_SLOPE, SEA_DEEP)

	var mask := _upsample(_blur3(land, gw, gh), gw, gh)
	var heights_up := _upsample(lift, gw, gh)
	var depth_up := _upsample(_blur3(deep, gw, gh), gw, gh)
	_fine_w = gw * TERRAIN_SUB
	_fine_h = gh * TERRAIN_SUB
	_fine_step = cell / TERRAIN_SUB
	# Image.resize puts sample j at tile (j + 0.5) / SUB - 0.5 (counting padded tiles).
	var first := (0.5 / TERRAIN_SUB - 0.5 - PADDING + 0.5) * cell
	_fine_origin = Vector2(first, first)

	# Keep each tile's middle on the right side of the waterline: where smoothing
	# has drowned a land tile's middle (or dried a sea tile's), push the mask
	# back with a round bump, so the fix looks like a little headland or pool.
	var half := TERRAIN_SUB / 2
	for gz in gh:
		for gx in gw:
			var is_land := land[gz * gw + gx] > 0.5
			var target := SHORE_LEVEL + LAND_MARGIN if is_land else SHORE_LEVEL - SEA_MARGIN
			var j0 := gx * TERRAIN_SUB + half - 1
			var k0 := gz * TERRAIN_SUB + half - 1
			var worst := 0.0
			for k: int in [k0, k0 + 1]:
				for j: int in [j0, j0 + 1]:
					var m: float = mask[k * _fine_w + j]
					worst = maxf(worst, target - m) if is_land else minf(worst, target - m)
			if worst == 0.0:
				continue
			for k in range(maxi(k0 - 2, 0), mini(k0 + 4, _fine_h)):
				for j in range(maxi(j0 - 2, 0), mini(j0 + 4, _fine_w)):
					var r := Vector2(j - j0 - 0.5, k - k0 - 0.5).length() / TERRAIN_SUB   # tiles from the middle
					var s := k * _fine_w + j
					var bumped: float = mask[s] + worst * (1.0 - smoothstep(0.2, 0.62, r))
					mask[s] = maxf(mask[s], bumped) if is_land else minf(mask[s], bumped)

	var count_fine := _fine_w * _fine_h
	_fine.resize(count_fine)
	_fine_coast.resize(count_fine)
	var packed := PackedFloat32Array()
	packed.resize(count_fine * 2)
	for s in count_fine:
		var m := clampf(mask[s], 0.0, 1.0)
		var h := 0.0
		if m >= SHORE_LEVEL:
			var t := minf((m - SHORE_LEVEL) / BEACH_RISE, 1.0)
			h = maxf(heights_up[s], LAND_MIN) * (1.0 - (1.0 - t) * (1.0 - t))
		else:
			var t := minf((SHORE_LEVEL - m) / SEABED_FALL, 1.0)
			h = -maxf(depth_up[s], SEA_SHELF) * (1.0 - (1.0 - t) * (1.0 - t))
		_fine[s] = h
		_fine_coast[s] = m
		packed[s * 2] = h
		packed[s * 2 + 1] = m
	var img := Image.create_from_data(_fine_w, _fine_h, false, Image.FORMAT_RGF, packed.to_byte_array())
	height_map_texture = ImageTexture.create_from_image(img)

	# Ground character per padded tile, for the shader and the woods.
	var smooth := _blur3(_blur3(lift, gw, gh), gw, gh)
	var wide := land
	for _pass in COAST_WIDE_TILES:
		wide = _blur3(wide, gw, gh)
	_land_info.resize(n * 4)
	land_map_image = Image.create_empty(gw, gh, false, Image.FORMAT_RGBA8)
	for gz in gh:
		for gx in gw:
			var g := gz * gw + gx
			var damp := clampf((smooth[g] - lift[g]) * 0.6, 0.0, 1.0) * land[g]
			var seaward := clampf((1.0 - wide[g]) * 2.2, 0.0, 1.0) * land[g] if reach[g] < 0.5 else 1.0
			_land_info[g * 4] = damp
			_land_info[g * 4 + 2] = seaward
	_plan_woods(gw, gh, lift, land)
	for gz in gh:
		for gx in gw:
			var g := gz * gw + gx
			land_map_image.set_pixel(gx, gz, Color(_land_info[g * 4], _land_info[g * 4 + 1],
				_land_info[g * 4 + 2], _land_info[g * 4 + 3]))
	land_map_texture = ImageTexture.create_from_image(land_map_image)


func _noise_texture() -> ImageTexture:
	# Four smooth, tiling noises in one texture (R, G, B, A) for the ground's
	# natural variation. The shader samples it at several scales.
	const SIZE := 256
	var layers: Array[PackedByteArray] = []
	for k in 4:
		var noise := FastNoiseLite.new()
		noise.seed = 4100 + k * 37
		noise.frequency = 0.012 + k * 0.004
		noise.fractal_octaves = 4
		var layer := noise.get_seamless_image(SIZE, SIZE)
		layer.convert(Image.FORMAT_L8)
		layers.append(layer.get_data())
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * 4)
	for i in SIZE * SIZE:
		for k in 4:
			data[i * 4 + k] = layers[k][i]
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- Open country: a patchwork of fields with hedges, a few conifer plantations
# on the hills, and natural woods. The shader draws the fields; the same sums
# here plant the hedgerow trees and plantations, so they line up. ---
const FIELD_ANGLE := 0.38               # radians the field pattern is turned
const FIELD_ROW := 165.0                # metres between the long field boundaries
const FIELD_COL := 225.0                # average field length
const FIELD_JITTER := 0.55              # how unevenly the fields are cut (share of a length)
const FIELD_WOBBLE := 9.0               # metres the boundaries meander
const FIELD_SPLIT := 0.35               # chance a field is cut in two
const FIELD_HEDGE := 0.72               # chance a boundary is a hedge (otherwise a fence)
const PLANT_CHANCE := 0.06              # chance a field on high ground is a conifer plantation
const PLANT_MIN_HEIGHT := 35.0          # metres
const FARM_MAX_HEIGHT := 105.0          # rough grazing above this
const HEDGE_TREE_GAP := 34.0            # average metres between trees in a hedge
const WOOD_TREES := 9                   # trees per tile in the thickest woods
const PLANT_TREES := 16                 # trees per tile in a plantation
const TREE_CHUNK_TILES := 20            # woods are drawn in squares this many tiles across
const TREE_RANGE := 3.0                 # woods drawn out to this many camera distances...
const TREE_RANGE_MIN := 3200.0          # ...and at least this far (metres)


func _set_field_uniforms(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("field_angle", FIELD_ANGLE)
	mat.set_shader_parameter("field_row", FIELD_ROW)
	mat.set_shader_parameter("field_col", FIELD_COL)
	mat.set_shader_parameter("field_jitter", FIELD_JITTER)
	mat.set_shader_parameter("field_wobble", FIELD_WOBBLE)
	mat.set_shader_parameter("field_split", FIELD_SPLIT)
	mat.set_shader_parameter("field_hedge", FIELD_HEDGE)
	mat.set_shader_parameter("plant_chance", PLANT_CHANCE)
	mat.set_shader_parameter("plant_min_height", PLANT_MIN_HEIGHT)
	mat.set_shader_parameter("farm_max_height", FARM_MAX_HEIGHT)


func _field_rand(x: int, y: int, salt: int) -> float:
	# The shader's integer hash (terrain.gdshader frand), in 32-bit sums.
	var h := ((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 0xFFFFFFFF
	h ^= h >> 13
	h = (h * 1274126177) & 0xFFFFFFFF
	h ^= h >> 16
	return float(h & 0xFFFF) / 65535.0


func _row_line(r: int, u: float) -> float:
	return r * FIELD_ROW + FIELD_WOBBLE * sin(u / 310.0 + TAU * _field_rand(r, 0, 1))


func _col_line(c: int, r: int, v: float) -> float:
	return (c + FIELD_JITTER * (_field_rand(c, r, 2) - 0.5) + _field_rand(r, 0, 3)) * FIELD_COL \
		+ FIELD_WOBBLE * sin(v / 270.0 + TAU * _field_rand(c, r, 4))


func _field_at(p: Vector2) -> Dictionary:
	# Which field a point is in (as the shader's field_at): its id, the field's
	# middle, and how far the point is from the nearest hedge.
	var ca := cos(FIELD_ANGLE)
	var sa := sin(FIELD_ANGLE)
	var u := p.x * ca + p.y * sa
	var v := -p.x * sa + p.y * ca
	var r := floori(v / FIELD_ROW)
	if v < _row_line(r, u):
		r -= 1
	elif v >= _row_line(r + 1, u):
		r += 1
	var v0 := _row_line(r, u)
	var v1 := _row_line(r + 1, u)
	var c := floori(u / FIELD_COL - _field_rand(r, 0, 3))
	if u < _col_line(c, r, v):
		c -= 1
	elif u >= _col_line(c + 1, r, v):
		c += 1
	var u0 := _col_line(c, r, v)
	var u1 := _col_line(c + 1, r, v)
	var sub := 0
	var vs := -1e6
	var split := _field_rand(c, r, 5) < FIELD_SPLIT
	if split:
		vs = lerpf(v0, v1, 0.35 + 0.3 * _field_rand(c, r, 6))
		sub = 1 if v > vs else 0
	var lo := vs if sub == 1 else v0
	var hi := vs if (split and sub == 0) else v1
	var hedge := 1e5
	var seg := floori(u / 90.0)
	if _field_rand(seg, r, 7) < FIELD_HEDGE:
		hedge = minf(hedge, v - v0)
	if _field_rand(seg, r + 1, 7) < FIELD_HEDGE:
		hedge = minf(hedge, v1 - v)
	if _field_rand(c, r, 8) < FIELD_HEDGE:
		hedge = minf(hedge, u - u0)
	if _field_rand(c + 1, r, 8) < FIELD_HEDGE:
		hedge = minf(hedge, u1 - u)
	if split and _field_rand(c, r, 9) < FIELD_HEDGE:
		hedge = minf(hedge, absf(v - vs))
	var mq := Vector2((u0 + u1) * 0.5, (lo + hi) * 0.5)
	return {"id": Vector2i(c, r * 2 + sub), "hedge": hedge,
		"mid": Vector2(mq.x * ca - mq.y * sa, mq.x * sa + mq.y * ca)}


func _is_plantation(field: Dictionary) -> bool:
	var id: Vector2i = field["id"]
	var mid: Vector2 = field["mid"]
	return _field_rand(id.x, id.y, 12) < PLANT_CHANCE and _sample_height(mid) > PLANT_MIN_HEIGHT


func _sample_height(p: Vector2) -> float:
	# The nearest height sample (as the shader's height_fetch).
	var j := clampi(roundi((p.x - _fine_origin.x) / _fine_step), 0, _fine_w - 1)
	var k := clampi(roundi((p.y - _fine_origin.y) / _fine_step), 0, _fine_h - 1)
	return _fine[k * _fine_w + j]


func coast_at(wx: float, wz: float) -> float:
	# The smoothed land mask at a point: 0 out at sea, SHORE_LEVEL at the waterline, 1 inland.
	var j := clampi(roundi((wx - _fine_origin.x) / _fine_step), 0, _fine_w - 1)
	var k := clampi(roundi((wz - _fine_origin.y) / _fine_step), 0, _fine_h - 1)
	return _fine_coast[k * _fine_w + j]


func _land_value(gx: int, gz: int, channel: int) -> float:
	# One of the per-tile ground values (0 damp, 1 woods, 2 near the sea) on the padded grid.
	var gw := map_w + PADDING * 2
	var gh := map_h + PADDING * 2
	return _land_info[(clampi(gz, 0, gh - 1) * gw + clampi(gx, 0, gw - 1)) * 4 + channel]


func _plan_woods(gw: int, gh: int, lift: PackedFloat32Array, land: PackedFloat32Array) -> void:
	# Natural woods: clumps from a noise, more likely on slopes and in gullies,
	# never on the beach or right by the sea. Stored per padded tile (0-1).
	var noise := FastNoiseLite.new()
	noise.seed = 1977
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	for gz in gh:
		for gx in gw:
			var g := gz * gw + gx
			if land[g] < 0.5:
				continue
			var steep := absf(lift[gz * gw + mini(gx + 1, gw - 1)] - lift[gz * gw + maxi(gx - 1, 0)]) \
				+ absf(lift[mini(gz + 1, gh - 1) * gw + gx] - lift[maxi(gz - 1, 0) * gw + gx])
			var raw := noise.get_noise_2d(gx - PADDING, gz - PADDING) + 0.012 * steep \
				+ 0.25 * _land_info[g * 4] - 0.7 * _land_info[g * 4 + 2]
			_land_info[g * 4 + 1] = smoothstep(0.24, 0.42, raw)


const FAR_RINGS: Array[float] = [0.0, 30.0, 80.0, 160.0, 300.0, 550.0, 1000.0, 1800.0, 3200.0,
	5500.0, 9000.0, 14000.0]      # metres beyond the detailed ground where the far land has a row
const FAR_HILLS := 45.0           # how high the distant land rolls (metres)


func _build_far_land() -> void:
	# Plain distant land and sea beyond the detailed ground, out into the haze,
	# so the world doesn't stop at a ruler line: the coast carries straight on,
	# the land rolls gently inland. Made of four strips and four corners, with a
	# row of points matching the edge of the detailed ground exactly.
	var lo := _fine_origin
	var hi := _fine_origin + Vector2(_fine_w - 1, _fine_h - 1) * _fine_step
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.00035
	noise.fractal_octaves = 3
	var along_x := PackedFloat32Array()
	for j in _fine_w:
		along_x.append(lo.x + j * _fine_step)
	var along_z := PackedFloat32Array()
	for k in _fine_h:
		along_z.append(lo.y + k * _fine_step)
	var out_lo := PackedFloat32Array()     # outwards from the low edge (descending coordinates)
	var out_hi := PackedFloat32Array()
	for r in range(FAR_RINGS.size() - 1, -1, -1):
		out_lo.append(lo.x - FAR_RINGS[r])
	for r in FAR_RINGS.size():
		out_hi.append(hi.x + FAR_RINGS[r])
	var out_lo_z := PackedFloat32Array()
	var out_hi_z := PackedFloat32Array()
	for r in range(FAR_RINGS.size() - 1, -1, -1):
		out_lo_z.append(lo.y - FAR_RINGS[r])
	for r in FAR_RINGS.size():
		out_hi_z.append(hi.y + FAR_RINGS[r])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	# (xs, zs) pairs: west, east, north, south strips and the four corners.
	for patch: Array in [[out_lo, along_z], [out_hi, along_z], [along_x, out_lo_z], [along_x, out_hi_z],
			[out_lo, out_lo_z], [out_hi, out_lo_z], [out_lo, out_hi_z], [out_hi, out_hi_z]]:
		var xs: PackedFloat32Array = patch[0]
		var zs: PackedFloat32Array = patch[1]
		for z: float in zs:
			for x: float in xs:
				var at := Vector2(x, z)
				var edge := at.clamp(lo, hi)
				var d := at.distance_to(edge)
				var h := height_at(edge.x, edge.y)
				var c := coast_at(edge.x, edge.y)
				if c >= SHORE_LEVEL:
					var far_h := 8.0 + FAR_HILLS * (noise.get_noise_2d(x, z) * 0.5 + 0.5)
					h = maxf(lerpf(h, far_h, smoothstep(0.0, 4000.0, d)), minf(h, 0.5))
				else:
					h = lerpf(h, -SEA_DEEP, smoothstep(0.0, 1500.0, d))
				st.set_uv(Vector2(1.0, c if d < 1.0 else (1.0 if c >= SHORE_LEVEL else 0.0)))
				st.add_vertex(Vector3(x, h, z))
		var w := xs.size()
		for zi in zs.size() - 1:
			for xi in w - 1:
				var a := base + zi * w + xi
				st.add_index(a)
				st.add_index(a + 1)
				st.add_index(a + w)
				st.add_index(a + 1)
				st.add_index(a + w + 1)
				st.add_index(a + w)
		base += w * zs.size()
	st.generate_normals()
	var far := MeshInstance3D.new()
	far.mesh = st.commit()
	far.material_override = terrain_material
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain_root.add_child(far)


func _mirror(t: int, size: int) -> int:
	# A tile index reflected back into the map at its edges.
	if t < 0:
		t = -t - 1
	elif t >= size:
		t = 2 * size - t - 1
	return clampi(t, 0, size - 1)


func _blur3(src: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array:
	# A soft [1 2 1] blur both ways (edges repeat).
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	for y in h:
		var row := y * w
		for x in w:
			tmp[row + x] = (src[row + maxi(x - 1, 0)] + 2.0 * src[row + x] + src[row + mini(x + 1, w - 1)]) * 0.25
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		var up := maxi(y - 1, 0) * w
		var down := mini(y + 1, h - 1) * w
		var row := y * w
		for x in w:
			out[row + x] = (tmp[up + x] + 2.0 * tmp[row + x] + tmp[down + x]) * 0.25
	return out


func _upsample(src: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array:
	# Smooth (cubic) enlargement to the fine samples.
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, src.to_byte_array())
	img.resize(w * TERRAIN_SUB, h * TERRAIN_SUB, Image.INTERPOLATE_CUBIC)
	return img.get_data().to_float32_array()


func _distance_to(cells: PackedFloat32Array, w: int, h: int, value: float) -> PackedFloat32Array:
	# Steps (in tiles) from each cell to the nearest cell holding `value`.
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	dist.fill(1e9)
	var queue := PackedInt32Array()
	for g in w * h:
		if cells[g] == value:
			dist[g] = 0.0
			queue.append(g)
	var head := 0
	while head < queue.size():
		var g := queue[head]
		head += 1
		var x := g % w
		var y := g / w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + d.x
			var ny := y + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ng := ny * w + nx
			if dist[ng] > dist[g] + 1.0:
				dist[ng] = dist[g] + 1.0
				queue.append(ng)
	return dist


func _grid_mesh(quads: int, step: float) -> ArrayMesh:
	# A flat square grid (the terrain shader raises it). Each square is split
	# along the same diagonal height_at() assumes.
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var side := quads + 1
	verts.resize(side * side)
	normals.resize(side * side)
	for z in side:
		for x in side:
			verts[z * side + x] = Vector3(x * step, 0.0, z * step)
			normals[z * side + x] = Vector3.UP
	indices.resize(quads * quads * 6)
	var at := 0
	for z in quads:
		for x in quads:
			var a := z * side + x
			var b := a + 1
			var c := a + side
			var d := c + 1
			indices[at] = a
			indices[at + 1] = b
			indices[at + 2] = c
			indices[at + 3] = b
			indices[at + 4] = d
			indices[at + 5] = c
			at += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	var extent := Vector2(map_w, map_h) * cell
	plane.size = extent + Vector2(PADDING * cell * 2.0, PADDING * cell * 2.0) + Vector2(40000, 40000)
	var mat := ShaderMaterial.new()
	mat.shader = SEA_SHADER
	plane.material = mat
	sea_material = mat
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
	roof_material = roof_mat
	roof_mat.shader = ROOF_SHADER
	var slate := _optional_texture("slate")
	if slate:
		roof_mat.set_shader_parameter("use_texture", true)
		roof_mat.set_shader_parameter("roof_tex", slate)
		roof_mat.set_shader_parameter("roof_average", _average_colour(slate))
	roofs.multimesh = _new_multimesh(_gable_mesh(), false)
	roofs.material_override = roof_mat
	add_child(roofs)
	_load_models(stone, slate)

	var chimney_mesh := CylinderMesh.new()
	chimney_mesh.top_radius = 0.8
	chimney_mesh.bottom_radius = 1.0
	chimney_mesh.height = 1.0
	chimney_mesh.radial_segments = 16
	var chimney_mat := StandardMaterial3D.new()
	chimney_mat.vertex_color_use_as_albedo = true
	chimney_mat.vertex_color_is_srgb = true      # (the game's colours are sRGB, like the props')
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

	var flat := ShaderMaterial.new()
	flat.shader = PAVING_SHADER
	flat.set_shader_parameter("noise_tex", _noise_tex)
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
	_water_icon = _svg_texture(WATER_ICON_SVG)
	add_child(alerts)
	add_child(service_pins)
	_build_reach_decal()
	_build_smoke()


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


func refresh_ground(layout_changed: bool = true) -> void:
	# Warnings on the ground; roads, power lines and woods too when the layout
	# has changed (they only depend on what's where).
	var tiles: PackedByteArray = sim.tiles
	var reach: PackedByteArray = sim.road_reach_map()
	var power: PackedByteArray = sim.power_map()
	if layout_changed:
		for y in map_h:
			for x in map_w:
				var k := y * map_w + x
				_infill[k] = _infill_kind(x, y) if tiles[k] == Tile.EMPTY else 0
	# (The plots' own ground, zone colours included, is painted from the lot map:
	# see _plan_lots, refreshed with the buildings.)
	for y in map_h:
		for x in map_w:
			var i := y * map_w + x
			var t := tiles[i]
			var warn := Color(0, 0, 0, 0)
			if ZONE_TINTS.has(t):
				if not sim.has_road_access(i):
					warn.r = 1.0
				elif power[i] == 0:
					warn.g = 1.0   # (shown as a floating icon, see _build_alerts)
				elif sim.needs_water_to_grow(i):
					warn.b = 1.0
			elif sim.is_service(t):
				if reach[i] > Settings.ROAD_REACH:
					warn.r = 1.0
				elif power[i] == 0:
					warn.g = 1.0
			elif t == Tile.AIRPORT:
				# (Only the terminal needs the road: the hover text says what's missing.)
				if sim.airport_role_at(i) == AIRPORT_TERMINAL and reach[i] > Settings.ROAD_REACH:
					warn.r = 1.0
			elif sim.is_project_tile(t):
				# (One road for the whole site, and nothing to warn about while it's being
				# built: the hover text says what's missing.)
				var deal_k: int = sim._deal_at.get(i, -1)
				if deal_k >= 0 and not sim.building_working(i) and not sim.deal_building(deal_k) and not sim.deal_repairing(deal_k):
					warn.g = 1.0
			elif sim.is_building(t):
				if not sim.makes_power(t) and not sim.needs_nothing(t):
					if reach[i] > Settings.ROAD_REACH:
						warn.r = 1.0
					elif not sim.building_working(i):
						warn.g = 1.0
			warn_image.set_pixel(x, y, warn)
	warn_texture.update(warn_image)
	_build_alerts()
	if overlay != Overlay.NONE:
		_paint_overlay()
	if layout_changed:
		_build_roads(tiles)
		_build_power_lines(tiles)
		_update_natural_trees(tiles)
		_update_built_map(tiles)
		_update_planted_woods(tiles)


func _update_built_map(tiles: PackedByteArray) -> void:
	# Fields, woods' dark ground and the wild look give way where anything is
	# built (power lines just cross the fields). Planted woodland stays wild, and
	# (G) gets the woods' dark ground, as if the land map said woods there.
	for y in map_h:
		for x in map_w:
			var i := y * map_w + x
			var t := tiles[i]
			var planted := t == Tile.WOODLAND
			var built := (t != Tile.EMPTY and t != Tile.POWER_LINE and not planted) or _infill[i] != 0
			built_image.set_pixel(x, y, Color(1.0 if built else 0.0, 1.0 if planted else 0.0, 0.0))
	built_texture.update(built_image)


func _build_alerts() -> void:
	# A floating icon over every plot that can't grow: no road (red), no power (yellow).
	# Icons are reused from one refresh to the next; spare ones are hidden.
	var count := 0
	for y in map_h:
		for x in map_w:
			var warn := warn_image.get_pixel(x, y)
			if warn.r < 0.5 and warn.g < 0.5 and warn.b < 0.5:
				continue
			if count == _alert_items.size():
				var fresh := Sprite3D.new()
				fresh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				fresh.no_depth_test = true
				fresh.render_priority = 10
				fresh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				alerts.add_child(fresh)
				_alert_items.append([fresh, Vector3.ZERO])
			var item: Array = _alert_items[count]
			var sprite: Sprite3D = item[0]
			sprite.texture = _road_icon if warn.r >= 0.5 else (_power_icon if warn.g >= 0.5 else _water_icon)
			sprite.visible = true
			item[1] = ground_point(Vector2i(x, y))
			count += 1
	for n in range(count, _alert_items.size()):
		var spare: Sprite3D = _alert_items[n][0]
		spare.visible = false
	_alert_count = count
	_place_alerts()


func _place_pins() -> void:
	# Service pins float a little higher than warning icons, and a little bigger.
	for n in _pin_count:
		var item: Array = _pin_items[n]
		var sprite: Sprite3D = item[0]
		var ground: Vector3 = item[1]
		sprite.pixel_size = _alert_size * 1.25 / 96.0
		sprite.position = ground + Vector3.UP * (30.0 + _alert_size * 1.2)


func set_view_distance(distance: float) -> void:
	# Shadows only as far as needed, so they stay crisp when zoomed in.
	_view_distance = distance
	sun.directional_shadow_max_distance = clampf(distance * SHADOW_REACH, 400.0, 9000.0)
	# Haze only well beyond what you're looking at.
	env.fog_depth_begin = distance * HAZE_START
	env.fog_depth_end = distance * HAZE_END
	_set_tree_range(maxf(TREE_RANGE_MIN, distance * TREE_RANGE))
	# Keep the warning icons a readable size however far the camera is.
	var size := clampf(distance * 0.022, 12.0, 120.0)
	if absf(size - _alert_size) > _alert_size * 0.05:
		_alert_size = size
		_place_alerts()
		_place_pins()


func _place_alerts() -> void:
	for n in _alert_count:
		var item: Array = _alert_items[n]
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
	_spire_items.clear()
	_model_items.clear()
	_smoke_points.clear()
	_values = sim.land_value_map()
	_wall_owner.clear()
	_roof_owner.clear()
	_plan_lots()
	for i in tiles.size():
		var t := tiles[i]
		var lv := levels[i]
		var walls_before := wall_list.size()
		var roofs_before := roof_list.size()
		_current_owner = i
		if t == Tile.POWER_PLANT:
			_plan_plant(i, wall_list, chimney_list)
		elif t == Tile.WOODLAND:
			pass    # (its trees are drawn with the woods: _update_planted_woods)
		elif sim.is_building(t):
			_plan_building(i, t, wall_list, roof_list, chimney_list)
		elif ZONE_TINTS.has(t) and lv > 0 and sim.is_abandoned(i):
			_plan_abandoned(i, t, wall_list, roof_list, chimney_list, walls_before, roofs_before)
		elif ZONE_TINTS.has(t) and lv > 0:
			_plan_zone(i, t, sim.stage(i), wall_list, roof_list, chimney_list)
		elif sim.is_service(t):
			_plan_service(i, t, wall_list, roof_list)
		elif ZONE_TINTS.has(t) and _lot_kind[i] == LOT_SITE:
			_plan_site(i, t, wall_list)
		elif ZONE_TINTS.has(t):
			_plan_empty(i, t)
		elif t == Tile.PARK:
			_plan_park(i)
		elif t == Tile.EMPTY and _infill[i] > 0:
			_plan_infill(i)
		for n in wall_list.size() - walls_before:
			_wall_owner.append(i)
		for n in roof_list.size() - roofs_before:
			_roof_owner.append(i)
	_fill(walls.multimesh, wall_list, true)
	_fill(roofs.multimesh, roof_list, false)
	_wall_base = _colours_of(wall_list)
	_roof_base = _colours_of(roof_list)
	_fill_models()
	if overlay != Overlay.NONE:
		_recolour_buildings()
	chimney_list.append_array(_spire_items)
	_fill(chimneys.multimesh, chimney_list, false)
	_place_smoke()
	_plan_street_furniture(tiles)
	_fill_chunked(paving, _paving_items)
	_fill_chunked(props, _prop_items)
	var bodies: Array = []
	var cabins: Array = []
	for car in _parked_items:
		bodies.append([car[0], car[1]])
		cabins.append([car[2], Color.WHITE])
	_fill_chunked(parked_bodies, bodies)
	_fill_chunked(parked_cabins, cabins)
	_build_city_trees(tiles)
	_write_lots()


const LAMP_GREY := Color(0.30, 0.32, 0.33)
const SHELTER_GLASS := Color(0.62, 0.72, 0.76)


func _plan_street_furniture(tiles: PackedByteArray) -> void:
	# Along every straight street: lamp posts where the road shader puts its pools
	# of light (every 25 m, staggered), and by flats, shops and offices a bus
	# shelter, litter bins and the odd post box. On the pavement (the road's
	# outer 1.7 m), facing the road.
	for i in tiles.size():
		if tiles[i] != Tile.ROAD:
			continue
		var tile := Vector2i(i % map_w, i / map_w)
		var road: int = sim.road_kind[i]
		var out_m: float = ROAD_HALF_WIDTHS[road] - ROAD_HALF_WIDTH    # how much wider than a plain road
		for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if not (_is_road(tile + axis) and _is_road(tile - axis)):
				continue
			var normal_axis := Vector2i(axis.y, axis.x)
			if _is_road(tile + normal_axis) or _is_road(tile - normal_axis):
				continue
			var c := tile_centre(tile)
			var ax := Vector2(axis)
			var nx := Vector2(normal_axis)
			if road == Settings.MOTORWAY:
				# A crash barrier down the middle and tall twin-headed lamps in it.
				for k: int in 4:
					_street_box(c + ax * (-18.75 + k * 12.5), Vector3(0.5 + absf(ax.x) * 12.0, 0.8, 0.5 + absf(ax.y) * 12.0),
						CONCRETE)
				for along: float in [0.0, -cell * 0.5 + 0.5]:
					var at := c + ax * along
					_street_box(at, Vector3(0.25, 11.0, 0.25), LAMP_GREY)
					_street_box(at, Vector3(0.3 + absf(nx.x) * 4.4, 0.2, 0.3 + absf(nx.y) * 4.4), LAMP_GREY, 10.8)
				continue
			# Lamps: one side mid-tile, the other at the tile's ends (see road.gdshader).
			var lamp_side := Vector2(-axis.y, axis.x)
			for spot: Vector2 in [Vector2(0.0, 1.0), Vector2(-cell * 0.5 + 0.5, -1.0)]:
				_lamp(c + ax * spot.x + lamp_side * spot.y * ROAD_LAMP_OFFSETS[road], -lamp_side * spot.y)
			for side: int in [-1, 1]:
				var beside: Vector2i = tile + normal_axis * side
				if beside.x < 0 or beside.y < 0 or beside.x >= map_w or beside.y >= map_h:
					continue
				var kind: int = _lot_kind[beside.y * map_w + beside.x]
				var busy := kind == LOT_SHOPS or kind == LOT_PLAZA or kind == LOT_TENEMENTS or kind == LOT_COURT \
					or kind == LOT_CIVIC
				var r := _field_rand(tile.x * 2 + (side + 1) / 2, tile.y, 301 + axis.x)
				var out := nx * float(side)
				if busy and r < 0.22:
					_bus_shelter(c + ax * 8.0 + out * (5.35 + out_m), -out, ax)
				if busy and r > 0.5:
					_street_box(c + ax * -6.0 + out * (5.5 + out_m), Vector3(0.5, 0.9, 0.5), CHARCOAL)       # litter bin
				if r > 0.93:
					_street_box(c + ax * 14.0 + out * (5.4 + out_m), Vector3(0.5, 1.4, 0.5), POST_BOX)


func _street_box(at: Vector2, size: Vector3, colour: Color, lift: float = 0.0) -> void:
	var pos := Vector3(at.x, maxf(height_at(at.x, at.y), 0.0) + 0.3 + lift, at.y)
	_prop_items.append([Transform3D(Basis.from_scale(size), pos), colour])


func _lamp(at: Vector2, towards_road: Vector2) -> void:
	# A street lamp: a slim post and a head leaning out over the road.
	_street_box(at, Vector3(0.16, 7.2, 0.16), LAMP_GREY)
	var head := at + towards_road * 0.7
	_street_box(head, Vector3(0.3 + absf(towards_road.x) * 1.2, 0.18, 0.3 + absf(towards_road.y) * 1.2),
		LAMP_GREY, 7.0)


func _bus_shelter(at: Vector2, towards_road: Vector2, along: Vector2) -> void:
	# A glass bus shelter: back and end panels, a roof, a bench inside.
	var z_axis := Vector3(towards_road.x, 0.0, towards_road.y)
	var x_axis := Vector3(along.x, 0.0, along.y)
	var base := Vector3(at.x, maxf(height_at(at.x, at.y), 0.0) + 0.3, at.y)
	_box_item(_prop_items, base - z_axis * 0.55, x_axis, z_axis, Vector3(3.4, 2.3, 0.08), SHELTER_GLASS)
	_box_item(_prop_items, base - x_axis * 1.65, x_axis, z_axis, Vector3(0.08, 2.3, 1.1), SHELTER_GLASS)
	_box_item(_prop_items, base + Vector3.UP * 2.3, x_axis, z_axis, Vector3(3.6, 0.12, 1.4), CHARCOAL)
	_box_item(_prop_items, base - z_axis * 0.3, x_axis, z_axis, Vector3(2.4, 0.45, 0.4), CHARCOAL)


func _plan_lots() -> void:
	# What kind of ground each plot has (see LOT_...), for the shader and for
	# the plot plans (a park's layout, whether an empty plot is being built on).
	var tiles: PackedByteArray = sim.tiles
	_lot_kind.resize(tiles.size())
	_lot_detail.resize(tiles.size())
	for i in tiles.size():
		var t := tiles[i]
		var kind := LOT_NONE
		var detail := 0
		if t == Tile.ROAD:
			kind = LOT_ROAD
		elif ZONE_TINTS.has(t) and sim.levels[i] == 0:
			# Being built on (the town wants it and it can grow), or still waiting.
			var growing: bool = sim.has_road_access(i) and sim.growth_state(i) == Growth.GROWING
			kind = LOT_SITE if growing else LOT_EMPTY
		elif t == Tile.HOMES:
			var s: int = sim.stage(i)
			detail = s
			if s >= 7:
				kind = LOT_PLAZA
			elif s >= 4:
				kind = LOT_COURT
			elif s == 3:
				kind = LOT_TENEMENTS
			elif s == 2 and sim.density[i] >= 1:
				kind = LOT_TERRACES
			else:
				kind = LOT_VILLAS
		elif t == Tile.SHOPS:
			var s: int = sim.stage(i)
			detail = s
			kind = LOT_PLAZA if s >= 4 else LOT_SHOPS
		elif t == Tile.OFFICES:
			var s: int = sim.stage(i)
			detail = s
			kind = LOT_PLAZA if s >= 3 else LOT_SHOPS
		elif t == Tile.INDUSTRY:
			kind = LOT_INDUSTRY
			detail = sim.stage(i)
		elif t == Tile.PARK or (t == Tile.EMPTY and _infill[i] == INFILL_PARK):
			kind = LOT_PARK
		elif t == Tile.EMPTY and _infill[i] == INFILL_ALLOTMENTS:
			kind = LOT_ALLOTMENTS
		elif t == Tile.EMPTY and _infill[i] == INFILL_CAR_PARK:
			kind = LOT_CAR_PARK
		else:
			match t:
				Tile.BIG_BEN, Tile.COLOSSEUM, Tile.OPERA_HOUSE, Tile.EMPIRE_STATE, Tile.EIFFEL, Tile.LIBERTY, \
						Tile.POLICE, Tile.LIBRARY, Tile.MUSEUM, Tile.TOWN_HALL, Tile.STATION, Tile.STADIUM, Tile.MARINA:
					kind = LOT_CIVIC
				Tile.SCHOOL:
					kind = LOT_SCHOOL
				Tile.HOSPITAL, Tile.CLINIC, Tile.POLICE_OFFICE, Tile.TAJ_MAHAL:
					kind = LOT_HOSPITAL
				Tile.GOLF:
					kind = LOT_GOLF
				Tile.WIND, Tile.SOLAR, Tile.GREAT_PYRAMID:
					kind = LOT_MEADOW
				Tile.WOODLAND:
					kind = LOT_WOODS
				Tile.AIRPORT:
					kind = LOT_AIRPORT
					detail = sim.airport_role[i] if i < sim.airport_role.size() else 4
				Tile.FIRE, Tile.FIRE_SMALL, Tile.POWER_PLANT, Tile.GAS, Tile.NUCLEAR, Tile.WATER_PUMP, Tile.WATER_TOWER, \
						Tile.LANDFILL, Tile.RECYCLING, Tile.INCINERATOR, Tile.BUS_DEPOT, Tile.HARBOUR, Tile.DATA_CENTRE, \
						Tile.GIGAFACTORY:
					kind = LOT_YARD
				Tile.LAUNCH_SITE, Tile.AI_DATA_CENTRE:
					kind = LOT_YARD
				Tile.TECH_CAMPUS:
					# Landscaped lawns once it's open; bare concrete while it's being built.
					var dk: int = sim._deal_at.get(i, -1)
					kind = LOT_YARD if dk >= 0 and sim.deal_building(dk) else LOT_PARK
					detail = PARK_LAWN
		_lot_kind[i] = kind
		_lot_detail[i] = detail
	# Parks: each tile picks a layout, knowing which of its sides join more park.
	for i in tiles.size():
		if _lot_kind[i] == LOT_PARK and tiles[i] != Tile.TECH_CAMPUS:   # (a campus is all lawn)
			_lot_detail[i] = _park_layout(i)


func _write_lots() -> void:
	for y in map_h:
		for x in map_w:
			var i := y * map_w + x
			var kind: int = _lot_kind[i]
			if kind == LOT_NONE:
				lot_image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var g := 0
			var b := 0
			var a := 0
			if kind != LOT_ROAD:
				var front := _frontage(i)
				g = SIDES.find(front)
				g = [2, 3, 0, 1][g]          # SIDES order -> _frontage order (+y, -y, +x, -x)
				g |= mini(_lot_detail[i], 31) << 3
				b = _same_kind_mask(i)
				for s: int in 4:
					if _street_reach(i, SIDES[s]) > 0.0:
						a |= 16 << s
				if kind == LOT_EMPTY or kind == LOT_SITE:
					var zone: int = 0 if sim.tiles[i] == Tile.OFFICES else sim.tiles[i] - Tile.HOMES + 1
					b |= (zone << 4) | (int(sim.density[i]) << 6)
				if ZONE_TINTS.has(sim.tiles[i]) and sim.is_abandoned(i):
					a |= 1
				if sim.district[i] == 2:
					a |= 2
			lot_image.set_pixel(x, y, Color8(kind, g, b, a))
	lot_texture.update(lot_image)


const PARK_LAWN := 0         # open lawn, a winding path, clumps of trees
const PARK_POND := 1         # a pond with reeds and a path round it
const PARK_FORMAL := 2       # cross paths, a fountain, flower beds
const PARK_PLAY := 3         # a playground
const PARK_PITCH := 4        # a football pitch
const PARK_BANDSTAND := 5    # a bandstand on a round paved plaza


func _park_layout(i: int) -> int:
	# Picked by position, so the same park always looks the same; neighbouring
	# tiles of one park differ. (The shader draws the layout's ground.)
	var x := i % map_w
	var y := i / map_w
	var choices: Array[int] = [PARK_POND, PARK_FORMAL, PARK_PLAY, PARK_BANDSTAND, PARK_LAWN]
	if sim.tiles[i] == Tile.EMPTY:
		choices = [PARK_LAWN, PARK_PLAY, PARK_FORMAL]          # pocket parks
	elif _same_kind_mask(i) != 0:
		choices = [PARK_POND, PARK_PITCH, PARK_LAWN, PARK_PLAY, PARK_FORMAL, PARK_BANDSTAND, PARK_LAWN]
	var pick := int(_field_rand(x, y, 101) * choices.size()) % choices.size()
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		var n := Vector2i(x, y) + d
		if n.x < 0 or n.y < 0:
			continue
		var k := n.y * map_w + n.x
		if _lot_kind[k] == LOT_PARK and _lot_detail[k] == choices[pick]:
			pick = (pick + 1) % choices.size()
	return choices[pick]


const RAILINGS := Color(0.12, 0.13, 0.13)
const BENCH := Color(0.42, 0.30, 0.19)
const PLAY_COLOURS := [Color(0.85, 0.20, 0.15), Color(0.15, 0.45, 0.80), Color(0.95, 0.75, 0.15),
	Color(0.20, 0.60, 0.30)]


func _park_prop(i: int, x: float, z: float, w: float, d: float, h: float, colour: Color,
		lift: float = 0.0) -> void:
	# A box in a park, placed by x, z from the tile's middle (parks are laid out
	# square to the map, not to a street).
	var c := tile_centre(Vector2i(i % map_w, i / map_w))
	var pos := Vector3(c.x + x, maxf(height_at(c.x + x, c.y + z), 0.0) - 0.1 + lift, c.y + z)
	_prop_items.append([Transform3D(Basis(Vector3.RIGHT * w, Vector3.UP * h, Vector3.BACK * d), pos), colour])


func _park_shape(i: int) -> Dictionary:
	# The numbers the shader lays a park tile out by (lots.gdshaderinc park()).
	var x := i % map_w
	var y := i / map_w
	var ext: Array[float] = []
	for s: int in 4:
		ext.append(cell * 0.5 + ((cell * 0.5 - ROAD_HALF_WIDTH - 1.0) if _street_reach(i, SIDES[s]) > 0.0 else 0.0))
	return {"plan": int(_lot_detail[i]), "same": _same_kind_mask(i), "ext": ext,
		"off": (Vector2(_field_rand(x, y, 111), _field_rand(x, y, 112)) - Vector2(0.5, 0.5)) * 8.0}


func _park_edge(shape: Dictionary, x: float, z: float) -> float:
	# How far x, z is from the park's outer edge (sides joining more park don't count).
	var ext: Array[float] = shape["ext"]
	var same: int = shape["same"]
	var edge := 1e4
	if (same & 1) == 0:
		edge = minf(edge, ext[0] - x)
	if (same & 2) == 0:
		edge = minf(edge, ext[1] + x)
	if (same & 4) == 0:
		edge = minf(edge, ext[2] - z)
	if (same & 8) == 0:
		edge = minf(edge, ext[3] + z)
	return edge


func _park_open(i: int, shape: Dictionary, x: float, z: float) -> bool:
	# Is x, z open grass, clear of the paths and features the shader paints?
	var edge := _park_edge(shape, x, z)
	if edge < 1.5 or absf(edge - 4.2) < 2.8:
		return false
	var same: int = shape["same"]
	var c := tile_centre(Vector2i(i % map_w, i / map_w))
	var tx := i % map_w
	var ty := i / map_w
	var ew := (same & 3) != 0 and ((same & 12) == 0 or ty % 2 == 0)
	var ns := (same & 12) != 0 and ((same & 3) == 0 or tx % 2 == 0)
	if ew and absf(z - 7.0 * sin((c.x + x) / 21.0 + ty * 1.7)) < 3.0:
		return false
	if ns and absf(x - 7.0 * sin((c.y + z) / 23.0 + tx * 2.3)) < 3.0:
		return false
	var off: Vector2 = shape["off"]
	var p := Vector2(x, z)
	match int(shape["plan"]):
		PARK_POND:
			return p.distance_to(off) > 17.0
		PARK_FORMAL:
			return absf(x) > 16.5 or absf(z) > 16.5
		PARK_PLAY:
			var q := p - Vector2(7.0, -7.0) - off * 0.4
			return (absf(q.x) > 10.5 or absf(q.y) > 8.5) and absf(x + z * 0.9) > 2.5
		PARK_PITCH:
			return absf(x) > 23.0 or absf(z) > 15.0
		PARK_BANDSTAND:
			return p.length() > 13.5 and absf(x - z) > 2.5
		_:
			return same != 0 or absf(z - x * 0.5 - 6.0 * sin(x / 9.0 + ty)) > 2.8
	return true


func _plan_park(i: int) -> void:
	# What stands in a park (its ground is painted by the shader): railings along
	# the street sides with a gate, benches by the paths, the layout's own pieces
	# (a fountain, a playground, goals, a bandstand) and trees on the open grass.
	var shape := _park_shape(i)
	var ext: Array[float] = shape["ext"]
	var same: int = shape["same"]
	var off: Vector2 = shape["off"]
	var pocket: bool = sim.tiles[i] == Tile.EMPTY
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 5333 + 11
	# Railings round the outside, a gate in the middle of each side.
	for s: int in 4:
		if (same & (1 << s)) != 0:
			continue
		var side: Vector2i = SIDES[s]
		var e: float = ext[s] - 0.2
		var run_lo: float = -ext[3] if side.x != 0 else -ext[1]
		var run_hi: float = ext[2] if side.x != 0 else ext[0]
		for part: Vector2 in [Vector2(run_lo, -1.5), Vector2(1.5, run_hi)]:
			var length := part.y - part.x
			var mid := (part.x + part.y) * 0.5
			if side.x != 0:
				_park_prop(i, side.x * e, mid, 0.06, length, 1.1, RAILINGS)
			else:
				_park_prop(i, mid, side.y * e, length, 0.06, 1.1, RAILINGS)
	match int(shape["plan"]):
		PARK_POND:
			for k in 3:
				var a := rng.randf() * TAU
				var at := off + Vector2.from_angle(a) * 13.0
				_park_bench(i, at, -Vector2.from_angle(a))
		PARK_FORMAL:
			_park_prop(i, 0.0, 0.0, 0.5, 0.5, 1.6, WHITE_RENDER)          # the fountain's jet
			_park_prop(i, 0.0, 0.0, 1.3, 1.3, 0.7, CREAM_STONE)           # ...and its pedestal
			for corner: Vector2 in [Vector2(5.0, 5.0), Vector2(-5.0, 5.0), Vector2(5.0, -5.0), Vector2(-5.0, -5.0)]:
				_park_bench(i, corner * 1.25, -corner.normalized())
		PARK_PLAY:
			var q := Vector2(7.0, -7.0) + off * 0.4
			# Swings: two A-frames and a top bar; a slide; a climbing frame; a fence.
			for end: float in [-2.2, 2.2]:
				_park_prop(i, q.x - 4.0 + end, q.y - 2.0, 0.12, 1.6, 2.3, PLAY_COLOURS[1])
			_park_prop(i, q.x - 4.0, q.y - 2.0, 4.6, 0.12, 0.12, PLAY_COLOURS[1], 2.25)
			_park_prop(i, q.x + 4.0, q.y - 2.5, 1.0, 3.5, 1.4, PLAY_COLOURS[0])
			_park_prop(i, q.x + 4.0, q.y - 4.6, 1.2, 1.2, 2.0, PLAY_COLOURS[2])
			_park_prop(i, q.x + 3.0, q.y + 2.5, 2.6, 2.6, 2.0, PLAY_COLOURS[3])
			_park_prop(i, q.x + 3.0, q.y + 2.5, 3.0, 3.0, 0.15, PLAY_COLOURS[0], 2.0)
			_park_prop(i, q.x, q.y - 6.1, 16.0, 0.05, 1.0, PLAY_COLOURS[3])
			_park_prop(i, q.x, q.y + 6.1, 16.0, 0.05, 1.0, PLAY_COLOURS[3])
			_park_prop(i, q.x - 8.1, q.y, 0.05, 12.0, 1.0, PLAY_COLOURS[3])
			_park_bench(i, q + Vector2(-10.0, 3.0), Vector2(1.0, 0.0))
		PARK_PITCH:
			var h := Vector2(minf(minf(ext[0], ext[1]) - 6.0, 26.0), minf(minf(ext[2], ext[3]) - 6.0, 17.0))
			for end: float in [-1.0, 1.0]:
				for post: float in [-3.6, 3.6]:
					_park_prop(i, end * h.x, post, 0.12, 0.12, 2.4, WHITE_RENDER)
				_park_prop(i, end * h.x, 0.0, 0.12, 7.3, 0.12, WHITE_RENDER, 2.35)
		PARK_BANDSTAND:
			_cylinder(_spire_items, _park_point(i, 0.0, 0.0), 4.2, 0.8, CREAM_STONE)
			for k in 8:
				var at := Vector2.from_angle(k * TAU / 8.0) * 3.6
				_park_prop(i, at.x, at.y, 0.18, 0.18, 3.6, WHITE_RENDER, 0.7)
			_cylinder(_spire_items, _park_point(i, 0.0, 0.0) + Vector3.UP * 4.3, 4.6, 0.5, Color(0.25, 0.42, 0.35))
			_cylinder(_spire_items, _park_point(i, 0.0, 0.0) + Vector3.UP * 4.8, 2.4, 1.2, Color(0.25, 0.42, 0.35))
			for k in 4:
				var a := (k + 0.5) * TAU / 4.0
				_park_bench(i, Vector2.from_angle(a) * 8.0, -Vector2.from_angle(a))
		_:
			for k in 2:
				var a := rng.randf_range(-20.0, 20.0)
				_park_bench(i, Vector2(a, a * 0.5 + 6.0 * sin(a / 9.0 + i / map_w) + 2.2), Vector2(0.0, -1.0))
	# Benches along the path round the inside.
	if not pocket:
		for s: int in 4:
			if (same & (1 << s)) == 0 and rng.randf() < 0.6:
				var side: Vector2 = Vector2(SIDES[s])
				var along := rng.randf_range(-14.0, 14.0)
				var at := side * (ext[s] - 6.1) + Vector2(side.y, side.x) * along
				_park_bench(i, at, -side)
	# Trees on the open grass: some round the edge, the rest in loose clumps.
	var wanted := 7 if pocket else 12
	var planted := 0
	var tries := 0
	var c := tile_centre(Vector2i(i % map_w, i / map_w))
	var clump := Vector2(rng.randf_range(-15.0, 15.0), rng.randf_range(-15.0, 15.0))
	while planted < wanted and tries < 60:
		tries += 1
		var at: Vector2
		if tries % 3 == 0:
			at = clump + Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-7.0, 7.0))
		else:
			at = Vector2(rng.randf_range(-ext[1] + 2.0, ext[0] - 2.0), rng.randf_range(-ext[3] + 2.0, ext[2] - 2.0))
		if not _park_open(i, shape, at.x, at.y):
			continue
		_extra_trees.append([c + at, rng.randf_range(7.0, 15.0), _park_kind(rng)])
		planted += 1


func _park_point(i: int, x: float, z: float) -> Vector3:
	var c := tile_centre(Vector2i(i % map_w, i / map_w))
	return Vector3(c.x + x, maxf(height_at(c.x + x, c.y + z), 0.0), c.y + z)


func _park_bench(i: int, at: Vector2, facing: Vector2) -> void:
	# A bench (seat and back) turned to face the way given.
	var p := _park_point(i, at.x, at.y)
	var z_axis := Vector3(facing.x, 0.0, facing.y).normalized()
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	_box_item(_prop_items, p + Vector3.UP * 0.35, x_axis, z_axis, Vector3(1.7, 0.1, 0.5), BENCH)
	_box_item(_prop_items, p + Vector3.UP * 0.35 - z_axis * 0.25, x_axis, z_axis, Vector3(1.7, 0.5, 0.08), BENCH)
	_box_item(_prop_items, p, x_axis, z_axis, Vector3(1.5, 0.35, 0.4), CHARCOAL)


func _same_kind_mask(i: int) -> int:
	# Which neighbours (+x, -x, +y, -y as bits 0-3) are the same kind of ground.
	var tile := Vector2i(i % map_w, i / map_w)
	var mask := 0
	for s: int in 4:
		var n: Vector2i = tile + SIDES[s]
		if n.x >= 0 and n.y >= 0 and n.x < map_w and n.y < map_h and _lot_kind[n.y * map_w + n.x] == _lot_kind[i]:
			mask |= 1 << s
	return mask


func _plan_abandoned(i: int, t: int, wall_list: Array, roof_list: Array, chimney_list: Array,
		walls_before: int, roofs_before: int) -> void:
	# The same buildings as before, but run down: the shaders read the flag from
	# the colour's alpha (dark, grimy walls, boarded windows, no lights), and no
	# cars are parked outside. Its own land value drop is left out, so the
	# building keeps its look rather than turning into a cheaper one.
	var models_before := _model_items.size()
	var cars_before := _parked_items.size()
	var own_value := _values[i]
	_values[i] = minf(own_value + Settings.ABANDONED_VALUE_PENALTY, 1.0)
	_plan_zone(i, t, sim.stage(i), wall_list, roof_list, chimney_list)
	_values[i] = own_value
	_parked_items.resize(cars_before)
	for n in range(walls_before, wall_list.size()):
		var item: Array = wall_list[n]
		var c: Color = item[1]
		item[1] = Color(c.r, c.g, c.b, ABANDONED_ALPHA)
	for n in range(roofs_before, roof_list.size()):
		var item: Array = roof_list[n]
		var c: Color = item[1]
		item[1] = Color(c.r, c.g, c.b, ABANDONED_ALPHA)
	for n in range(models_before, _model_items.size()):
		var item: Array = _model_items[n]
		var c: Color = item[2]
		item[2] = Color(c.r, c.g, c.b, ABANDONED_ALPHA)


func _colours_of(items: Array) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(items.size())
	for n in items.size():
		var item: Array = items[n]
		out[n] = item[1]
	return out


func _fill(mm: MultiMesh, items: Array, custom: bool) -> void:
	mm.instance_count = items.size()
	for n in items.size():
		var item: Array = items[n]
		mm.set_instance_transform(n, item[0])
		mm.set_instance_color(n, item[1])
		if custom:
			mm.set_instance_custom_data(n, item[2])


# The town's small things (paving, props, parked cars, planted trees) run to tens
# of thousands each, so they're drawn in DETAIL_CHUNK squares: one MultiMesh per
# square, as children of the node that names them. Squares off screen are
# skipped, and each shadow cascade only draws the squares it covers. (One
# MultiMesh for the whole town was drawn in full by the main pass and by all four
# shadow cascades: tens of millions of triangles a frame.)
const DETAIL_CHUNK := 400.0
var _pieces := {}          # node -> {Vector2i square -> MultiMeshInstance3D}
var _piece_totals := {}    # node -> instances in all its squares


func _fill_chunked(node: MultiMeshInstance3D, items: Array) -> void:
	var groups := {}
	for item: Array in items:
		var xf: Transform3D = item[0]
		var key := Vector2i(floori(xf.origin.x / DETAIL_CHUNK), floori(xf.origin.z / DETAIL_CHUNK))
		if not groups.has(key):
			groups[key] = []
		var list: Array = groups[key]
		list.append(item)
	if not _pieces.has(node):
		_pieces[node] = {}
		node.multimesh.instance_count = 0        # (the node itself draws nothing)
	var pieces: Dictionary = _pieces[node]
	for key: Vector2i in pieces:
		if not groups.has(key):
			(pieces[key] as MultiMeshInstance3D).multimesh.instance_count = 0
	for key: Vector2i in groups:
		if not pieces.has(key):
			var piece := MultiMeshInstance3D.new()
			piece.multimesh = _new_multimesh(node.multimesh.mesh, false)
			piece.material_override = node.material_override
			piece.cast_shadow = node.cast_shadow
			node.add_child(piece)
			pieces[key] = piece
		_fill((pieces[key] as MultiMeshInstance3D).multimesh, groups[key], false)
	_piece_totals[node] = items.size()


func instance_total(node: MultiMeshInstance3D) -> int:
	# How many things a node draws, in all its squares (for the dev tools' report).
	var total: int = _piece_totals.get(node, node.multimesh.instance_count)
	return total


# ------------------------------------------------------------------ overlays

func set_overlay(kind: int) -> void:
	# Colour the map by land value, power, road access or growth (NONE = normal view).
	overlay = kind
	var on := kind != Overlay.NONE
	terrain_material.set_shader_parameter("overlay_on", on)
	wall_material.set_shader_parameter("overlay_on", on)
	roof_material.set_shader_parameter("overlay_on", on)
	for mat in _model_materials:
		mat.set_shader_parameter("overlay_on", on)
	# Only the Traffic view colours the road surface itself (by congestion).
	if road_material:
		road_material.set_shader_parameter("overlay_on", kind == Overlay.TRAFFIC)
		road_material.set_shader_parameter("overlay_map", overlay_texture)
		road_material.set_shader_parameter("map_size", Vector2(map_w, map_h) * cell)
	# Trees, paving and parked cars would hide the colours on the ground.
	for node: GeometryInstance3D in [paving, props, parked_bodies, parked_cabins,
			city_trunks, city_crowns, city_cones]:
		node.visible = not on
	woods.visible = not on
	smoke.visible = not on
	if kind != Overlay.SERVICES:
		service_filter = -1
	# Map views are lit by day (see MAP_VIEW_TIME); the normal view by the clock.
	set_time_of_day(_clock_time)
	if on:
		_paint_overlay()
	else:
		_recolour_buildings()
		_update_pins()


func set_service_filter(s: int) -> void:
	# The Services view showing one service (0-3), or all four (-1).
	service_filter = s
	if overlay == Overlay.SERVICES:
		_paint_overlay()


func _service_legend(s: int) -> Array:
	# The key for the Services view showing one service. Bands as in cover_strength().
	var building: String = Settings.SERVICE_NAMES[s]
	var held: String = ["Homes and shops growing at half speed: no police",
		"Buildings that could burn down: no fire cover",
		"Homes that can't grow past terraces: no school",
		"Homes growing at half speed: no hospital"][s]
	var missing: String = ["Homes and shops with no police (not holding them back yet)",
		"Plots with no fire cover (no risk yet: empty, or a small town)",
		"Homes with no school (not holding them back yet)",
		"Homes with no hospital (not holding them back yet)"][s]
	return [[OV_GREEN, "Full cover (close by)"], [OV_LIGHT_GREEN, "Covered (weaker towards the edge)"],
		[OV_RED, held], [OV_ORANGE, missing], [OV_BLUE, "%s (marked with a pin)" % building]]


func overlay_legend(kind: int) -> Array:
	# [[colour, label], ...] for the key on screen.
	match kind:
		Overlay.LAND_VALUE:
			return [[OV_GREEN, "Very high"], [OV_LIGHT_GREEN, "High"], [OV_YELLOW, "Average"],
				[OV_ORANGE, "Low"], [OV_RED, "Very low"]]
		Overlay.POWER:
			return [[OV_YELLOW, "Has power"], [OV_DARK_YELLOW, "Carries power"],
				[OV_RED, "Zone with no power"], [OV_GREY, "Not connected"]]
		Overlay.ROADS:
			return [[OV_GREY, "Road"], [OV_GREEN, "Next to a road"],
				[OV_LIGHT_GREEN, "Near enough to grow"], [OV_RED, "Zone too far from a road"]]
		Overlay.GROWTH:
			return [[OV_GREEN, "Growing"], [OV_YELLOW, "Waiting (demand, space, land value or a school)"],
				[OV_RED, "Stuck (needs a road or power)"], [OV_BLUE, "Fully built"], [OV_ABANDONED, "Abandoned"]]
		Overlay.SERVICES:
			if service_filter >= 0:
				return _service_legend(service_filter)
			return [[OV_GREEN, "All four services"], [OV_LIGHT_GREEN, "Three"],
				[OV_YELLOW, "One or two"], [OV_RED, "None"], [OV_BLUE, "Service building"]]
		Overlay.DISTRICTS:
			return [[OV_CBD, "CBD: skyscrapers allowed"], [OV_TECH, "Tech zone: its own tax rate"],
				[OV_CONSERVATION, "Conservation area: low-rise only"], [OV_GREY, "Normal"]]
		Overlay.WATER:
			return [[OV_BLUE, "Has water"], [OV_DARK_BLUE, "Carries water"],
				[OV_RED, "Needs water to grow"], [OV_GREY, "Not connected"]]
		Overlay.POLLUTION:
			return [[OV_GREEN, "Clean air"], [OV_LIGHT_GREEN, "A little"], [OV_YELLOW, "Some"],
				[OV_ORANGE, "Polluted"], [OV_RED, "Heavy"]]
		Overlay.TRAFFIC:
			# Bands match the hover text (simulation.gd traffic_band, Settings.TRAFFIC_BANDS).
			var bands: Array = Settings.TRAFFIC_BANDS
			return [[TRAFFIC_COLOURS[0], "Quiet"],
				[TRAFFIC_COLOURS[1], "Free-flowing"],
				[TRAFFIC_COLOURS[2], "Busy: over %d%% full" % roundi(float(bands[0]) * 100.0)],
				[TRAFFIC_COLOURS[3], "Heavy: over %d%% full" % roundi(float(bands[1]) * 100.0)],
				[TRAFFIC_COLOURS[4], "Jammed: more traffic than it takes"]]
	return []


static func _trips_words(n: float) -> String:
	# 6000 -> "6,000"
	var digits := str(roundi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return digits + out


func _paint_overlay() -> void:
	var tiles: PackedByteArray = sim.tiles
	var values: PackedFloat32Array = sim.land_value_map()
	var power: PackedByteArray = sim.power_map()
	var reach: PackedByteArray = sim.road_reach_map()
	for y in map_h:
		for x in map_w:
			var i := y * map_w + x
			overlay_image.set_pixel(x, y, _overlay_colour(i, tiles[i], values, power, reach))
	overlay_texture.update(overlay_image)
	_recolour_buildings()
	_update_pins()


func _update_pins() -> void:
	# A pin over every building of the service the Services view is showing, so
	# they can be found from afar. Pins are reused from one paint to the next.
	var count := 0
	if overlay == Overlay.SERVICES and service_filter >= 0:
		var tiles: PackedByteArray = sim.tiles
		for i in tiles.size():
			if sim.service_of(tiles[i]) != service_filter:
				continue
			if count == _pin_items.size():
				var fresh := Sprite3D.new()
				fresh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				fresh.no_depth_test = true
				fresh.render_priority = 11
				fresh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				service_pins.add_child(fresh)
				_pin_items.append([fresh, Vector3.ZERO])
			var item: Array = _pin_items[count]
			var sprite: Sprite3D = item[0]
			sprite.texture = _pin_texture(service_filter)
			# A building that isn't working gets a faded pin.
			sprite.modulate = Color.WHITE if sim.service_working(i) else Color(1, 1, 1, 0.45)
			sprite.visible = true
			item[1] = ground_point(Vector2i(i % map_w, i / map_w))
			count += 1
	for n in range(count, _pin_items.size()):
		var spare: Sprite3D = _pin_items[n][0]
		spare.visible = false
	_pin_count = count
	_place_pins()


func pin_count() -> int:
	# How many service pins are showing (dev tools).
	return _pin_count


func _pin_texture(s: int) -> Texture2D:
	# A round blue badge with the service's white line icon (from icons.gd).
	if not _pin_textures.has(s):
		var key: String = ["police", "fire", "school", "hospital"][s]
		var line: String = Icons.LINES[key]
		var inner := line.substr(line.find(">") + 1)
		inner = inner.substr(0, inner.rfind("</svg>"))
		var blue := OV_BLUE.to_html(false)
		var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='96' viewBox='0 0 96 96'>" \
			+ "<circle cx='48' cy='48' r='42' fill='#%s' stroke='white' stroke-width='6'/>" % blue \
			+ "<g transform='translate(19.2,19.2) scale(2.4)' fill='none' stroke='white' stroke-width='1.9' " \
			+ "stroke-linecap='round' stroke-linejoin='round'>" + inner + "</g></svg>"
		_pin_textures[s] = _svg_texture(svg)
	var tex: Texture2D = _pin_textures[s]
	return tex


func _build_reach_decal() -> void:
	# A soft disc with a crisp rim, projected onto the ground (and anything on it)
	# round the mouse while a service building is being placed: where it would
	# reach. Brighter in the middle, where it would cover fully.
	const SIZE := 256
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var full := (1.0 - 1.0 / 1.6) / (1.0 - Settings.COVERED / 1.6)   # full cover, as a share of the reach
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x + 0.5 - SIZE * 0.5, y + 0.5 - SIZE * 0.5).length() / (SIZE * 0.5)
			var a := 0.0
			if d <= 1.0:
				a = 0.16 if d < full else 0.07
				a = maxf(a, smoothstep(0.955, 0.985, d) * 0.95)
				if d < full:
					a = maxf(a, smoothstep(full - 0.03, full - 0.01, d) * 0.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	reach_decal = Decal.new()
	reach_decal.texture_albedo = ImageTexture.create_from_image(img)
	reach_decal.modulate = Color(0.82, 0.96, 1.0)
	reach_decal.normal_fade = 0.6
	reach_decal.upper_fade = 0.05
	reach_decal.lower_fade = 0.05
	reach_decal.visible = false
	add_child(reach_decal)


func show_reach(tile: Vector2i, reach_tiles: float) -> void:
	# The disc a service building on `tile` would cover (reach_tiles: where it counts).
	if tile.x < 0 or tile.y < 0 or tile.x >= map_w or tile.y >= map_h:
		reach_decal.visible = false
		return
	var r := reach_tiles * cell
	reach_decal.size = Vector3(r * 2.0, 900.0, r * 2.0)
	reach_decal.position = ground_point(tile)
	reach_decal.visible = true


func hide_reach() -> void:
	reach_decal.visible = false


func _overlay_colour(i: int, t: int, values: PackedFloat32Array, power: PackedByteArray,
		reach: PackedByteArray) -> Color:
	var none := Color(0, 0, 0, 0)
	if water[i] == 1:
		return none
	var zone := ZONE_TINTS.has(t)
	var service: bool = sim.is_service(t)
	match overlay:
		Overlay.LAND_VALUE:
			# Bands match the hover text and the land value tall buildings need.
			var v := values[i]
			var c := OV_RED
			if v >= 0.65:
				c = OV_GREEN
			elif v >= 0.5:
				c = OV_LIGHT_GREEN
			elif v >= 0.35:
				c = OV_YELLOW
			elif v >= 0.2:
				c = OV_ORANGE
			return Color(c, 0.85)
		Overlay.POWER:
			if t == Tile.EMPTY:
				return none
			if zone or service or sim.power_use(i) > 0:
				return Color(OV_YELLOW if power[i] == 1 else OV_RED, 0.9)
			return Color(OV_DARK_YELLOW if power[i] == 1 else OV_GREY, 0.8)
		Overlay.DISTRICTS:
			var d: int = sim.district[i]
			if d == 2:
				return Color(OV_CBD, 0.85)
			if d == 1:
				return Color(OV_CONSERVATION, 0.85)
			if d == Settings.TECH_ZONE:
				return Color(OV_TECH, 0.85)
			return Color(OV_GREY, 0.35) if t != Tile.EMPTY else none
		Overlay.WATER:
			if t == Tile.EMPTY:
				return none
			var wet: PackedByteArray = sim.water_map()
			if zone:
				if sim.needs_water_to_grow(i):
					return Color(OV_RED, 0.9)
				return Color(OV_BLUE if wet[i] == 1 else OV_GREY, 0.9)
			return Color(OV_DARK_BLUE if wet[i] == 1 else OV_GREY, 0.8)
		Overlay.ROADS:
			if t == Tile.ROAD:
				return Color(OV_GREY, 0.8)
			if reach[i] == 1:
				return Color(OV_GREEN, 0.8)
			if sim.has_road_access(i):
				return Color(OV_LIGHT_GREEN, 0.7)
			if zone:
				return Color(OV_RED, 0.9)
			return none
		Overlay.GROWTH:
			if not zone:
				return none
			var state: int = sim.growth_state(i)
			match state:
				Growth.GROWING:
					return Color(OV_GREEN, 0.9)
				Growth.WAITING:
					return Color(OV_YELLOW, 0.9)
				Growth.BLOCKED:
					return Color(OV_RED, 0.9)
				Growth.FULL:
					return Color(OV_BLUE, 0.9)
				Growth.ABANDONED:
					return Color(OV_ABANDONED, 0.95)
		Overlay.SERVICES:
			if service_filter >= 0:
				return _one_service_colour(i, t, zone, service)
			if service:
				return Color(OV_BLUE, 0.95)
			var n: int = sim.services_covering(i)
			var c := OV_RED
			if n == 4:
				c = OV_GREEN
			elif n == 3:
				c = OV_LIGHT_GREEN
			elif n >= 1:
				c = OV_YELLOW
			if zone:
				return Color(c, 0.9)
			if t == Tile.EMPTY or t == Tile.PARK or t == Tile.WOODLAND:
				return Color(c, 0.45) if n > 0 else none
			return none
		Overlay.POLLUTION:
			# Bands match the hover text (simulation.gd pollution_band).
			var band: int = sim.pollution_band(i)
			var bands: Array[Color] = [OV_GREEN, OV_LIGHT_GREEN, OV_YELLOW, OV_ORANGE, OV_RED]
			if t == Tile.EMPTY:
				return Color(bands[band], 0.6) if band > 0 else none
			return Color(bands[band], 0.9)
		Overlay.TRAFFIC:
			# Only the roads, by how congested they are; everything else greyed out.
			# The whole road tile is tinted (busier ones more strongly) so thin roads
			# still read from afar; the road surface itself takes the full colour
			# (road.gdshader).
			if t != Tile.ROAD:
				return none
			var step: int = 0 if sim.traffic_quiet(i) else sim.traffic_band(i) + 1
			return Color(TRAFFIC_COLOURS[step], TRAFFIC_GROUND_ALPHA[step])
	return none


func _one_service_colour(i: int, t: int, zone: bool, service: bool) -> Color:
	# The Services view showing one service (see _service_legend): its cover in
	# greens, the plots that want it and don't have it in red (held back now) or
	# orange, its buildings blue and the other services' buildings grey.
	var s := service_filter
	if service:
		return Color(OV_BLUE, 0.95) if sim.service_of(t) == s else Color(OV_GREY, 0.6)
	var band: int = sim.cover_strength(s, i)
	if zone:
		if band >= 2:
			return Color(OV_GREEN if band == 3 else OV_LIGHT_GREEN, 0.9)
		if sim.service_matters(s, i):
			return Color(OV_RED if sim.service_holds_back(s, i) else OV_ORANGE, 0.92)
		return Color(OV_GREY, 0.45)
	if band >= 2 and (t == Tile.EMPTY or t == Tile.PARK or t == Tile.WOODLAND):
		return Color(OV_GREEN if band == 3 else OV_LIGHT_GREEN, 0.45)
	return Color(0, 0, 0, 0)


func _recolour_buildings() -> void:
	# In an overlay, each building takes its plot's colour; otherwise its own.
	_recolour(walls.multimesh, _wall_owner, _wall_base)
	_recolour(roofs.multimesh, _roof_owner, _roof_base)
	for key: String in _model_groups:
		var group: Dictionary = _model_groups[key]
		_recolour((_model_nodes[key] as MultiMeshInstance3D).multimesh, group["owners"], group["base"])


func _recolour(mm: MultiMesh, owners: PackedInt32Array, base: PackedColorArray) -> void:
	var count := mini(mini(owners.size(), base.size()), mm.instance_count)
	for n in count:
		if overlay == Overlay.NONE:
			mm.set_instance_color(n, base[n])
			continue
		var i := owners[n]
		var c := overlay_image.get_pixel(i % map_w, i / map_w)
		# Building colours are sRGB, but overlay colours go in linear (the shaders
		# convert only when the overlay is off); the image is in sRGB like the ground.
		mm.set_instance_color(n, OV_GREY.srgb_to_linear() if c.a < 0.05 \
			else Color(c.r, c.g, c.b).srgb_to_linear())


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

func height_at(wx: float, wz: float) -> float:
	# Ground height at any point, exactly as the terrain is drawn (the shader
	# lifts the same grid of samples; beyond the last sample it stays level).
	var gx := clampf((wx - _fine_origin.x) / _fine_step, 0.0, _fine_w - 1.0)
	var gz := clampf((wz - _fine_origin.y) / _fine_step, 0.0, _fine_h - 1.0)
	var x0 := mini(floori(gx), _fine_w - 2)
	var z0 := mini(floori(gz), _fine_h - 2)
	var fx := gx - x0
	var fz := gz - z0
	var at := z0 * _fine_w + x0
	var h00 := _fine[at]
	var h10 := _fine[at + 1]
	var h01 := _fine[at + _fine_w]
	var h11 := _fine[at + _fine_w + 1]
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
	for y in map_h:
		for x in map_w:
			if tiles[y * map_w + x] != Tile.ROAD:
				continue
			var c := tile_centre(Vector2i(x, y))
			# Each kind of road has its own width and markings (the shader reads the kind).
			var kind: int = sim.road_kind[y * map_w + x]
			var hw: float = ROAD_HALF_WIDTHS[kind]
			_road_kind_now = kind
			var links: Array[Vector2] = []
			var link_kinds: Array[int] = []
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < map_w and n.y < map_h \
						and tiles[n.y * map_w + n.x] == Tile.ROAD:
					links.append(Vector2(d))
					link_kinds.append(mini(kind, sim.road_kind[n.y * map_w + n.x]))

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
				var crossing := 1.0 if _busy_junction(x, y, tiles) else 0.5
				# Where a side road meets a bigger one, the bigger one has the right of way.
				var widest: int = link_kinds.max()
				var mixed: bool = link_kinds.min() != widest
				for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					var side := Vector2(-d.y, d.x)
					if d in links:
						# Arm into the junction (as wide as the narrower of the two roads):
						# a give-way line, and a zebra crossing just before it where the
						# streets are busy.
						var arm: int = link_kinds[links.find(d)]
						var arm_hw: float = ROAD_HALF_WIDTHS[arm]
						var give := 0.0 if arm == Settings.MOTORWAY or (mixed and arm == widest) else crossing
						_road_kind_now = arm
						_road_path(_line_points(c + d * half, c + d * hw), arm_hw, ROAD_NORMAL, 1.0, 0.0, give,
							ROAD_ARM_END - (half - hw))
						_road_kind_now = kind
						if arm_hw < hw - 0.5 and kind != Settings.MOTORWAY:
							# Kerbs along the square's edge either side of a narrower arm.
							var edge := c + d * (hw - KERB_HALF_WIDTH)
							for s: float in [-1.0, 1.0]:
								_road_path(_line_points(edge + side * s * arm_hw, edge + side * s * hw), KERB_HALF_WIDTH,
									ROAD_KERB, 0.0, 0.08)
					elif kind != Settings.MOTORWAY:
						var edge := c + d * (hw - KERB_HALF_WIDTH)
						var along := side * hw
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


func _busy_junction(x: int, y: int, tiles: PackedByteArray) -> bool:
	# Zebra crossings where people walk: by shops, offices, flats and public
	# buildings. Quiet suburbs (houses, parks, open land) only get give-way lines.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or ny < 0 or nx >= map_w or ny >= map_h:
				continue
			var k := ny * map_w + nx
			var t: int = tiles[k]
			if t == Tile.SHOPS or t == Tile.OFFICES or sim.is_service(t) or (t >= Tile.LIBRARY and t <= Tile.STATION):
				return true
			if t == Tile.HOMES and (sim.density[k] >= 1 or sim.district[k] == 2):
				return true
	return false


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


var _road_kind_now := 0     # the kind of road _road_path is drawing (0 road, 1 avenue, 2 motorway)


func _road_path(points: PackedVector2Array, half_width: float, across: Vector2,
		centre_line: float, lift: float = 0.0, crossing: float = 0.0, start_dist: float = 0.0) -> void:
	# A ribbon of road along the points. "across" is the texture position at the
	# left and right edges: (0, 1) = full road with pavements, (0.5, 0.5) = plain
	# tarmac, (0, 0) = pavement only. The kind of road goes to the shader with the
	# centre line flag (UV2.x = centre line + 2 x kind).
	var count := points.size()
	var start := _rv.size()
	var dist := start_dist
	# Wide roads are cut into strips across as well, so they follow the ground
	# (two edges 28 m apart would let a rise in between poke through).
	var strips := 1 if half_width <= ROAD_HALF_WIDTH else ceili(half_width / 2.5)
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
		for n in strips + 1:
			var s := float(n) / strips
			var q: Vector2 = points[k] + side * (s * 2.0 - 1.0)
			_rv.append(Vector3(q.x, maxf(height_at(q.x, q.y), 0.0) + 0.35 + lift, q.y))
			_rn.append(Vector3.UP)
			_ruv.append(Vector2(lerpf(across.x, across.y, s), dist))
			_ruv2.append(Vector2(centre_line + 2.0 * _road_kind_now, crossing))
	var row := strips + 1
	for k in count - 1:
		for n in strips:
			var a := start + k * row + n
			_ri.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])   # clockwise from above


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
				if nt != Tile.POWER_LINE and not sim.makes_power(nt):
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
				if n.x < 0 or n.y < 0 or not sim.makes_power(tiles[n.y * map_w + n.x]):
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
		if _is_road(Vector2i(x, y) + d) and _road_kind(Vector2i(x, y) + d) != Settings.MOTORWAY:
			return d                        # (nothing faces a motorway)
	return Vector2i(0, 1)


func _is_road(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < map_w and t.y < map_h \
		and sim.tiles[t.y * map_w + t.x] == Tile.ROAD


func _road_kind(t: Vector2i) -> int:
	# 0 road, 1 avenue, 2 motorway (only ask about road tiles).
	return sim.road_kind[t.y * map_w + t.x]


func _street_reach(i: int, front: Vector2i) -> float:
	# How far a plot's front can come forward into the road tile, so buildings
	# sit by the pavement instead of behind a wide strip of grass. Only where the
	# road runs straight past the plot (not on bends, where plots could collide).
	var tile := Vector2i(i % map_w, i / map_w)
	var road := tile + front
	if not _is_road(road) or _road_kind(road) != 0:
		return 0.0                          # (avenues and motorways fill more of their tile: plots keep to their own)
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
	# Sit on the lowest corner so nothing floats on a slope (and note the highest).
	var base := INF
	var top := -INF
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			var q: Vector2 = mid + across * (w * sx) + away * (d * sz)
			var corner := height_at(q.x, q.y)
			base = minf(base, corner)
			top = maxf(top, corner)
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
	var model := _model_for(style, w, h, roof_h)
	if model != "":
		_add_model(model, spot, w, d, h + roof_h, colour, roof_colour)
		return
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
	var b3 := Basis(x_axis * w, Vector3.UP * h, z_axis * d)
	wall_list.append([Transform3D(b3, pos), colour, Color(w, h, d, style)])
	if roof_h > 0.0:
		# Pitched roof with a small overhang, ridge running along the street.
		var roof_b3 := Basis(x_axis * (w + 0.8), Vector3.UP * roof_h, z_axis * (d + 1.0))
		roof_list.append([Transform3D(roof_b3, pos + Vector3.UP * h), roof_colour])


# --- Detailed building models ---

func _load_models(stone: Texture2D, slate: Texture2D) -> void:
	# Load each .glb and give it our shader. The model's parts (its materials:
	# stone, roof, glass...) are joined into one surface that tells the shader
	# each vertex's part, so a model is one draw, not one per part.
	var mat := ShaderMaterial.new()
	mat.shader = MODEL_SHADER
	if stone:
		mat.set_shader_parameter("use_wall_tex", true)
		mat.set_shader_parameter("wall_tex", stone)
		mat.set_shader_parameter("wall_average", _average_colour(stone))
	if slate:
		mat.set_shader_parameter("use_roof_tex", true)
		mat.set_shader_parameter("roof_tex", slate)
		mat.set_shader_parameter("roof_average", _average_colour(slate))
	_model_materials.append(mat)
	for model_name: String in _all_model_names():
		var path := MODEL_DIR + model_name + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var root := scene.instantiate()
		var mesh := _first_mesh(root)
		root.free()
		if mesh == null:
			continue
		_models[model_name] = _one_surface(mesh, mat)
	if _models.is_empty():
		push_warning("No building models found in %s: using simple blocks." % MODEL_DIR)


func _one_surface(mesh: ArrayMesh, mat: Material) -> Mesh:
	# All of a model's surfaces joined into one, each vertex carrying its part's
	# number in UV2.x (model.gdshader reads it; see MODEL_PARTS). With a surface
	# per part, the town's models came to thousands of draws a frame, and those,
	# not triangles, were the slowest thing on screen. Its detail levels (fewer
	# triangles far away) are made again for the joined mesh.
	var with_colour := true
	for s in mesh.get_surface_count():
		with_colour = with_colour and mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR] != null
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var parts := PackedVector2Array()
	var indices := PackedInt32Array()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var old := mesh.surface_get_material(s)
		var part := maxi(MODEL_PARTS.find(old.resource_name if old else ""), 0)   # (unknown: stone)
		var base := verts.size()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		verts.append_array(v)
		normals.append_array(nrm)
		if with_colour:
			var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			colours.append_array(col)
		for n in v.size():
			parts.append(Vector2(part, 0.0))
		if arrays[Mesh.ARRAY_INDEX] == null:
			for n in v.size():
				indices.append(base + n)
		else:
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for n: int in idx:
				indices.append(base + n)
	var joined := []
	joined.resize(Mesh.ARRAY_MAX)
	joined[Mesh.ARRAY_VERTEX] = verts
	joined[Mesh.ARRAY_NORMAL] = normals
	if with_colour:
		joined[Mesh.ARRAY_COLOR] = colours
	joined[Mesh.ARRAY_TEX_UV2] = parts
	joined[Mesh.ARRAY_INDEX] = indices
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, joined, [], {}, mat)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


func _all_model_names() -> Array[String]:
	# Every model file to look for: each size, its variants, and the classical
	# blocks' shopfront and bay-window versions.
	var names: Array[String] = []
	for base: String in MODEL_DIMS:
		if MODEL_VARIANTS.has(base):
			for v: String in MODEL_VARIANTS[base]:
				names.append(v)
		else:
			names.append(base)
		if base.begins_with("classical"):
			names.append(base + "_shops")
			names.append(base + "_bays")
	return names


func _model_dims(model_name: String) -> Vector4:
	# A variant shares its size with the model it's a version of.
	var base := model_name.trim_suffix("_shops").trim_suffix("_bays").trim_suffix("_b").trim_suffix("_c")
	var dims: Vector4 = MODEL_DIMS.get(base, MODEL_DIMS.get(model_name, Vector4(1, 1, 1, 0)))
	return dims


func _first_mesh(node: Node) -> ArrayMesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
		return (node as MeshInstance3D).mesh as ArrayMesh
	for child in node.get_children():
		var found := _first_mesh(child)
		if found:
			return found
	return null


func _model_for(style: int, w: float, h: float, roof_h: float) -> String:
	# Which model (if any) fits a planned block.
	var pick := ""
	if style == STYLE_HOUSE:
		if h <= 3.6:
			pick = "bungalow"
		elif w <= 9.5:
			pick = "villa"
		elif w <= 17.0:
			pick = "terrace"
	elif style == STYLE_FLATS and roof_h > 0.0:
		var storeys := roundi((h - 0.5) / 3.0)
		if storeys == 3:
			pick = "tenement3"
		elif storeys == 4:
			pick = "tenement4"
	elif style == STYLE_INDUSTRY and roof_h > 0.0:
		pick = "shed"
	elif style == STYLE_SHOP:
		if roof_h > 0.0 and h <= 8.0:
			pick = "shop2"
		elif roof_h == 0.0 and h <= 5.0:
			pick = "shop1"
		elif roof_h == 0.0:
			var floors := roundi((h - 0.6) / 3.2)
			if floors >= 2 and floors <= 4:
				pick = "shopflats%d" % floors
	if MODEL_VARIANTS.has(pick):
		for v: String in MODEL_VARIANTS[pick]:
			if _models.has(v):
				return pick
		return ""
	return pick if _models.has(pick) else ""


func _add_model(model_name: String, spot: Dictionary, w: float, d: float, total_h: float, colour: Color,
		roof_colour: Color) -> void:
	# The model stretched to the block: front to the street, base on the ground.
	# Where there are several designs of this size, one is picked by position.
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
	var variety := fposmod(sin(pos.x * 12.9898 + pos.z * 78.233) * 43758.5453, 1.0)   # door colours etc.
	if MODEL_VARIANTS.has(model_name):
		var choices: Array = []
		for v: String in MODEL_VARIANTS[model_name]:
			if _models.has(v):
				choices.append(v)
		if not choices.is_empty():
			model_name = choices[int(fposmod(variety * 7.31, 1.0) * choices.size())]
	var dims := _model_dims(model_name)
	var basis := Basis(x_axis * (w / dims.x), Vector3.UP * (total_h / (dims.z + dims.w)), z_axis * (d / dims.y))
	_model_items.append([model_name, Transform3D(basis, pos), colour,
		Color(roof_colour.r, roof_colour.g, roof_colour.b, variety), _current_owner])


func _model_total(model_name: String) -> float:
	# A model's full height as built (used to place it without stretching).
	var dims := _model_dims(model_name)
	return dims.z + dims.w


func _raised(spot: Dictionary, up: float) -> Dictionary:
	# The same spot, lifted (for stacking storeys).
	var copy := spot.duplicate()
	var pos: Vector3 = spot["pos"]
	copy["pos"] = pos + Vector3.UP * up
	return copy


func _fill_models() -> void:
	# Group the planned models by kind and 400 m square, one MultiMesh each.
	var groups := {}
	for item: Array in _model_items:
		var xf: Transform3D = item[1]
		var key := "%s|%d|%d" % [item[0], floori(xf.origin.x / MODEL_CHUNK), floori(xf.origin.z / MODEL_CHUNK)]
		if not groups.has(key):
			groups[key] = []
		var list: Array = groups[key]
		list.append(item)
	for key: String in _model_nodes:
		if not groups.has(key):
			var idle: MultiMeshInstance3D = _model_nodes[key]
			idle.multimesh.instance_count = 0
	_model_groups.clear()
	for key: String in groups:
		var list: Array = groups[key]
		var first: Array = list[0]
		var model_name: String = first[0]
		if not _model_nodes.has(key):
			var node := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _models[model_name]
			node.multimesh = mm
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(node)
			_model_nodes[key] = node
		var target: MultiMesh = (_model_nodes[key] as MultiMeshInstance3D).multimesh
		target.instance_count = list.size()
		var owners := PackedInt32Array()
		var base := PackedColorArray()
		for n in list.size():
			var item: Array = list[n]
			target.set_instance_transform(n, item[1])
			target.set_instance_color(n, item[2])
			target.set_instance_custom_data(n, item[3])
			owners.append(item[4])
			base.append(item[2])
		_model_groups[key] = {"owners": owners, "base": base}


# --- Lot details: flat paving, small props and parked cars ---

func _slab(i: int, front: Vector2i, along: float, back: float, w: float, d: float,
		colour: Color, lift: float = 0.0) -> void:
	# A flat surface (driveway, car park, yard), 15 cm proud of the ground.
	var spot := _place(i, front, along, back, w, d)
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	# Thick enough to clear the ground on a slope (like a levelled car park).
	var b3 := Basis(x_axis * w, Vector3.UP * (float(spot["rise"]) + 0.45 + lift), z_axis * d)
	_paving_items.append([Transform3D(b3, spot["pos"]), Color(colour, _surface_of(colour))])


func _surface_of(colour: Color) -> float:
	# What a slab is made of, for the paving shader (alpha: see paving.gdshader).
	if colour == CAR_PARK:
		return 0.8
	if colour == PAVEMENT:
		return 0.6
	if colour == DRIVEWAY:
		return 0.4
	if colour == CONCRETE or colour == YARD or colour == FOUNDATION:
		return 0.2
	return 1.0


func _prop(i: int, front: Vector2i, along: float, back: float, w: float, d: float, h: float,
		colour: Color, lift: float = 0.0) -> void:
	# A box standing on the plot (hedge, wall, container), or held lift metres up.
	# (The same spot as _place gives, worked out more cheaply: there are a lot of these.)
	var mid := _plot_point(i, front, along, back + d * 0.5)
	var fwd := Vector2(front)
	var x_axis := Vector3(-fwd.y, 0.0, fwd.x)
	var z_axis := Vector3(-fwd.x, 0.0, -fwd.y)
	var pos := Vector3(mid.x, maxf(height_at(mid.x, mid.y), 0.0) - 0.1 + lift, mid.y)
	_prop_items.append([Transform3D(Basis(x_axis * w, Vector3.UP * h, z_axis * d), pos), colour])


func _plot_point(i: int, front: Vector2i, along: float, back: float) -> Vector2:
	# World x, z of a point on a plot (along the street, back from its front), as _place.
	var fwd := Vector2(front)
	var front_edge := tile_centre(Vector2i(i % map_w, i / map_w)) + fwd * (cell * 0.5 + _street_reach(i, front))
	return front_edge + Vector2(-fwd.y, fwd.x) * along - fwd * back


func _parked_car(i: int, front: Vector2i, along: float, back: float, nose_to_street: bool,
		rng: RandomNumberGenerator, paint_over: Color = Color(0, 0, 0, 0)) -> void:
	var spot := _place(i, front, along, back, 1.9, 4.4)
	var z_axis: Vector3 = spot["z"]
	var facing := Basis.looking_at(-z_axis if nose_to_street else z_axis, Vector3.UP)
	var base: Vector3 = spot["pos"]
	base.y = maxf(float(spot["ground"]), base.y + float(spot["rise"])) + 0.15
	var paint: Color = paint_over
	if paint_over.a == 0.0:
		paint = CAR_PAINT[rng.randi_range(0, CAR_PAINT.size() - 1)]
	_parked_items.append([
		Transform3D(facing * Basis.from_scale(Vector3(1.85, 1.1, 4.3)), base + Vector3.UP * 0.75),
		paint,
		Transform3D(facing * Basis.from_scale(Vector3(1.65, 0.7, 2.3)), base + Vector3.UP * 1.6 + facing.z * 0.35)])


func _parking_bays(i: int, front: Vector2i, from: float, to: float, chance: float,
		rng: RandomNumberGenerator) -> void:
	# Rows of marked bays across the plot: each double row is 2 x 5 m bays plus
	# a 6 m aisle. Some bays have a car in them.
	var row_back := from
	var facing_street := true
	var row := 0
	while row_back + 5.0 <= to:
		for k in 13:
			var bay := -16.8 + k * 2.8
			_slab(i, front, bay - 1.4, row_back, 0.12, 4.8, BAY_LINE, 0.03)
			if rng.randf() < chance:
				_parked_car(i, front, bay, row_back + 0.2, facing_street, rng)
		_slab(i, front, 16.8 + 1.4, row_back, 0.12, 4.8, BAY_LINE, 0.03)
		# A planted island at each end of the row, a tree in every other one.
		for end: float in [-20.0, 20.0]:
			_prop(i, front, end, row_back + 0.3, 3.2, 4.4, 0.45, HEDGE_GREEN)
			if (row + int(end > 0.0)) % 2 == 0:
				_plant(i, front, end, row_back + 2.5, rng.randf_range(5.0, 7.5), TreeKind.ORNAMENTAL, rng)
		row += 1
		row_back += 5.0 if facing_street else 11.0
		facing_street = not facing_street


func _front_panel(spot: Dictionary, d: float, along: float, up: float, w: float, h: float,
		colour: Color, wall_list: Array) -> void:
	# A flat painted panel on a block's street face: a door, a sign, a cross.
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
	var at: Vector3 = pos + x_axis * along + Vector3.UP * up - z_axis * (d * 0.5 + 0.12)
	wall_list.append([Transform3D(Basis(x_axis * w, Vector3.UP * h, z_axis * 0.25), at), colour,
		Color(w, h, 0.25, STYLE_PAINT)])


func _roof_panel(spot: Dictionary, height: float, along: float, back: float, w: float, d: float,
		colour: Color, wall_list: Array) -> void:
	# A thin flat panel lying on a flat roof (helipad markings).
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
	var at: Vector3 = pos + x_axis * along + z_axis * back + Vector3.UP * height
	wall_list.append([Transform3D(Basis(x_axis * w, Vector3.UP * 0.3, z_axis * d), at), colour,
		Color(w, 0.3, d, STYLE_PAINT)])


func _plan_service(i: int, t: int, wall_list: Array, roof_list: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 6151 + t
	var front := _frontage(i)
	var depth := _depth(i, front)
	_slab(i, front, 0.0, 0.0, 49.0, 3.0, PAVEMENT)
	match t:
		Tile.POLICE:
			# A sandstone station with a blue sign over the door; patrol cars in the yard.
			# (A navy slate roof and a blue band round the building, so it reads from afar.)
			var spot := _place(i, front, -7.0, 4.0, 30.0, 15.0)
			_classical_block(spot, 30.0, 15.0, 3, BLONDE_SANDSTONE, false, false, wall_list, roof_list, true,
				POLICE_ROOF)
			_front_panel(spot, 15.0, 0.0, 0.0, 2.8, 3.2, POLICE_BLUE.darkened(0.35), wall_list)
			_front_panel(spot, 15.0, 0.0, 3.3, 9.0, 0.8, POLICE_BLUE, wall_list)
			var wing := _place(i, front, -12.0, 19.0, 18.0, 12.0)
			_add_block(wing, 18.0, 12.0, 7.0, BLONDE_SANDSTONE, STYLE_CLASSICAL, 0.0, SLATE, wall_list, roof_list)
			var wing_pos: Vector3 = wing["pos"]
			_box_item(wall_list, wing_pos + Vector3.UP * 5.6, wing["x"], wing["z"], Vector3(18.3, 0.8, 12.3),
				POLICE_BLUE, STYLE_PAINT)
			_flag(_place(i, front, 10.0, 1.5, 1.0, 1.0), 9.0, SALTIRE_BLUE)
			_slab(i, front, 16.0, 3.0, 16.0, depth - 5.0, CAR_PARK)
			for k in 4:
				_parked_car(i, front, 12.5 + (k % 2) * 7.0, 6.0 + (k / 2) * 8.0, true, rng, PATROL_WHITE)
			_prop(i, front, -7.0, 21.0, 30.0, 0.8, 1.2, _hedge_colour(rng))
		Tile.FIRE:
			# Red sandstone with three engine bays, an apron, a drill tower and a yard.
			var spot := _place(i, front, -5.0, 8.0, 34.0, 18.0)
			if _models.has("fire_station"):
				_add_model("fire_station", spot, 34.0, 18.0, _model_total("fire_station"), RED_SANDSTONE, FIRE_RED)
			else:
				_add_block(spot, 34.0, 18.0, 9.5, RED_SANDSTONE, STYLE_FLATS, 0.0, SLATE, wall_list, roof_list)
				for k in 3:
					_front_panel(spot, 18.0, -11.0 + k * 11.0, 0.0, 8.0, 5.2, FIRE_RED, wall_list)
			_slab(i, front, -5.0, 3.0, 34.0, 5.0, CONCRETE)
			var tower := _place(i, front, 19.0, 12.0, 6.0, 6.0)
			if _models.has("fire_tower"):
				_add_model("fire_tower", tower, 6.0, 6.0, _model_total("fire_tower"), RED_SANDSTONE, SLATE)
			else:
				_add_block(tower, 6.0, 6.0, 22.0, RED_SANDSTONE, STYLE_FLATS, 0.0, SLATE, wall_list, roof_list)
			_prop(i, front, -12.0, 30.0, 2.6, 8.5, 3.2, FIRE_RED)       # a fire engine
			_prop(i, front, -6.0, 30.0, 2.6, 8.5, 3.2, FIRE_RED)
		Tile.SCHOOL:
			# A Victorian sandstone school with a slate roof, a playground and a playing field.
			var spot := _place(i, front, -4.0, 4.0, 38.0, 13.0)
			_flag(_place(i, front, 19.0, 1.0, 0.2, 0.2), 8.0, SALTIRE_BLUE)
			if _models.has("school"):
				# The model has its own porch and wings standing forward of the front.
				_add_model("school", spot, 38.0, 13.0, _model_total("school"), RED_SANDSTONE, SLATE)
			else:
				_add_block(spot, 38.0, 13.0, 9.0, RED_SANDSTONE, STYLE_CLASSICAL, 4.5, SLATE, wall_list, roof_list)
				var porch := _place(i, front, -4.0, 2.2, 8.0, 3.0)
				_add_block(porch, 8.0, 3.0, 10.5, RED_SANDSTONE, STYLE_CLASSICAL, 3.0, SLATE, wall_list, roof_list)
			# (The playground and the playing field with its markings are painted
			# by the shader.) Goals at the ends of the pitch.
			for end: float in [-19.0, 19.0]:
				_prop(i, front, end, (21.0 + depth - 4.0) * 0.5 - 3.6, 0.12, 7.3, 0.12, WHITE_RENDER, 2.35)
				for post: float in [-3.6, 3.6]:
					_prop(i, front, end, (21.0 + depth - 4.0) * 0.5 + post, 0.12, 0.12, 2.4, WHITE_RENDER)
			# Railings along the street and a few trees round the field.
			_prop(i, front, 0.0, 0.2, 48.0, 0.1, 1.4, CHARCOAL)
			for k in 4:
				var at := _place(i, front, -21.5 + k * 14.3, depth - 3.0, 1.0, 1.0)
				var pos: Vector3 = at["pos"]
				_extra_trees.append([Vector2(pos.x, pos.z), rng.randf_range(8.0, 12.0), TreeKind.BROADLEAF])
		Tile.HOSPITAL:
			# A modern white block with a glass entrance, a red cross, a helipad on the
			# roof, and ambulances by the door.
			var floors := 6
			var h: float = floors * 3.2 + 0.6
			var main := _place(i, front, -6.0, 13.0, 34.0, 22.0)
			if _models.has("hospital"):
				# The model has the red cross on its front (in the accent colour).
				_add_model("hospital", main, 34.0, 22.0, _model_total("hospital"), MODERN_WHITE, CROSS_RED)
				h += 0.1    # the helipad sits on its roof, inside the parapet
			else:
				_add_block(main, 34.0, 22.0, h, MODERN_WHITE, STYLE_MODERN, 0.0, SLATE, wall_list, roof_list)
				_front_panel(main, 22.0, 11.0, h - 6.0, 1.3, 4.2, CROSS_RED, wall_list)
				_front_panel(main, 22.0, 11.0, h - 4.55, 4.2, 1.3, CROSS_RED, wall_list)
			var entrance := _place(i, front, -6.0, 4.0, 16.0, 9.0)
			_add_block(entrance, 16.0, 9.0, 5.0, GLASS_FRAME, STYLE_GLASS, 0.0, SLATE, wall_list, roof_list)
			_front_panel(entrance, 9.0, 0.0, 5.0, 18.0, 0.5, TRIM, wall_list)      # canopy edge
			_roof_panel(main, h, 0.0, 0.0, 14.0, 14.0, CHARCOAL, wall_list)      # helipad
			_roof_panel(main, h + 0.05, -2.5, 0.0, 1.0, 6.0, WHITE_RENDER, wall_list)
			_roof_panel(main, h + 0.05, 2.5, 0.0, 1.0, 6.0, WHITE_RENDER, wall_list)
			_roof_panel(main, h + 0.05, 0.0, 0.0, 4.0, 1.0, WHITE_RENDER, wall_list)
			_slab(i, front, 18.5, 3.0, 12.0, depth - 5.0, CAR_PARK)
			_prop(i, front, 15.5, 5.0, 2.3, 6.0, 2.8, AMBULANCE_YELLOW)
			_prop(i, front, 21.0, 5.0, 2.3, 6.0, 2.8, AMBULANCE_YELLOW)
			# The ambulance bays, boxed in yellow; trees on the lawn round the building.
			for along: float in [15.5, 21.0]:
				_slab(i, front, along - 1.7, 4.2, 0.15, 7.6, AMBULANCE_YELLOW, 0.03)
				_slab(i, front, along + 1.7, 4.2, 0.15, 7.6, AMBULANCE_YELLOW, 0.03)
			_slab(i, front, 18.25, 11.7, 7.0, 0.15, AMBULANCE_YELLOW, 0.03)
			for k in 3:
				_plant(i, front, -21.0 + k * 7.5, depth - 6.0, rng.randf_range(7.0, 10.0), TreeKind.BROADLEAF, rng)
			for k in 3:
				_parked_car(i, front, 15.5 + k * 3.0, 16.0, true, rng)
		Tile.POLICE_OFFICE:
			# A two-storey sandstone office with the navy roof and blue sign of the
			# big station, a blue lamp by the door, one patrol car, a lawn and a hedge.
			var spot := _place(i, front, -8.0, 4.0, 18.0, 11.0)
			_classical_block(spot, 18.0, 11.0, 2, BLONDE_SANDSTONE, false, false, wall_list, roof_list, true,
				POLICE_ROOF)
			_front_panel(spot, 11.0, 0.0, 0.0, 2.4, 3.0, POLICE_BLUE.darkened(0.35), wall_list)
			_front_panel(spot, 11.0, 0.0, 3.2, 7.0, 0.7, POLICE_BLUE, wall_list)
			_prop(i, front, -3.0, 2.6, 0.16, 0.16, 3.0, CHARCOAL)
			_prop(i, front, -3.0, 2.6, 0.5, 0.5, 0.6, POLICE_BLUE, 3.0)
			_slab(i, front, 14.0, 3.0, 14.0, 20.0, CAR_PARK)
			_parked_car(i, front, 11.0, 6.0, true, rng, PATROL_WHITE)
			_parked_car(i, front, 16.0, 6.0, true, rng)
			_prop(i, front, -8.0, 17.0, 32.0, 0.8, 1.2, _hedge_colour(rng))
			for k in 3:
				_plant(i, front, -19.0 + k * 16.0, depth - 8.0, rng.randf_range(7.0, 10.0), TreeKind.BROADLEAF, rng)
		Tile.FIRE_SMALL:
			# A two-bay red sandstone shed with red doors, an apron and one engine.
			var spot := _place(i, front, -6.0, 8.0, 20.0, 14.0)
			_add_block(spot, 20.0, 14.0, 6.6, RED_SANDSTONE, STYLE_FLATS, 2.2, SLATE, wall_list, roof_list)
			for k in 2:
				_front_panel(spot, 14.0, -4.6 + k * 9.2, 0.0, 7.0, 4.8, FIRE_RED, wall_list)
			_slab(i, front, -6.0, 3.0, 20.0, 5.0, CONCRETE)
			var hut := _place(i, front, 10.0, 10.0, 8.0, 9.0)
			_add_block(hut, 8.0, 9.0, 3.6, RED_SANDSTONE, STYLE_FLATS, 1.6, SLATE, wall_list, roof_list)
			_prop(i, front, -10.5, 24.0, 2.6, 8.5, 3.2, FIRE_RED)       # the fire engine, out the back
			_prop(i, front, 18.0, 6.0, 1.6, 1.6, 9.0, RED_SANDSTONE)     # a short hose tower
		Tile.CLINIC:
			# A low white health centre with a glass porch and a green cross, a small
			# car park, a lawn and trees.
			var main := _place(i, front, -7.0, 7.0, 28.0, 14.0)
			_add_block(main, 28.0, 14.0, 7.0, MODERN_WHITE, STYLE_MODERN, 0.0, SLATE, wall_list, roof_list)
			_front_panel(main, 14.0, 9.0, 3.6, 0.9, 2.7, CLINIC_GREEN, wall_list)
			_front_panel(main, 14.0, 9.0, 4.5, 2.7, 0.9, CLINIC_GREEN, wall_list)
			var porch := _place(i, front, -9.0, 4.0, 8.0, 3.2)
			_add_block(porch, 8.0, 3.2, 3.6, GLASS_FRAME, STYLE_GLASS, 0.0, SLATE, wall_list, roof_list)
			_front_panel(porch, 3.2, 0.0, 3.6, 9.0, 0.4, TRIM, wall_list)
			_slab(i, front, 16.0, 3.0, 14.0, 22.0, CAR_PARK)
			for k in 3:
				_parked_car(i, front, 11.5 + k * 4.0, 6.0, true, rng)
			_prop(i, front, 16.0, 16.0, 2.3, 6.0, 2.8, AMBULANCE_YELLOW)
			_prop(i, front, -7.0, 23.0, 30.0, 0.8, 1.2, _hedge_colour(rng))
			for k in 3:
				_plant(i, front, -19.0 + k * 16.0, depth - 8.0, rng.randf_range(7.0, 10.0), TreeKind.BROADLEAF, rng)


const POLICE_ROOF := Color(0.17, 0.24, 0.40)    # navy slate
const CLINIC_GREEN := Color(0.10, 0.55, 0.30)
const SALTIRE_BLUE := Color(0.0, 0.37, 0.72)
const COPPER_GREEN := Color(0.40, 0.64, 0.54)    # weathered copper domes and spires


func _flag(spot: Dictionary, tall: float, colour: Color) -> void:
	# A white flagpole with a flag flying from it (drawn with the chimneys and props).
	var pos: Vector3 = spot["pos"]
	var x_axis: Vector3 = spot["x"]
	_cylinder(_spire_items, pos, 0.12, tall, WHITE_RENDER)
	_box_item(_prop_items, pos + Vector3.UP * (tall - 1.4) + x_axis * 1.1, x_axis, spot["z"],
		Vector3(2.2, 1.4, 0.06), colour)


func _dome(at: Vector3, radius: float, colour: Color) -> void:
	# A copper dome on a drum, stepped like a dome, with a lantern on top.
	_cylinder(_spire_items, at, radius, radius * 0.7, colour.darkened(0.25))
	var up := radius * 0.7
	for k in 3:
		var r: float = radius * (0.95 - k * 0.27)
		var h: float = radius * (0.38 - k * 0.06)
		_cylinder(_spire_items, at + Vector3.UP * up, r, h, colour)
		up += h
	_cylinder(_spire_items, at + Vector3.UP * up, radius * 0.16, radius * 0.5, WHITE_RENDER)


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
		Tile.OFFICES:
			_plan_offices(i, lv, front, rng, wall_list, roof_list)
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
		var stone: Color = _house_colour(rng, i)
		var terrace_roof := _house_roof(rng, i)
		for along: float in [-15.5, 0.0, 15.5]:
			var spot := _place(i, side, along, 4.0, 15.0, 8.5)
			_add_block(spot, 15.0, 8.5, 6.2, stone, STYLE_HOUSE, 3.2, terrace_roof, wall_list, roof_list)
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
			_add_block(spot, w, d, 5.6 if rng.randf() < 0.8 else 3.2, _house_colour(rng, i), STYLE_HOUSE,
				rng.randf_range(2.8, 3.6), _house_roof(rng, i), wall_list, roof_list)
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
	if t == Tile.OFFICES:
		# Sandstone chambers along this street too.
		for along: float in [-12.5, 12.5]:
			var spot := _place(i, side, along, 3.0, 21.0, 13.0)
			_classical_block(spot, 21.0, 13.0, clampi(lv + 1, 2, 4), _classical_stone(rng),
				false, false, wall_list, roof_list)
		return
	# Flats or shops along the street: storeys follow the plot's level.
	var storeys := 3
	var colour := _tenement_stone(rng, i)
	var style := STYLE_FLATS
	var roof_h := 4.5
	if t == Tile.SHOPS:
		style = STYLE_SHOP
		colour = _pick(rng, SHOP_COLOURS)
		storeys = 2 if lv == 1 else 3
		roof_h = 0.0
	for along: float in [-12.5, 12.5]:
		var spot := _place(i, side, along, 3.0, 22.0, 13.0)
		_add_block(spot, 22.0, 13.0, storeys * 3.1 + 0.5, colour, style, roof_h, SLATE, wall_list, roof_list)


func _plan_site(i: int, t: int, wall_list: Array) -> void:
	# A zoned plot waiting to grow: hoarding round it, foundations, a site cabin,
	# piles of materials and sometimes a tower crane.
	# The ground is churned earth with a hard-core track in from the street
	# (painted by the shader). Hoarding in the zone's colour, so zones still read.
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 4241 + t
	var front := _frontage(i)
	var depth := _depth(i, front)
	var zone: Color = ZONE_TINTS[t]
	var panel := HOARDING.lerp(zone, 0.55)
	var dens: int = 1 if t == Tile.INDUSTRY else int(sim.density[i])
	_prop(i, front, -5.75, 1.0, 34.5, 0.2, 2.2, panel)                 # front hoarding, a gate for the track
	_prop(i, front, 20.0, 1.0, 6.0, 0.2, 2.2, panel)
	_prop(i, front, -23.0, 1.0, 0.2, depth - 3.0, 2.2, panel)
	_prop(i, front, 23.0, 1.0, 0.2, depth - 3.0, 2.2, panel)
	_prop(i, front, 0.0, depth - 2.0, 46.0, 0.2, 2.2, panel)
	# Foundations, and the building starting to rise on them.
	_slab(i, front, -4.0, 6.0, 30.0, 16.0, FOUNDATION)
	if t == Tile.HOMES and dens == 0:
		# Houses: brick walls part-built on each footprint.
		for k in 3:
			var at := -14.0 + k * 10.0
			var wall_h := rng.randf_range(0.8, 2.6)
			_prop(i, front, at, 8.0, 7.5, 0.3, wall_h, BRICK, 0.45)
			_prop(i, front, at, 15.5, 7.5, 0.3, wall_h, BRICK, 0.45)
			_prop(i, front, at - 3.6, 8.0, 0.3, 7.8, wall_h, BRICK, 0.45)
			_prop(i, front, at + 3.6, 8.0, 0.3, 7.8, wall_h * 0.6, BRICK, 0.45)
	else:
		# A concrete (or for industry, steel) frame going up, wrapped in scaffold.
		var floors: int = 1 + dens + rng.randi_range(0, 1)
		var frame_colour: Color = Color(0.45, 0.30, 0.22) if t == Tile.INDUSTRY else CONCRETE
		for k in 6:
			for r in 3:
				_prop(i, front, -18.0 + k * 5.6, 7.0 + r * 6.5, 0.45, 0.45, floors * 3.3, frame_colour, 0.45)
		for f in floors:
			_prop(i, front, -4.0, 6.5, 30.0, 15.0, 0.3, frame_colour.lightened(0.1), 0.45 + (f + 1) * 3.3 - 0.3)
		var top: float = floors * 3.3 + 1.5
		for k in 7:
			_prop(i, front, -19.2 + k * 5.2, 5.4, 0.08, 0.08, top, SCAFFOLD, 0.45)
		for f in floors + 1:
			_prop(i, front, -4.0, 5.0, 31.5, 0.9, 0.08, SCAFFOLD_BOARD, 0.45 + f * 3.3 + 1.2)
	# A site cabin by the gate, a portable toilet, a skip, pallets of bricks and blocks, timber.
	var cabin := _place(i, front, 19.5, 4.0, 6.0, 2.6)
	var cx: Vector3 = cabin["x"]
	var cz: Vector3 = cabin["z"]
	wall_list.append([Transform3D(Basis(cx * 6.0, Vector3.UP * 2.7, cz * 2.6), cabin["pos"]),
		SITE_CABIN, Color(6.0, 2.7, 2.6, STYLE_PLANT)])
	_prop(i, front, 21.5, 8.0, 1.1, 1.1, 2.3, Color(0.15, 0.35, 0.70))
	_prop(i, front, 19.0, depth - 9.0, 1.9, 3.8, 1.3, CRANE_YELLOW)
	for k in 4:
		_prop(i, front, -18.0 + k * 1.5, 25.5, 1.2, 1.0, 0.9, [BRICK, CONCRETE][k % 2])
	_prop(i, front, 2.0, 26.0, 5.0, 1.2, 0.6, TIMBER)
	_prop(i, front, rng.randf_range(-15.0, 0.0), rng.randf_range(30.0, depth - 10.0), 3.5, 3.5, 1.1, SAND_PILE)
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


func _plan_empty(i: int, t: int) -> void:
	# A zoned plot with nothing happening yet: rough ground (the shader draws it,
	# with a line in the zone's colour round the edge), a surveyor's peg in the
	# zone colour at each corner and a "plot available" board by the street.
	var front := _frontage(i)
	var depth := _depth(i, front)
	var zone: Color = ZONE_TINTS[t]
	for corner: Vector2 in [Vector2(-23.2, 1.0), Vector2(23.2, 1.0), Vector2(-23.2, depth - 1.6),
			Vector2(23.2, depth - 1.6)]:
		_prop(i, front, corner.x, corner.y, 0.35, 0.35, 1.3, zone)
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 3373 + t
	var along := rng.randf_range(-16.0, 16.0)
	for post: float in [-1.1, 1.1]:
		_prop(i, front, along + post, 1.6, 0.14, 0.14, 2.6, CHARCOAL)
	var board := _place(i, front, along, 1.5, 3.0, 0.12)
	var board_pos: Vector3 = board["pos"]
	board_pos.y = float(board["ground"]) + 1.3
	_box_item(_prop_items, board_pos, board["x"], board["z"], Vector3(3.0, 1.3, 0.12), zone.lerp(WHITE_RENDER, 0.15))
	_box_item(_prop_items, board_pos + Vector3.UP * 0.25 - Vector3(board["z"]) * 0.07, board["x"], board["z"],
		Vector3(2.4, 0.3, 0.02), WHITE_RENDER)


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
			if nt == Tile.ROAD and sim.road_kind[n.y * map_w + n.x] == Settings.MOTORWAY:
				continue                    # (a motorway isn't a street: nothing is squeezed in beside it)
			if nt != Tile.EMPTY and nt != Tile.POWER_LINE and nt != Tile.WOODLAND:
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
			_plan_park(i)
		INFILL_ALLOTMENTS:
			# Plots of vegetables and soil (painted by the shader) and a few sheds.
			for k in 3:
				_prop(i, front, rng.randf_range(-18.0, 18.0), rng.randf_range(6.0, depth - 10.0),
					2.4, 3.0, 2.2, Color(0.30, 0.38, 0.30))
		INFILL_CAR_PARK:
			_slab(i, front, 0.0, 1.0, 46.0, depth - 3.0, CAR_PARK)
			_parking_bays(i, front, 2.0, depth - 2.5, 0.5, rng)


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
		var c: Color = Color(colour.lightened(0.15), 0.6) if item[1] else Color(1.0, 0.25, 0.2, 0.6)
		list.append([Transform3D(Basis(), p + Vector3.UP * 1.5), c])
	_fill(preview.multimesh, list, false)
	hover_box.visible = items.is_empty() and hover_box.visible


# House walls and roofs. Neighbouring streets share a character (a palette),
# picked by position in squares of HOUSE_AREA tiles, so a street reads as one
# place and the next can differ: Victorian red or blonde sandstone under dark
# slate, white and cream harling, inter-war pebbledash under red and brown
# tiles, modern brick. (All colours in the game are sRGB.)
const RED_SANDSTONE_DEEP := Color(0.49, 0.25, 0.19)
const WHINSTONE := Color(0.44, 0.44, 0.43)
const PEBBLEDASH := Color(0.72, 0.70, 0.64)
const BUFF_BRICK := Color(0.72, 0.57, 0.40)
const RED_BRICK := Color(0.55, 0.26, 0.18)
const OCHRE_RENDER := Color(0.85, 0.72, 0.48)
const SLATE_DARK := Color(0.18, 0.20, 0.23)
const BROWN_TILE := Color(0.36, 0.24, 0.18)
const GREY_TILE := Color(0.32, 0.32, 0.33)
const HOUSE_AREA := 3
const HOUSE_PALETTES := [
	{"walls": [RED_SANDSTONE, RED_SANDSTONE_DEEP, RED_SANDSTONE, BLONDE_SANDSTONE], "roofs": [SLATE, SLATE_DARK]},
	{"walls": [BLONDE_SANDSTONE, HONEY_STONE, BLONDE_SANDSTONE, RED_SANDSTONE], "roofs": [SLATE, SLATE_DARK]},
	{"walls": [WHITE_RENDER, CREAM_RENDER, WHITE_RENDER, OCHRE_RENDER], "roofs": [SLATE, SLATE_DARK, SLATE]},
	{"walls": [PEBBLEDASH, CREAM_RENDER, GREY_RENDER, WHITE_RENDER], "roofs": [ROOF_TILE, BROWN_TILE, ROOF_TILE]},
	{"walls": [BUFF_BRICK, RED_BRICK, BUFF_BRICK, CREAM_RENDER], "roofs": [BROWN_TILE, GREY_TILE, ROOF_TILE]},
	{"walls": [RED_SANDSTONE, BLONDE_SANDSTONE, WHITE_RENDER, WHINSTONE], "roofs": [SLATE, SLATE_DARK]},
]
const HOUSE_PALETTE_ODDS := [0, 0, 1, 1, 2, 2, 3, 4, 5]   # how often each palette comes up


func _house_palette(i: int) -> Dictionary:
	var tile := Vector2i(i % map_w, i / map_w)
	var r := _field_rand(floori(tile.x / float(HOUSE_AREA)), floori(tile.y / float(HOUSE_AREA)), 311)
	var k: int = HOUSE_PALETTE_ODDS[mini(int(r * HOUSE_PALETTE_ODDS.size()), HOUSE_PALETTE_ODDS.size() - 1)]
	return HOUSE_PALETTES[k]


func _house_colour(rng: RandomNumberGenerator, i: int) -> Color:
	# Half the houses take the street's main colour, the rest any of its others.
	var walls: Array = _house_palette(i)["walls"]
	var c: Color = walls[0] if rng.randf() < 0.5 else walls[rng.randi_range(0, walls.size() - 1)]
	return c.darkened(rng.randf_range(-0.04, 0.08))


func _house_roof(rng: RandomNumberGenerator, i: int) -> Color:
	var roofs: Array = _house_palette(i)["roofs"]
	var c: Color = roofs[0] if rng.randf() < 0.5 else roofs[rng.randi_range(0, roofs.size() - 1)]
	return c.darkened(rng.randf_range(-0.05, 0.1))


func _tenement_stone(rng: RandomNumberGenerator, i: int) -> Color:
	# Tenement streets are mostly one stone: red or blonde, by the street's character.
	var walls: Array = _house_palette(i)["walls"]
	var first: Color = walls[0]
	var red_odds := 0.85 if first == RED_SANDSTONE else (0.15 if first == BLONDE_SANDSTONE else 0.5)
	var c: Color = RED_SANDSTONE if rng.randf() < red_odds else BLONDE_SANDSTONE
	return c.darkened(rng.randf_range(-0.03, 0.08))


func _plan_homes(i: int, lv: int, front: Vector2i, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array) -> void:
	var depth := _depth(i, front)
	var value := _values[i] if i < _values.size() else 0.3
	if lv >= 7:
		_plan_skyscraper(i, lv, front, depth, value, false, rng, wall_list, roof_list, _spire_items)
		return
	if lv >= 4:
		_plan_tall_homes(i, lv, front, depth, value, rng, wall_list, roof_list)
		return
	if lv >= 3:
		# Tenements front and back, with a shared back court between them.
		var back_row := depth - 16.0
		for row_back: float in [3.0, back_row]:
			for along: float in [-12.5, 12.5]:
				var storeys := rng.randi_range(3, 4)
				var stone := _tenement_stone(rng, i)
				var spot := _place(i, front, along, row_back, 22.0, 13.0)
				var slate: Color = SLATE_DARK if rng.randf() < 0.5 else SLATE
				_add_block(spot, 22.0, 13.0, storeys * 3.0 + 0.5, stone, STYLE_FLATS, 4.5, slate, wall_list, roof_list)
		_slab(i, front, 0.0, 0.0, 48.0, 3.0, PAVEMENT)                       # front pavement
		_tenement_court(i, front, back_row, rng)
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
	var tile := Vector2i(i % map_w, i / map_w)
	for row in rows.size():
		var back: float = rows[row]
		for lot: int in 4:
			var along: float = -17.25 + lot * 11.5
			if row == 0 and lv >= 2 and lot == 0:
				continue   # this lot is the lane
			if rng.randf() < 0.1:
				continue   # the odd empty garden plot
			var w := rng.randf_range(7.0, 7.8)
			var d := rng.randf_range(7.0, 9.0)
			var h := 5.6 if rng.randf() < 0.8 else 3.2   # mostly two storeys, some bungalows
			var roof := _house_roof(rng, i)
			var house_along: float = along - 5.3 + w * 0.5
			var spot := _place(i, front, house_along, back, w, d)
			var walls_colour := _house_colour(rng, i)
			_add_block(spot, w, d, h, walls_colour, STYLE_HOUSE,
				rng.randf_range(2.8, 3.6), roof, wall_list, roof_list)
			var drive_along: float = along - 5.3 + w + 1.5
			var drive_from := 0.0 if row == 0 else lane_at + 3.0
			_slab(i, front, drive_along, drive_from, 2.6, back + d - drive_from, DRIVEWAY)
			if rng.randf() < 0.6:
				_parked_car(i, front, drive_along, drive_from + 0.8, rng.randf() < 0.3, rng)
			# The front boundary: a hedge or a low wall, with a gap for the path
			# to the door (the path itself is painted by the shader).
			var wall_front := _field_rand(tile.x * 4 + lot, tile.y, 204) < 0.35
			var gate := along - 2.0
			var left := along - 5.3
			var right := along - 5.3 + w
			for part: Vector2 in [Vector2(left, gate - 0.6), Vector2(gate + 0.6, right)]:
				var pw := part.y - part.x
				if wall_front:
					_prop(i, front, (part.x + part.y) * 0.5, drive_from + 0.35, pw, 0.35, 0.75, walls_colour.darkened(0.15))
				else:
					_prop(i, front, (part.x + part.y) * 0.5, drive_from + 0.3, pw, 0.8, 1.1, green)
			var garden_to: float = lane_at - 0.5 if (row == 0 and lv >= 2) else depth - 0.8
			_villa_garden(i, front, along, back + 9.3, garden_to, tile.x * 4 + lot, tile.y)
		# Garden trees: a couple behind each house, sometimes one out front.
		var garden_to: float = lane_at - 1.5 if (row == 0 and lv >= 2) else depth - 2.5
		for along: float in [-17.25, -5.75, 5.75, 17.25]:
			var garden_from: float = back + 11.0
			if garden_to - garden_from > 2.0:
				for k in rng.randi_range(1, 2):
					_plant(i, front, along + rng.randf_range(-3.5, 3.5),
						rng.randf_range(garden_from, garden_to), rng.randf_range(5.0, 10.0), TreeKind.GARDEN, rng)
			if row == 0 and rng.randf() < 0.35:
				_plant(i, front, along + rng.randf_range(-3.0, 1.0), rng.randf_range(2.0, 4.0),
					rng.randf_range(4.0, 6.5), TreeKind.ORNAMENTAL, rng)
		# Between neighbouring lots, front to back: hedges, or fences out the back.
		var row_from := 0.3 if row == 0 else lane_at + 3.3
		var row_to := lane_at if (row == 0 and lv >= 2) else depth - 0.5
		for edge: float in [-11.5, 0.0, 11.5, 23.0]:
			if _field_rand(tile.x * 5 + int(edge), tile.y, 205) < 0.45:
				_prop(i, front, edge, row_from, 0.7, back + 9.0 - row_from, 1.4, green)
				_prop(i, front, edge, back + 9.0, 0.1, row_to - back - 9.0, 1.7, FENCE_TIMBER)
			else:
				_prop(i, front, edge, row_from, 0.7, row_to - row_from, 1.4, green)
	# A fence along the back of the gardens, where the next street's gardens begin.
	_prop(i, front, 0.0, depth - 0.45, 46.0, 0.1, 1.7, FENCE_TIMBER)
	if lv >= 2:
		_slab(i, front, -17.25, 0.0, 3.2, lane_at + 3.0, DRIVEWAY)     # lane in from the street
		_slab(i, front, 0.0, lane_at, 48.0, 3.0, DRIVEWAY)              # lane behind the front gardens


const FENCE_TIMBER := Color(0.42, 0.31, 0.21)
const SHEDS := [Color(0.30, 0.40, 0.30), Color(0.50, 0.37, 0.24), Color(0.56, 0.57, 0.56), Color(0.36, 0.43, 0.52),
	Color(0.62, 0.55, 0.42)]
const GREENHOUSE := Color(0.78, 0.86, 0.86)
const PATIO_SET := [Color(0.92, 0.92, 0.90), Color(0.45, 0.32, 0.20), Color(0.20, 0.22, 0.24)]


func _villa_garden(i: int, front: Vector2i, centre: float, from: float, to: float, salt_x: int, salt_y: int) -> void:
	# A back garden's things, matching what the shader paints there (the same
	# hashes: patio by the house, a border on one side, a vegetable patch near
	# the end): a shed at the bottom, sometimes a greenhouse, a rotary washing
	# line, a table on the patio.
	var s1 := _field_rand(salt_x, salt_y, 201)
	var s2 := _field_rand(salt_x, salt_y, 202)
	var s3 := _field_rand(salt_x, salt_y, 203)
	var length := to - from
	if length < 5.0:
		return
	var side := -1.0 if s3 < 0.5 else 1.0          # the side the shader's border runs down
	if s1 > 0.28:
		var shed_at := centre - side * 3.3
		var colour: Color = SHEDS[int(s2 * 17.0) % SHEDS.size()]
		_prop(i, front, shed_at, to - 2.4, 2.4, 1.9, 1.9, colour)
		_prop(i, front, shed_at, to - 2.4, 2.7, 2.3, 0.15, colour.darkened(0.45), 1.9)       # felt roof
	if s2 > 0.72 and length > 14.0:
		_prop(i, front, centre + 3.0, to - 8.0, 2.4, 3.2, 2.2, GREENHOUSE)
	if s3 > 0.2 and s3 < 0.7 and length > 9.0:
		var at := Vector2(centre + 1.6, from + 6.5)
		_prop(i, front, at.x, at.y, 0.07, 0.07, 1.9, PATIO_SET[0])
		_prop(i, front, at.x, at.y, 2.6, 0.04, 0.04, PATIO_SET[0], 1.82)
		_prop(i, front, at.x, at.y, 0.04, 2.6, 0.04, PATIO_SET[0], 1.82)
	if s1 < 0.6:
		var patio_w := 3.5 + 3.5 * s2
		_prop(i, front, centre - 5.3 + patio_w * 0.5, from + 1.5, 1.0, 1.0, 0.75,
			PATIO_SET[int(s1 * 10.0) % PATIO_SET.size()])


const BIN_STORE := Color(0.30, 0.31, 0.30)
const BINS := [Color(0.16, 0.30, 0.18), Color(0.20, 0.32, 0.55), Color(0.35, 0.36, 0.37), Color(0.55, 0.38, 0.20)]


func _tenement_court(i: int, front: Vector2i, back_row: float, rng: RandomNumberGenerator) -> void:
	# The shared back court (its ground is painted by the shader: paving by the
	# back doors, a path down the middle and up each close, four drying greens):
	# sandstone walls at the sides, a bin store by each close, clothes poles and
	# lines on the greens, trees in the corners.
	var mid := (16.5 + back_row) * 0.5
	var stone := RED_SANDSTONE.darkened(0.1) if rng.randf() < 0.5 else BLONDE_SANDSTONE.darkened(0.1)
	for along: float in [-23.9, 23.9]:
		_prop(i, front, along, 16.5, 0.35, back_row - 16.5, 1.6, stone)
	for along: float in [-7.0, 7.0]:
		for at: float in [18.4, back_row - 3.9]:
			_prop(i, front, along, at, 3.2, 1.5, 1.5, BIN_STORE)
			_prop(i, front, along, at - 0.1, 3.5, 1.8, 0.12, BIN_STORE.darkened(0.3), 1.5)
	for green: Vector2 in [Vector2(-12.0, (18.2 + mid) * 0.5), Vector2(12.0, (18.2 + mid) * 0.5),
			Vector2(-12.0, (mid + back_row - 2.3) * 0.5), Vector2(12.0, (mid + back_row - 2.3) * 0.5)]:
		var span := minf(7.0, (mid - 18.2) * 0.5 - 1.5)
		if span < 2.0:
			continue
		for end: float in [-1.0, 1.0]:
			_prop(i, front, green.x + end * 5.0, green.y - span, 0.1, 0.1, 2.2, CHARCOAL)
			_prop(i, front, green.x + end * 5.0, green.y + span, 0.1, 0.1, 2.2, CHARCOAL)
			_prop(i, front, green.x + end * 5.0, green.y - span, 0.03, span * 2.0, 0.03, WHITE_RENDER, 2.05)
		if rng.randf() < 0.6:
			# Washing out: a few things pegged on one line.
			for k in 4:
				var colour: Color = [WHITE_RENDER, Color(0.30, 0.45, 0.70), Color(0.80, 0.30, 0.30),
					Color(0.95, 0.85, 0.40)][rng.randi_range(0, 3)]
				_prop(i, front, green.x - 5.0, green.y - span + 1.0 + k * span * 0.45, 0.04, 0.8, 0.6, colour, 1.45)
	for corner: Vector2 in [Vector2(-21.0, 19.8), Vector2(21.0, back_row - 3.6)]:
		_plant(i, front, corner.x, corner.y, rng.randf_range(7.0, 10.0), _park_kind(rng), rng)


func _plan_terraces(i: int, front: Vector2i, depth: float, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array) -> void:
	# Medium density: two-storey terraces, front and back, each split into a few
	# runs of joined houses, with small front gardens and long back gardens.
	var back_row: float = depth - 13.0
	var green := _hedge_colour(rng)
	for row_back: float in [4.0, back_row]:
		var stone: Color = _house_colour(rng, i)
		var roof: Color = _house_roof(rng, i)
		for along: float in [-15.5, 0.0, 15.5]:
			var spot := _place(i, front, along, row_back, 15.0, 8.5)
			_add_block(spot, 15.0, 8.5, 6.2, stone.darkened(rng.randf_range(-0.04, 0.06)), STYLE_HOUSE,
				3.2, roof, wall_list, roof_list)
		_prop(i, front, 0.0, row_back - 3.6, 47.0, 0.7, 1.0, green)   # front garden hedge
	_slab(i, front, 0.0, 0.0, 48.0, 3.0, PAVEMENT)
	# A back lane between the two rows of back gardens, with a few cars.
	var lane: float = (4.0 + 8.5 + back_row) * 0.5 - 1.5
	_slab(i, front, 0.0, lane, 48.0, 3.0, DRIVEWAY)
	# Trees in the back gardens on both sides of the lane.
	for strip: Vector2 in [Vector2(14.5, lane - 1.5), Vector2(lane + 4.5, back_row - 1.5)]:
		if strip.y - strip.x < 2.0:
			continue
		for k in rng.randi_range(2, 4):
			_plant(i, front, rng.randf_range(-21.0, 21.0), rng.randf_range(strip.x, strip.y),
				rng.randf_range(5.0, 9.0), TreeKind.GARDEN, rng)
	for k in 4:
		if rng.randf() < 0.5:
			_parked_car(i, front, -18.0 + k * 12.0, lane - 0.7, rng.randf() < 0.5, rng)
	# Fences between the strip gardens (one per house, as the shader paints
	# them), and a shed at the lane end of some.
	var tile := Vector2i(i % map_w, i / map_w)
	var strip_w := 46.0 / 9.0
	for area: Vector2 in [Vector2(12.5, lane), Vector2(lane + 3.0, back_row - 0.4)]:
		if area.y - area.x < 4.0:
			continue
		for k in range(1, 9):
			_prop(i, front, -23.0 + k * strip_w, area.x, 0.08, area.y - area.x, 1.5, FENCE_TIMBER)
		var lane_end: float = area.y - 2.0 if area.x < lane else area.x + 0.2
		for k in 9:
			var s := _field_rand(tile.x * 9 + k, tile.y + int(area.x), 213)
			if s < 0.5:
				var colour: Color = SHEDS[int(s * 31.0) % SHEDS.size()]
				var at := -23.0 + (k + 0.5) * strip_w + (1.1 if s < 0.25 else -1.1)
				_prop(i, front, at, lane_end, 1.8, 1.7, 1.8, colour)
				_prop(i, front, at, lane_end - 0.15, 2.1, 2.0, 0.12, colour.darkened(0.45), 1.8)


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


# Skyscraper materials (sRGB). Glass tints for curtain walling...
const GLASS_TINTS := [Color(0.24, 0.38, 0.52), Color(0.26, 0.44, 0.42), Color(0.44, 0.34, 0.24),
	Color(0.62, 0.66, 0.70), Color(0.15, 0.17, 0.20), Color(0.32, 0.50, 0.60)]   # blue, green, bronze, silver, smoke, sky
# ...coloured spandrel panels between the glass...
const SPANDRELS := [Color(0.88, 0.88, 0.85), Color(0.20, 0.21, 0.23), Color(0.64, 0.34, 0.24),
	Color(0.72, 0.58, 0.32), Color(0.30, 0.40, 0.48)]                              # white, charcoal, terracotta, gold, slate blue
# ...stone and brick for art deco towers, concrete for grids, render for towers of flats.
const TOWER_STONES := [Color(0.86, 0.82, 0.72), Color(0.84, 0.71, 0.50), Color(0.60, 0.34, 0.27),
	Color(0.55, 0.28, 0.20), Color(0.80, 0.78, 0.74)]                             # limestone, honey, red sandstone, brick, Portland
const TOWER_CONCRETE := [Color(0.66, 0.66, 0.63), Color(0.88, 0.88, 0.85), Color(0.76, 0.68, 0.55),
	Color(0.40, 0.41, 0.42)]                                                        # concrete, white, buff, dark
const TOWER_RENDER := [Color(0.92, 0.92, 0.90), Color(0.86, 0.80, 0.67), Color(0.70, 0.42, 0.32),
	Color(0.72, 0.74, 0.74), Color(0.55, 0.60, 0.66)]                             # white, cream, terracotta, pale grey, blue-grey
const TOWER_PANELS := [Color(0.90, 0.70, 0.22), Color(0.22, 0.55, 0.56), Color(0.72, 0.22, 0.16),
	Color(0.24, 0.40, 0.66), Color(0.42, 0.60, 0.30), Color(0.25, 0.26, 0.28)]   # yellow, teal, red, blue, green, charcoal
const SKY_CLADDING := [Color(0.80, 0.82, 0.84), Color(0.33, 0.27, 0.21), Color(0.84, 0.71, 0.50),
	Color(0.22, 0.23, 0.25), Color(0.92, 0.92, 0.90)]   # (box fallback) silver, bronze, stone, charcoal, white


func _pick(rng: RandomNumberGenerator, list: Array) -> Color:
	var c: Color = list[rng.randi_range(0, list.size() - 1)]
	return c


func _plan_skyscraper(i: int, lv: int, front: Vector2i, depth: float, value: float, offices: bool,
		rng: RandomNumberGenerator, wall_list: Array, roof_list: Array, chimney_list: Array) -> void:
	# CBD skyscrapers: a three-storey podium along the street (glass, or classical
	# with shopfronts), and one or two towers rising from it. Each plot gets its
	# own design (picked from the plot's own random numbers, so it never changes):
	#   offices: tinted curtain glass, glass with coloured spandrels, art deco stone
	#            with a stepped floodlit top, or a precast concrete grid;
	#   flats:   bands of render with coloured panels, brick or stone, green or blue
	#            glass, or a white grid; all with balconies.
	# Footprints vary (slab, square, block, slender, twin towers), towers step in,
	# and tops differ: plant screens, sloping glass, deco steps, a landmark spire.
	# Stage 7 is 20-26 storeys; stage 8 a 32-42 storey landmark.
	var classical_podium := rng.randf() < 0.4
	var podium := _place(i, front, 0.0, 3.0, 46.0, 24.0)
	var podium_h := 12.6
	if classical_podium:
		_classical_block(podium, 46.0, 24.0, 3, _classical_stone(rng), true, false, wall_list, roof_list, false)
		podium_h = 4.2 + 2 * 3.4 + 0.6 + 0.9
	else:
		_add_block(podium, 46.0, 24.0, podium_h, GLASS_FRAME, STYLE_GLASS, 0.0, SLATE, wall_list, roof_list)
		_front_panel(podium, 24.0, 0.0, 4.6, 48.0, 0.6, TRIM, wall_list)     # canopy over the entrance
	_slab(i, front, 0.0, 0.0, 49.0, 3.0, PAVEMENT)
	_street_furniture(i, front, offices)
	var plaza_from := 28.0
	if depth - plaza_from > 6.0:
		_slab(i, front, 0.0, plaza_from, 46.0, depth - plaza_from - 1.0, PAVEMENT)
		for along: float in [-17.0, 0.0, 17.0]:
			_plant(i, front, along + rng.randf_range(-2.0, 2.0), plaza_from + (depth - plaza_from) * 0.5,
				rng.randf_range(7.0, 10.0), TreeKind.BROADLEAF, rng)

	# The design: material family, floor model and colours.
	var family := rng.randi_range(0, 3)
	var floor_model := "glass_floor"
	var colour := _pick(rng, GLASS_TINTS)
	var accent := colour.darkened(0.35)
	var box_style := STYLE_GLASS
	if offices:
		match family:
			1:          # glass with coloured spandrels
				accent = _pick(rng, SPANDRELS)
			2:          # art deco stone
				floor_model = "tower_stone"
				colour = _pick(rng, TOWER_STONES)
				accent = [BRONZE, CHARCOAL, Color(0.16, 0.28, 0.24)][rng.randi_range(0, 2)]
				box_style = STYLE_CLASSICAL
			3:          # precast concrete grid
				floor_model = "tower_grid"
				colour = _pick(rng, TOWER_CONCRETE)
				accent = colour
				box_style = STYLE_MODERN
	else:
		match family:
			0, 1:       # bands of render with coloured panels
				floor_model = "tower_band"
				colour = _pick(rng, TOWER_RENDER)
				accent = _pick(rng, TOWER_PANELS)
				box_style = STYLE_MODERN
			2:          # brick or stone with punched windows
				floor_model = "tower_stone"
				colour = _pick(rng, TOWER_STONES)
				accent = CHARCOAL
				box_style = STYLE_CLASSICAL
			3:          # green or blue glass
				colour = GLASS_TINTS[[0, 1, 5][rng.randi_range(0, 2)]]
				accent = _pick(rng, SPANDRELS) if rng.randf() < 0.5 else colour.darkened(0.35)
	var deco := floor_model == "tower_stone" and offices
	var glass := floor_model == "glass_floor"
	var floor_h := 3.6 if offices else 3.2
	var storeys := rng.randi_range(20, 26) if lv == 7 else rng.randi_range(32, 42)

	# Footprint and massing. Tiers: [width, depth, share of the storeys, offset along the street].
	var shape := rng.randi_range(0, 4)
	var dims: Array = [[26.0, 19.0], [32.0, 15.0], [22.0, 21.0], [19.0, 17.0], [16.0, 16.0]][shape]
	var tw0: float = dims[0]
	var td0: float = dims[1]
	var tiers: Array = [[tw0, td0, 1.0, 0.0]]
	if deco:
		tiers = [[tw0, td0, 0.55, 0.0], [tw0 * 0.82, td0 * 0.84, 0.28, 0.0], [tw0 * 0.64, td0 * 0.68, 0.17, 0.0]]
	elif lv >= 8:
		tiers = [[tw0, td0, 0.58, 0.0], [tw0 * 0.8, td0 * 0.82, 0.27, 0.0], [tw0 * 0.6, td0 * 0.66, 0.15, 0.0]]
	elif rng.randf() < 0.45:
		if rng.randf() < 0.5:
			tiers = [[tw0, td0, 0.8, 0.0], [tw0 * 0.72, td0 * 0.8, 0.2, 0.0]]          # one setback
		else:
			var side := -1.0 if rng.randf() < 0.5 else 1.0                          # stepped to one side
			tiers = [[tw0, td0, 0.7, 0.0], [tw0 * 0.55, td0, 0.3, side * tw0 * 0.225]]
	var crown := "crown_plant"
	if deco:
		crown = "crown_deco"
	elif glass and lv >= 8:
		crown = "crown_spire" if rng.randf() < 0.6 else "crown_slope"
	elif glass and rng.randf() < 0.4:
		crown = "crown_slope"
	elif not offices and rng.randf() < 0.5:
		crown = "modern_top"
	var towers: Array[float] = [0.0]
	if shape == 4 and lv == 7:
		towers = [-11.5, 11.5]           # twin slender towers
	elif tw0 < 30.0:
		var shift: float = float(rng.randi_range(-1, 1)) * (23.0 - tw0 * 0.5 - 1.0)
		towers = [shift]
	for t_along: float in towers:
		var twin := towers.size() > 1
		var floors_total: int = storeys - (rng.randi_range(2, 5) if twin and t_along > 0.0 else 0)
		var base := _place(i, front, t_along, 4.0, tw0, td0)
		var at: Vector3 = base["pos"]
		at.y += podium_h
		_stack_tower(at, base["x"], base["z"], tiers, floors_total, floor_h, floor_model, crown, colour, accent,
			box_style, not offices, wall_list, chimney_list, lv >= 8)


func _stack_tower(at: Vector3, x_axis: Vector3, z_axis: Vector3, tiers: Array, storeys: int, floor_h: float,
		floor_model: String, crown: String, colour: Color, accent: Color, box_style: int, balconies: bool,
		wall_list: Array, chimney_list: Array, landmark: bool) -> void:
	# A tower, storey by storey (the floor models stretched to each tier), stepping
	# in tier by tier, then its top.
	var stacked := _models.has(floor_model)
	var tw: float = 0.0
	var td: float = 0.0
	var centre := at
	for tier: Array in tiers:
		tw = tier[0]
		td = tier[1]
		centre = Vector3(at.x, at.y, at.z) + x_axis * float(tier[3])
		var floors: int = maxi(roundi(storeys * float(tier[2])), 2)
		var th: float = floors * floor_h
		if stacked:
			var tier_spot := {"pos": centre, "x": x_axis, "z": z_axis}
			for f: int in floors:
				_add_model(floor_model, _raised(tier_spot, f * floor_h), tw, td, floor_h, colour, accent)
		else:
			_box_item(wall_list, centre, x_axis, z_axis, Vector3(tw, th, td), colour, box_style)
		if balconies:
			# Balconies on the front and back, every other floor: a slab and glass front.
			for f in range(1, floors, 2):
				for side: float in [-1.0, 1.0]:
					var y: float = centre.y + f * floor_h
					var balcony := Vector3(centre.x, y, centre.z) + z_axis * side * (td * 0.5 + 0.7) \
						+ x_axis * (tw * 0.2 * side)
					_prop_items.append([Transform3D(Basis(x_axis * (tw * 0.45), Vector3.UP * 0.2, z_axis * 1.4),
						balcony), TRIM])
					_prop_items.append([Transform3D(Basis(x_axis * (tw * 0.45), Vector3.UP * 1.0, z_axis * 0.08),
						balcony + Vector3.UP * 0.2 + z_axis * side * 0.66), BALCONY_GLASS])
		# A slab edge where the tower steps in.
		_box_item(wall_list, centre + Vector3.UP * th, x_axis, z_axis, Vector3(tw + 0.5, 0.45, td + 0.5),
			accent.lerp(colour, 0.5), STYLE_PAINT)
		at = Vector3(at.x, centre.y + th + 0.45, at.z)
		centre.y = at.y
	var top := {"pos": centre, "x": x_axis, "z": z_axis}
	if _models.has(crown):
		_add_model(crown, top, tw, td, _model_total(crown), colour, accent)
		return
	# Without the models: roof plant and, on a landmark, a spire.
	_box_item(wall_list, centre, x_axis, z_axis, Vector3(8.0, 3.0, 6.0), CONCRETE, STYLE_PLANT)
	if landmark:
		chimney_list.append([Transform3D(Basis.from_scale(Vector3(0.7, 28.0, 0.7)), centre + Vector3.UP * 17.0),
			Color(0.80, 0.82, 0.84)])


func _classical_stone(rng: RandomNumberGenerator) -> Color:
	var stones := [HONEY_STONE, BLONDE_SANDSTONE, RED_SANDSTONE, CREAM_STONE, HONEY_STONE]
	var c: Color = stones[rng.randi_range(0, stones.size() - 1)]
	return c.darkened(rng.randf_range(-0.03, 0.05))


const TERRACOTTA := Color(0.72, 0.42, 0.30)
const ZINC := Color(0.50, 0.53, 0.56)
const SAGE := Color(0.56, 0.63, 0.50)


func _modern_cladding(rng: RandomNumberGenerator) -> Color:
	# Modern blocks: timber, bronze, stone, charcoal, brick, terracotta, zinc, sage render.
	var options := [TIMBER, BRONZE, CREAM_STONE, CHARCOAL, BRICK, TERRACOTTA, ZINC, SAGE, BUFF_BRICK, TIMBER]
	var c: Color = options[rng.randi_range(0, options.size() - 1)]
	return c


func _classical_block(spot: Dictionary, w: float, d: float, storeys: int, stone: Color,
		shops: bool, bays: bool, wall_list: Array, roof_list: Array, mansard: bool = true,
		slate: Color = SLATE) -> void:
	# Sandstone: tall rusticated ground floor, sash windows in stone surrounds,
	# full-height bay windows, a cornice and a slate mansard roof with dormers.
	var h: float = 4.2 + (storeys - 1) * 3.4 + 0.6
	if mansard:
		# The detailed model, where there is one for this height and kind.
		var kind := "_shops" if shops else ("_bays" if bays and storeys >= 5 else "")
		var model_name := "classical%d%s" % [storeys, kind]
		if _models.has(model_name):
			_add_model(model_name, spot, w, d, h + 0.9 + 4.0, stone, slate)
			return
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
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
		pos + Vector3.UP * (h + 0.9)), slate])
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
	var floor_model := "glass_floor" if glassy else "modern_floor"
	# All-glass blocks take a glass tint, picked by position (blue, green, bronze, silver...).
	var pos0: Vector3 = spot["pos"]
	var glass_tint: Color = GLASS_TINTS[int(fposmod(pos0.x * 0.131 + pos0.z * 0.173, 1.0) * GLASS_TINTS.size())]
	var stacked: bool = _models.has("modern_base") and _models.has("modern_top") and _models.has(floor_model)
	if stacked:
		# The detailed models, storey by storey (the roof has the penthouse and terrace).
		_add_model("modern_base", spot, w, d, base_h, cladding, cladding)
		for f: int in body_floors:
			if glassy:
				_add_model(floor_model, _raised(spot, base_h + f * 3.2), w, d, 3.2, glass_tint, glass_tint.darkened(0.35))
			else:
				_add_model(floor_model, _raised(spot, base_h + f * 3.2), w, d, 3.2, cladding, cladding)
		_add_model("modern_top", _raised(spot, base_h + body_h), w, d, _model_total("modern_top"), cladding, cladding)
	else:
		_modern_block_boxes(spot, w, d, base_h, body_h, cladding, glassy, wall_list)
	# Balconies on alternate sides, floor by floor: a slab and a glass balustrade.
	for f: int in body_floors:
		var y: float = base_h + f * 3.2
		var along: float = w * (0.22 if f % 2 == 0 else -0.22)
		var at: Vector3 = pos + Vector3.UP * y + x_axis * along - z_axis * (d * 0.5 + 0.8)
		_prop_items.append([Transform3D(Basis(x_axis * (w * 0.44), Vector3.UP * 0.22, z_axis * 1.6), at), TRIM])
		_prop_items.append([Transform3D(Basis(x_axis * (w * 0.44), Vector3.UP * 1.05, z_axis * 0.08),
			at + Vector3.UP * 0.22 - z_axis * 0.76), BALCONY_GLASS])


func _modern_block_boxes(spot: Dictionary, w: float, d: float, base_h: float, body_h: float,
		cladding: Color, glassy: bool, wall_list: Array) -> void:
	# The simple version of a modern block, when the models aren't there.
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
	wall_list.append([Transform3D(Basis(x_axis * w, Vector3.UP * base_h, z_axis * d), pos),
		GLASS_FRAME, Color(w, base_h, d, STYLE_GLASS)])
	var body_style: int = STYLE_GLASS if glassy else STYLE_MODERN
	var body_colour: Color = GLASS_FRAME if glassy else cladding
	wall_list.append([Transform3D(Basis(x_axis * w, Vector3.UP * body_h, z_axis * d), pos + Vector3.UP * base_h),
		body_colour, Color(w, body_h, d, body_style)])
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
	for k: int in 6:
		var along: float = rng.randf_range(-20.0, 20.0)
		if absf(along) < 3.0:
			along += 6.0
		var back: float = rng.randf_range(from + 2.0, to - 2.0)
		var spot := _place(i, front, along, back, 1.0, 1.0)
		var at: Vector3 = spot["pos"]
		_extra_trees.append([Vector2(at.x, at.z), rng.randf_range(7.0, 11.0), _park_kind(rng)])


# A high street's walls: sandstone, and render painted in many colours (sRGB).
const SHOP_COLOURS := [Color(0.90, 0.89, 0.85), Color(0.80, 0.69, 0.52), Color(0.86, 0.80, 0.67),
	Color(0.60, 0.34, 0.27), Color(0.62, 0.72, 0.78), Color(0.64, 0.72, 0.58), Color(0.86, 0.62, 0.52),
	Color(0.90, 0.80, 0.50), Color(0.70, 0.82, 0.76), Color(0.84, 0.71, 0.50), Color(0.55, 0.26, 0.18)]
	# white, blonde, cream, red sandstone, pale blue, sage, salmon, yellow ochre, mint, honey, brick


func _plan_shops(i: int, lv: int, front: Vector2i, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array) -> void:
	var colours := SHOP_COLOURS
	var depth := _depth(i, front)
	var value := _values[i] if i < _values.size() else 0.3
	if lv >= 7:
		_plan_skyscraper(i, lv, front, depth, value, true, rng, wall_list, roof_list, _spire_items)
		return
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
		_street_furniture(i, front, true)
		# A multi-storey car park behind.
		var deck := _place(i, front, 0.0, 28.0, 40.0, depth - 31.0)
		_add_block(deck, 40.0, depth - 31.0, 9.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, roof_list)
		return
	var park_from := 16.0           # the back of the shops
	if lv >= 3:
		for along: float in [-12.5, 12.5]:
			var spot := _place(i, front, along, 3.0, 23.0, 18.0)
			_add_block(spot, 23.0, 18.0, rng.randi_range(3, 4) * 3.2 + 0.6,
				colours[rng.randi_range(0, colours.size() - 1)], STYLE_SHOP, 0.0, SLATE,
				wall_list, roof_list)
		park_from = 21.0
	else:
		# A parade of shops along the street; flats above from level 2.
		var height := 4.2 if lv == 1 else 7.0
		for along: float in [-16.5, 0.0, 16.5]:
			var spot := _place(i, front, along, 3.0, 15.5, 13.0)
			_add_block(spot, 15.5, 13.0, height + rng.randf_range(-0.2, 0.4),
				colours[rng.randi_range(0, colours.size() - 1)], STYLE_SHOP,
				3.0 if lv == 2 else 0.0, SLATE_DARK if rng.randf() < 0.5 else SLATE, wall_list, roof_list)
	# Wide pavement out front with planters, a bench and bins (the shader paves
	# the rest of the frontage).
	_slab(i, front, 0.0, 0.0, 49.0, 3.0, PAVEMENT)
	_street_furniture(i, front, true)
	# A concrete service yard behind the shops (painted by the shader): bins,
	# pallets, roll cages and a delivery lorry now and then.
	for k in 5:
		_prop(i, front, -21.0 + k * 1.0, park_from + 0.6, 0.7, 0.8, 1.1, BINS[(k + i) % BINS.size()])
	_prop(i, front, -14.0, park_from + 1.0, 1.2, 1.0, rng.randf_range(0.5, 1.4), PALLETS)
	_prop(i, front, -12.5, park_from + 1.0, 0.8, 0.8, 1.7, SCAFFOLD)
	if rng.randf() < 0.5:
		_lorry(i, front, rng.randf_range(0.0, 10.0), park_from + 3.5, true, rng)
	# Then the car park: marked bays with planted islands, a trolley shelter.
	var park_at := park_from + 7.0
	var park_depth := depth - park_at - 1.6
	_slab(i, front, 0.0, park_at, 44.0, park_depth, CAR_PARK)
	_parking_bays(i, front, park_at + 1.0, park_at + park_depth - 0.5, 0.55, rng)
	_prop(i, front, 0.0, park_at + park_depth - 2.2, 4.0, 1.6, 2.2, BALCONY_GLASS)
	_prop(i, front, 0.0, park_at + park_depth - 2.3, 4.4, 1.9, 0.1, CHARCOAL, 2.2)
	for along: float in [-23.4, 23.4]:
		for k in 2:
			_plant(i, front, along, park_at + 3.0 + k * (park_depth - 6.0), rng.randf_range(6.0, 9.0),
				TreeKind.BROADLEAF, rng)


func _plan_offices(i: int, lv: int, front: Vector2i, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array) -> void:
	# Offices, by stage: 1 small two-storey offices, 2 three-storey chambers,
	# 3 a sandstone block beside a modern one, 4 taller blocks, 5 two glass
	# blocks, 6 a glass tower over a glass podium, 7-8 skyscrapers (CBD only).
	# Each plot is old (sandstone) or new (glass and cladding) at the low stages.
	var depth := _depth(i, front)
	var value := _values[i] if i < _values.size() else 0.3
	if lv >= 7:
		_plan_skyscraper(i, lv, front, depth, value, true, rng, wall_list, roof_list, _spire_items)
		return
	var extra: int = roundi(value * 2.0)
	var modern: bool = rng.randf() < 0.45
	_slab(i, front, 0.0, 0.0, 49.0, 3.0, PAVEMENT)
	_street_furniture(i, front, false)
	if lv >= 6:
		var podium := _place(i, front, 0.0, 3.0, 46.0, 22.0)
		_add_block(podium, 46.0, 22.0, 9.0, GLASS_FRAME, STYLE_GLASS, 0.0, SLATE, wall_list, roof_list)
		var tower := _place(i, front, rng.randf_range(-6.0, 6.0), 5.0, 24.0, 16.0)
		var tower_pos: Vector3 = tower["pos"]
		tower["pos"] = tower_pos + Vector3.UP * 9.0
		_modern_block(tower, 24.0, 16.0, rng.randi_range(13, 16) + extra * 2, _modern_cladding(rng),
			true, wall_list, roof_list)
	elif lv == 5:
		for along: float in [-12.5, 12.5]:
			var spot := _place(i, front, along, 3.0, 23.0, 18.0)
			_modern_block(spot, 23.0, 18.0, rng.randi_range(8, 11) + extra, _modern_cladding(rng),
				true, wall_list, roof_list)
	elif lv >= 3:
		var classical_left: bool = rng.randf() < 0.5
		for along: float in [-12.5, 12.5]:
			var spot := _place(i, front, along, 3.0, 23.0, 18.0)
			if (along < 0.0) == classical_left:
				_classical_block(spot, 23.0, 18.0, lv + rng.randi_range(1, 2), _classical_stone(rng),
					false, false, wall_list, roof_list)
			else:
				_modern_block(spot, 23.0, 18.0, lv * 2 - 1 + rng.randi_range(0, 1) + extra, _modern_cladding(rng),
					lv == 4 or value >= 0.5, wall_list, roof_list)
	elif modern:
		# A business park pair: low glass-fronted offices in pale cladding.
		for along: float in [-12.5, 12.5]:
			var spot := _place(i, front, along, 6.0, 21.0, 13.0)
			_modern_block(spot, 21.0, 13.0, lv + 2, _modern_cladding(rng), false, wall_list, roof_list)
			_prop(i, front, along, 4.4, 20.0, 0.8, 0.9, HEDGE_GREEN)
	else:
		# Sandstone offices: a bank, a solicitor's, an insurance company.
		for along: float in [-12.5, 12.5]:
			var spot := _place(i, front, along, 3.0, 21.0, 13.0)
			_classical_block(spot, 21.0, 13.0, lv + 1, _classical_stone(rng), false, false, wall_list, roof_list)
	# Behind: a car park with marked bays and trees (a multi-storey for the big ones).
	if lv >= 4:
		var deck := _place(i, front, 0.0, 28.0, 40.0, depth - 31.0)
		_add_block(deck, 40.0, depth - 31.0, 9.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, roof_list)
		return
	var park_at := 25.0 if lv >= 3 else 22.0
	var park_depth := depth - park_at - 1.6
	_slab(i, front, 0.0, park_at, 44.0, park_depth, CAR_PARK)
	_parking_bays(i, front, park_at + 1.0, park_at + park_depth - 0.5, 0.7, rng)
	for along: float in [-23.4, 23.4]:
		for k in 2:
			_plant(i, front, along, park_at + 3.0 + k * (park_depth - 6.0), rng.randf_range(6.0, 9.0),
				TreeKind.BROADLEAF, rng)


const PALLETS := Color(0.60, 0.47, 0.31)
const HEDGE_GREEN := Color(0.16, 0.30, 0.12)
const LORRY_TRAILERS := [Color(0.92, 0.92, 0.90), Color(0.75, 0.76, 0.78), Color(0.20, 0.35, 0.60),
	Color(0.55, 0.12, 0.10)]
const LORRY_CABS := [Color(0.92, 0.92, 0.90), Color(0.70, 0.12, 0.10), Color(0.15, 0.25, 0.50),
	Color(0.25, 0.27, 0.30)]
const BOLLARD := Color(0.20, 0.21, 0.22)
const POST_BOX := Color(0.75, 0.08, 0.06)


func _lorry(i: int, front: Vector2i, along: float, back: float, nose_to_street: bool,
		rng: RandomNumberGenerator, length: float = 10.0) -> void:
	# A lorry (cab and box trailer) parked along the plot's depth.
	var cab_back: float = back if nose_to_street else back + length + 0.3
	var trailer_back: float = back + 2.8 if nose_to_street else back
	_prop(i, front, along, cab_back, 2.4, 2.5, 3.0, LORRY_CABS[rng.randi_range(0, LORRY_CABS.size() - 1)], 0.3)
	_prop(i, front, along, trailer_back, 2.5, length, 3.2, LORRY_TRAILERS[rng.randi_range(0, LORRY_TRAILERS.size() - 1)],
		0.9)
	_prop(i, front, along, trailer_back + 0.5, 2.2, length - 1.0, 0.9, CHARCOAL)       # wheels and chassis


func _street_furniture(i: int, front: Vector2i, shops: bool) -> void:
	# On the pavement in front of shops and offices: planters with small trees,
	# a bench, litter bins, bollards; a post box now and then.
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 7717 + 3
	for along: float in [-18.0, 6.0]:
		var at := along + rng.randf_range(-2.0, 2.0)
		_prop(i, front, at, 0.6, 1.5, 1.5, 0.6, CREAM_STONE.darkened(0.15))
		_plant(i, front, at, 1.2, rng.randf_range(4.5, 6.0), TreeKind.ORNAMENTAL, rng)
	_prop(i, front, -6.0, 0.8, 1.8, 0.55, 0.45, BENCH)
	_prop(i, front, -3.8, 0.7, 0.5, 0.5, 0.9, CHARCOAL)
	if shops:
		for k in 3:
			_prop(i, front, 12.0 + k * 2.0, 0.35, 0.18, 0.18, 0.9, BOLLARD)
	if rng.randf() < 0.15:
		_prop(i, front, 20.0, 0.6, 0.5, 0.5, 1.4, POST_BOX)


# Industrial sheds come in colourways: [wall cladding, roof sheet] (sRGB).
const SHED_COLOURWAYS := [
	[Color(0.55, 0.58, 0.62), Color(0.40, 0.42, 0.45)],   # grey
	[Color(0.31, 0.42, 0.35), Color(0.30, 0.35, 0.32)],   # green
	[Color(0.22, 0.35, 0.52), Color(0.42, 0.45, 0.49)],   # blue
	[Color(0.82, 0.78, 0.66), Color(0.46, 0.46, 0.45)],   # cream ("goosewing grey")
	[Color(0.50, 0.23, 0.17), Color(0.34, 0.29, 0.27)],   # rust red
	[Color(0.74, 0.76, 0.78), Color(0.56, 0.58, 0.60)],   # silver
	[Color(0.29, 0.31, 0.33), Color(0.22, 0.23, 0.25)],   # dark grey
]
const WORKS_WALLS := [Color(0.58, 0.30, 0.22), Color(0.50, 0.25, 0.18), Color(0.60, 0.34, 0.27),
	Color(0.64, 0.56, 0.44)]                                # red brick, dark brick, red sandstone, buff stone
const WORKS_ROOF := Color(0.34, 0.36, 0.38)
const STEEL_STACK := Color(0.62, 0.63, 0.64)
const SILO := Color(0.80, 0.81, 0.80)


func _industrial(model_name: String, spot: Dictionary, w: float, d: float, h: float, roof_h: float,
		colour: Color, roof_colour: Color, wall_list: Array, roof_list: Array) -> void:
	# A works building: the model if it's there, otherwise the simple shed or block.
	if _models.has(model_name):
		_add_model(model_name, spot, w, d, h + roof_h, colour, roof_colour)
	else:
		_add_block(spot, w, d, h, colour, STYLE_INDUSTRY, roof_h, roof_colour, wall_list, roof_list)


func _plan_industry(i: int, lv: int, front: Vector2i, rng: RandomNumberGenerator,
		wall_list: Array, roof_list: Array, chimney_list: Array) -> void:
	# Works get bigger and heavier stage by stage: small units or an old brick
	# works with a sawtooth roof; then a bigger shed, works or warehouse; then a big
	# distribution warehouse, a large works with a brick chimney, or a processing
	# plant with silos and a steel stack. Sheds come in several colourways
	# (neighbouring works on an estate tend to match); only heavy works have chimneys.
	var depth := _depth(i, front)
	var stack_at := Vector2(-14.0, depth - 10.0)
	var tile := Vector2i(i % map_w, i / map_w)
	var estate := _field_rand(tile.x / 3, tile.y / 3, 331)
	var way_index := int(estate * SHED_COLOURWAYS.size()) if rng.randf() < 0.6 \
		else rng.randi_range(0, SHED_COLOURWAYS.size() - 1)
	var way: Array = SHED_COLOURWAYS[mini(way_index, SHED_COLOURWAYS.size() - 1)]
	var cladding: Color = way[0]
	var sheet: Color = way[1]
	var brick: Color = _pick(rng, WORKS_WALLS)
	var kind := rng.randi_range(0, 2)
	if lv == 1:
		if kind == 0:
			# An old works: brick, with a north-light roof.
			var spot := _place(i, front, -2.0, 6.0, 32.0, 24.0)
			_industrial("works", spot, 32.0, 24.0, 6.0, 3.0, brick, WORKS_ROOF, wall_list, roof_list)
		else:
			# Two small units side by side.
			for along: float in [-12.5, 9.5]:
				var spot := _place(i, front, along, 6.0, 17.0, 20.0)
				_industrial("shed", spot, 17.0, 20.0, 6.0, 1.6, cladding, sheet, wall_list, roof_list)
	elif lv == 2:
		match kind:
			0:
				var a := _place(i, front, -7.0, 4.0, 32.0, 26.0)
				_industrial("shed", a, 32.0, 26.0, 9.0, 2.2, cladding, sheet, wall_list, roof_list)
				var b := _place(i, front, 14.0, depth - 22.0, 18.0, 18.0)
				_add_block(b, 18.0, 18.0, 7.0, CONCRETE, STYLE_INDUSTRY, 0.0, SLATE, wall_list, roof_list)
			1:
				var a := _place(i, front, -4.0, 4.0, 36.0, 28.0)
				_industrial("works", a, 36.0, 28.0, 7.0, 3.2, brick, WORKS_ROOF, wall_list, roof_list)
				var b := _place(i, front, 16.0, depth - 18.0, 14.0, 14.0)
				_industrial("shed", b, 14.0, 14.0, 5.5, 1.4, cladding, sheet, wall_list, roof_list)
			_:
				var a := _place(i, front, -4.0, 4.0, 36.0, 26.0)
				_industrial("warehouse", a, 36.0, 26.0, 9.5, 0.0, cladding, sheet, wall_list, roof_list)
	else:
		match kind:
			0:
				# A big distribution warehouse with silos behind.
				var spot := _place(i, front, -3.0, 4.0, 42.0, depth - 18.0)
				_industrial("warehouse", spot, 42.0, depth - 18.0, 13.0, 0.0, cladding, sheet, wall_list, roof_list)
			1:
				# A large works with a tall brick chimney.
				var spot := _place(i, front, -3.0, 4.0, 42.0, depth - 18.0)
				_industrial("works", spot, 42.0, depth - 18.0, 8.0, 3.6, brick, WORKS_ROOF, wall_list, roof_list)
				var chimney := _place(i, front, 20.0, depth - 8.0, 4.0, 4.0)
				var pos: Vector3 = chimney["pos"]
				chimney_list.append([Transform3D(Basis.from_scale(Vector3(1.8, 32.0, 1.8)),
					pos + Vector3.UP * 16.0), brick.darkened(0.15)])
				chimney_list.append([Transform3D(Basis.from_scale(Vector3(2.1, 1.2, 2.1)),
					pos + Vector3.UP * 31.4), brick.darkened(0.35)])
			_:
				# A processing plant: a shed, a tall mill block, a row of silos and a steel stack.
				var shed := _place(i, front, -9.0, 4.0, 30.0, 26.0)
				_industrial("shed", shed, 30.0, 26.0, 10.0, 2.2, cladding, sheet, wall_list, roof_list)
				var mill := _place(i, front, 13.0, 4.0, 12.0, 16.0)
				_add_block(mill, 12.0, 16.0, 19.0, cladding.lerp(CONCRETE, 0.5), STYLE_INDUSTRY, 0.0, SLATE,
					wall_list, roof_list)
				for k in 3:
					var silo := _place(i, front, 10.0 + k * 5.2, 23.0, 4.6, 4.6)
					_cylinder(chimney_list, silo["pos"], 2.3, 17.0, SILO)
					_cylinder(chimney_list, Vector3(silo["pos"]) + Vector3.UP * 17.0, 1.6, 1.4, SILO.darkened(0.2))
				var stack := _place(i, front, 20.0, depth - 8.0, 3.0, 3.0)
				_cylinder(chimney_list, stack["pos"], 1.1, 28.0, STEEL_STACK)
				_cylinder(chimney_list, Vector3(stack["pos"]) + Vector3.UP * 25.0, 1.15, 1.0, CROSS_RED)
				_prop(i, front, 6.5, 10.0, 2.0, 1.0, 1.0, STEEL_STACK.darkened(0.3), 9.0)     # a pipe bridge
	# Shipping containers stacked in the yard.
	for k in 4:
		var colour: Color = CONTAINERS[rng.randi_range(0, CONTAINERS.size() - 1)]
		var height := 2.6 * (2 if rng.randf() < 0.35 else 1)
		_prop(i, front, stack_at.x + k * 3.0, stack_at.y, 2.5, 6.1, height, colour)
	# A few staff cars by the gate.
	for k in 4:
		if rng.randf() < 0.6:
			_parked_car(i, front, 12.0 + k * 3.0, 0.8, true, rng)
	# The yard (concrete, gravel at the back, scrub by the fences: painted by the
	# shader): a chain-link fence round it with a gap for the gate, pallets
	# stacked at the back, a skip, tanks, a lorry at the side of the shed.
	var fence := Color(0.34, 0.38, 0.36)
	_prop(i, front, -8.0, 0.4, 33.0, 0.05, 2.2, fence)
	_prop(i, front, -24.3, 0.4, 0.05, depth - 1.2, 2.2, fence)
	_prop(i, front, 24.3, 0.4, 0.05, depth - 1.2, 2.2, fence)
	_prop(i, front, 0.0, depth - 0.8, 48.6, 0.05, 2.2, fence)
	for k in rng.randi_range(2, 5):
		_prop(i, front, -22.0 + k * 1.4, depth - 12.8, 1.2, 1.0, rng.randf_range(0.4, 1.5), PALLETS)
	_prop(i, front, -20.5, depth - 7.0, 1.8, 3.8, 1.4,
		[CRANE_YELLOW, Color(0.20, 0.42, 0.25), Color(0.20, 0.32, 0.60)][rng.randi_range(0, 2)])
	if lv >= 2 or rng.randf() < 0.5:
		for along: float in [-1.5, 2.5]:
			var tank := _place(i, front, along, depth - 6.5, 3.6, 3.6)
			_cylinder(_spire_items, tank["pos"], rng.randf_range(1.4, 1.8), rng.randf_range(4.0, 7.0),
				[TANK_GREY, WHITE_RENDER, Color(0.45, 0.50, 0.42)][rng.randi_range(0, 2)])
	if rng.randf() < 0.7:
		_lorry(i, front, 16.0 if lv == 2 else 21.0, 8.0, false, rng, 12.0)


# --------------------------------------------- power, utilities, leisure, transport

const TURBINE_WHITE := Color(0.92, 0.93, 0.93)
const PANEL_BLUE := Color(0.10, 0.15, 0.28)
const TANK_GREY := Color(0.64, 0.70, 0.74)
const BUS_RED := Color(0.70, 0.12, 0.12)
const TRAIN_RED := Color(0.62, 0.12, 0.18)
const TEAM_BLUE := Color(0.12, 0.28, 0.62)
const HULL_WHITE := Color(0.94, 0.94, 0.92)
const SHIP_HULL := Color(0.20, 0.22, 0.26)
const PLANT_BLUE := Color(0.34, 0.41, 0.48)    # coal station boiler house cladding and roofs
const GAS_SILVER := Color(0.78, 0.80, 0.82)    # gas station cladding, stacks, gasholder
const GAS_BLUE := Color(0.10, 0.36, 0.56)      # gas station roofs and band
const NUCLEAR_CONCRETE := Color(0.80, 0.80, 0.78)
const NUCLEAR_BLUE := Color(0.30, 0.42, 0.56)


func _turned(spot: Dictionary, quarter_turns: int) -> Dictionary:
	# The same spot turned about its centre (a model facing sideways or away from the street).
	var copy := spot.duplicate()
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	match posmod(quarter_turns, 4):
		1:
			copy["x"] = z_axis
			copy["z"] = -x_axis
		2:
			copy["x"] = -x_axis
			copy["z"] = -z_axis
		3:
			copy["x"] = -z_axis
			copy["z"] = x_axis
	return copy


func _box_item(list: Array, at: Vector3, x_axis: Vector3, z_axis: Vector3, size: Vector3,
		colour: Color, style: int = -1) -> void:
	# A box standing at a point, size along the given axes. Into the wall list
	# (with a style) or the props list (style -1).
	if x_axis.dot(Vector3.UP.cross(z_axis)) < 0.0:
		x_axis = -x_axis      # keep it right-handed (a mirrored box would render inside out)
	var xf := Transform3D(Basis(x_axis * size.x, Vector3.UP * size.y, z_axis * size.z), at)
	if style >= 0:
		list.append([xf, colour, Color(size.x, size.y, size.z, style)])
	else:
		list.append([xf, colour])


func _cylinder(chimney_list: Array, at: Vector3, radius: float, height: float, colour: Color) -> void:
	# A round tower or tank standing on a point.
	chimney_list.append([Transform3D(Basis.from_scale(Vector3(radius, height, radius)),
		at + Vector3.UP * height * 0.5), colour])


# ------------------------------------------------------------ data centres

# Each company's data centre looks its own (no logos: colours and kit only).
#   wall, roof, band (a strip along the top), trim (entrance and fittings)
#   entrance: the front block's style; kit: what's on the roof and in the yard
const DC_LOOKS := {
	# Amazon: vast, plain, sand-coloured precast boxes with a dark band, rows of
	# rooftop air handlers and a long yard of backup generators.
	"Amazon": {"wall": Color(0.76, 0.69, 0.56), "roof": Color(0.46, 0.44, 0.40), "band": Color(0.28, 0.25, 0.22),
		"trim": Color(0.32, 0.29, 0.26), "entrance": STYLE_PAINT, "kit": "air_handlers"},
	# Microsoft: pale grey halls with a glass entrance pavilion and a roof
	# covered in solar panels.
	"Microsoft": {"wall": Color(0.80, 0.82, 0.84), "roof": Color(0.56, 0.58, 0.60), "band": Color(0.36, 0.48, 0.62),
		"trim": Color(0.30, 0.40, 0.52), "entrance": STYLE_GLASS, "kit": "solar"},
	# Google: white halls, a row of round cooling towers in the yard and pipes
	# on the roof painted in bright colours.
	"Google": {"wall": Color(0.84, 0.86, 0.86), "roof": Color(0.60, 0.63, 0.64), "band": Color(0.42, 0.46, 0.50),
		"trim": Color(0.26, 0.42, 0.70), "entrance": STYLE_MODERN, "kit": "cooling_towers"},
	# Tesla's Gigafactory: a huge white factory with a black band, solar panels on the
	# roof, rows of new cars out front and lorries at the back.
	"Tesla": {"wall": Color(0.93, 0.93, 0.92), "roof": Color(0.52, 0.54, 0.56), "band": Color(0.12, 0.12, 0.13),
		"trim": Color(0.16, 0.16, 0.17), "entrance": STYLE_GLASS, "kit": "factory"},
	# OpenAI: vast near-black halls, roofs packed with cooling units, and a yard of
	# its own gas turbines and transformers (it needs power like a city).
	"OpenAI": {"wall": Color(0.20, 0.21, 0.23), "roof": Color(0.30, 0.31, 0.33), "band": Color(0.85, 0.86, 0.86),
		"trim": Color(0.12, 0.12, 0.13), "entrance": STYLE_GLASS, "kit": "ai"},
}
const DC_DEFAULT_LOOK := {"wall": Color(0.60, 0.64, 0.68), "roof": Color(0.46, 0.48, 0.50), "band": Color(0.34, 0.37, 0.40),
	"trim": Color(0.34, 0.37, 0.40), "entrance": STYLE_PAINT, "kit": "air_handlers"}
const DC_PIPES := [Color(0.85, 0.22, 0.20), Color(0.95, 0.75, 0.15), Color(0.20, 0.62, 0.30), Color(0.20, 0.45, 0.85)]


func _plan_data_centre(i: int, wall_list: Array, roof_list: Array, chimney_list: Array) -> bool:
	# Draw a whole data centre from the first tile of its site, if its tiles fill
	# a rectangle. Returns true if this tile is taken care of (drawn, or part of
	# a site drawn from its first tile); false to draw it as a plain hall.
	var k: int = sim._deal_at.get(i, -1)
	if k < 0:
		return false
	var deal: Dictionary = sim.deals[k]
	var x0 := map_w
	var y0 := map_h
	var x1 := -1
	var y1 := -1
	var mine := 0
	for t in deal["tiles"]:
		var ti := int(t)
		if sim.tiles[ti] != sim.project_tile(sim.deal_kind(deal)):
			continue
		mine += 1
		x0 = mini(x0, ti % map_w)
		x1 = maxi(x1, ti % map_w)
		y0 = mini(y0, ti / map_w)
		y1 = maxi(y1, ti / map_w)
	if mine == 0 or mine != (x1 - x0 + 1) * (y1 - y0 + 1):
		return false                     # (not a full rectangle: a hall per tile)
	if i != y0 * map_w + x0:
		return true                      # (drawn from its first tile)
	var look: Dictionary = DC_LOOKS.get(String(deal["company"]), DC_DEFAULT_LOOK)
	# Which side faces a road: the entrance and car park go there.
	var best := Vector2i(0, 1)
	var best_n := -1
	for side: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n := 0
		var span := range(x0, x1 + 1) if side.x == 0 else range(y0, y1 + 1)
		for a: int in span:
			var p := Vector2i(a, y1 + 1 if side.y > 0 else y0 - 1) if side.x == 0 \
				else Vector2i(x1 + 1 if side.x > 0 else x0 - 1, a)
			if p.x >= 0 and p.y >= 0 and p.x < map_w and p.y < map_h and sim.tiles[p.y * map_w + p.x] == Tile.ROAD:
				n += 1
		if n > best_n:
			best_n = n
			best = side
	var fwd := Vector2(best)
	var away := -fwd
	var across := Vector2(away.y, -away.x)
	var lo := Vector2(x0 * cell, y0 * cell)
	var hi := Vector2((x1 + 1) * cell, (y1 + 1) * cell)
	var mid := (lo + hi) * 0.5
	var size := hi - lo
	var wide := size.x if best.x == 0 else size.y     # along the front
	var deep := size.y if best.x == 0 else size.x     # back from the front
	var front_edge := mid + fwd * deep * 0.5
	var site := {"front": front_edge, "away": away, "across": across}
	var margin := 5.0
	var front_strip := 16.0                           # entrance and car park
	var back_strip := 14.0 if deep >= 90.0 else 9.0   # generators, chillers, cooling towers
	var hall_w := wide - margin * 2.0
	var hall_d := deep - margin * 2.0 - front_strip - back_strip
	var halls := 2 if hall_d > 110.0 else 1
	var gap := 8.0
	var each_d := (hall_d - gap * (halls - 1)) / halls
	var wall: Color = look["wall"]
	var roof: Color = look["roof"]
	var band: Color = look["band"]
	var trim: Color = look["trim"]
	var kit: String = look["kit"]
	var hall_h := 22.0 if kit == "factory" else 14.0
	if sim.deal_building(k):
		_plan_site_works(site, wide, deep, margin, front_strip, hall_w, hall_d, wall_list, roof_list)
		return true
	if sim.deal_kind(deal) == "campus":
		_plan_campus(site, wide, deep, int(deal["id"]), wall_list, roof_list)
		return true
	if sim.deal_kind(deal) == "launch_site":
		_plan_launch_site(site, wide, deep, deal, wall_list, roof_list, chimney_list)
		return true
	for n: int in halls:
		var back := margin + front_strip + n * (each_d + gap)
		var spot := _site_spot(site, 0.0, back, hall_w, each_d)
		_add_block(spot, hall_w, each_d, hall_h, wall, STYLE_PAINT, 0.0, roof, wall_list, roof_list)
		# A band along the top of the walls, a little proud of them.
		var crown := _site_spot(site, 0.0, back - 0.3, hall_w + 0.6, each_d + 0.6)
		crown["pos"] = (crown["pos"] as Vector3) + Vector3.UP * (hall_h - 1.6)
		_add_block(crown, hall_w + 0.6, each_d + 0.6, 1.8, band, STYLE_PAINT, 0.0, band, wall_list, roof_list)
		var top := float((spot["pos"] as Vector3).y) + hall_h + 0.2
		match kit:
			"ai":
				# Cooling units packed edge to edge.
				var cols := maxi(int(hall_w / 9.0), 2)
				var rows := maxi(int(each_d / 10.0), 1)
				for r: int in rows:
					for c: int in cols:
						_site_box(site, -hall_w * 0.5 + (c + 0.5) * hall_w / cols, back + (r + 0.5) * each_d / rows - 3.0,
							6.5, 6.0, 3.2, Color(0.62, 0.64, 0.66), top)
			"air_handlers":
				# Rows of grey boxes over the server rooms.
				var cols := maxi(int(hall_w / 14.0), 2)
				var rows := maxi(int(each_d / 16.0), 1)
				for r: int in rows:
					for c: int in cols:
						_site_box(site, -hall_w * 0.5 + (c + 0.5) * hall_w / cols, back + (r + 0.5) * each_d / rows - 3.0,
							8.0, 5.0, 2.8, Color(0.55, 0.56, 0.57), top)
			"factory":
				# Solar panels over the whole roof, in long rows.
				var rows := maxi(int(each_d / 6.0) - 1, 1)
				for r: int in rows:
					_site_box(site, 0.0, back + 3.0 + r * 6.0, hall_w - 6.0, 3.6, 0.5, Color(0.10, 0.14, 0.24), top)
			"solar":
				# Solar panels in long rows, with a strip of cooling units down the middle.
				var rows := maxi(int(each_d / 5.0) - 1, 1)
				for r: int in rows:
					if r == rows / 2:
						for c: int in maxi(int(hall_w / 12.0), 2):
							_site_box(site, -hall_w * 0.5 + 6.0 + c * 12.0, back + 2.5 + r * 5.0, 7.0, 3.5, 2.4,
								Color(0.70, 0.72, 0.74), top)
						continue
					_site_box(site, 0.0, back + 2.5 + r * 5.0, hall_w - 4.0, 3.2, 0.5, Color(0.10, 0.16, 0.30), top)
			"cooling_towers":
				# Pipes in bright colours running the length of the roof, spread across it,
				# and a few units.
				for c: int in DC_PIPES.size():
					var along := -hall_w * 0.5 + (c + 0.5) * hall_w / DC_PIPES.size()
					_site_box(site, along, back + 3.0, 1.2, each_d - 6.0, 1.2, DC_PIPES[c], top)
				var units := maxi(int(hall_w / 30.0), 1)
				for u: int in units:
					_site_box(site, hall_w * 0.1 + u * 14.0, back + each_d * 0.5 - 4.0, 9.0, 8.0, 3.0,
						Color(0.82, 0.84, 0.84), top)
	# The yard behind: generators, or cooling towers.
	var yard_back := deep - margin - back_strip + 2.0
	if kit == "factory":
		# Lorries backed up to the loading bays.
		var bays := maxi(int(hall_w / 10.0), 2)
		for n: int in bays:
			_site_box(site, -hall_w * 0.5 + (n + 0.5) * hall_w / bays, yard_back - 2.0, 2.6, 12.0, 3.8,
				Color(0.85, 0.86, 0.86) if n % 3 else Color(0.20, 0.22, 0.25))
	elif kit == "ai":
		# Its own gas turbines (with short stacks) and transformers.
		var sets := maxi(int(hall_w / 12.0), 2)
		for n: int in sets:
			var along := -hall_w * 0.5 + (n + 0.5) * hall_w / sets
			if n % 3 == 2:
				_site_box(site, along, yard_back - 3.0, 6.0, 6.0, 4.5, Color(0.45, 0.48, 0.42))
				continue
			var spot := _site_spot(site, along, yard_back - 3.0, 6.0, 6.0)
			_cylinder(chimney_list, spot["pos"], 2.6, 7.0, Color(0.72, 0.74, 0.76))
			_cylinder(chimney_list, (spot["pos"] as Vector3) + Vector3.UP * 7.0, 0.9, 6.0, Color(0.40, 0.42, 0.44))
	elif kit == "cooling_towers":
		var towers := maxi(int(hall_w / 22.0), 2)
		for n: int in towers:
			var spot := _site_spot(site, -hall_w * 0.5 + (n + 0.5) * hall_w / towers, yard_back, 9.0, 9.0)
			_cylinder(chimney_list, spot["pos"], 4.5, 11.0, Color(0.92, 0.93, 0.92))
	else:
		var sets := maxi(int(hall_w / 8.0), 2)
		for n: int in sets:
			_site_box(site, -hall_w * 0.5 + (n + 0.5) * hall_w / sets, yard_back, 5.0, back_strip - 5.0, 3.0,
				Color(0.26, 0.28, 0.30) if kit == "air_handlers" else Color(0.40, 0.44, 0.48))
	# The entrance block and a car park at the front.
	var entrance_w := minf(28.0, hall_w * 0.4)
	var entrance := _site_spot(site, -hall_w * 0.5 + entrance_w * 0.5, margin + 1.0, entrance_w, front_strip - 3.0)
	var entrance_style: int = look["entrance"]
	_add_block(entrance, entrance_w, front_strip - 3.0, 7.0, trim, entrance_style, 0.0, roof, wall_list, roof_list)
	if kit == "factory":
		# Rows of brand-new cars waiting to go.
		var paints := [Color(0.80, 0.10, 0.10), Color(0.95, 0.95, 0.95), Color(0.10, 0.10, 0.11),
			Color(0.55, 0.57, 0.60), Color(0.15, 0.30, 0.65)]
		var cars := maxi(int((hall_w - entrance_w - 8.0) / 2.6), 4)
		for row: int in 2:
			for n: int in cars:
				_site_box(site, -hall_w * 0.5 + entrance_w + 6.0 + n * 2.6, margin + 2.0 + row * 6.0, 1.9, 4.6, 1.5,
					paints[(n * 7 + row * 3) % paints.size()])
	var park := _site_spot(site, entrance_w * 0.5 + 2.0, margin, hall_w - entrance_w - 4.0, front_strip - 2.0)
	var x_axis: Vector3 = park["x"]
	var z_axis: Vector3 = park["z"]
	_paving_items.append([Transform3D(Basis(x_axis * (hall_w - entrance_w - 4.0), Vector3.UP * (float(park["rise"]) + 0.45),
		z_axis * (front_strip - 2.0)), park["pos"]), Color(CAR_PARK, _surface_of(CAR_PARK))])
	# A fence round the site.
	for side: float in [-1.0, 1.0]:
		_site_box(site, side * (wide * 0.5 - 1.0), deep * 0.5, 0.15, deep - 2.0, 2.2, Color(0.30, 0.32, 0.30))
	_site_box(site, 0.0, deep - 1.0, wide - 2.0, 0.15, 2.2, Color(0.30, 0.32, 0.30))
	return true


func _plan_campus(site: Dictionary, wide: float, deep: float, seed_id: int, wall_list: Array, roof_list: Array) -> void:
	# A tech campus: low glass pavilions with green roofs in a grid of 55 m
	# squares, the middle ones left as a lawn quad, trees between them and
	# racks of bright bikes by the doors.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_id * 7919 + 3
	var cols := maxi(int(wide / 55.0), 1)
	var rows := maxi(int(deep / 55.0), 1)
	var cell_w := wide / cols
	var cell_d := deep / rows
	var bikes := [Color(0.85, 0.22, 0.20), Color(0.95, 0.75, 0.15), Color(0.20, 0.62, 0.30), Color(0.20, 0.45, 0.85)]
	for r: int in rows:
		for c: int in cols:
			var along := -wide * 0.5 + (c + 0.5) * cell_w
			var back := (r + 0.5) * cell_d
			var quad := cols >= 3 and rows >= 3 and c > 0 and c < cols - 1 and r > 0 and r < rows - 1
			if quad:
				# The lawn: trees round its edge.
				for n: int in 4:
					var corner := Vector2(-0.3 if n % 2 == 0 else 0.3, -0.3 if n < 2 else 0.3)
					var spot := _site_spot(site, along + corner.x * cell_w, back + corner.y * cell_d, 1.0, 1.0)
					var p: Vector3 = spot["pos"]
					_extra_trees.append([Vector2(p.x, p.z), rng.randf_range(8.0, 13.0), TreeKind.BROADLEAF])
				continue
			var pw := minf(cell_w - 16.0, 34.0)
			var pd := minf(cell_d - 22.0, 22.0)
			var storeys := 3 if rng.randf() < 0.6 else 4
			var h := storeys * 3.6
			var spot := _site_spot(site, along, back - pd * 0.5, pw, pd)
			var glass := Color(0.55, 0.66, 0.74) if rng.randf() < 0.5 else Color(0.70, 0.76, 0.80)
			_add_block(spot, pw, pd, h, glass, STYLE_GLASS, 0.0, glass, wall_list, roof_list)
			var top := float((spot["pos"] as Vector3).y) + h + 0.1
			_site_box(site, along, back - pd * 0.5 + 1.0, pw - 2.0, pd - 2.0, 0.4, Color(0.34, 0.52, 0.24), top)   # green roof
			# Trees in front and a rack of bikes by the door.
			for n: int in 2:
				var tree_at := _site_spot(site, along + (-0.5 + n) * (pw + 6.0), back + pd * 0.5 + 4.0, 1.0, 1.0)
				var tp: Vector3 = tree_at["pos"]
				_extra_trees.append([Vector2(tp.x, tp.z), rng.randf_range(7.0, 11.0),
					TreeKind.ORNAMENTAL if n == 0 else TreeKind.BIRCH])
			for n: int in 6:
				_site_box(site, along - 6.0 + n * 2.2, back - pd * 0.5 - 3.0, 0.5, 1.7, 1.0, bikes[(n + r + c) % bikes.size()])


func _plan_launch_site(site: Dictionary, wide: float, deep: float, deal: Dictionary, wall_list: Array,
		roof_list: Array, chimney_list: Array) -> void:
	# A rocket launch site: a tall assembly hangar by the road, a tank farm, and at
	# the back a concrete pad with a dark launch tower and a stainless rocket
	# (bigger for bigger sites). After a rocket blows up: no rocket, a scorched pad.
	var scale: Dictionary = sim.deal_scale(deal)
	var big := clampf(float(scale.get("tiles", 6)) / 30.0, 0.35, 1.0)
	var steel := Color(0.80, 0.82, 0.85)
	var hangar_w := minf(wide * 0.45, 70.0)
	var hangar := _site_spot(site, -wide * 0.5 + hangar_w * 0.5 + 6.0, 8.0, hangar_w, 28.0)
	_add_block(hangar, hangar_w, 28.0, 30.0 + 40.0 * big, Color(0.90, 0.91, 0.92), STYLE_PAINT, 0.0,
		Color(0.70, 0.72, 0.74), wall_list, roof_list)
	for n: int in 4:
		var tank := _site_spot(site, wide * 0.5 - 12.0 - (n % 2) * 9.0, 10.0 + (n / 2) * 9.0, 7.0, 7.0)
		_cylinder(chimney_list, tank["pos"], 3.2, 12.0, Color(0.93, 0.93, 0.92))
	var pad_back := deep - 8.0 - 30.0 * big
	var pad := _site_spot(site, 0.0, pad_back, 50.0 * big + 20.0, 50.0 * big + 20.0)
	var px: Vector3 = pad["x"]
	var pz: Vector3 = pad["z"]
	var repairing: bool = int(deal.get("repair_until", 0)) > int(sim.month)
	var pad_colour := Color(0.20, 0.20, 0.20) if repairing else CONCRETE
	_paving_items.append([Transform3D(Basis(px * (50.0 * big + 20.0), Vector3.UP * (float(pad["rise"]) + 0.6),
		pz * (50.0 * big + 20.0)), pad["pos"]), Color(pad_colour, _surface_of(pad_colour))])
	var tower_h := 50.0 + 90.0 * big
	var mid_back := pad_back + (50.0 * big + 20.0) * 0.5
	_site_box(site, -8.0, mid_back - 5.0, 9.0, 9.0, tower_h, Color(0.18, 0.19, 0.21))       # launch tower
	_site_box(site, -2.5, mid_back - 2.0, 6.0, 1.5, 1.5, Color(0.18, 0.19, 0.21),
		float((pad["pos"] as Vector3).y) + tower_h * 0.8)                                        # its arm
	if not repairing:
		var rocket := _site_spot(site, 4.0, mid_back - 4.5, 9.0, 9.0)
		var base: Vector3 = rocket["pos"]
		var booster := tower_h * 0.5
		_cylinder(chimney_list, base + Vector3.UP * 1.0, 4.5, booster, steel)
		_cylinder(chimney_list, base + Vector3.UP * (1.0 + booster), 4.5, tower_h * 0.4, Color(0.86, 0.87, 0.89))
	# A fence round it all.
	for side: float in [-1.0, 1.0]:
		_site_box(site, side * (wide * 0.5 - 1.0), deep * 0.5, 0.15, deep - 2.0, 2.4, Color(0.30, 0.32, 0.30))
	_site_box(site, 0.0, 1.0, wide - 2.0, 0.15, 2.4, Color(0.30, 0.32, 0.30))


func _plan_site_works(site: Dictionary, wide: float, deep: float, margin: float, front_strip: float,
		hall_w: float, hall_d: float, wall_list: Array, roof_list: Array) -> void:
	# A site being built: bare earth, a concrete frame going up, cranes and cabins.
	var frame := _site_spot(site, 0.0, margin + front_strip, hall_w, hall_d)
	_add_block(frame, hall_w, hall_d, 6.0, CONCRETE, STYLE_PLANT, 0.0, CONCRETE, wall_list, roof_list)
	var cranes := maxi(int(hall_w / 45.0), 1) + (1 if hall_d > 80.0 else 0)
	for n: int in cranes:
		var along := -hall_w * 0.5 + (n + 0.5) * hall_w / cranes
		var back := margin + front_strip + hall_d * (0.3 if n % 2 == 0 else 0.7)
		_site_box(site, along, back, 2.0, 2.0, 42.0, Color(0.95, 0.75, 0.15))                    # mast
		var mast := _site_spot(site, along, back, 2.0, 2.0)
		var top := float((mast["pos"] as Vector3).y) + 42.0
		_site_box(site, along + 12.0, back, 36.0, 1.4, 1.4, Color(0.95, 0.75, 0.15), top)       # jib
		_site_box(site, along - 10.0, back, 5.0, 2.4, 2.4, Color(0.40, 0.42, 0.44), top - 0.5)   # counterweight
	for n: int in 4:
		_site_box(site, -hall_w * 0.5 + 4.0 + n * 7.0, margin + 2.0, 6.0, 2.6, 2.7, Color(0.85, 0.82, 0.30))   # site cabins
	# Hoarding round the site.
	_site_box(site, 0.0, 0.5, wide - 2.0, 0.2, 2.4, Color(0.16, 0.18, 0.20))
	for side: float in [-1.0, 1.0]:
		_site_box(site, side * (wide * 0.5 - 1.0), deep * 0.5, 0.2, deep - 2.0, 2.4, Color(0.16, 0.18, 0.20))


func _site_spot(site: Dictionary, along: float, back: float, w: float, d: float) -> Dictionary:
	# Like _place, for a whole site: along its front, back from it.
	var away: Vector2 = site["away"]
	var across: Vector2 = site["across"]
	var front: Vector2 = site["front"]
	var c := front + across * along + away * (back + d * 0.5)
	var base := INF
	var top := -INF
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			var q: Vector2 = c + across * (w * sx) + away * (d * sz)
			var corner := height_at(q.x, q.y)
			base = minf(base, corner)
			top = maxf(top, corner)
	base = maxf(base, 0.3) - 0.3
	return {"pos": Vector3(c.x, base, c.y), "x": Vector3(across.x, 0.0, across.y), "z": Vector3(away.x, 0.0, away.y),
		"rise": maxf(top, 0.3) - 0.3 - base, "ground": maxf(height_at(c.x, c.y), 0.0)}


func _site_box(site: Dictionary, along: float, back: float, w: float, d: float, h: float, colour: Color,
		at_height: float = -INF) -> void:
	# A box on a site (or on a roof: at_height is its base, in metres above sea level).
	var away: Vector2 = site["away"]
	var across: Vector2 = site["across"]
	var front: Vector2 = site["front"]
	var c := front + across * along + away * (back + d * 0.5)
	var y := at_height if at_height > -INF else maxf(height_at(c.x, c.y), 0.0) - 0.1
	_prop_items.append([Transform3D(Basis(Vector3(across.x, 0.0, across.y) * w, Vector3.UP * h,
		Vector3(away.x, 0.0, away.y) * d), Vector3(c.x, y, c.y)), colour])


func _sea_side(i: int) -> Vector2i:
	# The direction of the sea from a tile by the shore (or (0, 0)).
	var tile := Vector2i(i % map_w, i / map_w)
	for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n := tile + d
		if n.x >= 0 and n.y >= 0 and n.x < map_w and n.y < map_h and water[n.y * map_w + n.x] == 1:
			return d
	return Vector2i.ZERO


func _columns(spot: Dictionary, d: float, count: int, span: float, height: float, colour: Color,
		wall_list: Array, roof_list: Array) -> void:
	# A classical portico: a row of columns in front of the door under a pediment.
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var pos: Vector3 = spot["pos"]
	for k in count:
		var along := -span * 0.5 + span * k / maxf(count - 1, 1)
		var at: Vector3 = pos + x_axis * along - z_axis * (d * 0.5 + 2.5)
		_box_item(wall_list, at, x_axis, z_axis, Vector3(0.9, height, 0.9), colour, STYLE_PAINT)
	var top: Vector3 = pos + Vector3.UP * height - z_axis * (d * 0.5 + 1.5)
	_box_item(wall_list, top, x_axis, z_axis, Vector3(span + 2.0, 0.9, 4.0), colour, STYLE_PAINT)
	roof_list.append([Transform3D(Basis(x_axis * (span + 2.4), Vector3.UP * 2.4, z_axis * 4.4),
		top + Vector3.UP * 0.9), colour.darkened(0.1)])


func _plan_building(i: int, t: int, wall_list: Array, roof_list: Array, chimney_list: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 4421 + t
	var front := _frontage(i)
	var depth := _depth(i, front)
	var tile := Vector2i(i % map_w, i / map_w)
	var c2 := tile_centre(tile)
	var centre := Vector3(c2.x, maxf(height_at(c2.x, c2.y), 0.0), c2.y)
	match t:
		Tile.GAS:
			if _models.has("gas_plant"):
				# Clad turbine hall, two boilers with slim stacks, a gasholder, tanks and pipes.
				var site := _place(i, front, 0.0, 3.0, 44.0, 44.0)
				_add_model("gas_plant", site, 44.0, 44.0, _model_total("gas_plant"), GAS_SILVER, GAS_BLUE)
			else:
				var hall := _place(i, front, -6.0, 6.0, 30.0, 18.0)
				_add_block(hall, 30.0, 18.0, 14.0, Color(0.52, 0.60, 0.68), STYLE_INDUSTRY, 2.0,
					SHED_METAL.darkened(0.2), wall_list, roof_list)
				var boiler := _place(i, front, -6.0, 27.0, 20.0, 12.0)
				_add_block(boiler, 20.0, 12.0, 24.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, roof_list)
				for along: float in [10.0, 17.0]:
					var stack := _place(i, front, along, 30.0, 3.0, 3.0)
					_cylinder(chimney_list, stack["pos"], 1.6, 46.0, Color(0.78, 0.78, 0.76))
				var tank := _place(i, front, 16.0, 10.0, 10.0, 10.0)
				_cylinder(chimney_list, tank["pos"], 4.5, 8.0, Color(0.86, 0.86, 0.84))
			_plan_fence(i, front, depth)
		Tile.NUCLEAR:
			if _models.has("nuclear_plant"):
				# Domed containment, turbine hall, vent stack and two cooling towers.
				var site := _place(i, front, 0.0, 2.0, 46.0, 46.0)
				_add_model("nuclear_plant", site, 46.0, 46.0, _model_total("nuclear_plant"), NUCLEAR_CONCRETE,
					NUCLEAR_BLUE)
			else:
				for along: float in [-12.0, 12.0]:
					var tower := _place(i, front, along, 32.0, 20.0, 20.0)
					_cylinder(chimney_list, tower["pos"], 10.5, 44.0, Color(0.82, 0.82, 0.80))
				var reactor := _place(i, front, -14.0, 5.0, 16.0, 14.0)
				_add_block(reactor, 16.0, 14.0, 16.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, roof_list)
				var dome_at: Vector3 = reactor["pos"]
				_cylinder(chimney_list, dome_at + Vector3.UP * 16.0, 6.5, 5.0, Color(0.74, 0.74, 0.72))
				var turbine := _place(i, front, 10.0, 5.0, 24.0, 12.0)
				_add_block(turbine, 24.0, 12.0, 12.0, Color(0.55, 0.62, 0.70), STYLE_INDUSTRY, 0.0, SLATE,
					wall_list, roof_list)
			_plan_fence(i, front, depth)
		Tile.WIND:
			# One turbine: a white tower, the nacelle facing the south-westerly wind,
			# three blades at a random angle, and a gravel pad.
			_slab(i, front, 0.0, 22.0, 8.0, 8.0, YARD)
			var base: Vector3 = centre
			var hub_h := 62.0
			_cylinder(chimney_list, base, 1.5, hub_h, TURBINE_WHITE)
			var into_wind := Vector3(-1.0, 0.0, 1.0).normalized()   # (a rotation axis must be exactly unit length)
			var side := Vector3.UP.cross(into_wind).normalized()
			var hub: Vector3 = base + Vector3.UP * hub_h
			_box_item(_prop_items, hub - into_wind * 3.0 + Vector3.DOWN * 1.5, side, into_wind,
				Vector3(3.0, 3.0, 9.0), TURBINE_WHITE)
			var rotor: Vector3 = hub + into_wind * 1.8
			var frame := Basis(side, Vector3.UP, into_wind)
			var phase := rng.randf() * TAU
			for k in 3:
				var spin := Basis(into_wind, phase + k * TAU / 3.0)
				var blade := spin * frame * Basis.from_scale(Vector3(1.4, 34.0, 0.35))
				_prop_items.append([Transform3D(blade, rotor), TURBINE_WHITE])
		Tile.SOLAR:
			# Rows of panels tilted to the south.
			for k in 6:
				var at := centre + Vector3(0.0, 0.6, -18.0 + k * 7.2)
				at.y = maxf(height_at(at.x, at.z), 0.0) + 0.6
				var panel := Basis(Vector3.RIGHT, deg_to_rad(-25.0)) * Basis.from_scale(Vector3(44.0, 0.12, 3.6))
				_prop_items.append([Transform3D(panel, at), PANEL_BLUE])
				for leg: float in [-18.0, 0.0, 18.0]:
					_prop_items.append([Transform3D(Basis.from_scale(Vector3(0.2, 1.2, 0.2)),
						at + Vector3(leg, -1.0, 0.0)), CHARCOAL])
		Tile.WATER_PUMP:
			var house := _place(i, front, -12.0, 5.0, 12.0, 9.0)
			_add_block(house, 12.0, 9.0, 5.5, RED_SANDSTONE, STYLE_PLANT, 3.0, SLATE, wall_list, roof_list)
			for along: float in [6.0, 18.0]:
				var tank := _place(i, front, along, 16.0, 10.0, 10.0)
				_cylinder(chimney_list, tank["pos"], 5.0, 7.0, TANK_GREY)
			_prop(i, front, 0.0, 12.0, 20.0, 0.8, 0.8, CHARCOAL)        # pipework
			_plan_fence(i, front, depth)
		Tile.WATER_TOWER:
			if _models.has("water_tower"):
				# Concrete shaft and tank, standing in the middle of the plot, its door to the street.
				var tower_spot := _place(i, front, 0.0, 0.0, 16.0, 16.0)
				tower_spot["pos"] = centre
				_add_model("water_tower", tower_spot, 16.0, 16.0, _model_total("water_tower"), CONCRETE, SLATE)
			else:
				_cylinder(chimney_list, centre, 2.4, 26.0, CONCRETE)
				_cylinder(chimney_list, centre + Vector3.UP * 26.0, 7.5, 9.0, Color(0.80, 0.82, 0.84))
			var hut := _place(i, front, 14.0, 4.0, 6.0, 5.0)
			_add_block(hut, 6.0, 5.0, 3.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, roof_list)
		Tile.LANDFILL:
			# A stepped mound of covered tips, a track and a lorry or two.
			_slab(i, front, 0.0, 6.0, 44.0, depth - 10.0, SOIL, 1.5)
			_slab(i, front, 0.0, 10.0, 34.0, depth - 18.0, Color(0.40, 0.36, 0.30), 3.5)
			_slab(i, front, 2.0, 15.0, 22.0, depth - 28.0, Color(0.36, 0.34, 0.29), 5.5)
			_slab(i, front, -20.0, 0.0, 4.0, 10.0, YARD)
			_prop(i, front, -20.0, 2.0, 2.6, 7.0, 3.2, CRANE_YELLOW)
			_plan_fence(i, front, depth)
		Tile.RECYCLING:
			var shed := _place(i, front, -5.0, 8.0, 32.0, 20.0)
			_add_block(shed, 32.0, 20.0, 10.0, SHED_GREEN, STYLE_INDUSTRY, 2.0, SHED_METAL.darkened(0.2),
				wall_list, roof_list)
			var skips := [Color(0.20, 0.45, 0.25), Color(0.15, 0.30, 0.60), Color(0.50, 0.35, 0.20),
				Color(0.55, 0.55, 0.55)]
			for k in 6:
				_prop(i, front, -19.0 + k * 6.5, depth - 10.0, 2.6, 6.0, 2.4, skips[k % 4])
		Tile.INCINERATOR:
			# A clad hall over the furnace, a concrete tipping bunker the bin lorries back
			# into, and one tall chimney (it smokes like the coal plant's, only from one stack).
			var hall := _place(i, front, -6.0, 14.0, 28.0, 22.0)
			_add_block(hall, 28.0, 22.0, 18.0, SHED_METAL, STYLE_INDUSTRY, 2.0, SHED_METAL.darkened(0.2),
				wall_list, roof_list)
			var bunker := _place(i, front, -6.0, 5.0, 20.0, 9.0)
			_add_block(bunker, 20.0, 9.0, 8.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, roof_list)
			var stack := _place(i, front, 15.0, 28.0, 4.0, 4.0)
			var stack_pos: Vector3 = stack["pos"]
			_cylinder(chimney_list, stack_pos, 2.0, 55.0, Color(0.80, 0.80, 0.78))
			_smoke_points.append(stack_pos + Vector3.UP * 56.0)
			for k in 2:
				_prop(i, front, 13.0 + k * 5.0, 6.0, 2.6, 8.0, 3.4, Color(0.22, 0.42, 0.28))   # bin lorries
			_plan_fence(i, front, depth)
		Tile.DATA_CENTRE, Tile.GIGAFACTORY, Tile.TECH_CAMPUS, Tile.LAUNCH_SITE, Tile.AI_DATA_CENTRE:
			# A company's project (data centre, Gigafactory) is drawn whole, from the first tile of its site
			# (_plan_data_centre); its other tiles draw nothing. An odd-shaped site
			# (or a tile with no deal) falls back to a hall per tile.
			if _plan_data_centre(i, wall_list, roof_list, chimney_list):
				return
			var hall := _place(i, front, 0.0, 1.0, 49.0, 47.0)
			_add_block(hall, 49.0, 47.0, 13.0, DC_CLADDING, STYLE_PAINT, 0.0, DC_ROOF, wall_list, roof_list)
			for k in 6:
				_prop(i, front, -16.0 + (k % 3) * 16.0, 9.0 + (k / 3) * 20.0, 10.0, 7.0, 2.6, DC_CHILLER, 13.0)
			for k in 3:
				_prop(i, front, -20.0 + k * 6.0, -1.5, 4.5, 2.4, 2.6, Color(0.30, 0.34, 0.38))   # generators
		Tile.AIRPORT:
			_plan_airport(i, rng, wall_list, roof_list, chimney_list)
		Tile.BIG_BEN, Tile.COLOSSEUM, Tile.GREAT_PYRAMID, Tile.LIBERTY, Tile.TAJ_MAHAL, Tile.OPERA_HOUSE, \
				Tile.EIFFEL, Tile.EMPIRE_STATE:
			_plan_landmark(i, t, front, wall_list, roof_list)
		Tile.GOLF:
			# Fairway (the ground colour), a green with its flag, bunkers, a tee and
			# a few trees in the rough.
			# (The green, bunkers and tee are painted by the shader, lots.gdshaderinc golf(),
			# from the same hashes.)
			var green_at := Vector2((_field_rand(tile.x, tile.y, 121) - 0.5) * 24.0,
				14.0 + _field_rand(tile.x, tile.y, 122) * (depth - 30.0))
			var flag := _place(i, front, green_at.x + 2.0, green_at.y - 0.05, 0.1, 0.1)
			var flag_pos: Vector3 = flag["pos"]
			flag_pos.y = float(flag["ground"])
			_prop_items.append([Transform3D(Basis.from_scale(Vector3(0.08, 2.4, 0.08)), flag_pos), WHITE_RENDER])
			_prop_items.append([Transform3D(Basis.from_scale(Vector3(0.9, 0.6, 0.05)),
				flag_pos + Vector3(0.45, 1.8, 0.0)), Color(0.85, 0.12, 0.10)])
			# The clubhouse: one at the start of each stretch of course along a road.
			var side := Vector2i(front.y, -front.x)
			var before := tile - side
			var club_here: bool = _is_road(tile + front) and not (before.x >= 0 and before.y >= 0
				and before.x < map_w and before.y < map_h and sim.tiles[before.y * map_w + before.x] == Tile.GOLF)
			if club_here:
				var club := _place(i, front, -14.0, 2.0, 18.0, 11.0)
				if _models.has("clubhouse"):
					_add_model("clubhouse", club, 18.0, 11.0, _model_total("clubhouse"), MODERN_WHITE, TIMBER)
				else:
					_add_block(club, 18.0, 11.0, 7.0, MODERN_WHITE, STYLE_MODERN, 0.0, SLATE, wall_list, roof_list)
				_slab(i, front, 2.0, 1.0, 12.0, 9.0, CAR_PARK)
				for k in 2:
					_parked_car(i, front, -1.0 + k * 5.0, 2.0, true, rng)
			for k in 3:
				var along := rng.randf_range(-23.0, 23.0) * (1 if k % 2 == 0 else -1)
				var back := rng.randf_range(4.0, depth - 4.0)
				var tree_h := rng.randf_range(6.0, 12.0)
				var kind: int = TreeKind.PINE if rng.randf() < 0.5 else TreeKind.BROADLEAF
				if club_here and along < 8.0 and back < 16.0:
					continue     # not in the clubhouse or its car park
				_plant(i, front, along, back, tree_h, kind, rng)
		Tile.LIBRARY:
			_slab(i, front, 0.0, 0.0, 49.0, 9.0, PAVEMENT)
			var spot := _place(i, front, 0.0, 9.0, 26.0, 16.0)
			_classical_block(spot, 26.0, 16.0, 2, CREAM_STONE, false, false, wall_list, roof_list)
			_columns(spot, 16.0, 4, 10.0, 7.5, CREAM_STONE.lightened(0.1), wall_list, roof_list)
			_dome(Vector3(spot["pos"]) + Vector3.UP * (4.2 + 3.4 + 0.6 + 0.9 + 4.0), 4.0, COPPER_GREEN)
			for k in 4:
				_plant(i, front, -20.0 + (k % 2) * 40.0, 12.0 + (k / 2) * 14.0, rng.randf_range(7.0, 10.0),
					TreeKind.BROADLEAF, rng)
			_street_furniture(i, front, false)
		Tile.MUSEUM:
			_slab(i, front, 0.0, 0.0, 49.0, 10.0, PAVEMENT)
			var spot := _place(i, front, -5.0, 10.0, 34.0, 20.0)
			_classical_block(spot, 34.0, 20.0, 3, HONEY_STONE, false, false, wall_list, roof_list)
			_columns(spot, 20.0, 6, 16.0, 10.5, HONEY_STONE.lightened(0.12), wall_list, roof_list)
			_dome(Vector3(spot["pos"]) + Vector3.UP * (4.2 + 2 * 3.4 + 0.6 + 0.9 + 4.0), 5.5, COPPER_GREEN)
			var wing := _place(i, front, 18.0, 14.0, 12.0, 16.0)
			if _models.has("museum_wing"):
				_add_model("museum_wing", wing, 12.0, 16.0, _model_total("museum_wing"), HONEY_STONE, SLATE)
			else:
				_add_block(wing, 12.0, 16.0, 9.0, GLASS_FRAME, STYLE_GLASS, 0.0, SLATE, wall_list, roof_list)
		Tile.STADIUM:
			# A pitch with stands round it, roofs over the long sides and floodlights.
			var mid := depth * 0.5
			_slab(i, front, 0.0, mid - 11.0, 32.0, 22.0, LAWN)
			_slab(i, front, 0.0, mid - 0.08, 0.15, 22.0, BAY_LINE, 0.03)
			_slab(i, front, -16.0, mid - 11.0, 0.15, 22.0, BAY_LINE, 0.03)
			_slab(i, front, 16.0, mid - 11.0, 0.15, 22.0, BAY_LINE, 0.03)
			var stands := _models.has("stand")
			for back: float in [mid - 18.0, mid + 12.0]:
				var stand := _place(i, front, 0.0, back, 42.0, 6.0)
				if stands:
					# Seats in the team colour, facing the pitch.
					var facing := _turned(stand, 2) if back < mid else stand
					_add_model("stand", facing, 42.0, 6.0, _model_total("stand"), CONCRETE, TEAM_BLUE)
					continue
				_add_block(stand, 42.0, 6.0, 9.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, roof_list)
				var roof_at: Vector3 = stand["pos"]
				_box_item(wall_list, roof_at + Vector3.UP * 11.0, stand["x"], stand["z"],
					Vector3(44.0, 0.5, 8.0), TEAM_BLUE, STYLE_PAINT)
			for along: float in [-20.0, 20.0]:
				var end := _place(i, front, along, mid - 11.0, 4.0, 22.0)
				if stands:
					# Covered terraces behind the goals: the stand, turned and lower.
					_add_model("stand", _turned(end, 1 if along < 0.0 else 3), 22.0, 4.0, 6.0, CONCRETE, TEAM_BLUE)
				else:
					_add_block(end, 4.0, 22.0, 6.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, roof_list)
			for corner: Vector2 in [Vector2(-22.0, mid - 20.0), Vector2(22.0, mid - 20.0),
					Vector2(-22.0, mid + 19.0), Vector2(22.0, mid + 19.0)]:
				var post := _place(i, front, corner.x, corner.y, 1.0, 1.0)
				var post_pos: Vector3 = post["pos"]
				_cylinder(chimney_list, post_pos, 0.5, 30.0, CHARCOAL)
				_prop_items.append([Transform3D(Basis.from_scale(Vector3(3.5, 1.6, 0.6)),
					post_pos + Vector3.UP * 29.0), WHITE_RENDER])
		Tile.MARINA:
			# A clubhouse by the road; pontoons and yachts out on the water.
			var club := _place(i, front, -8.0, 5.0, 18.0, 11.0)
			if _models.has("clubhouse"):
				_add_model("clubhouse", club, 18.0, 11.0, _model_total("clubhouse"), MODERN_WHITE, TIMBER)
			else:
				_add_block(club, 18.0, 11.0, 7.0, MODERN_WHITE, STYLE_MODERN, 0.0, SLATE, wall_list, roof_list)
			_slab(i, front, 10.0, 3.0, 22.0, 14.0, CAR_PARK)
			_plan_on_water(i, rng, false)
		Tile.TOWN_HALL:
			_slab(i, front, 0.0, 0.0, 49.0, 12.0, PAVEMENT)
			var spot := _place(i, front, 0.0, 12.0, 36.0, 18.0)
			_classical_block(spot, 36.0, 18.0, 3, BLONDE_SANDSTONE, false, false, wall_list, roof_list)
			_columns(spot, 18.0, 4, 10.0, 11.0, BLONDE_SANDSTONE.lightened(0.12), wall_list, roof_list)
			var tower := _place(i, front, 0.0, 16.0, 7.0, 7.0)
			var tower_pos: Vector3 = tower["pos"]
			_add_block(tower, 7.0, 7.0, 32.0, BLONDE_SANDSTONE, STYLE_CLASSICAL, 5.0, COPPER_GREEN, wall_list, roof_list)
			_flag(_raised(_place(i, front, 0.0, 19.5, 0.2, 0.2), 37.0), 6.0, SALTIRE_BLUE)
			_box_item(wall_list, tower_pos + Vector3.UP * 26.0 - Vector3(tower["z"]) * 3.62,
				tower["x"], tower["z"], Vector3(2.6, 2.6, 0.2), WHITE_RENDER, STYLE_PAINT)   # clock
			for along: float in [-18.0, 18.0]:
				_plant(i, front, along, 5.0, rng.randf_range(7.0, 9.0), TreeKind.BROADLEAF, rng)
			# A statue on a plinth in the square, benches facing it.
			_prop(i, front, 0.0, 4.5, 2.4, 2.4, 1.6, CREAM_STONE)
			_prop(i, front, 0.0, 5.3, 0.8, 0.8, 2.2, BRONZE.darkened(0.2), 1.5)
			for along: float in [-7.0, 7.0]:
				_prop(i, front, along, 5.5, 1.8, 0.55, 0.45, BENCH)
		Tile.BUS_DEPOT:
			_slab(i, front, 0.0, 0.0, 49.0, depth - 1.0, CAR_PARK)
			var shed := _place(i, front, 0.0, depth - 26.0, 44.0, 22.0)
			_add_block(shed, 44.0, 22.0, 8.0, GREY_RENDER, STYLE_INDUSTRY, 1.6, SHED_METAL.darkened(0.2),
				wall_list, roof_list)
			for k in 6:
				if rng.randf() < 0.8:
					_prop(i, front, -17.5 + k * 7.0, 4.0, 2.6, 12.0, 3.4,
						BUS_RED if rng.randf() < 0.6 else Color(0.15, 0.45, 0.30))
		Tile.STATION:
			# Station building by the street, a platform with a canopy, the tracks and a train.
			var spot := _place(i, front, 0.0, 3.0, 26.0, 11.0)
			_classical_block(spot, 26.0, 11.0, 2, RED_SANDSTONE, false, false, wall_list, roof_list)
			_slab(i, front, 0.0, 15.0, 49.0, 4.0, PAVEMENT, 0.6)
			var canopy := _place(i, front, 0.0, 15.0, 40.0, 4.0)
			var canopy_pos: Vector3 = canopy["pos"]
			_box_item(wall_list, canopy_pos + Vector3.UP * 4.2 + Vector3(canopy["z"]) * 2.0, canopy["x"],
				canopy["z"], Vector3(42.0, 0.3, 5.0), TRIM, STYLE_PAINT)
			_slab(i, front, 0.0, 20.0, 49.0, 10.0, Color(0.30, 0.29, 0.28))     # ballast
			for back: float in [22.0, 23.5, 26.0, 27.5]:
				_slab(i, front, 0.0, back, 49.0, 0.12, Color(0.55, 0.55, 0.56), 0.1)   # rails
			_prop(i, front, -2.0, 21.6, 44.0, 3.0, 3.8, TRAIN_RED)
		Tile.HARBOUR:
			# A quay with cranes and containers, a warehouse, and a ship alongside.
			_slab(i, front, 0.0, 0.0, 49.0, depth - 1.0, CONCRETE)
			var shed := _place(i, front, -10.0, 4.0, 26.0, 16.0)
			_add_block(shed, 26.0, 16.0, 10.0, SHED_METAL, STYLE_INDUSTRY, 2.0, SHED_METAL.darkened(0.2),
				wall_list, roof_list)
			for k in 8:
				_prop(i, front, 6.0 + (k % 4) * 4.0, 8.0 + (k / 4) * 7.0, 2.5, 6.1, 2.6 * (1 + k % 2),
					CONTAINERS[k % CONTAINERS.size()])
			_plan_on_water(i, rng, true)


# The landmarks: [model, first colour (stone, render), second colour (roofs, accents),
# metres back from the plot's front]. The two by the sea face the water.
const LANDMARKS := {
	Tile.BIG_BEN: ["big_ben", Color(0.74, 0.62, 0.42), Color(0.20, 0.22, 0.25), 16.0],
	Tile.COLOSSEUM: ["colosseum", Color(0.80, 0.72, 0.58), Color(0.78, 0.68, 0.48), 6.0],
	Tile.GREAT_PYRAMID: ["great_pyramid", Color(0.82, 0.72, 0.50), Color(0.78, 0.68, 0.48), 2.0],
	Tile.LIBERTY: ["liberty", Color(0.70, 0.66, 0.58), Color(0.42, 0.68, 0.60), 8.0],
	Tile.TAJ_MAHAL: ["taj_mahal", Color(0.95, 0.94, 0.91), Color(0.95, 0.94, 0.91), 2.0],
	Tile.OPERA_HOUSE: ["opera_house", Color(0.70, 0.56, 0.48), Color(0.95, 0.94, 0.91), 6.0],
	Tile.EIFFEL: ["eiffel", Color(0.44, 0.35, 0.27), Color(0.30, 0.25, 0.20), 3.0],
	Tile.EMPIRE_STATE: ["empire_state", Color(0.74, 0.72, 0.67), Color(0.30, 0.32, 0.35), 10.0],
}


func _plan_landmark(i: int, t: int, front: Vector2i, wall_list: Array, roof_list: Array) -> void:
	var look: Array = LANDMARKS[t]
	var model_name: String = look[0]
	var dims: Vector4 = MODEL_DIMS[model_name]
	var facing := front
	if bool(sim.info(t).get("near_sea", false)):
		var sea := _sea_side(i)
		if sea != Vector2i.ZERO:
			facing = sea
	var spot := _place(i, facing, 0.0, look[3], dims.x, dims.y)
	if _models.has(model_name):
		_add_model(model_name, spot, dims.x, dims.y, dims.z + dims.w, look[1], look[2])
	else:
		# No model file: a plain block of the right size and colour.
		_add_block(spot, dims.x * 0.6, dims.y * 0.6, dims.z, look[1], STYLE_CLASSICAL, 0.0, SLATE, wall_list, roof_list)


# Airport roles, as simulation.gd AirportRole (the runway, taxiway, apron and grass are
# painted by the shader; only what stands up is drawn here).
const AIRPORT_APRON := 3
const AIRPORT_TERMINAL := 5
const AIRPORT_TOWER := 6
const AIRPORT_HANGAR := 7
const TAIL_COLOURS := [Color(0.10, 0.25, 0.55), Color(0.75, 0.10, 0.10), Color(0.95, 0.60, 0.05),
	Color(0.05, 0.45, 0.40), Color(0.35, 0.15, 0.50), Color(0.15, 0.15, 0.18)]
const TOWER_GLASS := Color(0.10, 0.17, 0.22)


func _airport_spot(i: int, airside: Vector2i, along: float, back: float, w: float, d: float) -> Dictionary:
	# A spot on an airport tile, like _place gives: `back` metres from the tile's
	# landside edge towards the runway, `along` metres to one side.
	var centre := tile_centre(Vector2i(i % map_w, i / map_w))
	var away := Vector2(airside)
	var across := Vector2(away.y, -away.x)
	var mid := centre - away * (cell * 0.5) + across * along + away * (back + d * 0.5)
	var base := INF
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			var q: Vector2 = mid + across * (w * sx) + away * (d * sz)
			base = minf(base, height_at(q.x, q.y))
	base = maxf(base, 0.3) - 0.3
	return {"pos": Vector3(mid.x, base, mid.y), "x": Vector3(away.y, 0.0, -away.x), "z": Vector3(away.x, 0.0, away.y),
		"rise": 0.0, "ground": maxf(height_at(mid.x, mid.y), 0.0)}


func _airside(i: int) -> Vector2i:
	# Which way the runway lies from this airport tile (across the runway's line).
	var vertical: bool = (sim.airport_role[i] & 8) != 0
	var x := i % map_w
	var y := i / map_w
	for n in range(1, 40):
		for way: int in [1, -1]:
			var p := Vector2i(x + way * n, y) if vertical else Vector2i(x, y + way * n)
			if p.x < 0 or p.y < 0 or p.x >= map_w or p.y >= map_h:
				continue
			var k := p.y * map_w + p.x
			if sim.tiles[k] == Tile.AIRPORT and sim.airport_role_at(k) == 1:
				return Vector2i(way, 0) if vertical else Vector2i(0, way)
	return Vector2i(0, 1)


func _plan_airport(i: int, rng: RandomNumberGenerator, wall_list: Array, roof_list: Array,
		chimney_list: Array) -> void:
	if i >= sim.airport_role.size():
		return
	var role: int = sim.airport_role_at(i)
	if role < AIRPORT_APRON or role == 4:
		return
	var airside := _airside(i)
	match role:
		AIRPORT_APRON:
			# An airliner on its stand, nose in towards the terminal.
			if rng.randf() < 0.75:
				_airliner(_airport_spot(i, airside, rng.randf_range(-3.0, 3.0), 7.0, 30.0, 34.0),
					TAIL_COLOURS[rng.randi_range(0, TAIL_COLOURS.size() - 1)])
			_prop_items.append([Transform3D(Basis.from_scale(Vector3(2.2, 2.0, 5.0)),
				_airport_spot(i, airside, 19.0, 4.0, 2.2, 5.0)["pos"]), AMBULANCE_YELLOW])     # a tug
		AIRPORT_TERMINAL:
			# A long glass hall under a white roof, a pier out to the stands with two
			# air bridges, and a drop-off canopy on the landside.
			var hall := _airport_spot(i, airside, 0.0, 5.0, 50.0, 24.0)
			_add_block(hall, 50.0, 24.0, 11.0, GLASS_FRAME, STYLE_GLASS, 0.0, SLATE, wall_list, roof_list)
			var hall_pos: Vector3 = hall["pos"]
			_box_item(_prop_items, hall_pos + Vector3.UP * 11.0, hall["x"], hall["z"], Vector3(50.0, 0.9, 28.0), MODERN_WHITE)
			_box_item(_prop_items, hall_pos + Vector3.UP * 11.9, hall["x"], hall["z"], Vector3(50.0, 1.4, 12.0), MODERN_WHITE)
			var canopy := _airport_spot(i, airside, 0.0, 0.5, 44.0, 4.5)
			var canopy_pos: Vector3 = canopy["pos"]
			_box_item(_prop_items, canopy_pos + Vector3.UP * 4.6, canopy["x"], canopy["z"], Vector3(44.0, 0.4, 5.0), MODERN_WHITE)
			var pier := _airport_spot(i, airside, 0.0, 29.0, 9.0, 21.0)
			_add_block(pier, 9.0, 21.0, 7.5, MODERN_WHITE, STYLE_MODERN, 0.0, SLATE, wall_list, roof_list)
			for side: float in [-1.0, 1.0]:
				var bridge := _airport_spot(i, airside, side * 9.5, 40.0, 10.0, 2.6)
				var bridge_pos: Vector3 = bridge["pos"]
				_box_item(_prop_items, bridge_pos + Vector3.UP * 3.6, bridge["x"], bridge["z"], Vector3(10.0, 2.6, 2.6), TRIM)
				_box_item(_prop_items, bridge_pos + bridge["x"] * (side * 4.0), bridge["x"], bridge["z"],
					Vector3(0.8, 3.6, 0.8), CHARCOAL)
		AIRPORT_TOWER:
			# The control tower: a concrete shaft, a glazed cab and its roof, with a
			# low operations block and the fire crew's shed beside it.
			var foot: Vector3 = _airport_spot(i, airside, -10.0, 20.0, 8.0, 8.0)["pos"]
			_cylinder(chimney_list, foot, 3.4, 32.0, CONCRETE)
			_cylinder(chimney_list, foot + Vector3.UP * 32.0, 6.0, 4.6, TOWER_GLASS)
			_cylinder(chimney_list, foot + Vector3.UP * 36.6, 6.6, 0.7, MODERN_WHITE)
			_cylinder(chimney_list, foot + Vector3.UP * 37.3, 0.25, 7.0, CHARCOAL)
			var ops := _airport_spot(i, airside, 8.0, 6.0, 26.0, 13.0)
			_add_block(ops, 26.0, 13.0, 7.0, MODERN_WHITE, STYLE_MODERN, 0.0, SLATE, wall_list, roof_list)
			var crew := _airport_spot(i, airside, 12.0, 30.0, 18.0, 12.0)
			_add_block(crew, 18.0, 12.0, 6.0, FIRE_RED.darkened(0.15), STYLE_INDUSTRY, 0.0, SLATE, wall_list, roof_list)
			_prop_items.append([Transform3D(Basis.from_scale(Vector3(2.6, 3.2, 8.5)),
				_airport_spot(i, airside, 12.0, 43.0, 2.6, 8.5)["pos"]), FIRE_RED])
		AIRPORT_HANGAR:
			# A big hangar with its doors to the airfield.
			var shed := _turned(_airport_spot(i, airside, 0.0, 6.0, 44.0, 36.0), 2)
			_add_block(shed, 44.0, 36.0, 14.0, SHED_METAL, STYLE_INDUSTRY, 0.0, SLATE, wall_list, roof_list)
			var shed_pos: Vector3 = shed["pos"]
			_box_item(_prop_items, shed_pos + Vector3.UP * 14.0, shed["x"], shed["z"], Vector3(45.0, 1.2, 37.0),
				SHED_METAL.darkened(0.25))
			_front_panel(shed, 36.0, 0.0, 0.0, 36.0, 11.0, SHED_METAL.lightened(0.25), wall_list)


func _airliner(spot: Dictionary, tail: Color) -> void:
	# A twin-jet airliner out of boxes, about 32 m long: its nose at the spot's
	# landside end, its tail towards the runway.
	var x_axis: Vector3 = spot["x"]
	var z_axis: Vector3 = spot["z"]
	var at: Vector3 = spot["pos"]
	at.y = float(spot["ground"])
	var white := Color(0.94, 0.94, 0.93)
	_box_item(_prop_items, at + Vector3.UP * 2.0, x_axis, z_axis, Vector3(3.6, 3.6, 30.0), white)            # fuselage
	_box_item(_prop_items, at + Vector3.UP * 2.3 - z_axis * 16.2, x_axis, z_axis, Vector3(2.6, 2.8, 2.6), white)  # nose
	_box_item(_prop_items, at + Vector3.UP * 2.5 + z_axis * 1.0, x_axis, z_axis, Vector3(30.0, 0.5, 5.0), Color(0.80, 0.81, 0.82))
	_box_item(_prop_items, at + Vector3.UP * 4.4 + z_axis * 13.2, x_axis, z_axis, Vector3(11.0, 0.4, 3.0), white)
	_box_item(_prop_items, at + Vector3.UP * 5.6 + z_axis * 12.6, x_axis, z_axis, Vector3(0.5, 5.6, 4.6), tail)   # fin
	_box_item(_prop_items, at + Vector3.UP * 2.0 + z_axis * 13.0, x_axis, z_axis, Vector3(3.7, 1.2, 4.0), tail)
	for side: float in [-1.0, 1.0]:
		_box_item(_prop_items, at + Vector3.UP * 0.9 + x_axis * (side * 5.2) - z_axis * 1.5, x_axis, z_axis,
			Vector3(1.9, 1.9, 3.8), Color(0.72, 0.73, 0.75))


func _plan_fence(i: int, front: Vector2i, depth: float) -> void:
	var fence := Color(0.35, 0.38, 0.36)
	_prop(i, front, 0.0, 0.5, 48.0, 0.15, 2.4, fence)
	_prop(i, front, 0.0, depth - 1.5, 48.0, 0.15, 2.4, fence)
	_prop(i, front, -24.0, 0.5, 0.15, depth - 2.0, 2.4, fence)
	_prop(i, front, 24.0, 0.5, 0.15, depth - 2.0, 2.4, fence)


func _plan_on_water(i: int, rng: RandomNumberGenerator, harbour: bool) -> void:
	# Out on the sea beside the plot: pontoons and yachts (marina) or a crane,
	# the quay edge and a ship (harbour).
	var sea := _sea_side(i)
	if sea == Vector2i.ZERO:
		return
	var out := Vector3(sea.x, 0.0, sea.y)                # towards the sea
	var along := Vector3(-sea.y, 0.0, sea.x)
	var c2 := tile_centre(Vector2i(i % map_w, i / map_w))
	var shore := Vector3(c2.x, 0.0, c2.y) + out * (cell * 0.5)
	if harbour:
		_box_item(_prop_items, shore + Vector3.DOWN * 2.0, along, out, Vector3(50.0, 3.2, 6.0), CONCRETE)
		for k in 2:
			var base := shore - out * 2.0 + along * (-12.0 + k * 24.0)
			_box_item(_prop_items, base, along, out, Vector3(1.6, 30.0, 1.6), CRANE_YELLOW)
			_box_item(_prop_items, base + Vector3.UP * 28.0 + out * 10.0, along, out,
				Vector3(1.4, 1.4, 28.0), CRANE_YELLOW)
		var ship := shore + out * 12.0 + Vector3.DOWN * 1.5
		_box_item(_prop_items, ship, along, out, Vector3(44.0, 6.5, 10.0), SHIP_HULL)
		_box_item(_prop_items, ship + Vector3.UP * 6.5 - along * 16.0, along, out, Vector3(8.0, 8.0, 9.0), HULL_WHITE)
		return
	# Marina: a main pontoon out from the shore with fingers and yachts.
	_box_item(_prop_items, shore + out * 18.0 + Vector3.DOWN * 0.2, along, out, Vector3(2.4, 0.5, 36.0),
		Color(0.55, 0.50, 0.42))
	for k in 5:
		var at := shore + out * (6.0 + k * 7.0) + Vector3.DOWN * 0.2
		for s: float in [-1.0, 1.0]:
			_box_item(_prop_items, at + along * s * 5.0, along, out, Vector3(8.0, 0.5, 1.2),
				Color(0.55, 0.50, 0.42))
			if rng.randf() < 0.7:
				var boat := at + along * s * 5.5 + out * 3.0 + Vector3.DOWN * 0.3
				_box_item(_prop_items, boat, out, along, Vector3(2.6, 1.3, 8.0), HULL_WHITE)
				_box_item(_prop_items, boat + Vector3.UP * 1.3, out, along, Vector3(1.8, 1.0, 3.0), HULL_WHITE)
				_box_item(_prop_items, boat + Vector3.UP * 1.3, out, along, Vector3(0.15, 11.0, 0.15), WHITE_RENDER)


func _plan_plant(i: int, wall_list: Array, chimney_list: Array) -> void:
	var front := _frontage(i)
	var depth := _depth(i, front)
	_slab(i, front, 0.0, 0.0, 49.0, depth - 1.0, YARD)
	if _models.has("coal_plant"):
		# Turbine hall, boiler house, precipitator, twin chimneys, coal stock and conveyor.
		var site := _place(i, front, 0.0, 3.0, 44.0, 44.0)
		_add_model("coal_plant", site, 44.0, 44.0, _model_total("coal_plant"), CONCRETE, PLANT_BLUE)
		# Smoke from the model's two chimney tops (18.5 m to the side, 3.2 m and 13.5 m
		# behind its centre, 66 m up; see coal_plant() in tools/make_buildings.py).
		var site_pos: Vector3 = site["pos"]
		var site_x: Vector3 = site["x"]
		var site_z: Vector3 = site["z"]
		for behind: float in [3.2, 13.5]:
			_smoke_points.append(site_pos + site_x * 18.5 + site_z * behind + Vector3.UP * 66.0)
		_plan_fence(i, front, depth)
		return
	var spot := _place(i, front, -6.0, 6.0, 30.0, 26.0)
	_add_block(spot, 30.0, 26.0, 18.0, CONCRETE, STYLE_PLANT, 0.0, SLATE, wall_list, [])
	for along: float in [12.0, 19.0]:
		var stack := _place(i, front, along, 30.0, 5.0, 5.0)
		var pos: Vector3 = stack["pos"]
		chimney_list.append([Transform3D(Basis.from_scale(Vector3(3.0, 65.0, 3.0)),
			pos + Vector3.UP * 32.5), Color(0.75, 0.74, 0.72)])
		_smoke_points.append(pos + Vector3.UP * 66.0)
	_plan_fence(i, front, depth)       # security fence round the edge


# -------------------------------------------------------------------- smoke

func _build_smoke() -> void:
	# A soft grey puff that always faces the camera; each chimney gets a stream of them.
	var puff := Gradient.new()
	puff.set_color(0, Color(1, 1, 1, 1))
	puff.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = puff
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.roughness = 1.0
	_smoke_mesh.size = Vector2(1, 1)
	_smoke_mesh.material = mat
	add_child(smoke)


func _new_smoke_stream() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _smoke_mesh
	p.amount = 20
	p.lifetime = 12.0
	p.preprocess = 12.0                 # already billowing when it first appears
	p.local_coords = false              # puffs stay where they are if the plant is rebuilt
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 7.0
	p.damping_min = 0.3
	p.damping_max = 0.5
	p.gravity = Vector3(2.0, 0.8, 0.8)  # rises slowly and drifts on the breeze
	p.scale_amount_min = 14.0
	p.scale_amount_max = 20.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.62, 0.62, 0.60, 0.55))
	fade.set_color(1, Color(0.75, 0.75, 0.74, 0.0))
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.add_child(p)
	return p


func _place_smoke() -> void:
	# One stream per chimney top (up to MAX_SMOKE); spare streams are switched off.
	var count := mini(_smoke_points.size(), MAX_SMOKE)
	for n: int in count:
		if n == _smoke_items.size():
			_smoke_items.append(_new_smoke_stream())
		var stream := _smoke_items[n]
		stream.position = _smoke_points[n]
		stream.visible = true
		if not stream.emitting:
			stream.emitting = true
	for n: int in range(count, _smoke_items.size()):
		var spare := _smoke_items[n]
		spare.emitting = false
		spare.visible = false


# -------------------------------------------------------------------- trees

func _tree_multimesh(node: MultiMeshInstance3D, mesh: Mesh, shadows: bool, canopy: bool) -> void:
	if canopy:
		var leaves := ShaderMaterial.new()
		leaves.shader = FOLIAGE_SHADER
		node.material_override = leaves
	else:
		var bark := StandardMaterial3D.new()
		bark.vertex_color_use_as_albedo = true
		bark.vertex_color_is_srgb = true
		bark.roughness = 0.95
		node.material_override = bark
	node.multimesh = _new_multimesh(mesh, false)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _build_trees() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.3
	trunk_mesh.bottom_radius = 0.5
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	var crown_mesh := SphereMesh.new()       # one blob of a canopy
	crown_mesh.radius = 0.5
	crown_mesh.height = 1.0
	crown_mesh.radial_segments = 9
	crown_mesh.rings = 6
	var cone_mesh := CylinderMesh.new()      # one tier of a spruce
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 0.5
	cone_mesh.height = 1.0
	cone_mesh.radial_segments = 9
	cone_mesh.rings = 2
	_tree_multimesh(city_trunks, trunk_mesh, false, false)
	_tree_multimesh(city_crowns, crown_mesh, true, true)
	_tree_multimesh(city_cones, cone_mesh, true, true)
	_wood_meshes = [trunk_mesh, crown_mesh, cone_mesh]

	# The countryside's trees, tile by tile over the map and the land beyond it:
	# thick woods (bigger, closer trees inside, thinning at the edges), conifer
	# plantations, hedgerow trees along the field boundaries, gorse on rough
	# ground and the dunes, and the odd lone tree. Grouped in squares so the far
	# ones can be left out.
	add_child(woods)
	var gw := map_w + PADDING * 2
	var gh := map_h + PADDING * 2
	var per_row := ceili(float(gw) / TREE_CHUNK_TILES)
	var chunk_count := per_row * ceili(float(gh) / TREE_CHUNK_TILES)
	var lists: Array = []
	for n in chunk_count:
		lists.append([[], [], []])                 # trunk, canopy and cone items
	_tile_has_trees.resize(map_w * map_h)
	_tile_has_trees.fill(1)
	var clumps := FastNoiseLite.new()               # glades and thickets inside woods
	clumps.seed = 31
	clumps.frequency = 0.011
	_clumps = clumps                                # (planted woodland uses the same)
	_wood_per_row = per_row
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for gz in gh:
		for gx in gw:
			var g := gz * gw + gx
			var wood := _land_info[g * 4 + 1]
			var seaward := _land_info[g * 4 + 2]
			var corner := Vector2((gx - PADDING) * cell, (gz - PADDING) * cell)
			if wood > 0.15:
				# Thinner beyond the map edge, where they're only ever seen from afar.
				var outside := maxi(maxi(PADDING - gx, gx - (map_w + PADDING - 1)), maxi(PADDING - gz, gz - (map_h + PADDING - 1)))
				var thick := smoothstep(0.15, 0.75, wood) * (1.0 - 0.5 * smoothstep(4.0, 14.0, outside))
				for s in 9:
					var at := corner + Vector2((s % 3 + rng.randf_range(0.1, 0.9)) / 3.0,
						(s / 3 + rng.randf_range(0.1, 0.9)) / 3.0) * cell
					var clump := clumps.get_noise_2d(at.x, at.y) * 0.5 + 0.5
					if rng.randf() > thick * (0.45 + 0.8 * clump) or coast_at(at.x, at.y) < SHORE_LEVEL + 0.4:
						continue
					var inner := wood > 0.85 and clump > 0.45
					var kind := _wood_kind(wood, clump, rng)
					var tall := rng.randf_range(12.0, 20.0) if inner else rng.randf_range(8.0, 15.0)
					_add_wood_tree(lists, per_row, at, tall, kind, rng, 1.6 if inner else 1.15, inner)
				continue
			# Open land: gorse on rough ground and behind the beach, the odd lone tree.
			var centre := corner + Vector2(cell, cell) * 0.5
			var c := coast_at(centre.x, centre.y)
			if c < SHORE_LEVEL + 0.4:
				continue
			var h := _sample_height(centre)
			var steep := absf(_sample_height(centre + Vector2(cell, 0)) - _sample_height(centre - Vector2(cell, 0))) \
				+ absf(_sample_height(centre + Vector2(0, cell)) - _sample_height(centre - Vector2(0, cell)))
			var rough := maxf(maxf(smoothstep(0.25, 0.6, seaward), smoothstep(18.0, 40.0, steep)),
				smoothstep(FARM_MAX_HEIGHT - 20.0, FARM_MAX_HEIGHT + 10.0, h))
			var patch := clumps.get_noise_2d(centre.x * 1.7, centre.y * 1.7) * 0.5 + 0.5
			if rough > 0.2 and patch > 0.5:
				for k in rng.randi_range(1, 2 + int(rough * 4.0)):
					var at := corner + Vector2(rng.randf(), rng.randf()) * cell
					if coast_at(at.x, at.y) < SHORE_LEVEL + 0.3:
						continue
					_add_wood_tree(lists, per_row, at, rng.randf_range(1.2, 2.4), TreeKind.GORSE, rng, 1.0, false)
			if rng.randf() < 0.012 + 0.05 * rough:
				var at := corner + Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9)) * cell
				var kind := TreeKind.PINE if seaward > 0.3 else _wood_kind(0.2, 0.5, rng)
				_add_wood_tree(lists, per_row, at, rng.randf_range(8.0, 15.0), kind, rng, 1.0, false)
	_plant_plantations(lists, per_row, rng)
	_plant_hedgerows(lists, per_row, rng)

	var bark := StandardMaterial3D.new()
	bark.vertex_color_use_as_albedo = true
	bark.vertex_color_is_srgb = true
	bark.roughness = 0.95
	var leaves := ShaderMaterial.new()
	leaves.shader = FOLIAGE_SHADER
	_wood_bark = bark
	_wood_leaves = leaves
	for n in chunk_count:
		var chunk: Array = lists[n]
		for mesh_id: int in 3:
			var items: Array = chunk[mesh_id]
			var mm := _new_multimesh(_wood_meshes[mesh_id], false)
			_fill(mm, items, false)
			_wood_mms.append(mm)                     # number n * 3 + mesh_id
			if items.is_empty():
				continue
			var node := MultiMeshInstance3D.new()
			node.multimesh = mm
			node.material_override = bark if mesh_id == 0 else leaves
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mesh_id == 0 \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			woods.add_child(node)
			_wood_nodes.append(node)
			_natural_tree_parts += items.size()
	_set_tree_range(TREE_RANGE_MIN)


func _add_wood_tree(lists: Array, per_row: int, at: Vector2, tall: float, kind: int,
		rng: RandomNumberGenerator, spread: float, no_trunk: bool) -> void:
	# A natural tree, filed under its square, and under its map tile (if it's on
	# the map) so building there can hide it.
	var gx := clampi(floori(at.x / cell) + PADDING, 0, map_w + PADDING * 2 - 1)
	var gz := clampi(floori(at.y / cell) + PADDING, 0, map_h + PADDING * 2 - 1)
	var chunk_n := (gz / TREE_CHUNK_TILES) * per_row + gx / TREE_CHUNK_TILES
	var chunk: Array = lists[chunk_n]
	var tree := _tree(at, tall, kind, rng, spread, true)
	var tx := gx - PADDING
	var tz := gz - PADDING
	var tile := tz * map_w + tx if tx >= 0 and tz >= 0 and tx < map_w and tz < map_h else -1
	var parts: Array = []
	for mesh_id: int in 3:
		if mesh_id == 0 and no_trunk:
			continue    # deep in a wood the trunks can't be seen
		var items: Array = tree[mesh_id]
		var target: Array = chunk[mesh_id]
		for item: Array in items:
			if tile >= 0:
				parts.append(_part_xf.size())
				_part_xf.append(item[0])
				_part_mesh.append(chunk_n * 3 + mesh_id)
				_part_index.append(target.size())
			target.append(item)
	if tile >= 0:
		if not _parts_in_tile.has(tile):
			_parts_in_tile[tile] = []
		var in_tile: Array = _parts_in_tile[tile]
		in_tile.append_array(parts)


func _field_frame_bounds() -> Rect2:
	# The land with trees (map plus padding) in the fields' turned frame (u, v).
	var ca := cos(FIELD_ANGLE)
	var sa := sin(FIELD_ANGLE)
	var lo := Vector2(-PADDING, -PADDING) * cell
	var hi := Vector2(map_w + PADDING, map_h + PADDING) * cell
	var box := Rect2()
	var first := true
	for p: Vector2 in [lo, Vector2(hi.x, lo.y), Vector2(lo.x, hi.y), hi]:
		var q := Vector2(p.x * ca + p.y * sa, -p.x * sa + p.y * ca)
		if first:
			box = Rect2(q, Vector2.ZERO)
			first = false
		else:
			box = box.expand(q)
	return box


func _from_field_frame(u: float, v: float) -> Vector2:
	var ca := cos(FIELD_ANGLE)
	var sa := sin(FIELD_ANGLE)
	return Vector2(u * ca - v * sa, u * sa + v * ca)


func _on_padded_land(p: Vector2) -> bool:
	return p.x > -PADDING * cell and p.y > -PADDING * cell \
		and p.x < (map_w + PADDING) * cell and p.y < (map_h + PADDING) * cell


func _plant_plantations(lists: Array, per_row: int, rng: RandomNumberGenerator) -> int:
	# Spruce in close rows over the fields chosen as plantations (as the shader
	# picks them, so the dark needle ground lies under them).
	var box := _field_frame_bounds()
	var planted := 0
	const GAP := 13.0
	for r in range(floori(box.position.y / FIELD_ROW) - 1, floori(box.end.y / FIELD_ROW) + 2):
		var off := _field_rand(r, 0, 3)
		for c in range(floori(box.position.x / FIELD_COL - off) - 1, floori(box.end.x / FIELD_COL - off) + 2):
			var split := _field_rand(c, r, 5) < FIELD_SPLIT
			for sub in (2 if split else 1):
				var id := Vector2i(c, r * 2 + sub)
				if _field_rand(id.x, id.y, 12) >= PLANT_CHANCE:
					continue
				var u_lo := (c - 0.35 + off) * FIELD_COL - FIELD_WOBBLE
				var u_hi := (c + 1.35 + off) * FIELD_COL + FIELD_WOBBLE
				var v_lo := r * FIELD_ROW - FIELD_WOBBLE
				var v_hi := (r + 1) * FIELD_ROW + FIELD_WOBBLE
				var guess := _from_field_frame((u_lo + u_hi) * 0.5, (v_lo + v_hi) * 0.5)
				if not _on_padded_land(guess) or _sample_height(guess) < PLANT_MIN_HEIGHT - 8.0:
					continue
				var u := u_lo
				while u < u_hi:
					var v := v_lo
					while v < v_hi:
						var at := _from_field_frame(u + rng.randf_range(-1.5, 1.5), v + rng.randf_range(-1.5, 1.5))
						v += GAP
						if not _on_padded_land(at):
							continue
						var field := _field_at(at)
						var fid: Vector2i = field["id"]
						if fid != id or not _is_plantation(field) or coast_at(at.x, at.y) < SHORE_LEVEL + 0.4:
							continue
						var edge := minf(1.0, float(field["hedge"]) / 8.0)
						_add_wood_tree(lists, per_row, at, rng.randf_range(12.0, 17.0) * (0.85 + 0.15 * edge),
							TreeKind.SPRUCE, rng, 1.0, edge > 0.9)
						planted += 1
					u += GAP
	return planted


func _hedge_spot_ok(p: Vector2) -> bool:
	# Farmland, where the shader draws fields and hedges.
	if not _on_padded_land(p) or coast_at(p.x, p.y) < 0.98:
		return false
	var gx := floori(p.x / cell) + PADDING
	var gz := floori(p.y / cell) + PADDING
	if _land_value(gx, gz, 1) > 0.12 or _land_value(gx, gz, 2) > 0.08:
		return false
	var h := _sample_height(p)
	if h > FARM_MAX_HEIGHT - 5.0:
		return false
	var dx := _sample_height(p + Vector2(25.0, 0.0)) - _sample_height(p - Vector2(25.0, 0.0))
	var dz := _sample_height(p + Vector2(0.0, 25.0)) - _sample_height(p - Vector2(0.0, 25.0))
	return Vector2(dx, dz).length() < 30.0


func _hedge_tree(lists: Array, per_row: int, at: Vector2, rng: RandomNumberGenerator) -> void:
	# Mostly oak and ash grown up out of the hedge; some hawthorn.
	if rng.randf() < 0.25:
		_add_wood_tree(lists, per_row, at, rng.randf_range(4.5, 7.0), TreeKind.ORNAMENTAL, rng, 1.0, false)
	else:
		_add_wood_tree(lists, per_row, at, rng.randf_range(9.0, 15.0), TreeKind.BROADLEAF, rng, 1.0, false)


func _plant_hedgerows(lists: Array, per_row: int, rng: RandomNumberGenerator) -> int:
	# Trees standing in the hedges along the field boundaries.
	var box := _field_frame_bounds()
	var planted := 0
	for r in range(floori(box.position.y / FIELD_ROW) - 1, floori(box.end.y / FIELD_ROW) + 2):
		# The long boundaries (between rows of fields).
		var u := box.position.x
		while u < box.end.x:
			u += HEDGE_TREE_GAP * rng.randf_range(0.3, 1.7)
			if _field_rand(floori(u / 90.0), r, 7) >= FIELD_HEDGE:
				continue
			var at := _from_field_frame(u, _row_line(r, u) + rng.randf_range(-1.2, 1.2))
			if _hedge_spot_ok(at):
				_hedge_tree(lists, per_row, at, rng)
				planted += 1
		# The short boundaries (between the fields in this row), and splits.
		var off := _field_rand(r, 0, 3)
		for c in range(floori(box.position.x / FIELD_COL - off) - 1, floori(box.end.x / FIELD_COL - off) + 2):
			var v_mid := (r + 0.5) * FIELD_ROW
			var probe := _from_field_frame(_col_line(c, r, v_mid), v_mid)
			if not _on_padded_land(probe):
				continue
			if _field_rand(c, r, 8) < FIELD_HEDGE:
				var v := r * FIELD_ROW
				while v < (r + 1) * FIELD_ROW:
					v += HEDGE_TREE_GAP * rng.randf_range(0.3, 1.7)
					var at := _from_field_frame(_col_line(c, r, v) + rng.randf_range(-1.2, 1.2), v)
					var field := _field_at(at)
					var fid: Vector2i = field["id"]
					if fid.y / 2 == r and _hedge_spot_ok(at):
						_hedge_tree(lists, per_row, at, rng)
						planted += 1
			if _field_rand(c, r, 5) < FIELD_SPLIT and _field_rand(c, r, 9) < FIELD_HEDGE:
				var share := 0.35 + 0.3 * _field_rand(c, r, 6)
				var u_split := _col_line(c, r, v_mid)
				var u_end := _col_line(c + 1, r, v_mid)
				while u_split < u_end:
					u_split += HEDGE_TREE_GAP * rng.randf_range(0.3, 1.7)
					var v := lerpf(_row_line(r, u_split), _row_line(r + 1, u_split), share)
					var at := _from_field_frame(u_split, v + rng.randf_range(-1.2, 1.2))
					var field := _field_at(at)
					var fid: Vector2i = field["id"]
					if fid.x == c and _hedge_spot_ok(at):
						_hedge_tree(lists, per_row, at, rng)
						planted += 1
	return planted


func _set_tree_range(distance: float) -> void:
	# Leave out the woods beyond this distance (the ground under them is dark,
	# so they're still there from afar).
	if absf(distance - _tree_range) < _tree_range * 0.08:
		return
	_tree_range = distance
	if terrain_material:
		terrain_material.set_shader_parameter("tree_range", distance)
	for node in _wood_nodes:
		node.visibility_range_end = distance
		node.visibility_range_end_margin = distance * 0.1


func _wood_kind(woods: float, clump: float, rng: RandomNumberGenerator) -> int:
	# Mostly broadleaf (oak, ash, sycamore) with birch at the edges; stands of
	# Scots pine and spruce where the clump noise says so.
	var r := rng.randf()
	if woods > 0.6 and clump > 0.62 and r < 0.7:
		return TreeKind.SPRUCE if r < 0.45 else TreeKind.PINE
	if r < 0.07:
		return TreeKind.PINE
	if r < 0.14 + 0.2 * (1.0 - woods):
		return TreeKind.BIRCH
	return TreeKind.BROADLEAF


func _park_kind(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.45:
		return TreeKind.BROADLEAF
	if r < 0.62:
		return TreeKind.BIRCH
	if r < 0.72:
		return TreeKind.COPPER
	if r < 0.82:
		return TreeKind.ORNAMENTAL
	if r < 0.90:
		return TreeKind.COLUMNAR
	return TreeKind.PINE


func _garden_kind(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.28:
		return TreeKind.ORNAMENTAL
	if r < 0.46:
		return TreeKind.BIRCH
	if r < 0.64:
		return TreeKind.BROADLEAF
	if r < 0.80:
		return TreeKind.COLUMNAR      # leylandii and the like
	if r < 0.92:
		return TreeKind.COPPER
	return TreeKind.SPRUCE


func _plant(i: int, front: Vector2i, along: float, back: float, tall: float, kind: int,
		rng: RandomNumberGenerator) -> void:
	# A tree on a plot, planted with the other city trees.
	var k: int = _garden_kind(rng) if kind == TreeKind.GARDEN else kind
	_extra_trees.append([_plot_point(i, front, along, back + 0.5), tall, k])


func _leaf_colour(base: Color, rng: RandomNumberGenerator) -> Color:
	return Color(base.r * rng.randf_range(0.85, 1.15), base.g * rng.randf_range(0.88, 1.12),
		base.b * rng.randf_range(0.85, 1.15))


func _blob(spin: Basis, centre: Vector3, size: Vector3, colour: Color) -> Array:
	return [Transform3D(spin * Basis.from_scale(size), centre), colour]


func _tree(at: Vector2, tall: float, kind: int, rng: RandomNumberGenerator, slim: float = 1.0,
		lite: bool = false) -> Array:
	# One tree as [trunk items, canopy blob items, cone items]; each item is
	# [transform, colour]. Every kind has its own shape, size and colour.
	# slim < 1 makes the canopy narrower (street trees, pruned to fit); lite uses
	# fewer pieces (for the thousands of trees in the woods).
	var ground := height_at(at.x, at.y)
	var spin := Basis(Vector3.UP, rng.randf() * TAU)
	var base := Vector3(at.x, ground, at.y)
	var trunk_h := tall * 0.45
	var thick := 0.35 + tall * 0.035
	var bark := BARK
	var blobs: Array = []
	var tiers: Array = []
	match kind:
		TreeKind.BIRCH:
			# Slender white trunk, a narrow airy crown in light green.
			trunk_h = tall * 0.6
			thick = 0.22 + tall * 0.015
			bark = BIRCH_BARK
			var green := Color(0.36, 0.48, 0.18)
			var w := tall * rng.randf_range(0.28, 0.36) * slim
			for k in (2 if lite else 3):
				var off := Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.7, 0.7))
				blobs.append(_blob(spin, base + off + Vector3.UP * tall * (0.56 + k * 0.13),
					Vector3(w, tall * 0.36, w) * (1.0 - k * 0.15), _leaf_colour(green, rng)))
		TreeKind.COLUMNAR:
			# Tall and narrow: a poplar, or a leylandii hedge-tree.
			trunk_h = tall * 0.18
			var green := Color(0.16, 0.30, 0.15) if rng.randf() < 0.5 else Color(0.24, 0.38, 0.16)
			var w := tall * rng.randf_range(0.18, 0.24)
			blobs.append(_blob(spin, base + Vector3.UP * tall * 0.52, Vector3(w, tall * 0.8, w),
				_leaf_colour(green, rng)))
			blobs.append(_blob(spin, base + Vector3.UP * tall * 0.72, Vector3(w * 0.8, tall * 0.45, w * 0.8),
				_leaf_colour(green, rng)))
		TreeKind.PINE:
			# Scots pine: a tall bare reddish trunk with flat clumps at the top.
			trunk_h = tall * 0.78
			thick = 0.3 + tall * 0.03
			bark = PINE_BARK
			var green := Color(0.13, 0.23, 0.15)
			for k in (2 if lite else rng.randi_range(2, 4)):
				var off := Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.8, 0.8), rng.randf_range(-1.6, 1.6))
				var w := tall * rng.randf_range(0.22, 0.34)
				blobs.append(_blob(spin, base + off + Vector3.UP * tall * 0.84, Vector3(w, tall * 0.16, w * 0.9),
					_leaf_colour(green, rng)))
		TreeKind.SPRUCE:
			# Three stacked tiers, widest at the bottom.
			trunk_h = tall * 0.25
			var green := Color(0.11, 0.24, 0.15)
			for k in 3:
				var w := tall * (0.42 - k * 0.1)
				var tier_h := tall * (0.5 - k * 0.08)
				tiers.append(_blob(spin, base + Vector3.UP * (tall * (0.12 + k * 0.24) + tier_h * 0.5),
					Vector3(w, tier_h, w), _leaf_colour(green, rng)))
		TreeKind.GORSE:
			# A low, dense gorse bush (whin): dark spiny green, flecked yellow by
			# the foliage shader. No trunk to speak of.
			var green := Color(0.16, 0.24, 0.10)
			for k in rng.randi_range(2, 3):
				var off := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * tall * 0.6
				var w := tall * rng.randf_range(1.1, 1.6)
				var c := _leaf_colour(green, rng)
				blobs.append(_blob(spin, base + off + Vector3.UP * tall * 0.4, Vector3(w, tall, w * 0.9),
					Color(c.r, c.g, c.b, GORSE_ALPHA)))
			return [[], blobs, []]
		_:
			# Broadleaf (oak, sycamore, lime), small ornamentals and copper beech:
			# a main canopy with a few smaller blobs round it.
			var green := Color(rng.randf_range(0.20, 0.28), rng.randf_range(0.33, 0.42), rng.randf_range(0.11, 0.16))
			var spread := rng.randf_range(0.5, 0.75)
			if kind == TreeKind.ORNAMENTAL:
				green = Color(0.30, 0.42, 0.16)
				spread = rng.randf_range(0.7, 0.9)
				trunk_h = tall * 0.38
			elif kind == TreeKind.COPPER:
				green = Color(0.30, 0.13, 0.12)
			var w := tall * spread * slim
			var centre := base + Vector3.UP * tall * 0.64
			blobs.append(_blob(spin, centre, Vector3(w, tall * 0.48, w * rng.randf_range(0.85, 1.0)),
				_leaf_colour(green, rng)))
			for k in (1 if lite else rng.randi_range(2, 4)):
				var angle := rng.randf() * TAU
				var off := Vector3(cos(angle), 0.0, sin(angle)) * w * rng.randf_range(0.22, 0.34)
				off.y = tall * rng.randf_range(-0.1, 0.16)
				var size := rng.randf_range(0.45, 0.65)
				blobs.append(_blob(spin, centre + off, Vector3(w, tall * 0.48, w) * size,
					_leaf_colour(green, rng)))
	var trunk := [Transform3D(spin * Basis.from_scale(Vector3(thick, trunk_h + 0.3, thick)),
		base + Vector3.UP * (trunk_h * 0.5 - 0.3)), bark]
	return [[trunk], blobs, tiers]


func _update_natural_trees(tiles: PackedByteArray) -> void:
	# Trees stay on open land; building anything clears them (parks plant their
	# own). Woodland keeps them, and is filled in round them (_update_planted_woods).
	for i in tiles.size():
		var show := 1 if ((tiles[i] == Tile.EMPTY and _infill[i] == 0) or tiles[i] == Tile.WOODLAND) else 0
		if show == _tile_has_trees[i]:
			continue
		_tile_has_trees[i] = show
		if not _parts_in_tile.has(i):
			continue
		for part: int in _parts_in_tile[i]:
			var mm: MultiMesh = _wood_mms[_part_mesh[part]]
			mm.set_instance_transform(_part_index[part], _part_xf[part] if show == 1 else _hidden)


const WOODLAND_EDGE := 75.0     # metres in from the edge of a forest before planted trees are at their thickest
const WOODLAND_SETBACK := 4.0   # planted trees stand at least this far back from open or built land
const WOODLAND_EDGE_THICK := 0.55   # how wooded the very edge is (0-1, as the land map's woods; 1 inside)


func _update_planted_woods(tiles: PackedByteArray) -> void:
	# Trees on woodland tiles, planted to look like the natural woods: the same
	# kinds, sizes and clumps (_wood_kind, _clumps), bigger and closer inside a
	# forest and thinner at its edge, where birch come in. Natural woods next door
	# count as forest, so the two join up without an edge between them; natural
	# trees already on a woodland tile stay, and are only filled in round.
	# Every tree is seeded by its own spot, so nothing else built ever reshapes
	# it. Only the woods squares near a change are filled again.
	var t0 := Time.get_ticks_usec()
	if _natural_woods.is_empty():
		_natural_woods.resize(tiles.size())
		for i in tiles.size():
			_natural_woods[i] = 1 if water[i] == 0 and _land_value(i % map_w + PADDING, i / map_w + PADDING, 1) > 0.5 else 0
	var forest := PackedByteArray()
	forest.resize(tiles.size())
	for i in tiles.size():
		if tiles[i] == Tile.WOODLAND:
			forest[i] = 1
		elif tiles[i] == Tile.EMPTY and _infill[i] == 0 and _natural_woods[i] == 1:
			forest[i] = 2
		elif tiles[i] == Tile.ROAD or tiles[i] == Tile.POWER_LINE:
			forest[i] = 3     # (a road or a line through the woods doesn't make an edge to thin)
	if _forest.size() != forest.size():
		_forest.resize(forest.size())
		_forest.fill(0)
	var dirty := {}
	for i in tiles.size():
		if forest[i] == _forest[i]:
			continue
		# A change reaches the trees two tiles round it (how far in from the edge they are).
		var x := i % map_w
		var y := i / map_w
		for gz: int in [y - 2 + PADDING, y + 2 + PADDING]:
			for gx: int in [x - 2 + PADDING, x + 2 + PADDING]:
				dirty[(gz / TREE_CHUNK_TILES) * _wood_per_row + gx / TREE_CHUNK_TILES] = true
	_forest = forest
	if dirty.is_empty():
		return
	for n: int in dirty:
		_plant_woods_square(n)
	planted_refresh_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _plant_woods_square(n: int) -> void:
	# Fill one woods square's planted woodland (TREE_CHUNK_TILES across, the same
	# squares as the natural woods).
	var lists: Array = [[], [], []]
	var gx0 := (n % _wood_per_row) * TREE_CHUNK_TILES - PADDING
	var gz0 := (n / _wood_per_row) * TREE_CHUNK_TILES - PADDING
	for y in range(maxi(gz0, 0), mini(gz0 + TREE_CHUNK_TILES, map_h)):
		for x in range(maxi(gx0, 0), mini(gx0 + TREE_CHUNK_TILES, map_w)):
			if _forest[y * map_w + x] == 1:
				_plant_woodland_tile(x, y, lists)
	var count := 0
	for mesh_id: int in 3:
		var items: Array = lists[mesh_id]
		count += items.size()
	_planted_parts[n] = count
	if not _planted_nodes.has(n):
		if count == 0:
			return        # (nothing planted here yet: no nodes needed)
		var made: Array = []
		for k: int in 3:
			var node := MultiMeshInstance3D.new()
			node.multimesh = _new_multimesh(_wood_meshes[k], false)
			node.material_override = _wood_bark if k == 0 else _wood_leaves
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if k == 0 \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			node.visibility_range_end = _tree_range
			node.visibility_range_end_margin = _tree_range * 0.1
			woods.add_child(node)
			_wood_nodes.append(node)
			made.append(node)
		_planted_nodes[n] = made
	var nodes: Array = _planted_nodes[n]
	for mesh_id: int in 3:
		var items: Array = lists[mesh_id]
		var node: MultiMeshInstance3D = nodes[mesh_id]
		_fill(node.multimesh, items, false)
		node.visible = not items.is_empty()


func _is_forest(x: int, y: int) -> bool:
	# Woodland, untouched natural woods, or a road or power line (the woods run
	# right up to a lane, as they do to each other). Beyond the map edge: natural woods.
	if x < 0 or y < 0 or x >= map_w or y >= map_h:
		return _land_value(x + PADDING, y + PADDING, 1) > 0.5
	return _forest[y * map_w + x] != 0


func _plant_woodland_tile(x: int, y: int, lists: Array) -> void:
	var corner := Vector2(x * cell, y * cell)
	# Which sides open onto land that isn't forest (trees stand back from them).
	var lo := Vector2(0.0, 0.0)
	var hi := Vector2(cell, cell)
	if not _is_forest(x - 1, y):
		lo.x = WOODLAND_SETBACK
	if not _is_forest(x + 1, y):
		hi.x = cell - WOODLAND_SETBACK
	if not _is_forest(x, y - 1):
		lo.y = WOODLAND_SETBACK
	if not _is_forest(x, y + 1):
		hi.y = cell - WOODLAND_SETBACK
	# Open or built tiles within two tiles: how far in from the forest's edge each tree is.
	var open: Array[Rect2] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if (dx != 0 or dy != 0) and not _is_forest(x + dx, y + dy):
				open.append(Rect2(Vector2(x + dx, y + dy) * cell, Vector2(cell, cell)))
	var natural := _land_value(x + PADDING, y + PADDING, 1)
	var natural_thick := smoothstep(0.15, 0.75, natural) if natural > 0.15 else 0.0
	var rng := RandomNumberGenerator.new()
	for s in 9:
		# Every number is drawn in the same order whatever happens, so a tree only
		# changes if its own place in the forest does.
		rng.seed = hash(Vector3i(x, y, s)) + 4093
		var f := Vector2((s % 3 + rng.randf_range(0.1, 0.9)) / 3.0, (s / 3 + rng.randf_range(0.1, 0.9)) / 3.0) * cell
		var keep := rng.randf()
		var taken := rng.randf()
		var size := rng.randf()
		f = f.clamp(lo, hi)
		var at := corner + f
		var edge := WOODLAND_EDGE
		for r: Rect2 in open:
			var nearest := at.clamp(r.position, r.end)
			edge = minf(edge, at.distance_to(nearest))
		var wood := WOODLAND_EDGE_THICK + (1.0 - WOODLAND_EDGE_THICK) * smoothstep(0.0, WOODLAND_EDGE, edge)
		var clump := _clumps.get_noise_2d(at.x, at.y) * 0.5 + 0.5
		var thick := smoothstep(0.15, 0.75, wood)
		if keep > thick * (0.45 + 0.8 * clump) or coast_at(at.x, at.y) < SHORE_LEVEL + 0.4:
			continue
		if taken < natural_thick * (0.45 + 0.8 * clump):
			continue     # a natural tree stands about here already
		var inner := wood > 0.85 and clump > 0.45
		var kind := _wood_kind(wood, clump, rng)
		var tall := lerpf(12.0, 20.0, size) if inner else lerpf(8.0, 15.0, size)
		var tree := _tree(at, tall, kind, rng, 1.6 if inner else 1.15, true)
		for mesh_id: int in 3:
			if mesh_id == 0 and inner:
				continue    # deep in a wood the trunks can't be seen
			var target: Array = lists[mesh_id]
			target.append_array(tree[mesh_id])


func planted_total() -> int:
	# Instances (trunks, canopy blobs, cones) in the planted woodland.
	var planted := 0
	for n: int in _planted_parts:
		planted += int(_planted_parts[n])
	return planted


func woods_report() -> String:
	# Instances in the natural and planted woods (for the dev tools).
	return "natural woods %d, planted woodland %d (last change %.0f ms)" % [_natural_tree_parts, planted_total(),
		planted_refresh_ms]


func _build_city_trees(tiles: PackedByteArray) -> void:
	# Planted trees: in parks and pocket parks, on plots (gardens, courts, car
	# parks; see the plot plans) and along the streets.
	# (Park trees are planted by _plan_park, clear of the paths and ponds.)
	var lists: Array = [[], [], []]
	var plot_rng := RandomNumberGenerator.new()
	plot_rng.seed = 7
	for tree: Array in _extra_trees:
		var at: Vector2 = tree[0]
		var tall: float = tree[1]
		var kind: int = tree[2]
		# Each tree's shape from its own spot, so planting one more doesn't reshape
		# every tree after it in the list (they all changed whenever a plot grew).
		plot_rng.seed = hash(Vector2i(roundi(at.x * 4.0), roundi(at.y * 4.0))) + 7
		_add_tree(lists, _tree(at, tall, kind, plot_rng))
	_plant_street_trees(tiles, lists)
	_fill_chunked(city_trunks, lists[0])
	_fill_chunked(city_crowns, lists[1])
	_fill_chunked(city_cones, lists[2])


func _add_tree(lists: Array, tree: Array) -> void:
	for mesh_id: int in 3:
		var target: Array = lists[mesh_id]
		target.append_array(tree[mesh_id])


func _plant_street_trees(tiles: PackedByteArray, lists: Array) -> void:
	# Street trees along both sides of every straight road (not at junctions or
	# bends, or beside industry and power plants). Each street has one kind of
	# tree, as an avenue would.
	for i in tiles.size():
		if tiles[i] != Tile.ROAD:
			continue
		var tile := Vector2i(i % map_w, i / map_w)
		for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if not (_is_road(tile + axis) and _is_road(tile - axis)):
				continue
			var normal_axis := Vector2i(axis.y, axis.x)
			if _is_road(tile + normal_axis) or _is_road(tile - normal_axis):
				continue   # a junction, keep it clear
			var road: int = sim.road_kind[i]
			if road == Settings.MOTORWAY:
				continue
			var road_hw: float = ROAD_HALF_WIDTHS[road]
			var c := tile_centre(tile)
			# One species per street: the street's row (or column) picks it.
			var line := tile.y if axis.x == 1 else tile.x + 1000
			var street_rng := RandomNumberGenerator.new()
			street_rng.seed = line * 7919 + 3
			var kind: int = [TreeKind.BROADLEAF, TreeKind.BROADLEAF, TreeKind.ORNAMENTAL,
				TreeKind.BIRCH, TreeKind.COPPER][street_rng.randi_range(0, 4)]
			var rng := RandomNumberGenerator.new()
			rng.seed = i * 17 + 5
			if road == 1:
				# An avenue: a row of small trees down the middle.
				for k in 3:
					var mid := c + Vector2(axis) * (-16.7 + k * 16.7 + rng.randf_range(-0.6, 0.6))
					_add_tree(lists, _tree(mid, rng.randf_range(5.0, 6.5), TreeKind.ORNAMENTAL, rng, 0.6))
			for side: int in [-1, 1]:
				var normal: Vector2i = normal_axis * side
				var beside: Vector2i = tile + normal
				var offset := road_hw + 3.5    # open verge
				if beside.x >= 0 and beside.y >= 0 and beside.x < map_w and beside.y < map_h:
					var bt := tiles[beside.y * map_w + beside.x]
					if bt == Tile.INDUSTRY or sim.makes_power(bt) or bt == Tile.LANDFILL \
							or bt == Tile.HARBOUR or bt == Tile.RECYCLING or bt == Tile.INCINERATOR \
							or bt == Tile.DATA_CENTRE or bt == Tile.GIGAFACTORY or bt == Tile.AI_DATA_CENTRE:
						continue
					if bt != Tile.EMPTY and bt != Tile.PARK and bt != Tile.POWER_LINE and bt != Tile.WOODLAND:
						offset = road_hw + 2.6   # in the pavement in front of the buildings
				for k in 4:
					if rng.randf() < 0.12:
						continue   # the odd gap
					var spot := c + Vector2(axis) * (-18.75 + k * 12.5 + rng.randf_range(-0.8, 0.8)) \
						+ Vector2(normal) * offset
					var tall := rng.randf_range(6.5, 10.5) if kind != TreeKind.ORNAMENTAL else rng.randf_range(5.0, 7.0)
					_add_tree(lists, _tree(spot, tall, kind, rng, 0.72))


# -------------------------------------------------------------- day and night

func set_time_of_day(t: float) -> void:
	# t: 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset. Map views are
	# lit at MAP_VIEW_TIME whatever the clock says (clock_night keeps the real night).
	_clock_time = t
	clock_night = 1.0 - smoothstep(-0.12, 0.08, sin((t - 0.25) * TAU))
	if overlay != Overlay.NONE:
		t = MAP_VIEW_TIME
	var phase := (t - 0.25) * TAU
	var height := sin(phase)                       # above 0 = sun is up
	var daylight := smoothstep(-0.08, 0.25, height)
	night = 1.0 - smoothstep(-0.12, 0.08, height)
	var low_sun := 1.0 - smoothstep(0.0, 0.35, absf(height))   # 1 around sunrise and sunset

	if height > -0.05:
		# The sun rises in the east, crosses the south and sets in the west.
		var elevation := maxf(height, 0.02) * SUN_MAX_ELEVATION
		var yaw := 90.0 - 180.0 * clampf((t - 0.25) / 0.5, 0.0, 1.0)
		sun.rotation_degrees = Vector3(-elevation, _view_yaw(yaw, SUN_VIEW_ANGLE), 0.0)
		sun.light_color = SUN_LOW_COLOUR.lerp(SUN_DAY_COLOUR, smoothstep(0.0, 0.4, height))
		sun.light_energy = lerpf(0.0, SUN_ENERGY, smoothstep(-0.04, 0.1, height))
	else:
		# Cool, dim moonlight from high up: a dark blue night, but the town's
		# shapes still read, so you can keep building.
		sun.rotation_degrees = Vector3(MOON_ANGLE.x, _view_yaw(MOON_ANGLE.y, MOON_VIEW_ANGLE), 0.0)
		sun.light_color = MOON_COLOUR
		sun.light_energy = MOON_ENERGY

	if sea_material:
		sea_material.set_shader_parameter("day", 1.0 - night)
	if terrain_material:
		# Which way shadows fall across the ground (the shader draws the hedges' own).
		var fall := -sun.basis.z
		if Vector2(fall.x, fall.z).length() > 0.01:
			terrain_material.set_shader_parameter("shadow_dir", Vector2(fall.x, fall.z).normalized())

	env.ambient_light_energy = lerpf(AMBIENT_NIGHT, AMBIENT_DAY, daylight)
	env.background_energy_multiplier = lerpf(SKY_ENERGY_NIGHT, 1.0, daylight)
	var haze := HAZE_DAY.lerp(HAZE_DUSK, low_sun * (1.0 - night))
	env.fog_light_color = HAZE_NIGHT.lerp(haze, daylight)
	# Opened up as the light fades, like an eye (or camera) adjusting at dusk.
	env.tonemap_exposure = lerpf(LOOK_EXPOSURE_NIGHT, LOOK_EXPOSURE_DAY, daylight)
	env.glow_intensity = lerpf(GLOW_DAY, GLOW_NIGHT, night)
	# Dimming the sky itself makes Godot redo its lighting, so only do it in steps.
	var sky_energy := lerpf(SKY_ENERGY_NIGHT, 1.0, daylight)
	if absf(sky_energy - _sky_energy) > 0.04 and sky_material:
		_sky_energy = sky_energy
		sky_material.set("energy_multiplier", sky_energy)

	# How late in the night it is (0 in the evening, 1 in the small hours): homes go dark.
	var since_sunset := fposmod(t - 0.75, 1.0)
	var late := smoothstep(0.08, 0.3, since_sunset) * (1.0 - smoothstep(0.42, 0.5, since_sunset))
	if wall_material:
		wall_material.set_shader_parameter("night", night)
		wall_material.set_shader_parameter("late", late)
	for mat in _model_materials:
		mat.set_shader_parameter("night", night)
		mat.set_shader_parameter("late", late)
	if road_material:
		road_material.set_shader_parameter("night", night)


func _view_yaw(world_yaw: float, view_angle: float) -> float:
	# Like SimCity 4, light always comes from the same side of the screen, so
	# buildings show one sunlit and one shaded face and their shadows fall the
	# same way whichever way you turn. (SUN_FOLLOWS_VIEW = false: a real sun path.)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if not SUN_FOLLOWS_VIEW or cam == null:
		return world_yaw
	var back := cam.global_basis.z
	return rad_to_deg(atan2(back.x, back.z)) + view_angle


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
