class_name Card extends BaseCard # Inherits from BaseCard

signal hovered(card_instance: Card) 
signal hovered_off(card_instance: Card)

#signal card_selected(card_instance: Card) # This card was selected on board


#-----------------------------------------------------------------------------
# LIFECYCLE METHODS
#-----------------------------------------------------------------------------
func _ready() -> void:
	super._ready() # CORRECTED: Call super for _ready (usually works like this or with ())
	if material:
		material = material.duplicate()
	self.is_player_card = true 
	self.scale = Vector2(0.5, 0.5)
	self.position = Vector2(1110.0, 631.0)
	if scale == Vector2.ONE: 
		scale = Vector2(0.5, 0.5) 
	
	var area_2d = get_node_or_null("Area2D")
	if is_instance_valid(area_2d):
		if not area_2d.mouse_entered.is_connected(_on_area_2d_mouse_entered):
			area_2d.mouse_entered.connect(_on_area_2d_mouse_entered)
		if not area_2d.mouse_exited.is_connected(_on_area_2d_mouse_exited):
			area_2d.mouse_exited.connect(_on_area_2d_mouse_exited)
	else:
		printerr("Card '", name, "': Area2D node not found for input signals.")
	add_to_group("PlayerCards")

#func _process(_delta: float) -> void: #for debugging purposes
	#if self.is_emperor_card:
		#print(self.position)
		#print((randi()%2)+1) 
#-----------------------------------------------------------------------------
# VISUAL UPDATE IMPLEMENTATIONS (Overrides from BaseCard)
#-----------------------------------------------------------------------------

func _update_visual_state() -> void:
	if not is_instance_valid(card_is_in_slot):
	# --- PLAYER HAND LOGIC (Face Up) ---
		if get_node_or_null("CardImage"): get_node("CardImage").visible = true
		if get_node_or_null("CardBackImage"): get_node("CardBackImage").visible = false
		if get_node_or_null("ApCostImage"): get_node("ApCostImage").visible = true
		if get_node_or_null("TypeImage"): get_node("TypeImage").visible = true
		return # Exit, don't run board logic

	# --- BOARD LOGIC (Run Base) ---
	super._update_visual_state()

#-----------------------------------------------------------------------------
# INPUT HANDLERS (Specific to Player Card)
#-----------------------------------------------------------------------------
func _on_area_2d_mouse_entered() -> void:
	var mulligan_manager = get_node_or_null("../../MulliganManager") # Path might need adjustment from Main
	var in_mulligan_phase = is_instance_valid(mulligan_manager) and mulligan_manager.mull_phase
	
	if not card_is_in_slot and not in_mulligan_phase and state_machine.get_current_state() == state_machine.State.IN_HAND:
		# This hover logic is now primarily handled by PlayerHand.gd
		# This card can emit a signal, but PlayerHand decides the "true" hover.
		# state_machine.transition_to(state_machine.State.HOVERING) # Let PlayerHand manage this transition
		pass
	
	emit_signal("hovered", self)

func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)
