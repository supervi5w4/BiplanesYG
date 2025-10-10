extends Area2D
@export var speed := 800.0
@export var ignore_group: String = ""
var velocity: Vector2 = Vector2.ZERO
var fired_by_player: bool = false  # Флаг для отслеживания, кто выпустил пулю

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
	
	# Проверяем игнорирование группы
	if ignore_group != "" and body.is_in_group(ignore_group):
		return
	
	
	# Регистрируем попадание, если пуля выпущена игроком
	if fired_by_player:
		# Проверяем, что попали во врага
		if body.is_in_group("enemy"):
			GameState.register_hit(body)
	
	# Наносим урон и вызываем взрыв
	if body.has_method("apply_damage"):
		body.apply_damage(10)
	
	queue_free()
