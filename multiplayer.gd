extends Node

const PORT = 4433
const BROADCAST_PORT = 4434
const BROADCAST_INTERVAL = 2.0
const PING_INTERVAL = 2.0
const SERVER_TIMEOUT = 6.0
const RECONNECT_ATTEMPTS = 3
const RECONNECT_DELAY = 2.0
const USERNAME_SAVE_PATH = "user://username.txt"

var max_players := 1
var connected_players: Array = []
var player_usernames := {}
var player_pings := {}
var my_username := ""
var paused_players := {}

# ── NEW: Ready-up system ──────────────────────────────────────────────────────
var players_ready := {}  # tracks who is ready to start

var ping_timer := 0.0
var warning_tween: Tween

# reconnect stuff
var last_ip := ""
var reconnect_count := 0
var is_reconnecting := false

# tracks which peers are fully ready to receive a snapshot
var peers_ready_for_snapshot: Array = []

# lan discovery
var udp_broadcast: PacketPeerUDP
var udp_listen: PacketPeerUDP
var broadcast_timer := 0.0
var discovered_servers := {}
var lan_listen_active := false

# chat
var chat_messages: Array = []
var chat_fade_tweens := {}
var chat_open := false


# ── ready ─────────────────────────────────────────────────────────────────────

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	multiplayer.server_relay = false
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	$UI/Control/Label.text = ""

	_load_username()

	if DisplayServer.get_name() == "headless":
		_on_host_pressed.call_deferred()
	else:
		await get_tree().create_timer(randf_range(0.1, 0.5)).timeout
		_start_listening()

func _process(delta):
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_poll_broadcast(delta)
		_poll_ping(delta)
	elif udp_listen != null:
		_poll_listen(delta)


# ── username save/load ────────────────────────────────────────────────────────

func _save_username(name: String):
	var f = FileAccess.open(USERNAME_SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(name)
		f.close()

func _load_username():
	if not FileAccess.file_exists(USERNAME_SAVE_PATH):
		return
	var f = FileAccess.open(USERNAME_SAVE_PATH, FileAccess.READ)
	if f:
		var saved = f.get_as_text().strip_edges()
		f.close()
		if saved != "":
			$UI/Control/Username.text = saved


# ── username validation ───────────────────────────────────────────────────────

func get_username() -> String:
	return $UI/Control/Username.text.strip_edges()

func _validate_username() -> bool:
	if get_username() == "":
		_show_username_warning()
		return false
	return true

func _show_username_warning():
	var label = $UI/Control/Label
	label.text = "Enter a username before playing!"
	label.modulate = Color(1, 0.3, 0.3, 1)

	if warning_tween:
		warning_tween.kill()

	# little shake so they notice
	warning_tween = create_tween()
	warning_tween.tween_property(label, "position:x", label.position.x - 8, 0.05)
	warning_tween.tween_property(label, "position:x", label.position.x + 8, 0.05)
	warning_tween.tween_property(label, "position:x", label.position.x - 6, 0.05)
	warning_tween.tween_property(label, "position:x", label.position.x + 6, 0.05)
	warning_tween.tween_property(label, "position:x", label.position.x, 0.05)
	warning_tween.tween_interval(2.5)
	warning_tween.tween_property(label, "modulate:a", 0.0, 0.4)
	warning_tween.tween_callback(func(): label.text = "")


# ── lobby ui ──────────────────────────────────────────────────────────────────

func _update_lobby_ui():
	$UI/Lobby/PlayerCount.text = str(connected_players.size()) + " / " + str(max_players)

	# clear and rebuild the list fresh
	var list: VBoxContainer = $UI/Lobby/PlayerList
	for child in list.get_children():
		child.queue_free()

	for id in connected_players:
		var row := HBoxContainer.new()

		if id == 1:
			var badge := Label.new()
			badge.text = "[HOST]"
			badge.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
			row.add_child(badge)

		var name_label := Label.new()
		name_label.text = player_usernames.get(id, "...")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var ping_label := Label.new()
		if id == multiplayer.get_unique_id() and multiplayer.is_server():
			ping_label.text = "0 ms"
		else:
			ping_label.text = str(player_pings.get(id, "—")) + " ms"
		ping_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		row.add_child(ping_label)

		# ── NEW: Show ready status ────────────────────────────────────────
		var ready_label := Label.new()
		var is_ready = players_ready.get(id, false)
		ready_label.text = "✓ READY" if is_ready else "⏳ WAITING"
		ready_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2) if is_ready else Color(1.0, 0.8, 0.2))
		row.add_child(ready_label)

		list.add_child(row)

	# ── NEW: Show start button only if host and all players ready ────────────
	_update_start_button()


