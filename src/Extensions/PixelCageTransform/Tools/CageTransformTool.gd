extends BaseTool

var canvas: Node2D
var cage_transform: Node2D

var extensions_api: Node
var global: Node

var cage_transform_scene: PackedScene = preload("res://src/Extensions/PixelCageTransform/CageTransform.tscn")
var selection_node: Node2D

func _enter_tree() -> void:
	extensions_api = get_node("/root/ExtensionsApi")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if extensions_api:
		global = extensions_api.get_global()
		if !global.current_project.has_selection:
			return
		canvas = extensions_api.get_canvas()
		selection_node = canvas.selection
		if selection_node:
			selection_node.transform_content_start()
			selection_node.hide()
			cage_transform = cage_transform_scene.instance()
			canvas.add_child(cage_transform)
			cage_transform.global_position = selection_node.original_big_bounding_rectangle.position
			cage_transform.set_image(selection_node.original_preview_image)

func draw_start(_draw_pos: Vector2) -> void:
	pass

func _input(event: InputEvent) -> void:
	if cage_transform:
		if Input.is_action_just_pressed("ui_accept"):
			selection_node.preview_image = cage_transform.confirm()
			var new_rect := Rect2(cage_transform.get_bounding_box_position(), selection_node.preview_image.get_size())
			selection_node.big_bounding_rectangle = new_rect
			selection_node.transform_content_confirm()
			_resize_selection(selection_node)
			selection_node.show()
			cage_transform.queue_free()
			cage_transform = null
		else:
			cage_transform._handle_input(event)

func _process(_delta) -> void:
	if selection_node:
		selection_node.dragged_gizmo = null # Prevent the gizmos from being dragged while in this tool

func queue_free() -> void:
	if selection_node:
		selection_node.show()
	.queue_free()

# This logic is not present in the v0.10.3 release of Pixelorama
# Providing an implementation here for compatability
func _resize_selection(selection: Node2D) -> void:
	var size = selection.big_bounding_rectangle.size.abs()
	var selection_map = global.current_project.selection_map
	var selection_map_copy = SelectionMap.new()
	selection_map_copy.copy_from(selection_map)
	selection_map_copy.resize_bitmap_values(
		global.current_project, size, selection.temp_rect.size.x < 0, selection.temp_rect.size.y < 0
	)
	global.current_project.selection_map = selection_map_copy
	global.current_project.selection_map_changed()
	selection.update()
