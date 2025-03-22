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

const MINIMAP_WIDTH = 150  # Width in pixels
const MINIMAP_HEIGHT = 150  # Height in pixels
const MINIMAP_BORDER_COLOR = Color(0.8, 0.8, 0.8)
const MINIMAP_BORDER_WIDTH = 2

# Minimap settings
const MINIMAP_TILE_SIZE = 4  # Size of each tile on minimap
const MINIMAP_VISIBLE_RANGE = 15  # Number of tiles to show in each direction
const MINIMAP_BG_COLOR = Color(0.1, 0.1, 0.1, 0.7)  # Dark background
const MINIMAP_WALL_COLOR = Color(0.5, 0.5, 0.5)  # Wall color
const MINIMAP_ROAD_COLOR = Color(0.2, 0.2, 0.2)  # Road color
const MINIMAP_THIEF_COLOR = Color(1.0, 0.8, 0.0)  # Gold for thief
const MINIMAP_POLICE_COLOR = Color(0.2, 0.4, 1.0)  # Blue for police
const MINIMAP_COLLECTIBLE_COLOR = Color(1.0, 1.0, 0.2, 0.6)  # Yellow for collectibles

# References to game objects
var map = null
var thief = null
var police = null
var main_game = null

# Minimap buffer
var minimap_buffer = []
var minimap_size = Vector2(MINIMAP_VISIBLE_RANGE * 2 + 1, MINIMAP_VISIBLE_RANGE * 2 + 1)

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT:
			if event.pressed:
				# Check if the click is within the minimap area
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
		# Move the minimap
		global_position = initial_minimap_pos + (event.global_position - drag_start_pos)
		
		# Keep minimap within screen bounds
		var viewport_size = get_viewport_rect().size
		global_position.x = clamp(global_position.x, 0, viewport_size.x - MINIMAP_WIDTH)
		global_position.y = clamp(global_position.y, 0, viewport_size.y - MINIMAP_HEIGHT)

func _ready():
	# Set references from parent
	main_game = get_parent()
	map = main_game.get_node("TileMap")
	thief = main_game.get_node("ThiefCar")
	police = main_game.get_node("PoliceCar")
	
	# Initialize the minimap buffer
	initialize_buffer()
	var toggle_button = Button.new()
	toggle_button.text = "Map"
	toggle_button.rect_position = Vector2(0, 160)  # Below the minimap
	toggle_button.rect_size = Vector2(60, 30)
	toggle_button.connect("pressed", self, "_on_toggle_button_pressed")
	add_child(toggle_button)
	
	# Enable input processing for dragging
	set_process_input(true)

func initialize_buffer():
	# Create a 2D array for the minimap
	minimap_buffer = []
	for y in range(minimap_size.y):
		var row = []
		for x in range(minimap_size.x):
			row.append(-1)  # -1 means unexplored
		minimap_buffer.append(row)

func _process(delta):
	if minimap_visible:
		update()  # Only trigger redraw when visible

func _draw():
	# Calculate the scale to fit the minimap in the specified dimensions
	var scale_factor = min(
		MINIMAP_WIDTH / (minimap_size.x * MINIMAP_TILE_SIZE),
		MINIMAP_HEIGHT / (minimap_size.y * MINIMAP_TILE_SIZE)
	)
	
	# Apply scaling
	scale = Vector2(scale_factor, scale_factor)
	
	# Draw minimap background with border
	var minimap_rect = Rect2(
		Vector2(0, 0),
		Vector2(minimap_size.x * MINIMAP_TILE_SIZE, minimap_size.y * MINIMAP_TILE_SIZE)
	)
	draw_rect(minimap_rect, MINIMAP_BG_COLOR, true)
	draw_rect(minimap_rect, MINIMAP_BORDER_COLOR, false, MINIMAP_BORDER_WIDTH)
	
	# Get player position (either thief or police depending on who's controlled)
	var player_pos = thief.map_pos if main_game.is_player_thief else police.map_pos
	
	# Update and draw the minimap centered on player position
	update_minimap_buffer(player_pos)
	draw_minimap_from_buffer(player_pos)
	
	# Draw thief and police positions
	draw_character_markers(player_pos)
	
	# Draw collectibles
	draw_collectibles(player_pos)
	
	# Draw player direction indicator (arrow)
	draw_player_direction_indicator(player_pos)

