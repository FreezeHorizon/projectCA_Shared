# BattleManager.gd
extends Node

signal unit_attack_resolved(attacking_card: BaseCard, defending_card: BaseCard, attacker_died: bool, defender_died: bool)
signal combat_log_message(message: String) # For UI display of combat events
signal card_added_to_hand(card_node: BaseCard, for_player_id: int) # Changed Card to BaseCard for broader type
# signal game_over(winner_id: int) 

# action signals
signal unit_moved(card_that_moved: BaseCard)
signal unit_attack_initiated(attacking_card: BaseCard, defending_card: BaseCard)
signal unit_retaliation_initiated(retaliating_card: BaseCard, original_attacker: BaseCard)
signal unit_flipped(card_that_flipped: BaseCard)


@onready var turn_info_display_label: RichTextLabel = get_node("%TurnInfoDisplay")
@onready var card_manager: Node2D = get_node("%CardManager")
@onready var player_deck: Node2D = get_node("%Deck") # Player 1's Deck
@onready var enemy_deck: Node2D = get_node("%EnemyDeck") # Player 2's Deck
@onready var mulligan_manager = get_node("%MulliganManager")
@onready var player_hand: Node2D = get_node("%PlayerHand") # Player 1's Hand
@onready var enemy_hand: Node2D = get_node("%EnemyHand")   # Player 2's Hand
@onready var input_manager: Node2D = get_node("%InputManager") 
@onready var turn_end_button: Button = get_node("%TurnEndButton")
@onready var placement_choice_prompt: Control = get_node("%PlacementChoice")
# --- Player State Variables ---
var player1_current_ap: int = 0
var player1_max_ap: int = 0
var player1_emperor_on_board: bool = false # Tracks if Player 1's emperor is on board
var player1_has_used_extra_draw_this_turn: bool = false
var player1_extra_draw_ap_cost: int = 2
enum GamePhase { SETUP, MULLIGAN, PLAYER_TURN, OPPONENT_TURN, GAME_OVER }
var current_game_phase: GamePhase = GamePhase.SETUP
var player2_current_ap: int = 0
var player2_max_ap: int = 0
var player2_emperor_on_board: bool = false # Tracks if Player 2's emperor is on board
# var p2_has_drawn_extra_this_turn: bool = false # For P2 if they get this mechanic
# var p2_extra_draw_ap_cost: int = 2

var current_player_id: int = 0 # 0: No one, 1: P1, 2: P2
var game_round: int = 0 

const OVERALL_MAX_AP: int = 10
const EXTRA_DRAW_COST_INCREMENT: int = 2
const EXTRA_DRAW_COST_MAX: int = 10

const INITIAL_MULLIGAN_CARDS_DRAWN: int = 3 # How many player sees in mulligan
const TARGET_HAND_SIZE_AFTER_MULLIGAN: int = 3 # What hand size should be after mulligan
var is_processing_turn_start: bool = false # Add this at the class level
var is_waiting_for_placement_choice: bool = false
func _ready() -> void:
	# Direct connections, assuming input_manager is always valid
	input_manager.mulligan_card_toggled.connect(_on_InputManager_mulligan_card_toggled)
	input_manager.board_card_deselected_intent.connect(_on_InputManager_board_card_deselected_intent)
	input_manager.slot_clicked_intent.connect(_on_InputManager_slot_clicked_intent)
	input_manager.deck_draw_card_intent.connect(_on_InputManager_deck_draw_card_intent)
	input_manager.card_drag_initiated.connect(_on_InputManager_card_drag_initiated)
	input_manager.attack_intent.connect(_on_InputManager_attack_intent)
	input_manager.board_card_move_intent.connect(_on_InputManager_board_card_move_intent)
	
	input_manager.card_single_clicked_on_board_intent.connect(_on_InputManager_card_single_clicked_on_board_intent)
	input_manager.card_double_clicked_on_board_intent.connect(_on_InputManager_card_double_clicked_on_board_intent)
	
	mulligan_manager.mulligan_choices_confirmed.connect(_on_MulliganManager_mulligan_choices_confirmed)
	card_manager.card_drag_placement_attempted.connect(_on_CardManager_card_drag_placement_attempted)
	
	start_new_game_setup()

func _connect_card_signals(card_node: BaseCard):
	if not is_instance_valid(card_node):
		return
	if not card_node.died.is_connected(_on_card_confirmed_death): # Avoid duplicate connections
		card_node.died.connect(_on_card_confirmed_death.bind(card_node)) # Pass card_node as argument
		print("BattleManager: Connected 'died' signal for card: ", card_node.name)
	if not card_node.card_flipped.is_connected(_on_any_card_flipped):
		card_node.card_flipped.connect(_on_any_card_flipped)

func _on_card_confirmed_death(card_that_died: BaseCard):
	# This 'card_that_died' is automatically passed by the signal emitter (BaseCard)
	if not is_instance_valid(card_that_died):
		# This could happen if the signal was deferred and something else freed the card,
		# but with direct _die() call emitting before queue_free, it's less likely.
		print("BattleManager: Received 'died' signal for an already invalid card instance.")
		# We might still need to trigger a general board state update if context is lost.
		card_manager.board_state.precompute_all_movement_maps()
		return

	print("BattleManager: Received 'died' signal from: ", card_that_died.name)
	_handle_unit_death(card_that_died) # Process game state consequences

func _on_any_card_flipped(card_instance: BaseCard, is_now_face_up: bool):
	# This function now runs whenever ANY card on the board flips.
	print("BattleManager OBSERVED that '", card_instance.name, "' has flipped. Face up: ", is_now_face_up)

	# Now, we emit our own GLOBAL signal for other systems or cards to listen to.
	emit_signal("unit_flipped", card_instance)

	# FUTURE USE: This is where you would check for card effects like:
	# "Whenever a card is flipped, do X."

func start_new_game_setup():
	print("BattleManager: Starting new game setup.")
	current_game_phase = GamePhase.SETUP
	game_round = 0 
	current_player_id = 0 # No player's turn yet explicitly
	
	player1_max_ap = 0; player1_current_ap = 0; player1_emperor_on_board = false
	player1_has_used_extra_draw_this_turn = false; player1_extra_draw_ap_cost = 2
	
	player2_max_ap = 0; player2_current_ap = 0; player2_emperor_on_board = false
	# p2_has_drawn_extra_this_turn = false; p2_extra_draw_ap_cost = 2
	
	turn_end_button.visible = false
	player_deck.set_deck_clickable(false) # Assumes player_deck is always valid
	enemy_deck.set_deck_clickable(false)  # Assumes enemy_deck is always valid

	await get_tree().create_timer(0.2).timeout 
	initiate_player_mulligan() # Player 1 mulligan first

func initiate_player_mulligan() -> void:
	print("BattleManager: Initiating mulligan for Player 1.")
	current_game_phase = GamePhase.MULLIGAN
	current_player_id = 1 # Set current player for context if needed by MulliganManager later
	var mulligan_nodes_p1: Array[Card] = player_deck.draw_mulligan(INITIAL_MULLIGAN_CARDS_DRAWN)
	var valid_nodes_p1: Array[Card] = []
	for card_node in mulligan_nodes_p1:
		valid_nodes_p1.append(card_node)
	
	if valid_nodes_p1.is_empty() and INITIAL_MULLIGAN_CARDS_DRAWN > 0:
		printerr("BattleManager: P1 - No valid cards for mulligan! Simulating empty mulligan.")
		_on_MulliganManager_mulligan_choices_confirmed([], []) 
	else:
		mulligan_manager.start_mulligan(valid_nodes_p1) # Call the corrected function name
	