# ── NEW: Ready-up system ─────────────────────────────────────��────────────────

func _update_start_button():
	if not is_instance_valid($UI/Lobby/StartButton):
		return
	
	var all_ready = true
	for id in connected_players:
		if not players_ready.get(id, false):
			all_ready = false
			break
	
	var is_host = multiplayer.is_server()
	$UI/Lobby/StartButton.disabled = not all_ready or not is_host
	
	if all_ready and is_host:
		$UI/Lobby/StartButton.text = "START GAME"
		$UI/Lobby/StartButton.modulate = Color(0.2, 1.0, 0.2)
	else:
		$UI/Lobby/StartButton.text = "WAITING FOR PLAYERS..."
		$UI/Lobby/StartButton.modulate = Color(1.0, 0.8, 0.2)

func _on_start_button_pressed():
	if multiplayer.is_server():
		# Only start if everyone is ready
		var all_ready = true
		for id in connected_players:
			if not players_ready.get(id, false):
				all_ready = false
				break
		
		if all_ready:
			start_game.rpc()

func _on_ready_button_pressed():
	player_ready.rpc_id(1, multiplayer.get_unique_id())
	# Optionally disable the button after clicking
	$UI/Lobby/ReadyButton.disabled = true
	$UI/Lobby/ReadyButton.text = "✓ READY!"
# ── hosting ───────────────────────────────────────────────────────────────────

func _on_host_pressed():
	if not _validate_username():
		return

	my_username = get_username()
	_save_username(my_username)

	var count_text = $UI/Control/PlayerCount.text
	if count_text == "":
		OS.alert("Enter player count")
		return

	max_players = int(count_text)

	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT, max_players)
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		OS.alert("Failed to start server")
		return

	multiplayer.multiplayer_peer = peer

	connected_players.clear()
	connected_players.append(multiplayer.get_unique_id())
	player_usernames[multiplayer.get_unique_id()] = my_username
	player_pings[multiplayer.get_unique_id()] = 0
	players_ready[multiplayer.get_unique_id()] = false  # ── NEW ──

	_stop_listening()
	$UI/Control.hide()
	$UI/Lobby.show()
	_update_lobby_ui()

func _on_singleplayer_pressed():
	if not _validate_username():
		return

	my_username = get_username()
	_save_username(my_username)

	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT, 1)
	multiplayer.multiplayer_peer = peer

	connected_players.clear()
	connected_players.append(multiplayer.get_unique_id())
	player_usernames[multiplayer.get_unique_id()] = my_username
	player_pings[multiplayer.get_unique_id()] = 0
	players_ready[multiplayer.get_unique_id()] = true  # ── NEW: Auto-ready for singleplayer ──

	_stop_listening()
	start_game()


# ── connecting ────────────────────────────────────────────────────────────────

func _on_connect_pressed():
	if not _validate_username():
		return

	my_username = get_username()
	_save_username(my_username)

	var ip: String = $UI/Control/Remote.text
	if ip == "":
		OS.alert("Need a host IP to connect to.")
		return

	_connect_to_ip(ip)

func _connect_to_ip(ip: String):
	last_ip = ip

	var peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, PORT)
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		OS.alert("Failed to connect to " + ip)
		return

	multiplayer.multiplayer_peer = peer
	_stop_listening()
	_clear_server_buttons()
	$UI/Control.hide()
	$UI/Lobby.show()


# ── auto-reconnect ────────────────────────────────────────────────────────────

func _try_reconnect():
	if last_ip == "" or reconnect_count >= RECONNECT_ATTEMPTS:
		_show_disconnected_screen("Lost connection to server.")
		reconnect_count = 0
		is_reconnecting = false
		return

	is_reconnecting = true
	reconnect_count += 1
	_show_status("Reconnecting... (attempt %d/%d)" % [reconnect_count, RECONNECT_ATTEMPTS])

	await get_tree().create_timer(RECONNECT_DELAY).timeout

	var peer = ENetMultiplayerPeer.new()
	peer.create_client(last_ip, PORT)
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_try_reconnect()
		return

	multiplayer.multiplayer_peer = peer

