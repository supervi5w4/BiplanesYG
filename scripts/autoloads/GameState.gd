extends Node
signal save_updated(data: Dictionary)
signal game_ended(result: String, stats: Dictionary)

var current_level: int = 1
var score: int = 0
var state: String = "idle"
var highest_unlocked_level: int = 1
const SAVE_KEY := "save"

# === СТАТИСТИКА ИГРЫ ===
var kills: int = 0
var shots_fired: int = 0
var shots_hit: int = 0
var start_time: int = 0
var end_time: int = 0

func start_game(level: int) -> void:
	current_level = level
	score = 0
	state = "playing"
	
	# Обнуляем статистику
	kills = 0
	shots_fired = 0
	shots_hit = 0
	start_time = Time.get_ticks_msec()
	end_time = 0
	
	_persist()

func end_game(result: String = "") -> void:
	state = "idle"
	
	# Фиксируем время завершения
	end_time = Time.get_ticks_msec()
	
	# Вычисляем статистику
	var duration_ms: int = end_time - start_time
	var duration_sec: float = duration_ms / 1000.0
	var accuracy: float = 0.0
	if shots_fired > 0:
		accuracy = (float(shots_hit) / float(shots_fired)) * 100.0
	
	# Формируем словарь статистики
	var stats: Dictionary = {
		"player_lives": 0,  # Будет установлено HUD'ом
		"enemy_lives": 0,   # Будет установлено HUD'ом
		"score": score,
		"kills": kills,
		"shots_fired": shots_fired,
		"shots_hit": shots_hit,
		"accuracy": accuracy,
		"duration_sec": duration_sec
	}
	
	# Отправляем сигнал о завершении игры
	emit_signal("game_ended", result, stats)
	
	_persist()

func has_game_in_progress() -> bool:
	return state == "playing"

func update_game_state(level: int, new_score: int, new_state: String) -> void:
	current_level = level
	score = new_score
	state = new_state
	_persist()

func reset_for_level(level: int) -> void:
	current_level = level
	score = 0
	state = "ready"
	
	# Обнуляем статистику
	kills = 0
	shots_fired = 0
	shots_hit = 0
	start_time = 0
	end_time = 0
	
	_persist()

# === МЕТОДЫ ДЛЯ ОБНОВЛЕНИЯ СТАТИСТИКИ ===

func add_score(points: int) -> void:
	"""Добавляет очки к общему счету"""
	score += points
	_persist()

func add_kill() -> void:
	"""Увеличивает счетчик убийств"""
	kills += 1
	# За каждое убийство начисляем очки
	add_score(100)

func add_shot(fired: bool = true, hit: bool = false) -> void:
	"""
	Регистрирует выстрел
	
	Параметры:
	- fired: если true, увеличивает счетчик выстрелов
	- hit: если true, увеличивает счетчик попаданий
	"""
	if fired:
		shots_fired += 1
	if hit:
		shots_hit += 1

func register_hit(_target: Node = null) -> void:
	"""
	Регистрирует попадание по цели
	
	Параметры:
	- _target: узел, по которому попали (опционально, зарезервировано для будущего использования)
	"""
	shots_hit += 1
	
	# Дополнительные очки за попадание
	add_score(10)

func apply_cloud_save(data: Dictionary) -> void:
	if data.has(SAVE_KEY) and typeof(data[SAVE_KEY]) == TYPE_DICTIONARY:
		var blob: Dictionary = data[SAVE_KEY]
		current_level = int(blob.get("current_level", current_level))
		score = int(blob.get("score", score))
		state = String(blob.get("state", state))
		highest_unlocked_level = int(blob.get("highest_unlocked_level", highest_unlocked_level))
		emit_signal("save_updated", to_dict())

func to_dict() -> Dictionary:
	return {
		"current_level": current_level,
		"score": score,
		"state": state,
		"highest_unlocked_level": highest_unlocked_level
	}

func _persist() -> void:
	var payload := { SAVE_KEY: to_dict() }
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload))
		f.close()
	emit_signal("save_updated", to_dict())
	if OS.has_feature("yandex"):
		# true = попытаться сразу отправить
		YandexSDK.save_data(payload, true)
