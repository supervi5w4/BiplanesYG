extends CharacterBody2D
# ─────────────────────────────────────────────────────────────────────────────
# Enemy.gd — ИИ-противник с поиском игрока и стрельбой
# ─────────────────────────────────────────────────────────────────────────────

# === ПАРАМЕТРЫ ДВИЖЕНИЯ ===
@export var turn_speed: float = 2.5
@export var accel: float = 600.0
@export var brake_power: float = 800.0
@export var max_speed: float = 400.0
@export var drag_linear: float = 0.8
@export var fire_cooldown: float = 0.3

# === ПСЕВДО-ВЕРТИКАЛЬ (высота) ===
@export var start_altitude: float = 120.0
@export var gravity_alt: float = 200.0
@export var lift_speed_coeff: float = 0.8
@export var lift_throttle_coeff: float = 100.0
@export var stall_speed_alt: float = 120.0
@export var stall_soft: float = 35.0
@export var max_climb_rate: float = 200.0

# === НАЗЕМНЫЙ РЕЖИМ ===
@export var ground_friction: float = 180.0
@export var liftoff_speed: float = 150.0
@export var liftoff_lift_margin: float = 25.0

# === ИИ ПАРАМЕТРЫ ===
@export var detection_range: float = 500.0
@export var aim_accuracy: float = 0.1  # Радианы для точности прицеливания
@export var turn_smoothing: float = 0.8  # Сглаживание поворотов

# === ИЗБЕГАНИЕ GROUNDKILL ===
@export var groundkill_detection_range: float = 200.0  # Дистанция обнаружения GroundKill
@export var groundkill_avoidance_strength: float = 2.0  # Сила избегания (множитель поворота)
@export var groundkill_min_altitude: float = 80.0  # Минимальная безопасная высота

# === ВЗРЫВ ===
@export var explosion_scene: PackedScene = preload("res://scenes/Explosion.tscn")
@export var respawn_delay: float = 3.0
@export var respawn_enabled: bool = true  # Враг респавнится через 3 секунды

# === GroundKill ===
@export var ground_kill_group: String = "GroundKill"
@export var ground_kill_name: String = "GroundKill"

# === СОСТОЯНИЕ ===
var speed: float = 0.0
var hp: int = 10
var can_shoot: bool = true

var altitude: float = 0.0
var v_alt: float = 0.0
var is_grounded: bool = false

var is_alive: bool = true
var target_player: Node2D = null
var target_angle: float = 0.0
var last_player_search_time: float = 0.0

# === СОСТОЯНИЕ ИЗБЕГАНИЯ GROUNDKILL ===
var groundkill_threat: bool = false
var groundkill_avoidance_angle: float = 0.0
var groundkill_position: Vector2 = Vector2.ZERO

# === НАЧАЛЬНОЕ СОСТОЯНИЕ ===
var is_starting: bool = true
var start_safety_time: float = 0.0

@onready var muzzle: Node2D = $Muzzle

func _ready() -> void:
	# Добавляем в группу врагов
	add_to_group("enemy")
	
	altitude = start_altitude
	is_grounded = false
	speed = max_speed * 0.3  # Стартовая скорость врага
	hp = 10  # Инициализируем HP при создании
	
	# Ищем игрока
	_find_player()

