extends CanvasLayer
# ─────────────────────────────────────────────────────────────────────────────
# EnemyIndicators.gd — индикаторы врагов за пределами экрана
# ─────────────────────────────────────────────────────────────────────────────

@export var indicator_color: Color = Color.RED
@export var indicator_size: float = 25.0  # Размер треугольника
@export var edge_offset: float = 15.0     # Отступ от края экрана

var control_node: Control

func _ready() -> void:
	# Создаём Control узел для рисования
	control_node = Control.new()
	control_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	control_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control_node)
	
	# Подключаем сигнал для перерисовки
	control_node.draw.connect(_on_draw)

func _process(_delta: float) -> void:
	# Перерисовываем каждый кадр
	if control_node:
		control_node.queue_redraw()

func _on_draw() -> void:
	if not control_node:
		return
	
	# Получаем камеру и размер viewport
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return
	
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Вычисляем границы видимой области
	var camera_pos = camera.global_position
	var half_viewport = viewport_size / 2.0
	var right_edge = camera_pos.x + half_viewport.x
	
	# Получаем всех врагов
	var enemies = get_tree().get_nodes_in_group("enemy")
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		
		# Проверяем, жив ли враг
		if enemy.has_method("get_is_alive") and not enemy.get_is_alive():
			continue
		
		var enemy_pos = enemy.global_position
		
		# Проверяем, находится ли враг справа за пределами экрана
		if enemy_pos.x > right_edge:
			# Рисуем индикатор
			_draw_indicator(enemy_pos, camera_pos, viewport_size)

func _draw_indicator(enemy_pos: Vector2, camera_pos: Vector2, viewport_size: Vector2) -> void:
	# Вычисляем Y-координату врага относительно камеры
	var half_viewport = viewport_size / 2.0
	var top_edge = camera_pos.y - half_viewport.y
	
	# Y-координата индикатора (ограничиваем в пределах экрана)
	var indicator_y = enemy_pos.y - top_edge
	indicator_y = clamp(indicator_y, indicator_size, viewport_size.y - indicator_size)
	
	# X-координата индикатора (у правого края)
	var indicator_x = viewport_size.x - edge_offset
	
	# Позиция индикатора на экране
	var indicator_pos = Vector2(indicator_x, indicator_y)
	
	# Рисуем треугольник, указывающий направление врага
	_draw_triangle(indicator_pos)

func _draw_triangle(pos: Vector2) -> void:
	# Создаём треугольник, указывающий вправо
	var points = PackedVector2Array()
	var half_size = indicator_size / 2.0
	
	# Вершины треугольника (указывает вправо)
	points.append(pos + Vector2(half_size * 0.5, 0))           # Правая вершина
	points.append(pos + Vector2(-half_size * 0.5, -half_size)) # Верхняя левая
	points.append(pos + Vector2(-half_size * 0.5, half_size))  # Нижняя левая
	
	# Рисуем закрашенный треугольник
	control_node.draw_colored_polygon(points, indicator_color)
	
	# Рисуем контур для лучшей видимости
	control_node.draw_polyline(points + PackedVector2Array([points[0]]), Color.BLACK, 2.0)
