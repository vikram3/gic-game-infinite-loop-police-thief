extends Area2D

const N = 0x1
const E = 0x2
const S = 0x4
const W = 0x8

var previous_positions = []  # Add this as a class variable
const MAX_MEMORY = 5  # Remember the last 5 positions

var animations = {N: 'n', S: 's', E: 'e', W: 'w'}
var moves = {
	N: Vector2(0, -1),
	S: Vector2(0, 1),
	E: Vector2(1, 0),
	W: Vector2(-1, 0)
}

var map = null
var map_pos = Vector2()
var base_speed = 0.5
var speed = 0.5
var moving = false
var drift_factor = 0.2  # How much the car drifts when turning
var boost_active = false
var boost_timer = 0
var trail_effect = null
var chase_timer = 0

# Add special ability - thief can temporarily go invisible
var special_cooldown = 0
var special_active = false
var SPECIAL_MAX_COOLDOWN = 10.0

signal collected_item(item_type, value)

func _ready():
	# Set up trail effect
	trail_effect = $TrailEffect
	trail_effect.emitting = false
	
	if not is_connected("area_entered", self, "_on_ThiefCar_area_entered"):
		connect("area_entered", self, "_on_ThiefCar_area_entered")
	# Initialize the animated sprite
	$AnimatedSprite.play("s")

func _process(delta):
	# Handle special ability cooldown
	if special_cooldown > 0:
		special_cooldown -= delta
	
	# Handle speed boost timer
	if boost_active:
		boost_timer -= delta
		trail_effect.emitting = true
		if boost_timer <= 0:
			boost_active = false
			speed = base_speed
			trail_effect.emitting = false
	
	# Input handling for player-controlled mode
	if get_parent().is_player_thief and not moving:
		handle_player_input()
	# AI for computer-controlled mode
	elif not get_parent().is_player_thief:
		# Update chase timer regardless of movement status
		chase_timer += delta
		
		# Only attempt to move if not already moving
		if not moving and chase_timer >= 0.5:  # Make decision every 0.5 seconds
			chase_timer = 0
			run_away_from_player(delta)

func run_away_from_player(delta):
	# More sophisticated AI to run away from the police
	var police_pos = get_parent().police.map_pos
	var distance = (police_pos - map_pos).length()
	
	# Calculate vector from police to thief
	var direction = map_pos - police_pos
	
	# Try special ability if available and police is close
	if special_cooldown <= 0 and distance < 3:
		activate_special()
	
	# Array of possible directions in order of preference
	var possible_dirs = []
	
	# Prioritize directions that increase distance from police
	if direction.x > 0 and can_move(E):
		possible_dirs.append(E)
	elif direction.x < 0 and can_move(W):
		possible_dirs.append(W)
		
	if direction.y > 0 and can_move(S):
		possible_dirs.append(S)
	elif direction.y < 0 and can_move(N):
		possible_dirs.append(N)
	
	# Add secondary directions (perpendicular to escape vector)
	if abs(direction.x) > abs(direction.y):
		# Horizontal escape is primary, add vertical options as secondary
		if can_move(N) and not N in possible_dirs:
			possible_dirs.append(N)
		if can_move(S) and not S in possible_dirs:
			possible_dirs.append(S)
	else:
		# Vertical escape is primary, add horizontal options as secondary
		if can_move(E) and not E in possible_dirs:
			possible_dirs.append(E)
		if can_move(W) and not W in possible_dirs:
			possible_dirs.append(W)
	
	# Even add opposite directions as last resort
	for test_dir in [N, E, S, W]:
		if can_move(test_dir) and not test_dir in possible_dirs:
			possible_dirs.append(test_dir)
	
	# Move in the first available direction
	if not possible_dirs.empty():
		move(possible_dirs[0])
	# If no direction is available (shouldn't happen), just wait