func _physics_process(delta: float) -> void:
	if not is_alive:
		# Дополнительная проверка - отключаем коллайдер если он еще активен
		var collision_shape = get_node_or_null("CollisionShape2D")
		if collision_shape and not collision_shape.disabled:
			collision_shape.disabled = true
		return
	
	# 1) ИИ: Поиск и поворот к игроку
	_ai_behavior(delta)
	
	# 2) Постоянное ускорение
	speed += accel * delta
	if speed > 0.0:
		speed -= drag_linear * delta
		if speed < 0.0:
			speed = 0.0
	
	speed = clamp(speed, 0.0, max_speed)
	
	# 3) Вертикаль (поддержание высоты как у игрока)
	var lift_from_speed: float = _lift_factor_from_speed(speed) * lift_speed_coeff * speed
	var lift_from_throttle: float = lift_throttle_coeff * 0.5  # Постоянная тяга
	var lift_total: float = lift_from_speed + lift_from_throttle
	var down: float = gravity_alt
	var a_alt: float = lift_total - down
	
	if not is_grounded:
		v_alt += a_alt * delta
		v_alt = clamp(v_alt, -max_climb_rate, max_climb_rate)
		altitude += v_alt * delta
		
		# Ограничение максимальной высоты полета
		var max_altitude: float = 180.0
		if altitude > max_altitude:
			altitude = max_altitude
			if v_alt > 0:
				v_alt = 0
		
		if altitude <= 0.0:
			altitude = 0.0
			v_alt = 0.0
			is_grounded = true
	else:
		altitude = 0.0
		v_alt = 0.0
		
		if speed > 0.0:
			speed -= ground_friction * delta
			if speed < 0.0:
				speed = 0.0
		
		if speed >= liftoff_speed and (lift_total - down) > liftoff_lift_margin:
			is_grounded = false
			v_alt = max(v_alt, 50.0)
			altitude += v_alt * delta
	
	# 4) Горизонталь
	var heading: Vector2 = Vector2.RIGHT.rotated(rotation)
	velocity = heading * speed
	move_and_slide()
	
	# 5) Заворачивание за края экрана
	_wrap_around_screen()
	
	# 6) Проверка столкновений с GroundKill
	_check_groundkill_collisions()

func _process(_dt: float) -> void:
	if is_alive and can_shoot and target_player:
		# Стреляем, если угол на игрока < 0.1 рад
		var angle_to_player: float = abs(_get_angle_to_player())
		if angle_to_player < aim_accuracy:
			_shoot()

func _ai_behavior(delta: float) -> void:
	# 1) Проверяем начальное состояние безопасности
	if is_starting:
		_handle_starting_safety(delta)
		return
	
	# 2) Проверяем угрозу GroundKill
	_detect_groundkill()
	
	# 3) Если есть угроза GroundKill, приоритет - избегание
	if groundkill_threat:
		_ai_avoid_groundkill(delta)
		return
	
	# 3) Поиск игрока, если его нет
	if not target_player or not is_instance_valid(target_player):
		_find_player()
		
		# Если игрок все еще не найден, ИИ продолжает полет
		if not target_player or not is_instance_valid(target_player):
			_ai_flight_without_target(delta)
			return
	
	# 4) Проверяем, жив ли игрок перед использованием target_player
	if target_player.has_method("is_alive") and not target_player.is_alive:
		# Игрок мертв, сбрасываем цель и переходим к полету без цели
		target_player = null
		_ai_flight_without_target(delta)
		# Ищем нового игрока после сброса цели
		_find_player()
		return
	
	# 5) Вычисляем угол к игроку
	var angle_to_player: float = _get_angle_to_player()
	
	# 6) Дополнительная проверка безопасности: не поворачиваемся к игроку, 
	# если это может направить нас в GroundKill
	var safe_to_turn = _is_safe_to_turn_to_player(angle_to_player)
	
	if safe_to_turn:
		# Поворачиваемся к игроку с сглаживанием
		var turn_direction: float = sign(angle_to_player)
		rotation += turn_direction * turn_speed * delta * turn_smoothing
	else:
		# Небезопасно поворачиваться к игроку, набираем высоту
		if altitude < groundkill_min_altitude * 1.5:
			v_alt = max(v_alt + 100.0 * delta, max_climb_rate * 0.7)
	
	# 7) Проверяем расстояние до игрока
	var distance_to_player: float = global_position.distance_to(target_player.global_position)
	if distance_to_player > detection_range:
		# Если игрок слишком далеко, ищем нового
		_find_player()
		
		# Если игрок не найден, переходим к полету без цели
		if not target_player or not is_instance_valid(target_player):
			_ai_flight_without_target(delta)

