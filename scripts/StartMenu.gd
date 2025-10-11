extends Control

func _ready() -> void:
	_setup_button_style()
	# Подключаем сигнал изменения размера окна для адаптивности
	get_viewport().size_changed.connect(_on_viewport_size_changed)
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

func _on_campaign_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/campaign/level1.tscn")

func _on_viewport_size_changed() -> void:
	# Пересчитываем размеры при изменении размера окна
	call_deferred("_setup_button_style")

func _setup_button_style() -> void:
	# Получаем размер экрана для адаптивного дизайна
	var screen_size = get_viewport().get_visible_rect().size
	
	# Более консервативные пропорции для лучшей адаптивности
	var button_width = int(screen_size.x * 0.25)  # 25% от ширины экрана (было 30%)
	var button_height = int(screen_size.y * 0.06)  # 6% от высоты экрана (было 8%)
	
	# Минимальные и максимальные размеры для разных экранов
	button_width = max(button_width, 120)  # Минимум 120px (было 150px)
	button_width = min(button_width, int(screen_size.x * 0.4))  # Максимум 40% от ширины
	button_height = max(button_height, 35)  # Минимум 35px (было 40px)
	button_height = min(button_height, int(screen_size.y * 0.1))  # Максимум 10% от высоты
	
	# Стилизуем обе кнопки
	var buttons = [$VBoxContainer/Button, $VBoxContainer/ButtonCampaign]
	for button in buttons:
		if not button:
			continue
			
		# Дополнительная проверка - убеждаемся что кнопка помещается в контейнер
		var container_width = $VBoxContainer.size.x
		var btn_width = button_width
		if container_width > 0:  # Если контейнер уже имеет размер
			btn_width = min(btn_width, int(container_width * 0.9))  # Максимум 90% от контейнера
		
		# Устанавливаем адаптивный размер
		button.custom_minimum_size = Vector2(btn_width, button_height)
		
		# Создаем пиксельные текстуры для кнопки
		var normal_texture = _create_pixel_button_texture(btn_width, button_height, false)
		var hover_texture = _create_pixel_button_texture(btn_width, button_height, true)
		var pressed_texture = _create_pixel_button_texture(btn_width, button_height, false, true)
		
		# Создаем стиль кнопки с пиксельными текстурами
		var button_style = StyleBoxTexture.new()
		button_style.texture = normal_texture
		button_style.texture_margin_left = 8
		button_style.texture_margin_right = 8
		button_style.texture_margin_top = 8
		button_style.texture_margin_bottom = 8
		
		# Применяем стиль к кнопке
		button.add_theme_stylebox_override("normal", button_style)
		
		# Стиль для наведения (hover)
		var hover_style = StyleBoxTexture.new()
		hover_style.texture = hover_texture
		hover_style.texture_margin_left = 8
		hover_style.texture_margin_right = 8
		hover_style.texture_margin_top = 8
		hover_style.texture_margin_bottom = 8
		button.add_theme_stylebox_override("hover", hover_style)
		
		# Стиль для нажатия (pressed)
		var pressed_style = StyleBoxTexture.new()
		pressed_style.texture = pressed_texture
		pressed_style.texture_margin_left = 8
		pressed_style.texture_margin_right = 8
		pressed_style.texture_margin_top = 8
		pressed_style.texture_margin_bottom = 8
		button.add_theme_stylebox_override("pressed", pressed_style)
		
		# Адаптивный размер шрифта
		var font_size = int(screen_size.y * 0.025)  # 2.5% от высоты экрана
		font_size = max(font_size, 12)  # Минимальный размер
		font_size = min(font_size, 24)  # Максимальный размер
		
		# Настраиваем шрифт
		var font = ThemeDB.fallback_font
		if font:
			button.add_theme_font_override("font", font)
			button.add_theme_font_size_override("font_size", font_size)
		
		# Цвет текста - светлый для контраста
		button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8, 1.0))
		button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.9, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(0.8, 0.8, 0.7, 1.0))
	
	# Также стилизуем заголовок
	var label = $VBoxContainer/Label
	if label:
		# Цвет заголовка - теплый оранжевый как в небе
		label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2, 1.0))  # Оранжевый
		label.add_theme_color_override("font_shadow_color", Color(0.3, 0.2, 0.1, 1.0))  # Темная тень
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		
		# Адаптивный размер шрифта для заголовка
		var title_font_size = int(screen_size.y * 0.04)  # 4% от высоты экрана
		title_font_size = max(title_font_size, 18)  # Минимальный размер
		title_font_size = min(title_font_size, 36)  # Максимальный размер
		label.add_theme_font_size_override("font_size", title_font_size)
		
		# Добавляем пиксельный эффект для заголовка
		label.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.05, 1.0))  # Темная обводка
		label.add_theme_constant_override("outline_size", 2)  # Толщина обводки

func _create_pixel_button_texture(width: int, height: int, is_hover: bool = false, is_pressed: bool = false) -> ImageTexture:
	# Создаем изображение для пиксельной кнопки
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	
	# Определяем цвета в зависимости от состояния
	var base_color: Color
	var border_color: Color
	var highlight_color: Color
	
	if is_pressed:
		# Нажатое состояние - темнее
		base_color = Color(0.4, 0.25, 0.1, 1.0)  # Темно-коричневый
		border_color = Color(0.2, 0.1, 0.05, 1.0)  # Очень темно-коричневый
		highlight_color = Color(0.3, 0.2, 0.1, 1.0)  # Средне-коричневый
	elif is_hover:
		# Наведение - светлее
		base_color = Color(0.7, 0.5, 0.3, 1.0)  # Светло-коричневый
		border_color = Color(0.4, 0.3, 0.15, 1.0)  # Коричневый
		highlight_color = Color(0.8, 0.6, 0.4, 1.0)  # Светло-коричневый
	else:
		# Обычное состояние
		base_color = Color(0.6, 0.4, 0.2, 1.0)  # Коричневый
		border_color = Color(0.3, 0.2, 0.1, 1.0)  # Темно-коричневый
		highlight_color = Color(0.7, 0.5, 0.3, 1.0)  # Светло-коричневый
	
	# Заполняем основным цветом
	for x in range(width):
		for y in range(height):
			image.set_pixel(x, y, base_color)
	
	# Рисуем пиксельную границу (3 пикселя)
	var border_width = 3
	for x in range(width):
		for y in range(height):
			if x < border_width or x >= width - border_width or y < border_width or y >= height - border_width:
				image.set_pixel(x, y, border_color)
	
	# Добавляем пиксельные блики для объема
	var highlight_width = 2
	for x in range(highlight_width, width - border_width):
		for y in range(highlight_width, border_width + highlight_width):
			image.set_pixel(x, y, highlight_color)
	
	# Добавляем тень снизу и справа для эффекта объема
	var shadow_color = Color(0.2, 0.1, 0.05, 0.5)
	for x in range(border_width, width):
		for y in range(height - border_width, height):
			if x >= width - border_width or y >= height - border_width:
				image.set_pixel(x, y, shadow_color)
	
	# Создаем текстуру из изображения
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture
