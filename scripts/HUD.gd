extends CanvasLayer

# Экспортируемые переменные
@export var max_lives: int = 5
@export var heart_full_texture: Texture2D
@export var heart_empty_texture: Texture2D

# Ссылки на узлы HUD
@onready var player_hearts_container: HBoxContainer = $PlayerHearts
@onready var enemy_hearts_container: HBoxContainer = $EnemyHearts
@onready var game_status_label: Label = $GameStatusLabel

# Массивы для хранения ссылок на TextureRect узлы сердец
var player_hearts: Array[TextureRect] = []
var enemy_hearts: Array[TextureRect] = []

# Текущие значения жизней
var player_lives: int = 0
var enemy_lives: int = 0

# Флаг для предотвращения множественных срабатываний
var game_ended: bool = false

# Таймер для задержки перед переходом в меню
var end_timer: SceneTreeTimer

func _ready():
	# Инициализация массивов сердец
	initialize_hearts()
	
	# Установка начальных значений жизней
	update_player_lives(max_lives)
	update_enemy_lives(max_lives)
	
	# Обновление отображения сердец
	_update_hearts()

func initialize_hearts():
	"""Инициализирует массивы сердец из дочерних узлов"""
	# Получаем все TextureRect узлы из контейнеров сердец
	for child in player_hearts_container.get_children():
		if child is TextureRect:
			player_hearts.append(child)
	
	for child in enemy_hearts_container.get_children():
		if child is TextureRect:
			enemy_hearts.append(child)

func _update_hearts():
	"""Обновляет отображение всех сердец на основе текущих значений жизней"""
	# Обновляем сердца игрока
	for i in range(player_hearts.size()):
		if i < player_lives:
			player_hearts[i].texture = heart_full_texture
		else:
			player_hearts[i].texture = heart_empty_texture
	
	# Обновляем сердца врага
	for i in range(enemy_hearts.size()):
		if i < enemy_lives:
			enemy_hearts[i].texture = heart_full_texture
		else:
			enemy_hearts[i].texture = heart_empty_texture

func update_player_lives(new_lives: int):
	"""Обновляет количество жизней игрока"""
	player_lives = clamp(new_lives, 0, max_lives)
	_update_hearts()
	
	# Проверяем, не закончилась ли игра
	if player_lives <= 0 and not game_ended:
		_trigger_game_end("Поражение")

func update_enemy_lives(new_lives: int):
	"""Обновляет количество жизней врага"""
	enemy_lives = clamp(new_lives, 0, max_lives)
	_update_hearts()
	
	# Проверяем, не закончилась ли игра
	if enemy_lives <= 0 and not game_ended:
		_trigger_game_end("Победа")

func _trigger_game_end(result_text: String):
	"""Запускает процесс завершения игры"""
	if game_ended:
		return
	
	game_ended = true
	
	# Показываем результат
	show_result(result_text)
	
	# Создаем таймер для задержки перед переходом в меню
	end_timer = get_tree().create_timer(5.0)
	end_timer.timeout.connect(_return_to_menu)

func _return_to_menu():
	"""Переходит в главное меню"""
	get_tree().change_scene_to_file("res://scenes/start_menu.tscn")

func show_result(text: String):
	"""Показывает результат игры (может быть вызван извне)"""
	game_status_label.text = text
	game_status_label.visible = true
	
	# Если это внешний вызов, также запускаем таймер
	if not game_ended:
		game_ended = true
		end_timer = get_tree().create_timer(5.0)
		end_timer.timeout.connect(_return_to_menu)

func hide_result():
	"""Скрывает результат игры"""
	game_status_label.visible = false

func reset_game():
	"""Сбрасывает состояние игры"""
	game_ended = false
	player_lives = max_lives
	enemy_lives = max_lives
	_update_hearts()
	hide_result()
	
	# Отменяем активный таймер, если он есть
	if end_timer and end_timer.time_left > 0:
		end_timer.time_left = 0

func _exit_tree():
	"""Очистка при удалении узла"""
	# Отменяем активный таймер
	if end_timer and end_timer.time_left > 0:
		end_timer.time_left = 0