func _handle_starting_safety(delta: float) -> void:
	# Обрабатываем начальное состояние безопасности
	# В начале раунда ИИ должен набрать безопасную высоту перед преследованием игрока
	
	start_safety_time += delta
	
	# 1) Приоритет - набор безопасной высоты
	if altitude < groundkill_min_altitude * 1.5:  # Безопасная высота
		v_alt = max(v_alt + 100.0 * delta, max_climb_rate * 0.8)
	
	# 2) Небольшой поворот для естественного полета
	var random_turn: float = randf_range(-0.3, 0.3) * turn_speed * delta
	rotation += random_turn
	
	# 3) Увеличиваем скорость для набора высоты
	if speed < max_speed * 0.6:
		speed += accel * delta * 0.8
	
	# 4) Проверяем, можно ли перейти к нормальному поведению
	if altitude >= groundkill_min_altitude * 1.5 and start_safety_time > 2.0:
		is_starting = false
		print("ИИ переходит к нормальному поведению. Высота: ", altitude)
		_find_player()

func _ai_avoid_groundkill(delta: float) -> void:
	# ИИ избегает GroundKill - набирает высоту и поворачивает в сторону
	# ПРИОРИТЕТ: Полностью игнорируем игрока до устранения угрозы
	
	# 1) Приоритет - набор высоты для избегания GroundKill
	if altitude < groundkill_min_altitude * 2.0:  # Увеличиваем безопасную высоту
		v_alt = max(v_alt + 150.0 * delta, max_climb_rate * 0.9)
	
	# 2) Поворот в направлении избегания
	if abs(groundkill_avoidance_angle) > 0.01:  # Если есть угол для поворота
		var turn_direction: float = sign(groundkill_avoidance_angle)
		rotation += turn_direction * turn_speed * delta * groundkill_avoidance_strength
	
	# 3) Увеличиваем скорость для быстрого ухода от опасности
	if speed < max_speed * 0.8:
		speed += accel * delta * 1.5
	
	# 4) Периодически проверяем, можно ли вернуться к преследованию игрока
	last_player_search_time += delta
	if last_player_search_time > 0.5:  # Проверяем чаще при избегании
		_detect_groundkill()
		if not groundkill_threat:
			# Угроза миновала, возвращаемся к поиску игрока
			_find_player()
		last_player_search_time = 0.0

func _ai_flight_without_target(delta: float) -> void:
	# ИИ продолжает полет без цели - набирает высоту и скорость
	
	# Небольшой поворот в случайном направлении для естественного полета
	var random_turn: float = randf_range(-0.5, 0.5) * turn_speed * delta
	rotation += random_turn
	
	# Набираем высоту, если слишком низко
	if altitude < start_altitude * 1.5:
		# Увеличиваем вертикальную скорость для набора высоты
		v_alt = min(v_alt + 50.0 * delta, max_climb_rate * 0.8)
	
	# Поддерживаем хорошую скорость полета
	if speed < max_speed * 0.7:
		speed += accel * delta * 0.5  # Медленное ускорение
	
	# Периодически ищем игрока (каждые 2 секунды)
	last_player_search_time += delta
	if last_player_search_time > 2.0:
		_find_player()
		last_player_search_time = 0.0

