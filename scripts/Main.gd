extends Node

@export var player_scene: PackedScene = preload("res://scenes/Player.tscn")
@onready var spawn: Node2D = $Spawn if has_node("Spawn") else null

func _ready() -> void:
	_init_world()
	_spawn_player()

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