func _show_disconnected_screen(msg: String):
	is_reconnecting = false
	$UI.show()
	$UI/Control.show()
	$UI/Lobby.hide()
	$UI/Control/Label.text = msg
	$UI/Control/Label.modulate = Color(1, 0.4, 0.4, 1)

func _show_status(msg: String):
	$UI/Control/Label.text = msg
	$UI/Control/Label.modulate = Color(1, 1, 1, 1)


# ── peer events ───────────────────────────────────────────────────────────────

func _on_player_connected(id):
	if multiplayer.is_server():
		connected_players.append(id)
		players_ready[id] = false  # ── NEW: Mark as not ready ──
		sync_player_data.rpc(connected_players, player_usernames, player_pings, max_players, players_ready)

		# game already running = late joiner, tell them to load the level
		# we wait for them to confirm before sending the snapshot
		if not get_tree().paused:
			load_level_for_latejoin.rpc_id(id)

		# ── CHANGED: Removed auto-start, now requires ready-up ──
		_update_start_button()

func _on_player_disconnected(id):
	connected_players.erase(id)
	player_usernames.erase(id)
	player_pings.erase(id)
	players_ready.erase(id)  # ── NEW ──
	peers_ready_for_snapshot.erase(id)

	if multiplayer.is_server():
		sync_player_data.rpc(connected_players, player_usernames, player_pings, max_players, players_ready)

	_update_lobby_ui()
	_update_start_button()  # ── NEW ──

func _on_connected_to_server():
	send_username.rpc_id(1, my_username)
	reconnect_count = 0
	is_reconnecting = false

func _on_connection_failed():
	if not multiplayer.is_server() and not is_reconnecting:
		_try_reconnect()


# ── late join ─────────────────────────────────────────────────────────────────

# server tells the late joiner to load the level
# we dont send the snapshot yet, we wait for them to say theyre ready
@rpc
func load_level_for_latejoin():
	$UI.hide()
	get_tree().paused = false
	# small wait so the level actually finishes loading before we ping back
	await get_tree().create_timer(0.1).timeout
	i_am_ready_for_snapshot.rpc_id(1)

# client pings this when theyre fully loaded and ready
@rpc("any_peer")
func i_am_ready_for_snapshot():
	var id = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server():
		return
	if id in peers_ready_for_snapshot:
		return
	peers_ready_for_snapshot.append(id)
	_send_world_snapshot(id)

# scans every node in placed_objects group and builds a snapshot automatically
# no setup needed on the object side, just make sure theyre in the group
func _send_world_snapshot(target_id: int):
	var snapshot: Array = []

	for obj in get_tree().get_nodes_in_group("placed_objects"):
		if not obj is Node3D:
			continue

		# grab the scene path so we can reinstantiate it on the other end
		var scene_path = obj.scene_file_path
		if scene_path == "":
			push_warning("placed_objects: no scene path on %s, skipping" % obj.name)
			continue

		snapshot.append({
			"scene": scene_path,
			"pos": _vec3_to_arr(obj.global_position),
			"rot": _vec3_to_arr(obj.global_rotation),
			"scale": _vec3_to_arr(obj.scale),
		})

	receive_world_snapshot.rpc_id(target_id, snapshot)

# late joiner gets this, clears their level and respawns everything
@rpc
func receive_world_snapshot(snapshot: Array):
	var level = $Level

	# clear anything already there from a previous session
	for child in level.get_children():
		if child.is_in_group("placed_objects"):
			child.queue_free()

	# wait a frame so the queue_frees actually finish
	await get_tree().process_frame

	for data in snapshot:
		var scene = load(data["scene"])
		if scene == null:
			push_warning("snapshot: couldnt load scene: " + data["scene"])
			continue

		var obj = scene.instantiate()
		level.add_child(obj)
		obj.global_position = _arr_to_vec3(data["pos"])
		obj.global_rotation = _arr_to_vec3(data["rot"])
		obj.scale = _arr_to_vec3(data["scale"])
		obj.add_to_group("placed_objects")


# ── vector helpers (cant send Vector3 over rpc directly) ─────────────────────

func _vec3_to_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _arr_to_vec3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


# ── rpcs ───���──────────────────────────────────────────────────────────────────

