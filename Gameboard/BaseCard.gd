@abstract
class_name BaseCard
extends Node2D

# --- Signals ---
signal card_flipped(card_instance: BaseCard, is_now_face_up: bool)
signal health_changed(new_health: int, old_health: int, card_instance: BaseCard)
signal died(card_instance: BaseCard) # This signal means "I have completed my death process and am being removed"


@onready var animation_player: AnimationPlayer = $AnimationPlayer

# --- Properties (Initialized by initialize_card_from_database) ---
var card_name: String = "Unknown"    # User-facing name, or the db_key
var db_key: String = ""              # The key from CardDatabase (e.g., "Bilwis")

var base_attack: int = 0
var base_health: int = 1
var base_cost: int = 0
var base_move_range: int = 1
var base_attack_range: int = 1

var current_attack: int
var current_health: int
var current_cost: int
var current_move_range: int
var current_attack_range: int

var card_type_enum: GameConstants.CardType # MODIFIED: Use specific enum type
var faction_enum: GameConstants.Faction   # MODIFIED: Use specific enum type

var atlas_path_info: String = ""
var atlas_region_info: Array = [] # [x, y, w, h]

# --- Internal State Variables ---
var can_retaliate: bool = true # Default: most units can retaliate
var card_is_in_slot: Node2D = null # Reference to the CardSlot node if on board
var is_emperor_card: bool = false
var is_player_card: bool = true #
var is_entering_board_face_down: bool = false
# NEW Action Economy
var has_move_action_available: bool = true
var has_attack_action_available: bool = true
var has_flip_action_available: bool = true
# 'performed_action_type' might become less central, or track the *last* major board action.
# Let's keep it for now as it can inform visuals or other logic.
enum ActionType { NONE, ENTER, MOVE, ATTACK, FLIP, SPELL_CAST }

var performed_action_type: ActionType = ActionType.NONE # Tracks the last major action

# --- Node References ---
# State machine is fundamental. Path must be correct in Card.tscn & EnemyCard.tscn
@onready var state_machine: Node = $CardStateMachine 
var _is_face_down: bool = false
@export var is_face_down: bool:
	get: return _is_face_down
	set(value):
		if _is_face_down == value: return
		var old_face_down_state = _is_face_down 
		_is_face_down = value
		print(name, " property is_face_down set to: ", _is_face_down, " by setter.")
		
		if is_inside_tree(): 
			_update_visual_state()

			if is_instance_valid(card_is_in_slot) and not old_face_down_state and _is_face_down:
				print(name, ": Was face-up on board, now flipped face-down. Resetting stats.")
				reset_dynamic_stats_to_base()
				has_attack_action_available = false 
			elif old_face_down_state and not _is_face_down:
				print(name, ": Flipped face-up.")
				if not has_attack_action_available: 
					has_attack_action_available = true 
					print(name, ": Now face-up, attack action is potentially available.")
			
			# It signals that this specific card instance has flipped, and what its new state is.
			emit_signal("card_flipped", self, not _is_face_down)


#-----------------------------------------------------------------------------
# LIFECYCLE METHODS
#-----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("AllCards") 
	if not has_meta("original_y"):
		set_meta("original_y", position.y)
	_update_visual_state()

#-----------------------------------------------------------------------------
# PUBLIC METHODS - DATA & STATE MANAGEMENT
#-----------------------------------------------------------------------------
func initialize_card_from_database(database_key: String, card_data_dict: Dictionary) -> void:
	self.db_key = database_key
	self.card_name = card_data_dict.get("displayName", database_key) 
	
	base_attack = card_data_dict.get("attack", 0)
	base_health = card_data_dict.get("health", 1)
	if base_health <= 0: base_health = 1 
	base_cost = card_data_dict.get("apCost", 0) 
	base_move_range = card_data_dict.get("moveRange", 1)
	base_attack_range = card_data_dict.get("attackRange", 1)
	can_retaliate = card_data_dict.get("canRetaliate", true) # Get from data if specified, else default
	card_type_enum = card_data_dict.get("type", GameConstants.CardType.HERO) # MODIFIED with default
	faction_enum = card_data_dict.get("faction", GameConstants.Faction.NEUTRAL) # MODIFIED with default
	atlas_path_info = card_data_dict.get("atlasPath", "") 
	atlas_region_info = card_data_dict.get("atlasRegion", [])

	is_emperor_card = (card_type_enum == GameConstants.CardType.EMPEROR)
	is_face_down = false
	is_entering_board_face_down = false
	reset_dynamic_stats_to_base()
	_update_visuals_from_data()

func reset_dynamic_stats_to_base() -> void:
	current_attack = base_attack
	current_health = base_health
	current_cost = base_cost
	current_move_range = base_move_range
	current_attack_range = base_attack_range
	# print(name, " (", db_key, ") stats reset. HP: ", current_health, "/", base_health) # Less verbose for now
	_update_health_visual()

func get_database_key() -> String:
	return db_key

