extends Node

# Core references
var card_manager: Node2D
@onready var game_board_reference: Node2D = $"../../GameBoard"
var emperor_position: Node2D = null
@onready var player_hand_reference: Array[Node2D] = [%PlayerHand,%EnemyHand]
@onready var battle_manager: Node = %BattleManager
# Initialize with references to key systems
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
		card.position = target_slot.position
		card.card_is_in_slot = target_slot

		# Mark the new slot as occupied
		target_slot.is_occupied = true
		target_slot.card_in_slot = card
		
		# Special case for emperor cards - update emperor position tracker
		var card_data = card.get_current_card_data_dict()
		if card_data["type"] == 0:	# Emperor type
			card_manager.emperor_position[battle_manager.current_player_id-1] = target_slot
			emperor_position = target_slot
			print("Emperor moved to: ", target_slot.name) 

		# Clear highlights after movement
		card_manager.reset_all_slot_overlays()
		
		# Update movement maps for affected units
		print("Updating movement maps for card: ", card.name)
		card_manager.board_state.update_affected_movement_maps(card)

func swap_card_positions(card1: Node2D, card2: Node2D) -> void:
	# Get the current slot positions for both cards
	var slot1 = card1.card_is_in_slot
	var slot2 = card2.card_is_in_slot
	
	# Safety check: ensure both cards are actually in slots
	if slot1 == null or slot2 == null:
		return
		
	# Check if the second card can move - both cards need to be able to move for a swap
	if not card2.can_perform_action(card2.ActionType.MOVE):
		card_manager.reset_all_slot_overlays()
		return
	
	# Get the card data for both cards
	var card1_data = card1.get_current_card_data_dict()
	var card2_data = card2.get_current_card_data_dict()
	
	# Check if the cards are adjacent (orthogonally, not diagonally)
	var adjacent = card_manager.placement.is_adjacent(slot1, slot2)
	
	if adjacent:
		# Update emperor position if either card is an emperor
		if card1_data["type"] == 0:	   # Card1 is emperor
			card_manager.emperor_position[battle_manager.current_player_id-1] = slot2  # Update emperor position to the new slot
			emperor_position = slot2
		elif card2_data["type"] == 0:  # Card2 is emperor
			card_manager.emperor_position[battle_manager.current_player_id-1] = slot1  # Update emperor position to the new slot
			emperor_position = slot1

		# Don't move "Ploy" type cards (type 2) as they have special placement rules
		if card1_data["type"] == 2 or card2_data["type"] == 2:
			return
		
		# Perform direct swap for adjacent cards
		perform_direct_swap(card1, card2, slot1, slot2)
	else:
		# Not adjacent - we do not allow diagonal or distant swaps
		# Just reset the overlays and return without doing anything
		card_manager.reset_all_slot_overlays()
		return
	
	# Reset all slot overlays after the swap is complete
	card_manager.reset_all_slot_overlays()
	
	# Update movement maps for both cards after they've moved
	card_manager.board_state.update_affected_movement_maps(card1)
	card_manager.board_state.update_affected_movement_maps(card2)

# Helper function to perform a direct swap between adjacent cards
func perform_direct_swap(card1: Node2D, card2: Node2D, slot1: Node2D, slot2: Node2D) -> void:
	# Clear current slots first to avoid reference issues
	slot1.is_occupied = false
	slot1.card_in_slot = null
	slot2.is_occupied = false
	slot2.card_in_slot = null

	# Move card1 to slot2
	card1.position = slot2.position
	card1.card_is_in_slot = slot2
	slot2.is_occupied = true
	slot2.card_in_slot = card1

	# Move card2 to slot1
	card2.position = slot1.position
	card2.card_is_in_slot = slot1
	slot1.is_occupied = true
	slot1.card_in_slot = card2

	# Mark both cards as having used their move action
	card1.use_action(card1.ActionType.MOVE)
	card2.use_action(card2.ActionType.MOVE)
	
	# Reset both cards to idle state after movement
	card1.state_machine.transition_to(card1.state_machine.State.ON_BOARD_IDLE)
	card2.state_machine.transition_to(card2.state_machine.State.ON_BOARD_IDLE)

func place_card_in_slot(card: Node2D, slot: Node2D) -> void:
	# Remove card from the player's hand
	player_hand_reference[battle_manager.current_player_id-1].remove_card_from_hand(card)
	
	# Set the card's position to match the slot
	card.position = slot.position
	card.card_is_in_slot = slot
	# Change card state to indicate it's now on the board
	card.state_machine.transition_to(card.state_machine.State.ON_BOARD_ENTER,GameConstants.TriggerSource.PLAYER_CHOICE)
	
	# Store original Y position for animations like highlighting
	card.set_meta("original_y", slot.position.y)
	
	# Update slot state to show it's now occupied
	slot.is_occupied = true
	slot.card_in_slot = card
	card._update_visual_state() 
	print("CMSys: Called _update_visual_state for ", card.name, " after placing in slot. is_face_down: ", card.is_face_down)
	card_manager.board_state.update_movement_maps_for_obstacle_change(slot)

func reset_all_card_actions() -> void:
	# Loop through all cards in the game
	for card in get_tree().get_nodes_in_group("Cards"):
		# Only reset player cards that are on the board
		# Enemy cards are handled by the AI system separately
		if card.is_player_card and card.card_is_in_slot != null:
			card.reset_action()
	
	# Clear and recalculate all movement maps to account for any board changes
	card_manager.board_state.clear_all_movement_maps()
	card_manager.board_state.precompute_all_movement_maps()
