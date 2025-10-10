extends CharacterBody2D
# ─────────────────────────────────────────────────────────────────────────────
# Enemy.gd — МАКСИМАЛЬНО ПРОСТОЙ ИИ (как Player.gd)
# ─────────────────────────────────────────────────────────────────────────────

# === БАЗОВОЕ ДВИЖЕНИЕ (как у игрока) ===
@export var turn_speed: float = 2.8
@export var accel: float = 700.0
@export var brake_power: float = 800.0
@export var max_speed: float = 300.0
@export var drag_linear: float = 0.9

# === МОДИФИКАЦИЯ СКОРОСТИ ПО ОРИЕНТАЦИИ ===
@export var orientation_speed_factor: float = 0.25  # Насколько сильно ориентация влияет на скорость (0.0-1.0)
@export var max_orientation_penalty: float = 0.5   # Максимальное снижение скорости при неоптимальной ориентации

# === ВЫСОТА (как у игрока) ===
@export var start_altitude: float = 120.0
@export var gravity_alt: float = 220.0
@export var lift_speed_coeff: float = 0.9
@export var lift_throttle_coeff: float = 180.0  # Увеличиваем для лучшего поддержания высоты
@export var stall_speed_alt: float = 100.0  # Уменьшаем для возможности полета на меньшей скорости
@export var stall_soft: float = 40.0
@export var max_climb_rate: float = 220.0

# === НАЗЕМНЫЙ РЕЖИМ ===
@export var ground_friction: float = 180.0
@export var liftoff_speed: float = 150.0
@export var liftoff_lift_margin: float = 25.0

# === СРЫВ ПОТОКА (STALL) ===
@export var stall_speed_threshold: float = 40.0  # Порог скорости для срыва
@export var stall_drop_rate: float = 160.0  # Скорость падения при срыве
@export var stall_turn_rate: float = 2.5  # Скорость разворота носом вниз

# === ПАТРУЛИРОВАНИЕ ===
@export var idle_patrol_angle: float = PI  # Желаемый курс при патрулировании (PI = 180° = влево)

# === СТРЕЛЬБА ===
@export var fire_cooldown: float = 0.8
@export var bullet_speed: float = 820.0
@export var shooting_delay: float = 2.0  # Задержка перед началом стрельбы

# === ВЗРЫВ / РЕСПАВН ===
@export var explosion_scene: PackedScene
@export var spawn_path: NodePath
@export var respawn_delay: float = 3.0
@export var respawn_enabled: bool = true
@export var invuln_time: float = 1.0

# === GroundKill ===
@export var ground_kill_group: String = "GroundKill"
@export var ground_kill_name: String = "GroundKill"

# === ЖИЗНИ ===
@export var max_lives: int = 5
var lives: int

# === СОСТОЯНИЕ (как у игрока) ===
var speed: float = 0.0
var altitude: float = 0.0
var v_alt: float = 0.0
var is_grounded: bool = false

var hp: int = 10
var is_alive: bool = true
var can_shoot: bool = true
var invulnerable: bool = false
var shooting_started: bool = false

var target_player: Node2D = null
var target_life_pickup: Node2D = null  # Целевое сердечко для подбора

# Геттеры для проверки состояния
func get_is_alive() -> bool:
	return is_alive

func is_invulnerable() -> bool:
	return invulnerable

@onready var muzzle: Node2D = $Muzzle

func _ready() -> void:
	add_to_group("enemy")
	altitude = start_altitude
	is_grounded = false
	speed = max_speed * 0.6  # Увеличиваем начальную скорость для поддержания высоты
	hp = 10
	
	# Инициализируем жизни
	lives = max_lives
	
	# Устанавливаем правильную начальную позицию
	var ground_y: float = 706.0  # Y-координата земли (GroundKill)
	var initial_y: float = ground_y - start_altitude
	global_position.y = initial_y
	
	# Загружаем сцену взрыва
	var explosion_path = "res://scenes/Explosion.tscn"
	if ResourceLoader.exists(explosion_path):
		explosion_scene = load(explosion_path)
	
	# Уведомляем HUD о начальном количестве жизней
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud:
		hud.update_enemy_lives(lives)
	
	# Ищем игрока при создании
	_find_player()
	
	# Запускаем задержку перед началом стрельбы
	_start_shooting_delay()

