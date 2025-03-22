extends Node2D

const N = 0x1
const E = 0x2
const S = 0x4
const W = 0x8

# Define chunk size and management variables
const CHUNK_SIZE = 4
const VISIBLE_CHUNKS = 4 # How many chunks to keep loaded
const GENERATION_DISTANCE = 3  # How far ahead to generate chunks

onready var region_manager = RegionManager.new()

var cell_walls = {
	Vector2(0, -1): N, 
	Vector2(1, 0): E,
	Vector2(0, 1): S, 
	Vector2(-1, 0): W
}

var chunk_registry = {}  # Tracks which chunks have been generated
var active_chunks = []   # List of currently active chunks

# Game state variables
var is_player_thief = true
var score = 0
var chase_time = 0
var role_switch_timer = 0
var MAX_ROLE_TIME = 30.0  # Switch roles after 30 seconds

onready var navigation = $Navigation2D
# References to nodes
onready var Map = $TileMap
onready var thief = $ThiefCar
onready var police = $PoliceCar
onready var camera = $Camera2D
onready var UI = $UILayer/UI

# Sound effects
onready var switch_sound = $SwitchRoleSound
onready var chase_sound = $ChaseSound
onready var score_sound = $ScoreSound


var debug_mode = false

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_F1:
			debug_mode = !debug_mode
			navigation.visible = debug_mode

func _ready():
	print("Game starting...")
	randomize()
	
	if not has_node("ThiefCar") or not has_node("PoliceCar"):
		push_error("Missing ThiefCar or PoliceCar nodes")
		return
	if not Map:
		push_error("TileMap not found")
		return
	
	$UILayer/UI.max_role_time = MAX_ROLE_TIME
	thief.map = Map
	police.map = Map
	
	thief.map_pos = Vector2(0, 0)
	police.map_pos = Vector2(2, 2)
	thief.position = Map.map_to_world(thief.map_pos) + Vector2(0, 20)
	police.position = Map.map_to_world(police.map_pos) + Vector2(0, 20)
	
	# Generate initial map and navigation
	for x in range(-2, 3):
		for y in range(-2, 3):
			var cell = Vector2(x, y)
			generate_tile(cell)
	
	var chunk_pos = Vector2(0, 0)
	chunk_registry[chunk_pos] = true
	active_chunks.append(chunk_pos)
	create_navigation_polygon(chunk_pos)  # Generate navigation for initial chunk
	
	update_camera()
	$BackgroundMusic.play()
	print("Initialization complete")
	
	if not has_node("Navigation2D"):
		var nav = Navigation2D.new()
		nav.name = "Navigation2D"
		add_child(nav)
		navigation = nav

func _process(delta):
	# Update role switch timer
	role_switch_timer += delta
	if role_switch_timer >= MAX_ROLE_TIME:
		switch_roles()
		role_switch_timer = 0
	
	# Update UI
	UI.update_timer(MAX_ROLE_TIME - role_switch_timer)
	UI.update_score(score)
	
	# Update chase time for more dynamic AI
	chase_time += delta
	
	# Check for map generation needs
	check_and_generate_chunks()
	
	# Check for map cleanup needs
	cleanup_old_chunks()
	
	# Update camera position
	update_camera()

func update_camera():
	# Camera follows the player-controlled character
	var target = thief if is_player_thief else police
	camera.global_position = target.global_position

func generate_initial_map():
	# Generate area around both cars
	var min_x = min(thief.map_pos.x, police.map_pos.x) - CHUNK_SIZE
	var max_x = max(thief.map_pos.x, police.map_pos.x) + CHUNK_SIZE
	var min_y = min(thief.map_pos.y, police.map_pos.y) - CHUNK_SIZE
	var max_y = max(thief.map_pos.y, police.map_pos.y) + CHUNK_SIZE
	
	for x in range(-3, 4):  # Smaller range
		for y in range(-3, 4):  # Smaller range
			var cell = Vector2(x, y)
			if Map.get_cellv(cell) == -1:
				generate_tile(cell)
	
	# Register chunks for both cars
	var thief_chunk = get_chunk_from_map_pos(thief.map_pos)
	var police_chunk = get_chunk_from_map_pos(police.map_pos)
	
	for x in range(-2, 3):
		for y in range(-2, 3):
			# Register chunks around thief
			var chunk_pos_thief = Vector2(thief_chunk.x + x, thief_chunk.y + y)
			chunk_registry[chunk_pos_thief] = true
			if not chunk_pos_thief in active_chunks:
				active_chunks.append(chunk_pos_thief)
				
			# Register chunks around police
			var chunk_pos_police = Vector2(police_chunk.x + x, police_chunk.y + y)
			chunk_registry[chunk_pos_police] = true
			if not chunk_pos_police in active_chunks:
				active_chunks.append(chunk_pos_police)

func get_chunk_from_map_pos(map_pos):
	var chunk_x = floor(map_pos.x / CHUNK_SIZE)
	var chunk_y = floor(map_pos.y / CHUNK_SIZE)
	return Vector2(chunk_x, chunk_y)

