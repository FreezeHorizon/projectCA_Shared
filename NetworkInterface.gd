extends Node

# Reference to BattleManager (Logic on Server, Event Handler on Client)
signal mulligan_options_received(card_names: Array)
signal game_started
signal card_drawn(card_key, owner_id)
var battle_manager: Node
signal game_state_updated(player_id: int, current_ap: int, max_ap: int, round: int)
signal unit_moved(card_name: String, slot_name: StringName, card_data: Dictionary)
signal unit_attack_initiated(attacker_name: String, defender_name: String)
signal unit_retaliation_initiated(retaliator_name: String, attacker_name: String)
signal unit_flipped(card_name: String, is_face_down: bool)
signal unit_placed(card_name: String, slot_name: StringName, card_data: Dictionary)
signal initial_state_received(my_cards_data: Array, enemy_hand_count: int)
signal placement_validation_result(result_code: int)

# --- SERVER SIDE: CONNECT SIGNALS ---
func setup_server_connections(bm_node: Node):
	battle_manager = bm_node
	
	# --- 1. Connect Game State Signals ---
	if battle_manager.has_signal("game_state_updated"):
		if not battle_manager.game_state_updated.is_connected(_on_server_game_state_updated):
			battle_manager.game_state_updated.connect(_on_server_game_state_updated)
	
	if battle_manager.has_signal("card_added_to_hand"):
		if not battle_manager.card_added_to_hand.is_connected(_on_server_card_added):
			battle_manager.card_added_to_hand.connect(_on_server_card_added)

	# --- 2. Connect Action Signals ---
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
			
	if battle_manager.has_signal("unit_placed_on_board"):
		if not battle_manager.unit_placed_on_board.is_connected(_on_server_unit_placed):
			battle_manager.unit_placed_on_board.connect(_on_server_unit_placed)
	print("NetworkInterface: Signals connected safely (Checked for duplicates).")




# --- SERVER EVENT HANDLERS (Signal -> RPC) ---

func _on_server_game_state_updated(p_id, cur_ap, max_ap, round_num):
	# Send to clients
	client_update_game_state.rpc(p_id, cur_ap, max_ap, round_num)
	
	# FORCE LOCAL UPDATE FOR HOST (If not dedicated)
	if not ConnectionManager.is_dedicated_server:
		client_update_game_state(p_id, cur_ap, max_ap, round_num)

func _on_server_unit_placed(card: BaseCard):
	var slot_name = card.card_is_in_slot.data.slot_name
	
	# Logic to prepare data for the opponent (The Reveal Logic)
	var data_to_send = {}
	if not card.is_face_down:
		data_to_send = card.get_current_card_data_dict()
		data_to_send["atlasPath"] = card.atlas_path_info
		data_to_send["atlasRegion"] = card.atlas_region_info
	else:
		data_to_send = { "type": card.card_type_enum, "is_face_down": true }

	# Call the new RPC
	client_handle_placement.rpc(card.name, slot_name, data_to_send)

func _on_server_unit_moved(card: BaseCard):
	# We don't need card_data for simple moves because the card is already on board
	var slot_name = card.card_is_in_slot.data.slot_name
	client_handle_move.rpc(card.name, slot_name)

func _on_server_card_added(card_node: BaseCard, owner_id: int):
	# We need to notify ALL clients so they can update their UI (Hand visuals/Counts)
	
	for peer_id in ConnectionManager.players:
		var p_num = ConnectionManager.get_player_num_for_peer_id(peer_id)
		
		# If this peer is the OWNER of the card
		if p_num == owner_id:
			# Send the actual Data (Secure)
			print("Server: Sending REAL draw to Owner (P", p_num, ")")
			client_receive_card_draw.rpc_id(peer_id, card_node.db_key, card_node.name, owner_id)
		else:
			# If this peer is the OPPONENT
			# Send a "Ghost" draw (No Data) so they see the animation/card back
			print("Server: Sending GHOST draw to Opponent (P", p_num, ")")
			client_receive_card_draw.rpc_id(peer_id, "HIDDEN", "Unknown", owner_id)

func _on_server_unit_attack(attacker: BaseCard, defender: BaseCard):
	client_handle_attack.rpc(attacker.name, defender.name)

func _on_server_unit_retaliate(retaliator: BaseCard, original_attacker: BaseCard):
	client_handle_retaliation.rpc(retaliator.name, original_attacker.name)

func _on_server_unit_flipped(card: BaseCard):
	client_handle_flip.rpc(card.name, card.is_face_down)



# --- CLIENT SIDE: RECEIVE RPCs (RPC -> Visuals) ---


@rpc("authority", "call_remote", "reliable")
func client_update_game_state(p_id, cur_ap, max_ap, round_num):
	if OS.has_feature("server"): return
	
	# Emit the signal so ClientEventHandler can hear it
	emit_signal("game_state_updated", p_id, cur_ap, max_ap, round_num)
	
	print("Client: Game State Updated. Round: ", round_num)