func _is_safe_to_turn_to_player(angle_to_player: float) -> bool:
	# Проверяем, безопасно ли поворачиваться к игроку
	# Возвращаем false, если поворот может направить нас в GroundKill
	
	# Если мы слишком низко, не поворачиваемся к игроку
	if altitude <= groundkill_min_altitude:
		return false
	
	# Ищем GroundKill в сцене
	var groundkill_nodes = get_tree().get_nodes_in_group(ground_kill_group)
	if groundkill_nodes.size() == 0:
		var groundkill_node = get_tree().get_first_node_in_group(ground_kill_group)
		if not groundkill_node:
			groundkill_node = get_tree().current_scene.get_node_or_null(ground_kill_name)
		if groundkill_node:
			groundkill_nodes = [groundkill_node]
	
	# Проверяем каждую GroundKill
	for groundkill in groundkill_nodes:
		if not is_instance_valid(groundkill):
			continue
			
		var distance_to_groundkill = global_position.distance_to(groundkill.global_position)
		
		# Если GroundKill близко, проверяем направление поворота
		if distance_to_groundkill <= groundkill_detection_range * 1.5:
			var direction_to_groundkill = (groundkill.global_position - global_position).normalized()
			var current_direction = Vector2.RIGHT.rotated(rotation)
			var future_direction = Vector2.RIGHT.rotated(rotation + angle_to_player * 0.1)  # Предполагаемое направление
			
			# Если поворот к игроку приближает нас к GroundKill, это небезопасно
			var current_dot = current_direction.dot(direction_to_groundkill)
			var future_dot = future_direction.dot(direction_to_groundkill)
			
			if future_dot > current_dot:  # Поворот приближает к GroundKill
				return false
	
	return true

func _detect_groundkill() -> void:
	# Сбрасываем состояние угрозы
	var previous_threat = groundkill_threat
	groundkill_threat = false
	groundkill_avoidance_angle = 0.0
	
	# Ищем GroundKill в сцене
	var groundkill_nodes = get_tree().get_nodes_in_group(ground_kill_group)
	if groundkill_nodes.size() == 0:
		# Если группа не найдена, ищем по имени
		var groundkill_node = get_tree().get_first_node_in_group(ground_kill_group)
		if not groundkill_node:
			groundkill_node = get_tree().current_scene.get_node_or_null(ground_kill_name)
		
		if groundkill_node:
			groundkill_nodes = [groundkill_node]
	
	# Проверяем расстояние до каждой GroundKill
	for groundkill in groundkill_nodes:
		if not is_instance_valid(groundkill):
			continue
			
		var distance_to_groundkill = global_position.distance_to(groundkill.global_position)
		
		# Упрощенная логика: угроза если мы слишком низко И близко к GroundKill
		# В начале раунда используем более строгие условия
		var detection_range_multiplier = 1.0
		var altitude_threshold = groundkill_min_altitude
		
		if is_starting:
			detection_range_multiplier = 1.5  # Увеличиваем зону обнаружения в начале
			altitude_threshold = groundkill_min_altitude * 1.2  # Более строгий порог высоты
		
		if altitude <= altitude_threshold and distance_to_groundkill <= groundkill_detection_range * detection_range_multiplier:
			groundkill_threat = true
			groundkill_position = groundkill.global_position
			
			# Простое направление избегания: поворачиваем в сторону от GroundKill
			var direction_to_groundkill = (groundkill_position - global_position).normalized()
			
			# Определяем направление избегания
			var avoidance_direction: Vector2
			if direction_to_groundkill.x > 0:
				# GroundKill справа, поворачиваем влево (отрицательный угол)
				avoidance_direction = Vector2(-1, 0)
			else:
				# GroundKill слева, поворачиваем вправо (положительный угол)
				avoidance_direction = Vector2(1, 0)
			
			# Вычисляем угол поворота
			var current_direction = Vector2.RIGHT.rotated(rotation)
			groundkill_avoidance_angle = avoidance_direction.angle_to(current_direction)
			
			# Ограничиваем угол избегания
			groundkill_avoidance_angle = clamp(groundkill_avoidance_angle, -PI/3, PI/3)
			break
	
	# Обновляем отладочную информацию при изменении состояния
	if previous_threat != groundkill_threat:
		queue_redraw()

