extends CharacterBody2D
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
@export var ground_friction: float = 220.0     # трение по земле (м/с^2)
@export var liftoff_speed: float = 180.0       # минимальная скор. для уверенного отрыва
@export var liftoff_lift_margin: float = 30.0  # насколько лифт должен превышать гравитацию, чтобы оторваться

# === СОСТОЯНИЕ ===
var speed: float = 0.0
var hp: int = 100
var can_shoot: bool = true

var altitude: float = 0.0
var v_alt: float = 0.0
var is_grounded: bool = false

@onready var muzzle: Node2D = $Muzzle

func _ready() -> void:
	altitude = start_altitude
	is_grounded = false

func _physics_process(delta: float) -> void:
	# --- 1) ПОВОРОТ ---
	var turn: float = Input.get_action_strength("turn_right") - Input.get_action_strength("turn_left")
	rotation += turn * turn_speed * delta

	# --- 2) ГАЗ / ТОРМОЗ (назад не летим) ---
	var thrust_in: float = Input.get_action_strength("thrust")
	var brake_in: float = Input.get_action_strength("brake")

	if thrust_in > 0.0:
		speed += accel * thrust_in * delta
	if brake_in > 0.0:
		speed -= brake_power * brake_in * delta

	# пассивное сопротивление воздуха
	if speed > 0.0:
		speed -= drag_linear * delta
		if speed < 0.0:
			speed = 0.0

	# пределы
	if speed > max_speed:
		speed = max_speed
	if speed < 0.0:
		speed = 0.0

	# --- 3) ВЕРТИКАЛЬНАЯ ФИЗИКА (лифт/гравитация) ---
	var lift_from_speed: float = _lift_factor_from_speed(speed) * lift_speed_coeff * speed
	var lift_from_throttle: float = lift_throttle_coeff * thrust_in
	var lift_total: float = lift_from_speed + lift_from_throttle
	var down: float = gravity_alt

	var a_alt: float = lift_total - down

	# если в воздухе — обычная вертикальная динамика
	if not is_grounded:
		v_alt += a_alt * delta
		v_alt = clamp(v_alt, -max_climb_rate, max_climb_rate)
		altitude += v_alt * delta

		# приземление
		if altitude <= 0.0:
			altitude = 0.0
			v_alt = 0.0
			is_grounded = true
	else:
		# на земле: высота = 0, вертикаль «закреплена»
		altitude = 0.0
		v_alt = 0.0

		# катимся по земле с трением
		if speed > 0.0:
			speed -= ground_friction * delta
			if speed < 0.0:
				speed = 0.0

		# попытка взлёта: нужна скорость И достаточный подъём (лифт > гравитации)
		if speed >= liftoff_speed and (lift_total - down) > liftoff_lift_margin and thrust_in > 0.0:
			is_grounded = false
			# лёгкий толчок вверх, чтобы явно оторваться
			v_alt = max(v_alt, 60.0)
			altitude += v_alt * delta

	# --- 4) ГОРИЗОНТАЛЬНОЕ ДВИЖЕНИЕ ---
	var heading: Vector2 = Vector2.RIGHT.rotated(rotation)
	velocity = heading * speed
	move_and_slide()

func _process(_dt: float) -> void:
	if Input.is_action_pressed("shoot") and can_shoot:
		_shoot()

func _shoot() -> void:
	can_shoot = false
	var scene: PackedScene = preload("res://scenes/Bullet.tscn")
	var b: Node2D = scene.instantiate() as Node2D
	b.global_position = muzzle.global_position
	b.rotation = rotation
	var bullet_vel: Vector2 = Vector2.RIGHT.rotated(rotation) * 900.0 + velocity
	b.set("velocity", bullet_vel)
	# если в пулях есть логика owner — раскомментируй следующую строку:
	# b.set("owner", self)
	get_tree().current_scene.add_child(b)
	await get_tree().create_timer(fire_cooldown).timeout
	can_shoot = true

func apply_damage(amount: int) -> void:
	hp -= amount
	if hp < 0:
		hp = 0
	# Здесь нарочно НЕ удаляем и НЕ скрываем самолёт:
	# хочешь «смерть» — можно принудительно «уронить» его на землю:
	# is_grounded = true; altitude = 0.0; v_alt = 0.0

# === ВСПОМОГАТЕЛЬНОЕ ===
func _lift_factor_from_speed(s: float) -> float:
	# Ниже «скорости сваливания» подъёмная сила плавно убывает к нулю
	if s <= stall_speed_alt:
		var k: float = (s - (stall_speed_alt - stall_soft)) / max(stall_soft, 1.0)
		k = clamp(k, 0.0, 1.0)
		return k * k
	return 1.0

# Для HUD (опционально)
func get_altitude() -> float:
	return altitude

func get_vertical_speed() -> float:
	return v_alt
