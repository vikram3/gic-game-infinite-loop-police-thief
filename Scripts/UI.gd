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
var score_animation_speed = 5

func _ready():
	score_label.text = "0"
	timer_bar.value = 100
	update_role(true)
	
	messages_panel.visible = false
	show_message("Game started! You're the THIEF!", 3.0)

func _process(delta):
	if current_score < target_score:
		current_score += score_animation_speed
		if current_score > target_score:
			current_score = target_score
		score_label.text = str(current_score)

func update_score(new_score):
	target_score = new_score

func update_timer(time_left):
	var percentage = (time_left / max_role_time) * 100
	timer_bar.value = percentage
	
	if percentage < 25:
		timer_bar.modulate = Color(1, 0.3, 0.3)
	elif percentage < 50:
		timer_bar.modulate = Color(1, 0.8, 0.2)
	else:
		timer_bar.modulate = Color(0.3, 1, 0.3)

func update_role(is_thief):
	if is_thief:
		role_indicator.text = "THIEF"
		role_indicator.modulate = Color(1.0, 0.8, 0.2)
		role_icon.texture = preload("res://Assets/UI/thief_icon.jpg")
		
		show_message("You're the THIEF! Escape the police and collect coins!", 3.0)
	else:
		role_indicator.text = "POLICE"
		role_indicator.modulate = Color(0.2, 0.4, 1.0)
		role_icon.texture = preload("res://Assets/UI/police_icon.png")
		
		show_message("You're the POLICE! Catch the thief!", 3.0)
	
	$RolePanel.visible = true
	
	$RoleAnimation.play("RoleAnimation")

func show_message(text, duration=3.0):
	print("UI: Showing message: ", text)
	message_label.text = text
	messages_panel.visible = true
	messages_panel.modulate.a = 1.0
	
	message_timer.stop()
	
	message_timer.wait_time = duration
	message_timer.start()

func _on_MessageTimer_timeout():
	messages_panel.visible = false

func display_next_message():
	messages_panel.modulate.a = 1.0
	messages_panel.visible = true
	if messages_queue.empty():
		messages_panel.visible = false
		return
	
	var message = messages_queue.pop_front()
	message_label.text = message.text
	messages_panel.visible = true
	
	$MessageAnimation.stop()
	
	$MessageAnimation.play("fade_in")
	
	message_timer.wait_time = message.duration
	message_timer.start()

func _on_MessageAnimation_animation_finished(anim_name):
	if anim_name == "fade_out":
		display_next_message()

func show_game_over(win):
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
	
	$GameOverAnimation.play("show_game_over")

func _on_RestartButton_pressed():
	get_tree().reload_current_scene()

func _on_MainMenuButton_pressed():
	get_tree().change_scene("res://Scenes/MainMenu.tscn")
