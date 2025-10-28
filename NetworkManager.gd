# File: NetworkManager.gd (Autoload Singleton)
extends Node

# --- Signals ---
signal connection_succeeded(is_server: bool)
signal connection_failed(reason: String)
signal server_closed
signal peer_connected_to_server(peer_id: int, player_name: String) # Server emits this
signal peer_disconnected_from_server(peer_id: int) # Server emits this
signal player_list_updated(players: Dictionary) # {peer_id: {"name": "name", "is_ready": false}}
signal player_readiness_updated(peer_id: int, is_ready: bool)
signal all_players_ready_status_changed(all_ready: bool) # Emitted by server when all/not all are ready
signal game_starting_countdown(time_left: int)
signal start_game_now # Server tells clients to switch to game scene

# --- Properties ---
var player_name: String = "Player" # Default name
const DEFAULT_PORT: int = 7777 
var current_port: int = DEFAULT_PORT
var max_players: int = 2
var _current_game_countdown_value: int = 0
enum ConnectionStatus {
	DISCONNECTED,
	CONNECTING,
	HOSTING_SERVER,
	CONNECTED_AS_CLIENT,
	CONNECTION_FAILED
}
var connection_status: ConnectionStatus = ConnectionStatus.DISCONNECTED

# Stores info about connected players {peer_id: {"name": "PlayerName", "is_ready": false}}
# For the server, peer_id 1 is itself.
var players: Dictionary = {} 

var game_multiplayer_api: MultiplayerAPI

func _ready():
	# We'll use a custom MultiplayerAPI instance to avoid conflicts if the default
	# scene tree multiplayer is used elsewhere or for easier management.

	multiplayer.peer_connected.connect(_on_mp_api_peer_connected)
	multiplayer.peer_disconnected.connect(_on_mp_api_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_mp_api_server_disconnected)
	multiplayer.connected_to_server.connect(_on_mp_api_connected_to_server)
	multiplayer.connection_failed.connect(_on_mp_api_connection_failed)
	
	if multiplayer.multiplayer_peer != null:
		print("NetworkManager: Clearing existing tree multiplayer_peer in _ready().")
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	print("NetworkManager initialized.")

# --- Player Info ---
func set_player_name(p_name: String):
	if not p_name.strip_edges().is_empty():
		player_name = p_name.strip_edges()
		print("NetworkManager: Player name set to: ", player_name)
	else:
		player_name = "Player" + str(randi_range(100,999))
		print("NetworkManager: Empty name given, set to default: ", player_name)


func get_player_name() -> String:
	return player_name

