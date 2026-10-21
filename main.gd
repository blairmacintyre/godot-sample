extends Node3D
## Builds the whole scene in code: a physics cube you can pick up and throw, on a
## grid floor under a fantasy sky. Runs in VR via OpenXR when a headset runtime
## is present, otherwise falls back to a normal window so you can preview it on
## a desktop.

const CUBE_SIZE := 0.5
const CUBE_POSITION := Vector3(0.0, CUBE_SIZE * 0.5, -1.5)
const EYE_HEIGHT := 1.6
## A thrown cube that ends up farther away than this is put back.
const CUBE_MAX_DISTANCE := 80.0

var _cube: RigidBody3D
var _origin: XROrigin3D
var _camera: XRCamera3D


func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_cube()
	_build_light()
	_build_rig()


func _process(_delta: float) -> void:
	if _cube.global_position.length() > CUBE_MAX_DISTANCE:
		_reset_cube()


func _build_rig() -> void:
	_origin = XROrigin3D.new()
	_origin.name = "XROrigin3D"
	add_child(_origin)

	_camera = XRCamera3D.new()
	_camera.name = "XRCamera3D"
	_origin.add_child(_camera)

	var xr_interface := XRServer.find_interface("OpenXR")
	var xr_active := xr_interface != null and xr_interface.is_initialized()

	# Either hand can teleport (hold the bumper to aim, release to go), grab and
	# throw the cube (trigger or grip), and snap turn (thumbstick).
	for hand in ["left_hand", "right_hand"]:
		var controller := HandController.new()
		controller.name = hand.capitalize().replace(" ", "")
		controller.tracker = hand
		controller.pose = "aim"
		controller.teleport_requested.connect(_teleport_to)
		controller.snap_turn_requested.connect(_snap_turn)
		_origin.add_child(controller)
		# Render models need a running OpenXR session; the flat preview has none.
		if xr_active:
			_add_render_model(hand, controller)

	if xr_active:
		print("OpenXR initialized, starting VR")
		var viewport := get_viewport()
		viewport.use_xr = true
		# Foveated rendering (variable rate shading from the OpenXR runtime) stays on
		# for the Steam Frame, which has eye tracking. It is skipped on Android (Meta
		# Quest): setting vrs_mode = VRS_XR in the frame VR starts left a
		# cut-and-shifted band at the left and right edges there.
		if not OS.has_feature("android"):
			viewport.vrs_mode = Viewport.VRS_XR
	else:
		print("OpenXR not available, using flat preview camera")
		_camera.position.y = EYE_HEIGHT


## Shows the real controller model for this hand. The placeholder wand is hidden
## once a model appears and comes back if the runtime provides none.
##  - Meta Quest: Meta's own controller meshes through XR_FB_render_model, using the
##    OpenXR Vendors plugin's OpenXRFbRenderModel node.
##  - Everything else (Steam Frame): the runtime's XR_EXT_render_model meshes.
func _add_render_model(hand: String, controller: HandController) -> void:
	if _meta_render_models_available():
		_add_meta_render_model(hand, controller)
		return

	var manager := OpenXRRenderModelManager.new()
	manager.name = hand.capitalize().replace(" ", "") + "Model"
	manager.tracker = (
		OpenXRRenderModelManager.RENDER_MODEL_TRACKER_LEFT_HAND
		if hand == "left_hand"
		else OpenXRRenderModelManager.RENDER_MODEL_TRACKER_RIGHT_HAND
	)
	manager.render_model_added.connect(func(_model): controller.set_wand_visible(false))
	manager.render_model_removed.connect(func(_model): controller.set_wand_visible(true))
	_origin.add_child(manager)


## True when the OpenXR Vendors plugin is loaded and the runtime supports and
## enabled XR_FB_render_model (Meta Quest). Looked up by name so the project still
## parses and runs without the plugin.
func _meta_render_models_available() -> bool:
	if not ClassDB.class_exists("OpenXRFbRenderModel"):
		return false
	if not Engine.has_singleton("OpenXRFbRenderModelExtension"):
		return false
	var extension: Object = Engine.get_singleton("OpenXRFbRenderModelExtension")
	return extension.call("is_enabled")


func _add_meta_render_model(hand: String, controller: HandController) -> void:
	# Meta's meshes are authored for the grip pose, so they get their own controller
	# node on the grip pose rather than riding on the aim-pose HandController.
	var grip := XRController3D.new()
	grip.name = hand.capitalize().replace(" ", "") + "Grip"
	grip.tracker = hand
	grip.pose = "grip"

	var model: Node3D = ClassDB.instantiate("OpenXRFbRenderModel")
	model.name = "ControllerModel"
	model.set("render_model_type", 0 if hand == "left_hand" else 1)
	model.connect("openxr_fb_render_model_loaded", func():
		print("%s: Meta controller model loaded" % hand)
		controller.set_wand_visible(false))
	grip.add_child(model)
	_origin.add_child(grip)


## Rotates the play space about the user's head so they turn in place.
func _snap_turn(angle_degrees: float) -> void:
	var pivot := _camera.global_position
	pivot.y = 0.0
	var rotation := Transform3D(Basis(Vector3.UP, deg_to_rad(angle_degrees)), Vector3.ZERO)
	var about_pivot := Transform3D(Basis.IDENTITY, pivot) * rotation * Transform3D(Basis.IDENTITY, -pivot)
	_origin.global_transform = about_pivot * _origin.global_transform


## Moves the play space so the user's feet (the camera's ground position) land
## on `target`, keeping the same height and facing.
func _teleport_to(target: Vector3) -> void:
	var feet := Vector3(_camera.global_position.x, 0.0, _camera.global_position.z)
	var offset := target - feet
	_origin.global_position += Vector3(offset.x, 0.0, offset.z)


func _build_environment() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://sky.gdshader")

	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_floor() -> void:
	# An infinite collision plane at y = 0 so thrown objects land on the floor.
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorBody"
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)

	var material := ShaderMaterial.new()
	material.shader = load("res://grid_floor.gdshader")

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	floor_mesh.mesh = plane
	floor_mesh.material_override = material
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)


func _build_cube() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * CUBE_SIZE

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.45, 0.85)
	material.metallic = 0.3
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = Color(0.6, 0.15, 0.5)
	material.emission_energy_multiplier = 0.4

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box
	mesh_instance.material_override = material

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape

	var physics_material := PhysicsMaterial.new()
	physics_material.bounce = 0.35
	physics_material.friction = 0.8

	_cube = RigidBody3D.new()
	_cube.name = "Cube"
	_cube.mass = 1.0
	_cube.physics_material_override = physics_material
	_cube.continuous_cd = true
	_cube.add_to_group(HandController.GRABBABLE_GROUP)
	_cube.add_child(mesh_instance)
	_cube.add_child(shape)
	_cube.position = CUBE_POSITION
	add_child(_cube)


func _reset_cube() -> void:
	_cube.linear_velocity = Vector3.ZERO
	_cube.angular_velocity = Vector3.ZERO
	_cube.global_transform = Transform3D(Basis.IDENTITY, CUBE_POSITION)


func _build_light() -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.light_color = Color(1.0, 0.85, 0.7)
	light.light_energy = 1.2
	light.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	add_child(light)
