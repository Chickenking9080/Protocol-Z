extends CharacterBody3D

# --- Configuration & Stats ---
var health = 100
var SPEED = 5
const JUMP_VELOCITY = 4.5
var mouse_sensitivity = 0.1
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var hunger = 100
var thirst = 100
@export var player = 1

# --- Pickable Item Scenes ---
@export var log_scene: PackedScene
@export var rock_scene: PackedScene

# --- Buildable Structure Scenes ---
# Each structure needs a placed scene and a ghost (preview) scene.
# Assign all of these in the Inspector on the player node.

@export var house_scene: PackedScene
@export var house_ghost_scene: PackedScene

@export var campfire_scene: PackedScene
@export var campfire_ghost_scene: PackedScene

@export var table_scene: PackedScene
@export var table_ghost_scene: PackedScene

@export var bed_scene: PackedScene
@export var bed_ghost_scene: PackedScene

@export var bridge_scene: PackedScene
@export var bridge_ghost_scene: PackedScene

@export var tent_scene: PackedScene
@export var tent_ghost_scene: PackedScene

@export var raspberry_bush_scene: PackedScene
@export var raspberry_bush_ghost_scene: PackedScene

@export var lamp_scene: PackedScene
@export var lamp_ghost_scene: PackedScene

@export var wall_scene: PackedScene
@export var wall_ghost_scene: PackedScene

@export var floor_scene: PackedScene
@export var floor_ghost_scene: PackedScene

# --- Structure Registry ---
# Populated in _ready(). Each entry: { "ghost": PackedScene, "scene": PackedScene, "requires_item": String }
# "requires_item" is optional — if set, that inventory item is consumed on placement.
# To add a new structure in future: add @export vars above, then one _register_structure() call in _ready().
var structures: Dictionary = {}

# --- Node References ---
@onready var axe = $Camera3D/axe
@onready var camera = $Camera3D
@onready var ray = $Camera3D/RayCast3D
@onready var ray2 = $Camera3D/RayCast3D2
@onready var hold_pos = $Camera3D/HoldPosition
@onready var input_node = $PlayerInput
@onready var inventory_menu = $UI/InventoryMenu
@onready var torch = $Camera3D/torch
@onready var health_bar = $Camera3D/Control2/Health
@onready var hunger_bar = $Camera3D/Control2/Hunger
@onready var thirst_bar = $Camera3D/Control2/Thirst
@onready var name_label = $Label3D
@onready var log_label = $UI/InventoryMenu/VBox/LogLabel
@onready var rock_label = $UI/InventoryMenu/VBox/RockLabel
@onready var food_label = $UI/InventoryMenu/VBox/FoodLabel
@onready var water_label = $UI/InventoryMenu/VBox/WaterLabel
var chat_input

# --- State ---
var mode = "HANDS"
var inventory = {
	"logs": 0,
	"rocks": 0,
	"water": 0,
	"food": 0,
	"raspberry_seed": 0
}

var is_menu_open = false
var held_item = null
var current_ghost = null
var losing_health = false
var throw_force = 0.0
const MAX_THROW_FORCE = 20.0
var current_structure_key = ""

# --- Authority ---

func _enter_tree():
	set_multiplayer_authority(name.to_int())

func _ready():
	add_to_group("players")
	chat_input = get_tree().root.find_child("Input", true, false)
	# --- Register all buildable structures here ---
	# Signature: _register_structure("key", ghost_scene, placed_scene, requires_item="")
	# requires_item: inventory key consumed on placement. Leave blank if no item needed.
	_register_structure("house",          house_ghost_scene,          house_scene)
	_register_structure("campfire",       campfire_ghost_scene,       campfire_scene)
	_register_structure("table",          table_ghost_scene,          table_scene)
	_register_structure("bed",            bed_ghost_scene,            bed_scene)
	_register_structure("bridge",         bridge_ghost_scene,         bridge_scene)
	_register_structure("tent",           tent_ghost_scene,           tent_scene)
	_register_structure("raspberry_bush", raspberry_bush_ghost_scene, raspberry_bush_scene)
	_register_structure("lamp",           lamp_ghost_scene,           lamp_scene)
	_register_structure("wall",           wall_ghost_scene,           wall_scene)
	_register_structure("floor",           floor_ghost_scene,           floor_scene)

	if inventory_menu:
		inventory_menu.hide()

	health = 100
	health_bar.value = health

	if is_multiplayer_authority():
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		$Camera3D/Control2.visible = true
		$UI.visible = true
	else:
		$Camera3D/Control2.visible = false
		$UI.visible = false

	_update_mode_visuals()

