extends Node2D

var zoom_level = 1.0
const MIN_ZOOM = 0.5
const MAX_ZOOM = 2.0
const ZOOM_STEP = 0.1

var dragging = false
var drag_start_pos = Vector2()
var initial_minimap_pos = Vector2()
var minimap_visible = true

const N = 0x1
const E = 0x2
const S = 0x4
const W = 0x8

const MINIMAP_WIDTH = 150
const MINIMAP_HEIGHT = 150
const MINIMAP_BORDER_COLOR = Color(0.8, 0.8, 0.8)
const MINIMAP_BORDER_WIDTH = 2

const MINIMAP_TILE_SIZE = 4
const MINIMAP_VISIBLE_RANGE = 15
const MINIMAP_BG_COLOR = Color(0.1, 0.1, 0.1, 0.7)
const MINIMAP_WALL_COLOR = Color(0.5, 0.5, 0.5)
const MINIMAP_ROAD_COLOR = Color(0.2, 0.2, 0.2)
const MINIMAP_THIEF_COLOR = Color(1.0, 0.0, 0.0)
const MINIMAP_POLICE_COLOR = Color(0.2, 0.4, 1.0)
const MINIMAP_COLLECTIBLE_COLOR = Color(1.0, 1.0, 0.2, 0.6)

const CS_INSIDE = 0
const CS_LEFT = 1
const CS_RIGHT = 2
const CS_BOTTOM = 4
const CS_TOP = 8

var map = null
var thief = null
var police = null
var main_game = null

var minimap_buffer = []
var minimap_size = Vector2(MINIMAP_VISIBLE_RANGE * 2 + 1, MINIMAP_VISIBLE_RANGE * 2 + 1)

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT:
			if event.pressed:
				var minimap_rect = Rect2(
					global_position,
					Vector2(MINIMAP_WIDTH, MINIMAP_HEIGHT)
				)
				if minimap_rect.has_point(event.global_position):
					dragging = true
					drag_start_pos = event.global_position
					initial_minimap_pos = global_position
			else:
				dragging = false
	
	elif event is InputEventMouseMotion and dragging:
		global_position = initial_minimap_pos + (event.global_position - drag_start_pos)
		
		var viewport_size = get_viewport_rect().size
		global_position.x = clamp(global_position.x, 0, viewport_size.x - MINIMAP_WIDTH)
		global_position.y = clamp(global_position.y, 0, viewport_size.y - MINIMAP_HEIGHT)

func _ready():
	main_game = get_parent().get_parent()
	map = main_game.get_node("TileMap")
	thief = main_game.get_node("ThiefCar")
	police = main_game.get_node("PoliceCar")
	
	initialize_buffer()
	var toggle_button = Button.new()
	toggle_button.text = "Map"
	toggle_button.rect_position = Vector2(0, 160)
	toggle_button.rect_size = Vector2(60, 30)
	toggle_button.connect("pressed", self, "_on_toggle_button_pressed")
	add_child(toggle_button)
	
	set_process_input(true)

func initialize_buffer():
	minimap_buffer = []
	for y in range(minimap_size.y):
		var row = []
		for x in range(minimap_size.x):
			row.append(-1)
		minimap_buffer.append(row)

func _process(delta):
	if minimap_visible:
		update()

func _draw():
	var scale_factor = min(
		MINIMAP_WIDTH / (minimap_size.x * MINIMAP_TILE_SIZE),
		MINIMAP_HEIGHT / (minimap_size.y * MINIMAP_TILE_SIZE)
	)
	
	var minimap_rect = Rect2(
		Vector2(0, 0),
		Vector2(MINIMAP_WIDTH / scale_factor, MINIMAP_HEIGHT / scale_factor)
	)
	draw_rect(minimap_rect, MINIMAP_BG_COLOR, true)
	
	var clip_rect = Rect2(
		Vector2(0, 0),
		Vector2(MINIMAP_WIDTH / scale_factor, MINIMAP_HEIGHT / scale_factor)
	)
	
	var player_pos = thief.map_pos if main_game.is_player_thief else police.map_pos
	
	update_minimap_buffer(player_pos)
	
	draw_minimap_from_buffer(player_pos, clip_rect)
	
	draw_character_markers(player_pos, clip_rect)
	
	draw_collectibles(player_pos, clip_rect)
	
	draw_player_direction_indicator(player_pos, clip_rect)
	
	draw_rect(minimap_rect, MINIMAP_BORDER_COLOR, false, MINIMAP_BORDER_WIDTH)

func is_inside_clip_rect(point, clip_rect):
	return (point.x >= clip_rect.position.x && 
			point.y >= clip_rect.position.y && 
			point.x <= clip_rect.position.x + clip_rect.size.x && 
			point.y <= clip_rect.position.y + clip_rect.size.y)

func is_rect_visible(rect, clip_rect):
	return (rect.position.x + rect.size.x >= clip_rect.position.x &&
			rect.position.y + rect.size.y >= clip_rect.position.y &&
			rect.position.x <= clip_rect.position.x + clip_rect.size.x &&
			rect.position.y <= clip_rect.position.y + clip_rect.size.y)

