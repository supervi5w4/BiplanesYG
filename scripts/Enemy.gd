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
	# Поиск игрока, если его нет
	if not target_player or not is_instance_valid(target_player):
		_find_player()
		
		# Если игрок все еще не найден, ИИ продолжает полет
		if not target_player or not is_instance_valid(target_player):
			_ai_flight_without_target(delta)
			return
	
	# Вычисляем угол к игроку
	var angle_to_player: float = _get_angle_to_player()
	
	# Поворачиваемся к игроку с сглаживанием
	var turn_direction: float = sign(angle_to_player)
	rotation += turn_direction * turn_speed * delta * turn_smoothing
	
	# Проверяем расстояние до игрока
	var distance_to_player: float = global_position.distance_to(target_player.global_position)
	if distance_to_player > detection_range:
		# Если игрок слишком далеко, ищем нового
		_find_player()
		
		# Если игрок не найден, переходим к полету без цели
		if not target_player or not is_instance_valid(target_player):
			_ai_flight_without_target(delta)

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
	
	var direction_to_player: Vector2 = (target_player.global_position - global_position).normalized()
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
