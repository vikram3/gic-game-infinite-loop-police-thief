extends Node2D

const N = 0x1
const E = 0x2
const S = 0x4
const W = 0x8

const CHUNK_SIZE = 4
const VISIBLE_CHUNKS = 4
const GENERATION_DISTANCE = 3

var cell_walls = {
	Vector2(0, -1): N, 
	Vector2(1, 0): E,
	Vector2(0, 1): S, 
	Vector2(-1, 0): W
}

var chunk_registry = {}
var active_chunks = []

var is_player_thief = true
var score = 0
var chase_time = 0
var role_switch_timer = 0
var MAX_ROLE_TIME = 30.0

onready var Map = $TileMap
onready var thief = $ThiefCar
onready var police = $PoliceCar
onready var camera = $Camera2D
onready var UI = $UILayer/UI

onready var switch_sound = $SwitchRoleSound
onready var chase_sound = $ChaseSound
onready var score_sound = $ScoreSound

func _ready():
	var minimap_layer = CanvasLayer.new()
	minimap_layer.name = "MinimapLayer"
	add_child(minimap_layer)
	
	var minimap_scene = preload("res://Scenes/Minimap.tscn").instance()
	minimap_scene.name = "Minimap"
	minimap_scene.position = Vector2(20, 20)
	minimap_layer.add_child(minimap_scene)
	
	print("Game starting...")
	randomize()
	is_player_thief = true
	$UILayer/UI.max_role_time = MAX_ROLE_TIME
	
	thief.map = Map
	police.map = Map
	
	thief.map_pos = Vector2(0, 0)
	police.map_pos = Vector2(2, 2)
	
	thief.position = Map.map_to_world(thief.map_pos) + Vector2(0, 20)
	police.position = Map.map_to_world(police.map_pos) + Vector2(0, 20)
	
	for x in range(-2, 3):
		for y in range(-2, 3):
			var cell = Vector2(x, y)
			generate_tile(cell)
	
	var chunk_pos = Vector2(0, 0)
	chunk_registry[chunk_pos] = true
	active_chunks.append(chunk_pos)
	
	update_camera()
	$BackgroundMusic.play()
	print("Initialization complete")

func _process(delta):
	UI.update_score(score)
	
	chase_time += delta
	
	check_and_generate_chunks()
	
	cleanup_old_chunks()
	
	update_camera()
	
	if is_player_thief:
		role_switch_timer += delta
		UI.update_timer(MAX_ROLE_TIME - role_switch_timer)
		if role_switch_timer >= MAX_ROLE_TIME:
			switch_roles()
			role_switch_timer = 0
	else:
		UI.update_timer(MAX_ROLE_TIME)
		
func update_camera():
	var target = thief if is_player_thief else police
	camera.global_position = target.global_position

func generate_initial_map():
	var min_x = min(thief.map_pos.x, police.map_pos.x) - CHUNK_SIZE
	var max_x = max(thief.map_pos.x, police.map_pos.x) + CHUNK_SIZE
	var min_y = min(thief.map_pos.y, police.map_pos.y) - CHUNK_SIZE
	var max_y = max(thief.map_pos.y, police.map_pos.y) + CHUNK_SIZE
	
	for x in range(-3, 4):
		for y in range(-3, 4):
			var cell = Vector2(x, y)
			if Map.get_cellv(cell) == -1:
				generate_tile(cell)
	
	var thief_chunk = get_chunk_from_map_pos(thief.map_pos)
	var police_chunk = get_chunk_from_map_pos(police.map_pos)
	
	for x in range(-2, 3):
		for y in range(-2, 3):
			var chunk_pos_thief = Vector2(thief_chunk.x + x, thief_chunk.y + y)
			chunk_registry[chunk_pos_thief] = true
			if not chunk_pos_thief in active_chunks:
				active_chunks.append(chunk_pos_thief)
				
			var chunk_pos_police = Vector2(police_chunk.x + x, police_chunk.y + y)
			chunk_registry[chunk_pos_police] = true
			if not chunk_pos_police in active_chunks:
				active_chunks.append(chunk_pos_police)

func get_chunk_from_map_pos(map_pos):
	var chunk_x = floor(map_pos.x / CHUNK_SIZE)
	var chunk_y = floor(map_pos.y / CHUNK_SIZE)
	return Vector2(chunk_x, chunk_y)

