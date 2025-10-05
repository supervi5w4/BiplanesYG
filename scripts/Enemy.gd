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
	
	# Устанавливаем правильную начальную позицию
	var ground_y: float = 706.0  # Y-координата земли (GroundKill)
	var initial_y: float = ground_y - start_altitude
	global_position.y = initial_y
	
	# Загружаем сцену взрыва
	var explosion_path = "res://scenes/Explosion.tscn"
	if ResourceLoader.exists(explosion_path):
		explosion_scene = load(explosion_path)
	
	# Ищем игрока при создании
	_find_player()
	
	# Запускаем задержку перед началом стрельбы
	_start_shooting_delay()

func _physics_process(delta: float) -> void:
	print("Enemy _physics_process called, is_alive: ", is_alive)
	if not is_alive:
		var collision_shape = get_node_or_null("CollisionShape2D")
		if collision_shape and not collision_shape.disabled:
			collision_shape.call_deferred("set_disabled", true)
		return

	# Отладка: проверяем состояние ИИ каждые несколько кадров
	if int(Time.get_ticks_msec() / 100.0) % 10 == 0:  # Каждые 1 секунду
		print("Enemy physics: pos=", global_position, " altitude=", altitude, " speed=", speed, " rotation=", rotation)

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

func _ai_movement(delta: float) -> void:
	if target_player == null or not is_instance_valid(target_player):
		# Если нет цели, ищем игрока
		_find_player()
		if target_player == null:
			# Если все еще нет цели, просто летим вперед с покачиваниями
			var wiggle := sin(Time.get_ticks_msec() * 0.001) * 0.1
			rotation += wiggle * delta
			return
	
	# Проверяем, жив ли игрок
	var player_alive = target_player.get("is_alive")
	if player_alive == false:
		target_player = null
		return
	
	# Вычисляем направление к игроку
	var to_player = target_player.global_position - global_position
	var distance_to_player = to_player.length()
	
	# Если игрок слишком далеко, летим к нему
	if distance_to_player > 98.0:
		var desired_angle = to_player.angle()
		var current_angle = rotation
		
		# Вычисляем разность углов
		var angle_diff = desired_angle - current_angle
		
		# Нормализуем угол к диапазону [-PI, PI]
		while angle_diff > PI:
			angle_diff -= 2.0 * PI
		while angle_diff < -PI:
			angle_diff += 2.0 * PI
		
		# Поворачиваемся к игроку с ограниченной скоростью
		var max_turn_rate = turn_speed * delta
		var turn_amount = clamp(angle_diff, -max_turn_rate, max_turn_rate)
		rotation += turn_amount
	else:
		# Если игрок близко, добавляем небольшие покачивания для более естественного движения
		var wiggle := sin(Time.get_ticks_msec() * 0.002) * 0.05
		rotation += wiggle * delta

func _process(_dt: float) -> void:
	if not is_alive:
		return
	
	# Простая стрельба по игроку
	if target_player and can_shoot and shooting_started:
		var to_player = (target_player.global_position - global_position).normalized()
		var angle_to_player = Vector2.RIGHT.rotated(rotation).angle_to(to_player)
		
		# Отладка каждые несколько кадров
		if int(Time.get_ticks_msec() / 100.0) % 20 == 0:  # Каждые 2 секунды
			print("Enemy aiming: angle_to_player=", abs(angle_to_player), " threshold=0.14")
		
		if abs(angle_to_player) < 0.14:  # Если игрок в прицеле
			_shoot()