# Registers a structure. requires_item is optional — if set, that item is consumed on placement.
func _register_structure(key: String, ghost: PackedScene, scene: PackedScene, requires_item: String = ""):
	if ghost == null or scene == null:
		push_error("_register_structure: null scene assigned for '" + key + "' — check Inspector exports.")
		return
	structures[key] = {
		"ghost": ghost,
		"scene": scene,
		"requires_item": requires_item
	}

# --- INPUT ---

func _input(event):
	if not is_multiplayer_authority():
		return

	if event.is_action_pressed("inventory"):
		if chat_input and chat_input.is_visible_in_tree():
			return
		toggle_inventory()

	if is_menu_open:
		return

	# 👇 mouse capture (web + desktop)
	if event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# 👇 camera movement (BOTH)
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		camera.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	if Input.is_action_just_pressed("crouch"):
		scale.y = 0.5
	if Input.is_action_just_released("crouch"):
		scale.y = 1

	if event.is_action_pressed("attack"):
		if mode == "BUILDING":
			place_structure()
		elif held_item:
			rpc("drop_item_rpc", 2.0)
		else:
			handle_interaction()

	if event.is_action_released("secondary_attack") and held_item:
		rpc("drop_item_rpc", clamp(throw_force, 5.0, MAX_THROW_FORCE))
		throw_force = 0.0

	if event.is_action_pressed("interact") and held_item:
		stash_held_item()

	if Input.is_action_just_pressed("run"):
		SPEED = 10
		camera.fov = 70
	if Input.is_action_just_released("run"):
		SPEED = 5
		camera.fov = 64.4
	if Input.is_action_just_pressed("2"):
		mode = "AXE"
		_update_mode_visuals()
	if Input.is_action_just_pressed("1"):
		mode = "HANDS"
		_update_mode_visuals()
	if Input.is_action_just_pressed("3"):
		mode = "TORCH"
		_update_mode_visuals()
# --- MOVEMENT ---

func _physics_process(delta):
	health_bar.value = health
	hunger_bar.value = hunger
	thirst_bar.value = thirst

	thirst -= 0.0007
	hunger -= 0.0007

	if SPEED == 10:
		thirst -= 0.01

	thirst = clamp(thirst, 0.0, 100.0)
	hunger = clamp(hunger, 0.0, 100.0)

	if losing_health:
		health -= 1

	if not is_on_floor():
		velocity.y -= gravity * delta

	if health <= 0:
		global_position = Vector3(0, 5.521, 0)
		health = 100

	if is_multiplayer_authority() and not is_menu_open:
		if held_item and Input.is_action_pressed("secondary_attack"):
			throw_force = move_toward(throw_force, MAX_THROW_FORCE, 30.0 * delta)

		var move_dir = Vector3(input_node.direction.x, 0, input_node.direction.y)
		var direction = (transform.basis * move_dir).normalized()

		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)

		if input_node.jumping and is_on_floor():
			velocity.y = JUMP_VELOCITY

		input_node.jumping = false
		move_and_slide()

	if mode == "BUILDING" and current_ghost and is_multiplayer_authority():
		update_ghost_position()

	if held_item and is_multiplayer_authority():
		held_item.global_position = hold_pos.global_position
		held_item.global_rotation = hold_pos.global_rotation

# --- UI ---

func toggle_inventory():
	is_menu_open = !is_menu_open
	inventory_menu.visible = is_menu_open
	_update_inventory_ui()
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE if is_menu_open else Input.MOUSE_MODE_CAPTURED
	)

func _update_inventory_ui():
	if log_label:
		log_label.text = "Logs: " + str(inventory["logs"])
	if rock_label:
		rock_label.text = "Rocks: " + str(inventory["rocks"])
	if food_label:
		food_label.text = "Food: " + str(inventory["food"])
	if water_label:
		water_label.text = "Water: " + str(inventory["water"])

func _update_mode_visuals():
	axe.visible = (mode == "AXE")
	torch.visible = (mode == "TORCH")
	if mode != "BUILDING" and current_ghost:
		current_ghost.queue_free()
		current_ghost = null

