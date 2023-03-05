extends Path2D

onready var visual_line: Line2D = $VisualLine
onready var visual_line_outline: Line2D = $VisualLineOutline
onready var in_handle_line: Line2D = $InHandleLine
onready var out_handle_line: Line2D = $OutHandleLine
onready var in_handle: Node2D = $InHandle
onready var out_handle: Node2D = $OutHandle
onready var point_1: Node2D = $Point1
onready var point_2: Node2D = $Point2

onready var extensions_api = get_node("/root/ExtensionsApi")
var global: Node

var canvas: Node2D

var dragging_handle: bool = false
var dragging_point: bool = false
var selected_point_index: int = -1
var selected_handle: Node2D = null
var zoom: Vector2 = Vector2.ONE

signal handle_dragged
signal point_dragged

func _ready():
	in_handle.hide()
	out_handle.hide()
	in_handle_line.add_point(Vector2.ZERO)
	in_handle_line.add_point(Vector2.ZERO)
	out_handle_line.add_point(Vector2.ZERO)
	out_handle_line.add_point(Vector2.ZERO)
	in_handle_line.hide()
	out_handle_line.hide()
	if extensions_api:
		canvas = extensions_api.general.get_canvas()
		global = extensions_api.general.get_global()

func _process(_delta):
	update_line_with_path()
	if curve:
		point_1.position = curve.get_point_position(0)
		point_2.position = curve.get_point_position(1)
	if selected_point_index >= 0:
		in_handle_line.set_point_position(0, curve.get_point_position(selected_point_index))
		in_handle_line.set_point_position(1, in_handle.position)
		out_handle_line.set_point_position(0, curve.get_point_position(selected_point_index))
		out_handle_line.set_point_position(1, out_handle.position)
	if global:
		zoom = global.camera.zoom
		_update_based_on_zoom()

func _update_based_on_zoom() -> void:
	visual_line.width = 1 * zoom.x
	visual_line_outline.width = 2 * zoom.x
	in_handle_line.width = 1 * zoom.x
	out_handle_line.width = 1 * zoom.x
	in_handle.scale = zoom
	out_handle.scale = zoom
	point_1.scale = zoom
	point_2.scale = zoom

func init(point1: Vector2, point2: Vector2):
	var curve = Curve2D.new()
	var length = (point1 - point2).length()
	curve.add_point(point1)
	curve.set_point_out(0, point1.direction_to(point2).normalized() * length / 3.0)
	curve.add_point(point2)
	curve.set_point_in(1, point2.direction_to(point1).normalized() * length / 3.0)
	set_curve(curve)

func get_min_y_point() -> Vector2:
	var min_index = -1
	var min_y = 0
	var baked_points = curve.get_baked_points()
	for i in range(baked_points.size()):
		var p = baked_points[i]
		if min_index == -1 or p.y < min_y:
			min_index = i
			min_y = p.y
	return to_global(baked_points[min_index])

func get_max_y_point() -> Vector2:
	var max_index = -1
	var max_y = 0
	var baked_points = curve.get_baked_points()
	for i in range(baked_points.size()):
		var p = baked_points[i]
		if max_index == -1 or p.y > max_y:
			max_index = i
			max_y = p.y
	return to_global(baked_points[max_index])

func get_min_x_point() -> Vector2:
	var min_index = -1
	var min_x = 0
	var baked_points = curve.get_baked_points()
	for i in range(baked_points.size()):
		var p = baked_points[i]
		if min_index == -1 or p.x < min_x:
			min_index = i
			min_x = p.x
	return to_global(baked_points[min_index])

func get_max_x_point() -> Vector2:
	var max_index = -1
	var max_x = 0
	var baked_points = curve.get_baked_points()
	for i in range(baked_points.size()):
		var p = baked_points[i]
		if max_index == -1 or p.x > max_x:
			max_index = i
			max_x = p.x
	return to_global(baked_points[max_index])

func update_line_with_path() -> void:
	visual_line.clear_points()
	visual_line_outline.clear_points()
	var baked_points = curve.get_baked_points()
	while visual_line.points.size() < baked_points.size():
		visual_line.add_point(Vector2.ZERO)
	while visual_line_outline.points.size() < baked_points.size():
		visual_line_outline.add_point(Vector2.ZERO)
	for i in range(baked_points.size()):
		visual_line.set_point_position(i, baked_points[i])
		visual_line_outline.set_point_position(i, baked_points[i])

func find_selected_point_index(mouse_pos: Vector2, threshold: float) -> int:
	for i in range(curve.get_point_count()):
		var point = to_global(curve.get_point_position(i))
		if point.distance_to(mouse_pos) < threshold:
			return i
	return -1

func find_selected_in_out_handle(mouse_pos: Vector2, threshold: float) -> Node2D:
	if mouse_pos.distance_to(in_handle.global_position) < threshold and in_handle.visible:
		return in_handle
	if mouse_pos.distance_to(out_handle.global_position) < threshold and out_handle.visible:
		return out_handle
	return null

func _get_mouse_pos() -> Vector2:
	if canvas:
		return canvas.current_pixel
	return get_global_mouse_position()

func _handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		var mouse_pos = _get_mouse_pos()
		if mouse_event.button_index == BUTTON_LEFT and mouse_event.pressed:
			var prev_handle = selected_handle
			var prev_point = selected_point_index
			selected_handle = find_selected_in_out_handle(mouse_pos, in_handle.texture.get_width() * zoom.x * 1.5)
			
			if prev_handle != selected_handle:
				in_handle.hide()
				out_handle.hide()
				
			if selected_handle != null:
				selected_handle.show()
				dragging_handle = true
			else:
				selected_point_index = find_selected_point_index(mouse_pos, point_1.texture.get_width() * zoom.x * 1.5)
				
			if selected_point_index >= 0:
				dragging_point = true
				var vector = curve.get_point_in(selected_point_index)
				if vector != Vector2.ZERO:
					in_handle.position = vector + curve.get_point_position(selected_point_index)
					in_handle.show()
					in_handle_line.show()
				vector = curve.get_point_out(selected_point_index)
				if vector != Vector2.ZERO:
					out_handle.position = vector + curve.get_point_position(selected_point_index)
					out_handle.show()
					out_handle_line.show()
					
			if !(selected_point_index >= 0 or selected_handle != null) or prev_point != selected_point_index:
				in_handle.hide()
				out_handle.hide()
				in_handle_line.hide()
				out_handle_line.hide()
				
		elif mouse_event.button_index == BUTTON_LEFT and !mouse_event.pressed:
			dragging_handle = false
			dragging_point = false

	if event is InputEventMouseMotion:
		if dragging_handle and selected_point_index >= 0 and selected_handle != null:
			selected_handle.global_position = _get_mouse_pos()
			if selected_handle == in_handle:
				curve.set_point_in(selected_point_index, in_handle.position - curve.get_point_position(selected_point_index))
			if selected_handle == out_handle:
				curve.set_point_out(selected_point_index, out_handle.position - curve.get_point_position(selected_point_index))
			emit_signal("handle_dragged")
				
		elif dragging_point and selected_point_index >= 0:
			curve.set_point_position(selected_point_index, to_local(_get_mouse_pos()))
			in_handle.position = curve.get_point_in(selected_point_index) + curve.get_point_position(selected_point_index)
			out_handle.position = curve.get_point_out(selected_point_index) + curve.get_point_position(selected_point_index)
			emit_signal("point_dragged")
