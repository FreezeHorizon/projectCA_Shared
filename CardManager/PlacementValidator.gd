class_name PlacementValidator
extends Node

var card_manager: Node2D
var game_board_reference: Node2D
@onready var battlemanager = %BattleManager
# Initialize with references to key systems
func initialize(manager: Node2D, board: Node2D) -> void:
	card_manager = manager
	game_board_reference = board

# Check if a card can be legally placed at a given slot according to game rules
func is_valid_card_placement(slot: Node2D, card: BaseCard) -> bool:
	var card_data = card.get_current_card_data_dict()

	# Cannot place non-emperor cards if no emperor exists yet
	if card_manager.emperor_position[%BattleManager.current_player_id-1] == null and card_data["type"] != 0 and (%BattleManager.current_player_id-1) == 0:
		return false
	
	# Emperor cards can only be placed if no emperor exists
	if card_data["type"] == 0:
		return card_manager.emperor_position[%BattleManager.current_player_id-1] == null
	
	# Rule 1: Cards can be placed within range of emperor
	if card_manager.emperor_position[%BattleManager.current_player_id-1] != null:
		var distance_to_emperor = calculate_manhattan_distance(slot, card_manager.emperor_position[%BattleManager.current_player_id-1])
		if distance_to_emperor <= GameConstants.HERO_PLACEMENT_FROM_EMPEROR:
			return true
	
	# Rule 2: Cards can be placed adjacent to allied hero cards
	for neighbor_slot in get_adjacent_slots(slot):
		if neighbor_slot.is_occupied and neighbor_slot.card_in_slot != null:
			var neighbor_card_data = neighbor_slot.card_in_slot.get_current_card_data_dict()
			if is_ally_card(neighbor_slot.card_in_slot, card) and neighbor_card_data["type"] == 1:	# Hero type
				print("Found adjacent hero at: ", neighbor_slot.name) #debugging
				return true
	
	# No valid placement conditions met
	return false

# Visually highlight valid placement locations for a card being dragged
func display_valid_placements(card: Node2D) -> void:
	var card_data = card.get_current_card_data_dict() # Get the card's data (type, stats, etc.)
	var is_emperor = card_data["type"] == 0	 # Type 0 represents emperor cards
	
	# Iterate through all board slots to check valid placements
	var card_slots = get_tree().get_nodes_in_group("CardSlots")
	
	for slot in card_slots:
		var valid_placement = false
		
		if is_emperor:
			# Emperor cards can be placed anywhere if no emperor exists yet
			valid_placement = card_manager.emperor_position[%BattleManager.current_player_id-1] == null
		else:
			# Other cards need to follow placement rules (near emperor or allies)
			valid_placement = is_valid_card_placement(slot, card)
		
		# Update the slot's visual state if it's a valid placement and not occupied
		if valid_placement and not slot.is_occupied:
			slot.update_highlight("placement", true)

# Calculate Manhattan distance between two slots (used for placement and attack range)
func calculate_manhattan_distance(slot1: Node2D, slot2: Node2D) -> int:
	var slot1_pos: Vector2 = get_slot_grid_position(slot1)
	var slot2_pos: Vector2 = get_slot_grid_position(slot2)
	
	return abs(slot1_pos.x - slot2_pos.x) + abs(slot1_pos.y - slot2_pos.y)

# Convert a slot's name (like "A1", "B2") to grid coordinates (0,0), (1,1), etc.
func get_slot_grid_position(slot: Node2D) -> Vector2:
	var name_str = String(slot.name)
	# Convert letter (A-D) to row index (0-3)
	var row = name_str.unicode_at(0) - "A".unicode_at(0)
	# Convert number (1-4) to column index (0-3)
	var col = int(name_str[1]) - 1
	return Vector2(col, row)

# Check if two cards belong to the same faction (are allies)
func is_ally_card(card1: Node2D, card2: Node2D) -> bool:
	if card1 == null or card2 == null:
		return false
		
	# Cards are allies if they belong to the same player
	return card1.is_player_card == card2.is_player_card

# Check if two cards are enemies (different factions)
func is_enemy_card(card1: Node2D, card2: Node2D) -> bool:
	if card1 == null or card2 == null:
		return false
		
	# Cards are enemies if they belong to different players
	return card1.is_player_card != card2.is_player_card

