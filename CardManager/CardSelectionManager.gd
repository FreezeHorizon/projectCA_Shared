extends Node

var card_manager: Node2D
var game_board_reference: Node2D
var selected_card: BaseCard = null

func initialize(manager: Node2D, board: Node2D) -> void:
	card_manager = manager
	game_board_reference = board

func select_card_on_board(card: BaseCard) -> void:

	if selected_card == card:
		print("CardSelectionManager: Clicked same card. Deselecting.")
		deselect_all_cards()
		return
	
	deselect_all_cards() # Clean up previous
	
	if not card.is_player_card: return # Can't select enemy for action
	
	if card.current_health <= 0 and card.base_health > 0:
		print("CardSelectionManager: Ignoring click on dying unit.")
		return
	selected_card = card
	var is_my_turn: bool = false
	
	# Visual State
	print("CardSelectionManager: Selected ", card.name)
	card.state_machine.transition_to(card.state_machine.State.SELECTED)
	
	# Slot Interaction (Click-through)
	if is_instance_valid(card.card_is_in_slot):
		var collision_shape = card.card_is_in_slot.get_node_or_null("Area2D/CollisionShape2D")
		if collision_shape:
			collision_shape.scale = Vector2(1, 1) # Ensure clickable
			
	# Show Visuals
	is_my_turn = ($"../..".current_player_id == ConnectionManager.my_player_number)
	if is_my_turn:
		# Show Options ONLY if it is my turn
		_display_valid_actions(card)
	else:
		print("CardSelectionManager: Selected card, but not my turn. Hiding actions.")

func deselect_all_cards() -> void:
	if selected_card and is_instance_valid(selected_card):
		selected_card.state_machine.transition_to(selected_card.state_machine.State.ON_BOARD_IDLE)
	
	selected_card = null
	card_manager.reset_all_slot_overlays()

func get_selected_card() -> BaseCard:
	if not is_instance_valid(selected_card):
		selected_card = null # Auto-clean
		return null
	return selected_card

# --- NEW VISUAL LOGIC ---
func _display_valid_actions(card: BaseCard) -> void:
	var board_state = card_manager.board_state
	var card_key = card.name
	
	# 1. Regenerate maps if missing (Safety)
	if not board_state.movement_map.has(card_key):
		board_state.precompute_unit_options(card)
		
	var valid_moves = board_state.movement_map.get(card_key, {})
	var valid_attacks = board_state.attack_map.get(card_key, {})
	
	# 2. Display Attacks (Red)
	for slot_name in valid_attacks:
		var slot = _get_slot(slot_name)
		if slot:
			slot.update_highlight("attack", true)
			
	# 3. Display Moves (Blue)
	# Logic: If I can Attack AND Move to the same tile?
	# In your logic, Attack target must be enemy. Move target must be empty/ally.
	# So they shouldn't overlap.
	for slot_name in valid_moves:
		var slot = _get_slot(slot_name)
		if slot:
			slot.update_highlight("move", true)

func refresh_selection_overlays() -> void:
	if not is_instance_valid(selected_card):
		return
	
	print("CardSelectionManager: Refreshing overlays for ", selected_card.name)
	# 1. Clear old
	card_manager.reset_all_slot_overlays()
	
	# 2. Redraw new based on current maps
	_display_valid_actions(selected_card)

func _get_slot(slot_name: String) -> Node2D:
	# Helper assuming game_board has get_slot_by_name
	if game_board_reference.has_method("get_slot_by_name"):
		return game_board_reference.get_slot_by_name(slot_name)
	return null