# Add this to your main game script

# Create a NavigationPolygonInstance from tile data
func create_navigation_polygon(chunk_pos):
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	
	var nav_poly_instance = NavigationPolygonInstance.new()
	var nav_poly = NavigationPolygon.new()
	
	var tile_size = 64
	var chunk_boundary = PoolVector2Array([
		Vector2(start_x * tile_size, start_y * tile_size),
		Vector2((start_x + CHUNK_SIZE) * tile_size, start_y * tile_size),
		Vector2((start_x + CHUNK_SIZE) * tile_size, (start_y + CHUNK_SIZE) * tile_size),
		Vector2(start_x * tile_size, (start_y + CHUNK_SIZE) * tile_size)
	])
	nav_poly.add_outline(chunk_boundary)
	
	for x in range(start_x, start_x + CHUNK_SIZE):
		for y in range(start_y, start_y + CHUNK_SIZE):
			var cell_pos = Vector2(x, y)
			var cell_value = Map.get_cellv(cell_pos)
			if cell_value != -1:
				add_wall_obstacles(nav_poly, cell_pos, cell_value)
	
	nav_poly.make_polygons_from_outlines()
	nav_poly_instance.navpoly = nav_poly
	navigation.add_child(nav_poly_instance)
	
	return nav_poly_instance

func add_wall_obstacles(nav_poly, cell_pos, cell_value):
	var cell_size = 64
	var x = cell_pos.x * cell_size
	var y = cell_pos.y * cell_size
	
	if cell_value & N:
		var wall = PoolVector2Array([
			Vector2(x, y),
			Vector2(x + cell_size, y),
			Vector2(x + cell_size, y + 5),
			Vector2(x, y + 5)
		])
		nav_poly.add_outline(wall)
	
	if cell_value & E:
		var wall = PoolVector2Array([
			Vector2(x + cell_size - 5, y),
			Vector2(x + cell_size, y),
			Vector2(x + cell_size, y + cell_size),
			Vector2(x + cell_size - 5, y + cell_size)
		])
		nav_poly.add_outline(wall)
	
	if cell_value & S:
		var wall = PoolVector2Array([
			Vector2(x, y + cell_size - 5),
			Vector2(x + cell_size, y + cell_size - 5),
			Vector2(x + cell_size, y + cell_size),
			Vector2(x, y + cell_size)
		])
		nav_poly.add_outline(wall)
	
	if cell_value & W:
		var wall = PoolVector2Array([
			Vector2(x, y),
			Vector2(x + 5, y),
			Vector2(x + 5, y + cell_size),
			Vector2(x, y + cell_size)
		])
		nav_poly.add_outline(wall)

func check_and_generate_chunks():
	var thief_chunk = get_chunk_from_map_pos(thief.map_pos)
	var police_chunk = get_chunk_from_map_pos(police.map_pos)
	
	# Register current positions with region manager
	region_manager.register_chunk(thief_chunk)
	region_manager.register_chunk(police_chunk)
	
	# Get all chunks that should be active based on regions
	var chunks_to_process = region_manager.get_active_chunks([thief_chunk, police_chunk], GENERATION_DISTANCE)
	
	for chunk_pos in chunks_to_process:
		if not chunk_registry.has(chunk_pos):
			generate_chunk(chunk_pos)
			chunk_registry[chunk_pos] = true
			active_chunks.append(chunk_pos)

# Also update the cleanup function to consider both cars' positions
func cleanup_old_chunks():
	# Get current positions for both cars
	var thief_chunk = get_chunk_from_map_pos(thief.map_pos)
	var police_chunk = get_chunk_from_map_pos(police.map_pos)
	
	# Check each active chunk and remove those too far away from BOTH cars
	var chunks_to_remove = []
	
	for chunk in active_chunks:
		var distance_to_thief = (chunk - thief_chunk).length()
		var distance_to_police = (chunk - police_chunk).length()
		
		# Only remove if the chunk is far from both cars
		if distance_to_thief > VISIBLE_CHUNKS and distance_to_police > VISIBLE_CHUNKS:
			chunks_to_remove.append(chunk)
	
	for chunk in chunks_to_remove:
		# Remove the chunk's tiles from the tilemap
		clear_chunk(chunk)
		# Remove from active chunks list
		active_chunks.erase(chunk)

# Modify your generate_chunk function
func generate_chunk(chunk_pos):
	# Generate tiles for the chunk
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	
	for x in range(start_x, start_x + CHUNK_SIZE):
		for y in range(start_y, start_y + CHUNK_SIZE):
			var cell = Vector2(x, y)
			if Map.get_cellv(cell) == -1:
				generate_tile(cell)
	
	# Add some random obstacles or special tiles
	add_chunk_features(chunk_pos)
	
	# Create navigation for this chunk
	create_navigation_polygon(chunk_pos)

