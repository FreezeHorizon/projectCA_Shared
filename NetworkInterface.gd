class_name NetworkInterface
extends Node

# Reference to BattleManager (Logic on Server, Event Handler on Client)
@onready var battle_manager = get_parent().get_node("BattleManager")

func _ready():
	# Only the Server listens to Game Loop signals to broadcast them
	if OS.has_feature("server"):
		_connect_server_signals()

# --- SERVER SIDE: CONNECT SIGNALS ---
func _connect_server_signals():
	# 1. Connect Game State Signals
	if battle_manager.has_signal("game_state_updated"):
		battle_manager.game_state_updated.connect(_on_server_game_state_updated)
	
	if battle_manager.has_signal("card_added_to_hand"):
		battle_manager.card_added_to_hand.connect(_on_server_card_added)

	# 2. Connect Action Signals
	if battle_manager.has_signal("unit_moved"):
		battle_manager.unit_moved.connect(_on_server_unit_moved)
		
	if battle_manager.has_signal("unit_attack_initiated"):
		battle_manager.unit_attack_initiated.connect(_on_server_unit_attack)
		
	if battle_manager.has_signal("unit_retaliation_initiated"):
		battle_manager.unit_retaliation_initiated.connect(_on_server_unit_retaliate)
		
	if battle_manager.has_signal("unit_flipped"):
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
func client_update_game_state(p_id, cur_ap, max_ap, round_num):
	if OS.has_feature("server"): return
	# Update UI labels
	# battle_manager.update_ui(p_id, cur_ap, max_ap, round_num)
	print("Client: Game State Updated. Round: ", round_num)

@rpc("authority", "call_remote", "reliable")
func client_receive_card_draw(card_key: String, owner_id: int):
	if OS.has_feature("server"): return
	# Determine if we should show the face (if we are the owner)
	# battle_manager.visual_draw_card(card_key, owner_id)
	print("Client: Player ", owner_id, " drew ", card_key)

@rpc("authority", "call_remote", "reliable")
func client_handle_move(card_id: int, slot_name: StringName):
	if OS.has_feature("server"): return
	# Find the visual card and slot, then tween
	# battle_manager.visual_move_card(card_id, slot_name)
	print("Client: Moving card ", card_id, " to ", slot_name)

@rpc("authority", "call_remote", "reliable")
func client_handle_attack(attacker_id: int, defender_id: int):
	if OS.has_feature("server"): return
	print("Client: Attack animation!")

@rpc("authority", "call_remote", "reliable")
func client_handle_retaliation(retaliator_id: int, attacker_id: int):
	if OS.has_feature("server"): return
	print("Client: Retaliation animation!")

@rpc("authority", "call_remote", "reliable")
func client_handle_flip(card_id: int, is_face_down: bool):
	if OS.has_feature("server"): return
	print("Client: Flip animation!")
