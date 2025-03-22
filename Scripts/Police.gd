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
var base_speed = 0.85  # Slightly slower than thief by default
var speed = 0.85
var moving = false
var chase_timer = 0.0
var frustration = 0.0  # Increases when police can't catch thief
var ai_path = []  # For smarter pathing
var difficulty_scaling = 1.0  # Increases over time
var drift_factor = 0.15  # How much the car drifts when turning
var boost_active = false
var boost_timer = 0
var trail_effect = null

# Add special ability - police can see through walls temporarily
var special_cooldown = 0
var special_active = false
var SPECIAL_MAX_COOLDOWN = 15.0

signal collected_item(item_type, value)

func _ready():
	# Set up trail effect
	trail_effect = $TrailEffect
	trail_effect.emitting = false
	
	# Initialize the animated sprite
	$AnimatedSprite.play("s")
	
	# Set up the siren light
	$SirenLight.visible = true

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
	
	# Pulse siren light
	$SirenLight.modulate.a = 0.5 + abs(sin(OS.get_ticks_msec() * 0.005)) * 0.5
	
	# Player control vs AI control
	if not get_parent().is_player_thief and not moving:  # Player mode
		handle_player_input()
	elif get_parent().is_player_thief and not moving:  # AI mode
		run_police_ai(delta)

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

func run_police_ai(delta):
	chase_timer += delta
	
	# Increase difficulty over time
	difficulty_scaling = min(1.5, 1.0 + get_parent().chase_time / 120.0)
	
	# More aggressive movement if thief has been elusive for too long
	if frustration > 20:
		if chase_timer >= 0.7 / difficulty_scaling:  # Faster decisions when frustrated
			chase_timer = 0.0
			chase_thief_advanced()
			frustration = max(0, frustration - 5)  # Reduce frustration when taking action
	else:
		if chase_timer >= 1.0 / difficulty_scaling:  # Standard AI move rate
			chase_timer = 0.0
			chase_thief_advanced()
	
	# Use special ability more aggressively at higher difficulties
	if special_cooldown <= 0 and difficulty_scaling >= 1.3 and get_distance_to_thief() > 5:
		activate_special()

func get_distance_to_thief():
	var thief_pos = get_parent().thief.map_pos
	return (thief_pos - map_pos).length()

func chase_thief_advanced():
	var thief_pos = get_parent().thief.map_pos
	
	# If thief is invisible, use last known position or patrol
	if get_parent().thief.special_active:
		patrol_random()
		return
	
	# Check if we need to calculate a new path
	if ai_path.empty() or rand_range(0, 1) < 0.2:  # 20% chance to recalculate path for unpredictability
		ai_path = find_path_to_thief(thief_pos)
	
	# If we have a path, follow it
	if not ai_path.empty():
		var next_step = ai_path[0]
		var dir_to_move = null
		
		# Convert next position to direction
		for dir in moves.keys():
			if map_pos + moves[dir] == next_step:
				dir_to_move = dir
				break
		
		if dir_to_move != null and can_move(dir_to_move):
			move(dir_to_move)
			ai_path.pop_front()
			frustration = max(0, frustration - 1)
		else:
			# Path is blocked, recalculate
			ai_path.clear()
			frustration += 1
	else:
		# Fallback to simple chase if no path found
		simple_chase(thief_pos)
		frustration += 2

func simple_chase(thief_pos):
	var dx = thief_pos.x - map_pos.x
	var dy = thief_pos.y - map_pos.y
	
	# Try to move directly toward thief
	var tried_directions = []
	
	# Try horizontal or vertical movement based on which distance is greater
	if abs(dx) > abs(dy):
		if dx > 0 and can_move(E):
			move(E)
		elif dx < 0 and can_move(W):
			move(W)
		elif dy > 0 and can_move(S):
			move(S)
		elif dy < 0 and can_move(N):
			move(N)
		else:
			# Try any available direction
			for dir in [N, E, S, W]:
				if can_move(dir) and not dir in tried_directions:
					move(dir)
					break
				tried_directions.append(dir)
	else:
		if dy > 0 and can_move(S):
			move(S)
		elif dy < 0 and can_move(N):
			move(N)
		elif dx > 0 and can_move(E):
			move(E)
		elif dx < 0 and can_move(W):
			move(W)
		else:
			# Try any available direction
			for dir in [N, E, S, W]:
				if can_move(dir) and not dir in tried_directions:
					move(dir)
					break
				tried_directions.append(dir)

func find_path_to_thief(target_pos):
	# Add a maximum iteration count to prevent infinite loops
	var max_iterations = 100
	var iterations = 0
	
	# A* pathfinding to the thief
	var open_set = [map_pos]
	var came_from = {}
	var g_score = {str(map_pos): 0}
	var f_score = {str(map_pos): heuristic(map_pos, target_pos)}
	
	while not open_set.empty() and iterations < max_iterations:
		iterations += 1
		var current = get_lowest_fscore_node(open_set, f_score)
		
		if current == target_pos:
			return reconstruct_path(came_from, current)
		
		open_set.erase(current)
		
		for dir in moves.keys():
			if can_move(dir):
				var neighbor = current + moves[dir]
				var tentative_g = g_score[str(current)] + 1
				
				if not g_score.has(str(neighbor)) or tentative_g < g_score[str(neighbor)]:
					came_from[str(neighbor)] = current
					g_score[str(neighbor)] = tentative_g
					f_score[str(neighbor)] = tentative_g + heuristic(neighbor, target_pos)
					
					if not neighbor in open_set:
						open_set.append(neighbor)
	
	# No path found or max iterations reached, return empty path
	return []

func get_lowest_fscore_node(nodes, f_scores):
	var lowest_node = nodes[0]
	var lowest_score = f_scores[str(lowest_node)]
	
	for node in nodes:
		var score = f_scores[str(node)]
		if score < lowest_score:
			lowest_node = node
			lowest_score = score
	
	return lowest_node

func heuristic(a, b):
	return abs(a.x - b.x) + abs(a.y - b.y)

func reconstruct_path(came_from, current):
	var path = [current]
	
	while came_from.has(str(current)):
		current = came_from[str(current)]
		path.push_front(current)
	
	# Remove the starting position
	if not path.empty():
		path.pop_front()
	
	return path

func patrol_random():
	# When thief is invisible, move randomly
	var available_dirs = []
	
	for dir in [N, E, S, W]:
		if can_move(dir):
			available_dirs.append(dir)
	
	if not available_dirs.empty():
		var random_dir = available_dirs[randi() % available_dirs.size()]
		move(random_dir)

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
	
	# Modified: Special ability should not allow passing through walls
	# The x-ray vision is just for seeing, not for moving through walls
	
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

func apply_speed_boost(boost_amount, duration):
	boost_active = true
	boost_timer = duration
	speed = base_speed + boost_amount
	# Enable trail effect
	trail_effect.emitting = true
	# Play boost sound
	$BoostSound.play()

func activate_special():
	# Police can temporarily see through walls
	special_active = true
	special_cooldown = SPECIAL_MAX_COOLDOWN
	
	# Visual effect
	$XRayEffect.emitting = true
	
	# Create a pulse effect on the map to show walls becoming transparent
	var pulse = preload("res://Effects/XRayPulse.tscn").instance()
	pulse.position = position
	get_parent().add_child(pulse)
	
	# Special ability duration
	$SpecialTimer.start(5.0)  # 5 seconds of x-ray vision
	
	# Play special ability sound
	$SpecialSound.play()

func _on_SpecialTimer_timeout():
	special_active = false
	$XRayEffect.emitting = false