@rpc("any_peer")
func send_username(name: String):
	var id = multiplayer.get_remote_sender_id()
	player_usernames[id] = name
	sync_player_data.rpc(connected_players, player_usernames, player_pings, max_players, players_ready)

# ── CHANGED: Now includes players_ready ──
@rpc("call_local")
func sync_player_data(players: Array, usernames: Dictionary, pings: Dictionary, max_p: int, ready: Dictionary):
	connected_players = players
	player_usernames = usernames
	player_pings = pings
	max_players = max_p
	players_ready = ready
	_update_lobby_ui()

@rpc("call_local")
func start_game():
	$UI.hide()
	get_tree().paused = false
	_stop_broadcast()
	# Reset ready status for next game
	for id in connected_players:
		players_ready[id] = false
	if multiplayer.is_server():
		change_level.call_deferred(load("res://level.tscn"))

# ── NEW: RPC to mark player as ready ──
@rpc("any_peer", "call_local")
func player_ready(id: int):
	players_ready[id] = true
	sync_player_data.rpc(connected_players, player_usernames, player_pings, max_players, players_ready)
	_update_start_button()

# client bounces the timestamp back so server can work out round trip time
@rpc("any_peer")
func ping_request(sent_at: int):
	ping_response.rpc_id(1, sent_at)

@rpc("any_peer")
func ping_response(sent_at: int):
	if not multiplayer.is_server():
		return
	var id = multiplayer.get_remote_sender_id()
	player_pings[id] = Time.get_ticks_msec() - sent_at
	sync_player_data.rpc(connected_players, player_usernames, player_pings, max_players, players_ready)

func _poll_ping(delta: float):
	ping_timer += delta
	if ping_timer < PING_INTERVAL:
		return
	ping_timer = 0.0
	for id in connected_players:
		if id == multiplayer.get_unique_id():
			continue
		ping_request.rpc_id(id, Time.get_ticks_msec())


# ── chat ──────────────────────────────────────────────────────────────────────

func _input(event):
	if not event is InputEventKey:
		return

	# T toggles chat
	if Input.is_action_just_pressed("ui_chat"):
		if chat_open:
			_close_chat()
		else:
			_open_chat()
		return

	# enter sends if chat is open
	if Input.is_action_just_pressed("ui_accept") and chat_open:
		_try_send_chat()
		return

	# escape also closes chat
	if Input.is_action_just_pressed("ui_cancel") and chat_open:
		_close_chat()
		return

	# home reloads the level (host only, handy for testing)
	if multiplayer.is_server() and Input.is_action_just_pressed("ui_home"):
		change_level.call_deferred(load("res://level.tscn"))

func _open_chat():
	chat_open = true
	$Chat/Input.show()
	$Chat/SendButton.show()
	$Chat/Input.grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# kill all the fade tweens so messages stay visible while chatting
	for label in chat_fade_tweens:
		if is_instance_valid(label):
			chat_fade_tweens[label].kill()
			label.modulate.a = 1.0
	await get_tree().create_timer(0.1).timeout
	$Chat/Input.text = ""

func _close_chat():
	chat_open = false
	$Chat/Input.text = ""
	$Chat/Input.hide()
	$Chat/SendButton.hide()
	$Chat/Input.release_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# called by the send button in the scene
func _on_send_button_pressed():
	_try_send_chat()

func _try_send_chat():
	var msg = $Chat/Input.text.strip_edges()
	if msg != "":
		_send_chat(msg)
	_close_chat()

func _send_chat(text: String):
	var sender = player_usernames.get(multiplayer.get_unique_id(), "???")
	receive_chat.rpc(sender, text)

@rpc("any_peer", "call_local")
func receive_chat(sender: String, text: String):
	if chat_messages.size() >= 50:
		chat_messages.pop_front()
	chat_messages.append({"sender": sender, "text": text})
	_add_chat_label(sender, text)

func _add_chat_label(sender: String, text: String):
	var log_container: VBoxContainer = $Chat/Log

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = "[color=#aaaaff]%s[/color]: %s" % [sender, text]
	label.modulate.a = 1.0
	log_container.add_child(label)

	# fade out after 6 seconds unless chat is open
	var t = create_tween()
	t.tween_interval(6.0)
	t.tween_property(label, "modulate:a", 0.0, 1.5)
	t.tween_callback(label.queue_free)
	chat_fade_tweens[label] = t