# Check if two slots are adjacent
func is_adjacent(slot1: Node2D, slot2: Node2D) -> bool:
	var distance = calculate_manhattan_distance(slot1, slot2)
	return distance == 1
# Get the four orthogonally adjacent slots (up, down, left, right) for a given slot
func get_adjacent_slots(slot: Node2D) -> Array:
	var adjacents = []
	var slot_pos = get_slot_grid_position(slot)
	# The four cardinal directions
	var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]

	for dir in directions:
		var new_pos = slot_pos + dir
		# Ensure position is within the 4x4 game board
		if new_pos.x >= 0 and new_pos.x < 4 and new_pos.y >= 0 and new_pos.y < 4:
			var adjacent_slot = game_board_reference.board_slots[new_pos.x][new_pos.y]
			adjacents.append(adjacent_slot)
	return adjacents

# Calculate all tiles a unit can move to, accounting for obstacles
func get_reachable_tiles(start_slot: Node2D, move_range: int) -> Array:
	var reachable_slots = []
	var visited = {}
	var queue = []
	
	# Start BFS from the starting slot
	queue.push_back({"slot": start_slot, "distance": 0})
	visited[start_slot.name] = true	 # Change to use slot name as the key
	
	while queue.size() > 0:
		var current = queue.pop_front()
		var current_slot = current["slot"]
		var current_distance = current["distance"]
		
		# Add to reachable slots if not the starting position
		if current_slot != start_slot:
			reachable_slots.append({"slot": current_slot, "distance": current_distance})
		
		# Stop searching if we've reached maximum move range
		if current_distance >= move_range:
			continue
		
		# Check only orthogonally adjacent slots (no diagonals)
		for adjacent_slot in get_adjacent_slots(current_slot):
			if visited.has(adjacent_slot.name):	 # Change to use slot name as the key
				continue  # Skip already visited slots
			
			# Check if the adjacent slot is occupied
			if adjacent_slot.is_occupied:
				var occupying_card = adjacent_slot.card_in_slot
				
				# We can only swap with allied units in orthogonally adjacent slots
				if occupying_card != null and is_ally_card(start_slot.card_in_slot, occupying_card) and occupying_card.can_perform_action(occupying_card.ActionType.MOVE):
					# Ensure this is an orthogonally adjacent slot (should be redundant with get_adjacent_slots)
					if is_adjacent(start_slot, adjacent_slot):
						reachable_slots.append({"slot": adjacent_slot, "distance": current_distance + 1})
				
				# Either way, don't continue BFS through occupied slots
				continue
			
			# For empty slots, add them to the search queue
			queue.push_back({"slot": adjacent_slot, "distance": current_distance + 1})
			visited[adjacent_slot.name] = true	# Change to use slot name as the key
	
	return reachable_slots

# Find player cards near a given slot that might have their movement affected
func get_nearby_player_cards(slot: Node2D, card:Node2D = null) -> Array:
	print("Debugging nearby cards search")
	print("Starting slot: ", slot.name)
	var nearby_cards = []
	
	# Increased search range for more comprehensive detection
	var search_range = 8  # Increased from 6
	
	if card != null:
		var card_data = card.get_current_card_data_dict()
		search_range = max(card_data["moveRange"] + 2, 8)
		
		if card_data["type"] == 0:	# Emperor type
			search_range = GameConstants.EMPEROR_MOVE_RANGE + 2
	
	var visited = {}
	var queue = []
	
	queue.push_back({"slot": slot, "distance": 0})
	visited[slot] = true
	
	while queue.size() > 0:
		var current = queue.pop_front()
		var current_slot = current["slot"]
		var current_distance = current["distance"]
		
		# Include cards within a wider search range
		if current_slot.is_occupied and current_slot.card_in_slot.is_player_card and current_slot != slot:
			nearby_cards.append(current_slot.card_in_slot)
		
		if current_distance >= search_range:
			continue
		
		for adjacent_slot in get_adjacent_slots(current_slot):
			if visited.has(adjacent_slot):
				continue
			
			queue.push_back({"slot": adjacent_slot, "distance": current_distance + 1})
			visited[adjacent_slot] = true
	
	print("Found nearby cards: ", nearby_cards.size())
	for nearby_card in nearby_cards:
		print("Nearby card: ", nearby_card.name)
	
	return nearby_cards
