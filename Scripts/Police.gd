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

var siren_on_as_player = true 

var map = null
var map_pos = Vector2()
var base_speed = 0.6
var speed = 0.5
var moving = false
var chase_timer = 0.0
var frustration = 0.0
var ai_path = []
var difficulty_scaling = 1.0
var drift_factor = 0.15
var boost_active = false
var boost_timer = 0

var special_cooldown = 0
var special_active = false
var SPECIAL_MAX_COOLDOWN = 15.0

# Siren audio variables
var siren_playing = false
var siren_fade_timer = 0.0
var SIREN_FADE_TIME = 1.0
var distance_for_full_volume = 5.0
var BASE_VOLUME_DB = -10.0  # Lower base volume for the siren

signal collected_item(item_type, value)

func _ready():
	$AnimatedSprite.play("s")
	$SirenLight.visible = true
	# Set up siren audio player
	setup_siren_audio()

# Set up the siren audio player
func setup_siren_audio():
	# Create AudioStreamPlayer if it doesn't exist
	if not has_node("SirenAudio"):
		var audio_player = AudioStreamPlayer2D.new()
		audio_player.name = "SirenAudio"
		audio_player.bus = "SFX"  # Use SFX audio bus if available
		audio_player.volume_db = BASE_VOLUME_DB  # Set initial volume to -20dB
		audio_player.max_distance = 1000
		audio_player.attenuation = 2.0
		add_child(audio_player)
		
		# Load siren sound - ensure this path is correct for your project
		var siren_sound = load("res://Assets/Sounds/siren.mp3")
		if siren_sound:
			audio_player.stream = siren_sound
		else:
			print("ERROR: Could not load siren sound file")

func _process(delta):
	if special_cooldown > 0:
		special_cooldown -= delta
	
	if boost_active:
		boost_timer -= delta
		if boost_timer <= 0:
			boost_active = false
			speed = base_speed
	
	# Normal siren light effect
	if special_active:
		# Faster flashing for siren light during special
		$SirenLight.modulate.a = 0.7 + abs(sin(OS.get_ticks_msec() * 0.01)) * 0.3
	else:
		# Normal siren light behavior
		$SirenLight.modulate.a = 0.5 + abs(sin(OS.get_ticks_msec() * 0.005)) * 0.5
	
	# Update siren sound
	update_siren_audio(delta)
	
	if not get_parent().is_player_thief and not moving:
		handle_player_input()
	elif get_parent().is_player_thief:
		if not moving:
			run_police_ai(delta)

# Update siren audio based on game state
func update_siren_audio(delta):
	# Get distance to thief
	var distance_to_thief = get_distance_to_thief()
	
	# Determine if siren should be playing based on game conditions
	var should_play_siren = false
	
	if get_parent().is_player_thief:
		# AI-controlled police should play siren when actively chasing
		should_play_siren = distance_to_thief < 12 or special_active
	else:
		# Player-controlled police plays siren when actively chasing or special active
		should_play_siren = distance_to_thief < 12 or special_active
	
	if has_node("SirenAudio"):
		var audio = $SirenAudio
		
		if should_play_siren and not siren_playing:
			audio.volume_db = BASE_VOLUME_DB
			audio.play()
			siren_playing = true
			siren_fade_timer = 0
		elif not should_play_siren and siren_playing:
			siren_fade_timer += delta
			
			# Fade out siren
			if siren_fade_timer < SIREN_FADE_TIME:
				audio.volume_db = lerp(BASE_VOLUME_DB, -80, siren_fade_timer / SIREN_FADE_TIME)
			else:
				audio.stop()
				audio.volume_db = BASE_VOLUME_DB  # Reset to base volume
				siren_playing = false
		
		# Adjust volume based on distance to thief if playing
		if siren_playing and distance_to_thief > 0:
			var volume_factor = clamp(1.0 - (distance_to_thief / (distance_for_full_volume * 3)), 0.2, 1.0)
			# Apply this factor to the base volume (converts linear factor to dB)
			audio.volume_db = BASE_VOLUME_DB + linear2db(volume_factor)