func _physics_process(delta: float) -> void:
	if not is_alive:
		var collision_shape = get_node_or_null("CollisionShape2D")
		if collision_shape and not collision_shape.disabled:
			collision_shape.call_deferred("set_disabled", true)
		return

	# Периодически ищем игрока (каждые 2 секунды)
	if int(Time.get_ticks_msec() / 2000.0) % 2 == 0 and target_player == null:
		_find_player()

	# === УМНОЕ ДВИЖЕНИЕ К ИГРОКУ ===
	_ai_movement(delta)
	
	# === СКОРОСТЬ ПО КУРСУ + СОПРОТИВЛЕНИЕ ===
	speed += accel * delta
	if speed > 0.0:
		speed -= drag_linear * delta
	if speed < 0.0:
		speed = 0.0
	
	# Применяем модификатор скорости на основе ориентации
	var orientation_modifier = _get_orientation_speed_modifier()
	var effective_max_speed = max_speed * orientation_modifier
	speed = clamp(speed, 0.0, effective_max_speed)

	# === ВЕРТИКАЛЬНАЯ ДИНАМИКА ===
	_vertical_update(delta)

	# === ГОРИЗОНТАЛЬНОЕ ДВИЖЕНИЕ ===
	var heading: Vector2 = Vector2.RIGHT.rotated(rotation)
	velocity = heading * speed
	move_and_slide()

	# === ГРАНИЦЫ И КОЛЛИЗИИ ===
	_wrap_around_screen()
	_check_groundkill_collisions()
	_check_plane_collisions()

func _ai_movement(delta: float) -> void:
	# Ищем ближайшее сердечко если нужно
	_find_nearest_life_pickup()
	
	# Решаем, куда лететь: к игроку или к сердечку
	var target_position: Vector2
	var is_chasing_pickup = false
	
	# Если у врага не хватает жизней и есть сердечко, летим за ним с вероятностью 70%
	if lives < max_lives and target_life_pickup != null and is_instance_valid(target_life_pickup):
		var distance_to_pickup = global_position.distance_to(target_life_pickup.global_position)
		# Если сердечко близко или у нас мало жизней, летим за ним
		if distance_to_pickup < 400.0 or lives <= 2:
			# С вероятностью 70% выбираем сердечко
			if randf() < 0.7:
				target_position = target_life_pickup.global_position
				is_chasing_pickup = true
	
	# Если не летим за сердечком, атакуем игрока
	if not is_chasing_pickup:
		if target_player == null or not is_instance_valid(target_player):
			# Если нет цели, ищем игрока
			_find_player()
			if target_player == null:
				# Если все еще нет цели, плавно сближаемся с idle_patrol_angle
				var angle_diff = wrapf(idle_patrol_angle - rotation, -PI, PI)
				var max_turn_rate = turn_speed * delta
				var turn_amount = clamp(angle_diff, -max_turn_rate, max_turn_rate)
				rotation += turn_amount
				
				# После достижения курса добавляем небольшое покачивание
				if abs(angle_diff) < 0.05:  # Если почти достигли целевого угла
					var wiggle := sin(Time.get_ticks_msec() * 0.001) * 0.02
					rotation += wiggle * delta
				return
		
		# Проверяем, жив ли игрок
		var player_alive = target_player.get("is_alive")
		if player_alive == false:
			target_player = null
			return
		
		target_position = target_player.global_position
	
	# Вычисляем направление к цели
	var to_target = target_position - global_position
	var distance_to_target = to_target.length()
	
	# Определяем минимальную дистанцию в зависимости от цели
	var min_distance = 20.0 if is_chasing_pickup else 98.0
	
	# Если цель далеко, летим к ней
	if distance_to_target > min_distance:
		var desired_angle = to_target.angle()
		var current_angle = rotation
		
		# Вычисляем разность углов
		var angle_diff = desired_angle - current_angle
		
		# Нормализуем угол к диапазону [-PI, PI]
		while angle_diff > PI:
			angle_diff -= 2.0 * PI
		while angle_diff < -PI:
			angle_diff += 2.0 * PI
		
		# Поворачиваемся к цели с ограниченной скоростью
		var max_turn_rate = turn_speed * delta
		var turn_amount = clamp(angle_diff, -max_turn_rate, max_turn_rate)
		rotation += turn_amount
	else:
		# Если цель близко, добавляем небольшие покачивания для более естественного движения
		var wiggle := sin(Time.get_ticks_msec() * 0.002) * 0.05
		rotation += wiggle * delta

