extends "res://Scripts/Collectible.gd"

func _ready():
	type = "coin"
	value = 100  # Points for collecting
	$AnimatedSprite.animation = "coin"