# --- Hosting ---
func host_game(port: int = DEFAULT_PORT) -> bool:
	print("NetworkManager: Attempting to host game on port ", port)
	current_port = port
	
	# Ensure any previous peer is closed and cleared
	if is_instance_valid(multiplayer.multiplayer_peer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null # This sets it for the 'multiplayer' object this script uses

	players.clear()

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(current_port, max_players)
	if error != OK:
		printerr("NetworkManager: Failed to create server! Error code: ", error)
		connection_status = ConnectionStatus.CONNECTION_FAILED
		emit_signal("connection_failed", "Server creation failed.")
		return false

	# Assign the new peer to the scene tree's default multiplayer API.
	# This makes it active for RPCs on nodes in the tree and for MultiplayerSynchronizers/Spawners.
	multiplayer.multiplayer_peer = peer
	# The 'multiplayer' variable in this script will now also reflect this peer.
	
	connection_status = ConnectionStatus.HOSTING_SERVER
	print("NetworkManager: Server started. Local Peer ID: ", multiplayer.get_unique_id()) # Should be 1
	
	var host_id = multiplayer.get_unique_id() 
	players[host_id] = {"name": player_name, "is_ready": false}
	
	emit_signal("connection_succeeded", true) 
	emit_signal("player_list_updated", players)
	return true

# --- Joining ---
func join_game(ip_address: String, port: int = DEFAULT_PORT) -> bool:
	print("NetworkManager: Attempting to join game at ", ip_address, ":", port)

	if is_instance_valid(multiplayer.multiplayer_peer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

	players.clear()
	connection_status = ConnectionStatus.CONNECTING

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip_address, port)
	if error != OK:
		printerr("NetworkManager: Failed to create client! Error code: ", error)
		connection_status = ConnectionStatus.CONNECTION_FAILED
		emit_signal("connection_failed", "Client creation failed.")
		return false
	
	multiplayer.multiplayer_peer = peer
	# Again, 'multiplayer' in this script will reflect this.
	
	# Success/failure handled by connected_to_server / connection_failed signals
	return true

# --- Disconnecting ---
func disconnect_from_game():
	print("NetworkManager: Disconnecting...")
	if is_instance_valid(multiplayer.multiplayer_peer): 
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	
	players.clear()
	connection_status = ConnectionStatus.DISCONNECTED
	emit_signal("server_closed") 
	emit_signal("player_list_updated", players) 
	emit_signal("all_players_ready_status_changed", false)


# --- MultiplayerAPI Signal Handlers ---
func _on_mp_api_peer_connected(id: int):
	print("NetworkManager: Peer connected: ", id)
	if multiplayer.is_server():
		players[id] = {"name": "Player_" + str(id), "is_ready": false} # Add with placeholder
		emit_signal("peer_connected_to_server", id, players[id].name)
		
		# Broadcast to remote clients
		rpc("client_receive_initial_lobby_state", players) 
		
		# Also update host's own local client view
		print("	 NM Server (peer_connected): Forcing local client update with initial lobby state.")
		client_receive_initial_lobby_state(players) 

		_check_and_emit_all_players_ready()


func _on_mp_api_peer_disconnected(id: int):
	print("NetworkManager: Peer disconnected: ", id)
	if multiplayer.is_server():
		if players.has(id):
			var disconnected_player_name = players[id].name
			players.erase(id)
			emit_signal("peer_disconnected_from_server", id)
			rpc("client_receive_initial_lobby_state", players) # Update all with new list
			print("NetworkManager: Player '", disconnected_player_name, "' (ID:", id, ") disconnected.")
			_check_and_emit_all_players_ready()


func _on_mp_api_server_disconnected():
	print("NetworkManager: Disconnected from server (I was a client).")
	disconnect_from_game() # Clean up
	# UI should react to server_closed or a more specific client_disconnected_from_server signal

func _on_mp_api_connected_to_server():
	print("NetworkManager: Successfully connected to server! My ID: ", multiplayer.get_unique_id())
	connection_status = ConnectionStatus.CONNECTED_AS_CLIENT
	# Client now needs to send its name to the server.
	rpc_id(1, "server_receive_player_info", player_name) # RPC to server (ID 1)
	emit_signal("connection_succeeded", false) # false for is_server

func _on_mp_api_connection_failed():
	printerr("NetworkManager: Connection failed!")
	multiplayer.multiplayer_peer = null
	get_tree().multiplayer_peer = null
	connection_status = ConnectionStatus.CONNECTION_FAILED
	emit_signal("connection_failed", "Could not connect to server.")

# --- RPCs ---
@rpc("any_peer", "call_local", "reliable") 
func server_receive_player_info(p_name: String):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	# No need to check if sender_id is 0 here, as this RPC is only called by actual clients.
	
	print("NetworkManager (Server): Received player info from ID ", sender_id, ": ", p_name)
	if players.has(sender_id):
		players[sender_id].name = p_name
	else: 
		players[sender_id] = {"name": p_name, "is_ready": false}
	
	# Broadcast updated player list to everyone (remote clients)
	rpc("client_receive_initial_lobby_state", players)
	
	# Also update host's own local client view with the latest list
	print("	 NM Server (receive_player_info): Forcing local client update with initial lobby state.")
	client_receive_initial_lobby_state(players)

@rpc("reliable") # Called by server on all clients
func client_receive_initial_lobby_state(initial_players_state: Dictionary):
	print("NetworkManager (Client ", multiplayer.get_unique_id(), "): Received initial lobby state: ", initial_players_state)
	players = initial_players_state.duplicate() # Make a copy
	emit_signal("player_list_updated", players)
	# Also update local ready status if present
	var my_id = multiplayer.get_unique_id()
	if players.has(my_id):
		emit_signal("player_readiness_updated", my_id, players[my_id].is_ready)


@rpc("any_peer", "call_local", "reliable") 
func server_set_player_ready(is_ready: bool):
	if not multiplayer.is_server(): return
	
	var rpc_sender_id = multiplayer.get_remote_sender_id() 
	if rpc_sender_id == 0: # This means the server (host) called this on itself via local_player_is_ready toggle
		rpc_sender_id = multiplayer.get_unique_id() 
	
	var peer_id_that_changed_status = rpc_sender_id

	print("NM Server: server_set_player_ready for Peer ID ", peer_id_that_changed_status, " to is_ready = ", is_ready)

	if players.has(peer_id_that_changed_status):
		players[peer_id_that_changed_status].is_ready = is_ready
		print("	 NM Server: Player ID ", peer_id_that_changed_status, " readiness in 'players' dict updated.")
		
		# Option 1: Broadcast to all remote peers
		for peer_id_to_notify in multiplayer.get_peers(): # get_peers() returns IDs of OTHERS
			if peer_id_to_notify != multiplayer.get_unique_id(): # Don't RPC self if already handling
				rpc_id(peer_id_to_notify, "client_update_player_readiness", peer_id_that_changed_status, is_ready)
		
		# Option 2: Always run it locally on the server (host) as well, as it's also a client
		print("	 NM Server: Processing local client update for readiness change of peer ", peer_id_that_changed_status)
		client_update_player_readiness(peer_id_that_changed_status, is_ready) # Server's own client instance processes

		_check_and_emit_all_players_ready() 
	else:
		printerr("NM Server: Received ready status from unknown Peer ID: ", peer_id_that_changed_status)

@rpc("reliable") 
func client_update_player_readiness(peer_id: int, is_ready: bool):
	print("!!! NetworkManager (Instance ID:", multiplayer.get_unique_id(), "): client_update_player_readiness received. For Peer:", peer_id, " IsReady:", is_ready) 
	print("NetworkManager (Client ", multiplayer.get_unique_id(), "): client_update_player_readiness called for peer ", peer_id, " is_ready: ", is_ready) # DEBUG
	if players.has(peer_id): # Check if players dict on client has this peer (it might not yet if this is the first update)
		players[peer_id].is_ready = is_ready
	else: # If client doesn't know this peer yet, it will get full list from player_list_updated
		print("	 NetworkManager (Client ", multiplayer.get_unique_id(), "): Peer ", peer_id, " not in local players dict yet for readiness update.")
	
	print("	 NetworkManager (Client ", multiplayer.get_unique_id(), "): Emitting player_readiness_updated signal for peer ", peer_id) # DEBUG
	emit_signal("player_readiness_updated", peer_id, is_ready)


func _check_and_emit_all_players_ready():
	if not multiplayer.is_server(): return
	if players.size() < max_players : # Need at least max_players (e.g. 2)
		emit_signal("all_players_ready_status_changed", false)
		return
		
	var all_are_ready = true
	for peer_id in players:
		if not players[peer_id].is_ready:
			all_are_ready = false
			break
	emit_signal("all_players_ready_status_changed", all_are_ready)
	if all_are_ready:
		print("NetworkManager (Server): All players are ready! Starting countdown.")
		_start_game_countdown_on_server()


var _countdown_timer: Timer = null
func _start_game_countdown_on_server(duration: int = 3):
	if not multiplayer.is_server(): return
	
	if is_instance_valid(_countdown_timer) and not _countdown_timer.is_stopped():
		_countdown_timer.stop() 
	
	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = 1.0
	_countdown_timer.one_shot = false 
	add_child(_countdown_timer) 
	
	_current_game_countdown_value = duration
	
	# RPC to remote clients for initial display
	rpc("client_update_countdown_display", _current_game_countdown_value) 
	# Explicitly call for the host's local client instance
	if multiplayer.get_unique_id() == 1: # If I am the server/host
		print("  NM Server (countdown_start): Forcing local client update for countdown: ", _current_game_countdown_value)
		client_update_countdown_display(_current_game_countdown_value) # <<< ADD THIS

	_countdown_timer.timeout.connect(func():
		_current_game_countdown_value -= 1
		# RPC to remote clients for subsequent updates
		rpc("client_update_countdown_display", _current_game_countdown_value)
		# Explicitly call for the host's local client instance
		if multiplayer.get_unique_id() == 1:
			# print("  NM Server (countdown_tick): Forcing local client update for countdown: ", _current_game_countdown_value) # Can be noisy
			client_update_countdown_display(_current_game_countdown_value) # <<< ADD THIS

		if _current_game_countdown_value <= 0: # Check after decrementing and RPCing the current value
			_countdown_timer.stop()
			_countdown_timer.queue_free()
			_countdown_timer = null
			# The client_update_countdown_display(0) was already sent.
			
			# Tell clients to load game scene
			rpc("client_start_game_now_rpc") 
			# Server also loads game scene (which will emit start_game_now for its lobby)
			_load_game_scene_for_server() 
	)
	_countdown_timer.start()

@rpc("reliable")
func client_update_countdown_display(time_left: int):
	print("!!! NetworkManager (Instance ID:", multiplayer.get_unique_id(), "): client_update_countdown_display received. Time Left:", time_left)
	emit_signal("game_starting_countdown", time_left)

@rpc("reliable")
func client_start_game_now_rpc():
	print("NetworkManager (Client ", multiplayer.get_unique_id(), "): Received start_game_now RPC.")
	emit_signal("start_game_now")
	# UI (Lobby scenes) will connect to this signal to change to GameScene.tscn

func _load_game_scene_for_server():
	# For the server, "loading the game scene" means preparing BattleManager
	# and other logic, but not necessarily changing its own scene if it's headless
	# or if the HostLobby also contains the game.
	# For now, we'll assume the host also transitions.
	print("NetworkManager (Server): Loading game scene.")
	emit_signal("start_game_now")


# Helper (Optional)
func get_local_ip_addresses() -> Array[String]:
	var all_ips = IP.get_local_addresses()
	var lan_ipv4_candidates: Array[String] = []
	var other_ips: Array[String] = [] # For less common but potentially valid IPs

	print("NetworkManager: All detected local IPs: ", all_ips)

	for ip_string in all_ips:
		if ip_string.begins_with("192.168.") or \
		   ip_string.begins_with("10.") or \
		   (ip_string.begins_with("172.") and ip_string.split(".")[1].is_valid_int() and int(ip_string.split(".")[1]) >= 16 and int(ip_string.split(".")[1]) <= 31):
			# This is a common private IPv4 range, good candidate for LAN
			lan_ipv4_candidates.append(ip_string)
		elif not (ip_string.contains(":") or ip_string.begins_with("127.") or ip_string.begins_with("169.254.")):
			# Not IPv6, not loopback, not link-local IPv4 -- could be another valid IPv4
			other_ips.append(ip_string)
		# We are generally ignoring IPv6 link-local (fe80::) and IPv4 link-local (169.254) for user display

	if not lan_ipv4_candidates.is_empty():
		print("NetworkManager: Found LAN IPv4 candidates: ", lan_ipv4_candidates)
		return lan_ipv4_candidates # Return all likely LAN IPs
	elif not other_ips.is_empty():
		print("NetworkManager: No standard LAN IPv4 found, returning other IPs: ", other_ips)
		return other_ips # Fallback to other non-loopback/non-link-local IPv4s
	elif not all_ips.is_empty():
		print("NetworkManager: No ideal LAN IP found, returning first detected IP: ", [all_ips[0]])
		return [all_ips[0]] # Last resort, show the first one (might be loopback)
	else:
		print("NetworkManager: No local IP addresses found.")
		return []
