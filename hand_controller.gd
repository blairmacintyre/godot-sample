class_name HandController
extends XRController3D
## A tracked hand controller with teleport, grab-and-throw and snap turn.
##
## Teleport: hold the bumper (shoulder button) to aim. A ballistic arc comes out
## of the controller until it reaches the ground plane (y = 0), with a circle
## marking the landing spot. Releasing the bumper emits `teleport_requested`. The
## arc turns red, shows no circle and does nothing on release when the controller
## points up more than `max_aim_pitch` degrees above the horizon (or when the arc
## never lands).
##
## Grab: squeeze the trigger or grip while touching a body in the "grabbable"
## group to hold it. Releasing throws it with the controller's velocity.
##
## Snap turn: flick the thumbstick left or right to rotate by `snap_angle`.
##
## Haptic pulses confirm grabs, teleports and snap turns.

signal teleport_requested(target: Vector3)
## Emitted once per thumbstick flick. Positive turns left (counter-clockwise).
signal snap_turn_requested(angle_degrees: float)

@export_group("Teleport")
@export var launch_speed := 9.0
@export var gravity := 9.8
@export var step_time := 0.025
@export var max_time := 3.0
## Pointing higher than this above the horizon (3/4 of the way to straight up)
## disables teleporting.
@export var max_aim_pitch := 67.5
@export var arc_width := 0.012
@export var marker_radius := 0.25
@export var valid_color := Color(0.2, 0.95, 1.0)
@export var invalid_color := Color(1.0, 0.25, 0.25)

@export_group("Grab")
@export var grab_radius := 0.12
@export var throw_boost := 1.0

@export_group("Snap turn")
@export var snap_angle := 30.0

const TELEPORT_BUTTON := "bumper_click"
const GRAB_BUTTONS := ["trigger_click", "grip_click"]
const SNAP_TRIGGER := 0.7
const SNAP_RESET := 0.3
const VELOCITY_SAMPLES := 8
const GRABBABLE_GROUP := &"grabbable"

var _aiming := false
var _has_target := false
var _target := Vector3.ZERO

var _snap_ready := true

var _held: RigidBody3D
var _held_offset := Transform3D.IDENTITY
var _grab_buttons_down := {}
## Recent controller poses in the parent's (play space) frame: [time, position, rotation].
var _samples: Array = []

var _arc_mesh := ImmediateMesh.new()
var _arc_material := StandardMaterial3D.new()
var _arc_instance: MeshInstance3D
var _marker: MeshInstance3D
var _marker_material := StandardMaterial3D.new()
var _wand: MeshInstance3D


func _ready() -> void:
	_build_visuals()
	button_pressed.connect(_on_button_pressed)
	button_released.connect(_on_button_released)
	input_vector2_changed.connect(_on_vector2_changed)
	tracking_changed.connect(_on_tracking_changed)
	visible = false


func _process(delta: float) -> void:
	if _aiming:
		_update_arc()
	if _held:
		_record_sample()
		_held.global_transform = global_transform * _held_offset


## The placeholder wand is only for runtimes that provide no controller model.
func set_wand_visible(wand_visible: bool) -> void:
	_wand.visible = wand_visible


## True while this hand is holding a body.
func is_holding() -> bool:
	return _held != null


func _build_visuals() -> void:
	# A simple wand so you can see where each controller is.
	var wand_mesh := CylinderMesh.new()
	wand_mesh.top_radius = 0.012
	wand_mesh.bottom_radius = 0.02
	wand_mesh.height = 0.12
	var wand_material := StandardMaterial3D.new()
	wand_material.albedo_color = Color(0.15, 0.15, 0.2)
	wand_material.metallic = 0.5
	wand_material.roughness = 0.4
	_wand = MeshInstance3D.new()
	_wand.name = "Wand"
	_wand.mesh = wand_mesh
	_wand.material_override = wand_material
	_wand.rotation_degrees.x = 90.0
	_wand.position.z = -0.04
	add_child(_wand)

	# top_level so the arc and marker live in world space, not controller space.
	_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arc_instance = MeshInstance3D.new()
	_arc_instance.name = "Arc"
	_arc_instance.top_level = true
	_arc_instance.mesh = _arc_mesh
	_arc_instance.material_override = _arc_material
	_arc_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arc_instance.visible = false
	add_child(_arc_instance)

	var ring := TorusMesh.new()
	ring.inner_radius = marker_radius - 0.03
	ring.outer_radius = marker_radius
	ring.rings = 48
	ring.ring_segments = 6
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.albedo_color = valid_color
	_marker = MeshInstance3D.new()
	_marker.name = "TargetMarker"
	_marker.top_level = true
	_marker.mesh = ring
	_marker.material_override = _marker_material
	_marker.scale = Vector3(1.0, 0.15, 1.0)
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)


# --- Input ---------------------------------------------------------------

func _on_tracking_changed(tracking: bool) -> void:
	visible = tracking
	if tracking:
		var hand_tracker := XRServer.get_tracker(tracker)
		if hand_tracker:
			print("%s tracking, interaction profile: %s" % [tracker, hand_tracker.profile])
	if not tracking:
		_end_aiming(false)
		_release_held()


func _on_button_pressed(action_name: String) -> void:
	if action_name == TELEPORT_BUTTON:
		_begin_aiming()
	elif action_name in GRAB_BUTTONS:
		_grab_buttons_down[action_name] = true
		_try_grab()


func _on_button_released(action_name: String) -> void:
	if action_name == TELEPORT_BUTTON:
		_end_aiming(true)
	elif action_name in GRAB_BUTTONS:
		_grab_buttons_down.erase(action_name)
		# Keep holding while the other grab button is still down.
		if _grab_buttons_down.is_empty():
			_release_held()


