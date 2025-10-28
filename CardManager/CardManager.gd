class_name CardManager extends Node2D

# Import GameConstants
#const GameConstants = preload("res://CardManager/GameConstants.gd")
signal card_drag_placement_attempted(dragged_card_node: BaseCard, target_slot_node: Node2D)

# Core game state variables
var screen_size:Vector2
var card_being_dragged: BaseCard
var is_hovering_on_card:bool
var player_hand_reference:Node2D
var game_board_reference:Node2D
var emperor_position: Array[Node2D] = [null,null]

# References to subsystems
@onready var movement: Node = $CardMovementSystem
@onready var board_state: Node = $BoardStateManager
@onready var placement: Node = $PlacementValidator
@onready var selection: Node = $CardSelectionManager
@onready var mulligan_manager: Control = $"../MulliganManager"

# Initialize components
func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_hand_reference = $"../PlayerHand"
	game_board_reference = $"../GameBoard"

	# Connect input signals
	$"../InputManager".connect("left_mouse_button_released", Callable(self, "on_left_click_released"))
	$"../InputManager".connect("left_mouse_button_clicked", Callable(self, "left_mouse_button_clicked"))

	# Initialize subsystems and pass references
	initialize_subsystems()

# Initialize all subsystems with necessary references
func initialize_subsystems() -> void:
	# Provide references to key game objects to all subsystems
	movement.initialize(self, game_board_reference)
	board_state.initialize(self, game_board_reference)
	placement.initialize(self, game_board_reference)
	selection.initialize(self, game_board_reference)

	# Initialize board state
	board_state.movement_map = {}

# Update dragged card position to follow the mouse cursor



func _process(_delta: float) -> void:
	if card_being_dragged:
		var mouse_pos:Vector2 = get_global_mouse_position()
		# Ensure card stays within screen boundaries
		card_being_dragged.position = Vector2(clamp(mouse_pos.x,0,screen_size.x),
			clamp(mouse_pos.y,0,screen_size.y))

# Handle mouse release events - primarily for finishing card drags
func on_left_click_released():
	if card_being_dragged: # Check if card_being_dragged is valid
		var target_slot: Node2D = raycast_check_for_card_slot()
		var target_slot_name_str: String
		if is_instance_valid(target_slot):
			target_slot_name_str = target_slot.name
		else:
			target_slot_name_str = "None"
		print("CardManager: Drag released for ", card_being_dragged.name, ". Target slot: ", target_slot_name_str)
		
		# We still need to know which card was dragged and where it was attempted
		var card_that_was_dragged = card_being_dragged 
		card_being_dragged = null # Clear the reference for the next drag

		emit_signal("card_drag_placement_attempted", card_that_was_dragged as BaseCard, target_slot)
		
		# CardManager no longer decides if it goes back to hand or board. BattleManager does.
		# It also shouldn't directly transition card state here. BattleManager will.
		
		# We can still reset overlays as a general cleanup after a drag interaction.
		#reset_all_slot_overlays()
		card_being_dragged = null # Clear the reference

# Remove all visual overlays from board slots
func reset_all_slot_overlays() -> void:
	#print("!!!!!!!!!! CARD_MANAGER: RESET_ALL_SLOT_OVERLAYS CALLED !!!!!!!!!!") # Make it stand out
	for slot in get_tree().get_nodes_in_group("CardSlots"):
		slot.reset_overlays()

# Begin dragging a card if it's in a state that allows dragging
func start_drag(card: Node2D) -> void:
	if card.state_machine.can_drag() and not card.state_machine.get_current_state() == card.state_machine.State.MULLIGAN:
		selection.deselect_all_cards()
		print("CardManager: Starting drag for ", card.name)
		if player_hand_reference.has_method("remove_card_from_hand"): # Check method exists
			player_hand_reference.remove_card_from_hand(card)
			print("  Called remove_card_from_hand. Is ", card.name, " still in player_hand_cards? ", card in player_hand_reference.player_hand_cards)
		else:
			print("  ERROR: player_hand_reference does not have remove_card_from_hand")
		card_being_dragged = card
		# Update card state
		card.state_machine.transition_to(card.state_machine.State.DRAGGING, GameConstants.TriggerSource.PLAYER_CHOICE)
		
		# Reset all visual overlays before showing new ones
		reset_all_slot_overlays()
		
		# Show valid placement locations for this specific card
		placement.display_valid_placements(card)

	# selection.deselect_all_cards() # BattleManager handles this when drag is initiated if needed

	print("CardManager: Starting visual drag for ", card.name)
	
	# PlayerHand should have already removed it logically when BattleManager got card_drag_initiated
	# If not, this is a fallback, but ideally BattleManager ensures PlayerHand list is up-to-date.
	# if player_hand_reference.has_method("remove_card_from_hand") and card in player_hand_reference.player_hand_cards:
	#    player_hand_reference.remove_card_from_hand(card)
		
	card_being_dragged = card
	card.state_machine.transition_to(card.state_machine.State.DRAGGING,GameConstants.TriggerSource.PLAYER_CHOICE)
	
	reset_all_slot_overlays()
	var placement_validator = get_node("PlacementValidator") # Assuming it's a child
	placement_validator.display_valid_placements(card)

func _perform_raycast(collision_mask: int) -> Array: # Returns Array[Dictionary]
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var parameters: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = collision_mask
	return space_state.intersect_point(parameters)

# Gets the topmost Card node from a list of raycast results
func _get_topmost_card_from_results(raycast_results: Array) -> Card: # Returns Card or null
	var actual_cards: Array[Card] = []
	for r_data in raycast_results:
		if r_data.has("collider"):
			var obj = r_data.collider.get_parent()
			if obj is Card: # Type check for Card
				actual_cards.append(obj as Card)

	if actual_cards.is_empty():
		return null

	var highest_z_card: Card = actual_cards[0]
	for i in range(1, actual_cards.size()):
		var current_card: Card = actual_cards[i]
		if current_card.z_index > highest_z_card.z_index:
			highest_z_card = current_card
	
	return highest_z_card

# raycasting to check for a card slot at the mouse position
func raycast_check_for_card_slot() -> Node2D: # Stays Node2D as CardSlot might not have class_name
	var results: Array = _perform_raycast(GameConstants.COLLISION_MASK_CARD_SLOT) # Use your constant
	
	if results.size() > 0:
		# Assuming the first result is sufficient and its parent is the CardSlot node
		if results[0].has("collider"):
			var slot_area = results[0].collider 
			if slot_area != null and slot_area.get_parent() is Node2D: # Basic check
				return slot_area.get_parent() 
	return null

# raycasting to check for a card at the mouse position
func raycast_check_for_card() -> Card: # Returns Card or null
	var results: Array = _perform_raycast(GameConstants.COLLISION_MASK_CARD) # Use your constant
	# No need for 'if results.size() > 0:' here, _get_topmost_card_from_results handles empty actual_cards
	return _get_topmost_card_from_results(results)