func get_current_card_data_dict() -> Dictionary:
	# Consolidate has_action_available into more specific checks if it's not used elsewhere
	var general_action_available = has_move_action_available or has_attack_action_available
	return {
		"db_key": db_key, "name": card_name,
		"base_attack": base_attack, "current_attack": current_attack,
		"base_health": base_health, "current_health": current_health,
		"base_cost": base_cost, "current_cost": current_cost,
		"type": card_type_enum, "faction": faction_enum,
		"base_move_range": base_move_range, "current_move_range": current_move_range,
		"base_attack_range": base_attack_range, "current_attack_range": current_attack_range,
		"can_retaliate": can_retaliate,
		"is_emperor": is_emperor_card, "is_player_card": is_player_card,
		"has_action_available": general_action_available, # General status
		"can_move": has_move_action_available,        # Specific status
		"can_attack": has_attack_action_available     # Specific status
	}

func set_as_emperor(is_emp: bool = true) -> void:
	is_emperor_card = is_emp

func set_owner_is_player(is_player: bool) -> void:
	is_player_card = is_player

func use_action(action: ActionType, trigger_source: GameConstants.TriggerSource):
	# Actions triggered by effects should not consume the card's own turn budget.
	if trigger_source != GameConstants.TriggerSource.PLAYER_CHOICE:
		print(name, ": Action '{action_name}' triggered by an effect, not consuming player action budget.".format({"action_name": ActionType.keys()[action]}))
		return

	# If we get here, it was a PLAYER_CHOICE. Consume the action budget.
	print(name, ": Consuming action '{action_name}' due to PLAYER_CHOICE.".format({"action_name": ActionType.keys()[action]}))
	performed_action_type = action
	
	match action:
		ActionType.ENTER:
			# Placing a card consumes all its potential actions for that turn.
			has_move_action_available = false
			has_attack_action_available = false
			has_flip_action_available = false
		
		ActionType.MOVE:
			has_move_action_available = false
		
		ActionType.FLIP:
			has_flip_action_available = false

		ActionType.ATTACK:
			# Attacking is the ultimate commitment and consumes all remaining action potential.
			has_attack_action_available = false
			has_move_action_available = false
			has_flip_action_available = false

	# After any action, apply the visual cue if all actions are now used up.
	if not has_move_action_available and not has_attack_action_available and not has_flip_action_available:
		_apply_action_used_visuals()

func flip_card(face_up: bool, trigger_source: GameConstants.TriggerSource):
	var was_face_down = is_face_down
	var new_is_face_down = not face_up

	if is_face_down == new_is_face_down:
		return

	print(name, ": Flipping card. Triggered by: ", GameConstants.TriggerSource.keys()[trigger_source])
	
	# --- Handle Effect Triggers FIRST ---
	# This logic must happen BEFORE the state changes, while we still know it "was" face-down.
	if was_face_down and face_up: # It was face-down and is being flipped UP
		match trigger_source:
			GameConstants.TriggerSource.PLAYER_CHOICE:
				print(name, ": 'On-Faceup' effects WILL trigger.")
				# _trigger_on_faceup_effect()
			GameConstants.TriggerSource.COMBAT_REVEAL: 
				print(name, ": 'On-Faceup' effects DO NOT trigger.")
			GameConstants.TriggerSource.EFFECT_ALLY:
				print(name, ": 'EFFECT_ALLY' effects trigger.")
			GameConstants.TriggerSource.EFFECT_ENEMY: 
				print(name, ": 'EFFECT_ENEMY' effects trigger.")
			GameConstants.TriggerSource.GAME_RULE: 
				print(name, ": 'GAME_RULE' effects trigger.")
			_: #Default fall back
				print(name, ": 'On-Faceup' effects DO NOT trigger.")
	# --- Handle Action Consumption ---
	if trigger_source == GameConstants.TriggerSource.PLAYER_CHOICE:
		use_action(ActionType.FLIP, GameConstants.TriggerSource.PLAYER_CHOICE)

	# --- INITIATE THE STATE CHANGE ---
	# This call will trigger the setter logic above, which handles stat resets,
	# visual updates, and EMITTING THE 'card_flipped' SIGNAL.
	is_face_down = new_is_face_down

func reset_action() -> void:
	performed_action_type = ActionType.NONE
	_reset_action_visuals() # Reset greyed-out visual

	# Grant the full action budget first.
	has_move_action_available = true
	has_attack_action_available = true
	has_flip_action_available = true

	# Now, apply restrictions based on the card's state at the start of the turn.
	if is_face_down:
		# A card starting its turn face-down cannot use its attack action.
		has_attack_action_available = false
	
	print(name, " actions reset. Move:", has_move_action_available, "Attack:", has_attack_action_available, "Flip:", has_flip_action_available)

	if card_is_in_slot and state_machine and is_instance_valid(state_machine):
		if state_machine.get_current_state() != state_machine.State.ON_BOARD_IDLE:
			state_machine.transition_to(state_machine.State.ON_BOARD_IDLE, GameConstants.TriggerSource.GAME_RULE)


