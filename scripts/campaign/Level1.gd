extends Node2D
# ─────────────────────────────────────────────────────────────────────────────
# Level1.gd — первый уровень кампании
# ─────────────────────────────────────────────────────────────────────────────

var player: CharacterBody2D = null
var camera: Camera2D = null
var enemy_spawner: Node2D = null
var cloud_spawner: Node2D = null
var cloud_container: Node2D = null
var level_duration: float = 0.0
var level_complete: bool = false

func _ready() -> void:
	# Получаем ссылки
	player = get_node_or_null("PlayerCampaign")
	camera = get_node_or_null("Camera2D")
	enemy_spawner = get_node_or_null("EnemySpawner")
	cloud_spawner = get_node_or_null("CloudSpawner")
	cloud_container = get_node_or_null("CloudContainer")
	
	print("[Level1] Получены ссылки:")
	print("  player: ", player)
	print("  camera: ", camera)
	print("  enemy_spawner: ", enemy_spawner)
	print("  cloud_spawner: ", cloud_spawner)
	print("  cloud_container: ", cloud_container)
	
	if camera:
		camera.enabled = true
		camera.make_current()
	
	# Подключаем сигналы
	if player:
		player.player_dead.connect(_on_player_dead)
	
	if enemy_spawner:
		enemy_spawner.boss_defeated.connect(_on_boss_defeated)
	
	# Передаем камеру и контейнер в CloudSpawner
	if cloud_spawner and camera and cloud_container:
		print("[Level1] Передаю камеру и контейнер в CloudSpawner")
		cloud_spawner.set_camera(camera)
		cloud_spawner.set_cloud_container(cloud_container)
	else:
		print("[Level1] ОШИБКА: не могу передать камеру. cloud_spawner=", cloud_spawner, " camera=", camera, " cloud_container=", cloud_container)
	
	# Сбрасываем состояние игры и начинаем уровень
	GameState.start_game(1)

func _process(delta: float) -> void:
	if not level_complete:
		level_duration += delta
		
		# Камера следует за игроком по горизонтали (эффект полёта вперёд)
		if player and camera:
			# Камера движется вместе с игроком по X
			# Увеличенное смещение держит игрока левее на экране
			camera.global_position.x = player.global_position.x + 550
			# По Y остаётся в центре экрана
			camera.global_position.y = 360

func _on_player_dead() -> void:
	"""Обработка смерти игрока"""
	if level_complete:
		return
	
	level_complete = true
	
	# Останавливаем спавнеры
	if enemy_spawner:
		enemy_spawner.stop_spawning()
	if cloud_spawner:
		cloud_spawner.stop_spawning()
	
	# Завершаем игру с поражением
	await get_tree().create_timer(1.0).timeout
	_end_level("Поражение")

func _on_boss_defeated() -> void:
	"""Обработка победы над боссом"""
	if level_complete:
		return
	
	level_complete = true
	
	# Останавливаем спавнеры
	if enemy_spawner:
		enemy_spawner.stop_spawning()
	if cloud_spawner:
		cloud_spawner.stop_spawning()
	
	# Завершаем игру с победой
	await get_tree().create_timer(1.0).timeout
	_end_level("Победа")

func _end_level(result: String) -> void:
	"""Завершает уровень с передачей статистики"""
	# Получаем статистику из GameState
	var stats = GameState.get_stats()
	
	# Добавляем информацию о кампании
	stats["is_campaign"] = true
	stats["level"] = 1
	stats["duration_sec"] = level_duration
	
	# Эмитим сигнал завершения игры
	GameState.game_ended.emit(result, stats)
