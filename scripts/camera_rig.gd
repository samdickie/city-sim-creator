extends Node3D
## A city-builder camera: orbits around a point on the ground,
## with smooth movement for rotating, tilting, panning and zooming.

const MIN_DISTANCE := 70.0
const MAX_DISTANCE := 6500.0
const MIN_PITCH := 0.384          # 22 degrees
const MAX_PITCH := 1.484          # 85 degrees
const SMOOTHING := 9.0          # higher = snappier

var camera := Camera3D.new()
var bounds := Rect2()           # the map area the camera may look at (x, z)
var ground_height := Callable() # func(x, z) -> float, so the camera follows hills

# Where the camera is heading...
var target := Vector3.ZERO
var yaw := deg_to_rad(200.0)
var pitch := deg_to_rad(48.0)
var distance := 1400.0
# ...and where it is right now (eases towards the values above).
var _target := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _distance := 0.0


func _ready() -> void:
	camera.fov = 45.0
	camera.near = 1.0
	camera.far = 40000.0
	# Depth of field: blur what's well behind or in front of the point you're
	# looking at. From above, that gives the "tilt-shift" miniature-model look.
	var dof := CameraAttributesPractical.new()
	dof.dof_blur_far_enabled = true
	dof.dof_blur_near_enabled = true
	camera.attributes = dof
	add_child(camera)
	camera.make_current()
	snap()


func snap() -> void:
	_target = target
	_yaw = yaw
	_pitch = pitch
	_distance = distance
	_apply()


func _process(delta: float) -> void:
	var k := 1.0 - exp(-SMOOTHING * delta)
	if ground_height.is_valid():
		target.y = maxf(ground_height.call(target.x, target.z), 0.0)
	_target = _target.lerp(target, k)
	_yaw = lerp_angle(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_distance = lerpf(_distance, distance, k)
	_apply()


func _apply() -> void:
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	camera.global_position = _target + offset
	camera.look_at(_target, Vector3.UP)
	var dof := camera.attributes as CameraAttributesPractical
	if dof:
		dof.dof_blur_far_distance = _distance * 1.15
		dof.dof_blur_far_transition = _distance * 0.9
		dof.dof_blur_near_distance = _distance * 0.65
		dof.dof_blur_near_transition = _distance * 0.35
		# Gentle when zoomed in close, off when looking over the whole map.
		dof.dof_blur_amount = lerpf(0.09, 0.0, smoothstep(2500.0, 5000.0, _distance))


# ------------------------------------------------------------- controls

func orbit(dx: float, dy: float) -> void:
	# Mouse movement in pixels: left/right turns, up/down tilts.
	yaw -= dx * 0.005
	pitch = clampf(pitch + dy * 0.004, MIN_PITCH, MAX_PITCH)


func turn(radians: float) -> void:
	yaw += radians


func pan_pixels(delta: Vector2) -> void:
	# Drag the map: move the target opposite to the mouse, scaled by distance.
	var pan_scale := distance * 0.0011
	_pan(Vector2(-delta.x, -delta.y) * pan_scale)


func pan_direction(dir: Vector2, delta_time: float) -> void:
	# Keyboard panning: dir.x right, dir.y forward.
	_pan(Vector2(dir.x, -dir.y) * distance * 0.9 * delta_time)


func _pan(amount: Vector2) -> void:
	# amount.x = right, amount.y = towards the bottom of the screen.
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	target += right * amount.x + back * amount.y
	_clamp_target()


func zoom(factor: float, towards: Vector3 = Vector3.INF) -> void:
	# factor < 1 zooms in. When zooming in, drift towards the point under the mouse.
	var before := distance
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	if towards != Vector3.INF and distance < before:
		var pull := 1.0 - distance / before
		target = target.lerp(Vector3(towards.x, target.y, towards.z), pull)
		_clamp_target()


func _clamp_target() -> void:
	target.x = clampf(target.x, bounds.position.x, bounds.end.x)
	target.z = clampf(target.z, bounds.position.y, bounds.end.y)
