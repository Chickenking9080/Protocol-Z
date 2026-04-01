extends Control

@onready var building_menu = $Building
@onready var crafting_menu = $Crafting
@onready var inventory_menu = $InventoryMenu
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	building_menu.visible = false
	crafting_menu.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("inventory"):
		if visible == false:
			building_menu.visible = false
			inventory_menu.visible = false
			crafting_menu.visible = false
		elif crafting_menu.visible == true:
			crafting_menu.visible = false
		elif building_menu.visible == true:
			building_menu.visible = false


func _on_buildingmenu_pressed() -> void:
	building_menu.visible = true
	inventory_menu.visible = false

# Close Building Menu
func _on_close_pressed() -> void:
	building_menu.visible = false
	inventory_menu.visible = true


func _on_buildbutton_pressed() -> void:
	building_menu.visible = false
