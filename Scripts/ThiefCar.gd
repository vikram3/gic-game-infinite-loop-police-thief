extends Area2D

const N = 0x1
const E = 0x2
const S = 0x4
const W = 0x8

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
	if not map:
			map = get_parent().get_node("TileMap")
			if not map:
				push_error("ThiefCar: Could not find TileMap in parent node!")
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
	elif not get_parent().is_player_thief and not moving:
		run_away_from_player(delta)

# Add this new function
# For the ThiefCar, add a function to occasionally do something unexpected
func act_unpredictably():
	# 20% chance to do something unpredictable
	if randf() < 0.2:
		# Choose a random action
		var action = randi() % 3
		match action:
			0:  # Sprint straight away
				var dir = null
				if can_move(N): dir = N
				elif can_move(E): dir = E
				elif can_move(S): dir = S
				elif can_move(W): dir = W
				
				if dir != null:
					move(dir)
					# If can move again in same direction, do it
					if can_move(dir):
						yield(get_tree().create_timer(0.2/speed), "timeout")
						move(dir)
				
			1:  # Use special ability if available
				if special_cooldown <= 0:
					activate_special()
				
			2:  # Make a sharp turn
				var dir_options = []
				for dir in [N, E, S, W]:
					if can_move(dir):
						dir_options.append(dir)
				if not dir_options.empty():
					move(dir_options[randi() % dir_options.size()])
		return true
	return false
	
func run_away_from_player(delta):
	chase_timer += delta
	
	# Only update path periodically to avoid constant recalculation
	if chase_timer >= 1.0:
		chase_timer = 0.0
		
		var police_pos = get_parent().police.map_pos
		var police_world_pos = get_parent().map.map_to_world(police_pos) + Vector2(0, 20)
		var my_world_pos = position
		
		# Find escape points in different directions
		var escape_points = []
		var max_distance = 5  # How far to look for escape points
		
		# Try to find escape points in all four directions
		for dir in [N, E, S, W]:
			var test_pos = map_pos + (moves[dir] * max_distance)
			var test_world_pos = get_parent().map.map_to_world(test_pos) + Vector2(0, 20)
			
			# Calculate distance from police to this point
			var dist_to_police = (test_world_pos - police_world_pos).length()
			
			# Check if this point is reachable
			var path = get_parent().navigation.get_simple_path(my_world_pos, test_world_pos, true)
			
			if path.size() > 1 and dist_to_police > 200:  # Minimum safe distance
				escape_points.append({
					"pos": test_pos,
					"dist": dist_to_police,
					"path": path
				})
		
		# If we have escape points, choose the one furthest from police
		if not escape_points.empty():
			escape_points.sort_custom(self, "_sort_by_distance")
			var best_escape = escape_points[0]
			
			# Get next point in the path
			var next_point = best_escape.path[1]
			var next_map_pos = get_parent().map.world_to_map(next_point - Vector2(0, 20))
			
			# Determine direction to move
			for dir in moves.keys():
				if map_pos + moves[dir] == next_map_pos:
					move(dir)
					return
		
		# Fallback to simple avoidance if no good escape found
		simple_avoid(police_pos)
	
# Helper function to sort escape points
func _sort_by_distance(a, b):
	return a.dist > b.dist  # Sort from furthest to closest

# Simple avoidance logic if navigation fails
func simple_avoid(police_pos):
	# Your existing avoidance code...
	# This is the current run_away_from_player logic
	var direction = map_pos - police_pos
	var dir = null
	
	# Horizontal or vertical movement based on which distance is greater
	if abs(direction.x) > abs(direction.y):
		# Move horizontally
		if direction.x > 0 and can_move(E):
			dir = E  # Move right if police is to the left
		elif direction.x < 0 and can_move(W):
			dir = W  # Move left if police is to the right
	else:
		# Move vertically
		if direction.y > 0 and can_move(S):
			dir = S  # Move down if police is above
		elif direction.y < 0 and can_move(N):
			dir = N  # Move up if police is below
	
	# If preferred direction is blocked, try the other axis
	if dir == null or not can_move(dir):
		if abs(direction.x) <= abs(direction.y):
			# Try horizontal
			if direction.x > 0 and can_move(E):
				dir = E
			elif direction.x < 0 and can_move(W):
				dir = W
		else:
			# Try vertical
			if direction.y > 0 and can_move(S):
				dir = S
			elif direction.y < 0 and can_move(N):
				dir = N
	
	# If still blocked, try any available direction
	if dir == null or not can_move(dir):
		for test_dir in [N, E, S, W]:
			if can_move(test_dir):
				dir = test_dir
				break
	
	# Move in chosen direction
	if dir != null:
		move(dir)

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

func _on_ThiefCar_area_entered(area):
	if area == get_parent().police and not special_active:
		get_parent().switch_roles()
		# Play catch sound
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
