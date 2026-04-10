extends CharacterBody3D

enum State { WANDER, CHASE }
@export var current_state = State.WANDER
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

var is_dead: bool = false
var last_state: State = State.WANDER
var last_damage_time: float = 0.0
var damage_cooldown: float = 0.1

func damage(amount: int):
	if Time.get_ticks_msec() - last_damage_time < damage_cooldown * 1000:
		return
	last_damage_time = Time.get_ticks_msec()
	rpc_id(1, "server_damage", amount)


func _ready():
	if not is_multiplayer_authority():
		set_physics_process(false)
		return
		
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	_pick_random_wander_target()
	anim.play("Walk")
	$Timer.wait_time = 1.0
	$Timer2.wait_time = 0.2

func _physics_process(_delta):
	if not is_multiplayer_authority(): return


func _pick_random_wander_target():
	var random_offset = Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	wander_target = global_position + random_offset

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
	if not multiplayer.is_server() or is_dead:
		return
		
	health -= amount
	particles.emitting = true
	if health <= 0:
		is_dead = true
		rpc("kill_enemy")

@rpc("any_peer", "call_local")
func kill_enemy():
	set_physics_process(false)
	if mesh: mesh.visible = false
	if collider: collider.set_deferred("disabled", true)
	await get_tree().create_timer(1.0).timeout
	queue_free()


func _on_timer_timeout() -> void:
	if is_dead:
		return
		
	match current_state:
		State.WANDER:
			if last_state != current_state:
				anim.play("Walk")
				anim.speed_scale = 2.5
				last_state = current_state
			if nav_agent.is_navigation_finished():
				_pick_random_wander_target()
			nav_agent.target_position = wander_target
			
		State.CHASE:
			if last_state != current_state:
				anim.play("run")
				anim.speed_scale = 5
				last_state = current_state
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
	if is_dead:
		return
	
	var look_target = global_position
	
	if current_state == State.CHASE and is_instance_valid(target_node):
		look_target = target_node.global_position
	elif velocity.length() > 0.1:
		look_target = global_position + velocity
	else:
		look_target = global_position + (nav_agent.get_next_path_position() - global_position).normalized()
	
	if look_target != global_position:
		look_at(look_target, Vector3.UP)