func _on_vector2_changed(action_name: String, value: Vector2) -> void:
	if action_name != "primary":
		return
	if absf(value.x) <= SNAP_RESET:
		_snap_ready = true
	elif _snap_ready and absf(value.x) >= SNAP_TRIGGER and absf(value.x) > absf(value.y):
		_snap_ready = false
		_pulse(0.3, 0.04)
		# Stick right turns the view right, which is a negative rotation about Y.
		snap_turn_requested.emit(-signf(value.x) * snap_angle)


func _pulse(amplitude: float, duration: float) -> void:
	trigger_haptic_pulse("haptic", 0.0, amplitude, duration, 0.0)


# --- Teleport ------------------------------------------------------------

func _begin_aiming() -> void:
	if _aiming:
		return
	_aiming = true
	_arc_instance.visible = true
	_update_arc()


func _end_aiming(commit: bool) -> void:
	if not _aiming:
		return
	_aiming = false
	_arc_instance.visible = false
	_marker.visible = false
	_arc_mesh.clear_surfaces()
	if commit and _has_target:
		_pulse(0.6, 0.1)
		teleport_requested.emit(_target)


## True when the controller points higher above the horizon than `max_aim_pitch`.
func _is_pointing_too_high() -> bool:
	var forward := -global_basis.z
	return rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))) > max_aim_pitch


## Simulates a projectile from the controller and returns its path. The last
## point is on the ground when the path reaches it. `_has_target` is only set
## when it lands and the controller is not pointing too high.
func _simulate_arc() -> PackedVector3Array:
	var points := PackedVector3Array()
	var position_now := global_position
	var velocity := -global_basis.z * launch_speed
	var too_high := _is_pointing_too_high()
	_has_target = false
	points.append(position_now)

	var t := 0.0
	while t < max_time:
		var next_position := position_now + velocity * step_time
		velocity.y -= gravity * step_time
		if next_position.y <= 0.0 and position_now.y > 0.0:
			var fraction := position_now.y / (position_now.y - next_position.y)
			var landing := position_now.lerp(next_position, fraction)
			landing.y = 0.0
			points.append(landing)
			if not too_high:
				_target = landing
				_has_target = true
			return points
		position_now = next_position
		points.append(position_now)
		t += step_time
	return points


func _update_arc() -> void:
	var points := _simulate_arc()
	var color := valid_color if _has_target else invalid_color
	_arc_material.albedo_color = color
	_marker_material.albedo_color = color

	_marker.visible = _has_target
	if _has_target:
		_marker.global_position = _target + Vector3(0.0, 0.01, 0.0)

	_arc_mesh.clear_surfaces()
	if points.size() < 2:
		return

	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else global_position + Vector3.UP
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in points.size():
		var previous := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		var tangent := (next - previous).normalized()
		var side := tangent.cross(eye - points[i])
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized() * arc_width * 0.5
		_arc_mesh.surface_add_vertex(points[i] - side)
		_arc_mesh.surface_add_vertex(points[i] + side)
	_arc_mesh.surface_end()


# --- Grab and throw ------------------------------------------------------

## Finds a grabbable body touching a small sphere at the controller.
func _find_grabbable() -> RigidBody3D:
	var sphere := SphereShape3D.new()
	sphere.radius = grab_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 8)
	var best: RigidBody3D = null
	var best_distance := INF
	for hit in hits:
		var body := hit.collider as RigidBody3D
		if body == null or not body.is_in_group(GRABBABLE_GROUP):
			continue
		var distance := body.global_position.distance_to(global_position)
		if distance < best_distance:
			best = body
			best_distance = distance
	return best


func _try_grab() -> void:
	if _held:
		return
	var body := _find_grabbable()
	if body == null:
		return

	# Taking a body from the other hand: that hand lets go without throwing.
	if body.has_meta("held_by"):
		var other: Variant = body.get_meta("held_by")
		if other is HandController and other != self:
			other._release_held(false)

	_held = body
	_held_offset = global_transform.affine_inverse() * body.global_transform
	body.set_meta("held_by", self)
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	_samples.clear()
	_record_sample()
	_pulse(0.4, 0.05)


func _release_held(throw := true) -> void:
	if _held == null:
		return
	var body := _held
	_held = null
	if body.has_meta("held_by") and body.get_meta("held_by") == self:
		body.remove_meta("held_by")
	body.freeze = false
	if throw:
		var motion := _estimate_motion()
		body.linear_velocity = motion[0] * throw_boost
		body.angular_velocity = motion[1]
	else:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	_samples.clear()


## Poses are recorded relative to the parent (the XR origin), so teleporting or
## snap turning the play space never shows up as controller motion.
func _record_sample() -> void:
	_samples.append([Time.get_ticks_usec() / 1_000_000.0, position, transform.basis.get_rotation_quaternion()])
	if _samples.size() > VELOCITY_SAMPLES:
		_samples.pop_front()


## Returns [linear velocity, angular velocity] in world space.
func _estimate_motion() -> Array:
	if _samples.size() < 2:
		return [Vector3.ZERO, Vector3.ZERO]
	var first: Array = _samples[0]
	var last: Array = _samples[_samples.size() - 1]
	var dt: float = last[0] - first[0]
	if dt < 0.001:
		return [Vector3.ZERO, Vector3.ZERO]

	var linear: Vector3 = (last[1] - first[1]) / dt
	var delta_rotation: Quaternion = (last[2] as Quaternion) * (first[2] as Quaternion).inverse()
	var angular := Vector3.ZERO
	if absf(delta_rotation.w) < 0.99999:
		angular = delta_rotation.get_axis() * delta_rotation.get_angle() / dt

	var space: Basis = get_parent_node_3d().global_basis if get_parent_node_3d() else Basis.IDENTITY
	return [space * linear, space * angular]
