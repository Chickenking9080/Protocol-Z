extends Node3D

@export_group("Loot Settings")
@export var loot_scenes: Array[PackedScene] = []
@export var max_loot_spawns: int = 10

@export_group("Spawn Settings")
@export var spawn_interval: float = 600.0
@export var spawn_radius: float = 100.0
@export var spawn_height: float = 5.0

@export_group("Enemy Spawner Features")
@export var require_server: bool = true
@export var use_spawn_amount: bool = true
@export var spawn_amount: int = 1
@export var use_exit_tracking: bool = true

var spawn_timer: Timer
var active_loot_count: int = 0

func _ready():

	if loot_scenes.is_empty():
		push_error("LootSpawner: No loot scenes assigned in Inspector!")
		return

	if require_server and not multiplayer.is_server():
		return

	spawn_timer = Timer.new()
	add_child(spawn_timer)
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_loot)
	spawn_timer.start()

	print("LootSpawner started. Spawning every ", spawn_interval, " seconds")
	_spawn_one()
func _on_spawn_loot():
	if require_server and not multiplayer.is_server():
		return

	if use_spawn_amount:
		for i in range(spawn_amount):
			if active_loot_count < max_loot_spawns:
				_spawn_one()
	else:
		_spawn_one()

func _spawn_one():
	if loot_scenes.is_empty():
		return
	if active_loot_count >= max_loot_spawns:
		return

	var scene_index = randi() % loot_scenes.size()
	var random_angle = randf() * TAU
	var random_dist = randf_range(0, spawn_radius)
	var spawn_pos = Vector3(
		cos(random_angle) * random_dist,
		spawn_height,
		sin(random_angle) * random_dist
	) + global_position

	# Only server should call this
	if multiplayer.is_server():
		rpc("spawn_loot_on_all", scene_index, spawn_pos)

@rpc("any_peer", "call_local", "reliable")
func spawn_loot_on_all(scene_index: int, spawn_pos: Vector3):
	if scene_index >= loot_scenes.size():
		return

	var loot_instance = loot_scenes[scene_index].instantiate()
	loot_instance.global_position = spawn_pos  # Set position BEFORE adding to tree

	var level = get_tree().current_scene.find_child("World", true, false)
	if level:
		level.add_child(loot_instance)
	else:
		get_tree().current_scene.add_child(loot_instance)

	# Server-side tracking only
	if multiplayer.is_server():
		active_loot_count += 1
		if use_exit_tracking:
			loot_instance.tree_exited.connect(_on_loot_removed)

	print("Spawned loot at ", spawn_pos, " | Active: ", active_loot_count)

func _on_loot_removed():
	active_loot_count -= 1
	if active_loot_count < 0:
		active_loot_count = 0

func get_active_loot_count() -> int:
	return active_loot_count
