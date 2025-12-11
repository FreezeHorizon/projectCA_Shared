extends Node

@onready var placement_validator = $"../CardManager/PlacementValidator"
@onready var board_state_manager = $"../CardManager/BoardStateManager"


func validate_play_card(player: Player, card: BaseCard, target_slot: Node2D) -> bool:
	# 1. Check if target_slot exists
	if not target_slot:
		print("Validation Failed: No target slot.")
		return false

	# 2. Check Emperor Requirement
	if not card.is_emperor_card and not player.emperor_on_board:
		print("Validation Failed: Emperor not on board.")
		return false
		
	# 3. Check AP Cost
	if player.current_ap < card.current_cost:
		print("Validation Failed: Not enough AP.")
		return false

	# 4. Check if slot is occupied
	if target_slot.is_occupied:
		print("Validation Failed: Slot occupied.")
		return false

	# 5. Check Placement Rules (Range, etc.)
	if not placement_validator.is_valid_card_placement(target_slot, card):
		print("Validation Failed: Invalid placement position.")
		return false

	# If we passed all checks:
	return true

func validate_flip(player: Player, card: BaseCard) -> bool:
	# 1. Check Ownership
	# Logic: If it's Player 1, is_player_card must be true.
	#		 If it's Player 2, is_player_card must be false.
	var is_player_1 = (player.player_id == 1)
	
	if is_player_1 != card.is_player_card:
		print("	 Flip Denied: Not this player's card.")
		return false

	# 2. Check AP Cost
	var flip_ap_cost: int = 1 
	if player.current_ap < flip_ap_cost:
		print("	 Flip Denied: Player does not have enough AP for flip.")
		return false
		
	# 3. Check if actually Face Down (Sanity Check)
	if not card.is_face_down:
		print("	 Flip Denied: Card is already face up.")
		return false

	return true

# Remove the deck_node parameter. The Player object has the deck data.
func validate_extra_draw(player: Player) -> bool:
	# 1. Check if already used this turn
	if player.has_used_extra_draw:
		print("  Draw Denied: Player already used extra draw this turn.")
		return false

	# 2. Check AP Cost
	if player.current_ap < player.extra_draw_cost:
		print("  Draw Denied: Not enough AP. Has {ap}, needs {cost}".format({
			"ap": player.current_ap, "cost": player.extra_draw_cost
		}))
		return false

	# 3. Check if Deck is Empty (Using the Player data array)
	if player.deck_cards.is_empty():
		print("  Draw Denied: Deck is empty.")
		return false

	return true


func validate_move(player: Player, card: BaseCard, target_slot: Node2D) -> bool:
	# 1. Check Ownership
	var is_player_1 = (player.player_id == 1)
	if is_player_1 != card.is_player_card:
		print("  Move Denied: Not this player's card.")
		return false

	# 2. Check Action Availability
	if not card.can_perform_action(BaseCard.ActionType.MOVE):
		print("  Move Denied: Card cannot perform MOVE action.")
		return false

	# 3. Check Self-Move
	if target_slot == card.card_is_in_slot:
		print("  Move Denied: Cannot move to own slot.")
		return false

	# 4. Check Movement Range (Using the Map)
	var card_id = card.get_instance_id()
	if not board_state_manager.movement_map.has(card_id) or \
	   not board_state_manager.movement_map[card_id].has(target_slot.name):
		print("  Move Denied: Target slot is out of range.")
		return false
	
	# 5. Check Target Validity (Empty OR Ally Swap)
	if target_slot.is_occupied:
		# If occupied, it MUST be an ally to be valid (for swapping)
		if not placement_validator.is_ally_card(card, target_slot.card_in_slot):
			print("  Move Denied: Target slot occupied by non-ally.")
			return false
			
		# If it is an ally, that ally MUST also be able to move
		var ally = target_slot.card_in_slot
		if not ally.can_perform_action(BaseCard.ActionType.MOVE):
			print("  Move Denied: Swap target cannot move.")
			return false

	return true

func validate_attack(player: Player, attacker: BaseCard, defender: BaseCard) -> bool:
	# 1. Check Ownership
	var is_player_1 = (player.player_id == 1)
	if is_player_1 != attacker.is_player_card:
		print("  Attack Denied: Not this player's card.")
		return false

	# 2. Check Action Availability
	if not attacker.can_perform_action(BaseCard.ActionType.ATTACK):
		print("  Attack Denied: Attacker cannot perform ATTACK action.")
		return false

	# 3. Check Enemy Status
	if not placement_validator.is_enemy_card(attacker, defender):
		print("  Attack Denied: Target is not an enemy.")
		return false
		
	# 4. Check Range
	var distance = placement_validator.calculate_manhattan_distance(attacker.card_is_in_slot, defender.card_is_in_slot)
	if distance > attacker.current_attack_range:
		print("  Attack Denied: Target out of range.")
		return false
		
	# 5. Check Target Health
	if defender.current_health <= 0:
		print("  Attack Denied: Target is already dead.")
		return false
	
	return true
