extends Node2D
# ─────────────────────────────────────────────────────────────────────────────
# EnemySpawner.gd — спавнер врагов для режима кампании
# ─────────────────────────────────────────────────────────────────────────────

signal boss_defeated

# === ЭКСПОРТИРУЕМЫЕ ПАРАМЕТРЫ ===
@export var enemy_scene: PackedScene
@export var boss_scene: PackedScene
@export var spawn_interval_min: float = 3.0  # Минимальный интервал между спавнами
@export var spawn_interval_max: float = 10.0 # Максимальный интервал между спавнами
@export var boss_spawn_time: float = 60.0    # Время до появления босса

# === СОСТОЯНИЕ ===
var spawn_timer: float = 0.0
var current_spawn_interval: float = 3.0      # Текущий интервал для следующего спавна
var elapsed_time: float = 0.0
var is_spawning: bool = true
var boss_spawned: bool = false
var boss_instance: Node2D = null

func _ready() -> void:
	# Проверяем наличие сцены врага
	if not enemy_scene:
		push_error("EnemySpawner: enemy_scene не назначена!")
		is_spawning = false
	
	# Устанавливаем первый случайный интервал
	current_spawn_interval = randf_range(spawn_interval_min, spawn_interval_max)

func _process(delta: float) -> void:
	if not is_spawning:
		return
	
	elapsed_time += delta
	spawn_timer += delta
	
	# Проверяем время появления босса
	if elapsed_time >= boss_spawn_time and not boss_spawned:
		_spawn_boss()
		return
	
	# Обычный спавн врагов
	if spawn_timer >= current_spawn_interval and not boss_spawned:
		spawn_timer = 0.0
		_spawn_enemy()
		# Устанавливаем новый случайный интервал для следующего спавна
		current_spawn_interval = randf_range(spawn_interval_min, spawn_interval_max)

func _spawn_enemy() -> void:
	"""Спавнит обычного врага"""
	if not enemy_scene:
		return
	
	var enemy = enemy_scene.instantiate() as CharacterBody2D
	if not enemy:
		return
	
	# Получаем камеру, игрока и вычисляем позицию спавна
	var camera = get_viewport().get_camera_2d()
	var viewport_size = get_viewport().get_visible_rect().size
	var spawn_x: float
	
	# Ищем игрока
	var player = get_tree().get_first_node_in_group("player")
	
	if player:
		# ИСПРАВЛЕНИЕ БАГА: Спавним справа от ИГРОКА, а не от камеры
		# Враг должен появиться минимум на 300 единиц правее игрока
		var spawn_offset = 300.0
		var player_spawn_x = player.global_position.x + spawn_offset
		
		# Также вычисляем правый край экрана (от камеры)
		var screen_right_edge = viewport_size.x + 100
		if camera:
			screen_right_edge = camera.global_position.x + viewport_size.x / 2 + 100
		
		# Выбираем максимум - враг должен быть И справа от игрока, И за экраном
		spawn_x = max(player_spawn_x, screen_right_edge)
	elif camera:
		# Fallback: если игрок не найден, спавним справа от камеры
		spawn_x = camera.global_position.x + viewport_size.x / 2 + 100
	else:
		# Fallback: если ничего не найдено
		spawn_x = viewport_size.x + 100
	
	var spawn_y = randf_range(100, viewport_size.y - 100)
	
	enemy.global_position = Vector2(spawn_x, spawn_y)
	
	# === ОТЛАДОЧНЫЕ ПРИНТЫ ===
	print("[DEBUG SPAWN] === SPAWNING ENEMY ===")
	
	# Позиция игрока (используем уже найденного player)
	if player:
		print("[DEBUG SPAWN] Позиция игрока: ", player.global_position)
	else:
		print("[DEBUG SPAWN] Игрок не найден")
	
	# Позиция камеры
	if camera:
		print("[DEBUG SPAWN] Позиция камеры: ", camera.global_position)
	else:
		print("[DEBUG SPAWN] Камера не найдена")
	
	# Вычисленная позиция спавна
	print("[DEBUG SPAWN] Вычисленная позиция спавна: X=", spawn_x, " Y=", spawn_y)
	
	# Финальная позиция врага
	print("[DEBUG SPAWN] Финальная позиция врага: ", enemy.global_position)
	print("[DEBUG SPAWN] ==================")
	
	# Настраиваем врага для кампании (движение влево)
	enemy.rotation = PI  # Поворот влево
	
	# ВАЖНО: Включаем режим кампании - враг не преследует, а летит прямо
	if enemy.has_method("set"):
		enemy.set("campaign_mode", true)
		enemy.set("respawn_enabled", false)
	
	# ВАЖНО: Добавляем врага в корневой узел уровня (родитель спавнера)
	get_parent().add_child(enemy)
	
	# Удаляем врага через некоторое время, если он улетел далеко за экран
	_schedule_enemy_cleanup(enemy)