func _on_MulliganManager_mulligan_choices_confirmed(kept_card_nodes: Array[Card], card_db_keys_to_return: Array[String]) -> void:
	# This handler is currently for Player 1's mulligan.
	# If P2 has a mulligan, you'll need a way to distinguish or a separate flow.
	print("BattleManager: P1 Mulligan choices confirmed. Kept: {k_size}, Returning: {r_size}".format({
		"k_size": kept_card_nodes.size(), "r_size": card_db_keys_to_return.size()
		}))	
	for key_to_return in card_db_keys_to_return:
		player_deck.return_card_name_to_deck(key_to_return)
	
	for card_node in kept_card_nodes:
		if card_node.get_parent() == mulligan_manager: 
			mulligan_manager.remove_child(card_node) 
		elif card_node.get_parent() != null: 
			card_node.get_parent().remove_child(card_node)
		card_manager.add_child(card_node)
		player_hand.add_card_to_hand(card_node, 0.3)
		if is_instance_valid(card_node): 
			_connect_card_signals(card_node)
		emit_signal("card_added_to_hand", card_node, 1) # Player 1
	
	var num_to_draw_replace = card_db_keys_to_return.size()
	print("BattleManager: P1 drawing {num} replacement cards.".format({"num": num_to_draw_replace}))
	if num_to_draw_replace > 0:
		for _i in range(num_to_draw_replace):
			#if player_deck.can_draw_card(): no need to check can draw flag because its mulligan
			var new_card: Card = player_deck.draw_card()
			card_manager.add_child(new_card)
			player_hand.add_card_to_hand(new_card, 0.3)
			_connect_card_signals(new_card)
			emit_signal("card_added_to_hand", new_card, 1)
			await get_tree().create_timer(0.4).timeout
	setup_enemy_initial_hand() # Now setup enemy hand
	pass

func setup_enemy_initial_hand() -> void: 
	print("BattleManager: Setting up enemy initial hand (Player 2).")
	# Enemy simply draws initial hand (no interactive mulligan for AI/P2 in this example)
	for _i in range(TARGET_HAND_SIZE_AFTER_MULLIGAN): # Enemy gets target hand size
		if enemy_deck.can_draw_card():
			var enemy_card_node = enemy_deck.draw_card() # Assumes EnemyDeck.draw_card()
			card_manager.add_child(enemy_card_node)
			enemy_hand.add_card_to_hand(enemy_card_node, 0.3)
			_connect_card_signals(enemy_card_node)
			emit_signal("card_added_to_hand", enemy_card_node, 2) # Player 2
	
	var enemy_emperor_node = enemy_deck.draw_emperor() # Assumes EnemyDeck.draw_emperor()
	card_manager.add_child(enemy_emperor_node)
	enemy_hand.add_card_to_hand(enemy_emperor_node, 0.3)
	enemy_emperor_node.set_as_emperor(true)
	_connect_card_signals(enemy_emperor_node)
	emit_signal("card_added_to_hand", enemy_emperor_node, 2)

	finalize_game_start()

func finalize_game_start() -> void:
	print("BattleManager: Finalizing initial game setup (Player 1 Emperor check & start).")
	var emperor_node: Card = player_deck.get_emperor_card_node()
	if is_instance_valid(emperor_node):
		var already_in_hand = false
		if not already_in_hand:
			card_manager.add_child(emperor_node)
			await player_hand.add_card_to_hand(emperor_node, 0.2)
			emperor_node.set_as_emperor(true)
			_connect_card_signals(emperor_node)
			emit_signal("card_added_to_hand", emperor_node, 1)
			print("BattleManager: Player 1 Emperor explicitly added to hand.")
	
	print("--- GAME STARTING ---")
	_update_turn_info_display()
	start_turn_for_player(1) # Player 1 starts the first actual game turn

func start_turn_for_player(player_id: int):
	if is_processing_turn_start:
		var prev_player_id_display = str(current_player_id) if current_player_id != 0 else "previous (or 0)"
		print("BattleManager: Already processing turn start for P{prev_id} - new call for P{new_id} aborted.".format({
			"prev_id": prev_player_id_display, 
			"new_id": player_id
			}))
	is_processing_turn_start = true
	current_game_phase = GamePhase.PLAYER_TURN if player_id == 1 else GamePhase.OPPONENT_TURN
	print("BattleManager: start_turn_for_player BEGIN for P", player_id, " Phase: ", GamePhase.keys()[current_game_phase])
	current_player_id = player_id
	
	if current_player_id == 1:
			game_round += 1 
			if player1_max_ap < OVERALL_MAX_AP: player1_max_ap += 1
			player1_current_ap = player1_max_ap
			player1_has_used_extra_draw_this_turn = false
			print("--- Player 1 Turn - Round {gr} ---".format({"gr": game_round}))
			print("P1 AP: {c}/{m} | P2 AP: {p2_cur}/{p2_max}".format({
				"c":player1_current_ap, "m":player1_max_ap, 
				"p2_cur": player2_current_ap, "p2_max": player2_max_ap
				}))
			_update_turn_info_display()
	else: # Player 2
		if player2_max_ap < OVERALL_MAX_AP: player2_max_ap += 1
		player2_current_ap = player2_max_ap
		print("--- Player 2 Turn - Round {gr} (Simulated AI) ---".format({"gr": game_round}))
		print("P1 AP: {p1_cur}/{p1_max} | P2 AP: {cur}/{max}".format({
			"p1_cur": player1_current_ap, "p1_max": player1_max_ap, 
			"cur": player2_current_ap, "max": player2_max_ap
			}))
		_update_turn_info_display()
		
	
	# Call _perform_standard_draw. It has an await, so this function will yield here.
	_reset_actions_for_player(current_player_id) 
	await _perform_standard_draw(current_player_id)
	current_game_phase = GamePhase.PLAYER_TURN if player_id == 1 else GamePhase.OPPONENT_TURN
	_update_turn_info_display()
	_update_ui_for_turn_state()
	if current_player_id == 2:
		print("  AI: Turn actions (if any) would go here. Auto-ending P2 turn.")
		is_processing_turn_start = false
		await get_tree().create_timer(0.1).timeout # Tiny delay before AI "clicks" end turn
		call_deferred("simulate_opponent_actions") 
		#_on_TurnEndButton_pressed() # AI "presses" end turn button
	else:
		# Only set to false here if it's not P2's turn (where it's set above)
		is_processing_turn_start = false
	print("BattleManager: start_turn_for_player END for P", player_id) # New print