func draw_player_direction_indicator(center_pos):
	var player = thief if main_game.is_player_thief else police
	var player_minimap_pos = world_to_minimap_pos(player.map_pos, center_pos)
	var center = Vector2(player_minimap_pos.x + MINIMAP_TILE_SIZE / 2, 
						 player_minimap_pos.y + MINIMAP_TILE_SIZE / 2)
	
	# Determine direction based on animation state
	var direction = Vector2(0, 0)
	match player.get_node("AnimatedSprite").animation:
		"n": direction = Vector2(0, -1)
		"s": direction = Vector2(0, 1)
		"e": direction = Vector2(1, 0)
		"w": direction = Vector2(-1, 0)
	
	if direction != Vector2(0, 0):
		var arrow_length = MINIMAP_TILE_SIZE * 1.5
		var arrow_end = center + direction * arrow_length
		
		# Draw direction line
		var color = MINIMAP_THIEF_COLOR if main_game.is_player_thief else MINIMAP_POLICE_COLOR
		draw_line(center, arrow_end, color, 1.5)
		
		# Draw arrowhead
		var arrowhead_size = MINIMAP_TILE_SIZE / 2
		var angle = direction.angle()
		var arrowhead1 = arrow_end - Vector2(cos(angle + PI * 0.75), sin(angle + PI * 0.75)) * arrowhead_size
		var arrowhead2 = arrow_end - Vector2(cos(angle - PI * 0.75), sin(angle - PI * 0.75)) * arrowhead_size
		
		var points = PoolVector2Array([arrow_end, arrowhead1, arrowhead2])
		draw_colored_polygon(points, color)

func update_minimap_buffer(center_pos):
	# Update the buffer with the current state of the map around the player
	for y in range(-MINIMAP_VISIBLE_RANGE, MINIMAP_VISIBLE_RANGE + 1):
		for x in range(-MINIMAP_VISIBLE_RANGE, MINIMAP_VISIBLE_RANGE + 1):
			var world_pos = Vector2(center_pos.x + x, center_pos.y + y)
			var buffer_x = x + MINIMAP_VISIBLE_RANGE
			var buffer_y = y + MINIMAP_VISIBLE_RANGE
			
			# Check if the cell is explored
			var cell_value = map.get_cellv(world_pos)
			
			# Store the cell value in the buffer
			if buffer_x >= 0 and buffer_x < minimap_size.x and buffer_y >= 0 and buffer_y < minimap_size.y:
				minimap_buffer[buffer_y][buffer_x] = cell_value

func draw_minimap_from_buffer(center_pos):
	# Draw the minimap from the buffer
	for y in range(minimap_size.y):
		for x in range(minimap_size.x):
			var cell_value = minimap_buffer[y][x]
			
			if cell_value != -1:  # If the cell has been explored
				var rect_pos = Vector2(x * MINIMAP_TILE_SIZE, y * MINIMAP_TILE_SIZE)
				var rect_size = Vector2(MINIMAP_TILE_SIZE, MINIMAP_TILE_SIZE)
				var rect = Rect2(rect_pos, rect_size)
				
				# Draw road
				draw_rect(rect, MINIMAP_ROAD_COLOR, true)
				
				# Draw walls based on cell value
				draw_cell_walls(rect_pos, cell_value)

