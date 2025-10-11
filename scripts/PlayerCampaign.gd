extends CharacterBody2D
# ─────────────────────────────────────────────────────────────────────────────
# PlayerCampaign.gd — игрок для режима кампании с системой HP
# ─────────────────────────────────────────────────────────────────────────────

signal player_dead

# === КЛАССИЧЕСКОЕ ГОРИЗОНТАЛЬНОЕ ДВИЖЕНИЕ ===
@export var turn_speed: float = 2.6
@export var accel: float = 650.0
@export var brake_power: float = 1100.0
@export var max_speed: float = 250.0
@export var drag_linear: float = 0.85
@export var fire_cooldown: float = 0.14

# === МОДИФИКАЦИЯ СКОРОСТИ ПО ОРИЕНТАЦИИ ===
@export var orientation_speed_factor: float = 0.3
@export var max_orientation_penalty: float = 0.6

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

# === СРЫВ ПОТОКА (STALL) ===
@export var stall_speed_threshold: float = 40.0
@export var stall_drop_rate: float = 160.0
@export var stall_turn_rate: float = 2.5

# === ВЗРЫВ ===
@export var explosion_scene: PackedScene

# === GroundKill ===
@export var ground_kill_group: String = "GroundKill"
@export var ground_kill_name: String = "GroundKill"

# === HP ВМЕСТО ЖИЗНЕЙ (СИСТЕМА ПРОЦЕНТОВ) ===
@export var max_hp: int = 100  # 100% здоровья
@export var damage_per_hit: int = 10  # 10% за попадание
var player_hp: int

# === СОСТОЯНИЕ ===
var speed: float = 0.0
var can_shoot: bool = true
var shoot_timer: float = 0.0

var altitude: float = 0.0
var v_alt: float = 0.0
var is_grounded: bool = false

var is_alive: bool = true
var invulnerable: bool = false
var collision_cooldown: float = 0.0  # Кулдаун для столкновений с врагами
var collision_cooldown_time: float = 1.0  # 1 секунда между столкновениями

# Геттер для совместимости
func get_is_alive() -> bool:
	return is_alive

func is_invulnerable() -> bool:
	return invulnerable

@onready var muzzle: Node2D = $Muzzle

func _ready() -> void:
	# Добавляем в группу игроков
	add_to_group("player")
	
	altitude = start_altitude
	is_grounded = false
	speed = max_speed * 0.5
	
	# Инициализируем HP
	player_hp = max_hp
	
	# Загружаем сцену взрыва
	explosion_scene = load("res://scenes/Explosion.tscn")
	
	# Обновляем HUD
	await get_tree().process_frame
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("set_player_hp"):
		hud.set_player_hp(player_hp, max_hp)

func _physics_process(delta: float) -> void:
	if not is_alive:
		var collision_shape = get_node_or_null("CollisionShape2D")
		if collision_shape and not collision_shape.disabled:
			collision_shape.call_deferred("set_disabled", true)
		return
	
	# Обновляем кулдаун столкновений
	if collision_cooldown > 0.0:
		collision_cooldown -= delta

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
	
	# Масштабируем подъёмную силу от тяги в зависимости от скорости
	lift_from_throttle *= clamp(speed / stall_speed_threshold, 0.0, 1.0)
	
	var lift_total: float = lift_from_speed + lift_from_throttle
	var down: float = gravity_alt
	
	# === СРЫВ ПОТОКА (STALL) ===
	var is_stalling: bool = not is_grounded and speed <= stall_speed_threshold
	if is_stalling:
		lift_total = 0.0
		if speed <= 0.1:
			rotation = lerp_angle(rotation, PI / 2.0, stall_turn_rate * delta * 3.0)
			down = gravity_alt * 2.5
		else:
			rotation = lerp_angle(rotation, PI / 2.0, stall_turn_rate * delta)
			down = gravity_alt * 1.8
	
	var a_alt: float = lift_total - down

	if not is_grounded:
		v_alt += a_alt * delta
		v_alt = clamp(v_alt, -max_climb_rate, max_climb_rate)
		altitude += v_alt * delta

		var max_altitude: float = 300.0
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
	
	# 7) Проверка столкновений с врагами
	_check_plane_collisions()

func _process(delta: float) -> void:
	# Обновляем таймер кулдауна стрельбы
	if not can_shoot:
		shoot_timer += delta
		if shoot_timer >= fire_cooldown:
			can_shoot = true
			shoot_timer = 0.0
	
	# Проверяем стрельбу
	if is_alive and Input.is_action_just_pressed("shoot") and can_shoot:
		_shoot()

func _shoot() -> void:
	can_shoot = false
	shoot_timer = 0.0  # Сбрасываем таймер
	
	var scene: PackedScene = preload("res://scenes/Bullet.tscn")
	var b: Node2D = scene.instantiate() as Node2D
	b.global_position = muzzle.global_position
	b.rotation = rotation
	var bullet_vel: Vector2 = Vector2.RIGHT.rotated(rotation) * 900.0 + velocity
	b.set("velocity", bullet_vel)
	b.ignore_group = "player"
	
	# Регистрируем выстрел в GameState
	GameState.add_shot(true, false)
	
	# Помечаем пулю как выпущенную игроком
	b.set("fired_by_player", true)
	
	# ВАЖНО: Добавляем в корневой узел сцены (родитель игрока)
	get_parent().add_child(b)