func _find_player() -> void:
	# Очищаем предыдущую ссылку
	target_player = null
	
	# Ищем игрока в группе "player"
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		for player in players:
			# Проверяем, что игрок жив и валиден
			if player.has_method("is_alive") and player.is_alive:
				target_player = player
				return
			elif not player.has_method("is_alive"):
				# Если у игрока нет метода is_alive, считаем его живым
				target_player = player
				return
	
	# Если группа не найдена или игроки мертвы, ищем по имени
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node and is_instance_valid(player_node):
		if player_node.has_method("is_alive") and player_node.is_alive:
			target_player = player_node
			return
		elif not player_node.has_method("is_alive"):
			target_player = player_node
			return
	
	# Последний вариант - поиск по имени сцены
	var scene = get_tree().current_scene
	if scene and scene.has_method("get_node"):
		var player = scene.get_node_or_null("Player")
		if player and is_instance_valid(player):
			if player.has_method("is_alive") and player.is_alive:
				target_player = player
				return
			elif not player.has_method("is_alive"):
				target_player = player
				return

func _get_angle_to_player() -> float:
	if not target_player or not is_instance_valid(target_player):
		return 0.0
	
	# Получаем размеры экрана для wrap-around логики
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_width: float = viewport_size.x
	
	# Вычисляем базовый вектор к игроку
	var base_vector: Vector2 = target_player.global_position - global_position
	
	# Если есть угроза GroundKill, НЕ используем wrap-around логику
	# Это предотвращает направление ИИ через GroundKill
	if groundkill_threat:
		# Используем только прямой путь к игроку
		var direction_to_player: Vector2 = base_vector.normalized()
		var current_direction: Vector2 = Vector2.RIGHT.rotated(rotation)
		return current_direction.angle_to(direction_to_player)
	
	# Рассматриваем три варианта: обычный, с смещением +screen_width и -screen_width
	var vectors: Array[Vector2] = [
		base_vector,  # Обычный вектор
		base_vector + Vector2(screen_width, 0),  # Смещение вправо
		base_vector - Vector2(screen_width, 0)   # Смещение влево
	]
	
	# Находим вектор с наименьшим расстоянием
	var shortest_vector: Vector2 = vectors[0]
	var shortest_distance: float = vectors[0].length()
	
	for i in range(1, vectors.size()):
		var distance: float = vectors[i].length()
		if distance < shortest_distance:
			shortest_distance = distance
			shortest_vector = vectors[i]
	
	# Нормализуем выбранный вектор и вычисляем угол
	var direction_to_player: Vector2 = shortest_vector.normalized()
	var current_direction: Vector2 = Vector2.RIGHT.rotated(rotation)
	
	return current_direction.angle_to(direction_to_player)

func _shoot() -> void:
	can_shoot = false
	var scene: PackedScene = preload("res://scenes/Bullet.tscn")
	var b: Node2D = scene.instantiate() as Node2D
	b.global_position = muzzle.global_position
	b.rotation = rotation
	var bullet_vel: Vector2 = Vector2.RIGHT.rotated(rotation) * 800.0 + velocity
	b.set("velocity", bullet_vel)
	
	# Пули врага игнорируют группу "enemy"
	b.ignore_group = "enemy"
	
	get_tree().current_scene.add_child(b)
	await get_tree().create_timer(fire_cooldown).timeout
	can_shoot = true

func apply_damage(amount: int) -> void:
	if not is_alive:
		return
	print("Enemy получил урон: ", amount, " HP до: ", hp)
	hp -= amount
	print("Enemy HP после: ", hp)
	if hp <= 0:
		explode_on_ground(global_position)

func explode_on_ground(hit_pos: Vector2) -> void:
	if not is_alive:
		return
	
	# СРАЗУ отключаем коллайдер, чтобы мертвый враг не создавал невидимую стену
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.disabled = true
	
	if explosion_scene:
		var ex: Node2D = explosion_scene.instantiate() as Node2D
		ex.global_position = hit_pos
		get_tree().current_scene.add_child(ex)
	
	is_alive = false
	visible = false
	set_physics_process(false)
	can_shoot = false
	
	# Очищаем состояние врага и полностью останавливаем движение
	speed = 0.0
	v_alt = 0.0
	altitude = 0.0
	is_grounded = true
	velocity = Vector2.ZERO  # Полностью останавливаем движение
	target_player = null  # Очищаем ссылку на игрока
	
	# Временно удаляем из группы врагов
	remove_from_group("enemy")
	
	if respawn_enabled:
		await get_tree().create_timer(respawn_delay).timeout
		_respawn()
	else:
		# Враг не респавнится, просто исчезает
		queue_free()

