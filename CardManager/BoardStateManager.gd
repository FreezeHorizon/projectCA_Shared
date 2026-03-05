class_name BoardStateManager
extends Node

var card_manager: Node2D
var game_board_reference: Node2D

var movement_map = {} 
var attack_map = {}   

func initialize(manager: Node2D, board: Node2D) -> void:
	card_manager = manager
	game_board_reference = board

func precompute_all_movement_maps() -> void:
	# Reset maps
	movement_map.clear()
	attack_map.clear()
	
	# Every unit on the board gets its options calculated
	for card in get_tree().get_nodes_in_group("AllCards"):
		if is_instance_valid(card) and card.card_is_in_slot != null:
			_calculate_options_for_unit(card)

func _calculate_options_for_unit(card: BaseCard) -> void:
	var card_key = card.name 
	var start_slot = card.card_is_in_slot
	
	movement_map[card_key] = {}
	attack_map[card_key] = {}
	
	# 1. MOVEMENT
	if card.can_perform_action(BaseCard.ActionType.MOVE):
		var move_range = card.current_move_range
		if card.card_type_enum == GameConstants.CardType.EMPEROR:
			move_range = GameConstants.EMPEROR_MOVE_RANGE
			
		var reachable_tiles = card_manager.placement.get_reachable_tiles(start_slot, move_range)
		for tile_data in reachable_tiles:
			movement_map[card_key][tile_data["slot"].name] = tile_data["distance"]

	# 2. ATTACK
	if card.can_perform_action(BaseCard.ActionType.ATTACK):
		var attack_range = card.current_attack_range
		
		for slot in get_tree().get_nodes_in_group("CardSlots"):
			if slot == start_slot: continue
			var dist = card_manager.placement.calculate_manhattan_distance(start_slot, slot)
			
			if dist <= attack_range:
				if slot.is_occupied and is_instance_valid(slot.card_in_slot):
					var target = slot.card_in_slot
					
					# 1. Ownership check (Different players)
					var is_enemy = (card.is_player_card != target.is_player_card)
					
					if is_enemy:
						# --- THE FIX ---
						# If it is Face Down, we CANNOT see stats, so we MUST be able to target it.
						# If it is Face Up, we CAN see stats, so check if it is still alive.
						if target.is_face_down:
							attack_map[card_key][slot.name] = true
						elif target.current_health > 0:
							attack_map[card_key][slot.name] = true

func clear_all_movement_maps() -> void:
	movement_map.clear()
	attack_map.clear()