func _process(_dt: float) -> void:
	if not is_alive:
		return
	
	# Простая стрельба по игроку
	if target_player and can_shoot and shooting_started:
		var to_player = (target_player.global_position - global_position).normalized()
		var angle_to_player = Vector2.RIGHT.rotated(rotation).angle_to(to_player)
		
		if abs(angle_to_player) < 0.14:  # Если игрок в прицеле
			_shoot()

# ==========================
#   VERTICAL & COLLISIONS
# ==========================
func _vertical_update(delta: float) -> void:
	var lift_from_speed: float = _lift_factor_from_speed(speed) * lift_speed_coeff * speed
	var lift_from_throttle: float = lift_throttle_coeff * 0.5
	
	# Масштабируем подъёмную силу от тяги в зависимости от скорости
	lift_from_throttle *= clamp(speed / stall_speed_threshold, 0.0, 1.0)
	
	var lift_total: float = lift_from_speed + lift_from_throttle
	var down: float = gravity_alt
	
	# === СРЫВ ПОТОКА (STALL) - применяем ДО расчёта v_alt ===
	var is_stalling: bool = not is_grounded and speed <= stall_speed_threshold
	if is_stalling:
		# При срыве отключаем подъёмную силу полностью
		lift_total = 0.0
		# Увеличиваем гравитацию при срыве
		if speed <= 0.1:  # Практически нулевая скорость
			# Мгновенно направляем носом вниз
			rotation = lerp_angle(rotation, PI / 2.0, stall_turn_rate * delta * 3.0)
			# Усиленная гравитация для быстрого падения
			down = gravity_alt * 2.5
		else:
			# Обычный срыв при низкой скорости
			rotation = lerp_angle(rotation, PI / 2.0, stall_turn_rate * delta)
			# Увеличенная гравитация
			down = gravity_alt * 1.8
	
	var a_alt: float = lift_total - down

	if not is_grounded:
		v_alt += a_alt * delta
		v_alt = clamp(v_alt, -max_climb_rate, max_climb_rate)
		altitude += v_alt * delta
		
		var max_altitude: float = 200.0
		if altitude > max_altitude:
			altitude = max_altitude
			if v_alt > 0.0:
				v_alt = 0.0
		
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

func _check_groundkill_collisions() -> void:
	var collision_count = get_slide_collision_count()
	
	for i in range(collision_count):
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
			_explode(c.get_position(), false)  # Не убит игроком - столкновение с землей
			return

func _wrap_around_screen() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var w := viewport_size.x
	var h := viewport_size.y
	if global_position.x < 0.0:
		global_position.x = w
	elif global_position.x > w:
		global_position.x = 0.0
	var pad := 40.0
	var min_height := 150.0
	if global_position.y < min_height:
		global_position.y = min_height
		if v_alt < 0.0:
			v_alt = 0.0
	elif global_position.y > h - pad:
		global_position.y = h - pad
		if v_alt > 0.0:
			v_alt = 0.0

# ==========================
#   SHOOT / DAMAGE / FX
# ==========================
func _shoot() -> void:
	can_shoot = false
	var scene: PackedScene = preload("res://scenes/Bullet.tscn")
	var b := scene.instantiate() as Node2D
	b.global_position = muzzle.global_position
	b.rotation = rotation
	var bullet_vel: Vector2 = Vector2.RIGHT.rotated(rotation) * bullet_speed + velocity
	if "velocity" in b:
		b.set("velocity", bullet_vel)
	if "ignore_group" in b:
		b.set("ignore_group", "enemy")
	get_tree().current_scene.add_child(b)
	await get_tree().create_timer(fire_cooldown).timeout
	can_shoot = true