# FUNCTION FOR SIMULATING OPPONENT (PLAYER 2) ACTIONS
func simulate_opponent_actions() -> void:
	if current_player_id != 2: # Safety check
		return

	print("BattleManager: Simulating Player 2 actions...")
	await get_tree().create_timer(0.5).timeout # Small delay to simulate "thinking"

	# --- 1. Try to Play Emperor if not on board ---
	if not player2_emperor_on_board:
		var enemy_hand_cards: Array[BaseCard] = enemy_hand.get_card_nodes_in_hand() # Use helper
		var emperor_in_hand: BaseCard = null
		for card_node in enemy_hand_cards:
			if card_node.is_emperor_card: # Check property from BaseCard
				emperor_in_hand = card_node
				break
		
		if is_instance_valid(emperor_in_hand):
			# Find a valid placement slot (e.g., first available empty slot in their starting rows)
			# This is a simplified placement logic for AI.
			var target_slot_for_emperor = _find_first_valid_placement_for_ai(emperor_in_hand, true) # true for enemy side
			if is_instance_valid(target_slot_for_emperor):
				print("  AI: Attempting to place Emperor '", emperor_in_hand.name, "' on slot '", target_slot_for_emperor.name, "'")
				# Simulate the drag and placement attempt
				# CardManager needs to know this card is "picked up" from enemy hand
				
				enemy_hand.remove_card_from_hand(emperor_in_hand) # Logically remove from AI hand list first
				emperor_in_hand.get_node("AnimationPlayer").play("place_on_board")
				_on_CardManager_card_drag_placement_attempted(emperor_in_hand, target_slot_for_emperor)
				await get_tree().create_timer(0.5).timeout # Delay after action
			else:
				print("  AI: No valid slot found for Emperor.")
		else:
			print("  AI: Emperor not found in hand to place.")
	
	# --- 2. Try to Play One Other Unit (Example) ---
	# Only if Emperor is now on board (or was already)
	if player2_emperor_on_board:
		var enemy_hand_cards_after_emperor: Array[BaseCard] = enemy_hand.get_card_nodes_in_hand()
		# Shuffle to make it a bit random, or pick based on a simple heuristic
		enemy_hand_cards_after_emperor.shuffle() 
		
		for card_to_play in enemy_hand_cards_after_emperor:
			if not card_to_play.is_emperor_card and player2_current_ap >= card_to_play.current_cost:
				var target_slot_for_unit = _find_first_valid_placement_for_ai(card_to_play, true)
				if is_instance_valid(target_slot_for_unit):
					print("  AI: Attempting to play Unit '", card_to_play.name, "' on slot '", target_slot_for_unit.name, "'")
					
					enemy_hand.remove_card_from_hand(card_to_play)
					card_to_play.get_node("AnimationPlayer").play("place_on_board")
					_on_CardManager_card_drag_placement_attempted(card_to_play, target_slot_for_unit)
					await get_tree().create_timer(0.5).timeout
					break # AI plays one unit this turn for simplicity
				# else: print(" AI: No valid slot for unit ", card_to_play.name)
	
	# --- 3. Try to Make One Attack (Existing Logic) ---
	# ... (your existing code for AI attacking) ...
	# if attack_made_this_turn:
		# await get_tree().create_timer(0.5).timeout

	# --- 4. NEW: Try to Make One Move ---
	# --- 4. NEW: Try to Make One Move ---
	print("  AI: Checking for movement opportunities...")
	var ai_movable_units: Array[BaseCard] = []
	for card_node in get_tree().get_nodes_in_group("AllCards"):
		if card_node is BaseCard and \
		   not card_node.is_player_card and \
		   is_instance_valid(card_node.card_is_in_slot) and \
		   card_node.can_perform_action(BaseCard.ActionType.MOVE):
			ai_movable_units.append(card_node)

	var move_made_this_turn: bool = false
	if not ai_movable_units.is_empty():
		ai_movable_units.shuffle() 
		var unit_to_move: BaseCard = ai_movable_units[0]
		
		print("  AI: Considering moving unit '", unit_to_move.name, "' from slot '", unit_to_move.card_is_in_slot.name, "'")

		var placement_validator = card_manager.get_node("PlacementValidator")
		var board_state_manager = card_manager.get_node("BoardStateManager")
		var movement_system = card_manager.get_node("CardMovementSystem")

		# var potential_move_slots: Array[Node2D] = [] # REMOVED - Unused
		var card_id = unit_to_move.get_instance_id()

		if board_state_manager.movement_map.has(card_id):
			var unit_movement_options = board_state_manager.movement_map[card_id]
			# var all_slots_on_board = get_tree().get_nodes_in_group("CardSlots") # REMOVED - Unused
			
			var adjacent_empty_slots: Array[Node2D] = []

			for slot_name_in_map in unit_movement_options.keys():
				# Ensure game_board_reference is valid and has get_slot_by_name
				if not is_instance_valid(card_manager.game_board_reference) or not card_manager.game_board_reference.has_method("get_slot_by_name"):
					printerr("AI Move: GameBoard reference or get_slot_by_name method is missing!")
					break # Cannot proceed without this

				var target_slot_node = card_manager.game_board_reference.get_slot_by_name(slot_name_in_map)
				
				if is_instance_valid(target_slot_node) and not target_slot_node.is_occupied:
					if placement_validator.is_adjacent(unit_to_move.card_is_in_slot, target_slot_node):
						adjacent_empty_slots.append(target_slot_node)
			
			if not adjacent_empty_slots.is_empty():
				adjacent_empty_slots.shuffle() 
				var chosen_target_slot: Node2D = adjacent_empty_slots[0]
				
				print("  AI: Unit '", unit_to_move.name, "' moving to '", chosen_target_slot.name, "'")

				if is_instance_valid(unit_to_move.state_machine):
					unit_to_move.state_machine.transition_to(unit_to_move.state_machine.State.MOVING)
				else: 
					unit_to_move.use_action(BaseCard.ActionType.MOVE, GameConstants.TriggerSource.PLAYER_CHOICE)

				movement_system.move_card_to_slot(unit_to_move, chosen_target_slot)
				
				if is_instance_valid(unit_to_move.state_machine) and \
				   unit_to_move.state_machine.get_current_state() == unit_to_move.state_machine.State.MOVING:
					unit_to_move.state_machine.transition_to(unit_to_move.state_machine.State.ON_BOARD_IDLE)

				move_made_this_turn = true
				await get_tree().create_timer(0.5).timeout 
			else:
				print("  AI: Unit '", unit_to_move.name, "' found no simple adjacent empty slots to move to.")
		else:
			print("  AI: Unit '", unit_to_move.name, "' has no movement map.")
	
	if not move_made_this_turn:
		print("  AI: No valid movement actions taken this turn.")
	# --- END OF NEW MOVEMENT LOGIC ---

	# --- 5. AI Ends its turn ---
	print("BattleManager: Player 2 (AI) finished actions, ending turn.")
	_on_TurnEndButton_pressed()

# Simple AI placement logic (can be expanded)
# Finds the first empty slot, prioritizing enemy's back rows, then front rows.
# `is_for_enemy_side` helps determine which rows are "theirs".
func _find_first_valid_placement_for_ai(card_to_place: BaseCard, is_for_enemy_side: bool) -> Node2D:
	# Define rows for enemy (typically top rows A, B) and player (bottom rows C, D)
	var primary_rows = ["A", "B"] if is_for_enemy_side else ["D", "C"]
	var secondary_rows = ["C", "D"] if is_for_enemy_side else ["B", "A"] # If primary are full
	var placement_validator = card_manager.get_node("PlacementValidator")

	var all_rows_to_check = primary_rows + secondary_rows

	for row_letter in all_rows_to_check:
		for col_num in range(1, 5): # Assuming columns 1-4
			var slot_name = row_letter + str(col_num)
			var slot_node: Node2D = card_manager.game_board_reference.get_node_or_null(slot_name) # GameBoard needs to allow access or have a getter
			
			if is_instance_valid(slot_node) and not slot_node.is_occupied:
				# Check if placement is valid according to game rules
				# This is where the existing PlacementValidator is crucial.
				# BattleManager needs to temporarily set card_manager.emperor_position
				# to the *correct* emperor (P1 or P2) if PlacementValidator relies on it directly.
				# Or, pass the relevant emperor's position to a modified is_valid_card_placement.
				
				# Simplified: Assume PlacementValidator uses card_manager.emperor_position.
				# We need to ensure card_manager.emperor_position is set for THE ENEMY before this check.
				var original_cm_emperor_pos = card_manager.emperor_position[current_player_id-1] # Store original
				var enemy_emperor_node_on_board: Node2D = null
				# Find enemy emperor if on board (this is a bit inefficient to do repeatedly)
				for card_on_board in get_tree().get_nodes_in_group("AllCards"):
					if card_on_board is BaseCard and not card_on_board.is_player_card and card_on_board.is_emperor_card and is_instance_valid(card_on_board.card_is_in_slot) :
						enemy_emperor_node_on_board = card_on_board.card_is_in_slot
						break
				
				if card_to_place.is_emperor_card:
					# For placing emperor, card_manager.emperor_position should be null (or the one being replaced if rules allow)
					# For simplicity, AI places emperor if its player2_emperor_on_board is false
					if not player2_emperor_on_board: # Check our flag
						card_manager.emperor_position[current_player_id-1] = null # Temporarily for placement validation
						if placement_validator.is_valid_card_placement(slot_node, card_to_place):
							card_manager.emperor_position[current_player_id-1] = original_cm_emperor_pos # Restore
							return slot_node
						card_manager.emperor_position[current_player_id-1] = original_cm_emperor_pos # Restore
				elif player2_emperor_on_board and is_instance_valid(enemy_emperor_node_on_board):
					card_manager.emperor_position[current_player_id-1] = enemy_emperor_node_on_board # Set context for PlacementValidator
					if placement_validator.is_valid_card_placement(slot_node, card_to_place):
						card_manager.emperor_position[current_player_id-1] = original_cm_emperor_pos # Restore
						return slot_node
					card_manager.emperor_position[current_player_id-1] = original_cm_emperor_pos # Restore
				# else: Cannot place non-emperor if P2 emperor not on board
	
	printerr("AI: Could not find any valid placement for card: ", card_to_place.name)
	return null