func can_perform_action(action_to_check: ActionType) -> bool:
	match action_to_check:
		ActionType.ENTER:
			# ENTER action is typically only valid when placing from hand.
			# Once on board, a card cannot "re-enter" in the same way.
			return card_is_in_slot == null # True if not on board yet
		ActionType.MOVE:
			return has_move_action_available and card_is_in_slot != null
		ActionType.ATTACK:
			# Cannot attack if face-down
			if is_face_down:
				return false
			return has_attack_action_available and card_is_in_slot != null
		ActionType.SPELL_CAST:
			# Add specific spell logic here when spells are implemented
			return true # Placeholder
	return false # Default for NONE or unhandled

func set_can_retaliate(can_it: bool) -> void:
	can_retaliate = can_it

func has_any_board_action_available() -> bool:
	return (has_move_action_available or has_attack_action_available) and card_is_in_slot != null

func take_damage(amount: int) -> void: # No longer returns a boolean for this approach
	if amount <= 0 or current_health <= 0: return

	var previous_health = current_health
	current_health = max(0, current_health - amount)
	
	print(name, " (", db_key, ") took ", amount, " damage. Health: ", current_health, "/", base_health)
	emit_signal("health_changed", current_health, previous_health, self)
	
	_update_health_visual() 
	
	if current_health <= 0:
		_die() 
	elif state_machine and is_instance_valid(state_machine):
		state_machine.transition_to(state_machine.State.DAMAGED)

func heal(amount: int) -> void:
	if amount <= 0 or current_health <= 0 or current_health == base_health: return

	var previous_health = current_health
	current_health = min(base_health, current_health + amount)
	
	print(name, " (", db_key, ") healed ", amount, ". Health: ", current_health, "/", base_health)
	emit_signal("health_changed", current_health, previous_health, self)
	_update_health_visual()

func _die() -> void: # This is the base implementation, can be overridden
	print(name, " (", db_key, ") is initiating its death sequence (_die called). Current health: ", current_health)

	if state_machine and is_instance_valid(state_machine):
		state_machine.transition_to(state_machine.State.DEATH)

	print(name, " (", db_key, ") has completed its death effects/animations and is emitting 'died' signal.")
	self.emit_signal("died") # Signal that standard death processing by managers can occur

	print(name, " (", db_key, ") is now queueing itself for deletion.")
	queue_free() # Card removes itself from the scene tree



# --- VIRTUAL METHODS - To be overridden in Card.gd/EnemyCard.gd ---
func _update_visuals_from_data() -> void:
	# This is a VIRTUAL method, subclasses (Card.gd, EnemyCard.gd) implement it.
	# They should also call _update_visual_state() within their implementation
	# OR this base method can call it if there are base visuals to update regardless of face state.
	# For now, let's assume subclasses will handle it.
	# print(name, ": BaseCard _update_visuals_from_data called.")
	_update_visual_state() # Call it here to ensure it's always considered
	pass 

func _update_health_visual() -> void:
	pass 

func _update_visual_state() -> void:
	# This method will be overridden in Card.gd / EnemyCard.gd
	# to toggle visibility of CardImage vs CardBackImage.
	# print(name, ": BaseCard updating face down visual state. Is face down: ", is_face_down)
	pass

func _apply_action_used_visuals() -> void:
	var card_image = get_node_or_null("CardImage")
	var card_back = get_node_or_null("CardBackImage")
	if is_face_down and is_entering_board_face_down:
		# For face-down cards, we generally don't want them to gray out
		# just because they moved, as "flipping" is still a potential action.
		# We might revisit this if "flipping" becomes a tracked action that can be exhausted.
		# For now, keep the card back normal unless a more complex state dictates otherwise.
		if is_instance_valid(card_back):
			card_back.self_modulate = Color("656565") # Ensure it's not grayed
		if is_instance_valid(card_image): # Should be invisible anyway if face_down
			card_image.self_modulate = Color("656565")
	else: # Card is face-up
		if is_instance_valid(card_image):
			card_image.self_modulate = Color("656565")
		if is_instance_valid(card_back): # Should be invisible
			card_back.self_modulate = Color("656565")
	pass 

func _reset_action_visuals() -> void:
	var card_image = get_node_or_null("CardImage")
	var card_back = get_node_or_null("CardBackImage")
	if is_instance_valid(card_image): # Ensure node exists
		card_image.self_modulate = Color.WHITE
	if is_instance_valid(card_back):
		card_back.self_modulate = Color.WHITE
	pass

func setup_for_mulligan_display() -> void:
	if state_machine and state_machine.get_current_state() != state_machine.State.MULLIGAN:
		# print("BaseCard '", name, "': Transitioning to MULLIGAN state via setup_for_mulligan_display.")
		state_machine.transition_to(state_machine.State.MULLIGAN, GameConstants.TriggerSource.PLAYER_CHOICE)
