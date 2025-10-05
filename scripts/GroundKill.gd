extends Area2D

func _ready() -> void:
	connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body: Node) -> void:
	# Взрываем игрока или врага при касании земли
	if body and body.has_method("explode_on_ground"):
		if body.is_in_group("player") or body.is_in_group("enemy"):
			body.explode_on_ground(body.global_position)