func _update_ui_for_turn_state():
	var active_player_emperor_on_board_flag = player1_emperor_on_board if current_player_id == 1 else player2_emperor_on_board
	turn_end_button.visible = true 
	turn_end_button.disabled = not active_player_emperor_on_board_flag
	
	if current_player_id == 1:
		var can_afford_extra_draw = player1_current_ap >= player1_extra_draw_ap_cost
		player_deck.set_deck_clickable(active_player_emperor_on_board_flag and \
									   not player1_has_used_extra_draw_this_turn and \
									   can_afford_extra_draw and \
									   player_deck.can_draw_card())
	else:
		player_deck.set_deck_clickable(false)

func _on_TurnEndButton_pressed() -> void:
	print("BattleManager: TurnEndButton pressed by Player {id}".format({"id": current_player_id}))
	turn_end_button.disabled = true
	card_manager.selection.deselect_all_cards()
	if current_player_id == 1:
		print("--- PLAYER 1 TURN ENDED ---")
		start_turn_for_player(2) # Start Player 2's turn
	elif current_player_id == 2:
		print("--- PLAYER 2 TURN ENDED (SIMULATED) ---")
		start_turn_for_player(1) # Start Player 1's next turn

func _reset_actions_for_player(player_id_whose_turn_is_starting: int) -> void:
	print("BattleManager: Resetting actions for player {id} (at start of their turn).".format({"id": player_id_whose_turn_is_starting}))
	for card_node_any_type in get_tree().get_nodes_in_group("AllCards"):
		if not is_instance_valid(card_node_any_type) or not card_node_any_type is BaseCard:
			continue
		var card: BaseCard = card_node_any_type as BaseCard
		
		var card_belongs_to_this_player: bool = (player_id_whose_turn_is_starting == 1 and card.is_player_card) or \
												 (player_id_whose_turn_is_starting == 2 and not card.is_player_card)
												 
		if card_belongs_to_this_player and card.card_is_in_slot != null:
			card.reset_action()
	
	card_manager.board_state.precompute_all_movement_maps()

func _perform_standard_draw(player_id_drawing: int) -> void:
	var active_deck = player_deck if player_id_drawing == 1 else enemy_deck
	var active_hand = player_hand if player_id_drawing == 1 else enemy_hand

	if not (is_instance_valid(active_deck) and is_instance_valid(active_hand)):
		printerr("BattleManager: Active deck or hand not found for player {id} for standard draw.".format({"id": player_id_drawing}))
		return

	if active_deck.can_draw_card():
		var new_card_node: BaseCard = active_deck.draw_card() 
		print("BattleManager: Player {id} drew card (turn start): {name}".format({"id": player_id_drawing, "name": new_card_node.name}))
		card_manager.add_child(new_card_node)
		active_hand.add_card_to_hand(new_card_node, 0.3)
		_connect_card_signals(new_card_node)
		emit_signal("card_added_to_hand", new_card_node, player_id_drawing)
		await get_tree().create_timer(0.3).timeout 
	else: 
		print("BattleManager: Player {id} deck is empty. Cannot draw (turn start).".format({"id": player_id_drawing}))


func _on_InputManager_mulligan_card_toggled(card_node: Card) -> void:
	mulligan_manager.toggle_mulligan_selection(card_node)

func _on_InputManager_board_card_deselected_intent(_card_node: Card) -> void: # card_node might be useful context later
	print("BattleManager: P{id} received board_card_deselected_intent.".format({"id": current_player_id}))
	card_manager.get_node("CardSelectionManager").deselect_all_cards()

func _on_InputManager_slot_clicked_intent(slot_node: Node2D, selected_card_before_click: BaseCard) -> void: # Changed Card to BaseCard
	var selected_card_name_str: String = "None"
	if is_instance_valid(selected_card_before_click): 
		selected_card_name_str = selected_card_before_click.name

	print("BattleManager: P{id} received generic slot_clicked_intent for slot: {slot_name} with selected card: {card_name}. This intent should ideally be for non-action clicks now.".format({
		"id": current_player_id, "slot_name": str(slot_node.name) if is_instance_valid(slot_node) else "Invalid Slot", "card_name": selected_card_name_str
		}))

	# Most specific actions (move, attack, deselect via empty space) should be handled by other intents.
	# If this is still triggered with a selected card, it implies a click on a non-highlighted slot
	# that InputManager's Priority 3 deselection logic didn't catch or handle as a deselect intent.
	if is_instance_valid(selected_card_before_click):
		print("  BattleManager: Generic slot click with a selected card. Forcing deselect.")
		card_manager.get_node("CardSelectionManager").deselect_all_cards()
		card_manager.reset_all_slot_overlays()

func _on_InputManager_card_single_clicked_on_board_intent(card_node: BaseCard):
	if not is_instance_valid(card_node):
		printerr("BattleManager: Received card_single_clicked_on_board_intent for an invalid card node.")
		return
	
	print("BattleManager: Received card_single_clicked_on_board_intent for card: ", card_node.name)
	var selection_manager = card_manager.get_node("CardSelectionManager")
	if not is_instance_valid(selection_manager):
		printerr("BattleManager: CardSelectionManager not found!")
		return

	# 1. Check if it's a player's card (AI cards are not selectable by player)
	#    And ensure it's the current player's turn to interact with their own cards.
	var can_interact_with_card: bool = false
	if current_player_id == 1 and card_node.is_player_card:
		can_interact_with_card = true
	# Add elif for player 2 if they become human controlled and can select their cards
	# elif current_player_id == 2 and not card_node.is_player_card:
	#     can_interact_with_card = true 

	if not can_interact_with_card:
		print("  Interaction Denied: Cannot select/deselect card '", card_node.name, "' (not current player's card or not their turn to select).")
		# If an opponent's card was selected, deselect it.
		if selection_manager.get_selected_card() != null and not selection_manager.get_selected_card().is_player_card == (current_player_id == 1) :
			selection_manager.deselect_all_cards()
		return

	var previously_selected_card = selection_manager.get_selected_card()

	if previously_selected_card == card_node:
		# Clicked on the already selected card: Deselect it
		print("  Card '", card_node.name, "' was already selected. Deselecting.")
		selection_manager.deselect_all_cards() # This handles state transition and overlay reset
	else:
		# Clicked on a new selectable card (or the first card to be selected)
		print("  Selecting new card '", card_node.name, "'.")
		if is_instance_valid(previously_selected_card):
			selection_manager.deselect_all_cards() # Deselect the old one first
		
		# Select the new card
		if is_instance_valid(card_node.state_machine):
			card_node.state_machine.transition_to(card_node.state_machine.State.SELECTED,GameConstants.TriggerSource.PLAYER_CHOICE)
		selection_manager.select_card_on_board(card_node) # This shows ranges

func _on_InputManager_card_double_clicked_on_board_intent(card_node: BaseCard):
	if not is_instance_valid(card_node):
		printerr("BattleManager: Received card_double_clicked_intent for an invalid card node.")
		return

	print("BattleManager: Received card_double_clicked_intent for card: ", card_node.name)

	# InputManager should have already ensured it's a SELECTED, FACE-DOWN card.
	# We still need to check for player ownership and AP.
	if not (current_player_id == 1 and card_node.is_player_card):
		print("  Flip Denied: Not Player 1's card or not their turn.")
		return

	var flip_ap_cost: int = 1 
	if player1_current_ap < flip_ap_cost:
		print("  Flip Denied: Player 1 does not have enough AP for flip.")
		return
			
	print("  Flipping card '", card_node.name, "' face-up. Cost: ", flip_ap_cost, " AP.")
	player1_current_ap -= flip_ap_cost
	
	card_node.flip_card(true, GameConstants.TriggerSource.PLAYER_CHOICE)

	emit_signal("combat_log_message", "Player 1 flipped {card_name} face-up.".format({"card_name": card_node.name}))
	card_manager.get_node("CardSelectionManager").select_card_on_board(card_node)
	_update_turn_info_display()
	_update_ui_for_turn_state()

