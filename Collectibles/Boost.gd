extends "res://Scripts/Collectible.gd"

func _ready():
	type = "boost"
	value = 0.5  # Speed boost amount
	$AnimatedSprite.animation = "speed"
