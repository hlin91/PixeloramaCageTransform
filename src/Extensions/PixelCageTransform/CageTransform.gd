extends Node2D

export var cage_height: float = 10.0
export var cage_width: float = 10.0
export var bake_interval: float = 5.0

onready var top_edge: Node= $TopEdge
onready var bottom_edge: Node = $BottomEdge
onready var left_edge: Node = $LeftEdge
onready var right_edge: Node = $RightEdge
onready var preview_cooldown: Timer = $PreviewCooldown
onready var transform_preview_sprite: Sprite = $TransformPreview

var image: Image
var transform_preview_image: Image
var deformed_relative_pixel_positions: Array = []
# Pre-deformation baked points cache used to calculate displacement
var top_cached_points: Array = []
var left_cached_points: Array = []
var right_cached_points: Array = []
var bottom_cached_points: Array = []

var transform_preview_cooldown: bool = false

func _ready():
	connect_edge_signals(top_edge)
	connect_edge_signals(bottom_edge)
	connect_edge_signals(left_edge)
	connect_edge_signals(right_edge)
	top_cached_points.resize(101)
	left_cached_points.resize(101)
	right_cached_points.resize(101)
	bottom_cached_points.resize(101)

func connect_edge_signals(edge: Node) -> void:
	if edge.connect("handle_dragged", self, "_on_edge_update") != OK:
		print_debug("Failed to connect handle_dragged signal: %s" % edge)
	if edge.connect("point_dragged", self, "_on_edge_update") != OK:
		print_debug("Failed to connect point_dragged signal: %s" % edge)

func set_image(img: Image) -> void:
	image = img
	_set_transform_preview(img)
	init_size(img.get_width(), img.get_height())
	transform_preview_sprite.position = Vector2(img.get_width() / 2, img.get_height() / 2)

func _crop_transparent_borders(img: Image) -> Image:
	var crop_rect := img.get_used_rect()
	var new_image := Image.new()
	new_image.create(crop_rect.size.x, crop_rect.size.y, false, Image.FORMAT_RGBA8)
	new_image.blit_rect(img, crop_rect, Vector2.ZERO)
	return new_image
	
func _set_transform_preview(img: Image) -> void:
	var new_size := get_viewport_rect().size
	var new_image := Image.new()
	new_image.create(new_size.x, new_size.y, false, Image.FORMAT_RGBA8)

	new_image.lock()

	# Calculate the position where the original image will be copied
	var original_position = Vector2(
		(new_size.x - img.get_width()) / 2,
		(new_size.y - img.get_height()) / 2
	)

	img.lock()
	# Copy source image into center of new image
	for x in range(img.get_width()):
		for y in range(img.get_height()):
			var color = img.get_pixel(x, y)
			new_image.set_pixel(original_position.x + x, original_position.y + y, color)
	img.unlock()

	new_image.unlock()
	var texture := ImageTexture.new()
	texture.create_from_image(new_image, 0)
	transform_preview_sprite.texture = texture
	transform_preview_image = new_image

func _update_points_cache() -> void:
	for i in range(101):
		var t := i / 100.0
		top_cached_points[i] = top_edge.curve.interpolate(0, t)
		left_cached_points[i] = left_edge.curve.interpolate(0, t)
		right_cached_points[i] = right_edge.curve.interpolate(0, t)
		bottom_cached_points[i] = bottom_edge.curve.interpolate(0, t)

# Initialize the cage with the given size
func init_size(width: float, height: float) -> void:
	cage_width = width
	cage_height = height
	top_edge.init(Vector2.ZERO, Vector2(width, 0))
	bottom_edge.init(Vector2(0, height), Vector2(width, height))
	left_edge.init(Vector2.ZERO, Vector2(0, height))
	right_edge.init(Vector2(width, 0), Vector2(width, height))
	_update_points_cache()
	for _i in range(width):
		var l := []
		for _j in range(height):
			l.push_back(Vector2.ZERO)
		deformed_relative_pixel_positions.push_back(l)

# Returns the component of v1 that is orthogonal to v2
func _orthogonal_component(v1: Vector2, v2: Vector2) -> Vector2:
	var projection = v1.project(v2.normalized())
	return v1 - projection
		
