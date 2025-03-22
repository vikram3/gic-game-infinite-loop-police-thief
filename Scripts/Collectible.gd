extends Area2D
class_name Collectible

var map_pos = Vector2()
var type = "generic"
var value = 1
var animation_speed = 1.0
var collected = false

func _ready():
	if has_node("AnimatedSprite"):
		$AnimatedSprite.play()
	
	if has_node("Tween"):
		$Tween.interpolate_property(
			self, "position:y", 
			position.y, 
			position.y - 5, 
			0.5, 
			Tween.TRANS_SINE, 
			Tween.EASE_IN_OUT
		)
		$Tween.start()

func _on_Tween_tween_completed(object, key):
	if has_node("Tween"):
		$Tween.interpolate_property(
			self, "position:y", 
			position.y, 
			position.y + 10 if position.y < self.position.y else position.y - 10, 
			1.0, 
			Tween.TRANS_SINE, 
			Tween.EASE_IN_OUT
		)
		$Tween.start()

func collect():
	if collected:
		return {
			"type": type,
			"value": 0
		}
		
	collected = true
	
	if has_node("CollectSound"):
		$CollectSound.play()
	if has_node("CollectParticles"):
		$CollectParticles.emitting = true
	
	if has_node("AnimatedSprite"):
		$AnimatedSprite.visible = false
	
	if has_node("DespawnTimer"):
		$DespawnTimer.start(1.0)
	
	return {
		"type": type,
		"value": value
	}

func _on_DespawnTimer_timeout():
	queue_free()
