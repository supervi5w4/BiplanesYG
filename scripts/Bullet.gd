extends Area2D
@export var speed := 800.0
var velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	monitoring = true
	connect("body_entered", Callable(self, "_on_Bullet_body_entered"))

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	var safe_rect := get_viewport_rect().grow(64)
	if not safe_rect.has_point(global_position):
		queue_free()

func _on_Bullet_body_entered(body: Node) -> void:
	if body == self:
		return
	if body.has_method("apply_damage"):
		body.apply_damage(10)
	queue_free()