func check_and_generate_chunks():
	var thief_chunk = get_chunk_from_map_pos(thief.map_pos)
	var police_chunk = get_chunk_from_map_pos(police.map_pos)
	
	for x in range(-GENERATION_DISTANCE, GENERATION_DISTANCE + 1):
		for y in range(-GENERATION_DISTANCE, GENERATION_DISTANCE + 1):
			var check_chunk = Vector2(thief_chunk.x + x, thief_chunk.y + y)
			
			if not chunk_registry.has(check_chunk):
				generate_chunk(check_chunk)
				chunk_registry[check_chunk] = true
				active_chunks.append(check_chunk)
	
	for x in range(-GENERATION_DISTANCE, GENERATION_DISTANCE + 1):
		for y in range(-GENERATION_DISTANCE, GENERATION_DISTANCE + 1):
			var check_chunk = Vector2(police_chunk.x + x, police_chunk.y + y)
			
			if not chunk_registry.has(check_chunk):
				generate_chunk(check_chunk)
				chunk_registry[check_chunk] = true
				active_chunks.append(check_chunk)

func cleanup_old_chunks():
	var thief_chunk = get_chunk_from_map_pos(thief.map_pos)
	var police_chunk = get_chunk_from_map_pos(police.map_pos)
	
	var chunks_to_remove = []
	
	for chunk in active_chunks:
		var distance_to_thief = (chunk - thief_chunk).length()
		var distance_to_police = (chunk - police_chunk).length()
		
		if distance_to_thief > VISIBLE_CHUNKS and distance_to_police > VISIBLE_CHUNKS:
			chunks_to_remove.append(chunk)
	
	for chunk in chunks_to_remove:
		clear_chunk(chunk)
		active_chunks.erase(chunk)

func generate_chunk(chunk_pos):
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	
	for x in range(start_x, start_x + CHUNK_SIZE):
		for y in range(start_y, start_y + CHUNK_SIZE):
			var cell = Vector2(x, y)
			if Map.get_cellv(cell) == -1:
				generate_tile(cell)
	
	add_chunk_features(chunk_pos)

func add_chunk_features(chunk_pos):
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	
	var num_features = randi() % 3 + 1
	
	for i in range(num_features):
		var feature_x = start_x + randi() % CHUNK_SIZE
		var feature_y = start_y + randi() % CHUNK_SIZE
		var feature_pos = Vector2(feature_x, feature_y)
		
		var feature_type = randi() % 3
		
		match feature_type:
			0:
				place_collectible(feature_pos, "coin")
			1:
				place_collectible(feature_pos, "boost")
			2:
				place_collectible(feature_pos, "time")

func place_collectible(pos, type):
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
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	
	for x in range(start_x, start_x + CHUNK_SIZE):
		for y in range(start_y, start_y + CHUNK_SIZE):
			Map.set_cellv(Vector2(x, y), -1)
	
	for child in get_children():
		if child.has_method("get_map_pos"):
			var collectible_chunk = get_chunk_from_map_pos(child.map_pos)
			if collectible_chunk == chunk_pos:
				child.queue_free()

func generate_tile(cell, depth = 0):
	if depth > 10:
		return
	var cells = find_valid_tiles(cell)
	
	if cells.empty():
		Map.set_cellv(cell, randi() % 16)
	else:
		var weighted_cells = []
		for c in cells:
			var openness = count_open_directions(c)
			for i in range(openness):
				weighted_cells.append(c)
		
		if not weighted_cells.empty():
			Map.set_cellv(cell, weighted_cells[randi() % weighted_cells.size()])
		else:
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
	
	switch_sound.play()
	
	$SwitchEffect.global_position = camera.global_position
	$SwitchEffect.emitting = true
	
	var temp_sprite = thief.get_node("AnimatedSprite").animation
	thief.get_node("AnimatedSprite").animation = police.get_node("AnimatedSprite").animation
	police.get_node("AnimatedSprite").animation = temp_sprite
	
	thief.switch_role()
	
	if is_player_thief:
		police.chase_timer = 0
		if role_switch_timer > 0:
			$CaptureSound.play()
	else:
		thief.chase_timer = 0
	
	role_switch_timer = 0
	
	if chase_time > 60:
		police.speed = 1.0
	
	UI.update_role(is_player_thief)

func collect_coin(value, collector=null):
	if collector == null:
		score += value
	else:
		if (is_player_thief and collector == police) or (!is_player_thief and collector == thief):
			score -= value
		else:
			score += value
	
	score_sound.play()
	UI.update_score(score)

func apply_speed_boost(character, boost_amount, duration):
	character.apply_speed_boost(boost_amount, duration)

func extend_role_time(seconds):
	role_switch_timer -= seconds
	if role_switch_timer < 0:
		role_switch_timer = 0
		
func on_thief_caught():
	var catch_effect = preload("res://Effects/CatchEffect.tscn").instance()
	catch_effect.position = thief.position
	add_child(catch_effect)
	
	yield(get_tree().create_timer(0.5), "timeout")
	switch_roles()
	
	if !is_player_thief:
		calculate_catch_bonus()
	
func calculate_catch_bonus():
	var time_ratio = 1.0 - (role_switch_timer / MAX_ROLE_TIME)
	var bonus_points = int(100 * time_ratio)
	score += bonus_points
	UI.show_message("Quick Catch Bonus: " + str(bonus_points) + " points!", 2.0)
