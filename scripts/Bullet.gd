extends Area2D
@export var speed := 800.0
var velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	monitoring = true
	connect("body_entered", Callable(self, "_on_Bullet_body_entered"))

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	
	# Заворачивание за края экрана
	_wrap_around_screen()
	
	# Проверка на выход за безопасную зону (с запасом)
	var safe_rect := get_viewport_rect().grow(64)
	if not safe_rect.has_point(global_position):
		queue_free()

func _on_Bullet_body_entered(body: Node) -> void:
	if body == self:
		return
	if body.has_method("apply_damage"):
		body.apply_damage(10)
	queue_free()

# === ЗАВОРАЧИВАНИЕ ЗА КРАЯ ЭКРАНА ===
func _wrap_around_screen() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_width: float = viewport_size.x
	var _screen_height: float = viewport_size.y
	
	# Заворачивание по горизонтали
	if global_position.x < 0:
		global_position.x = screen_width
	elif global_position.x > screen_width:
		global_position.x = 0
	
	# Ограничение высоты для пуль - удаляем если слишком высоко
	var max_height: float = 50.0  # Максимальная высота для пуль
	if global_position.y < max_height:
		queue_free()