# --- BUTTONS ---

func _on_hand_button_pressed():
	mode = "HANDS"
	_update_mode_visuals()
	toggle_inventory()

func _on_axe_button_pressed():
	mode = "AXE"
	_update_mode_visuals()
	toggle_inventory()

func _on_torch_button_pressed():
	mode = "TORCH"
	_update_mode_visuals()
	toggle_inventory()

func _on_log_button_pressed():
	if inventory["logs"] > 0:
		rpc_id(1, "server_spawn_item_from_inv", "logs", multiplayer.get_unique_id())
		toggle_inventory()

func _on_rock_button_pressed():
	if inventory["rocks"] > 0:
		rpc_id(1, "server_spawn_item_from_inv", "rocks", multiplayer.get_unique_id())
		toggle_inventory()

# Universal build button handler.
# Connect any build button's pressed signal to this with the structure key as a Callable parameter,
# OR use the named wrappers below.
func _on_build_button_pressed(structure_key: String):
	if not structures.has(structure_key):
		push_error("_on_build_button_pressed: unknown structure key '" + structure_key + "'")
		return

	# Check if this structure requires an inventory item
	var required = structures[structure_key]["requires_item"]
	if required != "" and inventory.get(required, 0) <= 0:
		print("You need a " + required + " to place this.")
		return

	is_menu_open = false
	inventory_menu.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mode = "BUILDING"
	current_structure_key = structure_key
	start_building_mode(structure_key)

# --- Named button wrappers ---
# Connect each UI button's pressed signal to the matching function below.
func _on_craft_house_button_pressed():          _on_build_button_pressed("house")
func _on_craft_campfire_button_pressed():       _on_build_button_pressed("campfire")
func _on_craft_table_button_pressed():          _on_build_button_pressed("table")
func _on_craft_bed_button_pressed():            _on_build_button_pressed("bed")
func _on_craft_bridge_button_pressed():         _on_build_button_pressed("bridge")
func _on_craft_tent_button_pressed():           _on_build_button_pressed("tent")
func _on_craft_raspberry_bush_button_pressed(): _on_build_button_pressed("raspberry_bush")
func _on_craft_lamp_button_pressed():           _on_build_button_pressed("lamp")
func _on_craft_wall_button_pressed():           _on_build_button_pressed("wall")
func _on_craft_floor_button_pressed():           _on_build_button_pressed("floor")

# --- BUILDING ---

func start_building_mode(structure_key: String):
	if current_ghost:
		current_ghost.queue_free()
		current_ghost = null
	var ghost_scene = structures[structure_key]["ghost"]
	if ghost_scene == null:
		push_error("start_building_mode: ghost scene is null for '" + structure_key + "'")
		mode = "HANDS"
		return
	current_ghost = ghost_scene.instantiate()
	get_tree().current_scene.add_child(current_ghost)

func update_ghost_position():
	ray2.add_exception(self)
	if ray2.is_colliding():
		var p = ray2.get_collision_point()
		p.y = floor(p.y * 0) / 0
		current_ghost.global_position = p
	else:
		current_ghost.global_position = camera.global_position - camera.global_transform.basis.z * 5.0
	current_ghost.global_rotation.y = rotation.y

func place_structure():
	if not is_location_clear(current_ghost.global_position):
		print("Something is in the way!")
		return

	var spawn_pos = current_ghost.global_position
	var spawn_rot = current_ghost.global_rotation

	# Consume required item if any
	var required = structures[current_structure_key]["requires_item"]
	if required != "":
		inventory[required] -= 1
		_update_inventory_ui()

	rpc_id(1, "server_place_structure", current_structure_key, spawn_pos, spawn_rot)

	current_ghost.queue_free()
	current_ghost = null
	current_structure_key = ""
	mode = "HANDS"

func is_location_clear(pos: Vector3) -> bool:
	for blueprint in get_tree().get_nodes_in_group("Blueprints"):
		if blueprint.global_position.distance_to(pos) < 2.0:
			return false
	return true

# --- INTERACTION ---

func handle_interaction():
	$Camera3D/axe/AnimationPlayer.play("hit")
	if ray.is_colliding():
		var target = ray.get_collider()
		if mode == "HANDS" and target and target.is_in_group("pickable"):
			rpc("pick_up_item_rpc", target.get_path())
		elif mode == "AXE" and target and target.has_method("damage"):
			target.damage(10)