func handle_player_input():
	var dir = null
	
	if Input.is_action_pressed("move_up"):
		dir = N
	elif Input.is_action_pressed("move_down"):
		dir = S
	elif Input.is_action_pressed("move_right"):
		dir = E
	elif Input.is_action_pressed("move_left"):
		dir = W
	
	if Input.is_action_just_pressed("special") and special_cooldown <= 0:
		activate_special()
		
	
	if dir != null:
		move(dir)

func run_police_ai(delta):
	chase_timer += delta
	
	difficulty_scaling = min(2.0, 1.0 + get_parent().chase_time / 90.0)  
	
	if not moving:
		var distance = get_distance_to_thief()
		if distance > 5:
			speed = base_speed * (1.2 + (difficulty_scaling * 0.2))
		else:
			speed = base_speed * difficulty_scaling
			
		chase_thief_advanced()
		
		if special_cooldown <= 0 and (
			(distance > 8 and difficulty_scaling >= 1.2) or
			(distance > 4 and difficulty_scaling >= 1.5)
		):
			activate_special()
			
	if get_distance_to_thief() > 8:
		frustration += delta
	else:
		frustration = max(0, frustration - delta)

func get_distance_to_thief():
	var thief_pos = get_parent().thief.map_pos
	return (thief_pos - map_pos).length()

func chase_thief_advanced():
	var thief_pos = get_parent().thief.map_pos
	
	if get_parent().thief.special_active:
		patrol_random()
		return
	
	if ai_path.empty() or ai_path.size() <= 1:
		ai_path = find_path_to_thief(thief_pos)
	
	if not ai_path.empty():
		var next_step = ai_path[0]
		var dir_to_move = null
		
		for dir in moves.keys():
			if map_pos + moves[dir] == next_step:
				dir_to_move = dir
				break
		
		if dir_to_move != null and can_move(dir_to_move):
			move(dir_to_move)
			ai_path.pop_front()
			frustration = max(0, frustration - 1)
		else:
			ai_path.clear()
			frustration += 1
	else:
		simple_chase(thief_pos)
		frustration += 1

func search_in_spiral():
	var spiral_directions = [E, S, W, W, N, N, E, E, E, S, S, S, W, W, W, W]
	var spiral_index = int(chase_timer * 2) % spiral_directions.size()
	var search_dir = spiral_directions[spiral_index]
	
	if can_move(search_dir):
		move(search_dir)
	else:
		patrol_random()

func simple_chase(thief_pos):
	var dx = thief_pos.x - map_pos.x
	var dy = thief_pos.y - map_pos.y
	
	var primary_dirs = []
	var secondary_dirs = []
	
	if abs(dx) > abs(dy):
		primary_dirs = [E if dx > 0 else W]
		secondary_dirs = [S if dy > 0 else N]
	else:
		primary_dirs = [S if dy > 0 else N]
		secondary_dirs = [E if dx > 0 else W]
	
	var fallback_dirs = [
		opposite_direction(primary_dirs[0]),
		opposite_direction(secondary_dirs[0])
	]
	
	for dir in primary_dirs + secondary_dirs + fallback_dirs:
		if can_move(dir):
			move(dir)
			return
	
	patrol_random()

func find_path_to_thief(target_pos):
	var max_iterations = 200
	var iterations = 0
	
	var open_set = [map_pos]
	var came_from = {}
	var g_score = {str(map_pos): 0}
	var f_score = {str(map_pos): improved_heuristic(map_pos, target_pos)}
	
	while not open_set.empty() and iterations < max_iterations:
		iterations += 1
		var current = get_lowest_fscore_node(open_set, f_score)
		
		if current == target_pos:
			return reconstruct_path(came_from, current)
		
		open_set.erase(current)
		
		for dir in moves.keys():
			if can_move_from_position(current, dir):
				var neighbor = current + moves[dir]
				var tentative_g = g_score[str(current)] + 1
				
				if not g_score.has(str(neighbor)) or tentative_g < g_score[str(neighbor)]:
					came_from[str(neighbor)] = current
					g_score[str(neighbor)] = tentative_g
					f_score[str(neighbor)] = tentative_g + improved_heuristic(neighbor, target_pos)
					
					if not neighbor in open_set:
						open_set.append(neighbor)
	
	if not came_from.empty():
		var furthest_point = find_furthest_point_toward_target(came_from, target_pos)
		return reconstruct_path(came_from, furthest_point)
	
	return []

