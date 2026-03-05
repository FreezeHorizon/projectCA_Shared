extends Node

# Reference to BattleManager (Logic on Server, Event Handler on Client)
signal mulligan_options_received(card_names: Array)
signal game_started
signal card_drawn(card_key, owner_id)
var battle_manager: Node
signal game_state_updated(state: Dictionary)
signal unit_moved(card_name: String, slot_name: StringName, card_data: Dictionary)
signal unit_attack_initiated(atk_name: String, def_name: String, atk_hp: int, def_hp: int, atk_dead: bool, def_dead: bool, reveal_data: Dictionary)
signal unit_flipped(card_name: String, is_face_down: bool, card_data: Dictionary)
signal unit_placed(card_name: String, slot_name: StringName, card_data: Dictionary)
signal initial_state_received(my_cards_data: Array, enemy_hand_count: int)
signal placement_validation_result(result_code: int)
signal game_over(winner_id: int)

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
		if not battle_manager.unit_attack_initiated.is_connected(_on_server_unit_attack_initiated):
			battle_manager.unit_attack_initiated.connect(_on_server_unit_attack_initiated)
			
	if battle_manager.has_signal("unit_flipped"):
		if not battle_manager.unit_flipped.is_connected(_on_server_unit_flipped):
			battle_manager.unit_flipped.connect(_on_server_unit_flipped)
			
	if battle_manager.has_signal("unit_placed_on_board"):
		if not battle_manager.unit_placed_on_board.is_connected(_on_server_unit_placed):
			battle_manager.unit_placed_on_board.connect(_on_server_unit_placed)
	print("NetworkInterface: Signals connected safely (Checked for duplicates).")

# --- SERVER EVENT HANDLERS (Signal -> RPC) ---

func _on_server_game_state_updated(state: Dictionary):
	client_update_game_state.rpc(state)
	
	if not ConnectionManager.is_dedicated_server:
		client_update_game_state(state)

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

func _on_server_unit_attack_initiated(attacker: BaseCard, defender: BaseCard, atk_hp: int, def_hp: int, atk_dead: bool, def_dead: bool, reveal_data: Dictionary):
	client_handle_attack.rpc(
		attacker.name, 
		defender.name,
		atk_hp, def_hp, atk_dead, def_dead,
		reveal_data
	)

func _on_server_unit_flipped(card: BaseCard):
	var data_to_send = {}
	
	# If flipping UP, send the data so opponent can see the art/stats
	if not card.is_face_down:
		data_to_send = card.get_current_card_data_dict()
		data_to_send["atlasPath"] = card.atlas_path_info
		data_to_send["atlasRegion"] = card.atlas_region_info
	
	client_handle_flip.rpc(card.name, card.is_face_down, data_to_send)



# --- CLIENT SIDE: RECEIVE RPCs (RPC -> Visuals) ---

@rpc("authority", "call_local", "reliable")
func client_game_started():
	if OS.has_feature("server"): return
	emit_signal("game_started")

@rpc("authority", "call_remote", "reliable")
func client_handle_game_over(winner_id: int):
	emit_signal("game_over", winner_id)

@rpc("authority", "call_remote", "reliable")
func client_update_game_state(state: Dictionary):
	if OS.has_feature("server"): return
	emit_signal("game_state_updated", state)

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
func client_handle_attack(atk_name: String, def_name: String, atk_hp: int, def_hp: int, atk_dead: bool, def_dead: bool, reveal_data: Dictionary = {}):
	if OS.has_feature("server"): return
	print("Client: Attack RPC received.")
	emit_signal("unit_attack_initiated", atk_name, def_name, atk_hp, def_hp, atk_dead, def_dead, reveal_data)

@rpc("authority", "call_remote", "reliable")
func client_handle_flip(card_name: String, is_face_down: bool, card_data: Dictionary = {}):
	if OS.has_feature("server"): return
	print("Client: Network says flip ", card_name, " FaceDown: ", is_face_down)
	emit_signal("unit_flipped", card_name, is_face_down, card_data)

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

func request_extra_draw():
	server_process_extra_draw.rpc_id(1)


func request_placement_validate(card_db_key: String, slot_name: StringName):
	server_validate_placement.rpc_id(1, card_db_key, slot_name)

func request_play_card(card_db_key: String, slot_name: StringName, is_face_down: bool):
	# Send to Server (ID 1)
	server_process_play_card.rpc_id(1, card_db_key, slot_name, is_face_down)

func request_attack(attacker_key: String, defender_key: String):
	server_process_attack_request.rpc_id(1, attacker_key, defender_key)

@warning_ignore("unused_parameter")
func request_mulligan_confirm(kept_cards: Array, returned_keys: Array):
	# We probably only need to send the returned keys to the server
	server_process_mulligan.rpc_id(1, returned_keys)

func request_flip_card(card_name: String):
	server_process_flip_request.rpc_id(1, card_name)

func request_move_card(card_name: String, target_slot_name: StringName):
	server_process_move_request.rpc_id(1, card_name, target_slot_name)

func notify_client_mulligan_start(player_num: int, cards: Array):
	# Convert Game Player Number (1, 2) to Network Peer ID (1, 348215, etc.)
	var target_peer_id = ConnectionManager.get_peer_id_for_player(player_num)
	
	if target_peer_id == -1:
		printerr("NetworkInterface: Could not find peer ID for Player ", player_num)
		return

	var card_data_array = []
	for card in cards:
		# Send both pieces of info: the Key for the picture, and the Name for the ID
		card_data_array.append({"key": card.get_database_key(), "name": card.name})
	
	# Update your RPC to accept this array of dictionaries
	client_receive_mulligan_options.rpc_id(target_peer_id, card_data_array)

@rpc("any_peer", "call_remote", "reliable")
func server_process_attack_request(atk_key: String, def_key: String):
	if not multiplayer.is_server(): return
	
	var sender_id = multiplayer.get_remote_sender_id()
	var player_num = ConnectionManager.get_player_num_for_peer_id(sender_id)
	
	# Pass to BattleManager
	battle_manager.handle_attack_request(player_num, atk_key, def_key)

@rpc("any_peer", "call_remote", "reliable")
func server_process_move_request(card_name: String, slot_name: StringName):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	var player_num = ConnectionManager.get_player_num_for_peer_id(sender_id)
	battle_manager.handle_move_request(player_num, card_name, slot_name)

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
func server_process_flip_request(card_name: String):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	var player_num = ConnectionManager.get_player_num_for_peer_id(sender_id)
	
	battle_manager.handle_flip_request(player_num, card_name)

@rpc("any_peer", "call_remote", "reliable")
func server_process_mulligan(returned_names: Array): # Rename this for clarity
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	var player_num = ConnectionManager.get_player_num_for_peer_id(sender_id)
	
	if player_num != -1:
		# Pass the array of names to the BattleManager
		print("Server: Received mulligan choice from Peer ", sender_id, " (Player ", player_num, ")")
		battle_manager.execute_mulligan_resolution(player_num, returned_names)

@rpc("any_peer", "call_remote", "reliable")
func server_process_extra_draw():
	if not multiplayer.is_server(): return
	battle_manager.execute_extra_draw() # You already have this function

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

func broadcast_game_over(winner_id: int):
	client_handle_game_over.rpc(winner_id)
