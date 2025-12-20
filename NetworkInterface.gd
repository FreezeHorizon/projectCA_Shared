extends Node

# Reference to BattleManager (Logic on Server, Event Handler on Client)
signal mulligan_options_received(card_names: Array)
signal game_started
signal card_drawn(card_key, owner_id)
var battle_manager: Node

# --- SERVER SIDE: CONNECT SIGNALS ---
func setup_server_connections(bm_node: Node):
	battle_manager = bm_node
	if not is_instance_valid(battle_manager):
		printerr("NetworkInterface: Could not find BattleManager!")
	# 1. Connect Game State Signals
	if battle_manager.has_signal("game_state_updated"):
		if not battle_manager.game_state_updated.is_connected(_on_server_game_state_updated):
			battle_manager.game_state_updated.connect(_on_server_game_state_updated)
	
	if battle_manager.has_signal("card_added_to_hand"):
		if not battle_manager.card_added_to_hand.is_connected(_on_server_card_added):
			battle_manager.card_added_to_hand.connect(_on_server_card_added)

	# 2. Connect Action Signals
	if battle_manager.has_signal("unit_moved"):
		if not battle_manager.unit_moved.is_connected(_on_server_unit_moved):
			battle_manager.unit_moved.connect(_on_server_unit_moved)
		
	if battle_manager.has_signal("unit_attack_initiated"):
		if not battle_manager.unit_attack_initiated.is_connected(_on_server_unit_attack):
			battle_manager.unit_attack_initiated.connect(_on_server_unit_attack)
		
	if battle_manager.has_signal("unit_retaliation_initiated"):
		if not battle_manager.unit_retaliation_initiated.is_connected(_on_server_unit_retaliate):
			battle_manager.unit_retaliation_initiated.connect(_on_server_unit_retaliate)
		
	if battle_manager.has_signal("unit_flipped"):
		if not battle_manager.unit_flipped.is_connected(_on_server_unit_flipped):
			battle_manager.unit_flipped.connect(_on_server_unit_flipped)
	



# --- SERVER EVENT HANDLERS (Signal -> RPC) ---

func _on_server_game_state_updated(p_id, cur_ap, max_ap, round_num):
	# Broadcast to ALL clients
	client_update_game_state.rpc(p_id, cur_ap, max_ap, round_num)

func _on_server_card_added(card_node: BaseCard, owner_id: int):
	# Tell clients a card was added. Send DB Key so client knows what to spawn.
	client_receive_card_draw.rpc(card_node.db_key, owner_id)

func _on_server_unit_moved(card: BaseCard):
	# We send the Card's ID and the Slot's Name
	var slot_name = card.card_is_in_slot.data.slot_name
	client_handle_move.rpc(card.get_instance_id(), slot_name)

func _on_server_unit_attack(attacker: BaseCard, defender: BaseCard):
	client_handle_attack.rpc(attacker.get_instance_id(), defender.get_instance_id())

func _on_server_unit_retaliate(retaliator: BaseCard, original_attacker: BaseCard):
	client_handle_retaliation.rpc(retaliator.get_instance_id(), original_attacker.get_instance_id())

func _on_server_unit_flipped(card: BaseCard):
	client_handle_flip.rpc(card.get_instance_id(), card.is_face_down)


# --- CLIENT SIDE: RECEIVE RPCs (RPC -> Visuals) ---

@rpc("authority", "call_remote", "reliable")
@warning_ignore("unused_parameter")
func client_update_game_state(p_id, cur_ap, max_ap, round_num):
	if OS.has_feature("server"): return
	# Update UI labels
	# battle_manager.update_ui(p_id, cur_ap, max_ap, round_num)
	print("Client: Game State Updated. Round: ", round_num)

@rpc("authority", "call_remote", "reliable")
func client_receive_card_draw(card_key: String, owner_id: int):
	if OS.has_feature("server"): return
	print("Client: Player ", owner_id, " drew ", card_key)
	emit_signal("card_drawn", card_key, owner_id)

@rpc("authority", "call_remote", "reliable")
func client_handle_move(card_id: int, slot_name: StringName):
	if OS.has_feature("server"): return
	# Find the visual card and slot, then tween
	# battle_manager.visual_move_card(card_id, slot_name)
	print("Client: Moving card ", card_id, " to ", slot_name)

@rpc("authority", "call_remote", "reliable")
@warning_ignore("unused_parameter")
func client_handle_attack(attacker_id: int, defender_id: int):
	if OS.has_feature("server"): return
	print("Client: Attack animation!")

@rpc("authority", "call_remote", "reliable")
@warning_ignore("unused_parameter")
func client_handle_retaliation(retaliator_id: int, attacker_id: int):
	if OS.has_feature("server"): return
	print("Client: Retaliation animation!")

@rpc("authority", "call_remote", "reliable")
@warning_ignore("unused_parameter")
func client_handle_flip(card_id: int, is_face_down: bool):
	if OS.has_feature("server"): return
	print("Client: Flip animation!")

@rpc("authority", "call_local", "reliable")
func client_receive_mulligan_options(card_names: Array):
	if OS.has_feature("server"): return # Server ignores this

	print("Client: Received mulligan options: ", card_names)
	emit_signal("mulligan_options_received", card_names)

func notify_client_mulligan_start(player_num: int, cards: Array):
	# Convert Game Player Number (1, 2) to Network Peer ID (1, 348215, etc.)
	var target_peer_id = ConnectionManager.get_peer_id_for_player(player_num)
	
	if target_peer_id == -1:
		printerr("NetworkInterface: Could not find peer ID for Player ", player_num)
		return

	var card_data_array = []
	for card in cards:
		card_data_array.append(card.db_key)
	
	# Send to the correct network ID
	client_receive_mulligan_options.rpc_id(target_peer_id, card_data_array)
	
@warning_ignore("unused_parameter")
func request_mulligan_confirm(kept_cards: Array, returned_keys: Array):
	# We probably only need to send the returned keys to the server
	server_process_mulligan.rpc_id(1, returned_keys)

@rpc("any_peer", "call_remote", "reliable")
func server_process_mulligan(returned_keys: Array):
	if not multiplayer.is_server(): return
	
	var sender_id = multiplayer.get_remote_sender_id()
	
	# CONVERT Peer ID -> Player Number
	var player_num = ConnectionManager.get_player_num_for_peer_id(sender_id)
	
	if player_num == -1:
		printerr("NetworkInterface: Unknown peer ID ", sender_id, " sent mulligan choice.")
		return

	print("Server: Received mulligan choice from Peer ", sender_id, " (Player ", player_num, ")")
	
	# Pass the Player Number (1 or 2) to BattleManager
	battle_manager.execute_mulligan_resolution(player_num, returned_keys)


func broadcast_game_start():
	client_game_started.rpc()

@rpc("authority", "call_local", "reliable")
func client_game_started():
	if OS.has_feature("server"): return
	emit_signal("game_started")
