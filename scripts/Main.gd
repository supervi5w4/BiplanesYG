extends Node

@export var player_scene: PackedScene = preload("res://scenes/Player.tscn")
@export var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")
@onready var spawn: Node2D = $Spawn if has_node("Spawn") else null

func _ready() -> void:
	_init_world()
	_spawn_player()
	_spawn_enemy()

func _init_world() -> void:
	# здесь же можно подготовить фон, коллайдеры границ и т.п.
	pass

func _spawn_player() -> void:
	if player_scene:
		var p := player_scene.instantiate()
		if spawn:
			p.global_position = spawn.global_position
		add_child(p)
	GameState.start_game(1)

func _spawn_enemy() -> void:
	if enemy_scene:
		var e := enemy_scene.instantiate()
		
		# Получаем точку спавна игрока или используем координату по умолчанию
		var spawn_position: Vector2
		if spawn:
			spawn_position = spawn.global_position
		else:
			spawn_position = Vector2(1280, 720) * 0.75
		
		# Задаем зеркальную позицию относительно игрока
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var enemy_position: Vector2 = Vector2(viewport_size.x - spawn_position.x, spawn_position.y)
		
		e.global_position = enemy_position
		add_child(e)
