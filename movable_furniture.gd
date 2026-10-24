class_name MovableFurniture
extends RigidBody3D
## A piece of furniture that slides along the floor while a hand holds it.
##
## It stays on the floor and upright, only turning about the vertical axis, so it
## never tips over or climbs onto other furniture. It follows the hand's
## position and facing (twist your wrist to turn it). It is moved with velocities
## rather than teleported, so it stops at walls and shoves other furniture out of
## the way instead of passing through it.

## Fastest the furniture follows the hand, so a teleport or sudden yank can't fling it.
@export var max_speed := 2.5
## Fastest it turns to follow the hand, in radians per second.
@export var max_turn_speed := 4.0

var _hand: Node3D
## The body's transform relative to the hand's flattened (floor-level, yaw-only) pose.
var _offset := Transform3D.IDENTITY


func _ready() -> void:
	axis_lock_linear_y = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	# Turn about the floor-level pivot, the same point the hand drives.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	# Comes to rest soon after being let go or bumped.
	linear_damp = 3.0
	angular_damp = 6.0
	add_to_group(HandController.GRABBABLE_GROUP)


func grab_begin(hand: Node3D) -> void:
	_hand = hand
	_offset = _flatten(hand.global_transform).affine_inverse() * global_transform
	sleeping = false


func grab_end(hand: Node3D) -> void:
	if hand == _hand:
		_hand = null


func _physics_process(delta: float) -> void:
	if _hand == null:
		return
	var target := _flatten(_hand.global_transform) * _offset
	var to_target := target.origin - global_position
	linear_velocity = (Vector3(to_target.x, 0.0, to_target.z) / delta).limit_length(max_speed)
	var turn := angle_difference(global_basis.get_euler().y, target.basis.get_euler().y)
	angular_velocity = Vector3(0.0, clampf(turn / delta, -max_turn_speed, max_turn_speed), 0.0)


## The hand's pose projected onto the floor: its position at y = 0, turned only
## by the direction it points across the floor.
static func _flatten(pose: Transform3D) -> Transform3D:
	var forward := -pose.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		# Pointing straight down: the top of the controller faces forward instead.
		forward = pose.basis.y
		forward.y = 0.0
	var yaw := atan2(-forward.x, -forward.z)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(pose.origin.x, 0.0, pose.origin.z))
