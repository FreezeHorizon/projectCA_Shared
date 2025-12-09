extends Node
signal state_changed(from_state, to_state)

# Enum for all possible card states
enum State {
	MULLIGAN,
	IN_HAND,       # Card is in the player's hand
	HOVERING,      # Mouse is hovering over the card
	DRAGGING,      # Card is being dragged
	ON_BOARD_ENTER, # Card Enters the board / summoned
	ON_BOARD_IDLE,  # Card is idle on board
	SELECTED,       # Card is selected on the board
	MOVING,        # After selecting an Empty tile or an ally occupied tile 
	#is selected within movement range, move card to said tile on the board
	#if an ally unit occupies such tile swap positions this respects movement range
	ATTACKING,      # In attacking state
	DEATH,          # When card hp reaches 0
	DAMAGED,        # When card receives damage
	RETALIATE,      # When Card is attacked
}

# Current state of the card
var current_state: State = State.IN_HAND
var event_context: Dictionary = {}
# Reference to the card this state machine is managing
var card: Node2D
var card_manager_reference: Node2D

# Configuration for state-specific behaviors
var state_config = {
	State.MULLIGAN: {
		"scale": Vector2(1, 1), # make cards look bigger
		"z_index": 10,
		"can_drag": false
	},
	State.IN_HAND: {
		"scale": Vector2(0.5, 0.5),
		"z_index": 2,
		"can_drag": true
	},
	State.HOVERING: {
		"scale": Vector2(0.52, 0.52),
		"z_index": 3,
		#"y_offset": +50 #handled now by PlayerHand
	},
	State.DRAGGING: {
		"scale": Vector2(0.52, 0.52),
		"z_index": 5
	},
	State.ON_BOARD_ENTER: {
		"scale": Vector2(0.5, 0.5),
		"z_index": 1,
		"can_drag": false
	},
	State.ON_BOARD_IDLE: {
		"scale": Vector2(0.5, 0.5),
		"z_index": 1,
		"can_drag": false
	},
	State.SELECTED: {
		"scale": Vector2(0.5, 0.5),
		"z_index": 4,
		"y_offset": Vector2(0,15)
	},
	State.MOVING: {
		"scale": Vector2(0.5, 0.5),
		"z_index": 3
	},
	State.ATTACKING: {
		"scale": Vector2(0.5, 0.5),
		"z_index": 3
	},
	State.DAMAGED: {
		"scale": Vector2(0.5, 0.5),
		"z_index": 2
	},
	State.RETALIATE: {
		"scale": Vector2(0.5, 0.5),
		"z_index": 2
	},
	State.DEATH: {
		"scale": Vector2(0.5, 0.5),
		"z_index": 2
	},
}


func _ready():
	# Ensure we have a reference to the card
	card = get_parent()
	# Get a reference to the CardManager using relative path
	if is_instance_valid(card) and card.has_node("../../CardManager"): # Check if path is valid from current parent
		card_manager_reference = card.get_node("../../CardManager")
	else:
		# Attempt to get it via a more global path if card might be elsewhere initially
		# This assumes 'Main' is the root scene node containing 'CardManager'
		var main_node = get_tree().root.get_node_or_null("Main")
		if is_instance_valid(main_node) and main_node.has_node("CardManager"):
			card_manager_reference = main_node.get_node("CardManager")
		# else:
			# print("CardStateMachine on '", card.name, "': Could not reliably find CardManager.")

func _is_server() -> bool:
	return OS.has_feature("server")

# Transition between states with validation and side effects
func transition_to(new_state: State, context: Dictionary = {}) -> bool:
	var old_state = current_state
	if new_state == old_state: 
		return true 
	
	# Fix 2: Store the incoming context so state functions like _start_moving can read it
	self.event_context = context

	if _is_valid_transition(current_state, new_state):
		_exit_state(current_state)
		_enter_state(new_state)
		current_state = new_state
		emit_signal("state_changed", old_state, current_state)
		return true
	else:
		# Fix 3: Clear the context if the transition failed
		self.event_context = {}
		print("CardStateMachine: INVALID transition attempted on '", card.name, "' from ", State.keys()[old_state], " to ", State.keys()[new_state])
		return false