func _spawn_boss() -> void:
	"""Спавнит босса"""
	if boss_spawned:
		return
	
	boss_spawned = true
	is_spawning = false  # Останавливаем обычный спавн
	
	# Если сцена босса не назначена, используем обычного врага с повышенными характеристиками
	var boss: CharacterBody2D
	if boss_scene:
		boss = boss_scene.instantiate() as CharacterBody2D
	elif enemy_scene:
		boss = enemy_scene.instantiate() as CharacterBody2D
		# Увеличиваем характеристики обычного врага
		if boss:
			boss.set("max_lives", 10)
			boss.set("lives", 10)
			boss.set("hp", 100)
	
	if not boss:
		push_error("EnemySpawner: не удалось создать босса!")
		return
	
	# Спавним босса справа от игрока (как и обычных врагов)
	var camera = get_viewport().get_camera_2d()
	var viewport_size = get_viewport().get_visible_rect().size
	var spawn_x: float
	
	# Ищем игрока
	var player = get_tree().get_first_node_in_group("player")
	
	if player:
		# ИСПРАВЛЕНИЕ БАГА: Спавним справа от ИГРОКА, а не от камеры
		# Босс должен появиться минимум на 400 единиц правее игрока (больше чем обычные враги)
		var spawn_offset = 400.0
		var player_spawn_x = player.global_position.x + spawn_offset
		
		# Также вычисляем правый край экрана (от камеры)
		var screen_right_edge = viewport_size.x + 150
		if camera:
			screen_right_edge = camera.global_position.x + viewport_size.x / 2 + 150
		
		# Выбираем максимум - босс должен быть И справа от игрока, И за экраном
		spawn_x = max(player_spawn_x, screen_right_edge)
	elif camera:
		# Fallback: если игрок не найден, спавним справа от камеры
		spawn_x = camera.global_position.x + viewport_size.x / 2 + 150
	else:
		# Fallback: если ничего не найдено
		spawn_x = viewport_size.x + 150
	
	var spawn_y = viewport_size.y / 2
	
	boss.global_position = Vector2(spawn_x, spawn_y)
	boss.rotation = PI  # Поворот влево
	
	# Настраиваем босса для кампании
	if boss.has_method("set"):
		boss.set("campaign_mode", true)  # Босс тоже летит прямо в режиме кампании
		boss.set("respawn_enabled", false)
	
	# ВАЖНО: Добавляем босса в корневой узел уровня (родитель спавнера)
	get_parent().add_child(boss)
	boss_instance = boss
	
	# Подключаем сигнал смерти босса
	if boss.has_signal("tree_exited"):
		boss.tree_exited.connect(_on_boss_died)

func _on_boss_died() -> void:
	"""Обработка смерти босса"""
	if boss_instance and not is_instance_valid(boss_instance):
		# Босс умер
		await get_tree().create_timer(0.5).timeout
		boss_defeated.emit()

func _schedule_enemy_cleanup(enemy: Node2D) -> void:
	"""Планирует удаление врага, если он улетел далеко за экран"""
	await get_tree().create_timer(5.0).timeout
	
	# Проверяем периодически, не улетел ли враг слишком далеко
	for i in range(20):  # Проверяем 20 раз (100 секунд максимум)
		if not is_instance_valid(enemy):
			return
		
		# Получаем камеру и проверяем расстояние
		var camera = get_viewport().get_camera_2d()
		if camera:
			# Если враг улетел далеко влево от камеры - удаляем
			var distance = camera.global_position.x - enemy.global_position.x
			if distance > 2000:
				enemy.queue_free()
				return
		
		await get_tree().create_timer(5.0).timeout
	
	# Если прошло много времени - всё равно удаляем
	if is_instance_valid(enemy):
		enemy.queue_free()

func stop_spawning() -> void:
	"""Останавливает спавн врагов"""
	is_spawning = false

