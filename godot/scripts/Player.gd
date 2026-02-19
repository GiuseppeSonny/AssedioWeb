extends CharacterBody2D

@export var is_local: bool = true

const SPEED: float = 80.0

func _physics_process(_delta: float) -> void:
	if not is_local:
		return
	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	).normalized()
	velocity = dir * SPEED
	move_and_slide()
	position = position.clamp(Vector2(10, 10), Vector2(310, 230))
