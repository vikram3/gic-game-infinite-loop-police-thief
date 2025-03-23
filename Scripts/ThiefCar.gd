extends Area2D

const N = 0x1
const E = 0x2
const S = 0x4
const W = 0x8

var previous_positions = []
const MAX_MEMORY = 5

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
var drift_factor = 0.2
var boost_active = false
var boost_timer = 0
var chase_timer = 0

var special_active = false
var INVINCIBILITY_DURATION = 5.0

signal collected_item(item_type, value)

func _ready():
	if not is_connected("area_entered", self, "_on_ThiefCar_area_entered"):
		connect("area_entered", self, "_on_ThiefCar_area_entered")
	$AnimatedSprite.play("s")

func _process(delta):
	if boost_active:
		boost_timer -= delta
		if boost_timer <= 0:
			boost_active = false
			speed = base_speed
	
	if get_parent().is_player_thief and not moving:
		handle_player_input()
	elif not get_parent().is_player_thief:
		chase_timer += delta
		
		if not moving and chase_timer >= 0.5:
			chase_timer = 0
			run_away_from_player(delta)

func switch_role():
	special_active = true
	modulate.a = 0.5
	$SpecialTimer.start(INVINCIBILITY_DURATION)
	$SpecialSound.play()
	print("Role switched - invincibility active for 5 seconds!")

func run_away_from_player(delta):
	var police_pos = get_parent().police.map_pos
	var distance = (police_pos - map_pos).length()
	
	var direction = map_pos - police_pos
	
	var possible_dirs = []
	
	if direction.x > 0 and can_move(E):
		possible_dirs.append(E)
	elif direction.x < 0 and can_move(W):
		possible_dirs.append(W)
		
	if direction.y > 0 and can_move(S):
		possible_dirs.append(S)
	elif direction.y < 0 and can_move(N):
		possible_dirs.append(N)
	
	if abs(direction.x) > abs(direction.y):
		if can_move(N) and not N in possible_dirs:
			possible_dirs.append(N)
		if can_move(S) and not S in possible_dirs:
			possible_dirs.append(S)
	else:
		if can_move(E) and not E in possible_dirs:
			possible_dirs.append(E)
		if can_move(W) and not W in possible_dirs:
			possible_dirs.append(W)
	
	for test_dir in [N, E, S, W]:
		if can_move(test_dir) and not test_dir in possible_dirs:
			possible_dirs.append(test_dir)
	
	if not possible_dirs.empty():
		move(possible_dirs[0])

func escape_from_police(police_pos):
	var direction = map_pos - police_pos
	
	var possible_moves = []
	var move_scores = {}
	
	for dir in [N, E, S, W]:
		if can_move(dir):
			var new_pos = map_pos + moves[dir]
			
			if new_pos in previous_positions:
				continue
				
			var new_distance = (police_pos - new_pos).length()
			
			var score = new_distance
			
			var dot_product = direction.normalized().dot(moves[dir].normalized())
			score += dot_product * 2
			
			score += randf() * 0.5
			
			possible_moves.append(dir)
			move_scores[dir] = score
	
	if not possible_moves.empty():
		var best_dir = possible_moves[0]
		var best_score = move_scores[best_dir]
		
		for dir in possible_moves:
			if move_scores[dir] > best_score:
				best_score = move_scores[dir]
				best_dir = dir
		
		move(best_dir)
		
		previous_positions.append(map_pos)
		if previous_positions.size() > MAX_MEMORY:
			previous_positions.pop_front()
	else:
		for dir in [N, E, S, W]:
			if can_move(dir):
				move(dir)
				break

func explore_and_collect():
	var nearby_collectible = find_nearest_collectible()
	
	if nearby_collectible:
		move_toward_position(nearby_collectible.map_pos)
	else:
		explore_random()

func find_nearest_collectible():
	var nearest = null
	var min_distance = 999
	
	for collectible in get_parent().get_children():
		if collectible.has_method("collect"):
			var distance = (collectible.map_pos - map_pos).length()
			if distance < min_distance and distance < 8:
				min_distance = distance
				nearest = collectible
	
	return nearest

func move_toward_position(target_pos):
	var direction = target_pos - map_pos
	var possible_dirs = []
	
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0 and can_move(E): possible_dirs.append(E)
		elif direction.x < 0 and can_move(W): possible_dirs.append(W)
		
		if direction.y > 0 and can_move(S): possible_dirs.append(S)
		elif direction.y < 0 and can_move(N): possible_dirs.append(N)
	else:
		if direction.y > 0 and can_move(S): possible_dirs.append(S)
		elif direction.y < 0 and can_move(N): possible_dirs.append(N)
		
		if direction.x > 0 and can_move(E): possible_dirs.append(E)
		elif direction.x < 0 and can_move(W): possible_dirs.append(W)
	
	for dir in [N, E, S, W]:
		if can_move(dir) and not dir in possible_dirs:
			possible_dirs.append(dir)
	
	if not possible_dirs.empty():
		var chosen_dir = possible_dirs[randi() % possible_dirs.size()]
		move(chosen_dir)
		
		previous_positions.append(map_pos)
		if previous_positions.size() > MAX_MEMORY:
			previous_positions.pop_front()

func explore_random():
	var available_dirs = []
	
	for dir in [N, E, S, W]:
		if can_move(dir):
			var new_pos = map_pos + moves[dir]
			if not new_pos in previous_positions:
				available_dirs.append(dir)
	
	if available_dirs.empty():
		for dir in [N, E, S, W]:
			if can_move(dir):
				available_dirs.append(dir)
	
	if not available_dirs.empty():
		var random_dir = available_dirs[randi() % available_dirs.size()]
		move(random_dir)
		
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
	
	if Input.is_action_just_pressed("special"):
		activate_special()
	
	if dir != null:
		move(dir)

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

func _on_ThiefCar_area_entered(area):
	print("ThiefCar entered by: ", area.name)
	if area == get_parent().police and not special_active:
		print("Caught by police!")
		get_parent().on_thief_caught()
		$CaughtSound.play()

func apply_speed_boost(boost_amount, duration):
	boost_active = true
	boost_timer = duration
	speed = base_speed + boost_amount
	$BoostSound.play()

func activate_special():
	special_active = true
	modulate.a = 0.5
	$SpecialTimer.start(5)
	$SpecialSound.play()

func _on_SpecialTimer_timeout():
	special_active = false
	modulate.a = 1.0
