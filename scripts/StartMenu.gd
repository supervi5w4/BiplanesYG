extends Control

func _ready() -> void:
	if OS.has_feature("yandex"):
		# Р‘Р°Р·РѕРІР°СЏ РёРЅРёС†РёР°Р»РёР·Р°С†РёСЏ SDK
		YandexSDK.init_game()
		YandexSDK.init_player()
		YandexSDK.data_loaded.connect(_on_data_loaded)
		# Р’С‹Р·РѕРІРµРј game_ready РїРѕСЃР»Рµ С‚РѕРіРѕ, РєР°Рє UI СЂРµР°Р»СЊРЅРѕ РїРѕРєР°Р·Р°РЅ:
		call_deferred("_mark_game_ready")

func _mark_game_ready() -> void:
	if OS.has_feature("yandex"):
		YandexSDK.game_ready()
		# Р—Р°РїСЂРѕСЃРёРј РѕР±Р»Р°С‡РЅС‹Рµ РґР°РЅРЅС‹Рµ РїРѕ РєР»СЋС‡Сѓ GameState.SAVE_KEY
		YandexSDK.load_data([GameState.SAVE_KEY])

func _on_data_loaded(data: Dictionary) -> void:
	GameState.apply_cloud_save(data)

func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/battlefield.tscn")
