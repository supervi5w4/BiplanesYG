extends Node
signal save_updated(data: Dictionary)

var current_level: int = 1
var score: int = 0
var state: String = "idle"
var highest_unlocked_level: int = 1
const SAVE_KEY := "save"

func start_game(level: int) -> void:
	current_level = level
	score = 0
	state = "playing"
	_persist()

func end_game() -> void:
	state = "idle"
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
	_persist()

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
