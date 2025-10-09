extends CanvasLayer

# Ссылки на узлы
@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var player_lives_value: Label = $Panel/MarginContainer/VBoxContainer/StatsContainer/PlayerLivesRow/Value
@onready var enemy_lives_value: Label = $Panel/MarginContainer/VBoxContainer/StatsContainer/EnemyLivesRow/Value
@onready var score_value: Label = $Panel/MarginContainer/VBoxContainer/StatsContainer/ScoreRow/Value
@onready var kills_value: Label = $Panel/MarginContainer/VBoxContainer/StatsContainer/KillsRow/Value
@onready var accuracy_value: Label = $Panel/MarginContainer/VBoxContainer/StatsContainer/AccuracyRow/Value
@onready var time_value: Label = $Panel/MarginContainer/VBoxContainer/StatsContainer/TimeRow/Value
@onready var restart_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonsContainer/RestartButton
@onready var menu_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonsContainer/MenuButton
@onready var share_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonsContainer/ShareButton
@onready var animation_player: AnimationPlayer = $AnimationPlayer
# AudioPlayer опционален, может быть использован для звуков в будущем
@onready var audio_player: AudioStreamPlayer = $AudioPlayer if has_node("AudioPlayer") else null

# Цвета для разных результатов
const COLOR_VICTORY: Color = Color(0.2, 0.8, 0.2, 1.0)  # Зеленый
const COLOR_DEFEAT: Color = Color(0.8, 0.2, 0.2, 1.0)   # Красный
const COLOR_DRAW: Color = Color(0.7, 0.7, 0.2, 1.0)     # Желтый

func _ready():
	# Скрываем панель при старте
	visible = false
	panel.modulate.a = 0.0
	
	# Подключаем сигналы кнопок
	restart_button.pressed.connect(_on_restart_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	share_button.pressed.connect(_on_share_pressed)

func show_screen(result: String, stats: Dictionary):
	"""
	Показывает экран завершения игры
	
	Параметры:
	- result: "Победа", "Поражение" или другой текст
	- stats: Dictionary с ключами:
		- player_lives: int
		- enemy_lives: int
		- score: int
		- kills: int
		- shots_fired: int
		- shots_hit: int
		- accuracy: float (в процентах)
		- duration_sec: float
	"""
	# Устанавливаем видимость
	visible = true
	
	# Устанавливаем текст заголовка
	title_label.text = result
	
	# Устанавливаем цвет в зависимости от результата
	if result == "Победа" or result.to_lower().contains("побед"):
		title_label.modulate = COLOR_VICTORY
	elif result == "Поражение" or result.to_lower().contains("пораж"):
		title_label.modulate = COLOR_DEFEAT
	else:
		title_label.modulate = COLOR_DRAW
	
	# Заполняем основную статистику
	player_lives_value.text = str(stats.get("player_lives", 0))
	enemy_lives_value.text = str(stats.get("enemy_lives", 0))
	score_value.text = str(stats.get("score", 0))
	
	# Заполняем расширенную статистику
	kills_value.text = str(stats.get("kills", 0))
	
	# Форматируем точность
	var accuracy: float = stats.get("accuracy", 0.0)
	accuracy_value.text = "%.1f%%" % accuracy
	
	# Форматируем время (секунды в минуты:секунды)
	var duration_sec: float = stats.get("duration_sec", 0.0)
	var total_seconds: int = int(duration_sec)
	@warning_ignore("integer_division")
	var minutes: int = total_seconds / 60  # Целочисленное деление - это именно то, что нам нужно
	var seconds: int = total_seconds % 60
	if minutes > 0:
		time_value.text = "%d:%02d" % [minutes, seconds]
	else:
		time_value.text = "%dс" % seconds
	
	# Запускаем анимацию появления
	if animation_player and animation_player.has_animation("fade_in"):
		animation_player.play("fade_in")
	else:
		# Fallback: используем Tween для анимации
		_animate_show_with_tween()
	
	# Воспроизводим звук (если назначен)
	if audio_player and audio_player.stream:
		audio_player.play()

func _animate_show_with_tween():
	"""Альтернативная анимация появления через Tween"""
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.8, 0.8)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	tween.tween_property(panel, "modulate:a", 1.0, 0.5)
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.5)

func _animate_hide_with_tween():
	"""Альтернативная анимация исчезновения через Tween"""
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	await tween.finished

func hide_screen():
	"""Скрывает экран с анимацией"""
	if animation_player and animation_player.has_animation("fade_out"):
		animation_player.play("fade_out")
		await animation_player.animation_finished
	else:
		# Fallback: используем Tween для анимации
		await _animate_hide_with_tween()
	
	visible = false

func _on_restart_pressed():
	"""Обработчик нажатия кнопки 'Переиграть'"""
	# Сбрасываем состояние игры
	GameState.reset_for_level(GameState.current_level)
	
	# Скрываем экран
	await hide_screen()
	
	# Перезагружаем текущую сцену
	get_tree().reload_current_scene()

func _on_menu_pressed():
	"""Обработчик нажатия кнопки 'Меню'"""
	# Сбрасываем состояние игры
	GameState.end_game()
	
	# Скрываем экран
	await hide_screen()
	
	# Переходим в главное меню
	get_tree().change_scene_to_file("res://scenes/start_menu.tscn")

func _on_share_pressed():
	"""Обработчик нажатия кнопки 'Поделиться'"""
	# Если это Яндекс.Игры, вызываем API для шаринга
	if OS.has_feature("yandex") and YandexSDK:
		var share_text = "Я играю в Biplanes! Мой счет: %d" % GameState.score
		# Здесь можно добавить вызов YandexSDK для шаринга
		print("Поделиться: ", share_text)
	else:
		# В других случаях просто выводим сообщение
		print("Функция 'Поделиться' доступна только в Яндекс.Играх")
	
	# Можно добавить визуальную обратную связь
	share_button.disabled = true
	await get_tree().create_timer(1.0).timeout
	share_button.disabled = false
