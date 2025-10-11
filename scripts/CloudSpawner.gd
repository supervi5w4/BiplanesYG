extends Node2D
# ─────────────────────────────────────────────────────────────────────────────
# CloudSpawner.gd — спавнер облаков для фона
# ─────────────────────────────────────────────────────────────────────────────

@export var cloud_scene: PackedScene = null
@export var min_spawn_interval: float = 2.0
@export var max_spawn_interval: float = 4.0
@export var max_clouds: int = 5
@export var spawn_offset_x: float = 800.0  # На сколько впереди камеры спавнить
@export var min_y: float = 50.0
@export var max_y: float = 400.0

var camera: Camera2D = null
var cloud_container: Node2D = null
var spawn_timer: Timer = null
var active_clouds: int = 0
var is_spawning: bool = true

func _ready() -> void:
	print("[CloudSpawner] _ready() вызван")
	# Создаем таймер для спавна
	spawn_timer = Timer.new()
	add_child(spawn_timer)
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	spawn_timer.one_shot = false
	
	# Запускаем таймер
	_reset_spawn_timer()
	print("[CloudSpawner] Таймер запущен")

func set_camera(cam: Camera2D) -> void:
	"""Устанавливает ссылку на камеру"""
	camera = cam
	print("[CloudSpawner] Камера установлена: ", camera)

func set_cloud_container(container: Node2D) -> void:
	"""Устанавливает контейнер для облаков"""
	cloud_container = container
	print("[CloudSpawner] Контейнер установлен: ", cloud_container)

func _reset_spawn_timer() -> void:
	"""Сбрасывает таймер со случайным интервалом"""
	var interval = randf_range(min_spawn_interval, max_spawn_interval)
	spawn_timer.start(interval)

func _on_spawn_timer_timeout() -> void:
	"""Обработчик таймера - спавним облако"""
	print("[CloudSpawner] Таймер сработал. is_spawning=", is_spawning, " active_clouds=", active_clouds, " max_clouds=", max_clouds)
	if is_spawning and active_clouds < max_clouds:
		spawn_cloud()
	
	# Сбрасываем таймер для следующего спавна
	_reset_spawn_timer()

func spawn_cloud() -> void:
	"""Создает новое облако"""
	print("[CloudSpawner] spawn_cloud() вызван")
	if not cloud_scene:
		print("[CloudSpawner] ОШИБКА: cloud_scene отсутствует!")
		return
	if not camera:
		print("[CloudSpawner] ОШИБКА: camera отсутствует!")
		return
	if not cloud_container:
		print("[CloudSpawner] ОШИБКА: cloud_container отсутствует!")
		return
	
	var cloud = cloud_scene.instantiate()
	
	# Позиция: впереди камеры на случайной высоте
	var spawn_x = camera.global_position.x + spawn_offset_x
	var spawn_y = randf_range(min_y, max_y)
	cloud.global_position = Vector2(spawn_x, spawn_y)
	print("[CloudSpawner] Создано облако на позиции: ", cloud.global_position)
	
	# Передаем ссылку на камеру
	if cloud.has_method("set_camera"):
		cloud.set_camera(camera)
	
	# Добавляем в контейнер (а не в родительский узел)
	cloud_container.add_child(cloud)
	active_clouds += 1
	print("[CloudSpawner] Облако добавлено в контейнер. Активных облаков: ", active_clouds)
	
	# Подключаемся к сигналу удаления
	cloud.tree_exited.connect(_on_cloud_removed)

func _on_cloud_removed() -> void:
	"""Уменьшаем счетчик когда облако удаляется"""
	active_clouds -= 1

func stop_spawning() -> void:
	"""Останавливает спавн облаков"""
	is_spawning = false
	if spawn_timer:
		spawn_timer.stop()

func start_spawning() -> void:
	"""Возобновляет спавн облаков"""
	is_spawning = true
	_reset_spawn_timer()

