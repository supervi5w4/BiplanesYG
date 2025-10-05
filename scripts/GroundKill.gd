extends Area2D

func _ready() -> void:
	connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body: Node) -> void:
	# Проверяем, что объект существует и является игроком или врагом
	if not body or not (body.is_in_group("player") or body.is_in_group("enemy")):
		return
	
	# Проверяем состояние объекта перед взрывом
	# Если объект мертв или неуязвим, не взрываем его
	if body.has_method("get_is_alive") and not body.get_is_alive():
		return
	
	if body.has_method("is_invulnerable") and body.is_invulnerable():
		return
	
	# Взрываем игрока или врага при касании земли
	if body.is_in_group("player") and body.has_method("explode_on_ground"):
		body.explode_on_ground(body.global_position)
	elif body.is_in_group("enemy") and body.has_method("_explode"):
		body._explode(body.global_position)