func compute_code(p, rect):
	var min_x = rect.position.x
	var min_y = rect.position.y
	var max_x = rect.position.x + rect.size.x
	var max_y = rect.position.y + rect.size.y
	
	var code = CS_INSIDE
	if p.x < min_x:
		code |= CS_LEFT
	elif p.x > max_x:
		code |= CS_RIGHT
	if p.y < min_y:
		code |= CS_BOTTOM
	elif p.y > max_y:
		code |= CS_TOP
	return code

func draw_player_direction_indicator(center_pos, clip_rect):
	var player = thief if main_game.is_player_thief else police
	var player_minimap_pos = world_to_minimap_pos(player.map_pos, center_pos)
	var center = Vector2(player_minimap_pos.x + MINIMAP_TILE_SIZE / 2, 
						 player_minimap_pos.y + MINIMAP_TILE_SIZE / 2)
	
	if !is_inside_clip_rect(center, clip_rect):
		return
	
	var direction = Vector2(0, 0)
	match player.get_node("AnimatedSprite").animation:
		"n": direction = Vector2(0, -1)
		"s": direction = Vector2(0, 1)
		"e": direction = Vector2(1, 0)
		"w": direction = Vector2(-1, 0)
	
	if direction != Vector2(0, 0):
		var arrow_length = MINIMAP_TILE_SIZE * 1.5
		var arrow_end = center + direction * arrow_length
		
		if !is_inside_clip_rect(arrow_end, clip_rect):
			var clipped_end = clip_line_to_rect(center, arrow_end, clip_rect)
			if clipped_end != null:
				arrow_end = clipped_end
			else:
				return
		
		var color = MINIMAP_THIEF_COLOR if main_game.is_player_thief else MINIMAP_POLICE_COLOR
		draw_line(center, arrow_end, color, 1.5)
		
		if (arrow_end - center).length() >= arrow_length * 0.9:
			var arrowhead_size = MINIMAP_TILE_SIZE / 2
			var angle = direction.angle()
			var arrowhead1 = arrow_end - Vector2(cos(angle + PI * 0.75), sin(angle + PI * 0.75)) * arrowhead_size
			var arrowhead2 = arrow_end - Vector2(cos(angle - PI * 0.75), sin(angle - PI * 0.75)) * arrowhead_size
			
			if is_inside_clip_rect(arrowhead1, clip_rect) && is_inside_clip_rect(arrowhead2, clip_rect):
				var points = PoolVector2Array([arrow_end, arrowhead1, arrowhead2])
				draw_colored_polygon(points, color)

func clip_line_to_rect(p1, p2, rect):
	var min_x = rect.position.x
	var min_y = rect.position.y
	var max_x = rect.position.x + rect.size.x
	var max_y = rect.position.y + rect.size.y
	
	var code1 = compute_code(p1, rect)
	var code2 = compute_code(p2, rect)
	
	while true:
		if code1 == 0 && code2 == 0:
			return p2
		
		if (code1 & code2) != 0:
			return null
		
		var code_out = code1 if code1 != 0 else code2
		var x = 0
		var y = 0
		
		if (code_out & CS_TOP) != 0:
			x = p1.x + (p2.x - p1.x) * (max_y - p1.y) / (p2.y - p1.y)
			y = max_y
		elif (code_out & CS_BOTTOM) != 0:
			x = p1.x + (p2.x - p1.x) * (min_y - p1.y) / (p2.y - p1.y)
			y = min_y
		elif (code_out & CS_RIGHT) != 0:
			y = p1.y + (p2.y - p1.y) * (max_x - p1.x) / (p2.x - p1.x)
			x = max_x
		elif (code_out & CS_LEFT) != 0:
			y = p1.y + (p2.y - p1.y) * (min_x - p1.x) / (p2.x - p1.x)
			x = min_x
		
		if code_out == code1:
			p1 = Vector2(x, y)
			code1 = compute_code(p1, rect)
		else:
			p2 = Vector2(x, y)
			code2 = compute_code(p2, rect)
	
	return p2

func update_minimap_buffer(center_pos):
	for y in range(-MINIMAP_VISIBLE_RANGE, MINIMAP_VISIBLE_RANGE + 1):
		for x in range(-MINIMAP_VISIBLE_RANGE, MINIMAP_VISIBLE_RANGE + 1):
			var world_pos = Vector2(center_pos.x + x, center_pos.y + y)
			var buffer_x = x + MINIMAP_VISIBLE_RANGE
			var buffer_y = y + MINIMAP_VISIBLE_RANGE
			
			var cell_value = map.get_cellv(world_pos)
			
			if buffer_x >= 0 and buffer_x < minimap_size.x and buffer_y >= 0 and buffer_y < minimap_size.y:
				minimap_buffer[buffer_y][buffer_x] = cell_value

