extends Control

@export var UI = Control
@export var Menu = Control
@export var MP = Control

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_multiplayer_pressed() -> void:
	UI.visible = true
	Menu.visible = false


func _on_close_pressed() -> void:
	UI.visible = false
	Menu.visible = true


func _on_singleplayer_pressed() -> void:
	Menu.visible = false
