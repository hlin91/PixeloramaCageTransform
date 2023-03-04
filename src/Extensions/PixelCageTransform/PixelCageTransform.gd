extends Node2D

var extensions_api: Node
var cage_transform_tool_scene: PackedScene = preload("res://src/Extensions/PixelCageTransform/Tools/CageTransformTool.tscn")

func _enter_tree() -> void:
	extensions_api = get_node("/root/ExtensionsApi")
	if extensions_api:
		extensions_api.add_tool("CageTransform", "CageTransform", "cage_transform", cage_transform_tool_scene)

func _exit_tree() -> void:
	if extensions_api:
		extensions_api.remove_tool("CageTransform")
