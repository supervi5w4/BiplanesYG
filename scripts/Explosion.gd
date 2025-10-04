extends Node2D

@onready var anim: AnimatedSprite2D = $Anim
@onready var sfx: AudioStreamPlayer2D = $Sfx

func _ready() -> void:
	if sfx:
		sfx.play()
	if anim:
		anim.play("explode")
		anim.animation_finished.connect(_on_anim_finished)

func _on_anim_finished(anim_name: StringName) -> void:
	queue_free()