func apply_damage(amount: int, from_player: bool = true) -> void:
	if not is_alive or invulnerable:
		return
	
	hp -= amount
	
	if hp <= 0:
		_explode(global_position, from_player)

func _explode(hit_pos: Vector2, killed_by_player: bool = true) -> void:
	if not is_alive:
		return
	
	
	# Регистрируем убийство, если враг был убит игроком
	if killed_by_player:
		GameState.add_kill()
	
	# Объявляем переменную для коллайдера
	var collision_shape = get_node_or_null("CollisionShape2D")
	
	# Уменьшаем жизни
	lives -= 1
	
	# Уведомляем HUD о изменении жизней
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud:
		hud.update_enemy_lives(lives)
	
	# Проверяем, не закончились ли жизни
	if lives <= 0:
		# Игра окончена - отключаем респавн и вызываем GameState.end_game() с результатом "Победа"
		respawn_enabled = false
		GameState.end_game("Победа")
		
		# Отключаем коллайдер
		collision_shape = get_node_or_null("CollisionShape2D")
		if collision_shape:
			collision_shape.call_deferred("set_disabled", true)

		# Создаем взрыв
		if explosion_scene:
			var ex: Node2D = explosion_scene.instantiate() as Node2D
			if ex:
				ex.global_position = hit_pos
				get_tree().current_scene.add_child(ex)

		# Устанавливаем состояние смерти
		is_alive = false
		visible = false
		set_physics_process(false)
		can_shoot = false
		
		# Останавливаем движение
		speed = 0.0
		v_alt = 0.0
		altitude = 0.0
		is_grounded = true
		velocity = Vector2.ZERO
		
		# Очищаем цели
		target_player = null
		remove_from_group("enemy")
		
		
		# Удаляем врага без респавна
		queue_free()
		return
	
	# Если жизни остались, продолжаем с обычной логикой респавна
	respawn_enabled = true
	
	# Отключаем коллайдер
	if collision_shape:
		collision_shape.call_deferred("set_disabled", true)

	# Создаем взрыв
	if explosion_scene:
		var ex: Node2D = explosion_scene.instantiate() as Node2D
		if ex:
			ex.global_position = hit_pos
			get_tree().current_scene.add_child(ex)

	# Устанавливаем состояние смерти
	is_alive = false
	visible = false
	set_physics_process(false)
	can_shoot = false
	
	# Останавливаем движение
	speed = 0.0
	v_alt = 0.0
	altitude = 0.0
	is_grounded = true
	velocity = Vector2.ZERO
	
	# Очищаем цели
	target_player = null
	remove_from_group("enemy")
	
	
	# Респавн
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()

func _respawn() -> void:
	# Сразу устанавливаем неуязвимость для защиты от пуль
	invulnerable = true
	
	# Используем точку спавна если она задана
	if spawn_path and has_node(spawn_path):
		var spawn_node = get_node(spawn_path)
		# Рассчитываем правильную Y-координату на основе высоты над землей
		var ground_y: float = 706.0  # Y-координата земли (GroundKill)
		var spawn_y: float = ground_y - start_altitude
		global_position = Vector2(spawn_node.global_position.x, spawn_y)
		altitude = start_altitude
	else:
		# Fallback к случайной позиции справа от экрана
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var spawn_x: float = viewport_size.x + 200.0
		var ground_y: float = 706.0  # Y-координата земли (GroundKill)
		var spawn_y: float = ground_y - start_altitude
		var spawn_position = Vector2(spawn_x, spawn_y)
		global_position = spawn_position
		altitude = start_altitude
	
	# Устанавливаем правильную ориентацию - горизонтальный полет
	rotation = PI  # ИИ летит влево (180 градусов)
	
	hp = 10
	speed = max_speed * 0.6  # Увеличиваем начальную скорость для поддержания высоты
	v_alt = 0.0
	is_grounded = false
	velocity = Vector2.ZERO
	
	# Восстанавливаем видимость и физику
	visible = true
	set_physics_process(true)
	is_alive = true
	can_shoot = true
	shooting_started = false
	
	# Включаем коллайдер
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.call_deferred("set_disabled", false)
	
	# Возвращаем в группу
	add_to_group("enemy")
	
	
	# Ищем игрока
	_find_player()
	
	# Запускаем задержку перед началом стрельбы
	_start_shooting_delay()
	
	# Временная неуязвимость (уже установлена в начале функции)
	await get_tree().create_timer(invuln_time).timeout
	invulnerable = false

