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
var base_speed = 0.4  # Slightly slower than thief by default
var speed = 0.4
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
	# Update timer for other AI features, but don't use it to gate movement
	chase_timer += delta
	
	# Increase difficulty over time
	difficulty_scaling = min(1.5, 1.0 + get_parent().chase_time / 120.0)
	
	# Check if we're currently moving
	if not moving:
		# Just initiate movement immediately without waiting for timer thresholds
		chase_thief_advanced()
		
		# Use special ability when appropriate
		if special_cooldown <= 0 and difficulty_scaling >= 1.3 and get_distance_to_thief() > 5:
			activate_special()
			
	# Update frustration level - still used for decision-making
	if get_distance_to_thief() > 8:
		frustration += delta  # Increase frustration gradually
	else:
		frustration = max(0, frustration - delta)  # Decrease when closer

func get_distance_to_thief():
	var thief_pos = get_parent().thief.map_pos
	return (thief_pos - map_pos).length()

func chase_thief_advanced():
	var thief_pos = get_parent().thief.map_pos
	
	# If thief is invisible, use last known position or patrol
	if get_parent().thief.special_active:
		patrol_random()
		return
	
	# Recalculate path less frequently to reduce jitter
	# Only recalculate when we reach a waypoint or don't have a path
	if ai_path.empty() or ai_path.size() <= 1:
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
		frustration += 1
		
func search_in_spiral():
	# This creates a spiral search pattern
	var spiral_directions = [E, S, W, W, N, N, E, E, E, S, S, S, W, W, W, W]
	var spiral_index = int(chase_timer * 2) % spiral_directions.size()
	var search_dir = spiral_directions[spiral_index]
	
	# Try the suggested direction first
	if can_move(search_dir):
		move(search_dir)
	else:
		# Fall back to any available direction
		patrol_random()

func simple_chase(thief_pos):
	var dx = thief_pos.x - map_pos.x
	var dy = thief_pos.y - map_pos.y
	
	# Try primary and secondary directions based on which axis has greater distance
	var primary_dirs = []
	var secondary_dirs = []
	
	if abs(dx) > abs(dy):
		# Prioritize horizontal movement
		primary_dirs = [E if dx > 0 else W]
		secondary_dirs = [S if dy > 0 else N]
	else:
		# Prioritize vertical movement
		primary_dirs = [S if dy > 0 else N]
		secondary_dirs = [E if dx > 0 else W]
	
	# Try opposite directions as fallbacks
	var fallback_dirs = [
		opposite_direction(primary_dirs[0]),
		opposite_direction(secondary_dirs[0])
	]
	
	# Try directions in priority order
	for dir in primary_dirs + secondary_dirs + fallback_dirs:
		if can_move(dir):
			move(dir)
			return
	
	# If all else fails, move in any available direction
	patrol_random()

func find_path_to_thief(target_pos):
	# Increase maximum iterations for more complex paths
	var max_iterations = 200
	var iterations = 0
	
	# A* pathfinding to the thief with improved heuristic
	var open_set = [map_pos]
	var came_from = {}
	var g_score = {str(map_pos): 0}
	var f_score = {str(map_pos): improved_heuristic(map_pos, target_pos)}
	
	while not open_set.empty() and iterations < max_iterations:
		iterations += 1
		var current = get_lowest_fscore_node(open_set, f_score)
		
		# Success: found the target
		if current == target_pos:
			return reconstruct_path(came_from, current)
		
		open_set.erase(current)
		
		# Check all four directions
		for dir in moves.keys():
			# Only consider moves that are actually possible
			if can_move_from_position(current, dir):
				var neighbor = current + moves[dir]
				var tentative_g = g_score[str(current)] + 1
				
				if not g_score.has(str(neighbor)) or tentative_g < g_score[str(neighbor)]:
					came_from[str(neighbor)] = current
					g_score[str(neighbor)] = tentative_g
					f_score[str(neighbor)] = tentative_g + improved_heuristic(neighbor, target_pos)
					
					if not neighbor in open_set:
						open_set.append(neighbor)
	
	# No path found or max iterations reached
	# Return a partial path toward target if available
	if not came_from.empty():
		var furthest_point = find_furthest_point_toward_target(came_from, target_pos)
		return reconstruct_path(came_from, furthest_point)
	
	return []

func can_move_from_position(pos, dir):
	var cell = map.get_cellv(pos)
	# Generate the cell if it doesn't exist yet
	if cell == -1:
		get_parent().generate_tile(pos)
		cell = map.get_cellv(pos)
	
	return not (cell & dir)
	
func get_lowest_fscore_node(nodes, f_scores):
	var lowest_node = nodes[0]
	var lowest_score = f_scores[str(lowest_node)]
	
	for node in nodes:
		var score = f_scores[str(node)]
		if score < lowest_score:
			lowest_node = node
			lowest_score = score
	
	return lowest_node

func improved_heuristic(a, b):
	# Manhattan distance for basic estimation
	var manhattan = abs(a.x - b.x) + abs(a.y - b.y)
	
	# Add a small random factor to break ties and prevent predictable paths
	# This helps the AI explore slightly different paths even when options seem equal
	var random_factor = randf() * 0.2
	
	return manhattan + random_factor
	
func find_furthest_point_toward_target(came_from, target_pos):
	var best_distance = INF
	var best_point = null
	
	for point_str in came_from.keys():
		var point_parts = point_str.substr(1, point_str.length() - 2).split(", ")
		var point = Vector2(float(point_parts[0]), float(point_parts[1]))
		
		var distance = (point - target_pos).length()
		if distance < best_distance:
			best_distance = distance
			best_point = point
	
	return best_point if best_point != null else map_pos

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
func opposite_direction(dir):
	match dir:
		N: return S
		S: return N
		E: return W
		W: return E
	return N  # Default fallback

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
