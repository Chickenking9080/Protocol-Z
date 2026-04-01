extends Node3D

@export var enemy_scene: PackedScene
@export var max_zombies: int = 8
@export var spawn_amount: int = 1

@onready var timer = $Timer

var current_zombies: int = 0

func _ready():
	timer.start()

func spawn_enemy():
	if not multiplayer.is_server():
		return
	if enemy_scene == null:
		return

	if current_zombies >= max_zombies:
		return

	var e = enemy_scene.instantiate()
	get_parent().call_deferred("add_child", e, true)

	await get_tree().process_frame

	e.global_position = global_position + Vector3(randf_range(-5, 5), 4.0, randf_range(-5, 5))

	current_zombies += 1

	e.tree_exited.connect(_on_enemy_removed)

func _on_enemy_removed():
	current_zombies -= 1
	if current_zombies < 0:
		current_zombies = 0

func _on_timer_timeout():
	if not multiplayer.is_server():
		return
	for i in range(spawn_amount):
		if current_zombies < max_zombies:
			spawn_enemy()
