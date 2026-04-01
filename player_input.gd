extends MultiplayerSynchronizer

@export var jumping := false
@export var direction := Vector2()

func _ready():
	set_process(get_multiplayer_authority() == multiplayer.get_unique_id())

@rpc("call_local")
func jump():
	jumping = true

func _process(_delta):
	direction = Input.get_vector("left", "right", "forward", "back")
	
	if Input.is_action_just_pressed("jump"):
		jump.rpc()
