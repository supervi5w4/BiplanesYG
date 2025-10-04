extends Area2D

func _ready() -> void:
	connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body: Node) -> void:
	# Взрываем только игрока
	if body and body.is_in_group("player") and body.has_method("explode_on_ground"):
		body.explode_on_ground(global_position)