# Updates the array of new pixel positions based on the deformation of the cage (array[0][0] returns the new relative position of pixel (0,0))
# Positions are relative to pixel (0,0) and can be negative
func _update_deformed_pixel_positions() -> void:
	var threads := []
	for x in range(image.get_width()):
		var t := Thread.new()
		t.start(self, "_update_deformed_pixel_position_col", x)
		threads.push_back(t)
	for t in threads:
		t.wait_to_finish()

func _update_deformed_pixel_position_col(x: int):
	for y in range(image.get_height()):
			var deformation_vector:= Vector2.ZERO
			var horizontal_progress := int((float(x) / (image.get_width() - 1)) * 100)
			var vertical_progress := int((float(y) / (image.get_height() - 1)) * 100)
			var top_edge_weight := pow(((image.get_height() - 1) - float(y)) / (image.get_height() - 1), 1)
			var bottom_edge_weight := pow(float(y) / (image.get_height()), 1)
			var left_edge_weight := pow(((image.get_width() - 1) - float(x)) / (image.get_width() - 1), 1)
			var right_edge_weight := pow(float(x) / (image.get_width() - 1), 1)

			deformed_relative_pixel_positions[x][y] = Vector2.ZERO
			# Apply transform from top edge
			deformation_vector = top_edge.curve.interpolate(0, horizontal_progress / 100.0) - top_cached_points[horizontal_progress]
			deformed_relative_pixel_positions[x][y] += _orthogonal_component(
				deformation_vector,
				top_cached_points[clamp(horizontal_progress - 1, 0, top_cached_points.size())] - top_cached_points[clamp(horizontal_progress + 1, 0, top_cached_points.size())]
			) * top_edge_weight
			# Apply transform from bottom edge
			deformation_vector = bottom_edge.curve.interpolate(0, horizontal_progress / 100.0) - bottom_cached_points[horizontal_progress]
			deformed_relative_pixel_positions[x][y] += _orthogonal_component(
				deformation_vector,
				bottom_cached_points[clamp(horizontal_progress - 1, 0, bottom_cached_points.size())] - bottom_cached_points[clamp(horizontal_progress + 1, 0, bottom_cached_points.size())]
			) * bottom_edge_weight
			# Apply transform from left edge
			deformation_vector = left_edge.curve.interpolate(0, vertical_progress / 100.0) - left_cached_points[vertical_progress]
			deformed_relative_pixel_positions[x][y] += _orthogonal_component(
				deformation_vector,
				left_cached_points[clamp(vertical_progress - 1, 0, left_cached_points.size())] - left_cached_points[clamp(vertical_progress + 1, 0, left_cached_points.size())]
			) * left_edge_weight
			# Apply transform from right edge
			deformation_vector = right_edge.curve.interpolate(0, vertical_progress / 100.0) - right_cached_points[vertical_progress]
			deformed_relative_pixel_positions[x][y] += _orthogonal_component(
				deformation_vector,
				right_cached_points[clamp(vertical_progress - 1, 0, right_cached_points.size())] - right_cached_points[clamp(vertical_progress + 1, 0, right_cached_points.size())]
			) * right_edge_weight

# Updates the preview image using the deformed pixel position cache
func _update_transform_preview() -> void:
	if transform_preview_cooldown:
		print_debug("Skipping preview image update")
		return
	var transform_preview_size := transform_preview_sprite.texture.get_size()
	var original_position := Vector2(
		(transform_preview_size.x - image.get_width()) / 2,
		(transform_preview_size.y - image.get_height()) / 2
	)
	transform_preview_image.fill(Color(0, 0, 0, 0))
	
	image.lock()
	transform_preview_image.lock()

	var threads := []
	for x in range(image.get_width()):
		var t = Thread.new()
		t.start(self, "_transform_pixel_col", [original_position, x])
		threads.push_back(t)

	for t in threads:
		t.wait_to_finish()

	image.unlock()
	transform_preview_image.unlock()
	transform_preview_sprite.texture.set_data(transform_preview_image)
	