func apply_damage(amount: int = 0) -> void:
	"""Применяет урон игроку (по умолчанию 10%)"""
	if invulnerable or not is_alive:
		return
	
	# Если amount не указан, используем стандартный урон
	var damage = amount if amount > 0 else damage_per_hit
	
	player_hp -= damage
	player_hp = max(player_hp, 0)
	
	# Обновляем HUD
	_update_hp_display()
	
	# Проверяем смерть
	if player_hp <= 0:
		_die()

func heal(amount: int) -> void:
	"""Восстанавливает здоровье игрока"""
	if not is_alive:
		return
	
	player_hp += amount
	player_hp = min(player_hp, max_hp)
	
	# Обновляем HUD
	_update_hp_display()

func _update_hp_display() -> void:
	"""Обновляет отображение HP на прогресс-баре"""
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("set_player_hp"):
		hud.set_player_hp(player_hp, max_hp)

func _die() -> void:
	"""Обрабатывает смерть игрока"""
	if not is_alive:
		return
	
	is_alive = false
	can_shoot = false
	
	# Создаём взрыв
	if explosion_scene:
		var ex: Node2D = explosion_scene.instantiate() as Node2D
		ex.global_position = global_position
		get_tree().current_scene.add_child(ex)
	
	# Отключаем коллайдер (используем call_deferred, чтобы избежать ошибок при обработке коллизий)
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.call_deferred("set_disabled", true)
	
	# Скрываем игрока
	visible = false
	set_physics_process(false)
	
	speed = 0.0
	v_alt = 0.0
	altitude = 0.0
	is_grounded = true
	velocity = Vector2.ZERO
	
	# Эмитим сигнал смерти
	player_dead.emit()

# === ВСПОМОГАТЕЛЬНОЕ ===
func _lift_factor_from_speed(s: float) -> float:
	if s <= stall_speed_alt:
		var k: float = (s - (stall_speed_alt - stall_soft)) / max(stall_soft, 1.0)
		k = clamp(k, 0.0, 1.0)
		return k * k
	return 1.0

func _get_orientation_speed_modifier() -> float:
	var normalized_rotation = fmod(rotation + PI, 2.0 * PI) - PI
	var orientation_penalty = abs(normalized_rotation) / PI
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
			_die()
			return

func _wrap_around_screen() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	
	# В режиме кампании НЕ заворачиваем по горизонтали (бесконечный полёт)
	# Только ограничиваем по вертикали
	
	# Ограничение высоты полета
	var max_height: float = 5.0
	var min_height: float = viewport_size.y - 20.0  # Немного от низа
	
	if global_position.y < max_height:
		global_position.y = max_height
		if v_alt > 0:
			v_alt = 0
	elif global_position.y > min_height:
		global_position.y = min_height
		if v_alt < 0:
			v_alt = 0

func _check_plane_collisions() -> void:
	# Проверяем кулдаун столкновений
	if collision_cooldown > 0.0:
		return  # Еще не прошло время для нового столкновения
	
	# Проверяем столкновения с врагами
	for i in range(get_slide_collision_count()):
		var c: KinematicCollision2D = get_slide_collision(i)
		var col := c.get_collider()
		if col == null:
			continue
		
		# Проверяем, что это враг
		if col is Node and col.is_in_group("enemy"):
			var enemy = col as Node
			# Проверяем, что враг жив
			if enemy.has_method("get_is_alive") and enemy.get_is_alive():
				# Проверяем щиты обоих самолётов
				var player_has_shield = invulnerable
				var enemy_has_shield = enemy.has_method("is_invulnerable") and enemy.is_invulnerable()
				
				# Если у обоих есть щит - никто не получает урон
				if player_has_shield and enemy_has_shield:
					return
				
				# Если только у игрока есть щит - взрывается только враг
				if player_has_shield and not enemy_has_shield:
					if enemy.has_method("_explode"):
						enemy._explode(c.get_position(), false)
					return
				
				# Если только у врага есть щит - игрок получает 25% урона
				if not player_has_shield and enemy_has_shield:
					apply_damage(25)  # 25% урона вместо мгновенной смерти
					collision_cooldown = collision_cooldown_time  # Устанавливаем кулдаун
					return
				
				# Если у обоих нет щита - оба получают урон
				if not player_has_shield and not enemy_has_shield:
					apply_damage(25)  # Игрок получает 25% урона
					if enemy.has_method("apply_damage"):
						enemy.apply_damage(25)  # Враг получает урон
					collision_cooldown = collision_cooldown_time  # Устанавливаем кулдаун
					return

# === МЕТОДЫ ЩИТА ===
func activate_shield(duration: float) -> void:
	"""Активирует щит на заданное время"""
	invulnerable = true
	_set_shield_visuals(true)
	
	# За 1 секунду до конца начинаем мигать
	var blink_start = duration - 1.0
	if blink_start > 0:
		await get_tree().create_timer(blink_start).timeout
		_blink_before_end()
		await get_tree().create_timer(1.0).timeout
	else:
		await get_tree().create_timer(duration).timeout
	
	invulnerable = false
	_set_shield_visuals(false)

func _set_shield_visuals(active: bool) -> void:
	"""Включает/выключает визуал щита"""
	var aura = get_node_or_null("ShieldAura")
	if aura:
		aura.visible = active

func _blink_before_end() -> void:
	"""Мигание щита перед окончанием"""
	var aura = get_node_or_null("ShieldAura")
	if not aura:
		return
	
	for i in range(5):
		aura.visible = false
		await get_tree().create_timer(0.1).timeout
		aura.visible = true
		await get_tree().create_timer(0.1).timeout
