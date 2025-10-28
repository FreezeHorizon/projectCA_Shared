class_name BoardStateManager
extends Node

var card_manager: Node2D
var game_board_reference: Node2D
var movement_map = {}

# Initialize with references to key systems
func initialize(manager: Node2D, board: Node2D) -> void:
	card_manager = manager
	game_board_reference = board

func precompute_all_movement_maps() -> void:
	# Clear any existing movement maps
	movement_map.clear()
	
	# Calculate movement for each player card on the board
	for card in get_tree().get_nodes_in_group("AllCards"):
		if card.is_player_card and card.card_is_in_slot != null:
			precompute_unit_movement(card)

func precompute_unit_movement(card: Node2D) -> void:
	print("Recomputing movement for card: ", card.name)
	# OLD WAY in your BoardStateManager:
	# var card_data = card.get_card_data() # This was from the old Card.gd, returned the raw dict
	# var move_range = card_data["moveRange"]

	# NEW WAY:
	if not card is BaseCard:
		printerr("BoardStateManager: precompute_unit_movement called with non-BaseCard node!")
		return

	var typed_card: BaseCard = card as BaseCard
	var move_range = typed_card.current_move_range # Use the current, potentially modified, move range

	var start_slot = typed_card.card_is_in_slot # Access property

	print("Start slot: ", start_slot.name)
	print("Move range: ", move_range)

	var card_type = typed_card.card_type_enum # Access property
	if card_type == GameConstants.CardType.EMPEROR: # Use GameConstants
		move_range = GameConstants.EMPEROR_MOVE_RANGE
	# Special rule: Emperor has a fixed move range regardless of card stats
		
	# Create a unique identifier for this card instance
	var card_id = card.get_instance_id()
	
	# Initialize empty movement map for this unit
	movement_map[card_id] = {}
	
	# Use breadth-first search to find all tiles reachable within move range
	var reachable_tiles = card_manager.placement.get_reachable_tiles(start_slot, move_range)
	
	# Store each reachable tile with its distance in the movement map
	for tile_data in reachable_tiles:
		var tile = tile_data["slot"]
		var distance = tile_data["distance"]
		
		# Use the slot name as a unique key
		movement_map[card_id][tile.name] = distance

func clear_all_movement_maps() -> void:
	movement_map.clear()

func update_affected_movement_maps(changed_card: BaseCard) -> void:
	# First update the moved card's own movement options
	precompute_unit_movement(changed_card)

	# Debug print to track which cards are being updated
	print("Updating movement maps after card movement")
	print("Changed card: ", changed_card.name)
	print("Changed card slot: ", changed_card.card_is_in_slot.name)

	# Get all player cards on the board
	var all_player_cards = get_tree().get_nodes_in_group("AllCards").filter(
		func(card): return card.is_player_card and card.card_is_in_slot != null
	)

	# Recompute movement for all cards to ensure comprehensive update
	for card in all_player_cards:
		if card != changed_card:
			precompute_unit_movement(card)
			print("Recomputed movement for card: ", card.name)

	# Optional: Force a full movement map recalculation
	#precompute_all_movement_maps()

# Update movement maps when an obstacle (like a unit) is added or removed
func update_movement_maps_for_obstacle_change(slot: Node2D) -> void:
	# Find all cards that might be affected by changes at this slot
	var nearby_cards = card_manager.placement.get_nearby_player_cards(slot)
	for card in nearby_cards:
		precompute_unit_movement(card)

func update_action_overlays_for_board() -> void:
	# Placeholder for future implementation
	precompute_all_movement_maps()
	pass