# Check if the transition is valid
@warning_ignore("unused_parameter")
func _is_valid_transition(from_state: State, to_state: State) -> bool:
	match from_state:
		State.MULLIGAN:
			# Cards in mulligan shouldn't transition to hovering state
			return to_state == State.IN_HAND  # Only allow transition to IN_HAND when mulligan is over
		State.IN_HAND:
			# When in hand, don't allow hovering if in mulligan phase or if a card is being dragged
			if card_manager_reference and card_manager_reference.get_parent().get_node_or_null("MulliganManager").mull_phase:
				return to_state == State.MULLIGAN
			# Check if any card is being dragged
			if to_state == State.HOVERING and card_manager_reference and card_manager_reference.card_being_dragged:
				return false
			return to_state == State.HOVERING or \
					to_state == State.DRAGGING or \
					to_state == State.ON_BOARD_ENTER or \
					to_state == State.MULLIGAN
		State.HOVERING:
			# Check for mulligan phase when trying to exit hover state
			if card_manager_reference and card_manager_reference.get_parent().get_node_or_null("MulliganManager").mull_phase:
				return to_state == State.IN_HAND  # Only allow returning to hand during mulligan
			return to_state == State.IN_HAND or to_state == State.DRAGGING
		State.DRAGGING:
			return to_state == State.IN_HAND or to_state == State.ON_BOARD_ENTER
		State.ON_BOARD_ENTER:
			return to_state == State.ON_BOARD_IDLE or \
					to_state == State.RETALIATE
		State.ON_BOARD_IDLE:
			return to_state == State.SELECTED or \
					to_state == State.ATTACKING or \
					to_state == State.DAMAGED or \
					to_state == State.DEATH or \
					to_state == State.RETALIATE
		State.SELECTED:
			return to_state == State.ON_BOARD_IDLE or \
					to_state == State.MOVING or \
					to_state == State.ATTACKING or \
					to_state == State.DAMAGED or \
					to_state == State.RETALIATE
		State.MOVING:
			return to_state == State.ON_BOARD_IDLE or to_state == State.DAMAGED
		State.ATTACKING:
			return to_state == State.ON_BOARD_IDLE or \
				   to_state == State.DAMAGED or \
				   to_state == State.DEATH
		State.DAMAGED:
			return to_state == State.ON_BOARD_IDLE or to_state == State.DEATH or \
				   to_state == State.RETALIATE 
		State.RETALIATE:
			return to_state == State.ON_BOARD_IDLE or \
				   to_state == State.DAMAGED or \
				
				   to_state == State.DEATH
		State.DEATH:
			return false  # Death is a final state
	return false

# Handle exiting a state
func _exit_state(state: State) -> void:
	match state:
		State.HOVERING:
			print("HOVER OFF")
			_reset_hover_state()
		State.DRAGGING:
			print("FINISH DRAG")
			_finish_drag()
		State.SELECTED:
			print("EXIT SELECTION")
			_deselect_on_board()

# Handle entering a new state
func _enter_state(state: State) -> void:
	#print("CardStateMachine: ", card.name, " entering state ", state, " | Setting z_index to: ", state_config[state]["z_index"])
	card.z_index = state_config[state]["z_index"]
	match state:
		State.MULLIGAN:
			print("CardStateMachine: ", card.name, " entering MULLIGAN. Target scale: ", state_config[State.MULLIGAN]["scale"])
			card.scale = state_config[State.MULLIGAN]["scale"] 
			card.z_index = state_config[State.MULLIGAN]["z_index"]
		State.IN_HAND:
			print("CardStateMachine: ", card.name, " entering IN_HAND. Current scale: ", card.scale, " Target scale from config: ", state_config[State.IN_HAND]["scale"])
			card.scale = state_config[State.IN_HAND]["scale"]
			card.z_index = state_config[State.IN_HAND]["z_index"]
			var area_2d_shape = card.get_node_or_null("Area2D/CollisionShape2D")
			if is_instance_valid(area_2d_shape):
				area_2d_shape.disabled = false
		State.DRAGGING:
			print("Dragging")
			_start_drag()
		State.ON_BOARD_ENTER:
			print("CardState: ",card.name, " On_board_enter")
			_place_on_board()
		State.ON_BOARD_IDLE:
			print("CardState: ",card.name, " On_board_idle")
			_idle_on_board()
		State.SELECTED:
			print("CardState: ",card.name, " Selected")
			_select_on_board()
		State.HOVERING:
			print("Hovering")
			_start_hover()
		State.MOVING:
			print("CardState: ",card.name, " Moving")
			_start_moving()
		State.ATTACKING:
			print("CardState: ",card.name," Attacking")
			_start_attacking()
		State.DAMAGED:
			print("CardState: ",card.name, " Damaged")
			_take_damage()
		State.RETALIATE:
			print("CardState: ",card.name, " Retaliate")
			_start_retaliate()
		State.DEATH:
			print("CardState: ",card.name, " Death")
			_start_death()

# State-specific action methods
func _start_drag() -> void:
	if _is_server(): return
	card.scale = state_config[State.DRAGGING]["scale"]
	card.z_index = state_config[State.DRAGGING]["z_index"]
	card.get_node("Highlight").visible = true

func _finish_drag() -> void:
	if _is_server(): return
	# Reset any drag-specific configurations
	card.get_node("Highlight").visible = false
	pass

