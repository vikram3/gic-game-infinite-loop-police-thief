extends AudioStreamPlayer


func _ready():
	self.play()


func _on_BGMusic_finished():
	self.play()
