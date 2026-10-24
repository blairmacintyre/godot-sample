class_name LightSwitch
extends StaticBody3D
## A wall switch: grabbing it flips it.

signal toggled

func _ready() -> void:
	add_to_group(HandController.GRABBABLE_GROUP)


func grab_begin(_hand: Node3D) -> void:
	toggled.emit()


func grab_end(_hand: Node3D) -> void:
	pass