func _respawn() -> void:
	# Респавн врага в случайной позиции справа от экрана
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var spawn_x: float = viewport_size.x + 100.0  # За правым краем экрана с большим отступом
	var spawn_y: float = randf_range(100.0, viewport_size.y * 0.7)  # Случайная высота
	
	global_position = Vector2(spawn_x, spawn_y)
	altitude = start_altitude
	
	hp = 10  # Восстанавливаем HP врага
	speed = max_speed * 0.3  # Стартовая скорость врага
	v_alt = 0.0
	is_grounded = false
	velocity = Vector2.ZERO  # Убеждаемся, что нет остаточной скорости
	last_player_search_time = 0.0  # Сбрасываем таймер поиска игрока
	
	# Сбрасываем состояние избегания GroundKill
	groundkill_threat = false
	groundkill_avoidance_angle = 0.0
	groundkill_position = Vector2.ZERO
	
	# Сбрасываем начальное состояние
	is_starting = true
	start_safety_time = 0.0
	
	visible = true
	set_physics_process(true)
	is_alive = true
	can_shoot = true
	
	# Включаем коллайдер обратно
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.disabled = false
	
	# Возвращаем в группу врагов
	add_to_group("enemy")
	
	# Ищем игрока заново
	_find_player()

# === ОТЛАДОЧНАЯ ИНФОРМАЦИЯ ===
func _draw() -> void:
	if not is_alive:
		return
	
	# Рисуем зону обнаружения GroundKill
	if groundkill_threat:
		# Красный круг - зона угрозы
		draw_circle(Vector2.ZERO, groundkill_detection_range, Color(1, 0, 0, 0.3))
		
		# Стрелка направления избегания
		var avoidance_end = Vector2.RIGHT.rotated(groundkill_avoidance_angle) * 50
		draw_line(Vector2.ZERO, avoidance_end, Color.RED, 3.0)
		
		# Линия к GroundKill
		var groundkill_local = to_local(groundkill_position)
		draw_line(Vector2.ZERO, groundkill_local, Color.YELLOW, 2.0)
	else:
		# Зеленый круг - зона обнаружения
		draw_circle(Vector2.ZERO, groundkill_detection_range, Color(0, 1, 0, 0.1))

# === ВСПОМОГАТЕЛЬНОЕ ===
func _lift_factor_from_speed(s: float) -> float:
	if s <= stall_speed_alt:
		var k: float = (s - (stall_speed_alt - stall_soft)) / max(stall_soft, 1.0)
		k = clamp(k, 0.0, 1.0)
		return k * k
	return 1.0

func get_altitude() -> float:
	return altitude

func get_vertical_speed() -> float:
	return v_alt

func _check_groundkill_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var c: KinematicCollision2D = get_slide_collision(i)
		var col := c.get_collider()
		if col == null:
			continue
		
		var hit_kill: bool = false
		if col is Node:
			var n := col as Node
			if ground_kill_group != "" and n.is_in_group(ground_kill_group):
				hit_kill = true
			elif ground_kill_name != "" and n.name == ground_kill_name:
				hit_kill = true
		
		if hit_kill:
			explode_on_ground(c.get_position())
			return

func _wrap_around_screen() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_width: float = viewport_size.x
	var _screen_height: float = viewport_size.y
	
	# Заворачивание по горизонтали
	if global_position.x < 0:
		global_position.x = screen_width
	elif global_position.x > screen_width:
		global_position.x = 0
	
	# Ограничение высоты полета
	var max_height: float = 40.0
	
	if global_position.y < max_height:
		global_position.y = max_height
		if v_alt > 0:
			v_alt = 0
