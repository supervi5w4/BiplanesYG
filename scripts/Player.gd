extends CharacterBody2D
# ─────────────────────────────────────────────────────────────────────────────
# Player.gd — классическое управление + взрыв/респаун и GroundKill
# ─────────────────────────────────────────────────────────────────────────────

# === КЛАССИЧЕСКОЕ ГОРИЗОНТАЛЬНОЕ ДВИЖЕНИЕ ===
@export var turn_speed: float = 3.2
@export var accel: float = 900.0
@export var brake_power: float = 1100.0
@export var max_speed: float = 350.0
@export var drag_linear: float = 0.85
@export var fire_cooldown: float = 0.14

# === МОДИФИКАЦИЯ СКОРОСТИ ПО ОРИЕНТАЦИИ ===
@export var orientation_speed_factor: float = 0.3  # Насколько сильно ориентация влияет на скорость (0.0-1.0)
@export var max_orientation_penalty: float = 0.6   # Максимальное снижение скорости при неоптимальной ориентации

# === ПСЕВДО-ВЕРТИКАЛЬ (высота) ===
@export var start_altitude: float = 140.0
@export var gravity_alt: float = 260.0
@export var lift_speed_coeff: float = 0.9
@export var lift_throttle_coeff: float = 120.0
@export var stall_speed_alt: float = 140.0
@export var stall_soft: float = 40.0
@export var max_climb_rate: float = 240.0

# === НАЗЕМНЫЙ РЕЖИМ ===
@export var ground_friction: float = 220.0
@export var liftoff_speed: float = 180.0
@export var liftoff_lift_margin: float = 30.0

# === ВЗРЫВ/РЕСПАУН ===
@export var explosion_scene: PackedScene
@export var spawn_path: NodePath
@export var respawn_delay: float = 3.0
@export var invuln_time: float = 0.8

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
var invulnerable: bool = false

# Геттер для is_alive для совместимости с Enemy.gd
func get_is_alive() -> bool:
	return is_alive

@onready var muzzle: Node2D = $Muzzle

func _ready() -> void:
	# Добавляем в группу игроков
	add_to_group("player")
	
	altitude = start_altitude
	is_grounded = false
	speed = max_speed * 0.5  # Стартовая скорость при запуске игры
	hp = 10  # Инициализируем HP при создании
	
	# Загружаем сцену взрыва
	explosion_scene = load("res://scenes/Explosion.tscn")

func _physics_process(delta: float) -> void:
	if not is_alive:
		# Дополнительная проверка - отключаем коллайдер если он еще активен
		var collision_shape = get_node_or_null("CollisionShape2D")
		if collision_shape and not collision_shape.disabled:
			collision_shape.disabled = true
		return

	# 1) Поворот
	var turn: float = Input.get_action_strength("turn_right") - Input.get_action_strength("turn_left")
	rotation += turn * turn_speed * delta

	# 2) Газ/тормоз
	var thrust_in: float = Input.get_action_strength("thrust")
	var brake_in: float = Input.get_action_strength("brake")

	if thrust_in > 0.0:
		speed += accel * thrust_in * delta
	if brake_in > 0.0:
		speed -= brake_power * brake_in * delta

	if speed > 0.0:
		speed -= drag_linear * delta
		if speed < 0.0:
			speed = 0.0

	# Применяем модификатор скорости на основе ориентации
	var orientation_modifier = _get_orientation_speed_modifier()
	var effective_max_speed = max_speed * orientation_modifier
	speed = clamp(speed, 0.0, effective_max_speed)

	# 3) Вертикаль
	var lift_from_speed: float = _lift_factor_from_speed(speed) * lift_speed_coeff * speed
	var lift_from_throttle: float = lift_throttle_coeff * thrust_in
	var lift_total: float = lift_from_speed + lift_from_throttle
	var down: float = gravity_alt
	var a_alt: float = lift_total - down

	if not is_grounded:
		v_alt += a_alt * delta
		v_alt = clamp(v_alt, -max_climb_rate, max_climb_rate)
		altitude += v_alt * delta

		# Ограничение максимальной высоты полета
		var max_altitude: float = 300.0  # Максимальная высота полета
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

		if speed >= liftoff_speed and (lift_total - down) > liftoff_lift_margin and thrust_in > 0.0:
			is_grounded = false
			v_alt = max(v_alt, 60.0)
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
	if is_alive and Input.is_action_just_pressed("shoot") and can_shoot:
		_shoot()