func stash_held_item():
	if held_item:
		var type = ""
		if held_item.is_in_group("log"):
			type = "logs"
		elif held_item.is_in_group("rock"):
			type = "rocks"
		elif held_item.is_in_group("water"):
			type = "water"
		elif held_item.is_in_group("food"):
			type = "food"
		elif held_item.is_in_group("raspberry_seed"):
			type = "raspberry_seed"
		if type != "":
			inventory[type] += 1
			rpc("delete_held_item_rpc", held_item.get_path())
			held_item = null
			_update_inventory_ui()

# --- RPCS ---

@rpc("any_peer", "call_local")
func pick_up_item_rpc(path):
	var item = get_node_or_null(path)
	if not item:
		return
	item.set_multiplayer_authority(multiplayer.get_remote_sender_id())
	held_item = item
	if item is CollisionObject3D:
		ray.add_exception(item)
	if item is RigidBody3D:
		item.freeze = true
	for c in item.get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)

@rpc("any_peer", "call_local")
func drop_item_rpc(force):
	if held_item:
		var item = held_item
		var level_node = get_tree().current_scene.find_child("Level", true, false)
		if item is CollisionObject3D:
			ray.remove_exception(item)
		for c in item.get_children():
			if c is CollisionShape3D:
				c.set_deferred("disabled", false)
		item.reparent(level_node if level_node else get_tree().current_scene)
		if item is RigidBody3D:
			item.freeze = false
			item.set_multiplayer_authority(1)
			var dir = (-camera.global_transform.basis.z + Vector3(0, 0.1, 0)).normalized()
			item.apply_central_impulse(dir * force)
		held_item = null

@rpc("any_peer", "call_local")
func delete_held_item_rpc(path):
	var item = get_node_or_null(path)
	if item:
		if item == held_item and item is CollisionObject3D:
			ray.remove_exception(item)
		item.queue_free()

# --- SERVER ---

@rpc("any_peer", "call_local")
func server_spawn_item_from_inv(type: String, p_id: int):
	if not multiplayer.is_server():
		return
	var level_node = get_tree().current_scene.find_child("Level", true, false)
	var scene_to_spawn = log_scene if type == "logs" else rock_scene
	var item = scene_to_spawn.instantiate()
	item.name = type + "_" + str(Time.get_ticks_msec())
	(level_node if level_node else get_tree().current_scene).add_child(item, true)
	item.global_position = hold_pos.global_position
	await get_tree().process_frame
	pick_up_item_rpc.rpc(item.get_path())
	rpc_id(p_id, "sync_inv_minus", type)

@rpc("any_peer", "call_local")
func sync_inv_minus(type: String):
	inventory[type] -= 1
	_update_inventory_ui()

# Unified RPC for placing any registered structure type.
@rpc("any_peer", "call_local")
func server_place_structure(structure_key: String, pos: Vector3, rot: Vector3):
	if not multiplayer.is_server():
		return
	if not structures.has(structure_key):
		push_warning("server_place_structure: unknown key '" + structure_key + "'")
		return
	spawn_structure_blueprint.rpc(structure_key, pos, rot)

@rpc("any_peer", "call_local", "reliable")
func spawn_structure_blueprint(structure_key: String, pos: Vector3, rot: Vector3):
	var level = get_tree().current_scene.find_child("Level", true, false)
	if not level:
		level = get_tree().current_scene
	var blueprint = structures[structure_key]["scene"].instantiate()
	level.add_child(blueprint)
	blueprint.global_position = pos
	blueprint.global_rotation = rot

# --- MISC ---

func set_username(uname):
	name_label.text = uname

func _on_area_3d_body_entered(body: Node3D):
	if body.is_in_group("enemy"):
		losing_health = true

func _on_area_3d_body_exited(body: Node3D) -> void:
	if body.is_in_group("enemy"):
		losing_health = false

func drink_water():
	if inventory["water"] > 0:
		inventory["water"] -= 1
		thirst = min(thirst + 50, 100.0)
		_update_inventory_ui()
	else:
		print("No water left!")

func _on_food_button_pressed() -> void:
	if inventory["food"] > 0:
		inventory["food"] -= 1
		hunger = min(hunger + 50, 100.0)
		_update_inventory_ui()
	else:
		print("No food to eat!")