func _on_InputManager_deck_draw_card_intent() -> void:
	print("BattleManager: P{id} received deck_draw_card_intent (for EXTRA draw)".format({"id": current_player_id}))
	if current_game_phase != GamePhase.PLAYER_TURN or current_player_id != 1: # Assuming P1 is human
		print("BattleManager: Deck click ignored. Not P1's active turn phase. Current Phase: ", GamePhase.keys()[current_game_phase])
		return
	if current_player_id == 1:
		if player1_has_used_extra_draw_this_turn:
			print("  Action Denied: P1 already used extra draw this turn.") ; return
		if player1_current_ap < player1_extra_draw_ap_cost:
			print("  Action Denied: P1 not enough AP for extra draw. Has {ap}, needs {cost}".format({
				"ap": player1_current_ap, "cost": player1_extra_draw_ap_cost
				})) ; return
		if not player_deck.can_draw_card():
			print("  Action Denied: P1 Deck is empty.") ; return

		print("  P1 attempting extra draw. Cost: {cost}".format({"cost": player1_extra_draw_ap_cost}))
		player1_current_ap -= player1_extra_draw_ap_cost
		player1_has_used_extra_draw_this_turn = true
		var new_card: Card = player_deck.draw_card()
		if is_instance_valid(new_card):
			card_manager.add_child(new_card)
			player_hand.add_card_to_hand(new_card, 0.3)
			_connect_card_signals(new_card)
			emit_signal("card_added_to_hand", new_card, 1)
			player1_extra_draw_ap_cost = min(player1_extra_draw_ap_cost + EXTRA_DRAW_COST_INCREMENT, EXTRA_DRAW_COST_MAX)
			print("  P1 AP: {ap}. Next extra draw cost: {next_cost}".format({
			"ap": player1_current_ap, "next_cost": player1_extra_draw_ap_cost
			}))		
		_update_turn_info_display()
		_update_ui_for_turn_state() # Update deck clickability

	elif current_player_id == 2: # Placeholder if P2 gets extra draw
		print("  Extra draw for Player 2 not yet implemented.")
		pass 

func _on_InputManager_card_drag_initiated(card_node: Card) -> void:
	# Rule check: Can this card be dragged by the current player?
	if not ((current_player_id == 1 and card_node.is_player_card) or \
			(current_player_id == 2 and not card_node.is_player_card)):
		print("BattleManager: P{id} cannot drag card '{name}' (not their card).".format({
			"id": current_player_id, "name": card_node.name
			}))
		return
	if not card_node.state_machine.can_drag(): 
		print("BattleManager: Card '{name}' cannot be dragged (state: {state}).".format({
			"name": card_node.name, "state": card_node.state_machine.get_current_state()
			}))
		return

	print("BattleManager: P{id} received card_drag_initiated for: {name}".format({
		"id": current_player_id, "name": card_node.name
		}))
	if card_manager:
		var selection_manager = card_manager.get_node("CardSelectionManager")
		if selection_manager.is_any_card_selected() and selection_manager.get_selected_card() != card_node :
			selection_manager.deselect_all_cards()
		card_manager.start_drag(card_node) # CardManager handles visual start of drag

func _on_InputManager_attack_intent(attacking_card: BaseCard, defending_card: BaseCard) -> void:
	if not (attacking_card is BaseCard and defending_card is BaseCard):
		printerr("BattleManager: Received attack_intent with invalid card types.")
		return

	print("BattleManager: P{id} received attack_intent. Attacker: '{atk_name}', Defender: '{def_name}'".format({
		"id": current_player_id, "atk_name": attacking_card.name, "def_name": defending_card.name
		}))

	# --- Phase 1: VALIDATION ---
	# Ensure the action is legal before proceeding.

	# Check if the attacker belongs to the current player.
	if not ((current_player_id == 1 and attacking_card.is_player_card) or \
			(current_player_id == 2 and not attacking_card.is_player_card)):
		print("  Attack Denied: Not '{atk_name}' owner's turn.".format({"atk_name": attacking_card.name}))
		return

	# Check if the attacker has an attack action available.
	if not attacking_card.can_perform_action(BaseCard.ActionType.ATTACK):
		print("  Attack Denied: '{atk_name}' cannot perform ATTACK action.".format({"atk_name": attacking_card.name}))
		return

	# Check if the target is a valid enemy.
	var placement_validator = card_manager.get_node("PlacementValidator")
	if not placement_validator.is_enemy_card(attacking_card, defending_card):
		print("  Attack Denied: '{def_name}' is not an enemy of '{atk_name}'.".format({"def_name": defending_card.name, "atk_name": attacking_card.name}))
		return
		
	# Check if the target is within the attacker's range.
	var distance = placement_validator.calculate_manhattan_distance(attacking_card.card_is_in_slot, defending_card.card_is_in_slot)
	if distance > attacking_card.current_attack_range:
		print("  Attack Denied: '{def_name}' (dist {d}) is out of '{atk_name}' attack range ({r}).".format({
			"def_name": defending_card.name, "d": distance, "atk_name": attacking_card.name, "r": attacking_card.current_attack_range
			}))
		return
		
	# Check if the defender is already defeated.
	if defending_card.current_health <= 0:
		print("  Attack Invalid: '{def_name}' is already defeated.".format({"def_name": defending_card.name}))
		return

	# --- Phase 2: DECLARATION & REVEAL ---
	# All checks passed. Declare intentions and update the board state before damage.
	print("  Attack Validated: '{atk_name}' ({atk_hp} HP, {atk_atk} ATK) vs '{def_name}' ({def_hp} HP, {def_atk} ATK)".format({
		"atk_name": attacking_card.name, "atk_hp": attacking_card.current_health, "atk_atk": attacking_card.current_attack,
		"def_name": defending_card.name, "def_hp": defending_card.current_health, "def_atk": defending_card.current_attack
		}))

	# Attacker declares its intent, entering the ATTACKING state.
	emit_signal("unit_attack_initiated", attacking_card, defending_card)
	if is_instance_valid(attacking_card.state_machine):
		attacking_card.state_machine.transition_to(attacking_card.state_machine.State.ATTACKING)

	# Defender is revealed if it was face-down. This happens before retaliation is determined.
	if is_instance_valid(defending_card) and defending_card.is_face_down:
		print("  Combat Reveal: Defending card '", defending_card.name, "' is face-down. Flipping face-up.")
		defending_card.flip_card(true, GameConstants.TriggerSource.COMBAT_REVEAL)
		emit_signal("combat_log_message", "{def_name} is revealed!".format({"def_name": defending_card.name}))

	# Calculate all potential damage *before* applying any of it.
	var attacker_damage_to_defender: int = attacking_card.current_attack
	var defender_retaliation_damage_to_attacker: int = 0

	# Defender declares its retaliation, if possible.
	if defending_card.can_retaliate:
		defender_retaliation_damage_to_attacker = defending_card.current_attack
		emit_signal("unit_retaliation_initiated", defending_card, attacking_card)
		if is_instance_valid(defending_card.state_machine):
			defending_card.state_machine.transition_to(defending_card.state_machine.State.RETALIATE)
		print("  '{def_name}' will retaliate for {dmg} damage.".format({
			"def_name": defending_card.name, "dmg": defender_retaliation_damage_to_attacker
			}))
	else:
		print("  '{def_name}' cannot retaliate.")

	# --- Phase 3: ACTION & SIMULTANEOUS DAMAGE ---
	# With all intentions declared, the attacker's action is now officially consumed.
	attacking_card.use_action(BaseCard.ActionType.ATTACK, GameConstants.TriggerSource.PLAYER_CHOICE)

	# Damage is applied to both units. Because damage values were pre-calculated, this is effectively simultaneous.
	if attacker_damage_to_defender > 0:
		defending_card.take_damage(attacker_damage_to_defender)
		emit_signal("combat_log_message", "{atk} attacks {def} for {dmg} damage!".format({
			"atk": attacking_card.card_name, "def": defending_card.card_name, "dmg": attacker_damage_to_defender
			}))

	if defender_retaliation_damage_to_attacker > 0:
		attacking_card.take_damage(defender_retaliation_damage_to_attacker)
		emit_signal("combat_log_message", "{def} retaliates against {atk} for {dmg} damage!".format({
			"def": defending_card.card_name, "atk": attacking_card.card_name, "dmg": defender_retaliation_damage_to_attacker
			}))

	# --- Phase 4: RESOLUTION & CLEANUP ---
	# Check the final health of both cards to determine the outcome.
	var defender_died_this_combat: bool = defending_card.current_health <= 0
	var attacker_died_this_combat: bool = attacking_card.current_health <= 0
	
	# Transition any surviving units back to their idle state.
	if not attacker_died_this_combat and is_instance_valid(attacking_card.state_machine):
		if attacking_card.state_machine.get_current_state() in [attacking_card.state_machine.State.ATTACKING, attacking_card.state_machine.State.DAMAGED]:
			attacking_card.state_machine.transition_to(attacking_card.state_machine.State.ON_BOARD_IDLE)

	if not defender_died_this_combat and is_instance_valid(defending_card.state_machine):
		if defending_card.state_machine.get_current_state() in [defending_card.state_machine.State.RETALIATE, defending_card.state_machine.State.DAMAGED]:
			defending_card.state_machine.transition_to(defending_card.state_machine.State.ON_BOARD_IDLE)

	# Emit the final outcome signal for any systems that need to know the results of the combat.
	emit_signal("unit_attack_resolved", attacking_card, defending_card, attacker_died_this_combat, defender_died_this_combat)
	
	# Reset board visuals and check for game-ending conditions.
	card_manager.reset_all_slot_overlays()
	_update_ui_for_turn_state()
	check_for_game_over()