# ==========================
#   VERTICAL & COLLISIONS
# ==========================
func _vertical_update(delta: float) -> void:
	# Отладка каждые несколько кадров
	if int(Time.get_ticks_msec() / 100.0) % 10 == 0:  # Каждую секунду
		print("Enemy vertical: altitude=", altitude, " v_alt=", v_alt, " is_grounded=", is_grounded, " speed=", speed)
	
	var lift_from_speed: float = _lift_factor_from_speed(speed) * lift_speed_coeff * speed
	var lift_from_throttle: float = lift_throttle_coeff * 0.5
	var lift_total: float = lift_from_speed + lift_from_throttle
	var down: float = gravity_alt
	var a_alt: float = lift_total - down

	if not is_grounded:
		v_alt += a_alt * delta
		v_alt = clamp(v_alt, -max_climb_rate, max_climb_rate)
		altitude += v_alt * delta
		
		# Отладка падения
		if v_alt < -50.0:  # Если падаем быстро
			print("Enemy falling fast: v_alt=", v_alt, " altitude=", altitude)
		
		var max_altitude: float = 200.0
		if altitude > max_altitude:
			altitude = max_altitude
			if v_alt > 0.0:
				v_alt = 0.0
		
		if altitude <= 0.0:
			altitude = 0.0
			v_alt = 0.0
			is_grounded = true
			print("Enemy grounded due to altitude <= 0.0")
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
	print("Enemy _check_groundkill_collisions called")
	# Отладка: проверяем расстояние до земли
	var ground_y: float = 706.0
	var distance_to_ground: float = ground_y - global_position.y
	if int(Time.get_ticks_msec() / 100.0) % 10 == 0:  # Каждую секунду
		print("Enemy ground check: pos_y=", global_position.y, " distance_to_ground=", distance_to_ground, " altitude=", altitude, " is_grounded=", is_grounded)
	
	var collision_count = get_slide_collision_count()
	if collision_count > 0:
		print("Enemy has ", collision_count, " collisions")
	
	for i in range(collision_count):
		var c: KinematicCollision2D = get_slide_collision(i)
		var col := c.get_collider()
		if col == null:
			continue
		print("Enemy collision with: ", col.name, " at position: ", c.get_position())
		var hit_kill: bool = false
		if col is Node:
			var n := col as Node
			if ground_kill_group != "" and n.is_in_group(ground_kill_group):
				hit_kill = true
				print("Enemy hit GroundKill by group: ", ground_kill_group, " at position: ", c.get_position())
			elif ground_kill_name != "" and n.name == ground_kill_name:
				hit_kill = true
				print("Enemy hit GroundKill by name: ", ground_kill_name, " at position: ", c.get_position())
		if hit_kill:
			print("Enemy exploding due to GroundKill collision at position: ", c.get_position())
			_explode(c.get_position())
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
	if target_player:
		print("Enemy shooting at player! Enemy pos: ", global_position, " Player pos: ", target_player.global_position)
	else:
		print("Enemy shooting at player! Enemy pos: ", global_position, " Player pos: ", "no target")
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

func apply_damage(amount: int) -> void:
	print("Enemy apply_damage called with amount: ", amount, " is_alive: ", is_alive, " invulnerable: ", invulnerable)
	if not is_alive or invulnerable:
		print("Enemy damage blocked - not alive or invulnerable")
		return
	
	print("Enemy taking damage: ", amount, " HP before: ", hp)
	hp -= amount
	print("Enemy HP after damage: ", hp)
	
	if hp <= 0:
		print("Enemy exploding due to HP <= 0")
		_explode(global_position)

func _explode(hit_pos: Vector2) -> void:
	if not is_alive:
		return
	
	print("Enemy _explode called at position: ", hit_pos, " current position: ", global_position)
	
	# Отключаем коллайдер
	var collision_shape = get_node_or_null("CollisionShape2D")
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
	
	print("Enemy exploded, respawn in ", respawn_delay, " seconds")
	
	# Респавн или удаление
	if respawn_enabled:
		await get_tree().create_timer(respawn_delay).timeout
		_respawn()
	else:
		queue_free()

func _respawn() -> void:
	# Сразу устанавливаем неуязвимость для защиты от пуль
	invulnerable = true
	
	# Используем точку спавна если она задана
	if spawn_path and has_node(spawn_path):
		var spawn_node = get_node(spawn_path)
		print("Enemy respawn at spawn point: ", spawn_node.global_position)
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
		print("Enemy respawn at fallback position: ", spawn_position)
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
	
	print("Enemy respawned successfully at: ", global_position, " altitude: ", altitude)
	
	# Ищем игрока
	_find_player()
	
	# Запускаем задержку перед началом стрельбы
	_start_shooting_delay()
	
	# Временная неуязвимость (уже установлена в начале функции)
	await get_tree().create_timer(invuln_time).timeout
	invulnerable = false
	print("Enemy invulnerability ended")

func _find_player() -> void:
	target_player = null
	print("Enemy searching for player...")
	
	var players := get_tree().get_nodes_in_group("player")
	print("Found players in group: ", players.size())
	for p in players:
		var alive_prop: bool = p.get("is_alive")
		print("Player ", p.name, " is_alive: ", alive_prop)
		if alive_prop == false:
			continue
		target_player = p
		print("Enemy found target player: ", p.name, " at position: ", p.global_position)
		return
	
	var scene := get_tree().current_scene
	if scene:
		var pl := scene.get_node_or_null("Player")
		if pl and is_instance_valid(pl):
			var alive_prop2: bool = pl.get("is_alive")
			print("Found Player node directly, is_alive: ", alive_prop2)
			if alive_prop2 != false:
				target_player = pl
				print("Enemy found target player directly: ", pl.name, " at position: ", pl.global_position)
	
	if target_player == null:
		print("Enemy could not find any player!")

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

func _start_shooting_delay() -> void:
	shooting_started = false
	await get_tree().create_timer(shooting_delay).timeout
	shooting_started = true
	print("Enemy started shooting after delay")
