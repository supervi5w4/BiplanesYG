extends Node

@export var player_scene: PackedScene = preload("res://scenes/Player.tscn")
@export var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")
@export var life_pickup_scene: PackedScene = preload("res://scenes/LifePickup.tscn")
@export var life_pickup_spawn_interval_min: float = 5.0  # Минимальный интервал появления плюшек
@export var life_pickup_spawn_interval_max: float = 10.0  # Максимальный интервал появления плюшек
@onready var spawn_player: Node2D = $SpawnPlayer if has_node("SpawnPlayer") else null
@onready var spawn_enemy: Node2D = $SpawnEnemy if has_node("SpawnEnemy") else null

var life_pickup_timer: Timer

func _ready() -> void:
	_init_world()
	_spawn_player()
	_spawn_enemy()
	_setup_life_pickup_timer()

func _init_world() -> void:
	# здесь же можно подготовить фон, коллайдеры границ и т.п.
	pass

func _spawn_player() -> void:
	if player_scene:
		var p := player_scene.instantiate()
		if spawn_player:
			p.global_position = spawn_player.global_position
		add_child(p)
	GameState.start_game(1)

func _spawn_enemy() -> void:
	if enemy_scene:
		var e := enemy_scene.instantiate()
		
		# Используем точку спавна врага если она есть
		if spawn_enemy:
			e.global_position = spawn_enemy.global_position
		else:
			# Fallback к позиции справа от экрана
			var viewport_size: Vector2 = get_viewport().get_visible_rect().size
			e.global_position = Vector2(viewport_size.x + 200, 200)
		
		add_child(e)

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
