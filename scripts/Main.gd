extends Node

@export var player_scene: PackedScene = preload("res://scenes/Player.tscn")
@export var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")
@onready var spawn_player: Node2D = $SpawnPlayer if has_node("SpawnPlayer") else null
@onready var spawn_enemy: Node2D = $SpawnEnemy if has_node("SpawnEnemy") else null

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
