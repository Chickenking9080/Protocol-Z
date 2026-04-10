extends Node3D

@export var mesh = Node3D
@export var meshGROWN = Node3D
@onready var timer = $Timer

func _ready() -> void:
	meshGROWN.visible = false
	timer.start()
	
	if is_multiplayer_authority():
		timer.timeout.connect(_on_timer_timeout)


func _on_timer_timeout() -> void:
	set_mesh_grown_visible.rpc(true)


@rpc("authority", "call_local")
func set_mesh_grown_visible(visible: bool) -> void:
	meshGROWN.visible = visible
