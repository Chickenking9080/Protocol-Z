extends CharacterBody3D

enum State { WANDER, CHASE }
@export var current_state = State.WANDER #this is synced bc it will let the clients know what the ai should be doing
@onready var mesh = $zombie
@onready var collider = $CollisionShape3D
@export var speed: float = 3.0
@export var wander_range: float = 25
@export var chase_speed: float = 7
@export var health: int = 100
var target_node: Node3D = null
var wander_target: Vector3
@onready var anim = $zombie/AnimationPlayer
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var particles = $GPUParticles3D

func damage(amount: int):
	rpc_id(1, "server_damage", amount)


func _ready():
	if not is_multiplayer_authority():
		set_physics_process(false) #stop logic on clients
		return
		
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	_pick_random_wander_target()

func _physics_process(_delta):
	#double check we are the server if not dont do this crap, let the server sync it to you
	if not is_multiplayer_authority(): return


func _pick_random_wander_target():
	var random_offset = Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	wander_target = global_position + random_offset

# signals to set it to chase or not chase

func _on_area_3d_body_entered(body):
	if not is_multiplayer_authority(): return
	
	if body.is_in_group("player"):
		target_node = body
		current_state = State.CHASE

func _on_area_3d_body_exited(body):
	if not is_multiplayer_authority(): return
	
	if body == target_node:
		target_node = null
		current_state = State.WANDER

func _on_velocity_computed(safe_velocity: Vector3):
	velocity = safe_velocity
	move_and_slide()

@rpc("any_peer", "call_local")
func server_damage(amount: int):
	if not multiplayer.is_server():
		return
		
	health -= amount
	particles.emitting = true
	if health <= 0:
		rpc("kill_enemy")

@rpc("any_peer", "call_local")
func kill_enemy():
	if mesh: mesh.visible = false
	if collider: collider.set_deferred("disabled", true)
	await get_tree().create_timer(1.0).timeout
	queue_free()


func _on_timer_timeout() -> void:
	match current_state:
		State.WANDER:
			anim.play("Walk")
			anim.speed_scale = 2.5
			if nav_agent.is_navigation_finished():
				_pick_random_wander_target()
			nav_agent.target_position = wander_target
			
		State.CHASE:
			anim.play("run")
			anim.speed_scale = 5
			if is_instance_valid(target_node):
				nav_agent.target_position = target_node.global_position
			else:
				current_state = State.WANDER

	if not nav_agent.is_navigation_finished():
		var next_path_pos = nav_agent.get_next_path_position()
		var move_speed = chase_speed if current_state == State.CHASE else speed
		var new_velocity = (next_path_pos - global_position).normalized() * move_speed
		nav_agent.set_velocity(new_velocity)



func _on_timer_2_timeout() -> void:
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP)