func escape_from_police(police_pos):
	# Calculate vector from police to thief
	var direction = map_pos - police_pos
	
	# Get all possible moves
	var possible_moves = []
	var move_scores = {}
	
	for dir in [N, E, S, W]:
		if can_move(dir):
			var new_pos = map_pos + moves[dir]
			
			# Skip if we've been here recently (avoid loops)
			if new_pos in previous_positions:
				continue
				
			# Calculate new distance from police after this move
			var new_distance = (police_pos - new_pos).length()
			
			# Score this move (higher is better)
			var score = new_distance  # Base score is distance from police
			
			# Prefer moves that are in the general direction away from police
			var dot_product = direction.normalized().dot(moves[dir].normalized())
			score += dot_product * 2
			
			# Add some randomness to break patterns
			score += randf() * 0.5
			
			possible_moves.append(dir)
			move_scores[dir] = score
	
	# If we have moves available
	if not possible_moves.empty():
		# Find the move with the highest score
		var best_dir = possible_moves[0]
		var best_score = move_scores[best_dir]
		
		for dir in possible_moves:
			if move_scores[dir] > best_score:
				best_score = move_scores[dir]
				best_dir = dir
		
		# Move in the chosen direction
		move(best_dir)
		
		# Remember this position to avoid loops
		previous_positions.append(map_pos)
		if previous_positions.size() > MAX_MEMORY:
			previous_positions.pop_front()
	else:
		# All directions blocked or would cause a loop
		# Just move somewhere if possible, even if we've been there
		for dir in [N, E, S, W]:
			if can_move(dir):
				move(dir)
				break

func explore_and_collect():
	# Look for collectibles
	var nearby_collectible = find_nearest_collectible()
	
	if nearby_collectible:
		# Move toward the collectible
		move_toward_position(nearby_collectible.map_pos)
	else:
		# No collectibles nearby, just explore
		explore_random()

func find_nearest_collectible():
	var nearest = null
	var min_distance = 999
	
	for collectible in get_parent().get_children():
		if collectible.has_method("collect"):
			var distance = (collectible.map_pos - map_pos).length()
			if distance < min_distance and distance < 8:  # Only consider nearby collectibles
				min_distance = distance
				nearest = collectible
	
	return nearest

func move_toward_position(target_pos):
	var direction = target_pos - map_pos
	var possible_dirs = []
	
	# Determine which direction gets us closer
	if abs(direction.x) > abs(direction.y):
		# Try horizontal first
		if direction.x > 0 and can_move(E): possible_dirs.append(E)
		elif direction.x < 0 and can_move(W): possible_dirs.append(W)
		
		# Then vertical
		if direction.y > 0 and can_move(S): possible_dirs.append(S)
		elif direction.y < 0 and can_move(N): possible_dirs.append(N)
	else:
		# Try vertical first
		if direction.y > 0 and can_move(S): possible_dirs.append(S)
		elif direction.y < 0 and can_move(N): possible_dirs.append(N)
		
		# Then horizontal
		if direction.x > 0 and can_move(E): possible_dirs.append(E)
		elif direction.x < 0 and can_move(W): possible_dirs.append(W)
	
	# Try remaining directions if needed
	for dir in [N, E, S, W]:
		if can_move(dir) and not dir in possible_dirs:
			possible_dirs.append(dir)
	
	if not possible_dirs.empty():
		# Choose a random direction from our options
		var chosen_dir = possible_dirs[randi() % possible_dirs.size()]
		move(chosen_dir)
		
		# Remember this position
		previous_positions.append(map_pos)
		if previous_positions.size() > MAX_MEMORY:
			previous_positions.pop_front()

func explore_random():
	var available_dirs = []
	
	# Prefer directions we haven't been to recently
	for dir in [N, E, S, W]:
		if can_move(dir):
			var new_pos = map_pos + moves[dir]
			if not new_pos in previous_positions:
				available_dirs.append(dir)
	
	# If all directions have been visited recently, consider any direction
	if available_dirs.empty():
		for dir in [N, E, S, W]:
			if can_move(dir):
				available_dirs.append(dir)
	
	if not available_dirs.empty():
		# Choose a random direction
		var random_dir = available_dirs[randi() % available_dirs.size()]
		move(random_dir)
		
		# Remember this position
		previous_positions.append(map_pos)
		if previous_positions.size() > MAX_MEMORY:
			previous_positions.pop_front()

