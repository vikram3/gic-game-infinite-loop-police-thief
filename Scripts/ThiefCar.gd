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
func run_away_from_player(delta):
	# Simple AI to run away from the police
	var police_pos = get_parent().police.map_pos
	
	# Calculate vector from police to thief
	var direction = map_pos - police_pos
	
	# Choose direction to move (away from police)
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

# Modify the _on_ThiefCar_area_entered function
func _on_ThiefCar_area_entered(area):
	if area == get_parent().police and not special_active:
		# Trigger role switch regardless of who's controlling whom
		get_parent().on_thief_caught()
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