func _transform_pixel_col(args: Array) -> void:
	var original_position = args[0]
	var col = args[1]

	for y in range(image.get_height()):
		var new_pixel_position = original_position + Vector2(col, y) + deformed_relative_pixel_positions[col][y]
		transform_preview_image.set_pixelv(new_pixel_position, image.get_pixel(col, y))

func transform_image_with_cage() -> void:
	_update_deformed_pixel_positions()
	_update_transform_preview()
	pass

# Calculates the real pixel position of the top-left pixel of the bounding box for the transformed image
# using the deformed relative pixel positions
func _get_bounding_box_pixel_pos() -> Vector2:
	var transform_preview_size := transform_preview_sprite.texture.get_size()
	var original_position := Vector2(
		(transform_preview_size.x - image.get_width()) / 2,
		(transform_preview_size.y - image.get_height()) / 2
	)
	var min_x := -1
	var min_y := -1
	
	for x in range(image.get_width()):
		for y in range(image.get_height()):
			var real_pixel_pos = original_position + Vector2(x, y) + deformed_relative_pixel_positions[x][y]
			if min_x == -1 or real_pixel_pos.x < min_x:
				min_x = real_pixel_pos.x
			if min_y == -1 or real_pixel_pos.y < min_y:
				min_y = real_pixel_pos.y

	return Vector2(min_x, min_y)

# Saves the transformed image
func confirm() -> Image:
	var crop_rect := Rect2(_get_bounding_box_pixel_pos(), Vector2(cage_width, cage_height))
	var final_image := Image.new()
	final_image.create(cage_width, cage_height, false, Image.FORMAT_RGBA8)
	final_image.blit_rect(transform_preview_image, crop_rect, Vector2.ZERO)
	return final_image

# Get the top-left position of the bounding box for the cage
func get_bounding_box_position() -> Vector2:
	var min_y_values := [
		top_edge.get_min_y_point().y,
		bottom_edge.get_min_y_point().y,
		left_edge.get_min_y_point().y,
		right_edge.get_min_y_point().y
	]
	var min_x_values := [
		top_edge.get_min_x_point().x,
		bottom_edge.get_min_x_point().x,
		left_edge.get_min_x_point().x,
		right_edge.get_min_x_point().x
	]
	return Vector2(min_x_values.min(), min_y_values.min())
	
func _process(_delta) -> void:
	# Keep the edges in sync
	left_edge.curve.set_point_position(0, top_edge.curve.get_point_position(0))
	right_edge.curve.set_point_position(0, top_edge.curve.get_point_position(1))
	bottom_edge.curve.set_point_position(0, left_edge.curve.get_point_position(1))
	bottom_edge.curve.set_point_position(1, right_edge.curve.get_point_position(1))

func _handle_input(event: InputEvent) -> void:
	top_edge._handle_input(event)
	bottom_edge._handle_input(event)
	left_edge._handle_input(event)
	right_edge._handle_input(event)
	
func _on_edge_update() -> void:
	var max_y_values := [
		top_edge.get_max_y_point().y,
		bottom_edge.get_max_y_point().y,
		left_edge.get_max_y_point().y,
		right_edge.get_max_y_point().y
	]
	var min_y_values := [
		top_edge.get_min_y_point().y,
		bottom_edge.get_min_y_point().y,
		left_edge.get_min_y_point().y,
		right_edge.get_min_y_point().y
	]
	var max_x_values := [
		top_edge.get_max_x_point().x,
		bottom_edge.get_max_x_point().x,
		left_edge.get_max_x_point().x,
		right_edge.get_max_x_point().x
	]
	var min_x_values := [
		top_edge.get_min_x_point().x,
		bottom_edge.get_min_x_point().x,
		left_edge.get_min_x_point().x,
		right_edge.get_min_x_point().x
	]
	cage_height = abs(max_y_values.max() - min_y_values.min())
	cage_width = abs(max_x_values.max() - min_x_values.min())
	transform_image_with_cage()
	if preview_cooldown.is_stopped():
		transform_preview_cooldown = true
		preview_cooldown.start()

func _on_PreviewCooldown_timeout():
	transform_preview_cooldown = false
