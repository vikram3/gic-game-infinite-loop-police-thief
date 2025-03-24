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

# Arrays of funny messages for each role - SHORTER VERSIONS
var thief_messages = [
	"You're the THIEF! Grab and dash!",
	"THIEF MODE! Steal everything!",
	"THIEF TIME! Don't get caught!",
	"SNEAKY THIEF! Be invisible!",
	"THIEF ALERT! Coins need stealing!",
	"MASTER THIEF! Show your skills!",
	"You're a THIEF! Fingers ready!",
	"THIEF MODE! Crime pays... sometimes!",
	"THIEF LIFE! Run faster!",
	"THIEF DUTY! Pockets aren't full yet!"
]

var police_messages = [
	"POLICE! Catch that thief!",
	"OFFICER ON DUTY! Chase time!",
	"POLICE MODE! Serve justice!",
	"You're the LAW now! Go go go!",
	"POLICE POWER! Make an arrest!",
	"COP MODE! Donuts later!",
	"POLICE PURSUIT! Run faster!",
	"OFFICER! Badge with purpose!",
	"POLICE! Justice incoming!",
	"LAW ENFORCEMENT! Thief spotted!"
]

func _ready():
	score_label.text = "0"
	timer_bar.value = 100
	update_role(true)
	
	messages_panel.visible = false
	show_message("Game started! You're the THIEF!", 3.0)
	
	# Make sure text wrapping is enabled on the message label
	message_label.autowrap = true

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
		
		# Get a random thief message
		var random_message = thief_messages[randi() % thief_messages.size()]
		show_message(random_message, 3.0)
	else:
		role_indicator.text = "POLICE"
		role_indicator.modulate = Color(0.2, 0.4, 1.0)
		role_icon.texture = preload("res://Assets/UI/police_icon.png")
		
		# Get a random police message
		var random_message = police_messages[randi() % police_messages.size()]
		show_message(random_message, 3.0)
	
	$RolePanel.visible = true
	
	$RoleAnimation.play("RoleAnimation")

func show_catch_bonus_message(bonus_points):
	# Just update the score without any message
	update_score(target_score + bonus_points)

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
