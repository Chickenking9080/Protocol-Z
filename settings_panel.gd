extends Panel

@onready var Shadows = $MarginContainer/VBoxContainer/Shadows
@onready var Render_Scale = $MarginContainer/VBoxContainer/renderscale
var sun: DirectionalLight3D
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Shadows.toggle_mode = true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func register_sun(s):
	sun = s



func _on_renderscale_toggled(toggled_on: bool) -> void:
	get_viewport().scaling_3d_scale = 0.6


func _on_shadows_pressed() -> void:
	if sun.shadow_enabled == true:
		sun.shadow_enabled = false
		
	else:
		sun.shadow_enabled = true
