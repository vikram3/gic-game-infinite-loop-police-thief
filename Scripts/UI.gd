extends Control

onready var score_label = $ScorePanel/Score
onready var timer_bar = $TimerBar
onready var role_indicator = $RolePanel/RoleLabel
onready var role_icon = $RolePanel/RoleIcon
onready var messages_panel = $MessagesPanel
onready var message_label = $MessagesPanel/Message
onready var message_timer = $MessageTimer
var max_role_time = 30.0

var messages_queue = []
var current_score = 0
var target_score = 0
var score_animation_speed = 5  # Points per frame

func _ready():
	# Initialize UI
	score_label.text = "0"
	timer_bar.value = 100
	update_role(true)  # Start as thief by default
	messages_panel.visible = false

func _process(delta):
	# Animate score counting up
	if current_score < target_score:
		current_score += score_animation_speed
		if current_score > target_score:
			current_score = target_score
		score_label.text = str(current_score)

func update_score(new_score):
	target_score = new_score
	# Score will animate up in _process

func update_timer(time_left):
	var percentage = (time_left / max_role_time) * 100
	timer_bar.value = percentage
	
	# Change color based on time left
	if percentage < 25:
		timer_bar.modulate = Color(1, 0.3, 0.3)  # Red
	elif percentage < 50:
		timer_bar.modulate = Color(1, 0.8, 0.2)  # Yellow
	else:
		timer_bar.modulate = Color(0.3, 1, 0.3)  # Green

func update_role(is_thief):
	if is_thief:
		role_indicator.text = "THIEF"
		role_indicator.modulate = Color(1.0, 0.8, 0.2)  # Gold for thief
		role_icon.texture = preload("res://Assets/UI/thief_icon.jpg")
		
		# Show tip message
		show_message("You're the THIEF! Escape the police and collect coins!")
	else:
		role_indicator.text = "POLICE"
		role_indicator.modulate = Color(0.2, 0.4, 1.0)  # Blue for police
		role_icon.texture = preload("res://Assets/UI/police_icon.png")
		
		# Show tip message
		show_message("You're the POLICE! Catch the thief!")
	
	# Play role switch animation
	$RoleAnimation.play("RoleAnimation")

func show_message(text, duration=3.0):
	# Add message to queue
	messages_queue.append({"text": text, "duration": duration})
	
	# If not currently showing a message, show this one
	if not messages_panel.visible:
		display_next_message()

func display_next_message():
	if messages_queue.empty():
		messages_panel.visible = false
		return
	
	var message = messages_queue.pop_front()
	message_label.text = message.text
	messages_panel.visible = true
	
	# Start fade-in animation
	$MessageAnimation.play("fade_in")
	
	# Set timer for message duration
	message_timer.wait_time = message.duration
	message_timer.start()

func _on_MessageTimer_timeout():
	# Fade out current message
	$MessageAnimation.play("fade_out")

func _on_MessageAnimation_animation_finished(anim_name):
	if anim_name == "fade_out":
		# Check if there are more messages to display
		display_next_message()

func show_game_over(win):
	# Show game over screen
	$GameOverPanel.visible = true
	
	if win:
		$GameOverPanel/ResultLabel.text = "YOU WIN!"
		$GameOverPanel/ResultLabel.modulate = Color(0.2, 1.0, 0.2)
		$VictorySound.play()
	else:
		$GameOverPanel/ResultLabel.text = "GAME OVER"
		$GameOverPanel/ResultLabel.modulate = Color(1.0, 0.2, 0.2)
		$DefeatSound.play()
	
	$GameOverPanel/FinalScoreLabel.text = "Final Score: " + str(target_score)
	
	# Animate the panel
	$GameOverAnimation.play("show_game_over")

func _on_RestartButton_pressed():
	# Restart the game
	get_tree().reload_current_scene()

func _on_MainMenuButton_pressed():
	# Go back to main menu
	get_tree().change_scene("res://Scenes/MainMenu.tscn")