func _on_InputManager_board_card_move_intent(card_to_move: BaseCard, target_slot: Node2D) -> void:
	if not is_instance_valid(card_to_move) or not is_instance_valid(target_slot):
		printerr("BattleManager: Received board_card_move_intent with invalid card or slot.")
		return

	print("BattleManager: P{id} received board_card_move_intent for '{card_name}' to slot '{slot_name}'".format({
		"id": current_player_id, "card_name": card_to_move.name, "slot_name": target_slot.name
		}))
	# --- Get necessary subsystems from CardManager ---
	var board_state_manager = card_manager.get_node("BoardStateManager")
	var placement_validator = card_manager.get_node("PlacementValidator")
	var movement_system = card_manager.get_node("CardMovementSystem")
	var selection_manager = card_manager.get_node("CardSelectionManager")
	# --- VALIDATION ---
	# 1. Is it the card owner's turn?
	if not ((current_player_id == 1 and card_to_move.is_player_card) or \
			(current_player_id == 2 and not card_to_move.is_player_card)):
		print("  Move Denied: Not '{card_name}' owner's turn.".format({"card_name": card_to_move.name}))
		return

	# 2. Can the card perform a MOVE action?
	if not card_to_move.can_perform_action(BaseCard.ActionType.MOVE):
		print("  Move Denied: '{card_name}' cannot perform MOVE action.".format({"card_name": card_to_move.name}))
		selection_manager.deselect_all_cards()
		return

	# 3. AP Cost for moving (if any - currently no AP cost for moving is implemented in your rules)
	# var move_ap_cost = 0 # Example: GameConstants.MOVE_AP_COST
	# var active_player_current_ap = player1_current_ap if current_player_id == 1 else player2_current_ap
	# if active_player_current_ap < move_ap_cost:
	#     print("  Move Denied: Not enough AP for move. Has {ap}, needs {cost}".format(...))
	#     return
	# Possible future use

	# 4. Is the target_slot valid for movement?
	if target_slot == card_to_move.card_is_in_slot:
		print("  Move Denied: Card '{card_name}' attempting to move to its own slot.".format({"card_name": card_to_move.name}))
		selection_manager.deselect_all_cards()
		card_manager.reset_all_slot_overlays()
		return

	var card_id = card_to_move.get_instance_id()
	if not board_state_manager.movement_map.has(card_id) or \
	   not board_state_manager.movement_map[card_id].has(target_slot.name):
		print("  Move Denied: Target slot '{slot_name}' is not in the precomputed movement map for '{card_name}'.".format({
			"slot_name": target_slot.name, "card_name": card_to_move.name
			}))
		selection_manager.deselect_all_cards() # Invalid move target, deselect
		return

	# --- EXECUTION ---
	# If we reach here, the basic movement map check passed. Now differentiate move vs. swap.

	if not target_slot.is_occupied:
		print("  BattleManager: Moving card '{card_name}' to empty slot '{slot_name}'.".format({
			"card_name": card_to_move.name, "slot_name": target_slot.name
			}))
		movement_system.move_card_to_slot(card_to_move, target_slot)
		emit_signal("unit_moved", card_to_move)
		if is_instance_valid(card_to_move.state_machine):
			card_to_move.state_machine.transition_to(card_to_move.state_machine.State.MOVING)
		else:
			# Fallback if state machine somehow invalid, though it shouldn't be
			printerr("BattleManager: StateMachine for ", card_to_move.name, " is invalid during move intent!")
			card_to_move.use_action(BaseCard.ActionType.MOVE, GameConstants.TriggerSource.PLAYER_CHOICE)
		
		
		
		# The MOVING state should ideally transition to ON_BOARD_IDLE after its action/animation.
		# If CardMovementSystem.move_card_to_slot already forces it to ON_BOARD_IDLE, 
		# the MOVING state might be very brief or might need to handle its own transition back.
		# For now, CMSys.move_card_to_slot does set it to ON_BOARD_IDLE.
		# Let's ensure the MOVING state correctly transitions back.
		# In CardStateMachine._is_valid_transition for MOVING:
		# return to_state == State.ON_BOARD_IDLE or to_state == State.DAMAGED
		# The transition from MOVING to IDLE should happen after the move visual is complete.
		# If move_card_to_slot is instant, then BattleManager can transition it back:
		if is_instance_valid(card_to_move.state_machine) and card_to_move.state_machine.get_current_state() == card_to_move.state_machine.State.MOVING:
			card_to_move.state_machine.transition_to(card_to_move.state_machine.State.ON_BOARD_IDLE)
		
	elif target_slot.is_occupied and placement_validator.is_ally_card(card_to_move, target_slot.card_in_slot):
		var ally_card_in_target_slot: BaseCard = target_slot.card_in_slot as BaseCard
		if is_instance_valid(ally_card_in_target_slot) and ally_card_in_target_slot.can_perform_action(BaseCard.ActionType.MOVE):
			print("  BattleManager: Swapping card '{card_name}' with ally '{ally_name}'.".format({
				"card_name": card_to_move.name, "ally_name": ally_card_in_target_slot.name
				}))
			movement_system.swap_card_positions(card_to_move, ally_card_in_target_slot)
			emit_signal("unit_moved", card_to_move)
			emit_signal("unit_moved", ally_card_in_target_slot)
		else:
			print("  Move Denied: Cannot swap with ally in slot '{slot_name}'.".format({"slot_name": target_slot.name}))
			selection_manager.deselect_all_cards()
			card_manager.reset_all_slot_overlays()
			return
	else:
		print("  Move Denied: Target slot '{slot_name}' is occupied by non-ally or unexpected state.".format({"slot_name": target_slot.name}))
		selection_manager.deselect_all_cards()
		card_manager.reset_all_slot_overlays()
		return

	# --- POST-ACTION ---
	# CardMovementSystem methods should now handle:
	# - card_to_move.use_action(BaseCard.ActionType.MOVE)
	# - (if swapping) ally_card.use_action(BaseCard.ActionType.MOVE)
	# - State machine transitions to MOVING then ON_BOARD_IDLE
	# - Updating CardManager.emperor_position if an emperor moved
	# - Updating BoardStateManager (movement maps)

	selection_manager.deselect_all_cards() # Deselect after successful move/swap
	card_manager.reset_all_slot_overlays() # Clear highlights
	_update_ui_for_turn_state() # Update AP display, deck, etc.

