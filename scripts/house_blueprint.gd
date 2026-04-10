extends Node3D

@export var buildable_name = str("null")
@export var logs_needed := 5
@export var rocks_needed := 3
@export var screws_needed := 0
@export var raspberry_needed := 0
@export var finished_house: PackedScene
@export var rocks_name: bool = false
@export var logs_name: bool = false
@export var screws_name: bool = false
@export var raspberry_name: bool = false
@onready var area: Area3D = $Area3D
@onready var label: Label3D = $Label3D
var hehe = null
var logs := 0
var rocks := 0
var screws := 0
var raspberry := 0


func _ready():
	print("Blueprint ready")
	area.body_entered.connect(_on_body_entered)
	update_label()


# -------------------------
# BODY ENTERED
# -------------------------

func _on_body_entered(body: Node):

	print("Body entered:", body.name)

	# If client detected collision → tell server
	if not multiplayer.is_server():
		if body:
			register_material.rpc_id(
				1,
				get_path(),          # which blueprint
				body.get_path()      # which item
			)
		return

	# Server handles normally
	process_material(body)


# -------------------------
# SERVER RECEIVES REQUEST
# -------------------------

@rpc("any_peer","call_local")
func register_material(blueprint_path: NodePath, item_path: NodePath):

	if not multiplayer.is_server():
		return

	var blueprint = get_node_or_null(blueprint_path)
	var body = get_node_or_null(item_path)

	if blueprint == null or body == null:
		print("Server couldn't find blueprint or item")
		return

	blueprint.process_material(body)


# -------------------------
# MATERIAL LOGIC
# -------------------------
@rpc("any_peer", "call_local", "reliable")
func destroy_object(node_path: NodePath):
	var node = get_node_or_null(node_path)
	if node:
		node.queue_free()

@rpc("call_remote")
func process_material(body: Node):

	var added := false

	if body.is_in_group("Logs"):

		if logs < logs_needed:
			logs += 1
			added = true
			print("Log added:", logs)

	elif body.is_in_group("Rocks"):

		if rocks < rocks_needed:
			rocks += 1
			added = true
			print("Rock added:", rocks)

	elif body.is_in_group("Screws"):
		if screws < screws_needed:
			screws += 1
			added = true
			print("Screw added:", screws)

	elif body.is_in_group("raspberry_seed"):
		if raspberry < raspberry_needed:
			raspberry += 1
			added = true
			print("Raspberry added:", raspberry)

	else:
		print("Not a build material")
		return


	if added:
		
		destroy_object.rpc(body.get_path())

		update_progress.rpc(logs, rocks)


	if logs >= logs_needed and rocks >= rocks_needed and screws >= screws_needed and raspberry >= raspberry_needed:

		build_structure()


# -------------------------
# SYNC PROGRESS
# -------------------------

@rpc("any_peer","call_local")
func update_progress(l:int, r:int):

	logs = l
	rocks = r

	update_label()


func update_label():

	if label:
		var lines = [buildable_name]
		if logs_name == true:
			lines.append("Logs %d/%d" % [logs, logs_needed])
		if rocks_name == true:
			lines.append("Rocks %d/%d" % [rocks, rocks_needed])
		if screws_name == true:
			lines.append("Screws %d/%d" % [screws, screws_needed])
		if raspberry_name == true:
			lines.append("Raspberry Seed %d/%d" % [raspberry, raspberry_needed])
		label.text = "\n".join(lines)

# -------------------------
# BUILD HOUSE
# -------------------------

func build_structure():

	if not multiplayer.is_server():
		return

	var pos = global_position
	var rot = global_rotation

	spawn_finished_house(pos, rot)
	spawn_finished_house.rpc(pos, rot)

	remove_blueprint()
	remove_blueprint.rpc()


# -------------------------
# SPAWN HOUSE
# -------------------------

@rpc("any_peer","call_local")
func spawn_finished_house(pos:Vector3, rot:Vector3):

	var level = get_tree().current_scene.find_child("Level", true, false)

	if not level:
		level = get_tree().current_scene

	var house = finished_house.instantiate()

	level.add_child(house)

	house.global_position = pos
	house.global_rotation = rot


# -------------------------
# REMOVE BLUEPRINT
# -------------------------

@rpc("any_peer","call_local","reliable")
func remove_blueprint():

	queue_free()
