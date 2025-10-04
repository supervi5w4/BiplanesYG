extends CharacterBody2D
# ─────────────────────────────────────────────────────────────────────────────
# Player.gd — классическое управление + взрыв/респаун и GroundKill
# ─────────────────────────────────────────────────────────────────────────────

# === КЛАССИЧЕСКОЕ ГОРИЗОНТАЛЬНОЕ ДВИЖЕНИЕ ===
@export var turn_speed: float = 3.2
@export var accel: float = 900.0
@export var brake_power: float = 1100.0
@export var max_speed: float = 520.0
@export var drag_linear: float = 0.85
@export var fire_cooldown: float = 0.14

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
@export var explosion_scene: PackedScene = preload("res://scenes/Explosion.tscn")
@export var spawn_path: NodePath
@export var respawn_delay: float = 1.0
@export var invuln_time: float = 0.8

# === GroundKill ===
@export var ground_kill_group: String = "GroundKill"
@export var ground_kill_name: String = "GroundKill"

# === СОСТОЯНИЕ ===
var speed: float = 0.0
var hp: int = 100
var can_shoot: bool = true

var altitude: float = 0.0
var v_alt: float = 0.0
var is_grounded: bool = false

var is_alive: bool = true
var invulnerable: bool = false

@onready var muzzle: Node2D = $Muzzle

func _ready() -> void:
	altitude = start_altitude
	is_grounded = false

func _physics_process(delta: float) -> void:
	if not is_alive:
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

	speed = clamp(speed, 0.0, max_speed)

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

	# 5) Проверка столкновений с GroundKill
	_check_groundkill_collisions()

func _process(_dt: float) -> void:
	if is_alive and Input.is_action_pressed("shoot") and can_shoot:
		_shoot()

func _shoot() -> void:
	can_shoot = false
	var scene: PackedScene = preload("res://scenes/Bullet.tscn")
	var b: Node2D = scene.instantiate() as Node2D
	b.global_position = muzzle.global_position
	b.rotation = rotation
	var bullet_vel: Vector2 = Vector2.RIGHT.rotated(rotation) * 900.0 + velocity
	b.set("velocity", bullet_vel)
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

	await get_tree().create_timer(respawn_delay).timeout
	_respawn()

func _respawn() -> void:
	var spawn: Node2D = get_node_or_null(spawn_path) as Node2D
	if spawn:
		global_position = spawn.global_position

	hp = 100
	speed = 0.0
	altitude = start_altitude
	v_alt = 0.0
	is_grounded = false

	visible = true
	set_physics_process(true)
	is_alive = true
	can_shoot = true

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
