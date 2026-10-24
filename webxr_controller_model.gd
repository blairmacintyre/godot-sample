class_name WebXRControllerModel
extends XRController3D
## Shows the real controller model during a WebXR session, using the WebXR Input
## Profiles models bundled in res://webxr_controllers/ (MIT licensed, from the
## Immersive Web group's webxr-input-profiles project).
##
## Godot doesn't expose which controller the browser reports, so the web page's
## head script (in the Web export preset) keeps the session in
## window.godotXRSession, and this node reads the input source's profile ids from
## it. The browser lists the most specific profile first, then fallbacks, and the
## first one bundled here is used. Hand tracking ("generic-hand") isn't bundled,
## so hands keep the placeholder wand.
##
## The trigger, grip, thumbstick and buttons on the model move with the real ones,
## following each profile's "visual responses".

signal model_loaded

const MODELS_DIR := "res://webxr_controllers/"
const PROFILE_POLL_INTERVAL := 0.5
## Godot's WebXR input names, indexed like the gamepad's buttons and axes.
const BUTTON_NAMES := ["trigger_click", "grip_click", "touchpad_click", "thumbstick_click", "ax_button", "by_button"]
const PRESSURE_NAMES := ["trigger", "grip", "touchpad_click_pressure", "thumbstick_click_pressure", "ax_button_pressure", "by_button_pressure"]
## Each axis pair (0-1, 2-3) arrives as one Vector2.
const AXIS_VECTORS := ["touchpad", "thumbstick"]

var _model: Node3D
var _last_profile_check := -INF
## One entry per moving part: {component, response, node, min, max}.
var _responses: Array[Dictionary] = []


func _process(_delta: float) -> void:
	if _model:
		_update_responses()
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not get_has_tracking_data() or now - _last_profile_check < PROFILE_POLL_INTERVAL:
		return
	_last_profile_check = now
	for profile_id in _browser_profiles():
		if FileAccess.file_exists(MODELS_DIR + profile_id + "/profile.json"):
			_load_model(profile_id)
			return


func _handedness() -> String:
	return "left" if tracker == &"left_hand" else "right"


## The profile ids the browser reports for this hand's controller, most specific first.
func _browser_profiles() -> Array:
	var result: Variant = JavaScriptBridge.eval("""JSON.stringify((() => {
		const session = window.godotXRSession;
		if (!session) return [];
		const source = Array.from(session.inputSources).find(s => s.handedness === '%s' && s.gripSpace);
		return source ? Array.from(source.profiles) : [];
	})())""" % _handedness(), true)
	var profiles: Variant = JSON.parse_string(result) if result is String else null
	return profiles if profiles is Array else []


func _load_model(profile_id: String) -> void:
	var dir := MODELS_DIR + profile_id + "/"
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "profile.json"))
	var layout: Dictionary = profile["layouts"].get(_handedness(), {})
	if layout.is_empty():
		return
	var scene: PackedScene = load(dir + layout["assetPath"])
	_model = scene.instantiate()
	add_child(_model)
	print("%s: WebXR controller model %s" % [tracker, profile_id])

	for component: Dictionary in layout["components"].values():
		for response: Dictionary in component.get("visualResponses", {}).values():
			var node := _model.find_child(response["valueNodeName"], true, false) as Node3D
			if node == null:
				continue
			var entry := {"component": component, "response": response, "node": node}
			if response.get("valueNodeProperty", "transform") == "transform":
				var min_node := _model.find_child(response["minNodeName"], true, false) as Node3D
				var max_node := _model.find_child(response["maxNodeName"], true, false) as Node3D
				if min_node == null or max_node == null:
					continue
				entry["min"] = min_node.transform
				entry["max"] = max_node.transform
			_responses.append(entry)
	model_loaded.emit()


## Poses each moving part between its min and max nodes, the way the reference
## motion-controllers library does.
func _update_responses() -> void:
	for entry in _responses:
		var component: Dictionary = entry["component"]
		var response: Dictionary = entry["response"]
		var active: bool = _component_state(component) in response.get("states", [])
		var value := 0.0
		match response["componentProperty"]:
			"button":
				value = _button_value(component) if active else 0.0
			"xAxis":
				value = _axes(component).x if active else 0.5
			"yAxis":
				value = _axes(component).y if active else 0.5
			"state":
				value = 1.0 if active else 0.0
		var node: Node3D = entry["node"]
		if entry.has("min"):
			node.transform = (entry["min"] as Transform3D).interpolate_with(entry["max"], value)
		else:
			node.visible = value > 0.0


func _component_state(component: Dictionary) -> String:
	var indices: Dictionary = component["gamepadIndices"]
	if indices.has("button"):
		var index: int = indices["button"]
		if index < BUTTON_NAMES.size() and is_button_pressed(BUTTON_NAMES[index]):
			return "pressed"
		if _button_value(component) > 0.01:
			return "touched"
	if indices.has("xAxis"):
		var axes := _raw_axes(component)
		if absf(axes.x) > 0.1 or absf(axes.y) > 0.1:
			return "touched"
	return "default"


func _button_value(component: Dictionary) -> float:
	var index: int = component["gamepadIndices"].get("button", -1)
	if index < 0 or index >= BUTTON_NAMES.size():
		return 0.0
	return maxf(get_float(PRESSURE_NAMES[index]), 1.0 if is_button_pressed(BUTTON_NAMES[index]) else 0.0)


## The component's axes as the gamepad reports them, with +y pointing down.
func _raw_axes(component: Dictionary) -> Vector2:
	var index: int = component["gamepadIndices"]["xAxis"]
	if index / 2 >= AXIS_VECTORS.size():
		return Vector2.ZERO
	# Godot flips y so that up is positive; the profiles expect the raw value.
	var axes := get_vector2(AXIS_VECTORS[index / 2])
	return Vector2(axes.x, -axes.y)


## Axes mapped into 0..1, clamped to the unit circle.
func _axes(component: Dictionary) -> Vector2:
	return _raw_axes(component).limit_length(1.0) * 0.5 + Vector2(0.5, 0.5)