func draw_cell_walls(pos, cell_value):
	var line_width = 1.0
	
	# North wall
	if cell_value & N:
		draw_line(
			Vector2(pos.x, pos.y),
			Vector2(pos.x + MINIMAP_TILE_SIZE, pos.y),
			MINIMAP_WALL_COLOR,
			line_width
		)
	
	# East wall
	if cell_value & E:
		draw_line(
			Vector2(pos.x + MINIMAP_TILE_SIZE, pos.y),
			Vector2(pos.x + MINIMAP_TILE_SIZE, pos.y + MINIMAP_TILE_SIZE),
			MINIMAP_WALL_COLOR,
			line_width
		)
	
	# South wall
	if cell_value & S:
		draw_line(
			Vector2(pos.x, pos.y + MINIMAP_TILE_SIZE),
			Vector2(pos.x + MINIMAP_TILE_SIZE, pos.y + MINIMAP_TILE_SIZE),
			MINIMAP_WALL_COLOR,
			line_width
		)
	
	# West wall
	if cell_value & W:
		draw_line(
			Vector2(pos.x, pos.y),
			Vector2(pos.x, pos.y + MINIMAP_TILE_SIZE),
			MINIMAP_WALL_COLOR,
			line_width
		)

func draw_character_markers(center_pos):
	# Draw thief position
	var thief_minimap_pos = world_to_minimap_pos(thief.map_pos, center_pos)
	draw_circle(
		Vector2(thief_minimap_pos.x + MINIMAP_TILE_SIZE / 2, 
				thief_minimap_pos.y + MINIMAP_TILE_SIZE / 2),
		MINIMAP_TILE_SIZE / 1.5,
		MINIMAP_THIEF_COLOR
	)
	
	# Draw special effect if thief is invisible
	if thief.special_active:
		draw_circle(
			Vector2(thief_minimap_pos.x + MINIMAP_TILE_SIZE / 2, 
					thief_minimap_pos.y + MINIMAP_TILE_SIZE / 2),
			MINIMAP_TILE_SIZE,
			Color(MINIMAP_THIEF_COLOR.r, MINIMAP_THIEF_COLOR.g, MINIMAP_THIEF_COLOR.b, 0.3)
		)
	
	# Draw police position
	var police_minimap_pos = world_to_minimap_pos(police.map_pos, center_pos)
	draw_circle(
		Vector2(police_minimap_pos.x + MINIMAP_TILE_SIZE / 2, 
				police_minimap_pos.y + MINIMAP_TILE_SIZE / 2),
		MINIMAP_TILE_SIZE / 1.5,
		MINIMAP_POLICE_COLOR
	)
	
	# Draw special effect if police has x-ray vision
	if police.special_active:
		draw_circle(
			Vector2(police_minimap_pos.x + MINIMAP_TILE_SIZE / 2, 
					police_minimap_pos.y + MINIMAP_TILE_SIZE / 2),
			MINIMAP_TILE_SIZE,
			Color(MINIMAP_POLICE_COLOR.r, MINIMAP_POLICE_COLOR.g, MINIMAP_POLICE_COLOR.b, 0.3)
		)

func draw_collectibles(center_pos):
	# Draw collectibles on minimap
	for child in main_game.get_children():
		if child.has_method("collect"):
			var collectible_pos = world_to_minimap_pos(child.map_pos, center_pos)
			draw_rect(
				Rect2(collectible_pos, Vector2(MINIMAP_TILE_SIZE, MINIMAP_TILE_SIZE)),
				MINIMAP_COLLECTIBLE_COLOR,
				true
			)

func world_to_minimap_pos(world_pos, center_pos):
	# Convert world coordinates to minimap coordinates
	var rel_x = world_pos.x - center_pos.x + MINIMAP_VISIBLE_RANGE
	var rel_y = world_pos.y - center_pos.y + MINIMAP_VISIBLE_RANGE
	return Vector2(rel_x * MINIMAP_TILE_SIZE, rel_y * MINIMAP_TILE_SIZE)

# Function to check if a position is visible on the minimap
func is_visible_on_minimap(world_pos, center_pos):
	var rel_x = world_pos.x - center_pos.x + MINIMAP_VISIBLE_RANGE
	var rel_y = world_pos.y - center_pos.y + MINIMAP_VISIBLE_RANGE
	
	return (rel_x >= 0 and rel_x < minimap_size.x and 
			rel_y >= 0 and rel_y < minimap_size.y)
			
func _on_toggle_button_pressed():
	minimap_visible = !minimap_visible
	
	# Show/hide minimap components
	for child in get_children():
		if child is Button:  # Keep the toggle button visible
			continue
		child.visible = minimap_visible
	
	# Always show ourselves and the button
	visible = true

