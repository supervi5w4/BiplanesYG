extends Node2D
# ─────────────────────────────────────────────────────────────────────────────
# Cloud.gd — облако на заднем фоне
# ─────────────────────────────────────────────────────────────────────────────

var camera: Camera2D = null
var viewport_width: float = 1280.0  # Ширина экрана по умолчанию
var despawn_margin: float = 200.0  # Дополнительный отступ за левым краем экрана

func _ready() -> void:
	print("[Cloud] Облако создано на позиции: ", global_position)
	
	# Получаем реальную ширину viewport
	viewport_width = get_viewport().get_visible_rect().size.x
	print("[Cloud] Ширина viewport: ", viewport_width)
	
	# Случайный масштаб для разнообразия
	var scale_factor = randf_range(0.7, 1.3)
	scale = Vector2(scale_factor, scale_factor)
	
	# Случайная прозрачность
	modulate.a = randf_range(0.6, 0.9)

func set_camera(cam: Camera2D) -> void:
	"""Устанавливает ссылку на камеру"""
	camera = cam
	print("[Cloud] Камера установлена: ", camera)

func _process(_delta: float) -> void:
	if camera:
		# Вычисляем левый край экрана
		# Камера находится в центре экрана, поэтому левый край = camera.x - (viewport_width / 2)
		var left_edge = camera.global_position.x - (viewport_width / 2.0)
		
		# Удаляем облако когда оно полностью ушло за левый край + запас
		if global_position.x < left_edge - despawn_margin:
			print("[Cloud] Облако удаляется. Позиция облака: ", global_position.x, " Левый край экрана: ", left_edge, " Позиция камеры: ", camera.global_position.x)
			queue_free()