func _place_on_board() -> void:
	if not _is_server():
		# Disable collision for hand-related interactions
		if card.get_node_or_null("Area2D/CollisionShape2D"):
			card.get_node("Area2D/CollisionShape2D").set_deferred("disabled", true)
		
		# Hide UI elements
		var ap_cost = card.get_node_or_null("ApCostImage")
		if ap_cost: ap_cost.visible = false
		var type_img = card.get_node_or_null("TypeImage")
		if type_img: type_img.visible = false
		
		# Set scale/z_index
		card.scale = state_config[State.ON_BOARD_ENTER]["scale"]
		card.z_index = state_config[State.ON_BOARD_ENTER]["z_index"]
		
		# Enable collision after animation
		call_deferred("_enable_board_collision")
	var trigger_source = event_context.get("trigger_source", GameConstants.TriggerSource.PLAYER_CHOICE)
	card.use_action(card.ActionType.ENTER,trigger_source)

func _enable_board_collision() -> void:
	if not _is_server():
	# Re-enable collision for board interactions
		if card.get_node_or_null("Area2D/CollisionShape2D"):
			card.get_node("Area2D/CollisionShape2D").disabled = false

func _idle_on_board() -> void:
	if not _is_server():
		card.scale = state_config[State.ON_BOARD_IDLE]["scale"]
		card.z_index = state_config[State.ON_BOARD_IDLE]["z_index"]

func _start_hover() -> void:
	if not _is_server():
		card.scale = state_config[State.HOVERING]["scale"]
		card.z_index = state_config[State.HOVERING]["z_index"]
		card.get_node("Highlight").visible = true

func _reset_hover_state() -> void:
	if not _is_server():
		card.scale = state_config[State.IN_HAND]["scale"]
		card.z_index = state_config[State.IN_HAND]["z_index"]
		card.get_node("Highlight").visible = false

func _select_on_board() -> void:
	if not _is_server():
		card.get_node("CardImage").position -= state_config[State.SELECTED]["y_offset"]
		card.get_node("CardBackImage").position -= state_config[State.SELECTED]["y_offset"]
		card.get_node("CardOutline").scale -= Vector2(0.05,0.05)
		card.get_node("CardOutline").position += Vector2(0,6)
		card.get_node("Selected").play("Selected")
		card.scale = state_config[State.SELECTED]["scale"]
		card.z_index = state_config[State.SELECTED]["z_index"]

func _deselect_on_board() -> void:
	if not _is_server():
		card.get_node("Selected").stop()
		card.get_node("CardBackImage").position += state_config[State.SELECTED]["y_offset"]
		card.get_node("CardImage").position += state_config[State.SELECTED]["y_offset"]
		card.get_node("CardOutline").scale += Vector2(0.05,0.05)
		card.get_node("CardOutline").position -= Vector2(0,6)  
		card.scale = state_config[State.ON_BOARD_IDLE]["scale"]
		card.z_index = state_config[State.ON_BOARD_IDLE]["z_index"]

func _start_moving() -> void:
	if not _is_server():
		card.scale = state_config[State.MOVING]["scale"]
		card.z_index = state_config[State.MOVING]["z_index"]
	var trigger_source = event_context.get("trigger_source", GameConstants.TriggerSource.PLAYER_CHOICE)
	card.use_action(card.ActionType.MOVE, trigger_source)

func _start_attacking() -> void:
	# Visuals
	if not _is_server():
		card.scale = state_config[State.ATTACKING]["scale"]
		card.z_index = state_config[State.ATTACKING]["z_index"]
		var selected = card.get_node_or_null("Selected")
		if selected: selected.stop() # Use get_node_or_null to be safe
	
	# Logic
	var trigger_source = event_context.get("trigger_source", GameConstants.TriggerSource.PLAYER_CHOICE)
	card.use_action(card.ActionType.ATTACK, trigger_source)

func _take_damage() -> void:
	if not _is_server():
		card.scale = state_config[State.DAMAGED]["scale"]
		card.z_index = state_config[State.DAMAGED]["z_index"]
		# Damage animation would be handled here
		card._update_health_visual()
	
func _start_retaliate() -> void:
	if not _is_server():
		card.scale = state_config[State.RETALIATE]["scale"]
		card.z_index = state_config[State.RETALIATE]["z_index"]
		# Retaliation animation would be handled here
		card._update_health_visual()
func _start_death() -> void:
	if not _is_server():
		card.scale = state_config[State.DEATH]["scale"]
		card.z_index = state_config[State.DEATH]["z_index"]
		# Death animation would be handled here

# Public methods for external state management
func can_drag() -> bool:
	return state_config.get(current_state, {}).get("can_drag", true)

func get_current_state() -> State:
	return current_state
