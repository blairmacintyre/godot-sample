class_name OfficeDoor
extends AnimatableBody3D
## The door, pivoting on its hinge (this body's origin) and carrying the door's
## mesh. Grab it anywhere and move your hand around the hinge to swing it between
## closed (0) and `open_degrees`. Furniture in the way gets pushed.

@export var open_degrees := -95.0

var _hand: Node3D
var _grab_hand_angle := 0.0
var _grab_door_angle := 0.0


func _ready() -> void:
	add_to_group(HandController.GRABBABLE_GROUP)


func grab_begin(hand: Node3D) -> void:
	_hand = hand
	_grab_hand_angle = _hand_angle()
	_grab_door_angle = rotation.y


func grab_end(hand: Node3D) -> void:
	if hand == _hand:
		_hand = null


func _physics_process(_delta: float) -> void:
	if _hand == null:
		return
	var angle := _grab_door_angle + angle_difference(_grab_hand_angle, _hand_angle())
	rotation.y = clampf(angle, deg_to_rad(open_degrees), 0.0)


## The hand's angle about the hinge's vertical axis, measured the same way as a
## rotation about Y so the two can be added.
func _hand_angle() -> float:
	var offset := get_parent_node_3d().to_local(_hand.global_position) - position
	return atan2(-offset.z, offset.x)