# ── level stuff ───────────────────────────────────────────────────────────────

func change_level(scene: PackedScene):
	var level = $Level
	for c in level.get_children():
		level.remove_child(c)
		c.queue_free()
	level.add_child(scene.instantiate())

func update_all_name_labels():
	for player in get_tree().get_nodes_in_group("players"):
		var id = player.get_multiplayer_authority()
		if player_usernames.has(id):
			player.set_username(player_usernames[id])


# ── lan broadcast (server side) ───────────────────────────────────────────────

func _start_broadcast():
	if udp_broadcast:
		udp_broadcast.close()
	udp_broadcast = PacketPeerUDP.new()
	udp_broadcast.set_broadcast_enabled(true)
	var err = udp_broadcast.bind(0)
	if err != OK:
		push_warning("broadcast: couldnt bind socket: " + str(err))

func _stop_broadcast():
	if udp_broadcast:
		udp_broadcast.close()
		udp_broadcast = null
	broadcast_timer = 0.0

func _poll_broadcast(delta: float):
	if not udp_broadcast:
		_start_broadcast()
	broadcast_timer += delta
	if broadcast_timer < BROADCAST_INTERVAL:
		return
	broadcast_timer = 0.0
	var payload = JSON.stringify({
		"max": max_players,
		"current": connected_players.size(),
		"name": player_usernames.get(multiplayer.get_unique_id(), "Server")
	})
	udp_broadcast.set_dest_address("255.255.255.255", BROADCAST_PORT)
	udp_broadcast.put_packet(payload.to_utf8_buffer())


# ── lan listener (client side) ────────────────────────────────────────────────

func _start_listening():
	if lan_listen_active:
		return
	if udp_listen:
		udp_listen.close()
		udp_listen = null

	udp_listen = PacketPeerUDP.new()
	var err = udp_listen.bind(BROADCAST_PORT)
	if err != OK:
		push_warning("LAN listener: couldnt bind port %d (err=%d)" % [BROADCAST_PORT, err])
		udp_listen.close()
		udp_listen = null
		# retry in a bit
		await get_tree().create_timer(2.0).timeout
		if not lan_listen_active:
			_start_listening()
		return

	lan_listen_active = true

func _stop_listening():
	if udp_listen:
		udp_listen.close()
		udp_listen = null
	lan_listen_active = false
	discovered_servers.clear()
	_clear_server_buttons()

func _poll_listen(_delta: float):
	while udp_listen.get_available_packet_count() > 0:
		var packet = udp_listen.get_packet()
		var sender_ip = udp_listen.get_packet_ip()
		var data = JSON.parse_string(packet.get_string_from_utf8())
		if data == null:
			continue
		if data.get("current", 0) < data.get("max", 0):
			data["last_seen"] = Time.get_ticks_msec() / 1000.0
			discovered_servers[sender_ip] = data
		else:
			discovered_servers.erase(sender_ip)
		_refresh_server_buttons()

	# drop servers we havent heard from in a while
	var now = Time.get_ticks_msec() / 1000.0
	var expired: Array = []
	for ip in discovered_servers:
		if now - discovered_servers[ip].get("last_seen", 0.0) > SERVER_TIMEOUT:
			expired.append(ip)
	if expired.size() > 0:
		for ip in expired:
			discovered_servers.erase(ip)
		_refresh_server_buttons()

func _clear_server_buttons():
	if not is_instance_valid($UI/Control/DiscoveredServers):
		return
	for child in $UI/Control/DiscoveredServers.get_children():
		child.queue_free()

func _refresh_server_buttons():
	_clear_server_buttons()
	for ip in discovered_servers:
		var info = discovered_servers[ip]
		var btn := Button.new()
		btn.text = "%s  —  %s  (%d/%d)" % [
			info.get("name", "Server"),
			ip,
			info.get("current", 0),
			info.get("max", 0)
		]
		btn.pressed.connect(_connect_to_ip.bind(ip))
		$UI/Control/DiscoveredServers.add_child(btn)

# Track who's paused
@rpc("any_peer", "call_local")
func player_paused(id: int, is_paused: bool):
	paused_players[id] = is_paused
	print("%s is %s" % [player_usernames.get(id, "Player"), "paused" if is_paused else "playing"])

func get_paused_players() -> Array:
	var paused := []
	for id in paused_players:
		if paused_players[id]:
			paused.append(id)
	return paused
