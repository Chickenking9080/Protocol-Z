extends Area3D

@export var health: int = 50
@export var log_scene: PackedScene
@export var mesh: MeshInstance3D
@export var collider: CollisionShape3D
@onready var bark_particles = $tree/GPUParticles3D
@onready var leaf_particles = $tree/GPUParticles3D2
@onready var animation = $tree/AnimationPlayer
@onready var hit = $hit_sound
@onready var fall = $fall_sound
var done = false

func damage(amount: int):
	rpc_id(1, "server_damage", amount)

@rpc("any_peer", "call_local")
func server_damage(amount: int):
	if not multiplayer.is_server():
		return
		
	health -= amount
	animation.play("shake")
	hit.play()
	leaf_particles.emitting = true
	bark_particles.emitting = true
	if health <= 0:
		break_tree_logic()

func break_tree_logic():
	if done == true:
		pass
	else:
		if log_scene:
			for i in range(2):
				var log_instance = log_scene.instantiate()
				# Add the log
				done = true
				get_parent().add_child(log_instance, true) 
				log_instance.global_position = global_position + Vector3(randf(), 4.0, randf())
				fall.play()
				# FORCE WAIT: This prevents the "Node not found" errors on clients
				await get_tree().process_frame

	rpc("sync_tree_break")

@rpc("any_peer", "call_local")
func sync_tree_break():
	animation.play("fall")
	await get_tree().create_timer(0.5).timeout
	if mesh: mesh.visible = false
	if collider: collider.set_deferred("disabled", true)
	
	await get_tree().create_timer(1.0).timeout
	queue_free()
