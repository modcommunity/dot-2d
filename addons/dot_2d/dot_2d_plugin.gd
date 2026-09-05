@tool
extends EditorPlugin

## Editor entry point for dot-2d. Registers inspector types only.
##
## No autoload, for the family's reason: a process may run a server and a client at
## once, and a singleton arena makes that impossible. [Dot2DArena] registers itself in
## [DotRegistry] instead.

const _ICON := "res://addons/dot_2d/icon_placeholder.svg"

const _TYPES := [
	["Dot2DArena", "Node2D", "res://addons/dot_2d/world/dot_2d_arena.gd"],
	["Dot2DController", "Node2D", "res://addons/dot_2d/nodes/dot_2d_controller.gd"],
	["Dot2DSampler", "Node", "res://addons/dot_2d/nodes/dot_2d_sampler.gd"],
	["Dot2DCameraRig", "Camera2D", "res://addons/dot_2d/nodes/dot_2d_camera_rig.gd"],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
