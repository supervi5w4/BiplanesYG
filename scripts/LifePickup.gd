extends Area2D
# ─────────────────────────────────────────────────────────────────────────────
# LifePickup.gd — плюшка для восстановления жизней игрока
# ─────────────────────────────────────────────────────────────────────────────

@export var life_amount: int = 1  # Количество жизней для восстановления

func _ready() -> void:
	# Добавляем в группу для поиска ИИ
	add_to_group("life_pickup")
	
	# Подключаемся к сигналу входа тела
	body_entered.connect(_on_body_entered)
	
	# Добавляем небольшую анимацию плавающего движения
	_start_float_animation()

func _on_body_entered(body: Node2D) -> void:
	# Проверяем, что это игрок или враг
	if body.is_in_group("player"):
		# Вызываем метод добавления жизни у игрока
		if body.has_method("add_life"):
			body.add_life(life_amount)
			
			# Можно воспроизвести звук подбора (если есть)
			# $AudioStreamPlayer2D.play()
			
			# Удаляем плюшку
			queue_free()
	elif body.is_in_group("enemy"):
		# Вызываем метод добавления жизни у врага
		if body.has_method("add_life"):
			body.add_life(life_amount)
			
			# Можно воспроизвести звук подбора (если есть)
			# $AudioStreamPlayer2D.play()
			
			# Удаляем плюшку
			queue_free()

func _start_float_animation() -> void:
	"""Создает плавающую анимацию для плюшки"""
	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Плавное движение вверх-вниз
	tween.tween_property(self, "position:y", position.y - 10, 1.0)
	tween.tween_property(self, "position:y", position.y + 10, 1.0)
	
	# Добавляем небольшое вращение
	var rotation_tween = create_tween()
	rotation_tween.set_loops()
	rotation_tween.set_trans(Tween.TRANS_LINEAR)
	rotation_tween.tween_property(self, "rotation", TAU, 3.0)

