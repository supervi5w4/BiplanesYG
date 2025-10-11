extends "res://scripts/Enemy.gd"
# ─────────────────────────────────────────────────────────────────────────────
# Boss.gd — босс для режима кампании с увеличенными характеристиками
# ─────────────────────────────────────────────────────────────────────────────

signal boss_defeated

# === ДОПОЛНИТЕЛЬНЫЕ ПАРАМЕТРЫ БОССА ===
@export var boss_hp: int = 20  # Увеличенное HP
@export var burst_fire_count: int = 3  # Количество выстрелов в серии
@export var burst_fire_delay: float = 0.15  # Задержка между выстрелами в серии

var is_boss: bool = true
var burst_fire_active: bool = false

func _ready() -> void:
	# Вызываем родительский _ready
	super._ready()
	
	# Переопределяем характеристики для босса
	hp = boss_hp
	max_lives = 1  # У босса одна жизнь, но больше HP
	lives = 1
	
	# Увеличиваем скорость и маневренность
	max_speed = 350.0
	turn_speed = 3.5
	
	# Уменьшаем задержку стрельбы
	fire_cooldown = 0.5
	shooting_delay = 1.0
	
	# Отключаем респавн для босса
	respawn_enabled = false

func apply_damage(amount: int, _from_player: bool = true) -> void:
	"""Переопределяем получение урона для босса"""
	if invulnerable or not is_alive:
		return
	
	hp -= amount
	
	# Визуальная обратная связь при попадании
	_flash_on_hit()
	
	if hp <= 0:
		_die()

func _die() -> void:
	"""Переопределяем смерть босса"""
	if not is_alive:
		return
	
	is_alive = false
	can_shoot = false
	
	# Создаём взрыв
	if explosion_scene:
		var ex: Node2D = explosion_scene.instantiate() as Node2D
		ex.global_position = global_position
		get_tree().current_scene.add_child(ex)
	
	# Отключаем коллайдер
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.disabled = true
	
	# Эмитим сигнал победы над боссом
	boss_defeated.emit()
	
	# Скрываем босса
	visible = false
	set_physics_process(false)
	
	# Удаляем босса
	await get_tree().create_timer(0.5).timeout
	queue_free()

func _flash_on_hit() -> void:
	"""Визуальный эффект при попадании"""
	var sprite = get_node_or_null("Sprite2D")
	if not sprite:
		return
	
	# Создаём мигание
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1.5, 0.5, 0.5, 1.0), 0.1)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)

func _shoot() -> void:
	"""Переопределяем стрельбу для босса - серийная стрельба"""
	if burst_fire_active:
		return
	
	burst_fire_active = true
	
	for i in range(burst_fire_count):
		_shoot_single()
		await get_tree().create_timer(burst_fire_delay).timeout
	
	burst_fire_active = false

func _shoot_single() -> void:
	"""Одиночный выстрел босса"""
	if not can_shoot or not is_alive:
		return
	
	var scene: PackedScene = preload("res://scenes/Bullet.tscn")
	var b: Node2D = scene.instantiate() as Node2D
	
	if not muzzle:
		return
	
	b.global_position = muzzle.global_position
	b.rotation = rotation
	var bullet_vel: Vector2 = Vector2.RIGHT.rotated(rotation) * bullet_speed + velocity
	b.set("velocity", bullet_vel)
	b.ignore_group = "enemy"
	
	# Регистрируем выстрел в GameState
	GameState.add_shot(false, true)
	
	get_tree().current_scene.add_child(b)

# Переопределяем взрыв, чтобы использовать нашу логику смерти
func _explode(_hit_pos: Vector2, _killed_by_player: bool = true) -> void:
	_die()
