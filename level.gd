extends Node3D

const SPAWN_RANDOM := 5.0
const PLAYER_SCENE := preload("res://player.tscn")

func _ready():
	if not multiplayer.is_server():
		return

	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)

	# Spawn existing peers
	for id in multiplayer.get_peers():
		add_player(id)

	# Spawn host
	add_player(multiplayer.get_unique_id())

func add_player(id: int):
	var character = PLAYER_SCENE.instantiate()
	# Set the ID property first
	character.player = id
	character.name = str(id)
	
	# NEW: Set authority HERE, before add_child
	character.set_multiplayer_authority(id)

	var pos := Vector2.from_angle(randf() * TAU)
	character.position = Vector3(
		pos.x * SPAWN_RANDOM * randf(),
		0,
		pos.y * SPAWN_RANDOM * randf()
	)

	$Players.add_child(character, true)

func remove_player(id: int):
	if $Players.has_node(str(id)):
		$Players.get_node(str(id)).queue_free()
