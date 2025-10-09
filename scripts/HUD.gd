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

# Ссылка на экран завершения игры
var end_screen_scene: PackedScene = preload("res://scenes/EndScreen.tscn")
var end_screen_instance: CanvasLayer = null

func _ready():
	# Инициализация массивов сердец
	initialize_hearts()
	
	# Установка начальных значений жизней
	update_player_lives(max_lives)
	update_enemy_lives(max_lives)
	
	# Обновление отображения сердец
	_update_hearts()
	
	# Подключаемся к сигналу завершения игры
	GameState.game_ended.connect(_on_game_ended)

func _init_end_screen():
	"""Инициализирует экран завершения игры (ленивая инициализация)"""
	if end_screen_instance == null and end_screen_scene:
		end_screen_instance = end_screen_scene.instantiate()
		# Добавляем как дочерний узел к корню сцены, чтобы он был выше всего
		get_tree().root.add_child(end_screen_instance)
		end_screen_instance.visible = false

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

func _on_game_ended(result: String, stats: Dictionary):
	"""
	Обработчик сигнала GameState.game_ended
	Вызывается автоматически при завершении игры
	"""
	if game_ended:
		return
	
	game_ended = true
	
	# Дополняем статистику текущими значениями жизней
	stats["player_lives"] = player_lives
	stats["enemy_lives"] = enemy_lives
	
	# Показываем экран завершения
	show_end_screen(result, stats)

func _trigger_game_end(result_text: String):
	"""
	Запускает процесс завершения игры (устаревший метод)
	Теперь используется сигнал GameState.game_ended
	"""
	if game_ended:
		return
	
	game_ended = true
	
	# Собираем статистику для экрана завершения
	var stats = {
		"player_lives": player_lives,
		"enemy_lives": enemy_lives,
		"score": GameState.score
	}
	
	# Показываем экран завершения
	show_end_screen(result_text, stats)

func show_end_screen(result: String, stats: Dictionary):
	"""
	Показывает экран завершения игры с анимацией
	
	Параметры:
	- result: текст результата ("Победа", "Поражение" и т.д.)
	- stats: словарь со статистикой игры
	"""
	# Инициализируем EndScreen если еще не создан (ленивая загрузка)
	_init_end_screen()
	
	if end_screen_instance and end_screen_instance.has_method("show_screen"):
		# Скрываем основной HUD с анимацией (опционально)
		_hide_hud_animated()
		
		# Показываем экран завершения
		end_screen_instance.show_screen(result, stats)
	else:
		# Fallback на старый метод, если что-то пошло не так
		show_result(result)

func _hide_hud_animated():
	"""Плавно скрывает элементы HUD"""
	# Создаем Tween для плавного затухания
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(player_hearts_container, "modulate:a", 0.3, 0.3)
	tween.tween_property(enemy_hearts_container, "modulate:a", 0.3, 0.3)

func _show_hud_animated():
	"""Плавно показывает элементы HUD"""
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(player_hearts_container, "modulate:a", 1.0, 0.3)
	tween.tween_property(enemy_hearts_container, "modulate:a", 1.0, 0.3)

func show_result(text: String):
	"""
	Устаревший метод показа результата (для обратной совместимости)
	Используйте show_end_screen() вместо этого
	"""
	game_status_label.text = text
	game_status_label.visible = true
	
	# Если это внешний вызов, также запускаем таймер
	if not game_ended:
		game_ended = true
		end_timer = get_tree().create_timer(5.0)
		end_timer.timeout.connect(_return_to_menu)

func _return_to_menu():
	"""Переходит в главное меню"""
	get_tree().change_scene_to_file("res://scenes/start_menu.tscn")

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
	
	# Восстанавливаем видимость HUD
	_show_hud_animated()
	
	# Скрываем экран завершения, если он показан
	if end_screen_instance and end_screen_instance.visible:
		if end_screen_instance.has_method("hide_screen"):
			end_screen_instance.hide_screen()
		else:
			end_screen_instance.visible = false
	
	# Отменяем активный таймер, если он есть
	if end_timer and end_timer.time_left > 0:
		end_timer.time_left = 0

func _exit_tree():
	"""Очистка при удалении узла"""
	# Отменяем активный таймер
	if end_timer and end_timer.time_left > 0:
		end_timer.time_left = 0
	
	# Удаляем экземпляр EndScreen
	if end_screen_instance and is_instance_valid(end_screen_instance):
		end_screen_instance.queue_free()
		end_screen_instance = null
