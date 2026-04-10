extends Control

# References to UI panels
@export var pause_panel: Control
@export var network_manager: Node  # Reference to your NetworkManager

# Pause state
var is_paused := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if pause_panel:
		pause_panel.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep processing even when paused
	
	# ── NEW: Find network manager if not assigned ──
	if not network_manager:
		network_manager = get_tree().root.get_node_or_null("Main/NetworkManager")
		if not network_manager:
			network_manager = get_node_or_null("/root/Main/NetworkManager")
		if not network_manager:
			push_warning("PauseMenuManager: Could not find NetworkManager!")

# Called every frame. 'delta' is the elapsed time since the first frame.
func _process(delta: float) -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	# Only allow pause when in-game (not in lobby or main menu)
	if Input.is_action_just_pressed("ui_cancel"):
		if is_game_active() and not get_tree().paused:
			_toggle_pause()
			get_tree().root.set_input_as_handled()

# ── Pause/Resume Logic ────────────────────────────────────────────────────────

func _toggle_pause():
	if is_paused:
		_resume_game()
	else:
		_pause_game()

func _pause_game():
	is_paused = true
	
	if pause_panel:
		pause_panel.visible = true
		pause_panel.modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(pause_panel, "modulate:a", 1.0, 0.3)
	
	# ── NEW: Update ping display ──
	_update_ping_display()
	
	# Capture mouse and show cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Disable player movement input
	_disable_player_input()
	
	# Notify server that this player is paused
	if network_manager and network_manager.has_method("player_paused"):
		network_manager.player_paused.rpc_id(1, multiplayer.get_unique_id(), true)

func _resume_game():
	is_paused = false
	
	if pause_panel:
		var tween = create_tween()
		tween.tween_property(pause_panel, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): pause_panel.visible = false)
	
	# Recapture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Re-enable player movement input
	_enable_player_input()
	
	# Notify server that this player resumed
	if network_manager and network_manager.has_method("player_paused"):
		network_manager.player_paused.rpc_id(1, multiplayer.get_unique_id(), false)

# ── Input Control ─────────────────────────────────────────────────────────────

func _disable_player_input():
	# Find the player node and disable input
	var player = get_tree().root.get_node_or_null("Main/Player")  # Adjust path to your player
	if player and player.has_method("set_input_disabled"):
		player.set_input_disabled(true)
	elif player:
		player.process_mode = Node.PROCESS_MODE_DISABLED

func _enable_player_input():
	# Re-enable player input
	var player = get_tree().root.get_node_or_null("Main/Player")  # Adjust path to your player
	if player and player.has_method("set_input_disabled"):
		player.set_input_disabled(false)
	elif player:
		player.process_mode = Node.PROCESS_MODE_INHERIT

# ── Ping Display ──────────────────────────────────────────────────────────────

func _update_ping_display():
	# ── FIXED: Correct path to Label2 ──
	var label = pause_panel.get_node_or_null("MainPausePanel/MarginContainer/VBoxContainer/Label2")
	if not label:
		print("PauseMenuManager: Could not find Label2")
		return
	
	if not network_manager:
		print("PauseMenuManager: network_manager not set")
		label.text = "Ping: N/A"
		return
	
	var my_id = multiplayer.get_unique_id()
	var ping = 0
	
	# Get ping from network manager
	if network_manager.player_pings.has(my_id):
		ping = network_manager.player_pings[my_id]
	else:
		print("Ping not found for player ", my_id)
		label.text = "Ping: Calculating..."
		return
	
	# Color code based on ping
	var color = Color.GREEN
	if ping > 100:
		color = Color.YELLOW
	if ping > 150:
		color = Color.RED
	
	label.text = "Ping: %d ms" % ping
	
	# ── FIXED: Use modulate instead of theme override ──
	label.modulate = color
	
	print("Updated ping display: ", ping, " ms")

# ── Button Callbacks ──────────────────────────────────────────────────────────

func _on_resume_pressed() -> void:
	_resume_game()

func _on_settings_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Open settings menu (you can expand this)
	if pause_panel and is_instance_valid(pause_panel.get_node_or_null("SettingsPanel")):
		pause_panel.get_node("SettingsPanel").show()
		pause_panel.get_node("MainPausePanel").hide()

func _on_quit_to_menu_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().quit()

func _on_back_button_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if pause_panel and is_instance_valid(pause_panel.get_node_or_null("SettingsPanel")):
		pause_panel.get_node("SettingsPanel").hide()
		pause_panel.get_node("MainPausePanel").show()

# ── Helper Functions ──────────────────────────────────────────────────────────

func is_game_active() -> bool:
	# Check if we're actually in-game (not in lobby)
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return false
	
	# Make sure game tree is not paused (lobby pauses it)
	if get_tree().paused:
		return false
	
	return true

func get_paused_players() -> Array:
	# Returns list of paused player IDs
	if network_manager and network_manager.has_method("get_paused_players"):
		return network_manager.get_paused_players()
	return []
