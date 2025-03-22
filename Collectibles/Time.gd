extends "res://Scripts/Collectible.gd"

func _ready():
	type = "time"
	value = 5.0  # Seconds to add
	$AnimatedSprite.animation = "time"