func handle_player_input():
	var dir = null
	
	if Input.is_action_pressed('ui_up'):
		dir = N
	elif Input.is_action_pressed('ui_down'):
		dir = S
	elif Input.is_action_pressed('ui_right'):
		dir = E
	elif Input.is_action_pressed('ui_left'):
		dir = W
	
	# Special ability activation
	if Input.is_action_just_pressed("special") and special_cooldown <= 0:
		activate_special()
	
	if dir != null:
		move(dir)

func move(dir):
	if not can_move(dir):
		# Try to slide along walls for more fluid movement
		var alt_dirs = get_alternative_directions(dir)
		for alt_dir in alt_dirs:
			if can_move(alt_dir):
				dir = alt_dir
				break
		if not can_move(dir):
			return
	
	moving = true
	$AnimatedSprite.play(animations[dir])
	
	# Save previous position for smooth transitions
	var prev_map_pos = map_pos
	map_pos += moves[dir]
	
	# Generate map if needed
	if map.get_cellv(map_pos) == -1:
		get_parent().generate_tile(map_pos)
	
	# Calculate destination - direct movement without easing
	var destination = map.map_to_world(map_pos) + Vector2(0, 20)
	
	# Move with linear transition for immediate movement
	$Tween.interpolate_property(
		self, 'position', 
		position, 
		destination, 
		0.2/speed,  # Shorter duration for quicker movement
		Tween.TRANS_LINEAR,  # Linear transition instead of quadratic
		Tween.EASE_IN  # Only ease in, no easing out
	)
	$Tween.start()
	
	# Play movement sound
	$MoveSound.play()
	
	# Create tire marks or dust effect
	create_movement_effect(prev_map_pos)

func create_movement_effect(prev_pos):
	# Instance a particle effect at the previous position
	var dust = preload("res://Effects/TireDust.tscn").instance()
	dust.position = map.map_to_world(prev_pos) + Vector2(0, 20)
	dust.emitting = true
	get_parent().add_child(dust)

func get_alternative_directions(dir):
	# Provide alternative directions for sliding along walls
	match dir:
		N, S: return [E, W]
		E, W: return [N, S]
	return []

func can_move(dir):
	var t = map.get_cellv(map_pos)
	if t & dir:
		return false
	return true

func _on_Tween_tween_completed(object, key):
	moving = false
	
	# Check if we've reached a collectible
	check_for_collectibles()

func check_for_collectibles():
	# Find any collectibles at current position
	for collectible in get_parent().get_children():
		if collectible.has_method("collect") and collectible.map_pos == map_pos:
			var item_data = collectible.collect()
			emit_signal("collected_item", item_data.type, item_data.value)
			get_parent().collect_coin(item_data.value) if item_data.type == "coin" else null
			
			if item_data.type == "boost":
				apply_speed_boost(item_data.value, 3.0)
			elif item_data.type == "time":
				get_parent().extend_role_time(item_data.value)

# Modify the _on_ThiefCar_area_entered function
func _on_ThiefCar_area_entered(area):
	print("ThiefCar entered by: ", area.name)  # Debug line
	if area == get_parent().police and not special_active:
		print("Caught by police!")  # Debug line
		get_parent().on_thief_caught()
		$CaughtSound.play()

func apply_speed_boost(boost_amount, duration):
	boost_active = true
	boost_timer = duration
	speed = base_speed + boost_amount
	# Enable trail effect
	trail_effect.emitting = true
	# Play boost sound
	$BoostSound.play()

func activate_special():
	# Thief can temporarily become invisible to the police
	special_active = true
	special_cooldown = SPECIAL_MAX_COOLDOWN
	
	# Visual effect
	$InvisibilityEffect.emitting = true
	modulate.a = 0.5  # Make partially transparent
	
	# Special ability duration
	$SpecialTimer.start(3.0)  # 3 seconds of invisibility
	
	# Play special ability sound
	$SpecialSound.play()

func _on_SpecialTimer_timeout():
	special_active = false
	$InvisibilityEffect.emitting = false
	modulate.a = 1.0  # Return to normal visibility