func can_move_from_position(pos, dir):
	var cell = map.get_cellv(pos)
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
	var manhattan = abs(a.x - b.x) + abs(a.y - b.y)
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
	
	if not path.empty():
		path.pop_front()
	
	return path

func patrol_random():
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
	return N

func move(dir):
	if not can_move(dir):
		var alt_dirs = get_alternative_directions(dir)
		for alt_dir in alt_dirs:
			if can_move(alt_dir):
				dir = alt_dir
				break
		if not can_move(dir):
			return
	
	moving = true
	$AnimatedSprite.play(animations[dir])
	
	var prev_map_pos = map_pos
	map_pos += moves[dir]
	
	if map.get_cellv(map_pos) == -1:
		get_parent().generate_tile(map_pos)
	
	var destination = map.map_to_world(map_pos) + Vector2(0, 20)
	
	$Tween.interpolate_property(
		self, 'position', 
		position, 
		destination, 
		0.2/speed,
		Tween.TRANS_LINEAR,
		Tween.EASE_IN
	)
	$Tween.start()
	
	$MoveSound.play()

func get_alternative_directions(dir):
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
	check_for_collectibles()

func check_for_collectibles():
	for collectible in get_parent().get_children():
		if collectible.has_method("collect") and collectible.map_pos == map_pos:
			var item_data = collectible.collect()
			emit_signal("collected_item", item_data.type, item_data.value)
			get_parent().collect_coin(item_data.value, self) if item_data.type == "coin" else null
			
			if item_data.type == "boost":
				apply_speed_boost(item_data.value, 3.0)
			elif item_data.type == "time":
				get_parent().extend_role_time(item_data.value)

func apply_speed_boost(boost_amount, duration):
	boost_active = true
	boost_timer = duration
	speed = base_speed + boost_amount
	$BoostSound.play()

func activate_special():
	special_active = true
	special_cooldown = SPECIAL_MAX_COOLDOWN
	$SpecialTimer.start(5.0)
	$SpecialSound.play()
	
	# Store original speed to restore it later
	var original_speed = speed
	
	# Significant speed boost during special
	speed = base_speed * 1.8  # 80% speed boost
	
	# Visual indication using existing sprite
	$AnimatedSprite.modulate = Color(0.2, 0.2, 1.0, 1.0)  # Blue tint
	
	# Enhance siren using existing audio
	if has_node("SirenAudio"):
		$SirenAudio.volume_db = BASE_VOLUME_DB + 5  # Louder siren
		$SirenAudio.play()
		siren_playing = true
	
	# Make the siren light flash faster
	$SirenLight.modulate.a = 1.0  # Full brightness
	
	# Affect thief if in range
	slow_nearby_thief()

# Add this function to slow the thief when special is active
func slow_nearby_thief():
	var thief = get_parent().thief
	if thief and get_distance_to_thief() < 8:  # Extended range during special
		# Slow the thief by directly modifying their speed
		var original_thief_speed = thief.speed
		thief.speed = thief.speed * 0.6  # Slow to 60%
		
		# Visual indication that thief is affected
		thief.get_node("AnimatedSprite").modulate = Color(0.5, 0.5, 1.0)
		
		# Use a timer to reset the thief's speed
		yield(get_tree().create_timer(3.0), "timeout")
		
		# Only reset if special is still active and thief exists
		if is_instance_valid(thief):
			thief.speed = original_thief_speed
			thief.get_node("AnimatedSprite").modulate = Color(1, 1, 1)

func _on_SpecialTimer_timeout():
	special_active = false
	
	# Reset visual effects
	$AnimatedSprite.modulate = Color(1, 1, 1)  # Reset tint
	
	# Reset speed to normal
	speed = base_speed
	
	# If player isn't actively chasing, stop the siren when special ends
	if not get_parent().is_player_thief or get_distance_to_thief() > 12:
		if has_node("SirenAudio") and siren_playing:
			siren_fade_timer = 0