func _find_player() -> void:
	target_player = null
	
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		var alive_prop: bool = p.get("is_alive")
		if alive_prop == false:
			continue
		target_player = p
		return
	
	var scene := get_tree().current_scene
	if scene:
		var pl := scene.get_node_or_null("Player")
		if pl and is_instance_valid(pl):
			var alive_prop2: bool = pl.get("is_alive")
			if alive_prop2 != false:
				target_player = pl

func _find_nearest_life_pickup() -> void:
	"""Ищет ближайшее сердечко на карте"""
	# Сбрасываем старую цель если она уже недействительна
	if target_life_pickup != null and not is_instance_valid(target_life_pickup):
		target_life_pickup = null
	
	# Если уже есть валидная цель и мы не на максимуме жизней, продолжаем её преследовать
	if target_life_pickup != null and lives < max_lives:
		return
	
	# Если жизни заполнены, сбрасываем цель
	if lives >= max_lives:
		target_life_pickup = null
		return
	
	# Ищем все сердечки на сцене
	var scene = get_tree().current_scene
	if not scene:
		return
	
	var pickups = []
	for child in scene.get_children():
		if child.is_in_group("life_pickup") or child.name.contains("LifePickup"):
			pickups.append(child)
	
	# Если сердечек нет, выходим
	if pickups.is_empty():
		target_life_pickup = null
		return
	
	# Находим ближайшее сердечко
	var closest_pickup = null
	var closest_distance = INF
	
	for pickup in pickups:
		if is_instance_valid(pickup):
			var distance = global_position.distance_to(pickup.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_pickup = pickup
	
	target_life_pickup = closest_pickup

func add_life(amount: int = 1) -> void:
	"""Добавляет жизни врагу (не превышает max_lives)"""
	lives = clamp(lives + amount, 0, max_lives)
	
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud:
		hud.update_enemy_lives(lives)
	
	# Сбрасываем цель на сердечко после подбора
	target_life_pickup = null

# ==========================
#     HELPERS
# ==========================
func _lift_factor_from_speed(s: float) -> float:
	if s <= stall_speed_alt:
		var k: float = (s - (stall_speed_alt - stall_soft)) / max(stall_soft, 1.0)
		k = clamp(k, 0.0, 1.0)
		return k * k
	return 1.0

func _get_orientation_speed_modifier() -> float:
	# Нормализуем угол поворота к диапазону [-PI, PI]
	var normalized_rotation = fmod(rotation + PI, 2.0 * PI) - PI
	
	# Оптимальная ориентация - горизонтальный полет (rotation = 0)
	# Чем больше отклонение от горизонтали, тем больше штраф к скорости
	var orientation_penalty = abs(normalized_rotation) / PI  # 0.0 = горизонтально, 1.0 = вертикально
	
	# Применяем штраф с учетом настроек
	var speed_modifier = 1.0 - (orientation_penalty * orientation_speed_factor * max_orientation_penalty)
	
	return clamp(speed_modifier, 1.0 - max_orientation_penalty, 1.0)

func _check_plane_collisions() -> void:
	# Проверяем столкновения с игроком
	for i in range(get_slide_collision_count()):
		var c: KinematicCollision2D = get_slide_collision(i)
		var col := c.get_collider()
		if col == null:
			continue
		
		# Проверяем, что это игрок
		if col is Node and col.is_in_group("player"):
			var player = col as Node
			# Проверяем, что игрок жив и не неуязвим
			if player.has_method("get_is_alive") and player.get_is_alive():
				if not (player.has_method("is_invulnerable") and player.is_invulnerable()):
					# Столкновение! Взрываем оба самолета
					_explode(c.get_position(), false)  # Столкновение, а не убийство игроком
					# Также взрываем игрока
					if player.has_method("explode_on_ground"):
						player.explode_on_ground(c.get_position())
					return

func _start_shooting_delay() -> void:
	shooting_started = false
	await get_tree().create_timer(shooting_delay).timeout
	shooting_started = true
