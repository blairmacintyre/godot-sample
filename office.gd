class_name Office
extends Node3D
## The office from office_vr/office.glb, made interactive:
##  - Every piece of furniture slides along the floor when grabbed (MovableFurniture).
##  - The door swings on its hinge when grabbed (OfficeDoor).
##  - The switch by the entry turns the two ceiling lights on and off (LightSwitch).
## Collision comes from office_vr/colliders.json, whose shapes are in the local
## space of the named model node. The room's origin is its floor centre, +Z is the
## entrance.

const MODEL := preload("res://office_vr/office.glb")
const COLLIDERS_PATH := "res://office_vr/colliders.json"
## Suggested floor position for the player, facing -Z into the room.
const SPAWN := Vector3(0.15, 0.0, 0.85)
## Render layer (1-based) for the office's meshes, so the outdoor sun can skip them.
const RENDER_LAYER := 2

## Model nodes that become movable furniture, with their mass in kilograms.
const FURNITURE_MASS := {
	"Standing_Desk": 35.0,
	"Office_Chair": 12.0,
	"Walking_Treadmill": 30.0,
	"Guest_Chair_Desk": 6.0,
	"Guest_Chair_Meeting_Left": 6.0,
	"Guest_Chair_Meeting_Rear": 6.0,
	"Guest_Chair_Meeting_Front": 6.0,
	"Bookcase": 25.0,
	"Meeting_Table": 15.0,
	"Filing_Cabinet": 25.0,
	"Waste_Bin": 2.0,
}
## Model nodes with no collision of their own that ride along with a piece of furniture.
const ATTACHED := {"Desk_Accessories": "Standing_Desk"}
const DOOR_NODE := "Door_Hinge"
const SWITCH_NODE := "Wall_Controls"
## Centres of the two recessed ceiling lights (the ceiling is at 2.7432 m).
const LIGHT_POSITIONS := [Vector3(-0.9144, 2.68, -0.9144), Vector3(0.9144, 2.68, 0.9144)]
const LIGHT_ENERGY := 1.6
const LIGHT_RANGE := 5.0

var lights_on := true

var _model: Node3D
var _lights: Array[OmniLight3D] = []
## The glowing light tubes' material, dimmed when the lights are off.
var _diffuser: StandardMaterial3D
var _diffuser_energy := 1.0


func _ready() -> void:
	_model = MODEL.instantiate()
	_model.name = "Model"
	add_child(_model)
	_set_render_layer(_model)
	_build_collision()
	_build_lights()
	_build_switch()


## Turns both ceiling lights on or off.
func set_lights_on(on: bool) -> void:
	lights_on = on
	for light in _lights:
		light.visible = on
	if _diffuser:
		_diffuser.emission_energy_multiplier = _diffuser_energy if on else 0.0


func _set_render_layer(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = 1 << (RENDER_LAYER - 1)
	for child in node.get_children():
		_set_render_layer(child)


func _part(part_name: String) -> Node3D:
	return _model.find_child(part_name, true, false) as Node3D


func _build_collision() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(COLLIDERS_PATH))
	var bodies := {}
	for entry: Dictionary in data["colliders"]:
		var parent_name: String = entry["parent"]
		if not bodies.has(parent_name):
			bodies[parent_name] = _make_body(parent_name)
		var shape := _make_shape(entry)
		if shape:
			bodies[parent_name].add_child(shape)


## Creates the physics body for one model node and returns it. Furniture and the
## door move, so their body takes the model node's place and carries its mesh;
## physics bodies must move themselves, not be moved by a parent. Walls and the
## rest of the room get a static body as a child of their node.
func _make_body(part_name: String) -> CollisionObject3D:
	var part := _part(part_name)
	var body: CollisionObject3D
	if FURNITURE_MASS.has(part_name):
		body = MovableFurniture.new()
		body.mass = FURNITURE_MASS[part_name]
	elif part_name == DOOR_NODE:
		body = OfficeDoor.new()
	else:
		body = StaticBody3D.new()
		body.name = part_name + "Body"
		part.add_child(body)
		return body

	var pose := part.global_transform
	body.name = part_name
	add_child(body)
	body.global_transform = pose
	var carried: Array[Node3D] = [part]
	for attached_name: String in ATTACHED:
		if ATTACHED[attached_name] == part_name:
			carried.append(_part(attached_name))
	for node in carried:
		# Placed from `pose` rather than reparent()'s keep-global option: an
		# AnimatableBody3D doesn't report its new transform until the next physics step.
		var node_pose := node.global_transform
		node.reparent(body, false)
		node.transform = pose.affine_inverse() * node_pose
	return body


func _make_shape(entry: Dictionary) -> CollisionShape3D:
	var size := Vector3(entry["size"][0], entry["size"][1], entry["size"][2])
	var shape := CollisionShape3D.new()
	shape.name = entry["name"]
	match entry["type"]:
		"box":
			var box := BoxShape3D.new()
			box.size = size
			shape.shape = box
		"cylinder":
			# Size is diameter, height, diameter.
			var cylinder := CylinderShape3D.new()
			cylinder.radius = size.x * 0.5
			cylinder.height = size.y
			shape.shape = cylinder
		_:
			push_warning("Unknown collider type %s for %s" % [entry["type"], entry["name"]])
			return null
	shape.position = Vector3(entry["center"][0], entry["center"][1], entry["center"][2])
	shape.rotation.y = entry["yaw_radians"]
	return shape


func _build_lights() -> void:
	for i in LIGHT_POSITIONS.size():
		var light := OmniLight3D.new()
		light.name = "CeilingLight%d" % (i + 1)
		light.position = LIGHT_POSITIONS[i]
		light.light_color = Color(1.0, 0.97, 0.9)
		light.light_energy = LIGHT_ENERGY
		light.omni_range = LIGHT_RANGE
		light.omni_attenuation = 0.8
		add_child(light)
		_lights.append(light)

	var ceiling := _part("Ceiling_Grid") as MeshInstance3D
	if ceiling:
		for surface in ceiling.mesh.get_surface_count():
			var material := ceiling.mesh.surface_get_material(surface) as StandardMaterial3D
			if material and material.resource_name == "Diffuser":
				# Own copy, so dimming it never touches the imported resource.
				_diffuser = material.duplicate()
				_diffuser_energy = _diffuser.emission_energy_multiplier
				ceiling.set_surface_override_material(surface, _diffuser)


func _build_switch() -> void:
	# The rocker is at the switch plate's origin; its front faces the node's +Z.
	var box := BoxShape3D.new()
	box.size = Vector3(0.09, 0.13, 0.06)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position.z = 0.02

	var light_switch := LightSwitch.new()
	light_switch.name = "LightSwitch"
	light_switch.add_child(shape)
	light_switch.toggled.connect(func(): set_lights_on(not lights_on))
	_part(SWITCH_NODE).add_child(light_switch)