func draw_minimap_from_buffer(center_pos, clip_rect):
	for y in range(minimap_size.y):
		for x in range(minimap_size.x):
			var cell_value = minimap_buffer[y][x]
			
			if cell_value != -1:
				var rect_pos = Vector2(x * MINIMAP_TILE_SIZE, y * MINIMAP_TILE_SIZE)
				var rect_size = Vector2(MINIMAP_TILE_SIZE, MINIMAP_TILE_SIZE)
				var rect = Rect2(rect_pos, rect_size)
				
				if is_rect_visible(rect, clip_rect):
					draw_rect(rect, MINIMAP_ROAD_COLOR, true)
					
					draw_cell_walls(rect_pos, cell_value, clip_rect)

func draw_cell_walls(pos, cell_value, clip_rect):
	var line_width = 1.0
	
	if cell_value & N:
		var start = Vector2(pos.x, pos.y)
		var end = Vector2(pos.x + MINIMAP_TILE_SIZE, pos.y)
		if is_inside_clip_rect(start, clip_rect) || is_inside_clip_rect(end, clip_rect):
			draw_line(start, end, MINIMAP_WALL_COLOR, line_width)
	
	if cell_value & E:
		var start = Vector2(pos.x + MINIMAP_TILE_SIZE, pos.y)
		var end = Vector2(pos.x + MINIMAP_TILE_SIZE, pos.y + MINIMAP_TILE_SIZE)
		if is_inside_clip_rect(start, clip_rect) || is_inside_clip_rect(end, clip_rect):
			draw_line(start, end, MINIMAP_WALL_COLOR, line_width)
	
	if cell_value & S:
		var start = Vector2(pos.x, pos.y + MINIMAP_TILE_SIZE)
		var end = Vector2(pos.x + MINIMAP_TILE_SIZE, pos.y + MINIMAP_TILE_SIZE)
		if is_inside_clip_rect(start, clip_rect) || is_inside_clip_rect(end, clip_rect):
			draw_line(start, end, MINIMAP_WALL_COLOR, line_width)
	
	if cell_value & W:
		var start = Vector2(pos.x, pos.y)
		var end = Vector2(pos.x, pos.y + MINIMAP_TILE_SIZE)
		if is_inside_clip_rect(start, clip_rect) || is_inside_clip_rect(end, clip_rect):
			draw_line(start, end, MINIMAP_WALL_COLOR, line_width)

func draw_character_markers(center_pos, clip_rect):
	var thief_minimap_pos = world_to_minimap_pos(thief.map_pos, center_pos)
	var thief_center = Vector2(thief_minimap_pos.x + MINIMAP_TILE_SIZE / 2, 
							   thief_minimap_pos.y + MINIMAP_TILE_SIZE / 2)
	
	if is_inside_clip_rect(thief_center, clip_rect):
		draw_circle(thief_center, MINIMAP_TILE_SIZE / 1.5, MINIMAP_THIEF_COLOR)
		
		if thief.special_active:
			draw_circle(thief_center, MINIMAP_TILE_SIZE, 
						Color(MINIMAP_THIEF_COLOR.r, MINIMAP_THIEF_COLOR.g, MINIMAP_THIEF_COLOR.b, 0.3))
	
	var police_minimap_pos = world_to_minimap_pos(police.map_pos, center_pos)
	var police_center = Vector2(police_minimap_pos.x + MINIMAP_TILE_SIZE / 2, 
								police_minimap_pos.y + MINIMAP_TILE_SIZE / 2)
	
	if is_inside_clip_rect(police_center, clip_rect):
		draw_circle(police_center, MINIMAP_TILE_SIZE / 1.5, MINIMAP_POLICE_COLOR)
		
		if police.special_active:
			draw_circle(police_center, MINIMAP_TILE_SIZE,
						Color(MINIMAP_POLICE_COLOR.r, MINIMAP_POLICE_COLOR.g, MINIMAP_POLICE_COLOR.b, 0.3))

func draw_collectibles(center_pos, clip_rect):
	for child in main_game.get_children():
		if child.has_method("collect"):
			var collectible_pos = world_to_minimap_pos(child.map_pos, center_pos)
			var collectible_rect = Rect2(collectible_pos, Vector2(MINIMAP_TILE_SIZE, MINIMAP_TILE_SIZE))
			
			if is_rect_visible(collectible_rect, clip_rect):
				draw_rect(collectible_rect, MINIMAP_COLLECTIBLE_COLOR, true)

func world_to_minimap_pos(world_pos, center_pos):
	var rel_x = world_pos.x - center_pos.x + MINIMAP_VISIBLE_RANGE
	var rel_y = world_pos.y - center_pos.y + MINIMAP_VISIBLE_RANGE
	return Vector2(rel_x * MINIMAP_TILE_SIZE, rel_y * MINIMAP_TILE_SIZE)

func is_visible_on_minimap(world_pos, center_pos):
	var rel_x = world_pos.x - center_pos.x + MINIMAP_VISIBLE_RANGE
	var rel_y = world_pos.y - center_pos.y + MINIMAP_VISIBLE_RANGE
	
	return (rel_x >= 0 and rel_x < minimap_size.x and 
			rel_y >= 0 and rel_y < minimap_size.y)
			
func _on_toggle_button_pressed():
	minimap_visible = !minimap_visible
	
	for child in get_children():
		if child is Button:
			continue
		child.visible = minimap_visible
	
	visible = true
