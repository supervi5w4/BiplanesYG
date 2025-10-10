extends Node2D
# ─────────────────────────────────────────────────────────────────────────────
# Battlefield.gd — управление сценой battlefield (режим 1 на 1)
# ─────────────────────────────────────────────────────────────────────────────

@export var life_pickup_scene: PackedScene = preload("res://scenes/LifePickup.tscn")
@export var life_pickup_spawn_interval_min: float = 5.0  # Минимальный интервал появления плюшек
@export var life_pickup_spawn_interval_max: float = 10.0  # Максимальный интервал появления плюшек

var life_pickup_timer: Timer

func _ready() -> void:
	GameState.start_game(1)
	_setup_life_pickup_timer()

func _setup_life_pickup_timer() -> void:
	"""Настраивает таймер для периодического появления плюшек-сердечек"""
	life_pickup_timer = Timer.new()
	life_pickup_timer.one_shot = true  # Таймер срабатывает один раз
	life_pickup_timer.timeout.connect(_spawn_life_pickup)
	add_child(life_pickup_timer)
	
	# Запускаем таймер с случайным интервалом
	_start_next_spawn_timer()

func _start_next_spawn_timer() -> void:
	"""Запускает таймер со случайным интервалом"""
	var interval = randf_range(life_pickup_spawn_interval_min, life_pickup_spawn_interval_max)
	life_pickup_timer.wait_time = interval
	life_pickup_timer.start()

func _spawn_life_pickup() -> void:
	"""Создает плюшку-сердечко в случайной позиции на экране"""
	if not life_pickup_scene:
		_start_next_spawn_timer()  # Пробуем снова через случайный интервал
		return
	
	var pickup = life_pickup_scene.instantiate()
	
	# Получаем размеры видимой области экрана
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	
	# Генерируем случайную позицию в безопасной зоне экрана
	# Отступаем от краев, чтобы плюшка не появлялась слишком близко к границам
	var margin_x: float = 50.0
	var margin_y_top: float = 50.0
	var margin_y_bottom: float = 100.0  # Больше отступ снизу, чтобы не заходить на GroundKill
	
	var spawn_x: float = randf_range(margin_x, viewport_size.x - margin_x)
	var spawn_y: float = randf_range(margin_y_top, viewport_size.y - margin_y_bottom)
	
	pickup.global_position = Vector2(spawn_x, spawn_y)
	add_child(pickup)
	
	# Запускаем таймер для следующего спавна
	_start_next_spawn_timer()

