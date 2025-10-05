extends Node2D

var anim: AnimatedSprite2D

func _ready() -> void:
	
	# Ищем AnimatedSprite2D
	anim = get_node_or_null("AnimatedSprite2D")
	if anim:
		anim.play("explode")
		anim.animation_finished.connect(_on_anim_finished)

func _on_anim_finished() -> void:
	queue_free()
