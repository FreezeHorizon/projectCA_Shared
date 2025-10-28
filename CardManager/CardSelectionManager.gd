extends Node

var card_manager: Node2D
var game_board_reference: Node2D

# Initialize with references to key systems
func initialize(manager: Node2D, board: Node2D) -> void:
	card_manager = manager
	game_board_reference = board

# Handle when a card on the board is selected
func select_card_on_board(card: Node2D) -> void:
	print("Card selected: ", card.name)
	# Clear any existing highlights
	card_manager.reset_all_slot_overlays()
	if card.has_move_action_available:
		print("CardSelectionManager: Selecting card and showing move ranges for: ", card.name)
	# Set the collision shape of the selected card's slot to full size
	# this allows the player to toggle the selected card
	if card.has_attack_action_available:
		print("CardSelectionManager: Selecting card and showing attack ranges for: ", card.name)
	if card.card_is_in_slot:
		var collision_shape = card.card_is_in_slot.get_node("Area2D/CollisionShape2D")
		if collision_shape:
			collision_shape.scale = card.card_is_in_slot.DEFAULT_SLOT_COLLISION_SCALING
	# Show movement options for the selected card
	show_movement_range(card)
	
	# Show attack options for the selected card
	show_attack_range(card)

# Check if any card is currently in the selected state
func is_any_card_selected() -> bool:
	for card in get_tree().get_nodes_in_group("AllCards"):
		if card.state_machine.get_current_state() == card.state_machine.State.SELECTED:
			return true
	return false

# Get the currently selected card (if any)
func get_selected_card() -> Node2D:
	for card in get_tree().get_nodes_in_group("AllCards"):
		if card.state_machine.get_current_state() == card.state_machine.State.SELECTED:
			return card
	return null

# Deselect all cards on the board
func deselect_all_cards():
	var deselection_occurred = false
	for card_node_any in get_tree().get_nodes_in_group("AllCards"): # Iterate AllCards
		if not card_node_any is BaseCard: continue
		var card : BaseCard = card_node_any as BaseCard
		
		if card.state_machine.get_current_state() == card.state_machine.State.SELECTED:
			card.state_machine.transition_to(card.state_machine.State.ON_BOARD_IDLE)
			deselection_occurred = true
	
	if deselection_occurred:
		card_manager.reset_all_slot_overlays() # Reset overlays when any deselection happens
		print("CardSelectionManager: All cards deselected.")
	return deselection_occurred

# Highlight all valid movement options for a selected card
func show_movement_range(card: Node2D) -> void:
	# Skip if the card can't move right now (e.g., already moved this turn)
	if not card.can_perform_action(card.ActionType.MOVE):
		return
		
	var card_id = card.get_instance_id()
	
	# Generate movement map if it doesn't exist for this card
	if not card_manager.board_state.movement_map.has(card_id):
		card_manager.board_state.precompute_unit_movement(card)

	if not card_manager.board_state.movement_map.has(card_id):
		# Safety check - still no movement map (card might not be on a slot)
		return
		
	# Highlight all slots within movement range
	for slot in get_tree().get_nodes_in_group("CardSlots"):
		if card_manager.board_state.movement_map[card_id].has(slot.name):
			if not slot.is_occupied:
				# Empty slot - can move here
				slot.update_highlight("move")
			elif card_manager.placement.is_ally_card(card, slot.card_in_slot) and \
				slot.card_in_slot.can_perform_action(slot.card_in_slot.ActionType.MOVE) and \
				card_manager.placement.is_adjacent(card.card_is_in_slot, slot): #the '\' extrends the if statement 
				# Only highlight ally slots that are orthogonally adjacent (not diagonal)
				slot.update_highlight("move")

# Highlight all valid attack targets for a selected card
func show_attack_range(card: Node2D) -> void:
	print("CardSelectionManager: show_attack_range called for ", card.name) # Add this
	print("  Card state: is_face_down=", card.is_face_down, ", has_attack_action_available=", card.has_attack_action_available) # Add this

	if not card.can_perform_action(card.ActionType.ATTACK): # This calls the BaseCard method
		print("  show_attack_range: Bailing because card.can_perform_action(ATTACK) is false.") # Add this
		return
		
	var card_data = card.get_current_card_data_dict()
	var card_slot = card.card_is_in_slot
	var attack_range = card_data["current_attack_range"]
	print("  Attack range: ", attack_range) # Add this
	
	var found_target_to_highlight = false # Add this
	for slot in get_tree().get_nodes_in_group("CardSlots"):
		if slot.is_occupied and card_manager.placement.is_enemy_card(card, slot.card_in_slot):
			var distance = card_manager.placement.calculate_manhattan_distance(card_slot, slot)
			if distance <= attack_range:
				slot.update_highlight("attack")
				found_target_to_highlight = true # Add this
				print("    Highlighting ", slot.card_in_slot.name, " in slot ", slot.name, " for attack.") # Add this
		if not found_target_to_highlight: # Add this
			print("  show_attack_range: No valid enemy targets found in range.") # Add this
