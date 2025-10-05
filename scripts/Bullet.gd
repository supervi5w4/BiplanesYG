extends Area2D
@export var speed := 800.0
var velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	monitoring = true
	connect("body_entered", Callable(self, "_on_Bullet_body_entered"))

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	
	# Проверка на выход за границы экрана - удаляем пулю
	var viewport_rect := get_viewport_rect()
	var safe_rect := viewport_rect.grow(50)  # Небольшой запас для корректного удаления
	
	if not safe_rect.has_point(global_position):
		queue_free()

func _on_Bullet_body_entered(body: Node) -> void:
	if body == self:
		return
	# Не сталкиваемся с игроком (Player)
	if body.name == "Player":
		return
	if body.has_method("apply_damage"):
		body.apply_damage(10)
	queue_free()