func add_chunk_features(chunk_pos):
	# Add special features like obstacles, speed boosts, or score items
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	
	# Add 1-3 special features per chunk
	var num_features = randi() % 3 + 1
	
	for i in range(num_features):
		var feature_x = start_x + randi() % CHUNK_SIZE
		var feature_y = start_y + randi() % CHUNK_SIZE
		var feature_pos = Vector2(feature_x, feature_y)
		
		# Randomly select feature type
		var feature_type = randi() % 3
		
		match feature_type:
			0: # Score coin
				place_collectible(feature_pos, "coin")
			1: # Speed boost
				place_collectible(feature_pos, "boost")
			2: # Time extension
				place_collectible(feature_pos, "time")

func place_collectible(pos, type):
	# This would be implemented to spawn collectible objects at the given position
	# You'd need to create separate scenes for these collectibles
	match type:
		"coin":
			var coin = preload("res://Collectibles/Coin.tscn").instance()
			coin.position = Map.map_to_world(pos) + Vector2(0, 20)
			coin.map_pos = pos
			add_child(coin)
		"boost":
			var boost = preload("res://Collectibles/SpeedBoost.tscn").instance()
			boost.position = Map.map_to_world(pos) + Vector2(0, 20)
			boost.map_pos = pos
			add_child(boost)
		"time":
			var time_ext = preload("res://Collectibles/TimeExtension.tscn").instance()
			time_ext.position = Map.map_to_world(pos) + Vector2(0, 20)
			time_ext.map_pos = pos
			add_child(time_ext)



func clear_chunk(chunk_pos):
	# Clear all tiles in this chunk
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	
	for x in range(start_x, start_x + CHUNK_SIZE):
		for y in range(start_y, start_y + CHUNK_SIZE):
			Map.set_cellv(Vector2(x, y), -1)
	
	# Also remove any collectibles in this chunk
	for child in navigation.get_children():
		if child is NavigationPolygonInstance:
			var poly_pos = child.position
			var poly_chunk = get_chunk_from_map_pos(Vector2(poly_pos.x / 64, poly_pos.y / 64))
			
			if poly_chunk == chunk_pos:
				child.queue_free()

func generate_tile(cell, depth = 0):
	if depth > 10:  # Limit recursion depth
		return
	# Enhanced tile generation for more interesting roads
	var cells = find_valid_tiles(cell)
	
	if cells.empty():
		# If no valid tiles found, create a default configuration
		Map.set_cellv(cell, randi() % 16)
	else:
		# Weight the selection toward more open paths
		var weighted_cells = []
		for c in cells:
			# Count bits set to determine how open the tile is
			var openness = count_open_directions(c)
			# Add the cell multiple times based on openness
			for i in range(openness):
				weighted_cells.append(c)
		
		# If we have weighted cells, pick one randomly
		if not weighted_cells.empty():
			Map.set_cellv(cell, weighted_cells[randi() % weighted_cells.size()])
		else:
			# Fallback to original logic
			Map.set_cellv(cell, cells[randi() % cells.size()])

func count_open_directions(tile_id):
	var count = 0
	if not (tile_id & N): count += 1
	if not (tile_id & E): count += 1
	if not (tile_id & S): count += 1
	if not (tile_id & W): count += 1
	return count

func find_valid_tiles(cell):
	var valid_tiles = []
	for i in range(16):
		var is_match = false
		for n in cell_walls.keys():
			var neighbor_id = Map.get_cellv(cell + n)
			if neighbor_id >= 0:
				if (neighbor_id & cell_walls[-n])/cell_walls[-n] == (i & cell_walls[n])/cell_walls[n]:
					is_match = true
				else:
					is_match = false
					break
		if is_match and not i in valid_tiles:
			valid_tiles.append(i)
	return valid_tiles

func switch_roles():
	is_player_thief = !is_player_thief
	
	# Play switch sound effect
	switch_sound.play()
	
	# Visual effect to indicate the switch
	$SwitchEffect.global_position = camera.global_position
	$SwitchEffect.emitting = true
	
	# Swap sprites or properties
	var temp_sprite = thief.get_node("AnimatedSprite").animation
	thief.get_node("AnimatedSprite").animation = police.get_node("AnimatedSprite").animation
	police.get_node("AnimatedSprite").animation = temp_sprite
	
# Reset AI timers when roles switch
	if is_player_thief:
		police.chase_timer = 0  # Reset police AI timer when switching to thief
	else:
		thief.chase_timer = 0  # Reset thief AI timer when switching to police
	
	# Adjust AI difficulty based on chase time
	if chase_time > 60:  # After 1 minute, make AI more aggressive
		police.speed = 1.0  # Same speed as player
	
	# Update UI to show current role
	UI.update_role(is_player_thief)

func collect_coin(value):
	score += value
	score_sound.play()
	UI.update_score(score)

func apply_speed_boost(character, boost_amount, duration):
	character.apply_speed_boost(boost_amount, duration)

func extend_role_time(seconds):
	role_switch_timer -= seconds
	if role_switch_timer < 0:
		role_switch_timer = 0
