extends Control

func _ready() -> void:
	if OS.has_feature("yandex"):
		# Базовая инициализация SDK
		YandexSDK.init_game()
		YandexSDK.init_player()
		YandexSDK.data_loaded.connect(_on_data_loaded)
		# Вызовем game_ready после того, как UI реально показан:
		call_deferred("_mark_game_ready")

func _mark_game_ready() -> void:
	if OS.has_feature("yandex"):
		YandexSDK.game_ready()
		# Запросим облачные данные по ключу GameState.SAVE_KEY
		YandexSDK.load_data([GameState.SAVE_KEY])

func _on_data_loaded(data: Dictionary) -> void:
	GameState.apply_cloud_save(data)

func _on_Button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_button_pressed() -> void:
	pass # Replace with function body.