func _on_CardManager_card_drag_placement_attempted(dragged_card: BaseCard, target_slot: Node2D) -> void:
	var target_slot_name_str: String = "None"
	if is_instance_valid(target_slot): target_slot_name_str = target_slot.name
	var card_display_name = dragged_card.name

	print("BattleManager: P{id} card_drag_placement_attempted for '{c_name}' to slot {s_name}".format({
		"id": current_player_id, "c_name": card_display_name, "s_name": target_slot_name_str
		}))
	
	var active_player_current_ap = player1_current_ap if current_player_id == 1 else player2_current_ap
	var active_player_emperor_flag = player1_emperor_on_board if current_player_id == 1 else player2_emperor_on_board
	var active_hand_ref = player_hand if current_player_id == 1 else enemy_hand
	var originally_highlighted_target_slot: Node2D = target_slot 

	# --- Initial Validations ---
	if not target_slot:
		print("  Invalid target (not a slot). Returning card to hand.")
		if is_instance_valid(dragged_card): dragged_card.visible = true # Ensure visible before returning
		active_hand_ref.add_card_to_hand(dragged_card, 0.4)
		if is_instance_valid(dragged_card.state_machine):
			dragged_card.state_machine.transition_to(dragged_card.state_machine.State.IN_HAND, GameConstants.TriggerSource.PLAYER_CHOICE)
		card_manager.reset_all_slot_overlays()
		return

	var card_ap_cost = dragged_card.current_cost
	if not dragged_card.is_emperor_card and not active_player_emperor_flag:
		print("  Action Denied: P{id} Emperor not on board. Cannot play non-Emperor card.".format({"id": current_player_id}))
		active_hand_ref.add_card_to_hand(dragged_card, 0.3)
		if is_instance_valid(dragged_card.state_machine):
			dragged_card.state_machine.transition_to(dragged_card.state_machine.State.IN_HAND, GameConstants.TriggerSource.PLAYER_CHOICE)
		return
		
	if active_player_current_ap < card_ap_cost:
		print("  Action Denied: P{id} Not enough AP. Has {ap}, card costs {cost}".format({
			"id": current_player_id, "ap": active_player_current_ap, "cost": card_ap_cost
			}))
		active_hand_ref.add_card_to_hand(dragged_card, 0.3)
		if is_instance_valid(dragged_card.state_machine):
			dragged_card.state_machine.transition_to(dragged_card.state_machine.State.IN_HAND,  GameConstants.TriggerSource.PLAYER_CHOICE)
		card_manager.reset_all_slot_overlays()
		return
		
		
		
	if target_slot.is_occupied:
		print("  Action Denied: Slot {name} is already occupied.".format({"name": target_slot.name}))
		active_hand_ref.add_card_to_hand(dragged_card, 0.3)
		if is_instance_valid(dragged_card.state_machine):
			dragged_card.state_machine.transition_to(dragged_card.state_machine.State.IN_HAND)
		return
	
	var placement_validator = card_manager.get_node("PlacementValidator")
	if not placement_validator.is_valid_card_placement(target_slot, dragged_card):
		print("  Action Denied: Invalid placement according to PlacementValidator.")
		active_hand_ref.add_card_to_hand(dragged_card, 0.3)
		if is_instance_valid(dragged_card.state_machine):
			dragged_card.state_machine.transition_to(dragged_card.state_machine.State.IN_HAND)
		card_manager.reset_all_slot_overlays()
		return

	# --- All initial validations passed ---
	
	# --- Show Placement Choice Prompt if needed ---
	var place_card_face_up: bool = true # Default for AI or Emperors
	var placement_succeeded: bool = false # Flag to track if card was actually placed
	
	if dragged_card.is_player_card and not dragged_card.is_emperor_card:
		if is_instance_valid(placement_choice_prompt):
			if placement_choice_prompt.is_visible():
				print("BattleManager: Prompt already visible, returning card to hand.")
				if is_instance_valid(dragged_card): dragged_card.visible = true
				active_hand_ref.add_card_to_hand(dragged_card, 0.3)
				if is_instance_valid(dragged_card.state_machine):
					dragged_card.state_machine.transition_to(dragged_card.state_machine.State.IN_HAND)
				# is_waiting_for_placement_choice should ideally already be true if prompt is visible
				return
			if is_instance_valid(dragged_card):
				dragged_card.visible = false 
				print("  Made dragged card '", dragged_card.name, "' invisible.")
			for slot_node_in_group in get_tree().get_nodes_in_group("CardSlots"):
				if slot_node_in_group != originally_highlighted_target_slot:
					slot_node_in_group.reset_overlays() 
				elif is_instance_valid(originally_highlighted_target_slot): # Ensure it's still valid
					# Make sure the target slot specifically shows the "placement" highlight
					originally_highlighted_target_slot.update_highlight("placement", true) 
			is_waiting_for_placement_choice = true 
			turn_end_button.disabled = true       
			player_deck.set_deck_clickable(false) 
			if is_instance_valid(player_hand) and player_hand.has_method("set_processing_paused"):
				player_hand.set_processing_paused(true)

			placement_choice_prompt.show_prompt(dragged_card)
			print("BattleManager: Awaiting placement choice...")

			var choice_result_holder = {"chosen_face_up": null, "cancelled": false, "signal_received": false}
			var choice_made_callable = func(is_f_up):
				choice_result_holder.chosen_face_up = is_f_up
				choice_result_holder.signal_received = true
			var cancelled_callable = func():
				choice_result_holder.cancelled = true
				choice_result_holder.signal_received = true
			
			placement_choice_prompt.choice_made.connect(choice_made_callable)
			placement_choice_prompt.placement_cancelled.connect(cancelled_callable)

			var timer = get_tree().create_timer(60.0) 
			var timed_out = false

			while not choice_result_holder.signal_received and not timed_out:
				if timer.time_left <= 0.0: 
					timed_out = true
					print("BattleManager: Placement choice timed out.")
					break
				await get_tree().process_frame 
			if is_instance_valid(placement_choice_prompt):
				if placement_choice_prompt.choice_made.is_connected(choice_made_callable):
					placement_choice_prompt.choice_made.disconnect(choice_made_callable)
				if placement_choice_prompt.placement_cancelled.is_connected(cancelled_callable):
					placement_choice_prompt.placement_cancelled.disconnect(cancelled_callable)
			
			if is_instance_valid(target_slot):
				target_slot.reset_overlays() 
				print("  Reset overlays for target slot '", target_slot.name, "'.")

			if choice_result_holder.cancelled or timed_out:
				print("  Placement cancelled or timed out. Returning card to hand.")
				if is_instance_valid(dragged_card): # Make visible before returning to hand
					dragged_card.visible = true 
				active_hand_ref.add_card_to_hand(dragged_card, 0.3)
				if is_instance_valid(dragged_card.state_machine):
					dragged_card.state_machine.transition_to(dragged_card.state_machine.State.IN_HAND)
				if is_instance_valid(placement_choice_prompt) and placement_choice_prompt.is_visible():
					placement_choice_prompt.hide_prompt()
				
				is_waiting_for_placement_choice = false 
				_update_ui_for_turn_state()             
				if is_instance_valid(player_hand) and player_hand.has_method("set_processing_paused"):
					player_hand.set_processing_paused(false) 
				card_manager.reset_all_slot_overlays()
				return 
			elif choice_result_holder.chosen_face_up != null: 
				place_card_face_up = choice_result_holder.chosen_face_up
				print("  BattleManager: Player chose to place card face-up: ", place_card_face_up)
				placement_succeeded = true
				# Prompt should have hidden itself. Card visibility handled before placement.
				
			else: 
				print("  Placement choice unclear. Returning card to hand.")
				if is_instance_valid(dragged_card): # Make visible before returning
					dragged_card.visible = true
				active_hand_ref.add_card_to_hand(dragged_card, 0.3)
				if is_instance_valid(dragged_card.state_machine):
					dragged_card.state_machine.transition_to(dragged_card.state_machine.State.IN_HAND)
				if is_instance_valid(placement_choice_prompt) and placement_choice_prompt.is_visible():
					placement_choice_prompt.hide_prompt()
				
				is_waiting_for_placement_choice = false 
				_update_ui_for_turn_state()	
				if is_instance_valid(player_hand) and player_hand.has_method("set_processing_paused"):
					player_hand.set_processing_paused(false) 
				card_manager.reset_all_slot_overlays()
				return
		else: 
			printerr("BattleManager: PlacementChoicePromptUI instance not found!")
			place_card_face_up = true 
			if is_instance_valid(dragged_card): dragged_card.visible = true # Ensure visible if prompt fails
			placement_succeeded = true
	else: 
		place_card_face_up = true
		if is_instance_valid(dragged_card): dragged_card.visible = true # Ensure visible for AI/Emperor
		placement_succeeded = true

	# This block runs if prompt was skipped OR a choice was made and didn't return early
	is_waiting_for_placement_choice = false 
	#_update_ui_for_turn_state() # Update UI based on current game state (AP might have changed if prompt had cost)
	if is_instance_valid(player_hand) and player_hand.has_method("set_processing_paused"):
		player_hand.set_processing_paused(false) 
		