@rpc("authority", "call_remote", "reliable")
func client_handle_placement(card_name: String, slot_name: StringName, card_data: Dictionary):
	if OS.has_feature("server"): return
	print("Client: Network says PLACE card ", card_name)
	emit_signal("unit_placed", card_name, slot_name, card_data)

@rpc("authority", "call_remote", "reliable")
func client_receive_card_draw(card_key: String, card_name: String, owner_id: int):
	if OS.has_feature("server"): return
	print("Client: Player ", owner_id, " drew ", card_key, " named ", card_name)
	# Update the signal to include the name
	emit_signal("card_drawn", card_key, card_name, owner_id)

@rpc("authority", "call_remote", "reliable")
func client_handle_move(card_name: String, slot_name: StringName):
	if OS.has_feature("server"): return
	print("Client: Network says move card ", card_name, " to ", slot_name)
	# Note: We removed 'card_data' from this signal since it's just a move
	emit_signal("unit_moved", card_name, slot_name)


@rpc("authority", "call_remote", "reliable")
func client_handle_attack(attacker_name: String, defender_name: String):
	if OS.has_feature("server"): return
	print("Client: Network says attack")
	emit_signal("unit_attack_initiated", attacker_name, defender_name)

@rpc("authority", "call_remote", "reliable")
func client_handle_retaliation(retaliator_name: String, attacker_name: String):
	if OS.has_feature("server"): return
	print("Client: Network says retaliate")
	emit_signal("unit_retaliation_initiated", retaliator_name, attacker_name)

@rpc("authority", "call_remote", "reliable")
func client_handle_flip(card_name: String, is_face_down: bool):
	if OS.has_feature("server"): return
	print("Client: Network says flip")
	emit_signal("unit_flipped", card_name, is_face_down)

@rpc("authority", "call_local", "reliable")
func client_receive_mulligan_options(card_names: Array):
	if OS.has_feature("server"): return # Server ignores this

	print("Client: Received mulligan options: ", card_names)
	emit_signal("mulligan_options_received", card_names)

@rpc("authority", "call_remote", "reliable")
func client_receive_initial_hand_state(my_cards_data: Array, enemy_hand_count: int):
	if OS.has_feature("server"): return
	
	print("Client: Received initial hand state from server.")
	emit_signal("initial_state_received", my_cards_data, enemy_hand_count)

@rpc("authority", "call_remote", "reliable")
func client_receive_validation_response(result_code: int):
	emit_signal("placement_validation_result", result_code)

func request_initial_hand_state():
	# Ask server for my cards
	server_process_hand_request.rpc_id(1)

func request_end_turn():
	server_process_end_turn.rpc_id(1)

func request_placement_validate(card_db_key: String, slot_name: StringName):
	server_validate_placement.rpc_id(1, card_db_key, slot_name)

func request_play_card(card_db_key: String, slot_name: StringName, is_face_down: bool):
	# Send to Server (ID 1)
	server_process_play_card.rpc_id(1, card_db_key, slot_name, is_face_down)

@warning_ignore("unused_parameter")
func request_mulligan_confirm(kept_cards: Array, returned_keys: Array):
	# We probably only need to send the returned keys to the server
	server_process_mulligan.rpc_id(1, returned_keys)

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

@rpc("any_peer", "call_remote", "reliable")
func server_process_hand_request():
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Pass to BattleManager to handle the data retrieval
	battle_manager.handle_initial_hand_request(sender_id)

@rpc("any_peer", "call_remote", "reliable")
func server_process_play_card(card_db_key: String, slot_name: StringName, is_face_down: bool):
	if not multiplayer.is_server(): return
	
	var sender_id = multiplayer.get_remote_sender_id()
	var player_num = ConnectionManager.get_player_num_for_peer_id(sender_id)
	
	if player_num == -1:
		printerr("Server: Unknown peer ", sender_id, " tried to play a card.")
		return

	print("Server: Received Play Card Request from P", player_num, ": ", card_db_key, " -> ", slot_name)
	
	# Pass the request to BattleManager to find the real objects and execute
	battle_manager.handle_play_card_request(player_num, card_db_key, slot_name, is_face_down)

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

@rpc("any_peer", "call_remote", "reliable")
func server_process_end_turn():
	if not multiplayer.is_server(): return
	
	var sender_id = multiplayer.get_remote_sender_id()
	var player_num = ConnectionManager.get_player_num_for_peer_id(sender_id)
	
	if player_num != -1:
		battle_manager.execute_end_turn(player_num)

@rpc("any_peer", "call_remote", "reliable")
func server_validate_placement(card_key: String, slot_name: StringName):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	var player_num = ConnectionManager.get_player_num_for_peer_id(sender_id)
	
	# Pass to BattleManager
	battle_manager.handle_placement_validation_request(sender_id, player_num, card_key, slot_name)

func send_validation_response(peer_id: int, result_code: int):
	client_receive_validation_response.rpc_id(peer_id, result_code)

func broadcast_game_start():
	client_game_started.rpc()

@rpc("authority", "call_local", "reliable")
func client_game_started():
	if OS.has_feature("server"): return
	emit_signal("game_started")