func _shoot() -> void:
	can_shoot = false
	var scene: PackedScene = preload("res://scenes/Bullet.tscn")
	var b: Node2D = scene.instantiate() as Node2D
	b.global_position = muzzle.global_position
	b.rotation = rotation
	var bullet_vel: Vector2 = Vector2.RIGHT.rotated(rotation) * 900.0 + velocity
	b.set("velocity", bullet_vel)
	b.ignore_group = "player"
	get_tree().current_scene.add_child(b)
	await get_tree().create_timer(fire_cooldown).timeout
	can_shoot = true

func apply_damage(amount: int) -> void:
	if invulnerable or not is_alive:
		return
	hp -= amount
	if hp <= 0:
		explode_on_ground(global_position)

# ───────────── ВЗРЫВ / РЕСПАУН ─────────────
func explode_on_ground(hit_pos: Vector2) -> void:
	if not is_alive:
		return

	# СРАЗУ отключаем коллайдер, чтобы мертвый игрок не создавал невидимую стену
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.call_deferred("set_disabled", true)

	if explosion_scene:
		var ex: Node2D = explosion_scene.instantiate() as Node2D
		ex.global_position = hit_pos
		get_tree().current_scene.add_child(ex)

	is_alive = false
	visible = false
	set_physics_process(false)
	can_shoot = false

	speed = 0.0
	v_alt = 0.0
	altitude = 0.0
	is_grounded = true
	velocity = Vector2.ZERO  # Полностью останавливаем движение

	await get_tree().create_timer(respawn_delay).timeout
	_respawn()

func _respawn() -> void:
	# Используем точку спавна если она задана
	print("Player spawn_path: ", spawn_path)
	print("Player has_node(spawn_path): ", has_node(spawn_path) if spawn_path else "spawn_path is null")
	
	if spawn_path and has_node(spawn_path):
		var spawn_node = get_node(spawn_path)
		print("Player respawn at spawn point: ", spawn_node.global_position)
		global_position = spawn_node.global_position
	else:
		# Fallback к жестко заданной позиции
		print("Player respawn at fallback position: ", Vector2(81, 108))
		global_position = Vector2(81, 108)
	
	# Устанавливаем правильную ориентацию - горизонтальный полет
	rotation = 0.0
	altitude = start_altitude

	hp = 10
	speed = max_speed * 0.5  # Стартовая скорость - половина от максимальной
	v_alt = 0.0
	is_grounded = false
	velocity = Vector2.ZERO  # Убеждаемся, что нет остаточной скорости

	visible = true
	set_physics_process(true)
	is_alive = true
	can_shoot = true
	
	# Включаем коллайдер обратно
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.call_deferred("set_disabled", false)
	
	# Убеждаемся, что игрок в группе "player"
	if not is_in_group("player"):
		add_to_group("player")

	invulnerable = true
	await get_tree().create_timer(invuln_time).timeout
	invulnerable = false

# === ВСПОМОГАТЕЛЬНОЕ ===
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

# === ЗАВОРАЧИВАНИЕ ЗА КРАЯ ЭКРАНА ===
func _wrap_around_screen() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_width: float = viewport_size.x
	var _screen_height: float = viewport_size.y
	
	# Заворачивание по горизонтали
	if global_position.x < 0:
		global_position.x = screen_width
	elif global_position.x > screen_width:
		global_position.x = 0
	
	# Ограничение высоты полета - самолет всегда остается в зоне видимости
	# Увеличиваем минимальную высоту, чтобы избежать GroundKill (Y=706)
	var max_height: float = 5.0  # Минимальная высота от верха экрана
	
	if global_position.y < max_height:
		# Если самолет поднимается слишком высоко, ограничиваем его высоту
		global_position.y = max_height
		# Останавливаем вертикальное движение вверх
		if v_alt > 0:
			v_alt = 0
