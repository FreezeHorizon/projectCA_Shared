extends Node

var card_manager: Node2D
@onready var game_board_reference: Node = $"../../GameBoard"
var emperor_position: Array[Node] = [null, null] # Explicitly typed array
var player_hand_reference: Array = [null, null]
var battle_manager: Node

func _ready() -> void:
	if not OS.has_feature("server"):
		var p1_hand = get_node_or_null("%PlayerHand")
		var p2_hand = get_node_or_null("%EnemyHand")
		player_hand_reference = [p1_hand, p2_hand]
	else:
		battle_manager = $"../../BattleManager"

func initialize(manager: Node2D, board: Node2D) -> void:
	card_manager = manager
	game_board_reference = board

func move_card_to_slot(card: Node2D, target_slot: Node2D) -> void:
	if card.card_is_in_slot != null:
		# Clear the current slot
		var current_slot = card.card_is_in_slot
		current_slot.is_occupied = false
		current_slot.card_in_slot = null

		# Update the card's position and references
		card.global_position = target_slot.global_position # Use Global!
		card.card_is_in_slot = target_slot

		# Mark the new slot as occupied
		target_slot.is_occupied = true
		target_slot.card_in_slot = card
		
		# Special case for emperor cards
		var card_data = card.get_current_card_data_dict()
		if card_data["type"] == 0: # Emperor
			var player_idx = 0 if card.is_player_card else 1
			# On Server use battle_manager.current_player_id if needed, but local index logic is safer for shared code
			card_manager.emperor_position[player_idx] = target_slot
			print("Emperor moved to: ", target_slot.name) 
		if not ConnectionManager.is_dedicated_server:
			card_manager.reset_all_slot_overlays()
			# We use GameConstants.TriggerSource.PLAYER_CHOICE (0) as the source.
		if card.has_method("use_action"):
			card.use_action(card.ActionType.MOVE, 0)
		print("Updating movement maps for card: ", card.name)
		card_manager.board_state.precompute_all_movement_maps()

func swap_card_positions(card1: Node2D, card2: Node2D) -> void:
	var slot1 = card1.card_is_in_slot
	var slot2 = card2.card_is_in_slot
	
	if slot1 == null or slot2 == null: return
		
	if not card2.can_perform_action(card2.ActionType.MOVE):
		card_manager.reset_all_slot_overlays()
		return
	
	var card1_data = card1.get_current_card_data_dict()
	var card2_data = card2.get_current_card_data_dict()
	
	if card1_data["type"] == 2 or card2_data["type"] == 2: return # No Ploy Swap
	
	var adjacent = card_manager.placement.is_adjacent(slot1, slot2)
	
	if adjacent:
		# Emperor Logic for Swaps
		if card1_data["type"] == 0:
			var idx = 0 if card1.is_player_card else 1
			card_manager.emperor_position[idx] = slot2
		if card2_data["type"] == 0:
			var idx = 0 if card2.is_player_card else 1
			card_manager.emperor_position[idx] = slot1

		perform_direct_swap(card1, card2, slot1, slot2)
	else:
		card_manager.reset_all_slot_overlays()
		return
	if not ConnectionManager.is_dedicated_server:
		card_manager.reset_all_slot_overlays()
	card_manager.board_state.precompute_all_movement_maps()

func perform_direct_swap(card1: Node2D, card2: Node2D, slot1: Node2D, slot2: Node2D) -> void:
	slot1.is_occupied = false
	slot1.card_in_slot = null
	slot2.is_occupied = false
	slot2.card_in_slot = null

	card1.global_position = slot2.global_position
	card1.card_is_in_slot = slot2
	slot2.is_occupied = true
	slot2.card_in_slot = card1

	card2.global_position = slot1.global_position
	card2.card_is_in_slot = slot1
	slot1.is_occupied = true
	slot1.card_in_slot = card2

	card1.use_action(card1.ActionType.MOVE, 0) # Assuming 0 is PLAYER_CHOICE enum value
	card2.use_action(card2.ActionType.MOVE, 0)
	card1.set_meta("original_y", card1.position.y)
	card2.set_meta("original_y", card2.position.y)
	card1.state_machine.transition_to(card1.state_machine.State.ON_BOARD_IDLE, {})
	card2.state_machine.transition_to(card2.state_machine.State.ON_BOARD_IDLE, {})
	card_manager.board_state.precompute_all_movement_maps()
	
func place_card_in_slot(card: Node2D, slot: Node2D) -> void:
	# 1. Update Hierarchy
	if card.get_parent() != card_manager:
		card.get_parent().remove_child(card)
		card_manager.add_child(card)
	
	# 2. Update Position & Transform
	card.global_position = slot.global_position
	# CRITICAL: Reset transform to ensure animations play correctly
	card.rotation = 0.0 
	card.scale = Vector2(0.5, 0.5) 
	
	# 3. Data Links & Metadata
	card.set_meta("original_y", card.position.y)
	card.card_is_in_slot = slot
	
	# --- Snare vs Unit Logic ---
	var is_snare = false
	if card.has_method("get_current_card_data_dict"):
		var d = card.get_current_card_data_dict()
		if d.get("type") == 2 and d.get("subtype") == "Snare": # 2 is PLOY
			is_snare = true

	if is_snare:
		slot.snare_in_slot = card
		print("CMSys: Placed Snare '", card.name, "' in ", slot.name)
	else:
		slot.is_occupied = true
		slot.card_in_slot = card

	# --- Emperor Logic ---
	if card.has_method("get_current_card_data_dict"):
		var data = card.get_current_card_data_dict()
		if data.get("type") == 0: 
			var index = 0 if card.is_player_card else 1
			card_manager.emperor_position[index] = slot
			print("CMSys: Updated Emperor Position for index ", index, " to ", slot.name)

	# 4. Play Animation
	if card.has_node("AnimationPlayer"):
		var anim = card.get_node("AnimationPlayer")
		anim.stop() # Stop any previous hand/hover animations
		
		if anim.has_animation("CardAnimations/place_on_board"):
			anim.play("CardAnimations/place_on_board")
		else:
			print("CMSys: 'place_on_board' animation missing on ", card.name)

	# 5. Visuals
	card._update_visual_state() 
	card_manager.board_state.precompute_all_movement_maps()

func reset_all_card_actions() -> void:
	for card in get_tree().get_nodes_in_group("Cards"):
		if card.is_player_card and card.card_is_in_slot != null:
			card.reset_action()

	card_manager.board_state.clear_all_movement_maps()
	card_manager.board_state.precompute_all_movement_maps()