# --- Actual Placement Logic ---
	if placement_succeeded:
		# Make sure card is visible before placement
		if is_instance_valid(dragged_card) and not dragged_card.visible: 
			dragged_card.visible = true
		
		# Set the card's intended face-down state
		dragged_card.is_face_down = not place_card_face_up
		print("  BattleManager: Setting ", dragged_card.name, ".is_face_down to ", dragged_card.is_face_down)
		dragged_card.is_entering_board_face_down = dragged_card.is_face_down 
		# dragged_card._update_visual_state() #Explicit call if setter isn't working, but setter is preferred

		print("	 Placement confirmed for {name}. Cost: {cost}. Face down: {fd}".format({
			"name": dragged_card.name, "cost": card_ap_cost, "fd": dragged_card.is_face_down
			}))
		
		# Update Game State (AP and Emperor status)
		if current_player_id == 1:
			player1_current_ap -= card_ap_cost # Deduct AP
			if dragged_card.is_emperor_card: 
				player1_emperor_on_board = true
				card_manager.emperor_position[0] = target_slot
			print("	 Player 1 AP remaining: {ap}. Emperor on board: {emp_flag}".format({
				"ap": player1_current_ap, "emp_flag": player1_emperor_on_board
				}))
		else: 
			player2_current_ap -= card_ap_cost # Deduct AP
			if dragged_card.is_emperor_card: 
				player2_emperor_on_board = true
				card_manager.emperor_position[1] = target_slot
			print("	 Player 2 AP remaining: {ap}. Emperor on board: {emp_flag}".format({
				"ap": player2_current_ap, "emp_flag": player2_emperor_on_board
				}))
		
		# 1. Get references to subsystems
		var movement_system = card_manager.get_node("CardMovementSystem")

		# 2. Update the Hand Domain: Tell the hand to remove the card.
		active_hand_ref.remove_card_from_hand(dragged_card)

		# 3. Update the Board Domain: Tell the movement system to place the card.
		movement_system.place_card_in_slot(dragged_card, target_slot)

		# 4. Update the Card's State Domain: Tell the card to transition its state, providing context.
		dragged_card.state_machine.transition_to(dragged_card.state_machine.State.ON_BOARD_ENTER, GameConstants.TriggerSource.PLAYER_CHOICE )

		# 5. Final housekeeping
		_connect_card_signals(dragged_card)
		card_manager.reset_all_slot_overlays()
		
	_update_turn_info_display()
	_update_ui_for_turn_state()

func _handle_unit_death(card_that_has_died: BaseCard):
	if not is_instance_valid(card_that_has_died):
		print("BattleManager._handle_unit_death: Card instance '{name}' is already invalid. Cannot reliably clean up slot state without prior info.".format({"name": str(card_that_has_died.name) if card_that_has_died else "Unknown"}))
		card_manager.board_state.precompute_all_movement_maps() # Still update maps generally
		return

	print("BattleManager: Handling game state cleanup for '{name}' which has self-destructed or been confirmed dead.".format({"name": card_that_has_died.name}))

	var last_known_slot: Node2D = card_that_has_died.card_is_in_slot

	if is_instance_valid(last_known_slot):
		print("	 Clearing slot: ", last_known_slot.name)
		last_known_slot.is_occupied = false
		last_known_slot.card_in_slot = null
		# card_that_has_died.card_is_in_slot = null # Card will be freed by itself.
	else:
		print("	 Warning: Card '{name}' that died was not registered in a slot, or slot info lost.".format({"name": card_that_has_died.name}))
	# Add to graveyard data
	# ...
	# Update movement maps because an obstacle was removed
	card_manager.board_state.precompute_all_movement_maps()

	# Check for game over if an emperor died (this specific card)
	if card_that_has_died.is_emperor_card:
		print("	 An emperor ('{name}') has died! Global game over check will verify.".format({"name": card_that_has_died.name}))

func check_for_game_over():
	# Example: Check if either player's emperor is dead
	var p1_emperor_dead = true # Assume dead until found alive
	var p2_emperor_dead = true

	for card_node_any in get_tree().get_nodes_in_group("AllCards"):
		if not card_node_any is BaseCard: continue
		var card: BaseCard = card_node_any as BaseCard
		if card.is_emperor_card and card.current_health > 0:
			if card.is_player_card:
				p1_emperor_dead = false
			else: # Enemy card
				p2_emperor_dead = false
	
	if p1_emperor_dead:
		print("GAME OVER! Player 2 Wins! (Player 1 Emperor defeated)")
		# emit_signal("game_over", 2)
		# TODO: Transition to game over screen/state
		#get_tree().quit() # Simple end for now
	elif p2_emperor_dead:
		print("GAME OVER! Player 1 Wins! (Player 2 Emperor defeated)")
		# emit_signal("game_over", 1)
		#get_tree().quit()
		
func _handle_placement_choice_made(is_face_up: bool, outcome_dict: Dictionary):
	print("BattleManager: _handle_placement_choice_made called with: ", is_face_up)
	outcome_dict.chosen_face_up = is_face_up

func _handle_placement_cancelled(outcome_dict: Dictionary):
	print("BattleManager: _handle_placement_cancelled called")
	outcome_dict.was_cancelled = true
	
func _update_turn_info_display():
	if not is_instance_valid(turn_info_display_label):
		# printerr("BattleManager: turn_info_display_label is not valid.")
		return
	turn_info_display_label.text = ""
	var turn_text: String = "TURN : " + str(game_round)
	
	var current_player_string: String
	if current_player_id == 1:
		current_player_string = "Current Turn: You"
	elif current_player_id == 2:
		current_player_string = "Current Turn: Opponent"
	else:
		current_player_string = "Current Turn: -" # Should not happen during active play

	var ap_string: String
	if current_player_id == 1:
		ap_string = "AP: " + str(player1_current_ap) + "/" + str(player1_max_ap)
	elif current_player_id == 2:
		ap_string = "AP: " + str(player2_current_ap) + "/" + str(player2_max_ap)
	else:
		ap_string = "AP: -/-"

	# Using RichTextLabel's bbcode for newlines
	turn_info_display_label.append_text(turn_text + "\n")
	turn_info_display_label.append_text(current_player_string + "\n")
	turn_info_display_label.append_text(ap_string)

	# If you are not using bbcode for font size, you can just set the text directly:
	# turn_info_display_label.text = turn_text + "\n" + current_player_string + "\n" + ap_string
