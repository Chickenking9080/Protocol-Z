extends DirectionalLight3D

func _ready():
	add_to_group("Sun")
	get_tree().call_group("SunManager", "register_sun", self)
